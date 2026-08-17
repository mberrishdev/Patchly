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
        let action: UpdateAction?

        switch config.provider {
        case .github(let owner, let repo):
            let release = try await fetchLatestGitHubRelease(owner: owner, repo: repo, session: session)
            latest = release.version
            action = await directInstallAction(forGitHubRelease: release, session: session)
        case .generic(let baseURL):
            let manifest = try await fetchLatestGenericManifest(baseURL: baseURL, session: session)
            latest = manifest.version
            action = directInstallAction(forGenericManifest: manifest, baseURL: baseURL)
        case .unsupported(let providerName):
            return UpdateCheckResult(status: .checkFailed(reason: "unsupported update provider: \(providerName)"))
        }

        if VersionComparator.isVersion(latest, greaterThan: app.installedVersion) {
            return UpdateCheckResult(status: .updateAvailable(latestVersion: latest), action: action ?? .launchApp)
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

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubRelease {
    let version: String
    let assets: [GitHubReleaseAsset]
}

private func fetchLatestGitHubRelease(owner: String, repo: String, session: URLSession) async throws -> GitHubRelease {
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
    let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
    return GitHubRelease(version: version, assets: release.assets)
}

/// electron-builder publishes a `latest-mac-arm64.yml`/`latest-mac.yml`
/// manifest as a release asset alongside the actual update archive, even for
/// the `github` provider — the same manifest the `generic` provider serves
/// directly over HTTP, just attached to the release instead. Fetching it
/// gives the sha512 checksum `ElectronDirectInstaller` needs. When it isn't
/// published, Patchly can't verify a download safely — a coverage gap, not
/// an error, so this just returns nil and the caller falls back to
/// `.launchApp`.
private func directInstallAction(forGitHubRelease release: GitHubRelease, session: URLSession) async -> UpdateAction? {
    guard let manifestAsset = release.assets.first(where: { $0.name == "latest-mac-arm64.yml" })
        ?? release.assets.first(where: { $0.name == "latest-mac.yml" })
    else { return nil }

    guard let (data, response) = try? await session.data(from: manifestAsset.browserDownloadURL),
          let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
          let text = String(data: data, encoding: .utf8),
          let manifest = ElectronUpdateManifestParser.parse(text),
          let path = manifest.path, let sha512 = manifest.sha512,
          let archiveAsset = release.assets.first(where: { $0.name == path })
    else { return nil }

    return .installElectronUpdate(archiveURL: archiveAsset.browserDownloadURL, expectedSHA512Base64: sha512)
}

private func directInstallAction(forGenericManifest manifest: ElectronUpdateManifest, baseURL: String) -> UpdateAction? {
    guard let path = manifest.path, let sha512 = manifest.sha512, let base = URL(string: baseURL) else {
        return nil
    }
    return .installElectronUpdate(archiveURL: base.appendingPathComponent(path), expectedSHA512Base64: sha512)
}

/// electron-builder publishes per-arch manifests (`latest-mac-arm64.yml`) as
/// well as a combined one (`latest-mac.yml`) — try the arch-specific file
/// first since it's the one that actually applies to an Apple-Silicon-only
/// app, falling back to the combined manifest.
private func fetchLatestGenericManifest(baseURL: String, session: URLSession) async throws -> ElectronUpdateManifest {
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
                  let manifest = ElectronUpdateManifestParser.parse(text)
            else {
                lastError = ElectronUpdateCheckerError.badResponse
                continue
            }
            return manifest
        } catch {
            lastError = error
        }
    }
    throw lastError
}
