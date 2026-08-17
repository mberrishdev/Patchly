import Foundation

/// Checks Homebrew Formula Source CLI Tools' Update Status: a single batched
/// `brew info --json=v2 --formula --installed` call carries every formula's
/// outdated/latest-version data, matched directly by `CLITool.name` — since
/// discovery only ever produces Homebrew formulae, no attribution step is
/// needed. See CONTEXT.md ("Homebrew Formula Source").
struct HomebrewFormulaChecker: CLIToolUpdateSource {
    private let processRunner: ProcessRunning
    private let brewPath: String?

    init(processRunner: ProcessRunning = ProcessRunner(), brewPath: String? = ExecutableLocator.locateBrew()) {
        self.processRunner = processRunner
        self.brewPath = brewPath
    }

    func checkUpdates(for tools: [CLITool]) async -> [String: UpdateCheckResult] {
        guard let brewPath, !tools.isEmpty else { return [:] }

        do {
            let result = try await processRunner.run(
                executablePath: brewPath,
                arguments: ["info", "--json=v2", "--formula", "--installed"],
                timeout: 30
            )
            guard result.succeeded else { return [:] }
            let formulae = try Self.parseFormulae(from: result.standardOutput)
            return Self.matchResults(formulae: formulae, toolNames: Set(tools.map(\.name)))
        } catch {
            return [:]
        }
    }

    static func parseFormulae(from jsonString: String) throws -> [HomebrewFormulaInfo] {
        struct Response: Decodable {
            let formulae: [HomebrewFormulaInfo]
        }
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(Response.self, from: data).formulae
    }

    static func matchResults(formulae: [HomebrewFormulaInfo], toolNames: Set<String>) -> [String: UpdateCheckResult] {
        var results: [String: UpdateCheckResult] = [:]
        for formula in formulae {
            guard toolNames.contains(formula.name) else { continue }
            if formula.outdated {
                if let latest = formula.versions.stable {
                    results[formula.name] = UpdateCheckResult(
                        status: .updateAvailable(latestVersion: latest),
                        action: .runBrewUpgradeFormula(formulaName: formula.name)
                    )
                } else {
                    // Same rule as HomebrewCaskChecker: outdated with no
                    // reported version is a failed check, never "up to date".
                    results[formula.name] = UpdateCheckResult(
                        status: .checkFailed(reason: "\(formula.name) is outdated but brew reported no version")
                    )
                }
            } else {
                results[formula.name] = UpdateCheckResult(status: .upToDate)
            }
        }
        return results
    }
}

struct HomebrewFormulaInfo: Decodable, Sendable {
    let name: String
    let outdated: Bool
    let versions: Versions

    struct Versions: Decodable, Sendable {
        let stable: String?
    }
}
