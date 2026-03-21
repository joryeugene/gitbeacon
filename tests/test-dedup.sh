#!/usr/bin/env bash
# test-dedup.sh - Verify notification dedup logic in gitbeacon-daemon.sh.
# Exercises the three dedup tiers + terminal-state secondary dedup.
#
# Usage: bash tests/test-dedup.sh
# Exit 0 = all pass, exit 1 = failures.

set -uo pipefail
# Note: set -e is intentionally omitted. The daemon functions were written without
# errexit and contain patterns like `[[ test ]] && { ... }` that return non-zero
# when the test is false. Enabling errexit would cause false failures.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DAEMON="$REPO_ROOT/scripts/gitbeacon-daemon.sh"

PASS=0
FAIL=0

# -- test runner ---------------------------------------------------------------

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        (( PASS++ )) || true
        printf '  PASS  %s\n' "$label"
    else
        (( FAIL++ )) || true
        printf '  FAIL  %s\n' "$label"
        printf '        expected: %s\n' "$expected"
        printf '        actual:   %s\n' "$actual"
    fi
}

# -- per-test setup ------------------------------------------------------------

setup() {
    TEST_DIR=$(mktemp -d)
    export STATE_DIR="$TEST_DIR"
    export EVENTS_LOG="$TEST_DIR/events.log"
    export SFX_STATE="$TEST_DIR/sfx-state"
    export SEEN_IDS="$TEST_DIR/seen-ids"
    touch "$EVENTS_LOG" "$SEEN_IDS"
    echo "ON" > "$SFX_STATE"

    # Batch state (reset per test like the daemon does per poll)
    BATCH_SOUNDS=""
    BATCH_COUNT=0
    BATCH_BEST_LABEL=""
    BATCH_BEST_REPO=""
    BATCH_BEST_TITLE=""

    # Stub: GH_TOKEN not needed since api_get is stubbed
    GH_TOKEN="test-token"
    SELF="testuser"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -- source daemon functions (helpers only, skip top-level init) ---------------

# Extract function definitions from the daemon script, starting at the helpers
# section (line with "# -- helpers") and stopping before the poll loop
# ("while true; do"). This skips top-level init (state dir, lock, auth) that
# would exit 0 when a daemon is already running.
FUNC_SOURCE=$(awk '/^# ── helpers/{found=1} found && /^while true; do$/{exit} found{print}' "$DAEMON")

# Override api_get to return controlled data instead of hitting GitHub.
# Tests set API_GET_RESPONSE before calling process_notification.
API_GET_RESPONSE=""
api_get_override='
api_get() {
    printf "%s" "$API_GET_RESPONSE"
}
'

# Override send_notification to be a no-op (no macOS popups during tests).
send_notification_override='
send_notification() { :; }
'

# Evaluate the daemon functions, then layer our stubs on top.
eval "$FUNC_SOURCE"
eval "$api_get_override"
eval "$send_notification_override"

# -- helpers -------------------------------------------------------------------

# Build a minimal GitHub notification JSON object.
make_notification() {
    local id="$1" reason="$2" title="$3" repo="$4" subj_url="$5" \
          subj_type="${6:-PullRequest}" updated_at="${7:-2026-03-20T12:00:00Z}" \
          latest_comment_url="${8:-}"

    printf '{"id":"%s","reason":"%s","subject":{"title":"%s","url":"%s","type":"%s","latest_comment_url":%s},"repository":{"full_name":"%s"},"updated_at":"%s"}' \
        "$id" "$reason" "$title" "$subj_url" "$subj_type" \
        "$(if [[ -n "$latest_comment_url" ]]; then printf '"%s"' "$latest_comment_url"; else printf 'null'; fi)" \
        "$repo" "$updated_at"
}

# Build a minimal PR API response.
make_pr_response() {
    local merged="${1:-false}" state="${2:-open}" html_url="${3:-https://github.com/org/repo/pull/1}"
    printf '{"merged":%s,"state":"%s","html_url":"%s"}' "$merged" "$state" "$html_url"
}

# Count how many times a label appears in events.log (header lines only).
count_events() {
    local label="$1"
    grep -c "$label" "$EVENTS_LOG" 2>/dev/null || echo 0
}

# -- tests ---------------------------------------------------------------------

echo "=== Terminal-state dedup: merged PR ==="
# CONTRACT: A merged PR logs exactly once, even when latest_comment_url changes.
# BUGS CAUGHT:
#   1. New comment on merged PR re-logs "Merged"
#   2. Different poll with same PR (updated_at bump) re-logs "Merged"
#   3. state_change reason also re-fires merge for same PR

setup

# First notification: PR is merged. Should log "Merged".
API_GET_RESPONSE=$(make_pr_response "true" "closed" "https://github.com/org/repo/pull/99")
notif=$(make_notification "111" "author" "feat: my PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/99" "PullRequest" \
    "2026-03-20T12:00:00Z" "https://api.github.com/repos/org/repo/issues/comments/100")
process_notification "$notif"
assert_eq "first merge logs event" "1" "$(count_events 'Merged')"

# Second notification: same PR, new comment URL (someone commented on the merged PR).
# Primary dedup passes (different comment URL), but terminal dedup should block.
BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "111" "author" "feat: my PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/99" "PullRequest" \
    "2026-03-20T12:05:00Z" "https://api.github.com/repos/org/repo/issues/comments/200")
