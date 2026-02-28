#!/usr/bin/env bash
# gh-notify-daemon.sh — Background GitHub notification watcher.
# Polls /notifications every 30s with If-Modified-Since conditional requests.
# Fires macOS popups + sounds per event type, appends to events.log.
#
# State: ~/.config/gh-notify/{events.log,sfx-state,seen-ids}
# Started by: gh-notify-bar.sh

STATE_DIR="${HOME}/.config/gh-notify"
EVENTS_LOG="${STATE_DIR}/events.log"
SFX_STATE="${STATE_DIR}/sfx-state"
SEEN_IDS="${STATE_DIR}/seen-ids"

# ── init state dir ────────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR"
[[ -f "$SFX_STATE" ]] || echo "ON" > "$SFX_STATE"
touch "$EVENTS_LOG" "$SEEN_IDS"

# Migrate seen-ids: v0.9.1→v0.10 changed format from bare id to id|updated_at.
# Old entries can never match, so truncate if any old-format lines detected.
if [[ -s "$SEEN_IDS" ]] && grep -qv '|' "$SEEN_IDS" 2>/dev/null; then
    : > "$SEEN_IDS"
fi
[[ -s "$SEEN_IDS" ]] && sort -u -o "$SEEN_IDS" "$SEEN_IDS"

# ── prevent duplicate instances ───────────────────────────────────────────────
LOCK_FILE="${STATE_DIR}/.daemon.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    _lock_pid=$(cat "$LOCK_FILE/pid" 2>/dev/null)
    if [[ -n "$_lock_pid" ]] && kill -0 "$_lock_pid" 2>/dev/null; then
        exit 0  # healthy daemon already running
    fi
    # stale lock — reclaim it
    rm -f "$LOCK_FILE/pid"
    rmdir "$LOCK_FILE" 2>/dev/null || true
    mkdir "$LOCK_FILE" || exit 0
fi
echo $$ > "$LOCK_FILE/pid"
trap 'rm -f "$LOCK_FILE/pid"; rmdir "$LOCK_FILE" 2>/dev/null || true' EXIT

# ── resolve identity + auth ───────────────────────────────────────────────────
GH_TOKEN=$(gh auth token 2>/dev/null) || {
    echo "[$(date +%H:%M)] ERROR: gh auth token failed - run: gh auth login" >> "$EVENTS_LOG"
    exit 1
}
SELF=$(gh api /user --jq '.login' 2>/dev/null) || {
    echo "[$(date +%H:%M)] ERROR: gh api /user failed" >> "$EVENTS_LOG"
    exit 1
}

# ── helpers ───────────────────────────────────────────────────────────────────
send_notification() {
    local title="$1" subtitle="$2" message="$3"
    title="${title//\\/\\\\}"; title="${title//\"/\\\"}"
    subtitle="${subtitle//\\/\\\\}"; subtitle="${subtitle//\"/\\\"}"
    message="${message//\\/\\\\}"; message="${message//\"/\\\"}"
    local _custom="${STATE_DIR}/gh-notify-notifier.app/Contents/MacOS/gh-notify-notifier"
    local _sent=false
    local _args=(-title "$title" -subtitle "$subtitle" -message "$message")
    if [[ -x "$_custom" ]]; then
        "$_custom" "${_args[@]}" 2>/dev/null && _sent=true || true
    fi
    if ! $_sent; then
        osascript -e "display notification \"$message\" with title \"$title\" subtitle \"$subtitle\"" 2>/dev/null || true
    fi
}

