import XCTest
@testable import Patchly

final class CLIToolScannerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchlyCLIToolScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testResolvedToolWithVersionOutputIsIncluded() async throws {
        try makeExecutable(named: "git")
        let runner = FakeProcessRunner(outputsByExecutablePath: [
            path(for: "git"): "git version 2.43.0\n"
        ])
        let scanner = CLIToolScanner(processRunner: runner, toolNames: ["git"], directories: [tempDirectory])

        let tools = await scanner.scanInstalledTools()

        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "git")
        XCTAssertEqual(tools.first?.executablePath, path(for: "git"))
        XCTAssertEqual(tools.first?.version, "git version 2.43.0")
    }

    func testMissingToolIsOmittedNotAnError() async {
        let runner = FakeProcessRunner(outputsByExecutablePath: [:])
        let scanner = CLIToolScanner(processRunner: runner, toolNames: ["nonexistent-tool"], directories: [tempDirectory])

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }

    func testResolvedToolThatFailsToRunIsSkippedNotAnError() async throws {
        try makeExecutable(named: "broken")
        let runner = FakeProcessRunner(failingExecutablePaths: [path(for: "broken")])
        let scanner = CLIToolScanner(processRunner: runner, toolNames: ["broken"], directories: [tempDirectory])

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }

    func testResolvedToolWithNonZeroExitIsSkipped() async throws {
        try makeExecutable(named: "quirky")
        let runner = FakeProcessRunner(nonZeroExitExecutablePaths: [path(for: "quirky")])
        let scanner = CLIToolScanner(processRunner: runner, toolNames: ["quirky"], directories: [tempDirectory])

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }

    func testResolvedToolWithEmptyOutputIsSkipped() async throws {
        try makeExecutable(named: "silent")
        let runner = FakeProcessRunner(outputsByExecutablePath: [path(for: "silent"): ""])
        let scanner = CLIToolScanner(processRunner: runner, toolNames: ["silent"], directories: [tempDirectory])

        let tools = await scanner.scanInstalledTools()

        XCTAssertTrue(tools.isEmpty)
    }

    func testFirstLineOfMultilineOutputIsUsed() {
        let output = "v20.11.0\nSome extra debug info\n"
        XCTAssertEqual(CLIToolScanner.firstLine(of: output), "v20.11.0")
    }

    func testResultsAreSortedAlphabetically() async throws {
        try makeExecutable(named: "npm")
        try makeExecutable(named: "git")
        let runner = FakeProcessRunner(outputsByExecutablePath: [
            path(for: "npm"): "10.2.0\n",
            path(for: "git"): "git version 2.43.0\n"
        ])
        let scanner = CLIToolScanner(processRunner: runner, toolNames: ["npm", "git"], directories: [tempDirectory])

        let tools = await scanner.scanInstalledTools()

        XCTAssertEqual(tools.map(\.name), ["git", "npm"])
    }

    private func path(for name: String) -> String {
        tempDirectory.appendingPathComponent(name).path
    }

    private func makeExecutable(named name: String) throws {
        let filePath = path(for: name)
        FileManager.default.createFile(atPath: filePath, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePath)
    }
}

private final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let outputsByExecutablePath: [String: String]
    private let failingExecutablePaths: Set<String>
    private let nonZeroExitExecutablePaths: Set<String>

    init(
        outputsByExecutablePath: [String: String] = [:],
        failingExecutablePaths: Set<String> = [],
        nonZeroExitExecutablePaths: Set<String> = []
    ) {
        self.outputsByExecutablePath = outputsByExecutablePath
        self.failingExecutablePaths = failingExecutablePaths
        self.nonZeroExitExecutablePaths = nonZeroExitExecutablePaths
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        if failingExecutablePaths.contains(executablePath) {
            throw ProcessRunnerError.timedOut
        }
        if nonZeroExitExecutablePaths.contains(executablePath) {
            return ProcessResult(standardOutput: "", standardError: "boom", terminationStatus: 1)
        }
        let output = outputsByExecutablePath[executablePath] ?? ""
        return ProcessResult(standardOutput: output, standardError: "", terminationStatus: 0)
    }
}
