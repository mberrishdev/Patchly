import Foundation

/// Checks apps attributed to the Electron Update Source: apps shipping an
/// electron-builder `app-update.yml`. Fetches concurrently, bounded to
/// `maxConcurrentRequests` in flight at once, same as SparkleFeedChecker.
/// See CONTEXT.md.
struct ElectronUpdateChecker: UpdateSource {
    private let session: URLSession
    private let maxConcurrentRequests: Int

    init(session: URLSession = ElectronUpdateChecker.makeSession(), maxConcurrentRequests: Int = 8) {
        self.session = session
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult] {
        let candidates = apps.filter { $0.electronUpdateConfig != nil }
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
    guard let config = app.electronUpdateConfig else {
        return UpdateCheckResult(status: .unknownNoSource)
    }

    do {
        let latest: String
        switch config.provider {
        case .github(let owner, let repo):
            latest = try await fetchLatestGitHubTag(owner: owner, repo: repo, session: session)
        case .generic(let baseURL):
            latest = try await fetchLatestGenericVersion(baseURL: baseURL, session: session)
        case .unsupported(let providerName):
            return UpdateCheckResult(status: .checkFailed(reason: "unsupported update provider: \(providerName)"))
        }

        if VersionComparator.isVersion(latest, greaterThan: app.installedVersion) {
            return UpdateCheckResult(status: .updateAvailable(latestVersion: latest))
        }
        return UpdateCheckResult(status: .upToDate)
    } catch {
        return UpdateCheckResult(status: .checkFailed(reason: error.localizedDescription))
    }
}

private enum ElectronUpdateCheckerError: Error, LocalizedError {
    case invalidURL
    case badResponse
    case noVersionFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: "invalid update URL"
        case .badResponse: "update server returned an unexpected response"
        case .noVersionFound: "no version found in update manifest"
        }
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private func fetchLatestGitHubTag(owner: String, repo: String, session: URLSession) async throws -> String {
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
        throw ElectronUpdateCheckerError.invalidURL
    }
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw ElectronUpdateCheckerError.badResponse
    }
    let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
    return release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
}

/// electron-builder publishes per-arch manifests (`latest-mac-arm64.yml`) as
/// well as a combined one (`latest-mac.yml`) — try the arch-specific file
/// first since it's the one that actually applies to an Apple-Silicon-only
/// app, falling back to the combined manifest.
private func fetchLatestGenericVersion(baseURL: String, session: URLSession) async throws -> String {
    guard let base = URL(string: baseURL) else {
        throw ElectronUpdateCheckerError.invalidURL
    }

    var lastError: Error = ElectronUpdateCheckerError.noVersionFound
    for filename in ["latest-mac-arm64.yml", "latest-mac.yml"] {
        let url = base.appendingPathComponent(filename)
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let text = String(data: data, encoding: .utf8),
                  let version = extractVersion(fromYAML: text)
            else {
                lastError = ElectronUpdateCheckerError.badResponse
                continue
            }
            return version
        } catch {
            lastError = error
        }
    }
    throw lastError
}

private func extractVersion(fromYAML text: String) -> String? {
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("version:") else { continue }
        let value = trimmed.dropFirst("version:".count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
    return nil
}

