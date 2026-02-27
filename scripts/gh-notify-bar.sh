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

# ── spawn daemon (antifragile) ────────────────────────────────────────────────
_lock_pid() { cat "${STATE_DIR}/.daemon.lock/pid" 2>/dev/null; }

# Adopt existing healthy daemon rather than spawning a second one
_p=$(_lock_pid)
if [[ -n "$_p" ]] && kill -0 "$_p" 2>/dev/null; then
    DAEMON_PID=$_p
else
    bash "${HOME}/.config/gh-notify/gh-notify-daemon.sh" &
    DAEMON_PID=$!
    # Wait up to 2s — gives auth API calls time, and handles lock-race adoption
    _w=0
    while [[ $_w -lt 20 ]]; do
        sleep 0.1; (( _w++ )) || true
        kill -0 "$DAEMON_PID" 2>/dev/null && break
        # Daemon may have lost a lock race — adopt the winner
        _p=$(_lock_pid)
        if [[ -n "$_p" ]] && kill -0 "$_p" 2>/dev/null; then
            DAEMON_PID=$_p; break
        fi
    done
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        _last_err=$(grep "ERROR" "$EVENTS_LOG" 2>/dev/null | tail -1)
        printf '\033[1;31m  ERROR: daemon failed to start.\033[0m\n'
        [[ -n "$_last_err" ]] && printf '\033[1;31m  %s\033[0m\n' "$_last_err"
        sleep 3
        exit 1
    fi
fi

# ── cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    [[ -n "$DAEMON_PID" ]] && kill "$DAEMON_PID" 2>/dev/null || true
    tput cnorm 2>/dev/null || printf '\033[?25h'
}
trap cleanup EXIT SIGTERM SIGINT

# Hide cursor in the bar pane
tput civis 2>/dev/null || true

