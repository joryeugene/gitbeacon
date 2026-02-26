#!/usr/bin/env bash
# gh-notify installer
# Installs background GitHub notification daemon + tmux bar for macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/joryeugene/gh-notify/main/install.sh | bash
#   # or from local clone:
#   ./install.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "  ${BLUE}--${RESET} $*"; }
ok()    { echo -e "  ${GREEN}✓${RESET}  $*"; }
warn()  { echo -e "  ${YELLOW}!${RESET}  $*"; }
die()   { echo -e "  ${RED}✗${RESET}  $*"; exit 1; }

STATE_DIR="${HOME}/.config/gh-notify"
GITHUB_RAW="https://raw.githubusercontent.com/joryeugene/gh-notify/main"

# Detect local vs remote execution (empty BASH_SOURCE[0] when piped through bash)
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    IS_REMOTE=false
else
    IS_REMOTE=true
    SCRIPT_DIR=""
fi

echo
echo -e "${BOLD}gh-notify installer${RESET}"
echo

# -------------------------------------------------------------------
# 1. Check prerequisites
# -------------------------------------------------------------------
info "Checking prerequisites..."
echo

FAIL=0

if command -v gh &>/dev/null; then
    ok "gh CLI found: $(gh --version | head -1)"
else
    warn "gh CLI not found. Install: brew install gh"
    FAIL=1
fi

if command -v jq &>/dev/null; then
    ok "jq found: $(jq --version)"
else
    warn "jq not found. Install: brew install jq"
    FAIL=1
fi

if command -v tmux &>/dev/null; then
    ok "tmux found: $(tmux -V)"
else
    warn "tmux not found. Install: brew install tmux"
    FAIL=1
fi

if command -v osascript &>/dev/null; then
    ok "osascript found (macOS confirmed)"
else
    die "osascript not found. gh-notify requires macOS for notifications and sounds."
fi

if command -v clang &>/dev/null; then
    ok "clang found (needed to build GH Notifier app)"
else
    warn "clang not found — GH Notifier app won't build. Install CLT: xcode-select --install"
fi

if [[ "$FAIL" -eq 1 ]]; then
    echo
    die "Missing prerequisites above. Install them and re-run."
fi

echo

# -------------------------------------------------------------------
# 2. Copy scripts to ~/.config/gh-notify/
# -------------------------------------------------------------------
info "Installing scripts to ${STATE_DIR}..."

mkdir -p "$STATE_DIR"

if [[ "$IS_REMOTE" == "true" ]]; then
    info "Remote install — downloading scripts from GitHub..."
    curl -fsSL "${GITHUB_RAW}/scripts/gh-notify-daemon.sh" -o "${STATE_DIR}/gh-notify-daemon.sh" || die "Download failed"
    curl -fsSL "${GITHUB_RAW}/scripts/gh-notify-bar.sh"    -o "${STATE_DIR}/gh-notify-bar.sh"    || die "Download failed"
else
    [[ -d "${SCRIPT_DIR}/scripts" ]] || die "scripts/ not found. Run from the gh-notify repo root."
    cp "${SCRIPT_DIR}/scripts/gh-notify-daemon.sh" "${STATE_DIR}/gh-notify-daemon.sh"
    cp "${SCRIPT_DIR}/scripts/gh-notify-bar.sh"    "${STATE_DIR}/gh-notify-bar.sh"
fi
chmod +x "${STATE_DIR}/gh-notify-daemon.sh" "${STATE_DIR}/gh-notify-bar.sh"

ok "Copied gh-notify-daemon.sh"
ok "Copied gh-notify-bar.sh"

# If a bar is already running, kill it so it picks up the new scripts on next launch
if pgrep -f gh-notify-bar &>/dev/null; then
    pkill -f gh-notify-bar 2>/dev/null || true
    ok "Stopped running bar — relaunch with: gh-notify"
fi

# Init state files (idempotent)
[[ -f "${STATE_DIR}/sfx-state" ]] || echo "ON" > "${STATE_DIR}/sfx-state"
touch "${STATE_DIR}/events.log" "${STATE_DIR}/seen-ids"

