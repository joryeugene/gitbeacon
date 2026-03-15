# Changelog

All notable changes to gitbeacon are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

---

## [1.1.0] - 2026-03-15

### Added
- **macOS menu bar app** (`GitBeaconApp/`): native SwiftUI `MenuBarExtra` that wraps the daemon. Click the bell icon to see recent events, toggle sound, and quit. No terminal required.
  - Event log watcher using kqueue (`DispatchSource`) with 5-second timer fallback for file rotation
  - Daemon lifecycle management: spawn, adopt existing, health check every 10s, kill on quit
  - Single-instance guard: second launch exits immediately instead of creating duplicate menu bar icons
  - Click any event row to open the GitHub URL in the default browser
  - App icon (KingBee bee) in Finder, Spotlight, and DMG via `AppIcon.icns`
  - `build/package-app.sh` assembles a proper `.app` bundle with icon, `Info.plist`, and ad-hoc codesigning
  - `build/package-dmg.sh` creates a distributable DMG with drag-to-Applications install
- justfile recipes: `build-app` (universal binary), `package-app`, `package-dmg`
- CI workflow (`.github/workflows/ci.yml`): shellcheck lint + swift build on macos-latest
- README: Gatekeeper "unidentified developer" right-click workaround
- Daemon spawned with Homebrew bash 5 (not `/bin/bash` 3.2) to support associative arrays and `-v` tests used by the daemon script

---

## [1.0.0] - 2026-03-04

### Changed (breaking)
- Project renamed **gh-notify → gitbeacon**: CLI command (`gitbeacon`), config directory (`~/.config/gitbeacon/`), script names (`gitbeacon-daemon.sh`, `gitbeacon-bar.sh`), notifier app (`gitbeacon-notifier.app`), and bundle ID (`com.joryeugene.gitbeacon`)
- macOS notification permission prompt now shows **GitBeacon** instead of GH Notifier
- GitHub repo moved to `joryeugene/gitbeacon` (old URL auto-redirects)

### Fixed
- Duplicate `review_requested`, `assign`, `invitation`, and `approval_requested` events: these one-shot notifications were re-firing on every PR update because GitHub bumps `updated_at` on all unread thread notifications whenever the PR is touched. Dedup now uses bare notification ID (not `id|updated_at`) for these reason types
- PR review notifications showing as **Assigned** instead of actual review state (Approved / Changes requested) — `_pr_state_event()` now called with `no_fallback=1` for `assign` and `comment` reasons so the caller's default label is preserved when no review state is found

---

## [0.11.1] - 2026-02-28

### Changed (internal)
- Bar: extracted 9 inline ANSI escape codes into named color constants (`C_GREEN`, `C_MAGENTA`, etc.)
- Daemon: extracted `_pr_state_event()` helper, deduplicating PR review logic shared by `pull_request_review` and `author` reason handlers (net -27 lines)
- Daemon: `seen-ids` deduped on boot via `sort -u` to prevent file bloat

### Fixed
- Bar: 📬 repo invitation events now render cyan (were falling through to dim)
- Daemon: `send_notification` escapes backslashes and double-quotes instead of stripping/replacing them, fixing osascript rendering of titles containing those characters

---

## [0.11.0] - 2026-02-27

### Added
- `scripts/demo-scenario.sh`: standalone event writer that populates a realistic 8-event backlog with a fake daemon lock, enabling demo recordings without `gh auth`
- `demo.tape`: VHS recording script that produces `assets/demo.gif` (~22s animated GIF showing color-coded events arriving, stats bar, sound toggle, quit)
- `assets/demo.gif`: animated terminal recording for the README

### Changed
- README hero section: replaced stale single-line text mockup (pre-v0.9.0 format) with animated GIF showing the live bar
- `just lint` now includes `scripts/demo-scenario.sh`

---

## [0.10.0] - 2026-02-27

### Fixed
- PR notifications (merges, approvals, state changes) silently dropped after first sight of a thread. GitHub's `/notifications` endpoint returns mutable threads, not immutable events; the daemon now tracks `id|updated_at` compound keys so thread lifecycle updates register as new events.
- Within-batch dedup collapsed distinct PR lifecycle events (e.g. approval + merge in the same poll window). Batch key now includes `reason` so each event type is processed independently.

### Changed
- `seen-ids` format migrated from bare notification ID to `id|updated_at`. Old-format files are auto-detected and truncated on daemon startup (old entries can never match the new format).

---

## [0.9.1] - 2026-02-26

### Changed
- `[t]` test notification key removed; use `just notify "test"` from the repo instead
- README: add macOS notification screenshot

### Changed (internal)
- `just release` now creates a draft GitHub release automatically via `gh release create --draft`
- `.claude/` added to `.gitignore`

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

[Unreleased]: https://github.com/joryeugene/gitbeacon/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/joryeugene/gitbeacon/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/joryeugene/gitbeacon/compare/v0.11.1...v1.0.0
[0.11.1]: https://github.com/joryeugene/gitbeacon/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/joryeugene/gh-notify/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/joryeugene/gh-notify/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/joryeugene/gh-notify/compare/v0.9.0...v0.9.1
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
