import XCTest
@testable import Patchly

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "PatchlyAppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testShowsCLIToolsDefaultsToFalse() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.showsCLITools)
    }

    func testShowsCLIToolsPersistsAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.showsCLITools = true

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.showsCLITools)
    }

    func testShowsCLIToolsRoundTripsFalseAfterBeingSetTrue() {
        let settings = AppSettings(defaults: defaults)
        settings.showsCLITools = true
        settings.showsCLITools = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.showsCLITools)
    }
}
