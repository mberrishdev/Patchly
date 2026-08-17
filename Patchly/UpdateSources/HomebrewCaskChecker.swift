import Foundation

/// Checks apps attributed to the Homebrew Cask Source via a single
/// `brew info --cask --json=v2 --installed` call, matching each cask's
/// `artifacts` app filenames back to scanned bundles. See CONTEXT.md.
struct HomebrewCaskChecker: UpdateSource {
    private let processRunner: ProcessRunning
    private let brewPath: String?

    init(processRunner: ProcessRunning = ProcessRunner(), brewPath: String? = ExecutableLocator.locateBrew()) {
        self.processRunner = processRunner
        self.brewPath = brewPath
    }

    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult] {
        guard let brewPath else { return [:] }

        do {
            let result = try await processRunner.run(
                executablePath: brewPath,
                arguments: ["info", "--cask", "--json=v2", "--installed"],
                timeout: 30
            )
            guard result.succeeded else { return [:] }
            let casks = try Self.parseCasks(from: result.standardOutput)
            return Self.matchResults(casks: casks, apps: apps)
        } catch {
            return [:]
        }
    }

    static func parseCasks(from jsonString: String) throws -> [HomebrewCaskInfo] {
        struct Response: Decodable {
            let casks: [HomebrewCaskInfo]
        }
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(Response.self, from: data).casks
    }

    static func matchResults(casks: [HomebrewCaskInfo], apps: [DiscoveredApp]) -> [String: UpdateCheckResult] {
        var pathByFilename: [String: String] = [:]
        for app in apps {
            pathByFilename[app.bundleFilename] = app.bundlePath
        }

        var results: [String: UpdateCheckResult] = [:]
        for cask in casks {
            for artifactFilename in cask.artifactAppFilenames {
                guard let bundlePath = pathByFilename[artifactFilename] else { continue }
                if cask.outdated {
                    if let latest = cask.version {
                        results[bundlePath] = UpdateCheckResult(
                            status: .updateAvailable(latestVersion: latest),
                            action: .runBrewUpgrade(caskToken: cask.token)
                        )
                    } else {
                        // Homebrew says it's outdated but didn't report what the
                        // latest version is — that's a failed check, never "up
                        // to date" (an outdated cask can't resolve to that).
                        results[bundlePath] = UpdateCheckResult(
                            status: .checkFailed(reason: "\(cask.token) is outdated but brew reported no version")
                        )
                    }
                } else {
                    results[bundlePath] = UpdateCheckResult(status: .upToDate)
                }
            }
        }
        return results
    }
}

struct HomebrewCaskInfo: Decodable, Sendable {
    let token: String
    let version: String?
    let installed: String?
    let outdated: Bool
    let artifacts: [HomebrewCaskArtifact]?

    var artifactAppFilenames: [String] {
        (artifacts ?? []).flatMap { $0.app ?? [] }
    }
}

struct HomebrewCaskArtifact: Decodable, Sendable {
    let app: [String]?
}
