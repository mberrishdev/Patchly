# Patchly

Patchly is a native macOS menu bar utility that scans installed applications and reports which ones have updates available.

Patchly targets macOS 26 on Apple Silicon. It does not ship an Intel executable.
Patchly is a menu-bar-only app with no persistent Dock icon.

## Architecture

- Patchly builds from a committed Xcode project (`Patchly.xcodeproj`) without Tuist or any project generation
- SwiftUI is the entire application shell: a single `MenuBarExtra` scene renders both the status item and its dropdown content; there is no AppKit shell
- Patchly uses Swift 6 with complete strict concurrency
- Patchly has one third-party dependency, the Sparkle framework, used only so Patchly can self-update; Homebrew and mas are still invoked as external command-line tools via `Process`, never linked, and Sparkle appcasts belonging to *other* apps are still parsed with Foundation's `XMLParser` by the read-only Sparkle Feed Source — Patchly's own appcast is the one thing the linked Sparkle framework itself fetches and verifies

## Language

**Scanned App**: An application bundle discovered under `/Applications`, `/Applications/Utilities`, or `~/Applications` — either directly in one of those, or one level into a subfolder of one of those — together with the identity and version fields read from its `Info.plist`.
_Avoid_: Installed app, package

**Update Source**: The origin Patchly attributes a Scanned App to for update-checking purposes: Mac App Store, Homebrew Cask, Electron, or Sparkle Feed.
_Avoid_: Install method, provider

**Mac App Store Source**: An Update Source for a Scanned App whose bundle contains a `Contents/_MASReceipt/receipt` file.
_Avoid_: App Store app, MAS app

**Homebrew Cask Source**: An Update Source for a Scanned App whose bundle filename matches an installed Homebrew cask's `artifacts.app` entry.
_Avoid_: Brew app, cask app

