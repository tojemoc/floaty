#!/usr/bin/env bash
# Download or repack an existing .ipa for SideStore (macOS only: uses codesign).
set -euo pipefail

INPUT="${1:?Usage: $0 <input.ipa or https://...> <output.ipa>}"
OUT_IPA="${2:?}"
mkdir -p "$(dirname "$OUT_IPA")"
OUT_IPA="$(cd "$(dirname "$OUT_IPA")" && pwd)/$(basename "$OUT_IPA")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: codesign requires macOS (use GitHub Actions macos-latest / Blacksmith)" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

if [[ "$INPUT" == http://* || "$INPUT" == https://* ]]; then
  echo "Downloading $INPUT"
  curl -fsSL -o input.ipa "$INPUT"
  INPUT="$WORKDIR/input.ipa"
elif [[ ! -f "$INPUT" ]]; then
  echo "error: input not found: $INPUT" >&2
  exit 1
else
  cp "$INPUT" input.ipa
fi

unzip -q input.ipa

# Normalize layout: SideStore needs Payload/*.app at zip root.
if [[ ! -d Payload ]] || [[ -z "$(find Payload -maxdepth 1 -name '*.app' 2>/dev/null)" ]]; then
  APP="$(find . -type d -name '*.app' ! -path './Payload/*' | head -1)"
  if [[ -z "$APP" ]]; then
    echo "error: no .app bundle found inside IPA" >&2
    exit 1
  fi
  rm -rf Payload
  mkdir -p Payload
  cp -a "$APP" Payload/
fi

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/package-ios-ipa-for-sidestore.sh" "$APP" "$OUT_IPA"