ok "State directory ready: ${STATE_DIR}"
echo

# -------------------------------------------------------------------
# 3. Install gh-notify CLI command
# -------------------------------------------------------------------
info "Installing gh-notify command..."

BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

cat > "${BIN_DIR}/gh-notify" << 'EOF'
#!/usr/bin/env bash
exec bash "${HOME}/.config/gh-notify/gh-notify-bar.sh" "$@"
EOF
chmod +x "${BIN_DIR}/gh-notify"

ok "Installed: ${BIN_DIR}/gh-notify"

# Warn if ~/.local/bin not in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qF "$BIN_DIR"; then
    # shellcheck disable=SC2088  # intentional: display string, not expansion
    warn "~/.local/bin is not in your PATH. Add to ~/.zshrc:"
    warn "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
fi

echo

# -------------------------------------------------------------------
# 3.5. Build custom notifier bundle (gh-notify-notifier.app)
# -------------------------------------------------------------------
info "Building gh-notify notifier app (KingBee icon)..."

APP_DEST="${STATE_DIR}/gh-notify-notifier.app"
NOTIFIER_BUNDLE_ID="com.joryeugene.gh-notify"
_skip_notifier=false

# Idempotent: skip if already built with our bundle ID, display name, AND ObjC binary
if [[ -d "$APP_DEST" ]]; then
    _existing_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "${APP_DEST}/Contents/Info.plist" 2>/dev/null || true)
    _existing_display=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" \
        "${APP_DEST}/Contents/Info.plist" 2>/dev/null || true)
    _existing_exec=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
        "${APP_DEST}/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$_existing_id" == "$NOTIFIER_BUNDLE_ID" ]] && \
       [[ "$_existing_display" == "GH Notifier" ]] && \
       [[ "$_existing_exec" == "gh-notify-notifier" ]] && \
       [[ -x "${APP_DEST}/Contents/MacOS/gh-notify-notifier" ]]; then
        ok "Notifier app already built — skipping"
        _skip_notifier=true
    fi
fi

# Need rsvg-convert to render the SVG icon
if ! $_skip_notifier && ! command -v rsvg-convert &>/dev/null; then
    warn "rsvg-convert not found — skipping notifier build"
    warn "Install with: brew install librsvg  then run: just build-notifier"
    _skip_notifier=true
fi

# Get source files
if ! $_skip_notifier; then
    BUILD_DIR="${STATE_DIR}/.build"
    mkdir -p "$BUILD_DIR"
    _src_m=""
    _src_plist=""
    if [[ "$IS_REMOTE" == "true" ]]; then
        info "Downloading notifier sources..."
        if ! curl -fsSL "${GITHUB_RAW}/scripts/gh-notify-notifier.m" \
                -o "${BUILD_DIR}/gh-notify-notifier.m" 2>/dev/null; then
            warn "Source download failed — skipping notifier build. Run: just build-notifier"
            _skip_notifier=true
        else
            _src_m="${BUILD_DIR}/gh-notify-notifier.m"
        fi
        if ! curl -fsSL "${GITHUB_RAW}/scripts/gh-notify-notifier.plist" \
                -o "${BUILD_DIR}/gh-notify-notifier.plist" 2>/dev/null; then
            warn "Plist download failed — skipping notifier build. Run: just build-notifier"
            _skip_notifier=true
        else
            _src_plist="${BUILD_DIR}/gh-notify-notifier.plist"
        fi
    else
        if [[ -f "${SCRIPT_DIR}/scripts/gh-notify-notifier.m" ]]; then
            _src_m="${SCRIPT_DIR}/scripts/gh-notify-notifier.m"
        else
            warn "scripts/gh-notify-notifier.m not found — skipping notifier build. Run: just build-notifier"
            _skip_notifier=true
        fi
        if [[ -f "${SCRIPT_DIR}/scripts/gh-notify-notifier.plist" ]]; then
            _src_plist="${SCRIPT_DIR}/scripts/gh-notify-notifier.plist"
        else
            warn "scripts/gh-notify-notifier.plist not found — skipping notifier build. Run: just build-notifier"
            _skip_notifier=true
        fi
    fi