log_event() {
    local icon="$1" label="$2" title="$3" repo="$4" url="${5:-}"
    local timestamp
    timestamp=$(date +"%H:%M")
    if [[ -n "$url" ]]; then
        printf '[%s] %s %s  (%s)\t%s\n' "$timestamp" "$icon" "$label" "$repo" "$url" >> "$EVENTS_LOG"
    else
        printf '[%s] %s %s  (%s)\n' "$timestamp" "$icon" "$label" "$repo" >> "$EVENTS_LOG"
    fi
    printf '         %s\n' "$title" >> "$EVENTS_LOG"
    log_size=$(stat -f%z "$EVENTS_LOG" 2>/dev/null || echo 0)
    if [[ "$log_size" -gt 102400 ]]; then
        mv "$EVENTS_LOG" "${EVENTS_LOG}.$(date +%Y%m%d)"
        touch "$EVENTS_LOG"
    fi
}

api_get() {
    local path="$1"
    # Accept both /relative/path and full https://api.github.com/... URLs
    local url
    if [[ "$path" == https://* ]]; then
        url="$path"
    else
        url="https://api.github.com${path}"
    fi
    curl -sf "$url" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        2>/dev/null
}

# Convert GitHub API URL to browser-navigable HTML URL
to_html_url() {
    local u="$1"
    [[ -z "$u" ]] && { printf 'https://github.com/notifications'; return; }
    printf '%s' "$u" | sed \
        -e 's|https://api.github.com/repos/|https://github.com/|' \
        -e 's|/pulls/\([0-9]*\)$|/pull/\1|' \
        -e 's|/check-suites/[0-9]*$|/actions|' \
        -e 's|/check-runs/[0-9]*$|/actions|'
}

# ── batch state (reset each poll cycle) ──────────────────────────────────────
BATCH_SOUNDS=""
BATCH_COUNT=0
BATCH_BEST_LABEL=""
BATCH_BEST_REPO=""
BATCH_BEST_TITLE=""

queue_sound() {
    local s="$1"
    # Skip if already queued; append otherwise
    [[ " $BATCH_SOUNDS " == *" $s "* ]] && return
    BATCH_SOUNDS="${BATCH_SOUNDS:+$BATCH_SOUNDS }$s"
}

# ── PR review state helper ────────────────────────────────────────────────────
# Sets event_icon, event_label, sound, html_url based on PR state + review data.
# $1=subj_url  $2=pre-fetched pr_data  $3=self_filter (optional; excludes self-reviews)
_pr_state_event() {
    local subj_url="$1" pr_data="$2" self_filter="${3:-}"
    local pr_html pr_merged pr_state reviews_data approver changer

    pr_html=$(printf '%s' "$pr_data" | jq -r '.html_url // empty')
    [[ -n "$pr_html" ]] && html_url="$pr_html"
    pr_merged=$(printf '%s' "$pr_data" | jq -r '.merged')
    pr_state=$(printf '%s' "$pr_data" | jq -r '.state')

    if [[ "$pr_merged" == "true" ]]; then
        event_icon="🔀"; event_label="Merged"; sound="Hero.aiff"; return
    elif [[ "$pr_state" == "open" ]]; then
        reviews_data=$(api_get "${subj_url}/reviews") || reviews_data=""
        if [[ -n "$reviews_data" ]]; then
            if [[ -n "$self_filter" ]]; then
                approver=$(printf '%s' "$reviews_data" | jq -r \
                    --arg self "$self_filter" \
                    '[.[] | select(.state == "APPROVED" and .user.login != $self)] | last | .user.login // empty')
                changer=$(printf '%s' "$reviews_data" | jq -r \
                    --arg self "$self_filter" \
                    '[.[] | select(.state == "CHANGES_REQUESTED" and .user.login != $self)] | last | .user.login // empty')
            else
                approver=$(printf '%s' "$reviews_data" | jq -r \
                    '[.[] | select(.state == "APPROVED")] | last | .user.login // empty')
                changer=$(printf '%s' "$reviews_data" | jq -r \
                    '[.[] | select(.state == "CHANGES_REQUESTED")] | last | .user.login // empty')
            fi
        fi
        if [[ -n "$approver" ]]; then
            event_icon="✅"; event_label="Approved by ${approver}"; sound="Glass.aiff"
        elif [[ -n "$changer" ]]; then
            event_icon="🔁"; event_label="Changes requested by ${changer}"; sound="Basso.aiff"
        else
            event_icon="💬"; event_label="PR review comment"; sound="Tink.aiff"
        fi
    elif [[ "$pr_state" == "closed" ]]; then
        event_icon="🔒"; event_label="PR closed"; sound="Funk.aiff"
    fi
}

# ── process a single notification ─────────────────────────────────────────────
process_notification() {
    local notif="$1"
    local id reason title repo_name subj_url subj_type

    id=$(printf '%s' "$notif" | jq -r '.id // empty')
    [[ -z "$id" ]] && return
    reason=$(printf '%s' "$notif" | jq -r '.reason')
    title=$(printf '%s' "$notif" | jq -r '.subject.title')
    repo_name=$(printf '%s' "$notif" | jq -r '.repository.full_name')
    subj_url=$(printf '%s' "$notif" | jq -r '.subject.url // empty')
    subj_type=$(printf '%s' "$notif" | jq -r '.subject.type')
    updated_at=$(printf '%s' "$notif" | jq -r '.updated_at // empty')

    # Skip already-seen (compound key: id|updated_at catches thread updates)
    local seen_key="${id}|${updated_at}"
    if grep -qF "$seen_key" "$SEEN_IDS" 2>/dev/null; then
        return
    fi
    printf '%s\n' "$seen_key" >> "$SEEN_IDS"
    seen_count=$(wc -l < "$SEEN_IDS" | tr -d ' ')
    if [[ "$seen_count" -gt 10000 ]]; then
        tail -5000 "$SEEN_IDS" > "${SEEN_IDS}.tmp" && mv "${SEEN_IDS}.tmp" "$SEEN_IDS"
    fi

    local event_icon event_label sound html_url
    event_icon="🔔"
    event_label="Activity"
    sound="Ping.aiff"
    html_url=$(to_html_url "$subj_url")

    case "$reason" in
        comment|mention)
            event_icon="💬"
            if [[ "$subj_type" == "PullRequest" ]]; then
                event_label="PR comment"
            else
                event_label="New comment"
            fi
            sound="Tink.aiff"
            ;;
        review_requested)
            event_icon="👀"
            event_label="Review requested"
            sound="Tink.aiff"
            ;;
        assign)
            event_icon="📌"
            event_label="Assigned"
            sound="Ping.aiff"
            ;;
        approval_requested)
            event_icon="🚦"
            event_label="Approval needed"
            sound="Tink.aiff"
            ;;
        pull_request_review)
            if [[ "$subj_type" == "PullRequest" && -n "$subj_url" ]]; then
                local pr_data
                pr_data=$(api_get "$subj_url") || pr_data=""
                [[ -n "$pr_data" ]] && _pr_state_event "$subj_url" "$pr_data"
            else
                event_icon="💬"
                event_label="Review comment"
                sound="Tink.aiff"
            fi
            ;;
        invitation)
            event_icon="📬"
            event_label="Repo invitation"
            sound="Ping.aiff"
            ;;
        author)
            if [[ "$subj_type" == "PullRequest" && -n "$subj_url" ]]; then
                local pr_data
                pr_data=$(api_get "$subj_url") || pr_data=""
                [[ -n "$pr_data" ]] && _pr_state_event "$subj_url" "$pr_data" "$SELF"
            elif [[ "$subj_type" == "Issue" && -n "$subj_url" ]]; then
                local issue_data issue_state
                issue_data=$(api_get "$subj_url") || issue_data=""
                if [[ -n "$issue_data" ]]; then
                    local issue_html
                    issue_html=$(printf '%s' "$issue_data" | jq -r '.html_url // empty')
                    [[ -n "$issue_html" ]] && html_url="$issue_html"
                    issue_state=$(printf '%s' "$issue_data" | jq -r '.state')
                    if [[ "$issue_state" == "closed" ]]; then
                        event_icon="🔒"
                        event_label="Issue closed"
                        sound="Funk.aiff"
                    elif [[ "$issue_state" == "open" ]]; then
                        event_icon="🔓"
                        event_label="Issue reopened"
                        sound="Pop.aiff"
                    else
                        event_icon="💬"
                        event_label="Issue comment"
                        sound="Tink.aiff"
                    fi
                fi
            fi
            ;;
        team_mention)
            event_icon="👥"
            event_label="Team mentioned"
            sound="Tink.aiff"
            ;;
        state_change)
            if [[ -n "$subj_url" ]]; then
                local sc_data sc_merged sc_state
                sc_data=$(api_get "$subj_url") || sc_data=""
                if [[ -n "$sc_data" ]]; then
                    local sc_html
                    sc_html=$(printf '%s' "$sc_data" | jq -r '.html_url // empty')
                    [[ -n "$sc_html" ]] && html_url="$sc_html"
                    sc_merged=$(printf '%s' "$sc_data" | jq -r '.merged')
                    sc_state=$(printf '%s' "$sc_data" | jq -r '.state')
                    if [[ "$sc_merged" == "true" ]]; then
                        event_icon="🔀"
                        event_label="Merged"
                        sound="Hero.aiff"
                    elif [[ "$sc_state" == "closed" ]]; then
                        event_icon="🔒"
                        event_label="Closed"
                        sound="Funk.aiff"
                    elif [[ "$sc_state" == "open" ]]; then
                        event_icon="🔓"
                        event_label="Reopened"
                        sound="Pop.aiff"
                    fi
                fi
            fi
            ;;
        security_alert)
            event_icon="🛡️"
            event_label="Security alert"
            sound="Sosumi.aiff"
            ;;
        ci_activity)
            local ci_conclusion_src="" ci_status_src=""
            if [[ -n "$subj_url" ]]; then
                local ci_data ci_status ci_conclusion
                ci_data=$(api_get "$subj_url") || ci_data=""
                if [[ -n "$ci_data" ]]; then
                    ci_status=$(printf '%s' "$ci_data" | jq -r '.status // empty')
                    ci_conclusion=$(printf '%s' "$ci_data" | jq -r '.conclusion // empty')
                    ci_conclusion_src="$ci_conclusion"
                    ci_status_src="$ci_status"
                    html_url="https://github.com/${repo_name}/actions"
                fi
            else
                # subj_url is null for CheckSuite events — parse conclusion from title
                case "$title" in
                    *" failed "*)    ci_conclusion_src="failure" ;;
                    *" succeeded "*) ci_conclusion_src="success" ;;
                    *" skipped "*)   ci_conclusion_src="skipped" ;;
                    *" cancelled "*) ci_conclusion_src="cancelled" ;;
                esac
                html_url="https://github.com/${repo_name}/actions"
            fi
            case "$ci_conclusion_src" in
                failure|timed_out)
                    event_icon="❌"
                    event_label="CI failed"
                    sound="Basso.aiff"
                    ;;
                success)
                    event_icon="🟢"
                    event_label="CI passed"
                    sound="Pop.aiff"
                    ;;
                action_required)
                    event_icon="⚠️"
                    event_label="CI action required"
                    sound="Basso.aiff"
                    ;;
                cancelled)
                    event_icon="⛔"
                    event_label="CI cancelled"
                    sound="Funk.aiff"
                    ;;
                skipped|neutral|stale)
                    event_icon="⏭️"
                    event_label="CI skipped"
                    sound="Ping.aiff"
                    ;;
                *)
                    if [[ "$ci_status_src" == "in_progress" ]]; then
                        event_icon="⚙️"
                        event_label="CI running"
                        sound="Ping.aiff"
                    fi
                    ;;
            esac
            ;;
    esac

    log_event "$event_icon" "$event_label" "$title" "$repo_name" "$html_url"
    queue_sound "$sound"
    (( BATCH_COUNT++ )) || true
    if [[ -z "$BATCH_BEST_LABEL" ]]; then
        BATCH_BEST_LABEL="$event_label"
        BATCH_BEST_REPO="$repo_name"
        BATCH_BEST_TITLE="$title"
    fi
}

