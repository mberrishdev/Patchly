import Foundation

/// A per-app custom Update Status check — used only for a small, explicitly
/// maintained allowlist of apps that publish none of Patchly's four generic
/// Update Source signals (Mac App Store receipt, Homebrew Cask, an
/// electron-builder `app-update.yml`, a `SUFeedURL`). Not a general
/// detection mechanism: each conformance hardcodes one specific app's own
/// private update API. See CONTEXT.md ("Custom App Source").
protocol CustomAppChecker: Sendable {
    var bundleIdentifier: String { get }
    func checkUpdate(installedVersion: String, bundlePath: String) async -> UpdateCheckResult
}

/// Checks apps attributed to the Custom App Source: matches each
/// `DiscoveredApp`'s bundle identifier against the registry of per-app
/// checkers below, running only for apps actually present in it — everyone
/// else gets no result here and falls through to whatever the rest of
/// `UpdateAggregator`'s priority chain decides. See CONTEXT.md.
struct CustomAppSourceChecker: UpdateSource {
    private let checkers: [any CustomAppChecker]

    init(checkers: [any CustomAppChecker] = [VSCodeUpdateChecker()]) {
        self.checkers = checkers
    }

    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult] {
        // Built by hand rather than `Dictionary(uniqueKeysWithValues:)`,
        // which traps if two registry entries ever share a bundle
        // identifier — a real possibility as more per-app checkers get
        // added here over time, and not something a copy-paste mistake in
        // this small registry should be able to crash the app over. The
        // first entry registered for a given identifier wins.
        var checkersByBundleID: [String: any CustomAppChecker] = [:]
        for checker in checkers where checkersByBundleID[checker.bundleIdentifier] == nil {
            checkersByBundleID[checker.bundleIdentifier] = checker
        }
        let candidates: [(app: DiscoveredApp, checker: any CustomAppChecker)] = apps.compactMap { app in
            guard let bundleIdentifier = app.bundleIdentifier, let checker = checkersByBundleID[bundleIdentifier] else { return nil }
            return (app, checker)
        }
        guard !candidates.isEmpty else { return [:] }

        var results: [String: UpdateCheckResult] = [:]
        await withTaskGroup(of: (String, UpdateCheckResult).self) { group in
            for candidate in candidates {
                group.addTask {
                    let result = await candidate.checker.checkUpdate(
                        installedVersion: candidate.app.installedVersion,
                        bundlePath: candidate.app.bundlePath
                    )
                    return (candidate.app.bundlePath, result)
                }
            }
            for await (bundlePath, result) in group {
                results[bundlePath] = result
            }
        }
        return results
    }
}
