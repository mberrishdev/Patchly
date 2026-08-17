import XCTest
@testable import Patchly

final class UpdateInstallerTests: XCTestCase {
    func testNoUpdateActionFailsImmediately() async {
        let installer = UpdateInstaller(processRunner: RecordingProcessRunner(outcome: .success(.ok)), brewPath: "/opt/homebrew/bin/brew", masPath: "/opt/homebrew/bin/mas")
        let result = await installer.install(app(updateAction: nil))
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.failureReason, "No update action available")
    }

    func testBrewUpgradeRunsCorrectArguments() async {
        let runner = RecordingProcessRunner(outcome: .success(.ok))
        let installer = UpdateInstaller(processRunner: runner, brewPath: "/opt/homebrew/bin/brew", masPath: nil)

        let result = await installer.install(app(updateAction: .runBrewUpgrade(caskToken: "maccy")))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(runner.lastExecutablePath, "/opt/homebrew/bin/brew")
        XCTAssertEqual(runner.lastArguments, ["upgrade", "--cask", "maccy"])
    }

    func testMasUpgradeRunsCorrectArguments() async {
        let runner = RecordingProcessRunner(outcome: .success(.ok))
        let installer = UpdateInstaller(processRunner: runner, brewPath: nil, masPath: "/opt/homebrew/bin/mas")

        let result = await installer.install(app(updateAction: .runMasUpgrade(appID: "409183694")))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(runner.lastExecutablePath, "/opt/homebrew/bin/mas")
        XCTAssertEqual(runner.lastArguments, ["upgrade", "409183694"])
    }

    func testMissingBrewFailsWithoutRunningAnything() async {
        let runner = RecordingProcessRunner(outcome: .success(.ok))
        let installer = UpdateInstaller(processRunner: runner, brewPath: nil, masPath: nil)

        let result = await installer.install(app(updateAction: .runBrewUpgrade(caskToken: "maccy")))

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.failureReason, "Homebrew not found")
        XCTAssertNil(runner.lastExecutablePath)
    }

    func testNonZeroExitSurfacesStderrAsFailureReason() async {
        let failed = ProcessResult(standardOutput: "", standardError: "Error: Cask 'maccy' is not installed.", terminationStatus: 1)
        let runner = RecordingProcessRunner(outcome: .success(failed))
        let installer = UpdateInstaller(processRunner: runner, brewPath: "/opt/homebrew/bin/brew", masPath: nil)

        let result = await installer.install(app(updateAction: .runBrewUpgrade(caskToken: "maccy")))

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.failureReason, "Error: Cask 'maccy' is not installed.")
    }

    func testThrownErrorBecomesFailureReason() async {
        let runner = RecordingProcessRunner(outcome: .failure(ProcessRunnerError.timedOut))
        let installer = UpdateInstaller(processRunner: runner, brewPath: "/opt/homebrew/bin/brew", masPath: nil)

        let result = await installer.install(app(updateAction: .runBrewUpgrade(caskToken: "maccy")))

        XCTAssertFalse(result.succeeded)
        XCTAssertNotNil(result.failureReason)
    }

    func testSparkleLaunchClearsSULastCheckTimeFirst() async {
        let runner = RecordingProcessRunner(outcome: .success(.ok))
        let installer = UpdateInstaller(processRunner: runner, brewPath: nil, masPath: nil)

        _ = await installer.install(app(
            source: .sparkleFeed,
            bundleIdentifier: "com.example.sparkleapp",
            updateAction: .launchApp
        ))

        XCTAssertEqual(runner.lastExecutablePath, "/usr/bin/defaults")
        XCTAssertEqual(runner.lastArguments, ["delete", "com.example.sparkleapp", "SULastCheckTime"])
    }

    func testElectronLaunchDoesNotTouchDefaults() async {
        let runner = RecordingProcessRunner(outcome: .success(.ok))
        let installer = UpdateInstaller(processRunner: runner, brewPath: nil, masPath: nil)

        _ = await installer.install(app(
            source: .electron,
            bundleIdentifier: "com.example.electronapp",
            updateAction: .launchApp
        ))

        XCTAssertNil(runner.lastExecutablePath)
    }

    private func app(
        source: AppSource = .homebrewCask,
        bundleIdentifier: String? = "com.example.app",
        updateAction: UpdateAction?
    ) -> ScannedApp {
        ScannedApp(
            id: "com.example.app",
            name: "Example",
            bundlePath: "/Applications/Example.app",
            bundleIdentifier: bundleIdentifier,
            installedVersion: "1.0.0",
            source: source,
            updateStatus: .updateAvailable(latestVersion: "1.1.0"),
            lastCheckedAt: nil,
            updateAction: updateAction
        )
    }
}

private extension ProcessResult {
    static let ok = ProcessResult(standardOutput: "", standardError: "", terminationStatus: 0)
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    enum Outcome {
        case success(ProcessResult)
        case failure(Error)
    }

    private let outcome: Outcome
    private(set) var lastExecutablePath: String?
    private(set) var lastArguments: [String]?

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        lastExecutablePath = executablePath
        lastArguments = arguments
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