process_notification "$notif"
assert_eq "second notification with new comment URL does NOT re-log Merged" "1" "$(count_events 'Merged')"

# Third notification: same PR, yet another comment URL.
BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "111" "author" "feat: my PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/99" "PullRequest" \
    "2026-03-20T12:10:00Z" "https://api.github.com/repos/org/repo/issues/comments/300")
process_notification "$notif"
assert_eq "third notification still does NOT re-log Merged" "1" "$(count_events 'Merged')"

teardown

echo ""
echo "=== Terminal-state dedup: different PR can still merge ==="
# CONTRACT: The terminal dedup is per-notification-ID, not global.

setup

API_GET_RESPONSE=$(make_pr_response "true" "closed" "https://github.com/org/repo/pull/99")
notif=$(make_notification "111" "author" "feat: PR one" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/99" "PullRequest" \
    "2026-03-20T12:00:00Z" "https://api.github.com/repos/org/repo/issues/comments/100")
process_notification "$notif"

BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
API_GET_RESPONSE=$(make_pr_response "true" "closed" "https://github.com/org/repo/pull/100")
notif=$(make_notification "222" "author" "feat: PR two" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/100" "PullRequest" \
    "2026-03-20T12:01:00Z" "https://api.github.com/repos/org/repo/issues/comments/500")
process_notification "$notif"
assert_eq "different PR merges independently" "2" "$(count_events 'Merged')"

teardown

echo ""
echo "=== Terminal-state dedup: comment reason on merged PR ==="
# CONTRACT: A "comment" notification on a merged PR logs "Merged" once, not on
# every subsequent comment. The comment reason calls _pr_state_event with
# no_fallback, but merged check fires before fallback logic.

setup

API_GET_RESPONSE=$(make_pr_response "true" "closed" "https://github.com/org/repo/pull/50")
notif=$(make_notification "333" "comment" "fix: something" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/50" "PullRequest" \
    "2026-03-20T14:00:00Z" "https://api.github.com/repos/org/repo/issues/comments/600")
process_notification "$notif"
assert_eq "comment on merged PR logs Merged once" "1" "$(count_events 'Merged')"

BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "333" "comment" "fix: something" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/50" "PullRequest" \
    "2026-03-20T14:05:00Z" "https://api.github.com/repos/org/repo/issues/comments/700")
process_notification "$notif"
assert_eq "second comment on merged PR does NOT re-log Merged" "1" "$(count_events 'Merged')"

teardown

echo ""
echo "=== Terminal-state dedup: closed issue ==="
# CONTRACT: A closed issue logs "Issue closed" exactly once.

setup

API_GET_RESPONSE='{"state":"closed","html_url":"https://github.com/org/repo/issues/10"}'
notif=$(make_notification "444" "author" "bug report" "org/repo" \
    "https://api.github.com/repos/org/repo/issues/10" "Issue" \
    "2026-03-20T15:00:00Z" "")
process_notification "$notif"
assert_eq "closed issue logs event" "1" "$(count_events 'Issue closed')"

BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "444" "author" "bug report" "org/repo" \
    "https://api.github.com/repos/org/repo/issues/10" "Issue" \
    "2026-03-20T15:05:00Z" "")
process_notification "$notif"
assert_eq "second notification does NOT re-log Issue closed" "1" "$(count_events 'Issue closed')"

teardown

echo ""
echo "=== Primary dedup: one-shot reasons use bare id ==="
# CONTRACT: review_requested, assign, etc. dedup on bare id.

setup

API_GET_RESPONSE=$(make_pr_response "false" "open" "https://github.com/org/repo/pull/5")
notif=$(make_notification "555" "review_requested" "review me" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/5" "PullRequest" \
    "2026-03-20T10:00:00Z" "https://api.github.com/repos/org/repo/issues/comments/800")
process_notification "$notif"
assert_eq "review_requested logs once" "1" "$(count_events 'Review requested')"

# Same id, different timestamp and comment URL. Bare-id dedup should block.
BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "555" "review_requested" "review me" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/5" "PullRequest" \
    "2026-03-20T10:30:00Z" "https://api.github.com/repos/org/repo/issues/comments/900")
process_notification "$notif"
assert_eq "review_requested with different timestamp still blocked" "1" "$(count_events 'Review requested')"

teardown

echo ""
echo "=== Primary dedup: content-update reasons use latest_comment_url ==="
# CONTRACT: comment reason fires on new comment URL, blocks on same URL.

setup

API_GET_RESPONSE=$(make_pr_response "false" "open" "https://github.com/org/repo/pull/7")
# Stub reviews endpoint to return empty array (no approvals/changes)
eval 'api_get() {
    if [[ "$1" == *"/reviews" ]]; then
        printf "[]"
    else
        printf "%s" "$API_GET_RESPONSE"
    fi
}'

notif=$(make_notification "666" "comment" "discuss PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/7" "PullRequest" \
    "2026-03-20T11:00:00Z" "https://api.github.com/repos/org/repo/issues/comments/1000")
process_notification "$notif"
assert_eq "comment fires on first URL" "1" "$(count_events 'PR comment')"

# Same comment URL, different timestamp. Should be blocked.
BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "666" "comment" "discuss PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/7" "PullRequest" \
    "2026-03-20T11:05:00Z" "https://api.github.com/repos/org/repo/issues/comments/1000")
process_notification "$notif"
assert_eq "same comment URL blocked" "1" "$(count_events 'PR comment')"

# New comment URL. Should fire.
BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "666" "comment" "discuss PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/7" "PullRequest" \
    "2026-03-20T11:10:00Z" "https://api.github.com/repos/org/repo/issues/comments/2000")