fi

# Get the SVG source icon
if ! $_skip_notifier; then
    _svg="${BUILD_DIR}/icon.svg"
    if [[ "$IS_REMOTE" == "true" ]]; then
        info "Downloading icon SVG..."
        if ! curl -fsSL "${GITHUB_RAW}/assets/icon.svg" -o "$_svg" 2>/dev/null; then
            warn "SVG download failed — skipping notifier build. Run: just build-notifier"
            _skip_notifier=true
        fi
    else
        if [[ -f "${SCRIPT_DIR}/assets/icon.svg" ]]; then
            cp "${SCRIPT_DIR}/assets/icon.svg" "$_svg"
        else
            warn "assets/icon.svg not found — skipping notifier build. Run: just build-notifier"
            _skip_notifier=true
        fi
    fi
fi

# Render SVG → 1024×1024 PNG
if ! $_skip_notifier; then
    info "Rendering icon SVG..."
    if ! rsvg-convert -w 1024 -h 1024 "${BUILD_DIR}/icon.svg" \
            -o "${BUILD_DIR}/icon-1024.png" 2>/dev/null; then
        warn "SVG render failed — skipping notifier build. Run: just build-notifier"
        _skip_notifier=true
    fi
fi

# Build .iconset → .icns
if ! $_skip_notifier; then
    info "Building iconset..."
    ICONSET="${BUILD_DIR}/gh-notify.iconset"
    mkdir -p "$ICONSET"
    for _sz in 16 32 64 128 256 512 1024; do
        sips -z "$_sz" "$_sz" "${BUILD_DIR}/icon-1024.png" \
            --out "${ICONSET}/icon_${_sz}x${_sz}.png" &>/dev/null
    done
    cp "${ICONSET}/icon_32x32.png"     "${ICONSET}/icon_16x16@2x.png"
    cp "${ICONSET}/icon_64x64.png"     "${ICONSET}/icon_32x32@2x.png"
    cp "${ICONSET}/icon_256x256.png"   "${ICONSET}/icon_128x128@2x.png"
    cp "${ICONSET}/icon_512x512.png"   "${ICONSET}/icon_256x256@2x.png"
    cp "${ICONSET}/icon_1024x1024.png" "${ICONSET}/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" --output "${BUILD_DIR}/gh-notify.icns"
fi

# Compile ObjC notification binary
if ! $_skip_notifier; then
    info "Compiling notifier binary..."
    if ! clang -fobjc-arc \
            -framework AppKit \
            -framework UserNotifications \
            -target arm64-apple-macosx14.0 \
            -o "${BUILD_DIR}/gh-notify-notifier" \
            "$_src_m" 2>/dev/null; then
        warn "Compile failed — skipping notifier build. Run: just build-notifier"
        _skip_notifier=true
    fi
fi

