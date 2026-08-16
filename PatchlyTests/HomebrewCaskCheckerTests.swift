import XCTest
@testable import Patchly

final class HomebrewCaskCheckerTests: XCTestCase {
    // Captured shape from a real `brew info --cask --json=v2 --installed` run.
    private let sampleJSON = """
    {
      "formulae": [],
      "casks": [
        {
          "token": "example-app",
          "version": "2.0.0",
          "installed": "1.5.0",
          "outdated": true,
          "artifacts": [
            { "app": ["Example App.app"] }
          ]
        },
        {
          "token": "up-to-date-app",
          "version": "3.1.0",
          "installed": "3.1.0",
          "outdated": false,
          "artifacts": [
            { "app": ["Up To Date.app"] }
          ]
        },
        {
          "token": "binary-only-cask",
          "version": "1.0.0",
          "installed": "1.0.0",
          "outdated": false,
          "artifacts": [
            { "binary": ["some-tool"] }
          ]
        }
      ]
    }
    """

    func testParsesCasksFromRealSchema() throws {
        let casks = try HomebrewCaskChecker.parseCasks(from: sampleJSON)
        XCTAssertEqual(casks.count, 3)
        XCTAssertEqual(casks.first?.token, "example-app")
    }

    func testMatchResultsFlagsOutdatedCaskAsUpdateAvailable() throws {
        let casks = try HomebrewCaskChecker.parseCasks(from: sampleJSON)
        let apps = [
            DiscoveredApp(
                name: "Example App",
                bundlePath: "/Applications/Example App.app",
                bundleIdentifier: "com.example.app",
                installedVersion: "1.5.0",
                hasMacAppStoreReceipt: false,
                sparkleFeedURL: nil
            )
        ]
        let results = HomebrewCaskChecker.matchResults(casks: casks, apps: apps)
        guard case .updateAvailable(let latest) = results["/Applications/Example App.app"]?.status else {
            return XCTFail("Expected updateAvailable status")
        }
        XCTAssertEqual(latest, "2.0.0")
    }

    func testMatchResultsFlagsCurrentCaskAsUpToDate() throws {
        let casks = try HomebrewCaskChecker.parseCasks(from: sampleJSON)
        let apps = [
            DiscoveredApp(
                name: "Up To Date",
                bundlePath: "/Applications/Up To Date.app",
                bundleIdentifier: nil,
                installedVersion: "3.1.0",
                hasMacAppStoreReceipt: false,
                sparkleFeedURL: nil
            )
        ]
        let results = HomebrewCaskChecker.matchResults(casks: casks, apps: apps)
        XCTAssertEqual(results["/Applications/Up To Date.app"]?.status, .upToDate)
    }

    func testArtifactsWithNoAppKeyAreIgnored() throws {
        let casks = try HomebrewCaskChecker.parseCasks(from: sampleJSON)
        let binaryOnly = casks.first { $0.token == "binary-only-cask" }
        XCTAssertEqual(binaryOnly?.artifactAppFilenames, [])
    }
}
