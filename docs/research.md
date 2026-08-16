# Market & User Research

Research pass on the macOS "check installed apps for updates" space, done 2026-08-17 via web search (two parallel research passes: competitor feature/pricing/detection-method survey, and user sentiment from Reddit/HN/forums/reviews). This is a research record, not a roadmap — goals and implementation get decided separately, informed by this.

## Competitor landscape

| App | Price | Detection sources | Positioning |
|---|---|---|---|
| **MacUpdater** (corecode.io) | Free (post-shutdown); was one-time purchase | App Store, Sparkle, Electron, Squirrel, Homebrew, GitHub Releases | **Discontinued Jan 1, 2026.** Was the category benchmark — claimed "realtime updates for 6,800 apps, version info for another 100,000." Single-window list + menu bar, one-click update. |
| **Latest** ([GitHub](https://github.com/mangerlahn/Latest)) | Free, open source (GPL-3.0) | Mac App Store + Sparkle only | Explicitly the "minimal/lightweight" option in every comparison found. Narrower coverage than MacUpdater by design. No batch update, ignore list, or scheduling found. |
| **Updater** ([mac-updater.app](https://www.mac-updater.app/en/)) | Not disclosed | Sparkle, Mac App Store, Homebrew, **+ dev package managers**: NPM, Pip, MacPorts, RubyGems, Cargo, Go, Composer | Broadest source list found (11). Menu bar badge, one-click update, skip/ignore specific versions, configurable notification schedule (hourly–daily). |
| **App Update Monitor** ([onmymenubar.app](https://onmymenubar.app/app-update-monitor/)) | Free | Sparkle, Electron, Squirrel, GitHub Releases, Homebrew — **no Mac App Store** | Closest architectural sibling to Patchly. Menu bar badge + dropdown, background-only (no window), on-demand or scheduled scans, no auto-update without confirmation, no batch update. |
| **Updatest** ([pricing](https://updatest.app/pricing/), [review](https://medium.com/on-tech/updatest-macos-review-a-fast-modern-successor-to-macupdater-423b910b7387)) | $12.99/3 Macs or $24.99/10 Macs, one-time | Sparkle, Mac App Store (via mas-cli), Homebrew, Electron, GitHub Releases, **+ crowdsourced "Community Updates" for apps with no standard channel** | Marketed as MacUpdater's "modern successor." Bulk updates, CLI support, surfaces code-signing/notarization/Gatekeeper status per app. |
| **MacUpdate Desktop** | $9.99–20/yr (sources conflict) | Tied to the MacUpdate.com catalog | One-click "update everything." Still in beta as of 2026. |
| **App Cleaner & Uninstaller** ([nektony.com](https://nektony.com/reviews/top-updaters-for-mac)) | $14.95/yr | App Store, Sparkle, Electron, Squirrel, Homebrew, GitHub | Update-checking bundled inside a cleaner/uninstaller/startup-manager app, not standalone. "Less extensive [update] coverage than MacUpdater." |
| **CleanMyMac** | $40.20/yr | App Store + Sparkle only | Updater is one small module in a full system-cleaner suite (junk removal, malware scan, RAM optimizer). Reviewers: "a supplement, not a full replacement" for a dedicated updater. |
| **MacKeeper** | $71.40/yr | App Store + Sparkle only | Same pattern as CleanMyMac — minor feature inside an antivirus/VPN/cleaner suite. Most expensive, least update-focused. |
| **Setapp** | $9.99+/mo | N/A | Not a real competitor — subscription app-bundle service, auto-updates only apps that are part of its own bundle. No general scanning. |
| **`mas` CLI** ([GitHub](https://github.com/mas-cli/mas)) | Free, OSS | Mac App Store only | What Patchly already shells out to. Requires signed-in Apple Account for `mas outdated`. |
| **`brew cu`** (`homebrew-cask-upgrade`) | Free, OSS | Homebrew casks only | CLI-only batch-upgrade wrapper around `brew`. |

**No source publishes a database-size number except MacUpdater** — repeatedly cited by others as the benchmark competitors fell short of, right up until it died from exactly that database-maintenance burden (frozen since Dec 2025, coverage dropping toward ~3,500 and falling, rising false positives — see [TidBITS](https://tidbits.com/2026/01/09/macupdater-shuts-down-leaving-users-searching-for-alternatives/) and [corecode.io FAQ](https://www.corecode.io/macupdater/faq.html)).

Reviews consistently place tools on a spectrum from "simple/lightweight" (Latest, App Update Monitor) to "does everything" (CleanMyMac, MacKeeper, App Cleaner & Uninstaller — all bundle updating inside cleaner/security suites). **No tool sits at "simple + broad source coverage" simultaneously except possibly Updatest, which is paid.** That's the open position Patchly is closest to occupying: free, no-database, multi-source, menu-bar-only.

## User sentiment (Reddit, HN, MacRumors, App Store reviews, comparison articles)

Reddit itself returned almost nothing directly indexable via search; findings below lean on comparison articles, vendor FAQs, a shutdown retrospective, and one individual App Store review — flagged where a source has a commercial interest.

**Common complaints:**
- **Central-database staleness/rot.** MacUpdater's frozen database is the live example — false positives and missed updates climbing as it goes unmaintained. ([TidBITS](https://tidbits.com/2026/01/09/macupdater-shuts-down-leaving-users-searching-for-alternatives/), [corecode.io FAQ](https://www.corecode.io/macupdater/faq.html))
- **No Mac App Store coverage** in several tools (App Update Monitor, CleanMyMac, MacKeeper) — a recurring gap.
- **Slow scans** — MacUpdater measured at 30s vs. 4s for the fastest competitor in one head-to-head test ([nektony.com](https://nektony.com/reviews/top-updaters-for-mac), vendor-authored, treat as biased).
- **False positives** — called out for MacKeeper and (rarely) Updatest.
- **Bloat / business-practice criticism** — CleanMyMac ("numerous features some find unnecessary," hard to remove) and MacKeeper ("crowded interface") both criticized. ([alternativeto.net](https://www.alternativeto.net/software/cleanmymac/about/))
- **Price resentment** relative to what a pure updater does — MacKeeper $71.40/yr and CleanMyMac $40.20/yr called out next to free/one-time alternatives.

**Common asks:**
- **No database, no staleness** — Updatest explicitly markets "scans each app's own internal metadata, no database" as a direct response to MacUpdater's failure mode.
- **No account/registration, privacy-first** — stated as a selling point by Updatest.
- **Broad source coverage** — the best-reviewed tool in one comparison (App Cleaner & Uninstaller) covered Sparkle + Homebrew + Electron + App Store with "zero false positives" in that test.
- **Menu-bar badge + background scheduled checks + notifications, not a dashboard app** — the norm across App Update Monitor, Updater, and Updatest.
- **Lightweight/simple explicitly valued** — Latest praised for being "100% free" with the "fastest scan," positioned as the deliberately minimal option.
- **One-click / batch update** — the single most consistently-requested feature across nearly every tool and comparison.

One individual end-user quote surfaced (MacUpdate listing for App Update Monitor, 4.0/5 from 4 raters): *"it's a very convenient free utility for those who keep their software up-to-date,"* praising quiet background operation and a simple interface. Broader Reddit/HN discussion specific to this niche is thin online — not padded out further here.

## Implications for Patchly

**Validated, keep doing:**
- No maintained database — MacUpdater's death is direct evidence this is the right call, not a limitation.
- No account, no cloud sync, no telemetry — matches the explicit "privacy-first" ask.
- Menu-bar-only, background scans, badge count — matches the norm across the best-regarded tools.
- Mac App Store coverage — several competitors (App Update Monitor, CleanMyMac, MacKeeper) lack this; Patchly already has it.

**Real gaps, concrete evidence:**
- **No Electron/Squirrel/GitHub-Releases detection.** Every serious competitor covers this. Not hypothetical for us either — in Patchly's own real scan, Discord, Figma, Loom, Miro, and GitHub Copilot all came back `unknownNoSource`, and most are Electron apps with their own update feed.
- **No notifications**, only a badge — the user has to think to check. Every praised competitor pairs a badge with a notification on change.

**Deliberately not competing on:**
- Bundled cleaner/uninstaller/antivirus features — the most-criticized pattern in the whole space (CleanMyMac, MacKeeper).
- Dev package manager coverage (npm/pip/cargo, from Updater) — different job than "which of my `.app`s need updating."
- Crowdsourced community update network (Updatest) — needs a backend server, against zero-infrastructure simplicity.

**Not urgent, worth having eventually:**
- Ignore/skip list per app.
- One-click/batch update — most-requested everywhere, but also the highest-risk feature (different install mechanism per source, needs its own confirmation/error UX). Better after coverage + notifications land.

## Next step

Goals and an implementation plan get set separately, using this as the input.
