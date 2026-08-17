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
        let checkersByBundleID = Dictionary(uniqueKeysWithValues: checkers.map { ($0.bundleIdentifier, $0) })
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
