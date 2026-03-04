#!/usr/bin/env bash
# demo-scenario.sh — Write sample events to events.log for demo recordings.
# Run this in the background, then launch gitbeacon to see events arrive live.
#
# Usage:
#   just sync                          # deploy scripts first
#   bash scripts/demo-scenario.sh &    # start event writer
#   gitbeacon                          # launch the bar
#
# Used by demo.tape (VHS) to produce assets/demo.gif.

set -euo pipefail

STATE_DIR="${HOME}/.config/gitbeacon"
EVENTS_LOG="${STATE_DIR}/events.log"
SFX_STATE="${STATE_DIR}/sfx-state"
LOCK_DIR="${STATE_DIR}/.daemon.lock"

mkdir -p "$STATE_DIR"

# ── stop any real daemon and take over the lock ─────────────────────────────
if [[ -d "$LOCK_DIR" ]]; then
    _existing=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [[ -n "$_existing" ]] && kill -0 "$_existing" 2>/dev/null; then
        kill "$_existing" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
fi

# ── clean slate ──────────────────────────────────────────────────────────────
: > "$EVENTS_LOG"
echo "ON" > "$SFX_STATE"

# ── fake daemon: sleep process whose PID the bar adopts ─────────────────────
cleanup() {
    [[ -n "${FAKE_PID:-}" ]] && kill "$FAKE_PID" 2>/dev/null || true
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

sleep 999 &
FAKE_PID=$!
mkdir -p "$LOCK_DIR"
echo "$FAKE_PID" > "$LOCK_DIR/pid"

# ── emit: write a 2-line event in the daemon's exact log_event format ───────
# Args: timestamp icon label repo title [url]
emit() {
    local ts="$1" icon="$2" label="$3" repo="$4" title="$5" url="${6:-}"
    if [[ -n "$url" ]]; then
        printf '[%s] %s %s  (%s)\t%s\n' "$ts" "$icon" "$label" "$repo" "$url" >> "$EVENTS_LOG"
    else
        printf '[%s] %s %s  (%s)\n' "$ts" "$icon" "$label" "$repo" >> "$EVENTS_LOG"
    fi
    printf '         %s\n' "$title" >> "$EVENTS_LOG"
}

# ── scenario: a PR lifecycle + a flaky CI episode ────────────────────────────
# Events arrive with delays so the bar picks them up on successive 2s refreshes.

sleep 2   # let the bar render "Watching for notifications..." first

emit "14:32" "👀" "Review requested" "acme/api-gateway" \
    "Add retry logic to payment handler" \
    "https://github.com/acme/api-gateway/pull/847"
sleep 1.5

emit "14:33" "💬" "PR comment" "acme/api-gateway" \
    "Looks good, one nit on error handling" \
    "https://github.com/acme/api-gateway/pull/847"
sleep 1.5

emit "14:35" "✅" "Approved by alice" "acme/api-gateway" \
    "Add retry logic to payment handler" \
    "https://github.com/acme/api-gateway/pull/847"
sleep 1.5

emit "14:36" "🟢" "CI passed" "acme/api-gateway" \
    "build / test (ubuntu-latest)" \
    "https://github.com/acme/api-gateway/actions"
sleep 1

emit "14:37" "🔀" "Merged" "acme/api-gateway" \
    "Add retry logic to payment handler" \
    "https://github.com/acme/api-gateway/pull/847"
sleep 2

emit "14:41" "❌" "CI failed" "acme/docs-site" \
    "Deploy preview failed" \
    "https://github.com/acme/docs-site/actions"
sleep 1.5

emit "14:43" "💬" "New comment" "acme/docs-site" \
    "Known flaky, re-running" \
    "https://github.com/acme/docs-site/pull/203"
sleep 1.5

emit "14:45" "🟢" "CI passed" "acme/docs-site" \
    "Deploy preview" \
    "https://github.com/acme/docs-site/actions"

# Keep the fake daemon alive until the bar exits and kills it
wait "$FAKE_PID" 2>/dev/null || true
