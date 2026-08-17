import XCTest
@testable import Patchly

final class CLIToolScannerTests: XCTestCase {
    func testParsesFormulaeAndVersionsFromBrewListOutput() async {
        let runner = FakeProcessRunner(output: "ripgrep 14.1.1\njq 1.7.1\n")
        let scanner = CLIToolScanner(processRunner: runner, brewPath: "/opt/homebrew/bin/brew")

        let tools = await scanner.scanInstalledTools()

        XCTAssertEqual(tools.map(\.name), ["jq", "ripgrep"])
        XCTAssertEqual(tools.first { $0.name == "ripgrep" }?.version, "14.1.1")
    }

    func testMultipleInstalledVersionsUsesTheLastOneListed() {
        let tools = CLIToolScanner.parse("python@3.11 3.11.6 3.11.7\n")
        XCTAssertEqual(tools.first?.version, "3.11.7")
    }

    func testMalformedLineIsSkipped() {
        let tools = CLIToolScanner.parse("not-a-valid-line\nripgrep 14.1.1\n")
        XCTAssertEqual(tools.map(\.name), ["ripgrep"])
    }

    func testEmptyOutputProducesNoTools() {
        XCTAssertTrue(CLIToolScanner.parse("").isEmpty)
    }

    func testNoBrewInstalledProducesNoTools() async {
        let runner = FakeProcessRunner(output: "ripgrep 14.1.1\n")
        let scanner = CLIToolScanner(processRunner: runner, brewPath: nil)

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }

    func testNonZeroExitProducesNoTools() async {
        let runner = FakeProcessRunner(output: "", terminationStatus: 1)
        let scanner = CLIToolScanner(processRunner: runner, brewPath: "/opt/homebrew/bin/brew")

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }

    func testThrownErrorProducesNoTools() async {
        let runner = FakeProcessRunner(shouldThrow: true)
        let scanner = CLIToolScanner(processRunner: runner, brewPath: "/opt/homebrew/bin/brew")

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }
}

private final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let output: String
    private let terminationStatus: Int32
    private let shouldThrow: Bool

    init(output: String = "", terminationStatus: Int32 = 0, shouldThrow: Bool = false) {
        self.output = output
        self.terminationStatus = terminationStatus
        self.shouldThrow = shouldThrow
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        if shouldThrow {
            throw ProcessRunnerError.timedOut
        }
        return ProcessResult(standardOutput: output, standardError: "", terminationStatus: terminationStatus)
    }
}
