import XCTest
@testable import Patchly

final class CacheStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchlyCacheStoreTests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testRoundTripsAppsAndCLITools() {
        let store = CacheStore(fileURL: fileURL)
        let app = ScannedApp(
            id: "com.example.app",
            name: "Example",
            bundlePath: "/Applications/Example.app",
            bundleIdentifier: "com.example.app",
            installedVersion: "1.0.0",
            source: .homebrewCask,
            updateStatus: .upToDate
        )
        let tool = CLITool(
            name: "ripgrep",
            version: "14.1.1",
            source: .homebrewFormula,
            updateStatus: .upToDate
        )

        store.save(apps: [app], cliTools: [tool])
        let loaded = store.load()

        XCTAssertEqual(loaded.apps, [app])
        XCTAssertEqual(loaded.cliTools, [tool])
    }

    func testMissingFileProducesEmptyResult() {
        let store = CacheStore(fileURL: fileURL)
        let loaded = store.load()
        XCTAssertTrue(loaded.apps.isEmpty)
        XCTAssertTrue(loaded.cliTools.isEmpty)
    }

    func testLegacyAppsOnlyFormatDecodesToEmptyRatherThanCrashing() throws {
        let legacyApp = ScannedApp(
            id: "com.example.app",
            name: "Example",
            bundlePath: "/Applications/Example.app",
            bundleIdentifier: "com.example.app",
            installedVersion: "1.0.0",
            source: .homebrewCask,
            updateStatus: .upToDate
        )
        let data = try JSONEncoder().encode([legacyApp])
        try data.write(to: fileURL)

        let store = CacheStore(fileURL: fileURL)
        let loaded = store.load()

        XCTAssertTrue(loaded.apps.isEmpty)
        XCTAssertTrue(loaded.cliTools.isEmpty)
    }
}