_status_msg=""

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
                *"🔁"*) printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"❌"*) printf '\033[1;31m%s\033[0m\n' "$_display" ;;
                *"🟢"*) printf '\033[1;32m%s\033[0m\n' "$_display" ;;
                *"⚙"*)  printf '\033[2m%s\033[0m\n'   "$_display" ;;
                *"⛔"*) printf '\033[0;31m%s\033[0m\n' "$_display" ;;
                *"👥"*) printf '\033[1;36m%s\033[0m\n' "$_display" ;;
                *"🔒"*) printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"🔓"*) printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"🛡"*)  printf '\033[1;35m%s\033[0m\n' "$_display" ;;
                *"🚦"*)  printf '\033[1;33m%s\033[0m\n' "$_display" ;;
                *"⏭️"*) printf '\033[2m%s\033[0m\n'   "$_display" ;;
                *)       printf '\033[2m%s\033[0m\n'   "$_display" ;;
            esac
        done < <(tail -16 "$EVENTS_LOG")
    else
        printf '\033[2m  Watching for GitHub notifications...\033[0m\n'
    fi

    # Daemon health check
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        printf '\033[1;33m  ⚠  daemon offline - press r to restart\033[0m\n'
    fi

    # Transient status message (shown once, then cleared)
    if [[ -n "$_status_msg" ]]; then
        printf '  \033[1m%s\033[0m\n' "$_status_msg"
        _status_msg=""
    fi

    # Separator + keybind hints
    local_sfx=$(cat "$SFX_STATE" 2>/dev/null || echo "ON")
    _count=$(grep -c '^\[' "$EVENTS_LOG" 2>/dev/null | tr -d ' '); _count="${_count:-0}"
    _cols=${COLUMNS:-$(tput cols 2>/dev/null)}
    (( ${_cols:-0} > 0 )) || _cols=80
    _label="·:·[ gh-notify · ${_count} ]·:·"
    _pad=$(( (_cols - ${#_label}) / 2 ))
    [[ $_pad -lt 0 ]] && _pad=0
    printf "%${_pad}s\033[2m·:·[\033[0m gh-notify · %s \033[2m]·:·\033[0m\n" "" "$_count"

    # Stats line: per-icon session totals + top repos (omitted when log is empty)
    if [[ -s "$EVENTS_LOG" ]]; then
        _cnt_merge=$(grep -c '🔀' "$EVENTS_LOG" 2>/dev/null)    || _cnt_merge=0
        _cnt_approve=$(grep -c '✅' "$EVENTS_LOG" 2>/dev/null)  || _cnt_approve=0
        _cnt_changes=$(grep -c '🔁' "$EVENTS_LOG" 2>/dev/null)  || _cnt_changes=0
        _cnt_approval=$(grep -c '🚦' "$EVENTS_LOG" 2>/dev/null) || _cnt_approval=0
        _cnt_comment=$(grep -c '💬' "$EVENTS_LOG" 2>/dev/null)  || _cnt_comment=0
        _cnt_fail=$(grep -c '❌' "$EVENTS_LOG" 2>/dev/null)     || _cnt_fail=0
        _cnt_pass=$(grep -c '🟢' "$EVENTS_LOG" 2>/dev/null)     || _cnt_pass=0
        _stats=""
        [[ "$_cnt_merge"    -gt 0 ]] && _stats+="🔀 ${_cnt_merge}  "
        [[ "$_cnt_approve"  -gt 0 ]] && _stats+="✅ ${_cnt_approve}  "
        [[ "$_cnt_changes"  -gt 0 ]] && _stats+="🔁 ${_cnt_changes}  "
        [[ "$_cnt_approval" -gt 0 ]] && _stats+="🚦 ${_cnt_approval}  "
        [[ "$_cnt_comment"  -gt 0 ]] && _stats+="💬 ${_cnt_comment}  "
        [[ "$_cnt_fail"     -gt 0 ]] && _stats+="❌ ${_cnt_fail}  "
        [[ "$_cnt_pass"     -gt 0 ]] && _stats+="🟢 ${_cnt_pass}  "
        _top_repos=$(grep -oE '\([^)]+/[^)]+\)' "$EVENTS_LOG" 2>/dev/null \
            | sed 's/[()]//g' | sort | uniq -c | sort -rn | head -3 \
            | awk '{printf "%s(%s) ", $2, $1}')
        if [[ -n "$_stats" || -n "$_top_repos" ]]; then
            _sline="  ${_stats}"
            [[ -n "$_top_repos" ]] && _sline+="│  ${_top_repos}"
            printf '\033[2m%s\033[0m\n' "$_sline"
        fi
    fi

    # Determine [o] label from last event URL type
    _open_label="open"
    _last_event=$(grep $'\t' "$EVENTS_LOG" 2>/dev/null | tail -1)
    if [[ "$_last_event" == *$'\t'* ]]; then
        case "$_last_event" in
            *"/actions"*) _open_label="CI"  ;;
            *"/pull/"*)   _open_label="PR"  ;;
            *)            _open_label="url" ;;
        esac
    fi

    printf '  \033[1m[s]\033[0msnd(%s)  \033[1m[c]\033[0mclr  \033[1m[r]\033[0mrst  \033[1m[o]\033[0m%s  \033[1m[t]\033[0mtest  \033[1m[q]\033[0mquit\n' \
        "$local_sfx" "$_open_label"

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
            _last=$(grep $'\t' "$EVENTS_LOG" 2>/dev/null | tail -1 || true)
            if [[ "$_last" == *$'\t'* ]]; then
                _url="${_last##*$'\t'}"
            else
                _url="https://github.com/notifications"
            fi
            open "$_url" 2>/dev/null || true
            ;;
        t|T)
            _custom="${HOME}/.config/gh-notify/gh-notify-notifier.app/Contents/MacOS/gh-notify-notifier"
            _targs=(-title "gh-notify" -message "Test notification from gh-notify")
            _sent=false
            if [[ -x "$_custom" ]]; then
                "$_custom" "${_targs[@]}" 2>/dev/null && _sent=true || true
            fi
            if ! $_sent; then
                osascript -e 'display notification "Test notification from gh-notify" with title "gh-notify"' 2>/dev/null && _sent=true || true
            fi
            if $_sent; then
                _status_msg="Test sent - check top-right corner"
            else
                open "x-apple.systempreferences:com.apple.preference.notifications" 2>/dev/null || true
                _status_msg="⚠  no notifier - opened System Settings > Notifications"
            fi
            ;;
        q|Q)
            break
            ;;
    esac
done
