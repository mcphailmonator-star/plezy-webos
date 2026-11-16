#!/usr/bin/env bash
# Creates the GitHub release <tag> with the IPKs in dist/ plus a Homebrew Channel manifest and
# repository file for each. Needs GH_TOKEN with contents:write on <repo>.
# Usage: publish.sh <owner/name> <tag>
set -euo pipefail
ORIG_REPO="$1"
ORIG_TAG="$2"

REPO="$1"
TAG="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DIST="$REPO_ROOT/dist"

python3 "$REPO_ROOT/scripts/webos/ci/make_homebrew_repo.py" "$DIST" --repo "$REPO" --tag "$TAG"

latest="https://github.com/$REPO/releases/latest/download"
notes="Both packages contain 32-bit ARM binaries and share the app id com.edde746.plezy; install only the one matching your TV.

Homebrew Channel: add the repository URL for your TV in the Homebrew Channel settings. Each repository lists one package and follows the latest release.

| TV | Package | Homebrew Channel repository | Manifest |
| --- | --- | --- | --- |
| Factory webOS 25 / 26 hardware (2025+ models) | \`com.edde746.plezy_*_arm_webos25-26.ipk\` | $latest/plezy-webos25-26.repo.json | $latest/plezy-webos25-26.manifest.json |
| Pre-2025 TVs (webOS 6.x through webOS 24, and Re:New TVs on webOS 25 / 26) | \`com.edde746.plezy_*_arm_webos6-24.ipk\` | $latest/plezy-webos6-24.repo.json | $latest/plezy-webos6-24.manifest.json |

The \`webos6-24\` build bundles \`libwebos_compat32.so\`, NDK \`libstdc++.so.6\`, and \`libsqlite3_dart.so\` so it links cleanly back to \`webOS 6.x\` (\`glibc 2.28+\`).

The manifests carry the SHA-256 of each IPK, which the Homebrew Channel checks before installing."

gh release delete "$ORIG_TAG" --repo "$ORIG_REPO" --yes 2>/dev/null || true
gh release create "$TAG" --repo "$REPO" --title "$TAG" --notes "$notes" \
  "$DIST"/*.ipk "$DIST"/*.manifest.json "$DIST"/*.repo.json

NOTES_TMP="$(mktemp)"
cat << NOTES_EOF > "$NOTES_TMP"
Native 32-bit ARM (\`armv7l\`) packages of Plezy for LG webOS TVs. Both builds share the application ID \`com.edde746.plezy\`. Only one package or Homebrew repository should be active on a TV at a time.

### Package Selection (TV Model Year vs. webOS Version)

Which package your TV requires depends primarily on the **hardware release year** of the television rather than the displayed webOS version number alone. When 2022–2024 TVs receive webOS 25 or webOS 26 through LG's *webOS Re:New* program, the system interface is updated, but the underlying C runtime (\`glibc 2.31–2.35\`) and Wayland compositor protocol (\`wl_webos_shell\` v1) remain on the pre-2025 baseline rather than upgrading to the \`glibc 2.38\` and \`wl_webos_shell\` v2 stack used on factory-built 2025/2026 models.

* **\`webos25-26\` (Standard Build):** Built for 2025 and 2026 LG TV models that shipped with webOS 25 or webOS 26 from the factory (\`glibc 2.38+\` / \`wl_webos_shell\` v2).
* **\`webos6-24\` (Compatibility Build):** Bundles \`libwebos_compat32.so\` (\`glibc 2.28–2.38\` symbol & startup bridges, \`wl_webos_shell\` v1 protocol clamp & \`wl_proxy_marshal_flags\` fallback, and \`NDL_Media*\` shims), NDK \`libstdc++.so.6\` (\`6.0.32\`), and \`libsqlite3_dart.so\` (\`3.50.2\` via \`NativeAssetsManifest.json\`). Statically verified against firmware library dumps from **webOS 6.4.0 (`glibc 2.28`, 2021 models) through webOS 11.2.0**. Use this build on **all webOS 6.x–24 TVs** (including 2021 models such as \`75QNED90UPA\` / \`C1\` / \`G1\` and 2022–2024 models updated to webOS 25 or 26 via *Re:New*), or whenever the \`webos25-26\` package closes immediately on launch.

### Downloads & Homebrew Channel Repositories

| Target Hardware / Runtime | IPK Package | Homebrew Repository URL (add in Homebrew Settings) | Direct Manifest URL |
| :--- | :--- | :--- | :--- |
| Factory webOS 25 / 26 hardware (2025+ models) | \`com.edde746.plezy_*_arm_webos25-26.ipk\` | https://github.com/${ORIG_REPO}/releases/latest/download/plezy-webos25-26.repo.json | https://github.com/${ORIG_REPO}/releases/latest/download/plezy-webos25-26.manifest.json |
| Pre-2025 hardware (webOS 6.x–24 & Re:New-updated TVs) | \`com.edde746.plezy_*_arm_webos6-24.ipk\` | https://github.com/${ORIG_REPO}/releases/latest/download/plezy-webos6-24.repo.json | https://github.com/${ORIG_REPO}/releases/latest/download/plezy-webos6-24.manifest.json |

### Installation & Automatic Updates

* **webOS Homebrew Channel / Glasshouse:** Open the Homebrew Channel app on your TV, go to **Settings -> Repositories**, and add **only the \`.repo.json\` URL** matching your TV hardware from the table above (do not enter the \`.manifest.json\` URL there, and do not enable both repositories at the same time). The repository tracks the latest release and verifies the SHA-256 checksum from the manifest before installing.
* **Manual Installation:** Download the matching \`.ipk\` file from the release assets below and install it via **webOS Dev Manager** or the command line (\`ares-install <package>.ipk\`).
NOTES_EOF

gh release edit "$ORIG_TAG" --repo "$ORIG_REPO" --notes-file "$NOTES_TMP"
rm -f "$NOTES_TMP"
