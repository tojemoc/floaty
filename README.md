# Floaty
#### An unofficial Floatplane client for Windows, Linux, MacOS, iOS and Android.
#### ⚠️Spaghetti code
This repository is the tartar sauce spaghetti code of Floaty.

### [Download Here](https://floaty.fyi/download) 

## 📃Feature Matrix
| **Feature**                | **Windows** | **MacOS** | **Linux** | **Android** | **iOS** | **Info**                  |
|----------------------------|-------------|-----------|-----------|-------------|---------|---------------------------|
| **Channel Page**           | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Post Page**              | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Playback**               | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Livestream Page**        | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Livesteam playback**     | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Live Chat**              | ⚠️           | ⚠️         | ⚠️         | ⚠️           | ⚠️       | Awaiting Fix from floatplane.             | 
| **Live Chat Polls**        | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Live Chat Emotes**       | ⚠️           | ⚠️         | ⚠️         | ⚠️           | ⚠️       |                                           |
| **Floatplane Settings**    | ⚠️           | ⚠️         | ⚠️         | ⚠️           | ⚠️       | Some settings are there.                  |
| **Home Page**              | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Whenplane intergration** | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Updater**                | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **PiP**                    | ✅           | ✅         | ✅         | ✅           | ❌       |                                           |
| **Mini Player**            | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Subtitles**              | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Download**               | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |
| **Login**                  | ✅           | ✅         | ✅         | ✅           | ✅       |                                           |                                        |
| **Notifications**          | ❌           | ❌         | ❌         | ❌           | ❌       | Deciding on how to complete this.         |


## 🛠️ How to Compile and Run

### 1. Install Flutter

First, install Flutter by following the official guide:  
➡️ [Flutter Installation Guide](https://docs.flutter.dev/get-started/install)

Make sure to set up your system PATH to include the `flutter/bin` directory.  
Verify installation:
```bash
flutter --version
```

### 2. Clone the repository

```bash
git clone https://github.com/floatyfp/floaty.git
cd floaty
```

### 3. Install dependencies

Some dependencies rely on Rust, install Rust first by following the official guide:  
➡️ [Rust Installation Guide](https://www.rust-lang.org/tools/install)

```bash
flutter pub get
```

### 4. Run the app

Make sure you have an Android/iOS device or a desktop environment ready.

To get a list of available devices and select an option to run on:
```bash
flutter run
```
Or list devices and run on a specific one:
```bash
flutter devices
flutter run -d DEVICE_ID
```

### 5. Build the app
You can build the app in either release or debug mode. If you're building it in release refer to step 6 to setup certificates.

- **Android APK**  
  Build a release APK:
  ```bash
  flutter build apk --<INSERT MODE>
  ```

- **iOS**  
  Build for iOS (requires macOS and Xcode):
  ```bash
  flutter build ios --<INSERT MODE>
  ```

## iOS Over-the-Air (OTA) install for testers

CI builds an IPA on each successful deploy and publishes OTA install files under `docs/` for GitHub Pages. Source templates live in `docs/*.template`; CI generates `manifest.plist` and `index.html` with real release URLs and build numbers (never commit the template placeholders into the served files).

### One-time setup (repo maintainer)

1. Open **Settings → Pages** in this repository.
2. Set **Source** to deploy from the **`release`** branch (or your main deploy branch) using the **`/docs`** folder.
3. After the next CI run that includes an iOS build, the install page is available at:
   `https://<org>.github.io/<repo>/`  
   (for example: `https://tojemoc.github.io/floaty/`)

### Sharing with testers

1. Send testers the GitHub Pages URL above (or the link in the GitHub Release notes).
2. They must open the page in **Safari** on iPhone and tap **Install on iPhone**.
3. Their device **UDID must be registered** in your Apple Developer account (Ad Hoc distribution).
4. After install: **Settings → General → VPN & Device Management** → trust the developer certificate.

The IPA is downloaded from GitHub Releases (HTTPS). The install manifest is served from GitHub Pages. Both URLs must stay on HTTPS.

**Signing:** OTA only works when the IPA is signed with a valid **Ad Hoc** or **Enterprise** profile. The CI job currently packages an unsigned IPA (`flutter build ios --no-codesign`); configure codesigning in the workflow before distributing to testers.

**Expiry:** Ad Hoc provisioning profiles expire after about one year; rebuild and redistribute before expiry.

### SideStore / AltStore source

Host a [source JSON](https://faq.altstore.io/developers/make-a-source) and point each version’s `downloadURL` at an HTTPS `.ipa`. The IPA **must** use standard zip paths (`Payload/YourApp.app/...`). Do not zip with a relative path like `../../Payload` (CI used to do this on Linux); iOS reports that as **NSCocoaErrorDomain 513** (“no permission to download”) when SideStore extracts the archive.

If you already published a broken IPA, repack on a Mac (fixes zip paths and ldid signing):

```bash
mkdir repack && cd repack
unzip -q /path/to/floaty-release-ios.ipa
APP=Payload/Runner.app
rm -rf "$APP/_CodeSignature" "$APP/Frameworks"/*/_CodeSignature
codesign -s - -f "$APP/Frameworks"/*
codesign -s - -f "$APP"
zip -r ../floaty-release-ios-fixed.ipa Payload
```

Without the `codesign` steps, SideStore may fail with `ldid.cpp(1461): _assert(): end >= size - 0x10` when resigning unsigned Flutter frameworks.

Set `size` in the source JSON to the file size in bytes (`stat -f%z floaty-release-ios-fixed.ipa` on macOS). Use the real `bundleIdentifier` (`uk.bw86.floaty`) and match `appPermissions` to the built app.

- **Windows**
  ```bash
  flutter build windows --<INSERT MODE>
  ```

- **macOS**
  ```bash
  flutter build macos --<INSERT MODE>
  ```

- **Linux**
  ```bash
  flutter build linux --<INSERT MODE>
  ```

### 6. (Optional) Setup Release Signing for Android

To publish a signed APK or App Bundle:

1. Generate a signing key:
   ```bash
   keytool -genkey -v -keystore ~/your_keystore_name.jks -keyalg RSA -keysize 2048 -validity 10000 -alias your_key_alias
   ```
2. Create a `key.properties` file in the `android/` directory:
   ```properties
   storePassword=your_store_password
   keyPassword=your_key_password
   keyAlias=your_key_alias
   storeFile=/path/to/your_keystore_name.jks
   ```
3. Edit `android/app/build.gradle` to load the `key.properties` and configure signingConfigs.

Full guide here: [Signing Flutter apps](https://docs.flutter.dev/deployment/android#signing-the-app)
