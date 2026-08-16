# Patchly

Patchly is a native macOS menu bar utility that scans installed applications and reports which ones have updates available.

Patchly targets macOS 26 on Apple Silicon. It does not ship an Intel executable.
Patchly is a menu-bar-only app with no persistent Dock icon.
The first implementation milestone reports update status only; it does not install updates on the user's behalf.

## Architecture

- Patchly builds from a committed Xcode project (`Patchly.xcodeproj`) without Tuist or any project generation
- SwiftUI is the entire application shell: a single `MenuBarExtra` scene renders both the status item and its dropdown content; there is no AppKit shell
- Patchly uses Swift 6 with complete strict concurrency
- Patchly has zero third-party dependencies: Homebrew and mas are invoked as external command-line tools via `Process`, never linked; Sparkle appcasts belonging to *other* apps are parsed with Foundation's `XMLParser`, and Patchly does not use the Sparkle framework itself since it does not self-update in this milestone

## Language

**Scanned App**: An application bundle discovered under `/Applications`, `/Applications/Utilities`, or `~/Applications`, together with the identity and version fields read from its `Info.plist`.
_Avoid_: Installed app, package

**Update Source**: The origin Patchly attributes a Scanned App to for update-checking purposes: Mac App Store, Homebrew Cask, or Sparkle Feed.
_Avoid_: Install method, provider

**Mac App Store Source**: An Update Source for a Scanned App whose bundle contains a `Contents/_MASReceipt/receipt` file.
_Avoid_: App Store app, MAS app

**Homebrew Cask Source**: An Update Source for a Scanned App whose bundle filename matches an installed Homebrew cask's `artifacts.app` entry.
_Avoid_: Brew app, cask app

**Sparkle Feed Source**: An Update Source for a Scanned App whose `Info.plist` declares a `SUFeedURL`.
_Avoid_: Sparkle app (the app itself may or may not use Sparkle for its own UI; Patchly only reads its feed)

**Update Status**: The result Patchly attaches to a Scanned App after checking its Update Source: Up to Date, Update Available, Checking, Check Failed, or one of the two Unknown states below.
_Avoid_: Version status

**Unknown — No Source**: The Update Status for a Scanned App matching none of the three Update Sources.
_Avoid_: Unsupported, error

**Unknown — mas Missing**: The Update Status for a Mac App Store Source app when the `mas` CLI is not installed on the Mac.
_Avoid_: mas error, App Store unavailable

**Refresh**: A full re-run of scanning and all three Update Source checks that replaces the in-memory and cached Scanned App list.
_Avoid_: Sync, scan (scan is only the app-discovery step, not the update checks)

**Cache Snapshot**: The most recent Refresh's results, persisted to disk so the dropdown shows results instantly on launch before a new Refresh completes.
_Avoid_: Database, history

**Badge Count**: The number of Scanned Apps currently in Update Available status, shown next to the menu bar icon.
_Avoid_: Notification count, alert count

## Relationships

- A Scanned App with a Mac App Store receipt is always attributed to the Mac App Store Source, even if it would also match a Homebrew Cask or declare a `SUFeedURL`
- A Scanned App without a Mac App Store receipt is attributed to the Homebrew Cask Source when its bundle filename matches an installed cask's `artifacts.app` entry
- A Scanned App matching neither the Mac App Store Source nor the Homebrew Cask Source, and declaring a `SUFeedURL`, is attributed to the Sparkle Feed Source
- A Scanned App matching none of the three sources gets Unknown — No Source and is never treated as an error
- A Mac App Store Source app is checked with `mas outdated`; if `mas` is not installed, every Mac App Store Source app gets Unknown — mas Missing instead of blocking the rest of the Refresh
- Unknown — mas Missing apps show an inline action offering to run `brew install mas`; completing that action triggers an immediate re-check of Mac App Store Source apps only
- A Homebrew Cask Source app is checked via a single `brew info --cask --json=v2 --installed` call (this one call carries the installed version, latest version, outdated flag, and artifact filenames needed for matching, so no second call is needed); a cask not flagged `outdated` is Up to Date
- A cask flagged `outdated` with no reported latest version is Check Failed, never Up to Date — an outdated cask can never resolve to up to date
- A Sparkle Feed Source app's appcast is fetched and parsed independently per app, concurrently, with a bounded number in flight at once; one app's network failure or malformed feed never blocks another app's check
- A Sparkle Feed Source app whose feed can't be fetched or parsed gets Check Failed, not Unknown
- Version comparison for Homebrew and Sparkle sources uses dot-separated numeric comparison, never string equality, since "10" must sort after "9"
- Launching Patchly loads the Cache Snapshot into the dropdown immediately, then starts a Refresh in the background; the dropdown never shows a blank or loading-only state on a warm launch
- A Refresh runs automatically on a timer (default six hours, user-configurable) and immediately after the Mac wakes from sleep
- The user can trigger a Refresh manually at any time; a manual Refresh cancels any Refresh already in progress
- The dropdown list sorts Update Available apps first, then Unknown — mas Missing, then Check Failed, then Up to Date, then Unknown — No Source
- Within each status group, apps sort alphabetically by name
- The Badge Count reflects only Update Available apps; Unknown and Check Failed states never contribute to it
- Clicking a Scanned App row reveals it in Finder; Patchly does not install, launch an updater, or run `brew upgrade`/`mas upgrade` on the user's behalf in this milestone
- Patchly makes no changes to any other app's files; every external command it runs is read-only except the explicit, user-initiated `brew install mas` action

## Flagged ambiguities

- One-click "install this update" per source is deferred; each source's update mechanism (`brew upgrade --cask`, `mas upgrade`, launching the target app's own Sparkle updater) needs its own confirmation/progress/error handling and is out of scope for the first milestone
- Whether Patchly should also scan one level of subfolders inside `/Applications` (some vendors nest `.app` bundles) is unresolved; v1 only scans top-level `.app` bundles in each root directory

## Example dialogue

> **Dev:** "The build says an app is Check Failed — should we retry it automatically?"
> **Domain expert:** "No. Check Failed only means one Refresh's attempt didn't complete; the next scheduled or manual Refresh will try again naturally. Don't add a separate retry path for one app."
