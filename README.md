<h1>
  <img src="assets/plezy.png" alt="Plezy Logo" height="24" style="vertical-align: middle;" />
  Plezy for LG webOS
</h1>

Native LG webOS TV port of [Plezy](https://github.com/edde746/plezy) — a modern client for Plex, Jellyfin, and Emby built with Flutter, combining upstream fixes from [`edde746/plezy`](https://github.com/edde746/plezy) with the [`GLNick/plezy-webos`](https://github.com/GLNick/plezy-webos) native `NDL_media` playback and ASS/SSA/PGS subtitle engine.

> [!NOTE]
> This is an **unofficial community fork** for LG webOS TVs and is not maintained or endorsed by the upstream Plezy project. For official desktop and mobile builds, see [`edde746/plezy`](https://github.com/edde746/plezy).

<p>
  <a href="#download--which-package-to-use">Download</a> ·
  <a href="#how-to-install">How to Install</a> ·
  <a href="#building-for-webos-from-source">Build for webOS</a> ·
  <a href="BUILD_WEBOS.md">Toolchain Guide</a> ·
  <a href="WEBOS_COMPAT_PATCHING.md">Compatibility Notes</a> ·
  <a href="LICENSE">License</a>
</p>

## Download & Which Package to Use

All releases ship two native 32-bit ARM (`armv7l`) `.ipk` packages on the [Releases page](https://github.com/mcphailmonator-star/plezy-webos/releases/latest). Both share app ID `com.edde746.plezy` — **install only one package (and enable only one Homebrew repository) on a TV at a time.**

Choosing the right `.ipk` depends on your TV's **hardware release year** rather than the displayed webOS version alone. When 2022–2024 TVs receive webOS 25 or 26 via LG's *webOS Re:New* program, the UI updates while the underlying `glibc 2.35` and `wl_webos_shell` v1 runtime remain on the pre-2025 baseline.

| TV Hardware / Firmware | Package | Homebrew Channel / Glasshouse `.repo.json` URL | Notes |
| --- | --- | --- | --- |
| **Factory 2025 / 2026 TVs** (`webOS 25` / `webOS 26`) | [`*_arm_webos25-26.ipk`](https://github.com/mcphailmonator-star/plezy-webos/releases/latest) | `https://raw.githubusercontent.com/mcphailmonator-star/plezy-webos/hb-repo/plezy-webos25-26.repo.json` | Native `glibc 2.38+`, `wl_webos_shell` v2, and `NDL_MediaInitWithWindowId` |
| **Pre-2025 TVs** (`webOS 6.x` through `webOS 24`, or 2022–2024 *Re:New* TVs on `webOS 25` / `26`) | [`*_arm_webos6-24.ipk`](https://github.com/mcphailmonator-star/plezy-webos/releases/latest) | `https://raw.githubusercontent.com/mcphailmonator-star/plezy-webos/hb-repo/plezy-webos6-24.repo.json` | Targets `webOS 6.x` (`glibc 2.28+`) through `webOS 24` and *Re:New* TVs: bundles `libwebos_compat32.so` (`glibc 2.28–2.38` + Wayland v1 shims), NDK `libstdc++.so.6` (`6.0.32`), and `libsqlite3_dart.so` (`3.50.2`) |

> [!TIP]
> If the `webos25-26` build closes immediately after launch, uninstall it and install the `webos6-24` build instead. Runtime compatibility is statically verified against webOS `6.4.0`–`11.2.0` firmware library databases; physical TV playback (`NDL_media`) confirmation on webOS 6.x hardware is welcomed via issues/logs (`/media/developer/temp/plezy_appdata/log`).

## How to Install

### Option 1: Homebrew Channel or Glasshouse (Recommended — Auto-Updates)

Best if you have [webOS Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel) (or Glasshouse) on your TV:

1. Open **Homebrew Channel** on your LG TV and go to **Settings → Repositories**.
2. Choose **Add Repository** and enter **only the `.repo.json` URL** matching your TV from the table above (do **not** enter the GitHub repository page URL `https://github.com/mcphailmonator-star/plezy-webos`, do **not** paste a `.manifest.json` URL, and do **not** add both repositories at the same time).
3. Return to the main Homebrew Channel listing, find **Plezy (webOS 6-24)** (or **Plezy (webOS 25-26)**), and select **Install**. If `-5: ipk verified failed` ever occurs on an older TV, verify the TV's clock is set to the current date under **Settings → General → System → Time & Timer**.
4. Future tagged releases update automatically with SHA-256 verification.

### Option 2: webOS Dev Manager (No Root Required)

1. Download the matching `.ipk` file from the [Latest Release](https://github.com/mcphailmonator-star/plezy-webos/releases/latest).
2. On your LG TV, install **Developer Mode** from the LG Content Store, sign in with a free LG Developer account, and enable **Dev Mode Status** and **Key Server**.
3. On your computer, open [webOS Dev Manager](https://github.com/webosbrew/dev-manager-desktop/releases) and add/connect your TV using its IP address and Developer Mode passphrase.
4. Click **Install** (`+`) and select your downloaded `.ipk` file, then launch **Plezy** from your TV home screen.

> [!IMPORTANT]
> On non-rooted TVs using LG Developer Mode, LG automatically deletes sideloaded apps when the Developer Mode session timer expires unless you extend the timer periodically inside the Developer Mode app (or automate renewal with webOS Dev Manager / Home Assistant).

### Option 3: Command Line (`ares-install`)

Requires Node.js 20+ and LG's `@webos-tools/cli`:

```bash
npm install -g @webos-tools/cli

# One-time device setup (enter TV IP, port 9922, user prisoner, Developer Mode passphrase)
ares-setup-device

# Install the package matching your TV (example: webos6-24)
ares-install -d <your-tv-name> com.edde746.plezy_*_arm_webos6-24.ipk

# Launch Plezy
ares-launch -d <your-tv-name> com.edde746.plezy
```

<details>
<summary>Other platforms (upstream edde746/plezy desktop & mobile builds)</summary>

Official desktop and mobile builds are published upstream at [`edde746/plezy`](https://github.com/edde746/plezy/releases/latest):

- **Apple / Google / Amazon / Microsoft Stores:** Available from the [upstream Plezy README](https://github.com/edde746/plezy#download).
- **macOS:** [DMG (x64, arm64)](https://github.com/edde746/plezy/releases/latest/download/plezy-macos.dmg) (`brew install --cask plezy`)
- **Linux x64:** [.deb](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.deb) · [.rpm](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.rpm) · [.pkg.tar.zst](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.pkg.tar.zst) · [.flatpak](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.flatpak) · [.AppImage](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.AppImage) · [tar.gz](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-x64.tar.gz)
- **Linux arm64:** [.deb](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.deb) · [.rpm](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.rpm) · [.pkg.tar.zst](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.pkg.tar.zst) · [.flatpak](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.flatpak) · [.AppImage](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.AppImage) · [tar.gz](https://github.com/edde746/plezy/releases/latest/download/plezy-linux-arm64.tar.gz)

</details>

<p align="center">
  <img src="assets/readme-showcase.webp" alt="Plezy screenshots" width="900" />
</p>


## Features

### <img src="assets/readme_icons/browse.svg" height="20" alt="" align="center" /> Browse & Discover
- Libraries, collections, and playlists — video and audio
- Shuffle a whole movie or TV library
- Discover hub — Continue Watching, Next Up, trending, and recommendations
- Continue Watching shows a title held in several libraries or on several servers once, and asks which copy to play
- Cross-server search across every connected Plex, Jellyfin, and Emby server, including actors and directors
- Filtering, sorting, and alphabetical jump navigation
- Folder browsing and folder playback — home-video libraries open in folder view
- Resolution, HDR/Dolby Vision, and audio-format badges on cards and detail pages
- Favorites and unwatched library filters[^mb]
- Extras — trailers, deleted scenes, behind-the-scenes

### <img src="assets/readme_icons/explore.svg" height="20" alt="" align="center" /> Explore & Requests
- Explore tab — watchlist, trending, popular, and recommendation rows from Plex Discover[^plex], Trakt, MyAnimeList, AniList, Simkl, and Seerr[^connect]
- Search any connected catalog source
- Catalog titles matched back to your own libraries by external ID
- Seerr — request movies and shows with per-season, 4K, and advanced destination options, and see request status inline
- Watchlist sync — add and remove titles on Plex, Trakt, MyAnimeList, AniList, and Simkl from anywhere in the app

### <img src="assets/readme_icons/playback.svg" height="20" alt="" align="center" /> Playback
- Wide codec support (HEVC, AV1, VP9, and more)
- HDR and Dolby Vision[^hdr]
- Direct play, or transcode presets from 240p/320 kbps to 1080p/20 Mbps
- Multi-version switching with per-version file details
- Full ASS/SSA subtitles with customizable styling
- Online subtitle search & download[^plex]
- Audio & subtitle choices remembered per title, or follow the server's per-episode selections
- Progress sync and resume
- Auto-play next episode with skip intro / skip credits
- Chapter navigation with thumbnail scrub previews
- Playback speed from 0.25x to 8x, audio sync offset, sleep timer (fixed durations or end of video)
- Video zoom 50-200% with pinch, presets, and hotkeys
- Audio passthrough[^pass], output channel limit (5.1 or stereo, with center-channel boost), and loudness normalization
- File Info sheet — every version, file, and stream the server reports
- Ambient lighting and GLSL shader presets[^mpv]
- Picture-in-Picture[^pip]
- Refresh-rate matching[^rrm]
- External player launch (VLC, MX Player, etc.) with progress sync back[^android]

### <img src="assets/readme_icons/music.svg" height="20" alt="" align="center" /> Music
- Music libraries — artist, album, and track browsing with square artwork
- Album and artist screens with play, shuffle, and Instant Mix
- Gapless playback with a full play queue — reorder, remove, play next, add to queue
- Now Playing with synced lyrics[^lyrics], persistent mini-player, and sleep timer
- Background playback with lock-screen, media-key, and notification controls[^bgaudio]
- Offline playback of downloaded albums and tracks
- Streaming quality presets — Original, 320, 192, or 128 kbps

### <img src="assets/readme_icons/live-tv.svg" height="20" alt="" align="center" /> Live TV & DVR
- Live TV channel browsing, tuning, and favorites
- EPG guide with What's On and per-show schedules
- DVR recording rules, scheduled recordings, and a rememberable recording target library[^plex]
- Multi-server Live TV support where available

### <img src="assets/readme_icons/downloads.svg" height="20" alt="" align="center" /> Downloads & Offline
- Download movies, shows, and music for offline playback[^dl]
- Background queue with pause / resume
- Sync rules for automatic downloads, with per-show "Include Specials"
- Offline browsing with watch state sync-back on reconnect

### <img src="assets/readme_icons/watch-together.svg" height="20" alt="" align="center" /> Watch Together
- Rooms on [Open Watch Party](https://openwatch.party) — share a six-character code; friends join from Plezy or another Open Watch Party app
- Everyone plays their own copy from their own server — Plex, Jellyfin, or Emby — matched by catalogue IDs, with a picker when several copies fit
- Synchronized play / pause / seek, host or shared control, room lock, and host handoff
- Public relays by default, or point Plezy at your own self-hosted relay

### <img src="assets/readme_icons/integrations.svg" height="20" alt="" align="center" /> Integrations
- Discord Rich Presence[^desktop]
- Trakt, MyAnimeList, AniList, and Simkl — ratings, watched sync, and real-time scrobbling[^rt]
- Scores from connected trackers on detail pages — Trakt, Simkl, MyAnimeList, and AniList, plus Rotten Tomatoes, Metacritic, Letterboxd, IMDb, and TMDB through MDBList
- Plezy Remote — control desktop and TV from mobile
- Watch Next row and tvOS Top Shelf[^shelf]
- [`plezy://` links](#plezy-links) to open a profile, play a title, or tune a channel from Home Assistant, launchers, or an NFC tag; any movie, show, or episode menu shows its link[^links]

### <img src="assets/readme_icons/customization.svg" height="20" alt="" align="center" /> Platform & Customization
- Desktop, mobile, and TV — full D-pad, keyboard, and gamepad support
- Multiple servers at once — Plex, Jellyfin, and Emby side by side
- Profiles with per-profile downloads, watch state, and settings; Plex Home switching with PIN
- Jellyfin and Emby local-server discovery and multiple URLs per server; Quick Connect sign-in[^jf]
- TV layout options — corner spotlight backdrop, full-card artwork, and Force TV mode on desktop
- Customizable keyboard shortcuts[^desktop]
- Metadata and artwork editing
- Settings import/export
- Localized in English plus 21 translations

[^jf]: Jellyfin only.
[^mb]: Jellyfin and Emby only.
[^plex]: Plex only.
[^connect]: Requires connecting the service under Settings > Services.
[^hdr]: In-app HDR toggle on Windows, macOS, iOS, tvOS, and Linux — Linux needs a colour-managed Wayland compositor. Dolby Vision on Android, macOS, and Apple TV.
[^pass]: Desktop, Android TV, and Apple TV.
[^mpv]: Requires the mpv player backend — Android defaults to ExoPlayer. Not applied to Dolby Vision on Apple platforms.
[^pip]: Android, iOS, and macOS — not on Android TV or Apple TV.
[^rrm]: Windows, Android, and tvOS.
[^android]: Progress sync on Android.
[^lyrics]: Where your server provides lyrics.
[^bgaudio]: tvOS pauses music when the app is backgrounded.
[^dl]: Not available on tvOS.
[^desktop]: Desktop only.
[^rt]: Real-time scrobbling on Trakt and Simkl; MyAnimeList and AniList update on completion.
[^shelf]: Android TV / Fire TV and tvOS.
[^links]: Android, iOS, macOS, and tvOS.

## plezy:// links

Links start Plezy from outside the app. Any link may add `profile=<profile>`: a profile id, a Plex Home user UUID, or a display name (ignoring case; it must match one profile). Plezy switches to that profile first, and a protected profile still asks for its PIN. A link replaces whatever is playing.

| Link | Does |
|---|---|
| `plezy://open` | Opens Plezy |
| `plezy://play?server=<server>&id=<item>` | Plays one item on one server, any backend |
| `plezy://play?type=movie\|show&tmdb=<n>` | Plays a title from whichever server has it. Use `tmdb`, `tvdb`, `imdb=tt<n>`, or `plex=<hash>` (the Plex GUID without `plex://movie/`) |
| `plezy://live?channel=<channel>` | Tunes a Live TV channel by key, number, or call sign. Optional `server=<server>` and `start=beginning\|live` |

For a show, `mode=next` (the default) plays the next episode to watch, and `mode=shuffle` plays the show shuffled. The menu of any movie, show, or episode has **Show link**, and each profile's menu in **Switch Profile** has **Show profile link**. Both show the link as text and a QR code.

```sh
# Android / Android TV, over adb (Home Assistant: remote.turn_on with activity: plezy://...)
adb shell am start -a android.intent.action.VIEW -d "plezy://play?type=show\&tvdb=81189\&profile=Kids"
# macOS
open "plezy://play?type=movie&tmdb=603"
```

On iOS, use the Open URLs action in Shortcuts.

## Building for webOS from Source

All LG webOS plugins (`webos_plugins/`) and Dart 3.10-compatible vendored packages (`vendor/`) are included in this repository. See [`BUILD_WEBOS.md`](BUILD_WEBOS.md) for full toolchain setup, [`WEBOS_COMPAT_PATCHING.md`](WEBOS_COMPAT_PATCHING.md) for `webos6-24` compatibility patching details, and [`WEBOS_CI.md`](WEBOS_CI.md) for GitHub Actions release automation.

### Quick Build (Ubuntu / Linux x86_64)

```bash
git clone https://github.com/mcphailmonator-star/plezy-webos.git plezy
cd plezy

# Install LG Starfish NDK 11.2.0, flutter-webos (Flutter 3.38.10 / Dart 3.10.9), Node.js 22, and ares 3.2.6
./scripts/webos/ci/setup-toolchain.sh

# Build both release IPKs into ./dist/
./scripts/webos/ci/build.sh
```

Or run the build steps directly after sourcing the environment:

```bash
source scripts/webos/env.sh
flutter-webos pub get
flutter-webos build webos --release
./scripts/webos/build_32bit_ipk.sh
```

Output `.ipk` packages will be written to `dist/`:
- `dist/com.edde746.plezy_<version>_arm_webos25-26.ipk`
- `dist/com.edde746.plezy_<version>_arm_webos6-24.ipk`

<details>
<summary>Upstream code generation, Linux packaging, and checks</summary>

After modifying model classes or generated sources:

```bash
scripts/codegen.sh
```

After modifying translations:

```bash
dart run slang
```

Upstream Linux Flatpak packaging and CI check scripts (`scripts/ci_checks.sh`, `linux/packaging/build-flatpak.py`) target the upstream desktop/mobile Flutter 3.47+ tree at [`edde746/plezy`](https://github.com/edde746/plezy).

</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for general codebase workflow and translation guidelines. Upstream non-webOS issues and contributions should go to [`edde746/plezy`](https://github.com/edde746/plezy).

## License

Plezy is licensed under [GPL-3.0](LICENSE). The license covers the code, not the Plezy name or logo; forks distributed beyond personal use must follow [TRADEMARKS.md](TRADEMARKS.md).

## Acknowledgments

- Upstream application by [`edde746/plezy`](https://github.com/edde746/plezy) built with [Flutter](https://flutter.dev)
- LG webOS native `NDL_media` player, 60fps ASS/SSA/PGS subtitle renderer, and `webos6-24` compatibility toolchain by [`GLNick/plezy-webos`](https://github.com/GLNick/plezy-webos) and [`lg-flutter-webos/flutter-webos`](https://github.com/lg-flutter-webos/flutter-webos)
- Supports [Plex Media Server](https://www.plex.tv), [Jellyfin](https://jellyfin.org), and [Emby](https://emby.media)
- Upstream desktop/mobile playback powered by [mpv](https://mpv.io), Android [ExoPlayer](https://developer.android.com/media/media3/exoplayer), and [libass-android](https://github.com/peerless2012/libass-android)

