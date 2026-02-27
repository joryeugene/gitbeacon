# gh-notify

<p align="center">
  <img src="assets/icon.svg" alt="gh-notify" width="80" height="80">
</p>

<p align="center">
  <a href="https://github.com/joryeugene/gh-notify/blob/main/LICENSE"><img src="https://img.shields.io/github/license/joryeugene/gh-notify.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="macOS">
  <img src="https://img.shields.io/badge/requires-gh%20CLI-blue.svg" alt="requires gh CLI">
</p>

<table><tr>
<td>
  <h3>Real-time GitHub PR notifications with macOS sounds</h3>
  <p>Background daemon that polls GitHub every 30s, fires event-specific sounds and macOS popups, and streams a live log into an interactive bottom bar. Run it in any terminal pane.</p>
</td>
<td align="center">
<pre>
[12:04] ✅ Approved - Fix auth (org/repo)
[12:07] 💬 Comment - Add retry logic (org/repo)
[12:09] 🔀 Merged - Update deps (org/repo)
[12:11] 🔔 Activity - CI passed (org/repo)
              ·:·[ gh-notify · 4 ]·:·
  ✅ 1  🔀 1  💬 1  │  org/repo(4)
  [s]snd(ON)  [c]clr  [r]rst  [o]PR  [q]quit
</pre>
</td>
</tr></table>

## macOS Notification Permissions

gh-notify ships a custom notification app (`gh-notify-notifier.app`) — a minimal Objective-C `.app` bundle with the KingBee bee icon and bundle ID `com.joryeugene.gh-notify`. It appears in System Settings as **GH Notifier**.

<p align="center">
  <img src="assets/mac-notification.png" alt="gh-notify macOS notification banner" width="380">
</p>

**Why a custom app:** `osascript display notification` requires the calling process to be attached to the macOS GUI session. Background daemons run in a detached session with no GUI attachment — notifications sent via `osascript` from a detached process are silently dropped. A proper `.app` bundle with `UNUserNotificationCenter` works from any context, including background daemons.

**One-time setup:** On first use, macOS opens System Settings to request notification permission. Find **GH Notifier** in the list and set the style to **Banners** or **Alerts**. The first launch triggers a permission prompt — click **Allow**.

```bash
# Jump directly to the Notifications pane:
open "x-apple.systempreferences:com.apple.preference.notifications"
```

**After running the installer:** If the bar was already running, it was stopped automatically. Relaunch with `gh-notify`.

**If banners stop appearing:** Check that Do Not Disturb / Focus mode is off (Control Center, top-right menu bar). Run `just notify "test"` from the repo to send a test notification.

---

## TLDR

**Prerequisites** (one-time):
```bash
brew install gh jq
# tmux is optional — gh-notify runs in any terminal pane
gh auth login
```

1. **Install**: `curl -fsSL https://raw.githubusercontent.com/joryeugene/gh-notify/main/install.sh | bash`
2. **Launch**: `gh-notify` (in any terminal pane)

---

## Events

| Icon | Event | Trigger | Sound |
|------|-------|---------|-------|
| ✅ | Approved | Non-self APPROVED review on your PR | `Glass.aiff` |
| 🔁 | Changes requested | Reviewer requested changes on your PR | `Basso.aiff` |
| 🔀 | Merged | PR merged (author or state_change) | `Hero.aiff` |
| 💬 | Comment / mention | Comment, @mention, or PR review comment | `Tink.aiff` |
| 👀 | Review requested | You were asked to review | `Tink.aiff` |
| 📌 | Assigned | Issue or PR assigned to you | `Ping.aiff` |
| 🚦 | Approval needed | Approval requested on a PR | `Tink.aiff` |
| 👥 | Team mentioned | Your team was @mentioned | `Tink.aiff` |
| 🔒 | Closed | PR or issue closed without merging | `Funk.aiff` |
| 🔓 | Reopened | PR or issue reopened | `Pop.aiff` |
| 📬 | Repo invitation | You were invited to a repository | `Ping.aiff` |
| ❌ | CI failed | Workflow run failed or timed out | `Basso.aiff` |
| 🟢 | CI passed | Workflow run succeeded | `Pop.aiff` |
| ⚙️ | CI running | Workflow run in progress | `Ping.aiff` |
| ⛔ | CI cancelled | Workflow run cancelled | `Funk.aiff` |
| ⚠️ | CI action required | Workflow requires manual action | `Basso.aiff` |
| ⏭️ | CI skipped | Workflow run skipped / neutral / stale | `Ping.aiff` |
| 🛡️ | Security alert | Dependabot or security advisory | `Sosumi.aiff` |
| 🔔 | Activity | All other notification types | `Ping.aiff` |