**Electron Source**: An Update Source for a Scanned App whose bundle contains an electron-builder `Contents/Resources/app-update.yml` config file.
_Avoid_: Electron app (many Electron apps ship a custom updater with no `app-update.yml` and are never attributed to this source — the file's presence is the signal, not the framework itself)

**Sparkle Feed Source**: An Update Source for a Scanned App whose `Info.plist` declares a `SUFeedURL`.
_Avoid_: Sparkle app (the app itself may or may not use Sparkle for its own UI; Patchly only reads its feed)

**Update Status**: The result Patchly attaches to a Scanned App after checking its Update Source: Up to Date, Update Available, Checking, Check Failed, or one of the two Unknown states below.
_Avoid_: Version status

**Unknown — No Source**: The Update Status for a Scanned App matching none of the Update Sources.
_Avoid_: Unsupported, error

**Unknown — mas Missing**: The Update Status for a Mac App Store Source app when the `mas` CLI is not installed on the Mac.
_Avoid_: mas error, App Store unavailable

**Refresh**: A full re-run of scanning and all Update Source checks that replaces the in-memory and cached Scanned App list.
_Avoid_: Sync, scan (scan is only the app-discovery step, not the update checks)

**Cache Snapshot**: The most recent Refresh's results, persisted to disk so the dropdown shows results instantly on launch before a new Refresh completes.
_Avoid_: Database, history

**Badge Count**: The number of Scanned Apps currently in Update Available status, shown next to the menu bar icon.
_Avoid_: Notification count, alert count

**Update Action**: How Patchly installs a Scanned App's available update: running `brew upgrade --cask` (Homebrew Cask Source), running `mas upgrade` (Mac App Store Source), or activating the app so its own linked updater runs (Electron Source, Sparkle Feed Source).
_Avoid_: Install method (that term is reserved for Update Source, the detection origin — Update Action is what happens when the user asks to install)

**Selection**: The set of Scanned Apps or CLI Tools the user has checked in the dropdown for a batch Update Action, independent of Update Status or Update Source. Scanned App Selection and CLI Tool Selection are two separate sets — checking apps and CLI Tools at the same time shows two independent "Update Selected" bars, not one combined one.
_Avoid_: Multi-select (describes the UI gesture, not the domain concept)

**CLI Tool**: A Homebrew-installed developer command-line formula (e.g. ripgrep, jq), discovered via `brew list --formula --versions` rather than a fixed name list, directory scan, or per-binary probing, shown in the dropdown by its formula name with its installed version. Always attributed to the Homebrew Formula Source — there's no unattributed CLI Tool state, since Homebrew is the only thing Patchly discovers CLI Tools from at all.
_Avoid_: CLI app, command-line app, Scanned App (a wholly separate concept), binary name (a CLI Tool's name is the Homebrew formula name, e.g. "ripgrep", not necessarily the command you'd type, e.g. "rg")

**Homebrew Formula Source**: The CLI Tool Source — the only one Patchly has. A CLI Tool's Update Status comes from `brew info --json=v2 --formula --installed`, matched directly by formula name.
_Avoid_: Brew formula, formula tool, CLI Tool Source (there's only ever this one, so the more general term is unnecessary)

**Search**: A case-insensitive substring filter on Scanned App and CLI Tool names, applied only to what's currently displayed in the dropdown.
_Avoid_: Filter (Search is the user-typed text specifically; it never changes the Cache Snapshot, sort order, or Refresh behavior)

## Relationships

- A Scanned App with a Mac App Store receipt is always attributed to the Mac App Store Source, even if it would also match a Homebrew Cask or declare a `SUFeedURL`
- A Scanned App without a Mac App Store receipt is attributed to the Homebrew Cask Source when its bundle filename matches an installed cask's `artifacts.app` entry
- A Scanned App matching neither the Mac App Store Source nor the Homebrew Cask Source, with an `app-update.yml` file, is attributed to the Electron Source
- A Scanned App matching none of the above, and declaring a `SUFeedURL`, is attributed to the Sparkle Feed Source
- A Scanned App matching none of the sources gets Unknown — No Source and is never treated as an error
- A Mac App Store Source app is checked with `mas outdated`; if `mas` is not installed, every Mac App Store Source app gets Unknown — mas Missing instead of blocking the rest of the Refresh
- Unknown — mas Missing apps show an inline action offering to run `brew install mas`; completing that action triggers an immediate re-check of Mac App Store Source apps only
- A Homebrew Cask Source app is checked via a single `brew info --cask --json=v2 --installed` call (this one call carries the installed version, latest version, outdated flag, and artifact filenames needed for matching, so no second call is needed); a cask not flagged `outdated` is Up to Date
- A cask flagged `outdated` with no reported latest version is Check Failed, never Up to Date — an outdated cask can never resolve to up to date
- A Sparkle Feed Source app's appcast is fetched and parsed independently per app, concurrently, with a bounded number in flight at once; one app's network failure or malformed feed never blocks another app's check
- A Sparkle Feed Source app whose feed can't be fetched or parsed gets Check Failed, not Unknown
- An Electron Source app with `provider: github` in its `app-update.yml` is checked against the GitHub Releases API (`/repos/{owner}/{repo}/releases/latest`); with `provider: generic`, it's checked against `{url}/latest-mac-arm64.yml`, falling back to `{url}/latest-mac.yml`
- An Electron Source app whose `app-update.yml` names any other provider is Check Failed, not Unknown — the update mechanism is real, Patchly just doesn't parse that provider yet
- An Electron Source app's manifest is fetched independently per app, concurrently, with the same bounded-in-flight and per-app-failure-isolation behavior as the Sparkle Feed Source
- Version comparison for Homebrew, Electron, and Sparkle sources uses dot-separated numeric comparison, never string equality, since "10" must sort after "9"
- Launching Patchly loads the Cache Snapshot into the dropdown immediately, then starts a Refresh in the background; the dropdown never shows a blank or loading-only state on a warm launch
- A Refresh runs automatically on a timer (default six hours, user-configurable) and immediately after the Mac wakes from sleep
- The user can trigger a Refresh manually at any time; a manual Refresh cancels any Refresh already in progress
- The dropdown list sorts Update Available apps first, then Unknown — mas Missing, then Check Failed, then Up to Date, then Unknown — No Source
- Within each status group, apps sort alphabetically by name
- The Badge Count reflects only Update Available apps; Unknown and Check Failed states never contribute to it
- Clicking a Scanned App row reveals it in Finder
- A Homebrew Cask Source app's Update Action is `brew upgrade --cask <token>`; a Mac App Store Source app's is `mas upgrade <app ID>` — both hand off to a CLI that already downloads, verifies, and installs
- A Sparkle Feed Source app whose appcast item has an enclosure URL and an EdDSA signature, and whose own `Info.plist` declares a `SUPublicEDKey`, gets a direct-install Update Action: Patchly downloads the enclosure, verifies its Ed25519 signature against that public key (the same scheme and raw-file-bytes verification Sparkle's own `SUSignatureVerifier` uses), and only on success quits the app if running, replaces its bundle, and relaunches it
- A Sparkle Feed Source app missing any of those three things (enclosure URL, EdDSA signature, or its own public key) falls back to activating the app so its own updater runs instead — this is not an error, just a coverage gap for apps that don't publish everything needed to verify
- A Sparkle Feed Source app's signature verification failing is treated as Check Failed, never as a reason to fall back to activating the app — a failed verification means the download shouldn't be trusted, not that Patchly should try something else with it
- An Electron Source app's Update Action always activates the app so its own linked updater runs; Patchly never downloads an update artifact or replaces an Electron app's bundle itself — reimplementing electron-updater's own update verification is a real security liability (it has a documented signature-bypass history) Patchly avoids taking on for a "best-effort activate the app" feature
- The fallback path (activating the app without a direct install) first clears that app's `SULastCheckTime` default — Sparkle's own documented way to bypass its 24-hour check throttle — so it reliably triggers an immediate check instead of possibly doing nothing; a missing key is not an error. The direct-install path's post-success relaunch skips this, since the app was just verified and replaced with the latest version — there's nothing left to check for
- Clicking Update on a single Scanned App row runs its Update Action immediately, no confirmation
- Checking multiple Scanned Apps and clicking Update Selected shows a confirmation before running every selected app's Update Action
- A failed Update Action sets that Scanned App's Update Status to Check Failed with the failure reason, reusing the existing Check Failed UI rather than a separate error surface
- After a batch of Update Actions completes with at least one success — of any kind, including the fallback activate-only path — Patchly runs a full Refresh, since a Homebrew/Mac App Store install can change more than just the installed app (e.g. local tap metadata)
- A Sparkle Feed Source app's direct-install Update Action quits that app first if it's running, so its bundle isn't replaced out from under a live process; it escalates from a graceful to a forced quit, and gives up (Check Failed) rather than replacing files under a process that won't exit
- Scanning each root directory also looks one level into any subfolder that isn't itself a `.app` (e.g. `/Applications/Development`), since users commonly organize `/Applications` that way; it never looks further than that one level, and never looks inside a matched `.app` bundle's own contents (a helper `.app` nested in another app's `Contents/Frameworks` is not a separate Scanned App)
- A row's Update button reads "Open to Update" instead of "Update" whenever its Update Action is `.launchApp` (always true for the Electron Source, and the Sparkle Feed Source's no-signature fallback) — that action only activates the app and hands off to its own updater, so the label says what actually happens instead of promising a direct install Patchly isn't doing
- Patchly makes no changes to any other app's files outside an explicit, user-initiated Update Action or the `brew install mas` action
- An Electron Source app's Update Action gets a direct-install Update Action when its `latest-mac[-arm64].yml` manifest (published by both the `generic` and `github` providers) includes both a `path` and a `sha512` field: Patchly downloads that artifact, verifies its sha512 checksum, verifies its code signature is valid (`codesign --verify --deep --strict`), and verifies its Team Identifier and bundle identifier both match the already-installed app — only then does it quit the app if running, replace its bundle, and relaunch it, the same replace/relaunch mechanics as the Sparkle Feed Source's direct install
- An Electron Source app missing a `path`, a `sha512`, or the manifest itself falls back to activating the app so its own updater runs, same as the Sparkle Feed Source's no-signature fallback — this is not an error, just a coverage gap for apps whose manifest doesn't publish everything needed to verify
- An Electron Source app's direct-install verification failing (checksum, code signature, Team Identifier, or bundle identifier mismatch) is Check Failed, never a reason to fall back to activating the app — same reasoning as the Sparkle Feed Source: a failed verification means the download shouldn't be trusted, not that Patchly should try something else with it
- Both direct-install Update Actions (Sparkle Feed Source, Electron Source) require macOS's "App Management" permission (System Settings → Privacy & Security → App Management) to actually replace another app's bundle — there's no API to request this proactively; macOS blocks the first write attempt and only then lists Patchly there for the user to grant. A replace blocked by this shows an actionable Check Failed reason telling the user exactly where to grant it, instead of the raw "operation not permitted" OS error
- Patchly self-updates via Sparkle, checked separately from the Refresh cycle: automatically (user-configurable in Settings) and on manual request from the menu bar dropdown or Settings; this never affects Scanned Apps or the Cache Snapshot
- CLI Tools are discovered with a single `brew list --formula --versions` call — no directory scan, no `$PATH`, no per-binary `--version` probe, no symlink resolution; Homebrew already enumerates every formula it installed and its version directly
- CLI Tools are only detected and shown when the user turns on the Show CLI Tools setting, folded into the same Refresh when it's on, skipped entirely when it's off. Both discovery and the Homebrew Formula Source check are local and read-only — no network calls
- Every CLI Tool is attributed to the Homebrew Formula Source by construction, since that's the only thing Patchly discovers CLI Tools from — there's no unattributed CLI Tool state, and no per-tool attribution step (unlike an Update Source's attribution across several possible origins for a Scanned App)
- A CLI Tool's Update Status comes from a single `brew info --json=v2 --formula --installed` call (same one-call-carries-everything shape as the Homebrew Cask Source), matched to each discovered CLI Tool directly by formula name
- A CLI Tool's Update Action hands off to `brew upgrade <formula>` — the same "hand off to a CLI that already downloads, verifies, and installs" reasoning as the Homebrew Cask/Mac App Store Update Actions; a successful CLI Tool update re-runs only the CLI Tool discovery+check pass, never a full Refresh, since it can't change anything about Scanned Apps
- A CLI Tool row shows a checkbox for Selection whenever it has an Update Available, exactly like a Scanned App row — checking multiple CLI Tools and clicking Update Selected shows its own confirmation, independent of any Scanned App Selection, and installs the checked tools in parallel the same way a batch app update does
- The CLI Tools list sorts the same way the Scanned Apps list does — Update Available first, then Check Failed, then Up to Date, then Unknown — No Source, alphabetically within each group — so a tool needing an update isn't buried alphabetically among however many formulae are installed
- A Refresh publishes Scanned Apps as soon as they're ready rather than waiting on CLI Tools too, since there's no reason to hold the app results back for an unrelated check — the two passes start concurrently. `isRefreshing` — and the disabled Refresh button — stays true for the whole duration, not just the apps portion
- The auto-Refresh interval is user-configurable from Settings (1/3/6/12/24 hours), backed by the same `refreshIntervalSeconds` the timer already reads

## Flagged ambiguities

- Activating an app as the fallback Update Action doesn't guarantee an update actually happens — the app's own updater might not check immediately, or the user might quit it first. Patchly has no way to confirm the update completed; the Refresh that follows (every successful Update Action triggers one, not just verified ones) can easily just report the same old version if the app's own update hasn't landed yet by then
- The Electron Source's `provider: github` check uses the unauthenticated GitHub Releases API (60 requests/hour per IP); with many GitHub-provider apps installed and frequent Refreshes this could get rate-limited — accepted for now since it degrades to Check Failed rather than breaking anything, revisit only if it becomes a real problem
- Many Electron apps ship a custom updater with no `app-update.yml` at all (seen firsthand: Discord ships its own native updater module) and are never attributed to the Electron Source — this is an inherent coverage gap, not a bug to chase
- A Sparkle Feed Source direct-install Update Action quitting a running app can lose that app's unsaved state (open documents, browser tabs the app doesn't itself persist, in-progress work) — clicking Update on a single row runs immediately with no confirmation, same as every other Update Action, so this real consequence isn't surfaced to the user before it happens. Whether direct-install specifically deserves its own confirmation, distinct from the general single-row-runs-immediately rule, is unresolved
- Patchly only handles the common case of a Sparkle update archive containing exactly one `.app` at its top level (or, for a `.dmg`, mounted at its top level); an update packaged as an installer `.pkg`, or with additional non-`.app` payloads Sparkle's own updater would normally handle, isn't supported — falls back to Check Failed, not silently ignored
- CLI Tools only ever shows Homebrew-installed formulae — a system tool (git, python3), an `npm install -g`/`cargo install`/`pip`-installed tool, or a hand-copied script never appears, even though each is a real, useful CLI tool a developer might want tracked. This is a deliberate scope choice (a directory-scan-and-probe-everything approach was tried and discarded — see git history — for being both slow at scale and still needing per-source special-casing to check for updates), not a temporary gap

## Example dialogue

> **Dev:** "The build says an app is Check Failed — should we retry it automatically?"
> **Domain expert:** "No. Check Failed only means one Refresh's attempt didn't complete; the next scheduled or manual Refresh will try again naturally. Don't add a separate retry path for one app."
