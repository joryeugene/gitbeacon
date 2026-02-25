# gh-notify development and release workflow

default:
    @just --list

# Lint all shell scripts with shellcheck
lint:
    shellcheck scripts/gh-notify-daemon.sh scripts/gh-notify-bar.sh install.sh

# Copy scripts to ~/.config/gh-notify/ — fast dev deploy, no prereq checks
# Use after any edit to scripts/; press [r] in the bar to reload
sync:
    @mkdir -p "${HOME}/.config/gh-notify"
    @cp scripts/gh-notify-daemon.sh "${HOME}/.config/gh-notify/gh-notify-daemon.sh"
    @cp scripts/gh-notify-bar.sh    "${HOME}/.config/gh-notify/gh-notify-bar.sh"
    @chmod +x "${HOME}/.config/gh-notify/gh-notify-daemon.sh" \
              "${HOME}/.config/gh-notify/gh-notify-bar.sh"
    @echo "synced → ~/.config/gh-notify/  (press [r] in bar to reload)"

# Full install: prereq checks, copy scripts, install CLI wrapper (first-time setup)
install:
    bash install.sh

# Remove all installed files and state
uninstall:
    @echo "Stopping any running processes..."
    @pkill -f gh-notify-daemon 2>/dev/null || true
    @pkill -f gh-notify-bar 2>/dev/null || true
    @echo "Removing state directory..."
    @rm -rf "${HOME}/.config/gh-notify"
    @echo "Removing CLI wrapper..."
    @rm -f "${HOME}/.local/bin/gh-notify"
    @echo "Uninstalled."

# Print a draft CHANGELOG section from commits since last tag
# Review and paste into CHANGELOG.md [Unreleased] before releasing
notes:
    #!/usr/bin/env bash
    set -euo pipefail
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    DATE=$(date +%Y-%m-%d)
    if [[ -z "$LAST_TAG" ]]; then
        echo "## [Unreleased] - ${DATE}"
        echo ""
        git log --pretty="format:- %s" --reverse
    else
        echo "## [Unreleased] - ${DATE}"
        echo ""
        git log --pretty="format:- %s" --reverse "${LAST_TAG}..HEAD"
    fi

# Build a custom gh-notify-notifier.app with pixel art icon.
# Repackages terminal-notifier with our icon + bundle ID so the left-side app icon
# in macOS notifications shows the gh-notify bell instead of terminal-notifier's icon.
#
# Prereqs: sips, iconutil, codesign, PlistBuddy (built-in macOS) + rsvg-convert (brew install librsvg)
# Requires: brew terminal-notifier already installed
# One-time after build: macOS will prompt for notification permission on first use.
build-notifier:
    #!/usr/bin/env bash
    set -euo pipefail

    TN_APP="$(brew --prefix terminal-notifier 2>/dev/null)/terminal-notifier.app"
    [[ -d "$TN_APP" ]] || { echo "✗  terminal-notifier.app not found — run: brew install terminal-notifier"; exit 1; }
    [[ -f "assets/icon.svg" ]] || { echo "✗  assets/icon.svg not found — run from repo root"; exit 1; }

    STATE_DIR="${HOME}/.config/gh-notify"
    BUILD_DIR="${STATE_DIR}/.build"
    APP_DEST="${STATE_DIR}/gh-notify-notifier.app"

    mkdir -p "$BUILD_DIR"

    echo "→ Rendering icon SVG → PNG..."
    command -v rsvg-convert &>/dev/null || { echo "✗  rsvg-convert not found — run: brew install librsvg"; exit 1; }
    rsvg-convert -w 1024 -h 1024 assets/icon.svg -o "${BUILD_DIR}/icon-1024.png"

    echo "→ Building iconset..."
    ICONSET="${BUILD_DIR}/gh-notify.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512 1024; do
        sips -z "$size" "$size" "${BUILD_DIR}/icon-1024.png" \
            --out "${ICONSET}/icon_${size}x${size}.png" &>/dev/null
    done
    cp "${ICONSET}/icon_32x32.png"   "${ICONSET}/icon_16x16@2x.png"
    cp "${ICONSET}/icon_64x64.png"   "${ICONSET}/icon_32x32@2x.png"
    cp "${ICONSET}/icon_256x256.png" "${ICONSET}/icon_128x128@2x.png"
    cp "${ICONSET}/icon_512x512.png" "${ICONSET}/icon_256x256@2x.png"
    cp "${ICONSET}/icon_1024x1024.png" "${ICONSET}/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" --output "${BUILD_DIR}/gh-notify.icns"

    echo "→ Copying app bundle..."
    rm -rf "$APP_DEST"
    cp -r "$TN_APP" "$APP_DEST"

    echo "→ Swapping icon..."
    cp "${BUILD_DIR}/gh-notify.icns" "${APP_DEST}/Contents/Resources/Terminal.icns"

    echo "→ Patching Info.plist..."
    /usr/libexec/PlistBuddy -c \
        "Set :CFBundleIdentifier com.joryeugene.gh-notify-notifier" \
        "${APP_DEST}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c \
        "Set :CFBundleName gh-notify" \
        "${APP_DEST}/Contents/Info.plist"

    echo "→ Ad-hoc signing..."
    codesign --force --deep --sign - "$APP_DEST"

    echo "→ Clearing quarantine..."
    xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

    echo "→ Triggering first-launch permission prompt..."
    open "$APP_DEST"
    sleep 2
    pkill -f "gh-notify-notifier" 2>/dev/null || true

    echo "✓  ${APP_DEST} ready"
    echo "   Check System Settings > Notifications > gh-notify and set style to Banners."

# Tag and push a release: lints, syncs locally, tags, pushes, prints release URL
# Prereq: CHANGELOG.md already updated for the version; commit all changes first
# Usage: just release 0.6.0
release version:
    @echo "→ Checking CHANGELOG.md has [{{version}}] entry..."
    @grep -q "\[{{version}}\]" CHANGELOG.md || { echo "✗  [{{version}}] not found in CHANGELOG.md — update it first"; exit 1; }
    @echo "→ Linting..."
    @just lint
    @echo "→ Syncing scripts to ~/.config/gh-notify/..."
    @just sync
    @echo "→ Tagging v{{version}}..."
    git tag -a "v{{version}}" -m "v{{version}}"
    git push origin main "v{{version}}"
    @echo "→ Draft release: https://github.com/joryeugene/gh-notify/releases/new?tag=v{{version}}"
