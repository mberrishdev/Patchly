# Patchly

Menu-bar-only macOS 26 utility (Apple Silicon only) that scans installed applications and reports which ones have updates available. Read `CONTEXT.md` first — it is the domain model and rulebook; its terminology is binding.

## State of the repo

Freshly scaffolded: project structure, folder layout, and docs are in place, loosely following the pattern of github.com/mberrishdev/Patchly (README/CLAUDE.md/CONTEXT.md split). Core scanning and update-checking logic is being implemented next.

## Stack decisions (already made, do not relitigate)

- Plain committed `Patchly.xcodeproj` (generated once via `xcodegen` from `project.yml`, then treated as a normal checked-in project — no Tuist, no regeneration as part of the build)
- SwiftUI is the entire shell — a single `MenuBarExtra` scene, no AppKit shell, no hosted-window pattern (Patchly has no HUD, no global hotkeys, no reason for an AppKit composition root)
- Zero third-party dependencies — Homebrew/mas are invoked as external processes; Sparkle appcasts belonging to other apps are parsed with Foundation's `XMLParser`
- App Sandbox off (`ENABLE_APP_SANDBOX = NO`) — required to shell out to `brew`/`mas` and to read other apps' bundles freely
- Scaffolding values (bundle ID, entitlements, Info.plist keys): `docs/ProjectSettings.md`

## Layout (modules as folders)

- `Patchly/App/` — composition root: `PatchlyApp.swift` (the `@main` `MenuBarExtra` scene) and `AppSettings.swift` (UserDefaults-backed preferences: refresh interval, badge visibility)
- `Patchly/Models/` — `ScannedApp` (the merged, displayable record) and `DiscoveredApp` (the scan-only intermediate, before any Update Source is attributed)
- `Patchly/Scanner/` — `ApplicationScanner` (enumerates the three app directories, reads Info.plist) and `UpdateAggregator` (runs all three Update Sources concurrently, applies the Mac App Store > Homebrew Cask > Sparkle Feed priority from `CONTEXT.md`)
- `Patchly/UpdateSources/` — one file per source (`HomebrewCaskChecker`, `MacAppStoreChecker`, `SparkleFeedChecker`), each independently unit-testable behind the shared `UpdateSource` protocol
- `Patchly/Support/` — `ProcessRunner` (async wrapper over `Process`), `ExecutableLocator` (finds `brew`/`mas` without relying on inherited `$PATH`), `VersionComparator`, `SparkleAppcastParser`
- `Patchly/Persistence/` — `CacheStore`, the Cache Snapshot JSON read/write
- `Patchly/State/` — `AppState`, the `@MainActor` published source of truth the UI observes, owns the refresh timer and wake-notification subscription
- `Patchly/UI/` — `MenuBarLabelView` (icon + Badge Count), `MenuBarContentView` (dropdown root), `AppRowView`, `SourceBadgeView`

## Code style

- Standard Swift formatting, 4-space indentation
- No `// MARK:` comments — a file that needs section markers needs splitting, not markers
- Use `CONTEXT.md` terminology in code (type/case names, tests, commits) rather than drifting to a synonym it explicitly avoids

## Roadmap

1. ~~Scaffold Xcode project + folder layout~~ done
2. Scanner + all three Update Sources + Aggregator, unit-tested independently — next
3. Cache-first UI with manual/auto Refresh
4. One-click update actions per source (deferred, needs its own design pass)

## Agent skills

### Domain docs

Single-context: `CONTEXT.md` at the repo root. See `docs/agents/domain.md`.