# Assemble fresh .app bundle
if ! $_skip_notifier; then
    info "Assembling app bundle..."
    rm -rf "$APP_DEST"
    mkdir -p "${APP_DEST}/Contents/MacOS"
    mkdir -p "${APP_DEST}/Contents/Resources"
    cp "${BUILD_DIR}/gh-notify-notifier" "${APP_DEST}/Contents/MacOS/gh-notify-notifier"
    chmod +x "${APP_DEST}/Contents/MacOS/gh-notify-notifier"
    cp "${BUILD_DIR}/gh-notify.icns" "${APP_DEST}/Contents/Resources/gh-notify.icns"
    cp "$_src_plist" "${APP_DEST}/Contents/Info.plist"

    info "Ad-hoc signing..."
    codesign --force --deep --sign - "$APP_DEST" 2>/dev/null || true

    info "Clearing quarantine..."
    xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

    info "Flushing icon cache..."
    touch "$APP_DEST"
    killall iconservicesagent 2>/dev/null || true
    _ICON_STORE="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.iconservices/store.index"
    [[ -f "$_ICON_STORE" ]] && rm -f "$_ICON_STORE" || true
    _LSR="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    [[ -x "$_LSR" ]] && "$_LSR" -f "$APP_DEST" 2>/dev/null || true
    launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui" 2>/dev/null || true
    sleep 2

    info "Resetting stale notification center registration..."
    launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui" 2>/dev/null || true
    sleep 1
    _nc_prefs="${HOME}/Library/Preferences/com.apple.ncprefs.plist"
    _nc_count=$(/usr/libexec/PlistBuddy -c "Print :apps" "$_nc_prefs" 2>/dev/null \
        | grep -c "Dict {" || true)
    for _ni in $(seq 0 $(( _nc_count - 1 ))); do
        _nb=$(/usr/libexec/PlistBuddy -c "Print :apps:${_ni}:bundle-id" \
            "$_nc_prefs" 2>/dev/null || true)
        if [[ "$_nb" == "$NOTIFIER_BUNDLE_ID" ]]; then
            /usr/libexec/PlistBuddy -c "Delete :apps:${_ni}" "$_nc_prefs" 2>/dev/null || true
            break
        fi
    done
    launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui" 2>/dev/null || true
    sleep 1

    info "Triggering first-launch permission prompt..."
    open -n -W "$APP_DEST" --args \
        -title "GH Notifier" \
        -message "Allow notifications — click Allow in the dialog above" \
        2>/dev/null || true

    ok "Notifier app built: ${APP_DEST}"
    info "Check System Settings > Notifications > GH Notifier → set style to Banners"
fi

echo

# -------------------------------------------------------------------
# 4. Verify
# -------------------------------------------------------------------
info "Verifying installation..."
echo

VFAIL=0

# Check daemon script is executable
if [[ -x "${STATE_DIR}/gh-notify-daemon.sh" ]]; then
    ok "gh-notify-daemon.sh is executable"
else
    warn "gh-notify-daemon.sh is not executable"
    VFAIL=1
fi

# Check bar script is executable
if [[ -x "${STATE_DIR}/gh-notify-bar.sh" ]]; then
    ok "gh-notify-bar.sh is executable"
else
    warn "gh-notify-bar.sh is not executable"
    VFAIL=1
fi

# Check gh auth
if gh auth status &>/dev/null; then
    ok "gh auth: authenticated"
else
    warn "gh auth: not authenticated. Run: gh auth login"
    VFAIL=1
fi

# Send test notification — check delivery and open System Settings if denied
_custom="${STATE_DIR}/gh-notify-notifier.app/Contents/MacOS/gh-notify-notifier"
if [[ -x "$_custom" ]]; then
    if "$_custom" -title "GH Notifier" \
            -message "If you see this, notifications are working!" 2>/dev/null; then
        ok "macOS notifications: GH Notifier — banner delivered"
    else
        warn "GH Notifier notifications are off or not yet permitted"
        info "Opening System Settings > Notifications..."
        open "x-apple.systempreferences:com.apple.preference.notifications" 2>/dev/null || true
        info "Find GH Notifier and set style to Banners or Alerts, then press [t] in the bar to confirm"
        VFAIL=1
    fi
else
    osascript -e 'display notification "Notifications working!" with title "GH Notifier"' 2>/dev/null || true
    ok "macOS notifications: osascript fallback"
fi

echo

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
if [[ "$VFAIL" -eq 0 ]]; then
    echo -e "${BOLD}Installation complete!${RESET}"
    echo
    echo -e "  ${DIM}Test a sound:   afplay /System/Library/Sounds/Glass.aiff${RESET}"
    echo -e "  ${DIM}Test a popup:   osascript -e 'display notification \"Ready\" with title \"gh-notify\"'${RESET}"
    echo -e "  ${DIM}Launch:         gh-notify${RESET}"
else
    warn "Installation completed with warnings above."
    echo -e "  ${DIM}Run manual checks to resolve issues.${RESET}"
fi
echo
