# Changelog

All notable changes to gh-notify are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

---

## [0.9.0] - 2026-02-26

### Changed
- Event log now uses 2-line format: headline (timestamp + icon + label + repo) on line 1, title indented on line 2
- Bar shows 16 lines (8 events × 2 lines each) instead of 8 lines
- Event count uses `grep -c '^\['` instead of `wc -l` to avoid double-counting detail lines
- `[o]` URL extraction targets tab-bearing lines (header lines only)

### Fixed
- Antifragile daemon startup
- `pull_request_review` event handler
- CI null-url edge case

---

## [0.8.1] - 2026-02-25

### Changed
- `build-notifier` / installer: replaced terminal-notifier repackaging with a compiled ObjC binary (`scripts/gh-notify-notifier.m`). No `brew install terminal-notifier` required; prerequisite is now Xcode CLT (`clang`) + `librsvg`.
- daemon/bar: `send_notification` and `[t]` handler now call the `gh-notify-notifier` binary directly; removed `terminal-notifier` and `icon.png` fallback paths.
- install.sh: idempotency check now verifies `CFBundleDisplayName == "GH Notifier"` and `CFBundleExecutable == "gh-notify-notifier"` — stale installs missing the display name are auto-rebuilt on re-run.
- install.sh: Step 4 verify tests the custom app and opens System Settings automatically if permissions are denied.
- README: notification permissions section updated to reference "GH Notifier" throughout; verification command updated to call the custom app binary.

### Fixed
- Notification prompt / System Settings entry now shows **GH Notifier** instead of falling back to the executable name `gh-notify-notifier`.
- Icon cache flushed after build (`touch`, `iconservicesagent`, `lsregister`, `notificationcenterui` restart) so the bee icon and correct display name appear immediately in the permission prompt.

### Added
- `scripts/gh-notify-notifier.plist`: authored `Info.plist` with `CFBundleDisplayName = "GH Notifier"`, `CFBundleName = "GH Notifier"`, `CFBundleIdentifier = "com.joryeugene.gh-notify"`.
- `scripts/gh-notify-notifier.m`: minimal Objective-C notification binary source (compilable via Xcode CLT, no Swift toolchain required).

---

## [0.8.0] - 2026-02-24

### Added
- `assets/icon.svg`: KingBee — cute bee icon (amber body, black stripes, iridescent wings, big eyes, antennae, stinger) on GitHub dark background. The bee is the notification.
- `just build-notifier`: repackages terminal-notifier with the custom icon and bundle ID `com.joryeugene.gh-notify-notifier`. Builds a full ICNS iconset via `rsvg-convert` + `sips` + `iconutil`, ad-hoc signs with `codesign`, strips quarantine, triggers the first-launch notification permission prompt. Requires `brew install librsvg`.
- README: bee icon displayed above badges

### Changed
- daemon/bar: notification sender now prefers `gh-notify-notifier.app` binary when present, so the bee icon appears in the left-side notification slot. Falls back to system `terminal-notifier`, then `osascript`.
- install: downloads GitHub mark PNG to `~/.config/gh-notify/icon.png` for use as `-contentImage` on the right side of notifications

---

## [0.7.0] - 2026-02-24

### Added
- `terminal-notifier` as primary notification path in daemon and installer; `osascript` used as fallback when terminal-notifier is not installed. Fixes silent notification drops from within tmux sessions.
- `[t]` keybind: sends a test notification and shows a transient one-cycle status confirm in the bar
- `approval_requested` event type: 🚦 Approval needed (Tink, bold yellow in bar)
- `invitation` event type: 📬 Repo invitation (Ping)
- CI `skipped`, `neutral`, `stale` conclusions: ⏭️ CI skipped (dim in bar)
- PR closed (non-merged) via `author` reason: 🔒 PR closed (Funk)
- Issue closed/reopened via `author` reason: 🔒 Issue closed / 🔓 Issue reopened
- Distinct PR vs. issue comment labels via `author` reason: 💬 PR comment vs. 💬 Issue comment
- 🔁 Changes requested label via `author` reason (review dismissed → requested changes state)
- 🚦 included in session stats footer (approval_requested count)
- installer kills stale bar process after script deploy, prints relaunch prompt
- README: notification permissions section documenting terminal-notifier, one-time System Settings grant, DND gotcha, and bar-restart note

### Changed
- installer test notification message updated to "Grant permission in System Settings if prompted"; follow-up `info` lines added if no banner appears
- `[t]` added to keybind hints line in bar

---

## [0.6.0] - 2026-02-24

