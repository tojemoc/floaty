#!/usr/bin/env python3
"""Generate docs/altstore-source.json from GitHub Releases (including pre-releases)."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

TAG_SUFFIX_RE = re.compile(r"-v(?P<version>[\d.]+)-build(?P<build>\d+)$", re.IGNORECASE)
IPA_NAME_RE = re.compile(r"^floaty-(?P<version>[\d.]+)-ios\.ipa$", re.IGNORECASE)


def api_get(url: str, token: str | None) -> object:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode())


def fetch_all_releases(repo: str, token: str | None) -> list[dict]:
    releases: list[dict] = []
    page = 1
    while True:
        url = (
            f"https://api.github.com/repos/{repo}/releases"
            f"?per_page=100&page={page}"
        )
        batch = api_get(url, token)
        if not isinstance(batch, list) or not batch:
            break
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return releases


def parse_tag(tag_name: str) -> tuple[str | None, str | None, str | None]:
    match = TAG_SUFFIX_RE.search(tag_name)
    if not match:
        return None, None, None
    version = match.group("version")
    build = match.group("build")
    flavor = tag_name[: match.start()].strip("-") or "release"
    return flavor, version, build


def iso_date(release: dict) -> str:
    raw = release.get("published_at") or release.get("created_at")
    if not raw:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return raw.replace("+00:00", "Z")


def build_versions(releases: list[dict]) -> list[dict]:
    versions: list[dict] = []
    seen: set[tuple[str, str, str]] = set()

    for release in releases:
        if release.get("draft"):
            continue

        tag = release.get("tag_name") or ""
        flavor, tag_version, tag_build = parse_tag(tag)
        body = (release.get("body") or "").strip()
        date = iso_date(release)

        for asset in release.get("assets") or []:
            name = asset.get("name") or ""
            ipa_match = IPA_NAME_RE.match(name)
            if not ipa_match:
                continue

            version = tag_version or ipa_match.group("version")
            build = tag_build or "0"
            flavor_label = flavor or "unknown"
            key = (flavor_label, version, build)
            if key in seen:
                continue
            seen.add(key)

            description = body.split("\n")[0][:500] if body else None
            if flavor_label and flavor_label != "release":
                prefix = f"[{flavor_label}] "
                description = (
                    f"{prefix}{description}"
                    if description
                    else f"{prefix}Build {build}"
                )

            entry: dict = {
                "version": version,
                "buildVersion": build,
                "marketingVersion": f"{flavor_label} {version} ({build})",
                "date": date,
                "downloadURL": asset["browser_download_url"],
                "size": asset["size"],
            }
            if description:
                entry["localizedDescription"] = description

            versions.append(entry)

    versions.sort(key=lambda v: v["date"], reverse=True)
    return versions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument(
        "--meta",
        default="docs/altstore-source.meta.json",
        help="Static source metadata JSON",
    )
    parser.add_argument(
        "--output",
        default="docs/altstore-source.json",
        help="Generated AltStore source path",
    )
    args = parser.parse_args()

    if not args.repo:
        print("error: --repo or GITHUB_REPOSITORY required", file=sys.stderr)
        return 1

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

    with open(args.meta, encoding="utf-8") as handle:
        meta = json.load(handle)

    app_template = meta.pop("app")
    try:
        releases = fetch_all_releases(args.repo, token)
    except urllib.error.HTTPError as exc:
        print(f"error: GitHub API {exc.code}: {exc.reason}", file=sys.stderr)
        return 1

    versions = build_versions(releases)
    if not versions:
        print("warning: no iOS IPA assets found in releases", file=sys.stderr)

    app = {**app_template, "versions": versions}
    source = {
        **meta,
        "apps": [app],
    }

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(source, handle, indent=2)
        handle.write("\n")

    print(f"Wrote {args.output} with {len(versions)} version(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
