#!/usr/bin/env bash
# Creates the GitHub release <tag> with the IPKs in dist/ plus a Homebrew Channel manifest and
# repository file for each. Needs GH_TOKEN with contents:write on <repo>.
# Usage: publish.sh <owner/name> <tag>
set -euo pipefail
REPO="$1"
TAG="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DIST="$REPO_ROOT/dist"

RAW_REPO_BASE="https://raw.githubusercontent.com/$REPO/hb-repo"
LATEST_RELEASE_BASE="https://github.com/$REPO/releases/latest/download"

python3 "$REPO_ROOT/scripts/webos/ci/make_homebrew_repo.py" "$DIST" \
  --repo "$REPO" --tag "$TAG" --manifest-base-url "$RAW_REPO_BASE"

# Publish repository & manifest JSON files onto the dedicated hb-repo branch so
# raw.githubusercontent.com serves them directly with HTTP 200 (no 302 redirects)
# and Access-Control-Allow-Origin: * for Homebrew Channel / Glasshouse.
PUSH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"
if [ -n "$PUSH_TOKEN" ]; then
  HB_TMP="$(mktemp -d)"
  git -C "$HB_TMP" init
  git -C "$HB_TMP" config user.name "github-actions[bot]"
  git -C "$HB_TMP" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git -C "$HB_TMP" remote add origin "https://x-access-token:${PUSH_TOKEN}@github.com/${REPO}.git"
  if git -C "$HB_TMP" fetch --depth=1 origin hb-repo 2>/dev/null; then
    git -C "$HB_TMP" checkout -B hb-repo FETCH_HEAD
  else
    git -C "$HB_TMP" checkout --orphan hb-repo
  fi
  cp -f "$DIST"/*.repo.json "$DIST"/*.manifest.json "$HB_TMP"/
  cat << EOF > "$HB_TMP/README.md"
# Plezy Homebrew Channel Repositories

Auto-updated on release \`${TAG}\`.

- **Pre-2025 TVs (webOS 6.x–24 and Re:New 25/26):** \`${RAW_REPO_BASE}/plezy-webos6-24.repo.json\`
- **Factory 2025/2026 TVs (webOS 25/26):** \`${RAW_REPO_BASE}/plezy-webos25-26.repo.json\`
EOF
  git -C "$HB_TMP" add *.repo.json *.manifest.json README.md
  if ! git -C "$HB_TMP" diff --cached --quiet; then
    git -C "$HB_TMP" commit -m "chore(hb-repo): publish ${TAG} Homebrew manifests"
    git -C "$HB_TMP" push origin HEAD:refs/heads/hb-repo
  fi
  rm -rf "$HB_TMP"
else
  echo "WARNING: no GH_TOKEN available; skipping hb-repo branch update" >&2
fi

APP_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$REPO_ROOT/webos/meta/appinfo.json" 2>/dev/null || true)"
APP_ID="${APP_ID:-com.mcphailmonator.plezy}"

NOTES_TMP="$(mktemp)"
cat << NOTES_EOF > "$NOTES_TMP"
Native 32-bit ARM (\`armv7l\`) packages of Plezy for LG webOS TVs. Both builds share the application ID \`${APP_ID}\`. Only one package or Homebrew repository should be active on a TV at a time.

### Package Selection (TV Model Year vs. webOS Version)

Which package your TV requires depends primarily on the **hardware release year** of the television rather than the displayed webOS version number alone. When 2022–2024 TVs receive webOS 25 or webOS 26 through LG's *webOS Re:New* program, the system interface is updated, but the underlying C runtime (\`glibc 2.31–2.35\`) and Wayland compositor protocol (\`wl_webos_shell\` v1) remain on the pre-2025 baseline rather than upgrading to the \`glibc 2.38\` and \`wl_webos_shell\` v2 stack used on factory-built 2025/2026 models.

* **\`webos25-26\` (Standard Build):** Built for 2025 and 2026 LG TV models that shipped with webOS 25 or webOS 26 from the factory (\`glibc 2.38+\` / \`wl_webos_shell\` v2).
* **\`webos6-24\` (Compatibility Build):** Bundles \`libwebos_compat32.so\` (\`glibc 2.28–2.38\` symbol & startup bridges, \`wl_webos_shell\` v1 protocol clamp & \`wl_proxy_marshal_flags\` fallback, and \`NDL_Media*\` shims), NDK \`libstdc++.so.6\` (\`6.0.32\`), and \`libsqlite3_dart.so\` (\`3.50.2\` via \`NativeAssetsManifest.json\`). Packed in System V \`ar\` + POSIX \`ustar\` format with accurate \`Installed-Size\`. Statically verified against firmware library dumps from **webOS 6.4.0 (\`glibc 2.28\`, 2021 models) through webOS 11.2.0**. Use this build on **all webOS 6.x–24 TVs** (including 2021 models such as \`75QNED90UPA\` / \`C1\` / \`G1\` and 2022–2024 models updated to webOS 25 or 26 via *Re:New*), or whenever the \`webos25-26\` package closes immediately on launch.

### Downloads & Homebrew Channel Repositories

| Target Hardware / Runtime | IPK Package | Homebrew Repository URL (add in Homebrew Settings) |
| :--- | :--- | :--- |
| Pre-2025 hardware (webOS 6.x–24 & Re:New-updated TVs) | \`${APP_ID}_*_arm_webos6-24.ipk\` | ${RAW_REPO_BASE}/plezy-webos6-24.repo.json |
| Factory webOS 25 / 26 hardware (2025+ models) | \`${APP_ID}_*_arm_webos25-26.ipk\` | ${RAW_REPO_BASE}/plezy-webos25-26.repo.json |

*(Release asset mirrors: ${LATEST_RELEASE_BASE}/plezy-webos6-24.repo.json and ${LATEST_RELEASE_BASE}/plezy-webos25-26.repo.json)*

### Installation & Automatic Updates

* **webOS Homebrew Channel / Glasshouse:** Open the Homebrew Channel app on your TV, go to **Settings -> Repositories -> Add repository**, and enter **only the \`.repo.json\` URL** matching your TV hardware from the table above (do **not** enter the GitHub repository page URL or a \`.manifest.json\` URL, and do not enable both variants at the same time). The manifest verifies the IPK's SHA-256 checksum before installing.
* **Manual Installation:** Download the matching \`.ipk\` file from the release assets below and install it via **webOS Dev Manager** or the command line (\`ares-install <package>.ipk\`).
NOTES_EOF

gh release delete "$TAG" --repo "$REPO" --yes 2>/dev/null || true
gh release create "$TAG" --repo "$REPO" --title "$TAG" --notes-file "$NOTES_TMP" \
  "$DIST"/*.ipk "$DIST"/*.manifest.json "$DIST"/*.repo.json
rm -f "$NOTES_TMP"

