import XCTest
@testable import Patchly

final class CustomAppSourceCheckerTests: XCTestCase {
    func testMatchesAppByBundleIdentifierAgainstRegistry() async {
        let fakeChecker = FakeCustomAppChecker(bundleIdentifier: "com.example.app", result: UpdateCheckResult(status: .upToDate))
        let checker = CustomAppSourceChecker(checkers: [fakeChecker])
        let app = discoveredApp(bundleIdentifier: "com.example.app", bundlePath: "/Applications/Example.app")

        let results = await checker.checkUpdates(for: [app])

        XCTAssertEqual(results["/Applications/Example.app"]?.status, .upToDate)
    }

    func testAppNotInRegistryProducesNoResult() async {
        let fakeChecker = FakeCustomAppChecker(bundleIdentifier: "com.example.app", result: UpdateCheckResult(status: .upToDate))
        let checker = CustomAppSourceChecker(checkers: [fakeChecker])
        let app = discoveredApp(bundleIdentifier: "com.other.app", bundlePath: "/Applications/Other.app")

        let results = await checker.checkUpdates(for: [app])

        XCTAssertTrue(results.isEmpty)
    }

    func testAppWithNoBundleIdentifierProducesNoResult() async {
        let fakeChecker = FakeCustomAppChecker(bundleIdentifier: "com.example.app", result: UpdateCheckResult(status: .upToDate))
        let checker = CustomAppSourceChecker(checkers: [fakeChecker])
        let app = discoveredApp(bundleIdentifier: nil, bundlePath: "/Applications/NoID.app")

        let results = await checker.checkUpdates(for: [app])

        XCTAssertTrue(results.isEmpty)
    }

    func testDuplicateBundleIdentifiersInRegistryDoNotCrash() async {
        // Dictionary(uniqueKeysWithValues:) would trap here — the first
        // registered checker for a colliding identifier should just win.
        let first = FakeCustomAppChecker(bundleIdentifier: "com.example.app", result: UpdateCheckResult(status: .upToDate))
        let second = FakeCustomAppChecker(bundleIdentifier: "com.example.app", result: UpdateCheckResult(status: .checkFailed(reason: "should not be used")))
        let checker = CustomAppSourceChecker(checkers: [first, second])
        let app = discoveredApp(bundleIdentifier: "com.example.app", bundlePath: "/Applications/Example.app")

        let results = await checker.checkUpdates(for: [app])

        XCTAssertEqual(results["/Applications/Example.app"]?.status, .upToDate)
    }

    func testEmptyRegistryProducesNoResultsWithoutCallingAnyChecker() async {
        let checker = CustomAppSourceChecker(checkers: [])
        let app = discoveredApp(bundleIdentifier: "com.example.app", bundlePath: "/Applications/Example.app")

        let results = await checker.checkUpdates(for: [app])

        XCTAssertTrue(results.isEmpty)
    }

    private func discoveredApp(bundleIdentifier: String?, bundlePath: String) -> DiscoveredApp {
        DiscoveredApp(
            name: "Example",
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            installedVersion: "1.0.0",
            hasMacAppStoreReceipt: false,
            sparkleFeedURL: nil
        )
    }
}

private struct FakeCustomAppChecker: CustomAppChecker {
    let bundleIdentifier: String
    let result: UpdateCheckResult

    func checkUpdate(installedVersion: String, bundlePath: String) async -> UpdateCheckResult {
        result
    }
}
