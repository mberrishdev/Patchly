import XCTest
@testable import Patchly

final class ApplicationScannerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchlyScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testDiscoversAppWithVersionAndBundleIdentifier() async throws {
        try makeFakeApp(
            named: "Example.app",
            infoPlist: [
                "CFBundleName": "Example",
                "CFBundleIdentifier": "com.example.app",
                "CFBundleShortVersionString": "1.2.3"
            ]
        )

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.name, "Example")
        XCTAssertEqual(apps.first?.installedVersion, "1.2.3")
        XCTAssertEqual(apps.first?.bundleIdentifier, "com.example.app")
        XCTAssertFalse(apps.first?.hasMacAppStoreReceipt ?? true)
        XCTAssertNil(apps.first?.sparkleFeedURL)
    }

    func testDetectsMacAppStoreReceipt() async throws {
        let appURL = try makeFakeApp(
            named: "StoreApp.app",
            infoPlist: [
                "CFBundleName": "StoreApp",
                "CFBundleShortVersionString": "1.0"
            ]
        )
        let receiptDirectory = appURL.appendingPathComponent("Contents/_MASReceipt", isDirectory: true)
        try FileManager.default.createDirectory(at: receiptDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: receiptDirectory.appendingPathComponent("receipt").path, contents: Data())

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertEqual(apps.first?.hasMacAppStoreReceipt, true)
    }

    func testDetectsSparkleFeedURL() async throws {
        try makeFakeApp(
            named: "SparkleApp.app",
            infoPlist: [
                "CFBundleName": "SparkleApp",
                "CFBundleShortVersionString": "1.0",
                "SUFeedURL": "https://example.com/appcast.xml"
            ]
        )

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertEqual(apps.first?.sparkleFeedURL, URL(string: "https://example.com/appcast.xml"))
    }

    func testIgnoresNonAppEntries() async throws {
        let stray = tempDirectory.appendingPathComponent("not-an-app.txt")
        FileManager.default.createFile(atPath: stray.path, contents: Data())

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertTrue(apps.isEmpty)
    }

    func testDiscoversAppNestedOneLevelInASubfolder() async throws {
        // Real bug report: Docker, Rider, and VS Code all live in a
        // self-organized "/Applications/Development" subfolder and were
        // never found because the scanner only looked at the top level.
        let subfolder = tempDirectory.appendingPathComponent("Development", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try makeFakeApp(
            named: "Nested.app",
            in: subfolder,
            infoPlist: ["CFBundleName": "Nested", "CFBundleShortVersionString": "1.0"]
        )

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertEqual(apps.map(\.name), ["Nested"])
    }

    func testDoesNotRecurseMoreThanOneLevelDeep() async throws {
        let tooDeep = tempDirectory
            .appendingPathComponent("Development", isDirectory: true)
            .appendingPathComponent("SubTool", isDirectory: true)
        try FileManager.default.createDirectory(at: tooDeep, withIntermediateDirectories: true)
        try makeFakeApp(
            named: "TooDeep.app",
            in: tooDeep,
            infoPlist: ["CFBundleName": "TooDeep", "CFBundleShortVersionString": "1.0"]
        )

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertTrue(apps.isEmpty)
    }

    func testDoesNotTreatAnAppBundlesOwnContentsAsASubfolderToScan() async throws {
        // A nested helper .app inside another app's Contents/ (e.g. Electron's
        // "Foo Helper.app") must never surface as its own Scanned App.
        let appURL = try makeFakeApp(
            named: "Outer.app",
            infoPlist: ["CFBundleName": "Outer", "CFBundleShortVersionString": "1.0"]
        )
        let frameworksURL = appURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworksURL, withIntermediateDirectories: true)
        try makeFakeApp(
            named: "Helper.app",
            in: frameworksURL,
            infoPlist: ["CFBundleName": "Helper", "CFBundleShortVersionString": "1.0"]
        )

        let scanner = ApplicationScanner(rootDirectories: [tempDirectory])
        let apps = await scanner.scanInstalledApps()

        XCTAssertEqual(apps.map(\.name), ["Outer"])
    }

    @discardableResult
    private func makeFakeApp(named name: String, in directory: URL? = nil, infoPlist: [String: Any]) throws -> URL {
        let appURL = (directory ?? tempDirectory).appendingPathComponent(name, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try data.write(to: plistURL)
        return appURL
    }
}
