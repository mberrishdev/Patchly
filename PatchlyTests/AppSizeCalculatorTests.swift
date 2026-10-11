import XCTest
@testable import Patchly

final class AppSizeCalculatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchlySizeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testMeasuresOnlyAppsSpotlightDidNotSize() async throws {
        let unsized = try makeBundle("Unsized.app", fileSize: 100_000)
        let sized = try makeBundle("Sized.app", fileSize: 100_000)

        let sizes = await AppSizeCalculator.measureUnsizedApps([
            discovered(unsized, size: nil),
            discovered(sized, size: 42),
        ])

        XCTAssertEqual(Set(sizes.keys), [unsized.path])
        XCTAssertGreaterThanOrEqual(sizes[unsized.path] ?? 0, 100_000)
    }

    func testIncludesNestedFiles() throws {
        let bundle = try makeBundle("Nested.app", fileSize: 50_000)
        let nested = bundle.appendingPathComponent("Contents/Frameworks/Lib.framework", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 50_000).write(to: nested.appendingPathComponent("Lib"))

        XCTAssertGreaterThanOrEqual(AppSizeCalculator.allocatedSize(of: bundle) ?? 0, 100_000)
    }

    private func makeBundle(_ name: String, fileSize: Int) throws -> URL {
        let bundle = tempDirectory.appendingPathComponent(name, isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data(count: fileSize).write(to: macOS.appendingPathComponent("Binary"))
        return bundle
    }

    private func discovered(_ bundle: URL, size: Int64?) -> DiscoveredApp {
        DiscoveredApp(
            name: bundle.deletingPathExtension().lastPathComponent,
            bundlePath: bundle.path,
            bundleIdentifier: nil,
            installedVersion: "1.0",
            hasMacAppStoreReceipt: false,
            sparkleFeedURL: nil,
            sizeInBytes: size
        )
    }
}
