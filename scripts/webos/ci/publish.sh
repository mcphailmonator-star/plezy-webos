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
32-bit ARM (\`armv7l\`) release of Plezy for LG webOS TVs (app ID \`${APP_ID}\`). Install only one package variant or Homebrew repository on a TV at a time.

### Choosing the Right Package

Select the package that matches your **TV's hardware model year** rather than the webOS version displayed in settings. TVs from 2022–2024 that receive webOS 25 or 26 via LG's *webOS Re:New* program keep their original \`glibc 2.31–2.35\` runtime and \`wl_webos_shell\` v1 compositor protocol, so they still require the \`webos6-24\` build.

* **\`webos6-24\` (2021–2024 TVs & Re:New Upgrades):** Targets webOS 6.x through webOS 24 as well as 2022–2024 models updated to webOS 25/26. Bundles \`libwebos_compat32.so\` (\`glibc 2.28–2.38\` symbol shims, \`wl_webos_shell\` v1 protocol handling, and \`NDL_Media*\` wrappers), NDK \`libstdc++.so.6\` (\`6.0.32\`), and \`libsqlite3_dart.so\` (\`3.50.2\`). Use this package if the \`webos25-26\` build exits on startup.
* **\`webos25-26\` (2025–2026 Factory TVs):** Targets 2025 and 2026 LG models that shipped from the factory with webOS 25 or webOS 26 (\`glibc 2.38+\` and \`wl_webos_shell\` v2).

### Packages & Homebrew Repositories

| TV Hardware | IPK File | Homebrew Channel / Glasshouse Repository URL |
| :--- | :--- | :--- |
| 2021–2024 TVs (webOS 6.x–24 & *Re:New* 25/26) | \`${APP_ID}_*_arm_webos6-24.ipk\` | ${RAW_REPO_BASE}/plezy-webos6-24.repo.json |
| 2025–2026 Factory TVs (webOS 25 / 26) | \`${APP_ID}_*_arm_webos25-26.ipk\` | ${RAW_REPO_BASE}/plezy-webos25-26.repo.json |

*(Release asset mirrors: ${LATEST_RELEASE_BASE}/plezy-webos6-24.repo.json and ${LATEST_RELEASE_BASE}/plezy-webos25-26.repo.json)*

### Installation

* **Homebrew Channel / Glasshouse (Auto-Updates):** Open Homebrew Channel on your TV, go to **Settings → Repositories → Add Repository**, and enter the single \`.repo.json\` URL for your TV from the table above (do not use the GitHub repository URL or a \`.manifest.json\` link, and do not add both repositories at once).
* **Sideloading:** Download the matching \`.ipk\` below and install it with **webOS Dev Manager** or \`ares-install <package>.ipk\`.
NOTES_EOF

gh release delete "$TAG" --repo "$REPO" --yes 2>/dev/null || true
gh release create "$TAG" --repo "$REPO" --title "$TAG" --notes-file "$NOTES_TMP" \
  "$DIST"/*.ipk "$DIST"/*.manifest.json "$DIST"/*.repo.json
rm -f "$NOTES_TMP"

