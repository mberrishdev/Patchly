import Foundation

/// Runs the discovery scan and the Homebrew Formula Source check
/// concurrently, then attributes each matched CLI Tool. Mirrors
/// `UpdateAggregator`. See CONTEXT.md.
actor CLIToolUpdateAggregator {
    private let scanner: CLIToolScanner
    private let homebrewFormulaChecker: any CLIToolUpdateSource

    init(
        scanner: CLIToolScanner = CLIToolScanner(),
        homebrewFormulaChecker: any CLIToolUpdateSource = HomebrewFormulaChecker()
    ) {
        self.scanner = scanner
        self.homebrewFormulaChecker = homebrewFormulaChecker
    }

    func refresh() async -> [CLITool] {
        let discovered = await scanner.scanInstalledTools()
        return await Self.mergeResults(discovered: discovered, homebrewFormulaChecker: homebrewFormulaChecker)
    }

    static func mergeResults(
        discovered: [CLITool],
        homebrewFormulaChecker: any CLIToolUpdateSource
    ) async -> [CLITool] {
        let homebrew = await homebrewFormulaChecker.checkUpdates(for: discovered)
        let now = Date()

        return discovered.map { tool in
            var tool = tool
            tool.lastCheckedAt = now
            // Discovery only ever produces Homebrew formulae, so every tool
            // is Homebrew-sourced by construction — a missing entry in
            // `homebrew` just means the check itself failed or hasn't
            // matched it yet, not that it's unattributed.
            tool.source = .homebrewFormula
            if let result = homebrew[tool.name] {
                tool.updateStatus = result.status
                tool.updateAction = result.action
            } else {
                // A missing entry here means the check itself failed (e.g.
                // `brew info` timed out or returned malformed JSON), not
                // that the tool is unattributed — it's already known to be
                // Homebrew-sourced by construction, so leaving the struct
                // default `.unknownNoSource` in place would render
                // identically to Up to Date and hide a real failure.
                tool.updateStatus = .checkFailed(reason: "No result")
            }
            return tool
        }
    }
}