All sounds are built-in macOS system sounds. No dependencies beyond the prereqs.

---

## Keybinds

| Key | Action |
|-----|--------|
| `s` | Toggle sound ON/OFF |
| `c` | Clear the event log |
| `r` | Restart daemon (if crashed) |
| `o` | Open last event in browser |
| `q` | Quit bar (also stops daemon) |

---

## How It Works

```mermaid
flowchart LR
    subgraph loop["Poll Loop"]
        BAR[gh-notify-bar.sh] -->|spawns| DAEMON[gh-notify-daemon.sh]
        DAEMON -->|If-Modified-Since| POLL{GET /notifications}
        POLL -->|304 Not Modified| SLEEP[sleep 30]
        SLEEP --> DAEMON
    end

    subgraph classify["Per Notification"]
        FILTER["dedup: seen-ids\n+ batch repo:title"] --> R{reason}
        R -->|"comment / mention\nreview_requested"| TINK["💬 👀  Tink"]
        R -->|assign| PING["📌 Ping"]
        R -->|author → fetch PR| STATE{PR state}
        STATE -->|merged| HERO["🔀 Hero"]
        STATE -->|approved| GLASS["✅ Glass"]
        STATE -->|other| PING
    end

    subgraph dispatch["One Per Poll Cycle"]
        Q["priority queue\nHero › Glass › Ping › Tink"] --> GATE{sfx-state}
        GATE -->|ON| SOUND[afplay]
        GATE -->|OFF| MUTE[silent]
        Q --> POPUP[gh-notify-notifier]
        Q --> LOG[events.log]
    end

    POLL -->|200 OK| FILTER
    TINK --> Q
    PING --> Q
    HERO --> Q
    GLASS --> Q
    LOG -->|tail -8| BAR
```

The daemon uses HTTP conditional requests (`If-Modified-Since` / `304 Not Modified`). GitHub's API returns 304 when the notification list hasn't changed since the last poll — these responses don't count against your rate limit.

---

<details>
<summary><strong>Manual installation / custom sesh integration</strong></summary>

**Without the installer:**

```bash
mkdir -p ~/.config/gh-notify
cp scripts/gh-notify-daemon.sh ~/.config/gh-notify/
cp scripts/gh-notify-bar.sh    ~/.config/gh-notify/
chmod +x ~/.config/gh-notify/*.sh
echo "ON" > ~/.config/gh-notify/sfx-state
touch ~/.config/gh-notify/events.log ~/.config/gh-notify/seen-ids

# Install CLI command
mkdir -p ~/.local/bin
cat > ~/.local/bin/gh-notify << 'EOF'
#!/usr/bin/env bash
exec bash "${HOME}/.config/gh-notify/gh-notify-bar.sh" "$@"
EOF
chmod +x ~/.local/bin/gh-notify
```

**Custom sesh integration:**

Add one line to your existing briefing script:

```bash
# Replace your existing right-pane split with:
tmux split-window -v -l 12% 'gh-notify'
tmux select-pane -t :.1
```

**Full sesh + gh-dash + gh-notify example:**

