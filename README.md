<p align="center">
  <img src="docs/assets/app-icon.png" width="96" alt="Patchly icon" />
  <h1 align="center">Patchly</h1>
</p>

<h3 align="center">Know what's out of date on your Mac, from the menu bar</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-orange.svg" />
  <img src="https://img.shields.io/badge/macOS-26+-blue.svg" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey.svg" />
  <img src="https://github.com/mberrishdev/Patchly/actions/workflows/ci.yml/badge.svg" />
</p>

Patchly sits in the menu bar and scans every app in `/Applications` (plus `/Applications/Utilities` and `~/Applications`), checking each one against the Mac App Store, Homebrew, or its own Sparkle update feed — whichever applies — and shows you which ones actually have an update waiting.

## Requirements

- macOS 26 (Tahoe) on Apple Silicon

## Install

Build from source:

```bash
git clone https://github.com/mberrishdev/Patchly.git
cd Patchly
open Patchly.xcodeproj   # ⌘R
```

Or headless:

```bash
xcodebuild -project Patchly.xcodeproj -scheme Patchly -configuration Debug build
```

Run the tests the same way CI does:

```bash
xcodebuild test -project Patchly.xcodeproj -scheme Patchly -destination 'platform=macOS'
```

A Homebrew cask (`brew install --cask patchly`) is planned once there's a first tagged release.

## Using it

Click the menu bar icon to see the list. Apps with an update available sort to the top, with a badge count next to the icon so you don't even need to open it to know something's out of date. Click any app to reveal it in Finder. A manual Refresh button is always available; Patchly also refreshes automatically on a timer and whenever your Mac wakes from sleep.

Patchly reports update status — it does not install updates for you (yet). See `CONTEXT.md` for exactly why and how each app's status is determined.

## Architecture

- `Patchly/App/` — composition root and app settings
- `Patchly/Scanner/` — app discovery and the three-source update aggregator
- `Patchly/UpdateSources/` — Mac App Store, Homebrew Cask, and Sparkle Feed checkers
- `Patchly/Support/`, `Patchly/Persistence/`, `Patchly/State/`, `Patchly/UI/`

`CONTEXT.md` is the domain doc — binding terminology and behavior.

## Roadmap

1. ~~Scaffold Xcode project + folder layout~~ done
2. Scanner + all three Update Sources + Aggregator, unit-tested independently
3. Cache-first UI with manual/auto Refresh
4. One-click update actions per source

## License

[MIT](LICENSE)