process_notification "$notif"
assert_eq "new comment URL fires" "2" "$(count_events 'PR comment')"

teardown

# Restore api_get override for remaining tests
eval "$api_get_override"

echo ""
echo "=== state_change reason: Merged deduped by terminal check ==="
# CONTRACT: state_change with updated_at bump does not re-log Merged.

setup

API_GET_RESPONSE=$(make_pr_response "true" "closed" "https://github.com/org/repo/pull/20")
notif=$(make_notification "777" "state_change" "state changed PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/20" "PullRequest" \
    "2026-03-20T16:00:00Z" "")
process_notification "$notif"
assert_eq "state_change Merged logs once" "1" "$(count_events 'Merged')"

# Same notification, updated_at bumped. Primary dedup passes (tier 3), terminal blocks.
BATCH_SOUNDS=""; BATCH_COUNT=0; BATCH_BEST_LABEL=""
notif=$(make_notification "777" "state_change" "state changed PR" "org/repo" \
    "https://api.github.com/repos/org/repo/pulls/20" "PullRequest" \
    "2026-03-20T16:05:00Z" "")
process_notification "$notif"
assert_eq "state_change with bumped timestamp does NOT re-log Merged" "1" "$(count_events 'Merged')"

teardown

# -- summary -------------------------------------------------------------------

echo ""
echo "==================================="
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
echo "==================================="

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
