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

    func testCorruptCLIToolsDoesNotWipeApps() throws {
        // A decode failure in one array (e.g. an incompatible field added to
        // a model in a later version) must not wipe the other one - each
        // key should decode independently.
        let app = ScannedApp(
            id: "com.example.app",
            name: "Example",
            bundlePath: "/Applications/Example.app",
            bundleIdentifier: "com.example.app",
            installedVersion: "1.0.0",
            source: .homebrewCask,
            updateStatus: .upToDate
        )
        let appData = try JSONEncoder().encode(app)
        let appJSON = String(data: appData, encoding: .utf8)!
        let json = """
        {"apps": [\(appJSON)], "cliTools": [{"nonsense": true}]}
        """
        try Data(json.utf8).write(to: fileURL)

        let store = CacheStore(fileURL: fileURL)
        let loaded = store.load()

        XCTAssertEqual(loaded.apps, [app])
        XCTAssertTrue(loaded.cliTools.isEmpty)
    }

    func testCorruptAppsDoesNotWipeCLITools() throws {
        let tool = CLITool(name: "ripgrep", version: "14.1.1", source: .homebrewFormula, updateStatus: .upToDate)
        let toolData = try JSONEncoder().encode(tool)
        let toolJSON = String(data: toolData, encoding: .utf8)!
        let json = """
        {"apps": [{"nonsense": true}], "cliTools": [\(toolJSON)]}
        """
        try Data(json.utf8).write(to: fileURL)

        let store = CacheStore(fileURL: fileURL)
        let loaded = store.load()

        XCTAssertTrue(loaded.apps.isEmpty)
        XCTAssertEqual(loaded.cliTools, [tool])
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
