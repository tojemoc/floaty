# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Floaty is a cross-platform Floatplane client built with **Flutter 3.38.4** and **Dart 3.10.3**. It targets Linux, Windows, macOS, iOS, Android, and Web. In the Cloud Agent VM, only the **Linux desktop** target is buildable and runnable.

### Standard commands

| Task | Command |
|------|---------|
| Install deps | `flutter pub get` |
| Lint / analyze | `flutter analyze` |
| Build (Linux debug) | `flutter build linux --debug` |
| Run built binary | `DISPLAY=:99 ./build/linux/x64/debug/bundle/floaty` |
| Run via Flutter | `DISPLAY=:99 flutter run -d linux` |

There is no `test/` directory — the repo has no automated tests.

### Headless Linux environment caveats

- **Xvfb required**: The Linux GTK app needs an X display. Start one with `Xvfb :99 -screen 0 1280x1024x24 &` and set `DISPLAY=:99`.
- **xdg-user-dirs required**: `path_provider` calls `xdg-user-dir DOCUMENTS` at startup; the package must be installed or the app crashes with `MissingPlatformDirectoryException`.
- **D-Bus warnings are expected**: `connectivity_plus` and `flutter_local_notifications` try to reach `org.freedesktop.NetworkManager` and the session bus, which are absent in a headless VM. These errors are non-blocking — the app still starts and renders.
- **ALSA warnings are expected**: No audio hardware in the VM; audio-related ALSA errors are harmless.
- **Software rendering**: Xvfb uses software rendering; libEGL DRI3 warnings are normal.

### Web target

`flutter build web` currently fails with type errors in the `better_player_plus` dependency override. Use the Linux desktop target for development.

### System dependencies for Linux build

The Flutter Linux build uses clang/LLVM and requires:
- `clang`, `cmake`, `ninja-build`, `pkg-config` (build toolchain)
- `g++-14`, `llvm` (C++ headers and LLVM tools for the native toolchain)
- `libgtk-3-dev`, `libmpv-dev`, `libayatana-appindicator3-dev`, `libasound2-dev` (GTK/media/audio libs)
- `libstdc++-14-dev` (linker needs `libstdc++.so` symlink in the standard lib path)
- `xdg-user-dirs`, `scrot`, `xvfb` (runtime/testing utilities)

A symlink `ln -sf /usr/lib/gcc/x86_64-linux-gnu/14/libstdc++.so /usr/lib/x86_64-linux-gnu/libstdc++.so` may be needed if the linker cannot find `-lstdc++`.
