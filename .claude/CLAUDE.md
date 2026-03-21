# gitbeacon — Project Notes for Claude

## Project Structure

```
scripts/gitbeacon-daemon.sh   — background daemon: polls GH API, logs events, sends notifications
scripts/gitbeacon-bar.sh      — bar plugin: reads log, renders event lines, handles keypresses
scripts/gitbeacon-notifier.m  — ObjC source for custom macOS notifier app (bundle ID: com.joryeugene.gitbeacon)
install.sh                    — first-time setup: prereq checks, script copy, notifier build prompt
justfile                      — dev/release workflow (lint, sync, build-notifier, release)
CHANGELOG.md                  — Keep a Changelog format, Semantic Versioning
GitBeaconApp/                 — macOS menu bar app (SwiftUI MenuBarExtra, wraps daemon)
  Package.swift               — SPM manifest, macOS 14+
  Sources/GitBeaconApp/       — App.swift, DaemonManager, EventLogWatcher, MenuBarView, etc.
  build/package-app.sh        — assembles .app bundle from SPM build output
  build/package-dmg.sh        — creates distributable DMG with drag-to-Applications install
```

## Release Workflow

### 1. Write code, commit incrementally

### 2. Generate draft CHANGELOG notes
```bash
just notes
```
Prints commits since last tag. Review and paste into `CHANGELOG.md` under `## [Unreleased]`.

### 3. Update CHANGELOG.md
- Replace `## [Unreleased]` header with `## [X.Y.Z] - YYYY-MM-DD`
- Add a new empty `## [Unreleased]` section above it
- Update comparison links at the bottom:
  ```markdown
  [X.Y.Z]: https://github.com/joryeugene/gitbeacon/compare/vPREV...vX.Y.Z
  [Unreleased]: https://github.com/joryeugene/gitbeacon/compare/vX.Y.Z...HEAD
  ```

### 4. Commit the changelog
```bash
git add CHANGELOG.md
git commit -m "chore: changelog for vX.Y.Z"
```

### 5. Run the release
```bash
just release X.Y.Z
```

This recipe:
1. Verifies `[X.Y.Z]` exists in `CHANGELOG.md`
2. Lints all shell scripts with shellcheck
3. Builds universal binary, packages .app and .dmg
4. Syncs scripts to `~/.config/gitbeacon/` + app bundle
5. Installs to `/Applications/GitBeacon.app`
6. Creates and pushes annotated tag `vX.Y.Z`
7. Extracts the version's CHANGELOG section via `awk` and creates a **draft** GitHub release with DMG attached

### 6. Publish the draft
Review at `https://github.com/joryeugene/gitbeacon/releases`, then click Publish.

---

## Dev Workflow

```bash
just sync            # copy scripts to ~/.config/gitbeacon/ + app bundle (then press [r] in bar to reload)
just lint            # shellcheck all scripts
just dev-install     # build, package, and install to /Applications (full local rebuild)
just build-notifier  # rebuild the ObjC notifier .app (needed after icon/code changes)
just build-app       # universal release binary (arm64 + x86_64)
just package-app     # assemble .app bundle from release build
just package-dmg     # create distributable DMG
bash tests/test-dedup.sh  # run dedup test suite (15 assertions)
```

## Version Conventions

- **patch** (0.x.Y): bug fixes, docs, CI
- **minor** (0.X.0): user-visible behavior changes (log format, new events, new keybindings)
- **major** (X.0.0): breaking changes to install layout or config format

## Key Design Notes

- Event log uses 2-line format (v0.9.0+): `[timestamp] icon LABEL  repo\ttitle` on line 1, `\ttitle` on line 2
- `grep -c '^\['` counts events (not `wc -l`) to avoid double-counting detail lines
- `[o]` URL extraction greps for tab-bearing lines (header lines only, not detail lines)
- Bar displays 16 tail lines = 8 events x 2 lines each (terminal bar only)
- Menu bar app: 500-event in-memory cap, 50 shown in scroll list, `totalEventCount` tracks running total (resets on Clear)
- Three-tier dedup: one-shot (bare id), content-update (id|latest_comment_url), terminal-state (id|Merged etc.)
- `just sync` patches both `~/.config/gitbeacon/` and `/Applications/GitBeacon.app/Contents/Resources/` so the SHA-256 check in `installDaemonScript()` does not revert synced scripts
- macOS menu bar app spawns daemon with Homebrew bash 5 (not `/bin/bash` 3.2). The daemon uses `declare -A` and `[[ -v ]]` which require bash 4+.
- `events.log` is the integration contract between daemon and app. The daemon writes, the SwiftUI app reads via kqueue + timer fallback. No IPC, no sockets.
- Tests: `bash tests/test-dedup.sh` (15 assertions, 7 groups, requires bash 5 + jq)
