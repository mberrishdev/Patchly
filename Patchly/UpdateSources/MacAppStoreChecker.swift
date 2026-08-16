import Foundation

/// Checks apps attributed to the Mac App Store Source. If `mas` isn't installed,
/// every such app gets `.unknownMasCliMissing` instead of blocking the rest of
/// the Refresh. See CONTEXT.md.
struct MacAppStoreChecker: UpdateSource {
    private let processRunner: ProcessRunning
    private let masPath: String?

    init(processRunner: ProcessRunning = ProcessRunner(), masPath: String? = ExecutableLocator.locateMas()) {
        self.processRunner = processRunner
        self.masPath = masPath
    }

    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult] {
        let masApps = apps.filter { $0.hasMacAppStoreReceipt }
        guard !masApps.isEmpty else { return [:] }

        guard let masPath else {
            return masApps.reduce(into: [:]) { results, app in
                results[app.bundlePath] = UpdateCheckResult(status: .unknownMasCliMissing)
            }
        }

        do {
            let result = try await processRunner.run(executablePath: masPath, arguments: ["outdated"], timeout: 20)
            // A non-zero exit is always a failed check, even if `mas` printed
            // something to stdout (a warning, a partial line, a sign-in
            // prompt) — that text isn't a valid `outdated` listing and must
            // not be silently parsed into "nothing is outdated."
            guard result.succeeded else {
                let reason = result.standardError.isEmpty
                    ? "mas outdated exited \(result.terminationStatus)"
                    : result.standardError
                return masApps.reduce(into: [:]) { results, app in
                    results[app.bundlePath] = UpdateCheckResult(status: .checkFailed(reason: reason))
                }
            }
            let outdated = Self.parseOutdated(from: result.standardOutput)
            return Self.matchResults(outdated: outdated, apps: masApps)
        } catch {
            return masApps.reduce(into: [:]) { results, app in
                results[app.bundlePath] = UpdateCheckResult(status: .checkFailed(reason: error.localizedDescription))
            }
        }
    }

    /// Parses lines like `1234567890 App Name (1.2.3) -> 1.3.0`.
    /// `mas` has no stable JSON output for `outdated`.
    static func parseOutdated(from output: String) -> [MasOutdatedEntry] {
        let pattern = #"^\d+\s+(.+?)\s+\(([^)]+)\)\s+->\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let line = String(line)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let installedRange = Range(match.range(at: 2), in: line),
                  let latestRange = Range(match.range(at: 3), in: line)
            else { return nil }

            return MasOutdatedEntry(
                name: String(line[nameRange]).trimmingCharacters(in: .whitespaces),
                installedVersion: String(line[installedRange]).trimmingCharacters(in: .whitespaces),
                latestVersion: String(line[latestRange]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    static func matchResults(outdated: [MasOutdatedEntry], apps: [DiscoveredApp]) -> [String: UpdateCheckResult] {
        var entryByName: [String: MasOutdatedEntry] = [:]
        for entry in outdated {
            entryByName[entry.name.lowercased()] = entry
        }

        var results: [String: UpdateCheckResult] = [:]
        for app in apps {
            if let entry = entryByName[app.name.lowercased()] {
                results[app.bundlePath] = UpdateCheckResult(status: .updateAvailable(latestVersion: entry.latestVersion))
            } else {
                results[app.bundlePath] = UpdateCheckResult(status: .upToDate)
            }
        }
        return results
    }
}

struct MasOutdatedEntry: Sendable, Equatable {
    let name: String
    let installedVersion: String
    let latestVersion: String
}
