# Building Plezy for LG webOS

This document covers the toolchain setup, runtime compatibility matrix, vendored dependencies, and packaging steps used to build Plezy (`com.mcphailmonator.plezy`) for LG webOS TVs.

All webOS Flutter plugins (`./webos_plugins/`) and Dart 3.10-adjusted dependencies (`./vendor/`) live directly in the repository, so a clean checkout builds without external sibling repositories.

---

## 1. Runtime Compatibility Matrix

Although current LG TVs boot a 64-bit ARM (`aarch64`) Linux kernel, native webOS applications execute in a **32-bit ARMv7 (`armv7l` / `lib32`) userland** across all models.

Both release `.ipk` files are 32-bit ARMv7 binaries. They differ in the system library ABI they target (`glibc`, `libstdc++`, `wl_webos_shell`, and `libNDL_media`):

| Firmware / Hardware Tier | Release Years | Representative TVs | Package Variant | Runtime Details |
| :--- | :--- | :--- | :--- | :--- |
| **Factory webOS 25 / 26+** | 2025–2026 factory models | OLED C5, G5 | `com.mcphailmonator.plezy_<ver>_arm_webos25-26.ipk` | Native `glibc >= 2.38`, `GLIBCXX_3.4.32`, `wl_webos_shell` v2, and `NDL_MediaInitWithWindowId`. |
| **webOS 24 & Re:New 25/26** | 2022–2024 models (including *Re:New* upgrades) | OLED G4, C4, B4, QNED85T, C2, C3 | `com.mcphailmonator.plezy_<ver>_arm_webos6-24.ipk` | Runs on `glibc 2.35`, `wl_webos_shell` v1, and legacy `NDL_MediaInit`. Uses bundled `libwebos_compat32.so` and `libstdc++.so.6` (`6.0.32`). |
| **webOS 22 / 23** | 2022–2023 models | OLED C2, C3, G2, G3, QNED816RE | `com.mcphailmonator.plezy_<ver>_arm_webos6-24.ipk` | Runs on `glibc 2.31`, `libstdc++.so.6` (`6.0.28`), `/lib/ld-linux.so.3`, and `wl_webos_shell` v1 (lacks `wl_proxy_marshal_flags`). |
| **webOS 6.x** | 2021 models | OLED C1, G1, 75QNED90UPA | `com.mcphailmonator.plezy_<ver>_arm_webos6-24.ipk` | Runs on `glibc 2.28`, `libstdc++.so.6` (`6.0.25`), and older system SQLite. Uses `libwebos_compat32.so`, ELF `GLIBC_2.4` symbol remapping, kernel ABI tag `3.2.0`, NDK `libstdc++.so.6`, and bundled `libsqlite3_dart.so` (`3.50.2`). |

### Summary Guidelines

- **2025+ factory TVs (webOS 25 / 26):** Use `com.mcphailmonator.plezy_<ver>_arm_webos25-26.ipk`.
- **2021–2024 TVs (webOS 6.x–24 and *Re:New* updates to webOS 25/26):** Use `com.mcphailmonator.plezy_<ver>_arm_webos6-24.ipk`.
- Both IPKs use System V `ar` + POSIX `ustar` archives (accurate `Installed-Size`, normalized tar paths, and safe timestamps) compatible with **Homebrew Channel**, **Glasshouse**, **webOS Dev Manager**, and **`ares-install`**.

---

## 2. Toolchain Specifications

Release builds use the following pinned toolchain versions:

- **`flutter-webos` SDK:** [`lg-flutter-webos/flutter-webos`](https://github.com/lg-flutter-webos/flutter-webos) @ `950398131830e9bd5dc91e588c3db8f5c42322be`
  - **Flutter:** `3.38.10` (`c6f67dede3`, `2026-02-10`)
  - **Engine:** `cafcda5721` (`3c25ef829c74f0f39fbb8df093d9a6b9f941ea6b`)
  - **webOS Engine Artifacts:** `c6f67dede3-webos26-2` (`https://github.com/lg-flutter-webos/artifacts/releases/download`)
  - **Dart SDK:** `3.10.9`
- **LG Starfish NDK:** `11.2.0` at `/usr/local/starfish-sdk-x86_64`
  - **Metadata Revision:** `01423828248b75e1f5afe2e5959ccd971df875cd` (`20260623020250`)
  - **Target Sysroot:** `ca9v1-webosmllib32-linux-gnueabi`
  - **Environment Script:** `/usr/local/starfish-sdk-x86_64/environment-setup-ca9v1-webosmllib32-linux-gnueabi`
  - **Build Tools:** `clang 18.1.6`, `cmake 3.28.3`, `pkg-config 0.29.2`
- **Bundled SQLite (`libsqlite3_dart.so`):** `3.50.2` (`sqlite-amalgamation-3500200.zip`, fetched and verified via SHA-256 by `setup-toolchain.sh` / `build_32bit_ipk.sh`)
- **Packaging CLI & Runtime:** `@webos-tools/cli` (`ares`) `3.2.6`, Node.js `v22.22.1`
- **Host Packages:** `patchelf`, `python3`, `binutils` (`ar`, `readelf`), `tar`, `unzip`

### Directory Layout & `scripts/webos/env.sh`

Default workspace layout under `$WORK_DIR` (`~/plezy-webos-workspace`):

```text
~/plezy-webos-workspace/
├── flutter-webos/                  # lg-flutter-webos/flutter-webos checkout (95039813)
├── sqlite-amalgamation-3500200.zip # cached SQLite 3.50.2 source archive
└── plezy/                          # repository checkout
    ├── webos_plugins/              # in-repo webOS Flutter plugins
    ├── vendor/                     # in-repo Dart 3.10-compatible packages
    └── scripts/webos/
        ├── env.sh
        ├── build_32bit_ipk.sh
        ├── ci/
        └── vendor_diffs.patch
```

`scripts/webos/env.sh` exports:

```bash
export WORK_DIR="${WORK_DIR:-$HOME/plezy-webos-workspace}"
export WEBOS_SDK_DIR="${WEBOS_SDK_DIR:-/usr/local/starfish-sdk-x86_64}"
export PATH="$WORK_DIR/flutter-webos/bin:/usr/local/bin:$PATH"
export WEBOS_ENGINE_BASE_URL="https://github.com/lg-flutter-webos/artifacts/releases/download"
export WEBOS_FLUTTER_NDK_ENV="$WEBOS_SDK_DIR/environment-setup-ca9v1-webosmllib32-linux-gnueabi"
```

---

## 3. Vendored Plugins & Packages

`pubspec.yaml` references `./webos_plugins/` and `./vendor/` directly:

1. **`./webos_plugins/`**
   - Based on [`lg-flutter-webos/plugins`](https://github.com/lg-flutter-webos/plugins) (prior to `382f006b04218bca86322ea4b81d94568536bfa6`).
   - **Local patches applied:**
     - `video_player`: Reuses a persistent `_sharedWindowId` (`_Window_Id_1`) across playback sessions in `video_player_webos.dart` to avoid `104 fail to create AVProxy`; calls `Unload()` immediately prior to `PushDispose(50)` in `video_player.cc`; adds a 150 ms cleanup timer in `video_player_plugin.cc`; implements the `selectTrack` method channel handler and `NDL_MediaUnload` guard in `webos_player.cc`.
     - `path_provider` & `package_info_plus`: Null-safety and environment fallback adjustments.
     - Relaxed Dart SDK lower bounds to `>=3.1.0 <4.0.0`.

2. **`./vendor/`** (full patch set recorded in [`scripts/webos/vendor_diffs.patch`](scripts/webos/vendor_diffs.patch))
   - Upstream Plezy targets Dart `3.12+` syntax (such as private named constructor parameters `this._field`), while `flutter-webos` `3.38.10` runs Dart `3.10.9`. The vendored packages adjust SDK constraints and rewrite Dart 3.12-only syntax for Dart 3.10:
   - **`vendor/slang` (`slang`, `slang_flutter`):** [`slang-i18n/slang`](https://github.com/slang-i18n/slang) @ `ca6b49fbcc720c304f9c41af82ec31e64afa46e3`
   - **`vendor/plus_plugins` (`connectivity_plus`):** [`fluttercommunity/plus_plugins`](https://github.com/fluttercommunity/plus_plugins) @ `bf04cdf66598dc3fca274b8b1db2b92b0bf6b73e`
   - **`vendor/media_controls`:** [`edde746/media_controls`](https://github.com/edde746/media_controls) @ `a27208e641790029ac54d825b97508575caee1a7`
   - **`vendor/background_downloader`:** [`edde746/background_downloader`](https://github.com/edde746/background_downloader) @ `ebdf69a7bdd03d410bfdfc700add08eed0de161d`
   - **`vendor/auto_updater`:** [`edde746/auto_updater`](https://github.com/edde746/auto_updater) @ `9e150f71e17495b7361aedbe6df22e89ad52c254`
   - **`vendor/openwatchparty` & `vendor/web_socket`:** `openwatchparty 1.1.0` and `web_socket 1.0.1` from `pub.dev`

---

## 4. Building Release IPKs

From a clean checkout with the toolchain installed:

```bash
# 1. Load environment variables for flutter-webos and Starfish NDK
source scripts/webos/env.sh

# 2. Resolve dependencies and compile the release bundle
flutter-webos pub get
flutter-webos build webos --release

# 3. Package both webos25-26 and webos6-24 IPKs into ./dist/
./scripts/webos/build_32bit_ipk.sh
```

To customize the output folder, pass `OUT_DIR=/custom/path ./scripts/webos/build_32bit_ipk.sh`. Default build artifacts:
- `dist/com.mcphailmonator.plezy_<version>_arm_webos25-26.ipk`
- `dist/com.mcphailmonator.plezy_<version>_arm_webos6-24.ipk`