### Added
- Distinct sound mappings per event type: CI failure/action_required → Basso, CI pass/reopened → Pop, CI cancelled/closed → Funk, security alert → Sosumi; merge (Hero) and approve (Glass) unchanged
- Multi-sound dispatch: all distinct sounds in a poll batch now play sequentially in a background subshell instead of one priority-winner; a merge + CI fail in one poll plays Hero then Basso
- Stats line in footer showing per-icon session totals (🔀 ✅ 💬 ❌ 🟢) sourced from the full events.log; shown only when non-zero, resets when `[c]` clears the log
- Repo activity inline with stats: top-3 repos by event count appended after `│` separator (e.g. `org/repo(9) other/repo(3)`)
- Centered separator: `·:·[ gh-notify · N ]·:·` dynamically pads to terminal width via `tput cols`; the `+4` correction accounts for 4 middle-dot chars (U+00B7) that are 2 UTF-8 bytes but 1 display column each

### Changed
- Separator event count now reflects true all-time total from full events.log (`wc -l`) instead of capped-at-8 tail count
- `queue_sound()` rewritten from priority-replacement to additive deduplication
- `play_sound()` helper removed (inlined into async dispatch block)

---

## [0.5.0] - 2026-02-23

### Added
- `[o]` keybind to open the last event's URL in the default browser
- `to_html_url()` helper in daemon converts API URLs to browser-navigable HTML URLs: `pulls/N` → `pull/N`, `check-suites/N` → `actions`, empty → `https://github.com/notifications`
- URL stored inline in events.log as tab-appended field: `[HH:MM] icon label - title (repo)\thttps://...`
- CI events always link to the repo's Actions page; PR/issue events use `html_url` from the GitHub API response when available

### Changed
- Bar display loop strips tab-suffix before rendering (backward-compatible: lines without a tab are unchanged)
- Hints line updated to include `[o] open`

---

## [0.4.0] - 2026-02-23

### Added
- CI/Actions events (`ci_activity`): ❌ failed, 🟢 passed, ⚙️ running, ⛔ cancelled, ⚠️ action required — each fetches the check suite for actual conclusion
- State change events (`state_change`): 🔒 closed, 🔓 reopened, 🔀 merged (via PR object fetch)
- Team mention events (`team_mention`): 👥 Team mentioned
- Security alert events (`security_alert`): 🛡️ Security alert (Glass sound)
- Per-type color in bar for all new icons: red for ❌/⛔, green for 🟢, dim for ⚙️, cyan for 👥, yellow for 🔒/🔓, magenta for 🛡️
- Inline-header separator replaces fixed-width line: `── gh-notify ─ N ──` auto-sizes to terminal width via `tput cols`
- Event count shown live in the separator

### Changed
- Events table in README expanded from 6 to 14 rows covering all handled reasons
- Layout comment updated to describe actual rendering behavior

---

## [0.3.0] - 2026-02-23

### Added
- Daemon liveness check in bar: yellow `⚠ daemon offline` warning fires within 2s of crash
- `[r]` keybind to restart the daemon from the bar without relaunching the session
- `just uninstall` recipe to cleanly remove all installed files and state
- Troubleshooting section in README covering the 5 most common failure modes
- Uninstall section in README with `seen-ids` backup note

### Changed
- TLDR prerequisites moved before numbered steps as a runnable block (auth failure is now obvious before install)
- Diagram surfaces `sfx-state` gate making the `[s]` sound toggle architecturally visible
- Poll interval docs clarify default (30s) and minimum (15s) without contradicting each other

### Fixed
- `[r]` restart waits for old daemon's lock release before spawning (prevented silent spawn failure)
- `just lint` SC2088 warning on `~/.local/bin` display string suppressed with inline comment

---

## [0.2.0] - 2026-02-23

### Added
- CLI wrapper `gh-notify` installed to `~/.local/bin` — no more bare `bash` launch instructions
- `justfile` with `lint`, `install`, and `release` recipes
- `just notes` recipe to draft changelog sections from git log

### Changed
- Notifications within a poll cycle are now batched and deduped by repo + title
- Sound dispatch uses priority queue: Hero > Glass > Ping > Tink
- Exactly one sound and one popup fires per poll — "N new notifications" when count > 1, eliminating popup spam under load

---

## [0.1.0] - 2026-02-23

### Added
- Background daemon polling GitHub notifications via `gh` CLI
- tmux status bar integration showing unread count
- macOS native popups via `osascript`
- macOS system sound notifications (Glass, Ping, Tink, Hero)
- Sound on/off toggle persisted to `~/.config/gh-notify/sfx-state`
- `seen-ids` dedup across sessions
- `install.sh` with prerequisite checks (gh, jq, tmux, osascript)

---

[Unreleased]: https://github.com/joryeugene/gh-notify/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/joryeugene/gh-notify/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/joryeugene/gh-notify/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/joryeugene/gh-notify/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/joryeugene/gh-notify/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/joryeugene/gh-notify/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/joryeugene/gh-notify/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/joryeugene/gh-notify/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/joryeugene/gh-notify/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/joryeugene/gh-notify/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/joryeugene/gh-notify/releases/tag/v0.1.0