```bash
#!/usr/bin/env bash
# Example: sesh briefing.sh with gh-notify bar
# Drop into ~/.config/sesh/scripts/briefing.sh (or wherever your sesh script lives)

tmux rename-window -t 1 "BRIEFING"

# Weather (optional — remove if you don't use wttr.in)
printf '\033[1;36m'
curl -s --max-time 3 "wttr.in?format=%l:+%c+%t+%w" 2>/dev/null || true
printf '\033[0m\n'

# Bottom pane: gh-notify bar (live PR notifications + daemon)
tmux split-window -v -l 12% 'gh-notify'

# Top pane: gh-dash
tmux select-pane -t :.1
exec gh dash
```

**Run the bar in any terminal pane (tmux example):**

```bash
gh-notify
```

The bar automatically starts the daemon. When the bar exits, it kills the daemon.

</details>

<details>
<summary><strong>Configuration</strong></summary>

**State files** — all in `~/.config/gh-notify/`:

| File | Purpose |
|------|---------|
| `events.log` | Appended event lines displayed in the bar |
| `sfx-state` | Contains `ON` or `OFF` — controls sound playback |
| `seen-ids` | Newline-separated processed notification IDs (prevents duplicates) |

**Poll interval:**

Edit `gh-notify-daemon.sh` and change the `sleep 30` at the bottom of the loop. The default is 30 seconds. Going below 15 seconds is not recommended (GitHub rate limit is 5000 requests/hour; 304 responses don't count toward that limit).

**Sounds:**

Edit the `case "$reason"` block in `gh-notify-daemon.sh` to swap any sound file. All built-in macOS sounds are in `/System/Library/Sounds/`. Test one with:

```bash
afplay /System/Library/Sounds/Glass.aiff
```

**Bar height:**

Change `12%` in the `split-window` command to any percentage or fixed line count (e.g., `-l 10`).

</details>

---

## Verification

```bash
# 1. Launch the bar
gh-notify
# Watching for GitHub notifications... (bottom pane)

# 2. Test sound
afplay /System/Library/Sounds/Glass.aiff

# 3. Test popup (uses GH Notifier custom app with bee icon)
~/.config/gh-notify/gh-notify-notifier.app/Contents/MacOS/gh-notify-notifier \
    -title "GH Notifier" -message "Test"

# 4. Check daemon is running
pgrep -f gh-notify-daemon && echo "daemon running"

# 5. Live trigger
# Open a draft PR, request a review, approve it — bar updates within 30s
```

---

## Troubleshooting

**No events appearing in the bar**
```bash
# Check daemon is running
pgrep -f gh-notify-daemon && echo "running" || echo "not running"

# Check GitHub auth
gh auth status

# Check events.log for content
cat ~/.config/gh-notify/events.log
```

**Bar shows events but daemon died mid-session**
```bash
# Kill any orphaned daemon
pkill -f gh-notify-daemon
# Then relaunch
gh-notify
```

**Sound not playing**
```bash
# Check current sound state
cat ~/.config/gh-notify/sfx-state   # should print ON

# Test sound manually
afplay /System/Library/Sounds/Glass.aiff

# Toggle sound in the bar with [s]
```

**Daemon exits immediately on start**
```bash
# The daemon detects and reclaims stale locks automatically.
# If you suspect a stuck state, force-clear manually:
rm -rf ~/.config/gh-notify/.daemon.lock
```

**Notifications stop after a long session**

GitHub's rate limit is 5000 requests/hour. 304 (not-modified) responses don't count.
If you hit the limit, the daemon sleeps until the window resets (check with `gh api /rate_limit`).

---

## Uninstall

```bash
# Stop the bar and daemon first (press q in the bar, or:)
pkill -f gh-notify-daemon
pkill -f gh-notify-bar

# Optional: back up seen-ids if you plan to reinstall
# Without it, all previously-seen notifications re-fire on first poll after reinstall
# cp ~/.config/gh-notify/seen-ids ~/seen-ids.bak

# Remove scripts, state, and CLI wrapper
rm -rf ~/.config/gh-notify
rm -f ~/.local/bin/gh-notify
```
