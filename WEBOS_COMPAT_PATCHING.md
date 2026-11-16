# webOS Compatibility Patching (webOS 6-24 Package)

Background on why the `_arm_webos6-24.ipk` package exists, what `scripts/webos/build_32bit_ipk.sh`
changes, how the missing video function is handled, and the known risks. See `BUILD_WEBOS.md` for
build steps.

Unless stated otherwise, these findings come from static analysis: `readelf` and symbol checks of
the built packages, compared against the webOS firmware library data published by webosbrew
(`common/data/` in [webosbrew/dev-toolbox-cli](https://github.com/webosbrew/dev-toolbox-cli)).
That data has one firmware dump per release, from one TV model each, so other models may differ.

## 1. Why a patched package is needed

- LG's Flutter SDK ([lg-flutter-webos](https://github.com/lg-flutter-webos)) officially supports
  only **webOS 26 Re:New** and later.
- LG publishes one NDK (`11.2.0`) and only `webos26` engine artifacts (`c6f67dede3-webos26-*`).
- The SDK's version table (`lib/webos_sdk.dart`) lists only `queue` (webOS 26) and `spacebuns`
  (webOS 27). There is no option to target webOS 24 or 25.
- LG does not publish source for its webOS engine or embedder, so they cannot be rebuilt against an
  older system.

The unpatched build (`_arm_webos25-26.ipk`) is LG's standard output. It links against the NDK's
glibc 2.39 and GCC 13 libstdc++, and needs functions that only newer firmware has.

## 2. Both packages are 32-bit ARM

Every binary in both packages is 32-bit ARM (`ELF 32-bit LSB, ARM, EABI5`). LG TVs run a 32-bit
system (`lib32` firmware images) even on 64-bit chips, and the NDK targets that system
(`ca9v1-webosmllib32-linux-gnueabi`). The packages differ in which firmware's libraries they
can load against, not in CPU architecture.

## 3. Firmware library versions (webosbrew data)

| webOS | Firmware dump | glibc | libstdc++ | `wl_proxy_marshal_flags` | `NDL_MediaInitWithWindowId` |
| --- | --- | --- | --- | --- | --- |
| 6 | 6.4.0 (`03.40.82.01`) | 2.28 | 6.0.25 (`GLIBCXX_3.4.25`) | missing | missing |
| 22 | 7.4.0 (`04.40.90.01`) | 2.31 | 6.0.28 (`GLIBCXX_3.4.28`) | missing | missing |
| 23 | 8.3.0 (`03.30.60.01`) | 2.31 | 6.0.28 (`GLIBCXX_3.4.28`) | missing | missing |
| 24 | 9.2.0 (`23.20.50.01`) | 2.35 | 6.0.29 (`GLIBCXX_3.4.29`) | present | missing |
| 25 | 10.2.0 (`33.20.40.01`) | 2.35 (no `__isoc23_*`) | 6.0.29 | present | missing |
| 26 | 11.2.0 (`43.21.70.01`) | 2.38+ | 6.0.32 (`GLIBCXX_3.4.32`) | present | present |

What the unpatched engine and app need that older firmware (`6.4.0`–`10.2.0`) lacks:

- **SQLite `3.50.2` via Dart NativeAssets (`libsqlite3_dart.so`):** `sqlite3` relies on SQLite `3.50.x` APIs such as `sqlite3_error_offset` and `sqlite3_stmt_isexplain` that are missing from older TVs' `/usr/lib/libsqlite3.so.0`.
- **`libstdc++.so.6` (`6.0.32`):** NDK-compiled plugins and embedder libs reference `GLIBCXX_3.4.26`–`3.4.32` (such as `std::ios_base_library_init()`, `std::__cxx11::...` symbols, and C++17/20 runtime bits) not present on `6.4.0`–`10.2.0`.
- **glibc `2.29`–`2.38` symbols:** `plezy`, `libflutter_engine.so`, `libflutter_webos_media.so`, `libvideo_player_webos_plugin.so`, and bundled NDK `libstdc++.so.6` reference newer symbol versions:
  - Symbols that actually existed in `GLIBC_2.4` and were merely moved/re-versioned in later glibc (`dlopen`/`dlsym`/`dladdr`/`dlclose`/`dlerror`, `pthread_*`, `sem_*`, `shm_*`, math functions `exp`/`log`/`log2`/`pow`/`fmod*`/`hypot*`), plus `pthread_getname_np`/`pthread_setname_np` (`GLIBC_2.12`) and weak `close_range` (`GLIBC_2.34`).
  - Symbols genuinely added after glibc `2.28`: `__libc_start_main` (`GLIBC_2.34` NULL `init`/`fini` calling convention), `__libc_single_threaded` (`GLIBC_2.32`), `stat64`/`fstat64`/`lstat64`/`fstatat64` (`GLIBC_2.33`, replacing `__*xstat64`), `pthread_cond_clockwait` (`GLIBC_2.30`), `arc4random` (`GLIBC_2.36`), and the C23 `__isoc23_*` `strto*`/`scanf`/`wcsto*` family (`GLIBC_2.38`).
- **Wayland (`wl_proxy_marshal_flags` & `wl_webos_shell` v2):** `libflutter_webos_media.so` binds `wl_webos_shell` v2 and calls `wl_proxy_marshal_flags`, which does not exist in `libwayland-client.so.0` on webOS 6–23 (`6.4.0`–`8.3.0`).
- **Media & plugin symbols (`libvideo_player_webos_plugin.so`):** `NDL_MediaInitWithWindowId` and `NDL_MediaUnsubscribeEvents` (missing prior to `11.2.0`).

All remaining system libraries the engine needs (Wayland client/EGL/cursor, `xkbcommon`, `systemd` `LIBSYSTEMD_221`, `fontconfig`, `luna-service2`, `pbnjson_cpp`, `libatomic`, `libNDL_media`) already exist on webOS `6.4.0` and newer.

## 4. What `build_32bit_ipk.sh` changes

It unpacks the unpatched IPK and produces `com.edde746.plezy_<ver>_arm_webos6-24.ipk` across seven steps:

1. Compiles `libsqlite3_dart.so` from the SHA-256-verified SQLite `3.50.2` amalgamation with Starfish NDK `clang` (`_FILE_OFFSET_BITS=64`, `-Wl,-Bsymbolic`, `--version-script` exporting the 92 symbols used by `package:sqlite3`) and writes `data/flutter_assets/NativeAssetsManifest.json` (`"native-assets": {"linux_arm": {"package:sqlite3/src/ffi/libsqlite3.g.dart": ["system", "libsqlite3_dart.so"]}}`).
2. Bundles the Starfish NDK `libstdc++.so.6` (`6.0.32`) into `lib/`.
3. Compiles `libwebos_compat32.so` (`clang -nostdlib` with explicit `libc.so.6`, `libdl.so.2`, `libpthread.so.0`, and `librt.so.1` `DT_NEEDED` entries). See section 5.
4. Sets `plezy`'s interpreter to `/lib/ld-linux.so.3` (the unpatched build uses `/usr/lib/ld-linux.so.3`), sets `RPATH` (`$ORIGIN/lib:$ORIGIN` on `plezy`, `$ORIGIN` on libraries), and prepends `libwebos_compat32.so`, `libdl.so.2`, `libpthread.so.0`, and `librt.so.1` ahead of existing `DT_NEEDED` entries (skipping `libapp.so`).
5. Patches `libflutter_webos_media.so` so `WebOSSurface` binds `wl_webos_shell` version 1 instead of 2 by replacing the exact machine-code sequence (aborting with an error if the signature is not found).
6. Cleans ELF `.gnu.version` and `.gnu.version_r` entries on each binary (`plezy` and bundled `.so` files except `libwebos_compat32.so` and `libapp.so`): remaps `GLIBC_2.29`–`2.38` versions of pre-existing symbols to `GLIBC_2.4`, unversions shimmed/weak/`GLIBC_2.12` symbols, drops unused `GLIBC >= 2.29` `Verneed` records, updates `DT_VERNEEDNUM` and section `sh_info`, verifies zero disallowed `GLIBC >= 2.29` symbol references remain, and lowers `.note.ABI-tag` kernel versions above `3.2.0` to `3.2.0`.
7. Updates `Installed-Size` in `control` to match the unpacked bytes (`file_bytes + dir_count * 4096`), repacks `control.tar.gz` (`control` only) and `data.tar.gz` (`usr/...` without `./` prefixes) in POSIX `ustar` format with a safe past timestamp (`2024-01-01 UTC`), writes a System V `ar` archive (no trailing `/`, non-zero mtime, `100644`), and self-verifies the output `.ipk`.

## 5. What `libwebos_compat32.so` provides

Because `libwebos_compat32.so` is first in `DT_NEEDED`, GNU `ld.so` resolves interposed unversioned/versioned symbols here before searching `libc.so.6` or `libwayland-client.so.0`:

- **Process startup (`__libc_start_main`) & TLS hint (`__libc_single_threaded`):** On glibc `2.34+`, forwards to `dlvsym(RTLD_NEXT, "__libc_start_main", "GLIBC_2.34")`. On glibc `2.28`–`2.31` (webOS 6–23), forwards to `GLIBC_2.4` and injects `dl_iterate_phdr`-based `compat_exe_init` / `compat_exe_fini` helpers so PIE executables compiled against NDK `2.38` (`init=NULL, fini=NULL`) run their `DT_INIT` / `DT_INIT_ARRAY` / `DT_FINI_ARRAY` / `DT_FINI` cleanly.
- **`*stat*64` (`stat64`, `fstat64`, `lstat64`, `fstatat64`):** Forwards to real `stat64` via `RTLD_NEXT` on glibc `>= 2.33`, or falls back to `__xstat64` / `__fxstat64` / `__lxstat64` / `__fxstatat64` (`_STAT_VER_LINUX = 3`) on glibc `< 2.33`.
- **`pthread_cond_clockwait` & `arc4random`:** `pthread_cond_clockwait` delegates to the system implementation when present (`glibc >= 2.30`), otherwise inspects `pthread_cond_t::__data.__wrefs` bit `0x2` (`CLOCK_MONOTONIC`) and converts relative waits to `pthread_cond_timedwait`. `arc4random` uses `getentropy` or `/dev/urandom`.
- **`__isoc23_*` functions:** Forwards the C23 `strto*`, `scanf`/`fscanf`/`sscanf`, and `wcsto*` family to standard `strtol`/`vsscanf`/etc.
- **Wayland:** Wraps `wl_proxy_marshal_flags` and `wl_proxy_marshal_constructor_versioned` with up to 20 variadic arguments, checking `wl_proxy_get_class(proxy) == "wl_registry"` to clamp both the marshal version and `wl_registry.bind` interface version for `wl_webos_*` interfaces to `1`, and falling back from missing `wl_proxy_marshal_flags` (`6.4.0`–`8.3.0`) to `wl_proxy_marshal_constructor_versioned` / `wl_proxy_marshal` + `wl_proxy_destroy` (`WL_MARSHAL_FLAG_DESTROY`).
- **Video:** `NDL_MediaInitWithWindowId`, `NDL_MediaUnsubscribeEvents`, `NDL_MediaSelectAudioTrack`, `NDL_MediaSetPlayRate`, plus SDL window functions (`SDL_webOS*`, `SDL_GL_GetCurrentWindow`, `SDL_GetWindowFromID`, `SDL_GetWindowSize`) and dynamic trampolines for any non-6.x `NDL_*` symbols. See section 6.
- **App data paths:** Replaces `getenv` and `setenv` for the whole process and redirects `FLUTTER_HOME`, `FLUTTER_APPDATA_HOME`, `FLUTTER_TEMP_HOME`, `FLUTTER_DOWNLOAD_HOME`, `FLUTTER_EXT_STORAGE_PATH`, `FLUTTER_APP_LOG_PATH` and `XDG_*` to `/media/developer/temp/plezy_appdata`, falling back to `/tmp/plezy_appdata`.

## 6. How the missing video function is handled

The video plugin calls `NDL_MediaInitWithWindowId(0, windowId)` to attach video to Flutter's window. Pre-webOS 26 firmware does not have it.

1. The compatibility library's `NDL_MediaInitWithWindowId` saves the window ID (default `_Window_Id_1`). It calls the real function if the firmware has it (webOS 26), otherwise it calls the older `NDL_MediaInit(0)`, which takes no window ID.
2. On old firmware, `NDL_MediaInit` asks SDL for an exported window ID. A Flutter app has no SDL window; the plugin's comments say this path crashes in `TVDisplay::Initialize`. The compatibility library therefore also defines `SDL_webOSCreateExportedWindow`, which returns the saved Flutter window ID, so the old media library uses Flutter's window.
3. `SDL_webOSSetExportedWindow`, `SDL_webOSExportedSetCropRegion` and `SDL_webOSExportedSetProperty` do nothing and report success. `SDL_GetWindowSize` always reports 1920x1080.
4. If the firmware lacks `NDL_MediaUnsubscribeEvents`, the replacement returns success without unsubscribing.

## 7. Risks & verification status

- **Static verification passes across `6.4.0`–`11.2.0`; on-TV runtime confirmation is still pending.** `webosbrew-ipk-verify` reports `OK` for every binary and bundled library in `com.edde746.plezy_<ver>_arm_webos6-24.ipk` across webOS `6.4.0`, `7.4.0`, `8.3.0`, `9.2.0`, `10.2.0`, and `11.2.0`. Real-hardware execution on **webOS 6.x (e.g. LG `75QNED90UPA`, software `03.53.45`)**—especially compositor surface creation, video playback, and app shutdown—still requires physical testing.
- **Undocumented media library behavior.** The video path depends on older `libNDL_media` versions looking up those SDL functions by name and accepting the returned window ID.
- **Video position and size are not set.** If the old media library positions or crops video through the SDL functions that do nothing, those settings are lost. Full-screen playback should work; non-full-screen layouts may be misplaced.
- **Player teardown.** The plugin unsubscribes events in its player destructor to avoid a SEGV in `libumedia_api.so` when events arrive during teardown. On firmware without `NDL_MediaUnsubscribeEvents` that protection is gone. The plugin's own event routing is still safe (`dispatchEvent` checks the slot table under a mutex); the risk is an occasional crash inside LG's library when the player closes.
- **App data security and persistence.** The redirected data folders are created with mode `0777` in a Developer Mode temp folder, so settings and the Plex token are world-writable. If `/media/developer/temp` is not usable, data goes to `/tmp` and is lost on reboot. The redirection applies on every TV, including those where the normal app folder works.
- **The webOS 25-26 label.** The `10.2.0` (webOS 25) database lacks glibc 2.38 functions and `NDL_MediaInitWithWindowId`, so webOS 25 and *Re:New*-updated TVs normally need the `webos6-24` package as well.
- **Wayland version cap & older compositors.** If the engine uses a version 2 request on a clamped `wl_webos_*` object, the compositor disconnects the app. The Wayland wrappers forward up to 20 variadic arguments (exceeding the 12-argument `wl_webos_exported` calls observed in the engine).
- **Removed version requirements (low risk).** ELF symbols are resolved lazily against `libwebos_compat32.so` and system libraries with `BIND_NOW`, so any genuinely missing symbol fails cleanly at launch rather than mid-playback.

## 8. Checking a built package

```bash
# Inside the unpacked package
readelf -l plezy | grep interpreter
readelf -d plezy | grep NEEDED
for f in plezy lib/*.so*; do
  echo "$f: $(readelf -V "$f" 2>/dev/null | grep -o -E 'GLIBC_2\.[0-9]+|GLIBCXX_3\.4\.[0-9]+' | sort -u | tr '\n' ' ')"
done
cat data/flutter_assets/NativeAssetsManifest.json
readelf -Ws --dyn-syms lib/libwebos_compat32.so | grep -E 'NDL_|SDL_|__isoc23|__libc_start_main'
```

For a firmware-level check, `webosbrew-ipk-verify` from dev-toolbox-cli grades a package against its firmware database (`6.4.0` through `11.2.0`).

## 9. On-TV test checklist (webOS 6.x–25)

1. The app starts and displays the UI cleanly (confirming `ld-linux.so.3`, `__libc_start_main` init, and Wayland v1 compositor negotiation).
2. Settings, SQLite storage (`NativeAssetsManifest.json` -> `libsqlite3_dart.so`), and sign-in persist across a TV reboot (if not, appdata fell back to `/tmp`).
3. Playback works full-screen with correct size and position.
4. Opening and closing the player repeatedly does not crash.
5. Audio and subtitle track switching works.

Logs: `/media/developer/temp/plezy_appdata/log` (or `/tmp/plezy_appdata/log` if `/media/developer/temp` is not writable).

## 10. Alternatives to patching

- **Rebuild the engine and embedder** against a webOS 24 sysroot. The Flutter engine is open source
  and LG's embedder appears to be based on Sony's `flutter-elinux`, but webOS window and video
  support would have to be rewritten. Much larger effort.
- **Bundle a newer glibc and loader** in the IPK. Avoids rewriting version requirements, but the
  missing video function still needs a replacement, and whether the app sandbox allows a bundled
  loader is unknown.
- **Web app** (the `webos-chromium` branch): no patching, but no native NDL video path.
- **Wait for webOS 26** via LG's Re:New updates. The unpatched package then runs as LG ships it.

## 11. Build environment notes

- The LG NDK and the engine's `gen_snapshot` run only on x86_64 Linux.
- `@webos-tools/cli` (`ares`) 3.2.6 requires Node.js 20 or later, although LG's guide lists Node
  14-16.
- `scripts/webos/env.sh` does not put the bundled `flutter` on `PATH`; use
  `flutter-webos pub get`.
- The committed `pubspec.lock` was resolved with a newer Flutter. With Flutter 3.38.10, `pub get`
  changes `characters`, `intl`, `matcher`, `material_color_utilities`, `meta`, `test_api` and
  `vector_math` to the versions that SDK pins.
- In OrbStack Ubuntu 26.04 VMs, GNU tar `1.35+dfsg-4ubuntu0.4` fails with "Function not
  implemented" when extracting into subdirectories. That build backports `openat2` support for
  `CVE-2025-45582`; the VM most likely rejects that call (not confirmed). The NDK installer and `build_32bit_ipk.sh` both use `tar`. Workarounds:
  `bsdtar`, or the Ubuntu 24.04 `tar` binary. GitHub's Ubuntu runners are not affected.
