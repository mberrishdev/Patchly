import Foundation

/// Checks apps attributed to the Sparkle Feed Source: fetches each app's appcast
/// concurrently, bounded to `maxConcurrentRequests` in flight at once, so one
/// app's failure never blocks another's. See CONTEXT.md.
struct SparkleFeedChecker: UpdateSource {
    private let session: URLSession
    private let maxConcurrentRequests: Int

    init(session: URLSession = SparkleFeedChecker.makeSession(), maxConcurrentRequests: Int = 8) {
        self.session = session
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult] {
        let candidates = apps.filter { $0.sparkleFeedURL != nil }
        guard !candidates.isEmpty else { return [:] }

        var results: [String: UpdateCheckResult] = [:]
        for chunk in candidates.chunked(into: maxConcurrentRequests) {
            await withTaskGroup(of: (String, UpdateCheckResult).self) { group in
                for app in chunk {
                    group.addTask {
                        (app.bundlePath, await checkSingle(app, session: session))
                    }
                }
                for await (bundlePath, result) in group {
                    results[bundlePath] = result
                }
            }
        }
        return results
    }
}

private func checkSingle(_ app: DiscoveredApp, session: URLSession) async -> UpdateCheckResult {
    guard let feedURL = app.sparkleFeedURL else {
        return UpdateCheckResult(status: .unknownNoSource)
    }
    do {
        let (data, _) = try await session.data(from: feedURL)
        let items = SparkleAppcastParser.parse(data: data)
        guard let latest = SparkleAppcastParser.latestVersion(among: items) else {
            return UpdateCheckResult(status: .checkFailed(reason: "No versioned items in appcast"))
        }
        if VersionComparator.isVersion(latest, greaterThan: app.installedVersion) {
            return UpdateCheckResult(status: .updateAvailable(latestVersion: latest))
        }
        return UpdateCheckResult(status: .upToDate)
    } catch {
        return UpdateCheckResult(status: .checkFailed(reason: error.localizedDescription))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
