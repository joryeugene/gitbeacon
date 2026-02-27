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

# Send a test notification with custom text
# Usage: just notify "your message here"
notify msg:
    #!/usr/bin/env bash
    set -euo pipefail
    _custom="${HOME}/.config/gh-notify/gh-notify-notifier.app/Contents/MacOS/gh-notify-notifier"
    _sent=false
    if [[ -x "$_custom" ]]; then
        "$_custom" -title "gh-notify" -message "{{msg}}" 2>/dev/null && _sent=true || true
    fi
    if ! $_sent; then
        osascript -e "display notification \"{{msg}}\" with title \"gh-notify\"" 2>/dev/null && _sent=true || true
    fi
    if $_sent; then
        echo "✓  notification sent"
    else
        open "x-apple.systempreferences:com.apple.preference.notifications" 2>/dev/null || true
        echo "✗  no notifier found — opened System Settings > Notifications"
    fi

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

# Build a custom gh-notify-notifier.app with KingBee icon.
# Compiles a minimal ObjC notification binary and bundles it with our icon + bundle ID
# so the left-side app icon in macOS notifications shows the bee, not terminal-notifier's tree.
#
# Prereqs: clang (Xcode CLT), sips, iconutil, codesign, PlistBuddy (built-in macOS)
#          + rsvg-convert (brew install librsvg)
# One-time after build: macOS will prompt for notification permission on first use.
build-notifier:
    #!/usr/bin/env bash
    set -euo pipefail

    [[ -f "assets/icon.svg" ]] || { echo "✗  assets/icon.svg not found — run from repo root"; exit 1; }
    [[ -f "scripts/gh-notify-notifier.m" ]] || { echo "✗  scripts/gh-notify-notifier.m not found"; exit 1; }
    [[ -f "scripts/gh-notify-notifier.plist" ]] || { echo "✗  scripts/gh-notify-notifier.plist not found"; exit 1; }
    command -v clang &>/dev/null || { echo "✗  clang not found — install CLT: xcode-select --install"; exit 1; }
    command -v rsvg-convert &>/dev/null || { echo "✗  rsvg-convert not found — run: brew install librsvg"; exit 1; }

    STATE_DIR="${HOME}/.config/gh-notify"
    BUILD_DIR="${STATE_DIR}/.build"
    APP_DEST="${STATE_DIR}/gh-notify-notifier.app"

    mkdir -p "$BUILD_DIR"

    echo "→ Rendering icon SVG → PNG..."
    rsvg-convert -w 1024 -h 1024 assets/icon.svg -o "${BUILD_DIR}/icon-1024.png"

    echo "→ Building iconset..."
    ICONSET="${BUILD_DIR}/gh-notify.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512 1024; do
        sips -z "$size" "$size" "${BUILD_DIR}/icon-1024.png" \
            --out "${ICONSET}/icon_${size}x${size}.png" &>/dev/null
    done
    cp "${ICONSET}/icon_32x32.png"     "${ICONSET}/icon_16x16@2x.png"
    cp "${ICONSET}/icon_64x64.png"     "${ICONSET}/icon_32x32@2x.png"
    cp "${ICONSET}/icon_256x256.png"   "${ICONSET}/icon_128x128@2x.png"
    cp "${ICONSET}/icon_512x512.png"   "${ICONSET}/icon_256x256@2x.png"
    cp "${ICONSET}/icon_1024x1024.png" "${ICONSET}/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" --output "${BUILD_DIR}/gh-notify.icns"

    echo "→ Compiling notifier binary..."
    clang -fobjc-arc \
        -framework AppKit \
        -framework UserNotifications \
        -target arm64-apple-macosx14.0 \
        -o "${BUILD_DIR}/gh-notify-notifier" \
        scripts/gh-notify-notifier.m

    echo "→ Assembling app bundle..."
    rm -rf "$APP_DEST"
    mkdir -p "${APP_DEST}/Contents/MacOS"
    mkdir -p "${APP_DEST}/Contents/Resources"
    cp "${BUILD_DIR}/gh-notify-notifier" "${APP_DEST}/Contents/MacOS/gh-notify-notifier"
    chmod +x "${APP_DEST}/Contents/MacOS/gh-notify-notifier"
    cp "${BUILD_DIR}/gh-notify.icns" "${APP_DEST}/Contents/Resources/gh-notify.icns"
    cp scripts/gh-notify-notifier.plist "${APP_DEST}/Contents/Info.plist"

    echo "→ Ad-hoc signing..."
    codesign --force --deep --sign - "$APP_DEST"

    echo "→ Clearing quarantine..."
    xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

    echo "→ Flushing icon cache..."
    touch "$APP_DEST"
    killall iconservicesagent 2>/dev/null || true
    _ICON_STORE="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.iconservices/store.index"
    [[ -f "$_ICON_STORE" ]] && rm -f "$_ICON_STORE" || true
    _LSR="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    [[ -x "$_LSR" ]] && "$_LSR" -f "$APP_DEST" 2>/dev/null || true
    launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui" 2>/dev/null || true
    sleep 2

    echo "→ Resetting stale notification center registration..."
    launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui" 2>/dev/null || true
    sleep 1
    _nc_prefs="${HOME}/Library/Preferences/com.apple.ncprefs.plist"
    _nc_count=$(/usr/libexec/PlistBuddy -c "Print :apps" "$_nc_prefs" 2>/dev/null \
        | grep -c "Dict {" || true)
    for _ni in $(seq 0 $(( _nc_count - 1 ))); do
        _nb=$(/usr/libexec/PlistBuddy -c "Print :apps:${_ni}:bundle-id" \
            "$_nc_prefs" 2>/dev/null || true)
        if [[ "$_nb" == "com.joryeugene.gh-notify" ]]; then
            /usr/libexec/PlistBuddy -c "Delete :apps:${_ni}" "$_nc_prefs" 2>/dev/null || true
            break
        fi
    done
    launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui" 2>/dev/null || true
    sleep 1

    echo "→ Triggering first-launch permission prompt..."
    open -n -W "$APP_DEST" --args \
        -title "GH Notifier" \
        -message "Allow notifications — click Allow in the dialog above" \
        2>/dev/null || true

    echo "✓  ${APP_DEST} ready"
    echo "   Check System Settings > Notifications > GH Notifier and set style to Banners."

# Tag and push a release: lints, syncs locally, tags, pushes, creates draft GitHub release
# Prereq: CHANGELOG.md already updated for the version; commit all changes first
# Usage: just release 0.6.0
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ Checking CHANGELOG.md has [{{version}}] entry..."
    grep -q "\[{{version}}\]" CHANGELOG.md \
        || { echo "✗  [{{version}}] not found in CHANGELOG.md — update it first"; exit 1; }
    echo "→ Linting..."
    just lint
    echo "→ Syncing scripts to ~/.config/gh-notify/..."
    just sync
    echo "→ Tagging v{{version}}..."
    git tag -a "v{{version}}" -m "v{{version}}"
    git push origin main "v{{version}}"
    echo "→ Creating draft release on GitHub..."
    NOTES=$(awk '/^## \[{{version}}\]/{found=1; next} found && /^---/{exit} found{print}' CHANGELOG.md)
    gh release create "v{{version}}" --title "v{{version}}" --draft --notes "$NOTES"
    echo "✓  Draft release ready: https://github.com/joryeugene/gh-notify/releases"
