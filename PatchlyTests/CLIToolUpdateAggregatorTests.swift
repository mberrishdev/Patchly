import XCTest
@testable import Patchly

final class CLIToolUpdateAggregatorTests: XCTestCase {
    func testMissingHomebrewResultIsCheckFailedNotUnknown() async {
        // Discovery only ever produces Homebrew formulae, so every tool is
        // Homebrew-sourced by construction - a missing entry here means the
        // check itself failed (e.g. `brew info` timed out), not that the
        // tool is unattributed. Leaving the struct-default `.unknownNoSource`
        // in place would render identically to Up to Date in the UI and
        // hide a real failure.
        let tool = CLITool(name: "ripgrep", version: "14.1.1")
        let results = await CLIToolUpdateAggregator.mergeResults(
            discovered: [tool],
            homebrewFormulaChecker: FakeCLIToolUpdateSource(results: [:])
        )

        XCTAssertEqual(results.first?.source, .homebrewFormula)
        guard case .checkFailed = results.first?.updateStatus else {
            return XCTFail("A missing check result should be checkFailed, not \(String(describing: results.first?.updateStatus))")
        }
    }

    func testPresentHomebrewResultIsUsedAsIs() async {
        let tool = CLITool(name: "ripgrep", version: "14.1.1")
        let results = await CLIToolUpdateAggregator.mergeResults(
            discovered: [tool],
            homebrewFormulaChecker: FakeCLIToolUpdateSource(results: [
                "ripgrep": UpdateCheckResult(status: .updateAvailable(latestVersion: "14.1.2"), action: .runBrewUpgradeFormula(formulaName: "ripgrep"))
            ])
        )

        XCTAssertEqual(results.first?.updateStatus, .updateAvailable(latestVersion: "14.1.2"))
    }
}

private struct FakeCLIToolUpdateSource: CLIToolUpdateSource {
    let results: [String: UpdateCheckResult]

    func checkUpdates(for tools: [CLITool]) async -> [String: UpdateCheckResult] {
        results
    }
}
