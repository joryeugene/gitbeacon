#!/usr/bin/env bash
# gh-notify-bar.sh — Interactive bottom bar showing live GitHub PR notifications.
# Spawns the daemon, displays event log, handles [s]ound / [c]lear / [q]uit.
#
# Layout: inline-header separator, event color, auto-sized to tput cols
# Keybinds: [s] toggle sound  [c] clear log  [r] restart daemon  [q] quit

export TERM="${TERM:-xterm-256color}"

STATE_DIR="${HOME}/.config/gh-notify"
EVENTS_LOG="${STATE_DIR}/events.log"
SFX_STATE="${STATE_DIR}/sfx-state"
DAEMON_PID=""

# ── init state ────────────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR"
[[ -f "$SFX_STATE" ]] || echo "ON" > "$SFX_STATE"
touch "$EVENTS_LOG"

# ── spawn daemon ──────────────────────────────────────────────────────────────
bash "${HOME}/.config/gh-notify/gh-notify-daemon.sh" &
DAEMON_PID=$!
sleep 0.2
if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    printf '\033[1;31m  ERROR: daemon failed to start. Run: gh auth status\033[0m\n'
    sleep 3
    exit 1
fi

# ── cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    [[ -n "$DAEMON_PID" ]] && kill "$DAEMON_PID" 2>/dev/null || true
    tput cnorm 2>/dev/null || printf '\033[?25h'
}
trap cleanup EXIT SIGTERM SIGINT

# Hide cursor in the bar pane
tput civis 2>/dev/null || true

# ── display loop ──────────────────────────────────────────────────────────────
while true; do
    # Move to top of pane and clear
    tput cup 0 0 2>/dev/null || printf '\033[H'
    tput ed 2>/dev/null || printf '\033[J'

    # Show last 8 events (or placeholder if log is empty)
    if [[ -s "$EVENTS_LOG" ]]; then
        while IFS= read -r _line; do
            _display="${_line%%$'\t'*}"
            case "$_display" in
                *"✅"*) printf '\033[1;32m%s\033[0m\n' "$_display" ;;
                *"🔀"*) printf '\033[1;35m%s\033[0m\n' "$_display" ;;
                *"💬"*) printf '\033[1;36m%s\033[0m\n' "$_display" ;;
                *"👀"*) printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"📌"*) printf '\033[1;34m%s\033[0m\n' "$_display" ;;
                *"⚠"*)  printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"❌"*) printf '\033[1;31m%s\033[0m\n' "$_display" ;;
                *"🟢"*) printf '\033[1;32m%s\033[0m\n' "$_display" ;;
                *"⚙"*)  printf '\033[2m%s\033[0m\n'   "$_display" ;;
                *"⛔"*) printf '\033[0;31m%s\033[0m\n' "$_display" ;;
                *"👥"*) printf '\033[1;36m%s\033[0m\n' "$_display" ;;
                *"🔒"*) printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"🔓"*) printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"🛡"*)  printf '\033[1;35m%s\033[0m\n' "$_display" ;;
                *)       printf '\033[2m%s\033[0m\n'   "$_display" ;;
            esac
        done < <(tail -8 "$EVENTS_LOG")
    else
        printf '\033[2m  Watching for GitHub notifications...\033[0m\n'
    fi

    # Daemon health check
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        printf '\033[1;33m  ⚠  daemon offline - press r to restart\033[0m\n'
    fi

    # Inline-header separator + keybind hints
    local_sfx=$(cat "$SFX_STATE" 2>/dev/null || echo "ON")
    _cols=$(tput cols 2>/dev/null || echo 80)
    _count=$(tail -8 "$EVENTS_LOG" 2>/dev/null | grep -c . || echo 0)
    _mid=" gh-notify ─ ${_count} "
    _left=20
    _right=$(( _cols - _left - ${#_mid} ))
    [[ $_right -lt 0 ]] && _right=0
    printf '\033[2m'
    _i=0; while [[ $_i -lt $_left ]]; do printf '─'; (( _i++ )); done
    printf '\033[0m%s\033[2m' "$_mid"
    _i=0; while [[ $_i -lt $_right ]]; do printf '─'; (( _i++ )); done
    printf '\033[0m\n'
    printf '  \033[1m[s]\033[0m sound \033[1m(%s)\033[0m  \033[1m[c]\033[0m clear  \033[1m[r]\033[0m restart  \033[1m[o]\033[0m open  \033[1m[q]\033[0m quit\n' "$local_sfx"

    # Read a single keypress (2s timeout, no echo)
    key=""
    IFS= read -rs -t 2 -n 1 key 2>/dev/null || true

    case "$key" in
        s|S)
            current=$(cat "$SFX_STATE" 2>/dev/null || echo "ON")
            if [[ "$current" == "ON" ]]; then
                echo "OFF" > "$SFX_STATE"
            else
                echo "ON" > "$SFX_STATE"
            fi
            ;;
        c|C)
            : > "$EVENTS_LOG"
            ;;
        r|R)
            pkill -f gh-notify-daemon 2>/dev/null || true
            # Wait for old daemon's EXIT trap to release the lock (max 3s)
            _w=0
            while [[ -d "${STATE_DIR}/.daemon.lock" && $_w -lt 30 ]]; do
                sleep 0.1
                (( _w++ )) || true
            done
            bash "${HOME}/.config/gh-notify/gh-notify-daemon.sh" &
            DAEMON_PID=$!
            ;;
        o|O)
            _last=$(tail -1 "$EVENTS_LOG" 2>/dev/null || true)
            if [[ "$_last" == *$'\t'* ]]; then
                _url="${_last##*$'\t'}"
            else
                _url="https://github.com/notifications"
            fi
            open "$_url" 2>/dev/null || true
            ;;
        q|Q)
            break
            ;;
    esac
done
