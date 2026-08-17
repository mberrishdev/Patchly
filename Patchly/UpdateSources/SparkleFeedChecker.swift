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
        guard let latestItem = SparkleAppcastParser.latestItem(among: items),
              let latest = latestItem.shortVersionString ?? latestItem.version
        else {
            return UpdateCheckResult(status: .checkFailed(reason: "No versioned items in appcast"))
        }
        guard VersionComparator.isVersion(latest, greaterThan: app.installedVersion) else {
            return UpdateCheckResult(status: .upToDate)
        }
        return UpdateCheckResult(status: .updateAvailable(latestVersion: latest), action: updateAction(for: latestItem, app: app))
    } catch {
        return UpdateCheckResult(status: .checkFailed(reason: error.localizedDescription))
    }
}

/// Direct install requires everything needed to verify the download before
/// it's trusted: an enclosure URL, its EdDSA signature, and the app's own
/// public key. Missing any of those falls back to just activating the app —
/// there's nothing unsafe about that path, it just can't be verified.
private func updateAction(for item: SparkleAppcastItem, app: DiscoveredApp) -> UpdateAction {
    guard let enclosureURL = item.enclosureURL,
          let edSignatureBase64 = item.edSignatureBase64,
          let publicKeyBase64 = app.sparklePublicEDKey
    else {
        return .launchApp
    }
    return .installSparkleUpdate(enclosureURL: enclosureURL, edSignatureBase64: edSignatureBase64, publicKeyBase64: publicKeyBase64)
}
