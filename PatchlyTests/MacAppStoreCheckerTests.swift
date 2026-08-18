import XCTest
@testable import Patchly

final class MacAppStoreCheckerTests: XCTestCase {
    func testParsesOutdatedLine() {
        let output = "1234567890 Example App (1.2.3) -> 1.3.0\n"
        let entries = MacAppStoreChecker.parseOutdated(from: output)
        XCTAssertEqual(
            entries,
            [MasOutdatedEntry(appID: "1234567890", name: "Example App", installedVersion: "1.2.3", latestVersion: "1.3.0")]
        )
    }

    func testMatchResultsAttachesMasUpgradeAction() {
        let outdated = [MasOutdatedEntry(appID: "1234567890", name: "Example App", installedVersion: "1.2.3", latestVersion: "1.3.0")]
        let apps = [app(name: "Example App", path: "/Applications/Example App.app")]
        let results = MacAppStoreChecker.matchResults(outdated: outdated, apps: apps)
        XCTAssertEqual(results["/Applications/Example App.app"]?.action, .runMasUpgrade(appID: "1234567890"))
    }

    func testMatchResultsFlagsMissingEntryAsUpToDate() {
        let apps = [app(name: "Not Outdated", path: "/Applications/Not Outdated.app")]
        let results = MacAppStoreChecker.matchResults(outdated: [], apps: apps)
        XCTAssertEqual(results["/Applications/Not Outdated.app"]?.status, .upToDate)
    }

    func testTwoInstalledAppsSharingANameAreCheckFailedNotMismatched() {
        // `mas outdated` identifies apps only by display name - if two
        // installed apps share one, blindly matching by name could
        // attribute the wrong App ID to the wrong app and upgrade the
        // wrong one. Both should surface as Check Failed instead.
        let outdated = [MasOutdatedEntry(appID: "111", name: "Example App", installedVersion: "1.0", latestVersion: "1.1")]
        let apps = [
            app(name: "Example App", path: "/Applications/Example App.app"),
            app(name: "Example App", path: "/Applications/Utilities/Example App.app")
        ]
        let results = MacAppStoreChecker.matchResults(outdated: outdated, apps: apps)

        for app in apps {
            guard case .checkFailed = results[app.bundlePath]?.status else {
                return XCTFail("\(app.bundlePath) should be checkFailed when its name is ambiguous")
            }
        }
    }

    func testNonZeroExitWithStdoutIsCheckFailedNotUpToDate() async {
        // `mas` can exit non-zero while still printing something to stdout (a
        // warning, a partial line, a sign-in prompt) — that text must never
        // be parsed as "nothing is outdated."
        let fakeResult = ProcessResult(
            standardOutput: "Please sign in to the App Store.\n",
            standardError: "",
            terminationStatus: 1
        )
        let checker = MacAppStoreChecker(
            processRunner: FakeProcessRunner(outcome: .success(fakeResult)),
            masPath: "/usr/bin/true"
        )
        let apps = [app(name: "Some App", path: "/Applications/Some App.app")]

        let results = await checker.checkUpdates(for: apps)

        guard case .checkFailed = results["/Applications/Some App.app"]?.status else {
            return XCTFail("A non-zero exit must never resolve to upToDate")
        }
    }

    func testThrownErrorIsCheckFailedForEveryMasApp() async {
        let checker = MacAppStoreChecker(
            processRunner: FakeProcessRunner(outcome: .failure(ProcessRunnerError.timedOut)),
            masPath: "/usr/bin/true"
        )
        let apps = [
            app(name: "App One", path: "/Applications/App One.app"),
            app(name: "App Two", path: "/Applications/App Two.app")
        ]

        let results = await checker.checkUpdates(for: apps)

        for app in apps {
            guard case .checkFailed = results[app.bundlePath]?.status else {
                return XCTFail("\(app.name) should be checkFailed when the process throws")
            }
        }
    }

    private func app(name: String, path: String) -> DiscoveredApp {
        DiscoveredApp(
            name: name,
            bundlePath: path,
            bundleIdentifier: nil,
            installedVersion: "1.0",
            hasMacAppStoreReceipt: true,
            sparkleFeedURL: nil
        )
    }
}

private struct FakeProcessRunner: ProcessRunning {
    enum Outcome {
        case success(ProcessResult)
        case failure(Error)
    }

    let outcome: Outcome

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
