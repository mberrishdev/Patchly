import XCTest
@testable import Patchly

final class HomebrewFormulaCheckerTests: XCTestCase {
    // Captured shape from a real `brew info --json=v2 --formula --installed` run.
    private let sampleJSON = """
    {
      "formulae": [
        { "name": "ripgrep", "outdated": true, "versions": { "stable": "14.1.1" } },
        { "name": "jq", "outdated": false, "versions": { "stable": "1.7.1" } },
        { "name": "partial-formula", "outdated": true, "versions": { "stable": null } }
      ],
      "casks": []
    }
    """

    func testParsesFormulaeFromRealSchema() throws {
        let formulae = try HomebrewFormulaChecker.parseFormulae(from: sampleJSON)
        XCTAssertEqual(formulae.count, 3)
        XCTAssertEqual(formulae.first?.name, "ripgrep")
    }

    func testMatchResultsFlagsOutdatedFormulaAsUpdateAvailable() throws {
        let formulae = try HomebrewFormulaChecker.parseFormulae(from: sampleJSON)
        let results = HomebrewFormulaChecker.matchResults(formulae: formulae, toolNames: ["ripgrep"])

        guard case .updateAvailable(let latest) = results["ripgrep"]?.status else {
            return XCTFail("Expected updateAvailable status")
        }
        XCTAssertEqual(latest, "14.1.1")
        XCTAssertEqual(results["ripgrep"]?.action, .runBrewUpgradeFormula(formulaName: "ripgrep"))
    }

    func testMatchResultsFlagsCurrentFormulaAsUpToDate() throws {
        let formulae = try HomebrewFormulaChecker.parseFormulae(from: sampleJSON)
        let results = HomebrewFormulaChecker.matchResults(formulae: formulae, toolNames: ["jq"])

        XCTAssertEqual(results["jq"]?.status, .upToDate)
    }

    func testOutdatedFormulaWithNoReportedVersionIsCheckFailedNotUpToDate() throws {
        let formulae = try HomebrewFormulaChecker.parseFormulae(from: sampleJSON)
        let results = HomebrewFormulaChecker.matchResults(formulae: formulae, toolNames: ["partial-formula"])

        guard case .checkFailed = results["partial-formula"]?.status else {
            return XCTFail("An outdated formula with no version must never resolve to upToDate")
        }
    }

    func testUnrequestedFormulaProducesNoResult() throws {
        let formulae = try HomebrewFormulaChecker.parseFormulae(from: sampleJSON)
        let results = HomebrewFormulaChecker.matchResults(formulae: formulae, toolNames: ["nonexistent"])

        XCTAssertTrue(results.isEmpty)
    }

    func testNoBrewInstalledProducesNoResults() async {
        let checker = HomebrewFormulaChecker(processRunner: FakeProcessRunner(output: sampleJSON), brewPath: nil)
        let results = await checker.checkUpdates(for: [CLITool(name: "ripgrep", version: "14.1.0")])
        XCTAssertTrue(results.isEmpty)
    }

    func testNoToolsProducesNoResultsWithoutCallingBrew() async {
        let runner = FakeProcessRunner(output: sampleJSON)
        let checker = HomebrewFormulaChecker(processRunner: runner, brewPath: "/opt/homebrew/bin/brew")
        let results = await checker.checkUpdates(for: [])
        XCTAssertTrue(results.isEmpty)
    }
}

private final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let output: String
    private let terminationStatus: Int32

    init(output: String, terminationStatus: Int32 = 0) {
        self.output = output
        self.terminationStatus = terminationStatus
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        ProcessResult(standardOutput: output, standardError: "", terminationStatus: terminationStatus)
    }
}