# ── poll loop ─────────────────────────────────────────────────────────────────
LAST_MODIFIED=""

while true; do
    # Build conditional request args
    EXTRA_ARGS=()
    if [[ -n "$LAST_MODIFIED" ]]; then
        EXTRA_ARGS=("-H" "If-Modified-Since: ${LAST_MODIFIED}")
    fi

    # Fetch notifications with response headers (-i for status + headers)
    raw_response=$(curl -si "https://api.github.com/notifications" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${EXTRA_ARGS[@]}" 2>/dev/null) || { sleep 30; continue; }

    # Extract HTTP status code from first header line
    http_status=$(printf '%s\n' "$raw_response" | head -1 | grep -oE '[0-9]{3}' | head -1)

    # 304 = nothing changed since last poll; skip processing
    if [[ "$http_status" == "304" ]]; then
        sleep 30
        continue
    fi

    # Store Last-Modified for next conditional request
    new_lm=$(printf '%s\n' "$raw_response" | grep -i "^last-modified:" | head -1 | sed 's/[Ll]ast-[Mm]odified: //' | tr -d '\r')
    [[ -n "$new_lm" ]] && LAST_MODIFIED="$new_lm"

    # Extract body: everything after the blank line separating headers from body
    body=$(printf '%s\n' "$raw_response" | awk 'found{print} /^\r?$/{found=1}')

    # Validate response is a JSON array before processing
    if ! printf '%s\n' "$body" | jq -e 'type == "array"' > /dev/null 2>&1; then
        sleep 30
        continue
    fi

    # Reset batch accumulators
    BATCH_SOUNDS=""
    BATCH_COUNT=0
    BATCH_BEST_LABEL=""
    BATCH_BEST_REPO=""
    BATCH_BEST_TITLE=""
    unset batch_dedup
    declare -A batch_dedup

    count=$(printf '%s\n' "$body" | jq 'length')
    for i in $(seq 0 $((count - 1))); do
        notif=$(printf '%s\n' "$body" | jq ".[${i}]")

        # Within-batch dedup: collapse same repo+title (e.g. 20x skipped workflow runs)
        batch_key=$(printf '%s' "$notif" | jq -r '"\(.repository.full_name):\(.subject.title):\(.reason)"')
        if [[ -v batch_dedup["$batch_key"] ]]; then
            dup_id=$(printf '%s' "$notif" | jq -r '.id // empty')
            dup_updated=$(printf '%s' "$notif" | jq -r '.updated_at // empty')
            [[ -n "$dup_id" ]] && printf '%s\n' "${dup_id}|${dup_updated}" >> "$SEEN_IDS"
            continue
        fi
        batch_dedup["$batch_key"]=1

        process_notification "$notif"
    done

    # Dispatch once for the whole batch: sounds (sequential, async), 1 popup
    if [[ -n "$BATCH_SOUNDS" ]]; then
        _sfx=$(cat "$SFX_STATE" 2>/dev/null || echo "ON")
        if [[ "$_sfx" == "ON" ]]; then
            ( for _snd in $BATCH_SOUNDS; do
                afplay "/System/Library/Sounds/${_snd}" 2>/dev/null
              done ) &
        fi
    fi
    if [[ "$BATCH_COUNT" -eq 1 ]]; then
        send_notification "GitHub: ${BATCH_BEST_LABEL}" "$BATCH_BEST_REPO" "$BATCH_BEST_TITLE"
    elif [[ "$BATCH_COUNT" -gt 1 ]]; then
        send_notification "GitHub: ${BATCH_COUNT} new notifications" \
            "$BATCH_BEST_REPO" "${BATCH_BEST_TITLE} +$((BATCH_COUNT - 1)) more"
    fi

    sleep 30
done
