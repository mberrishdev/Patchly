import XCTest
@testable import Patchly

final class ElectronUpdateManifestParserTests: XCTestCase {
    func testParsesVersionPathAndSHA512() {
        let yaml = """
        version: 3.8.0
        files:
          - url: RedisInsight-mac-arm64-3.8.0.zip
            sha512: abc123base64==
            size: 123456789
        path: RedisInsight-mac-arm64-3.8.0.zip
        sha512: abc123base64==
        releaseDate: '2026-01-01T00:00:00.000Z'
        """
        let manifest = ElectronUpdateManifestParser.parse(yaml)
        XCTAssertEqual(manifest, ElectronUpdateManifest(version: "3.8.0", path: "RedisInsight-mac-arm64-3.8.0.zip", sha512: "abc123base64=="))
    }

    func testMissingVersionReturnsNil() {
        let yaml = "path: Foo.zip\nsha512: abc=="
        XCTAssertNil(ElectronUpdateManifestParser.parse(yaml))
    }

    func testMissingPathOrSHA512LeavesThoseFieldsNil() {
        let manifest = ElectronUpdateManifestParser.parse("version: 1.0.0")
        XCTAssertEqual(manifest, ElectronUpdateManifest(version: "1.0.0", path: nil, sha512: nil))
    }

    func testPrefersArm64FileOverMismatchedTopLevelPair() {
        // Real bug, caught against Loom's actual latest-mac.yml: when the
        // arch-specific latest-mac-arm64.yml can't be fetched and Patchly
        // falls back to the combined manifest, its top-level path/sha512
        // point at a *different* build than the first files: entry. A naive
        // line scan (no indentation awareness) picked up the first sha512
        // it saw — from inside files:, paired with the top-level path —
        // producing a mismatched pair that would never verify.
        let yaml = """
        version: 0.368.1
        releaseDate: 2026-08-13T14:26:34.388Z
        files:
          - url: Loom-0.368.1-arm64-mac.zip
            sha512: 2Zv2HaFQJnWiWlTWw/WKQb1nu7ACxIt10/bSl7oV8cFliI8XQzhJ8xJ1z/4EKUQYTXVSHAtihyVUgMgRk8+R0A==
            size: 219004548
          - url: Loom-0.368.1-arm64.dmg
            sha512: E7oxEC6Vvoo5m2bJD8p87T9rPq7cJmNmSq6LNT5Evf8rGmOJDp9yrSHT5GSU5B2qKVF5gG4TFhZ8znXvBAUhow==
            size: 228355106
          - url: Loom-0.368.1-mac.zip
            sha512: On83zyAXhjb+JGQmzyeIf8WIg46DU1wby+PXGINucEFQlBq5QK0tXErnMexw0qIsbeEUWaU91WK5OXOfCgsP7A==
            size: 226241050
          - url: Loom-0.368.1.dmg
            sha512: yJtq7I83fPOKTJXEZy/ooZgXkHjT9up0iX0SwxNhOJZTX5paoeBpG7Q2q0ccxxdfKspI6ol67RfA4vO77cp0Xw==
            size: 235654351
        path: Loom-0.368.1-mac.zip
        sha512: On83zyAXhjb+JGQmzyeIf8WIg46DU1wby+PXGINucEFQlBq5QK0tXErnMexw0qIsbeEUWaU91WK5OXOfCgsP7A==
        """
        let manifest = ElectronUpdateManifestParser.parse(yaml)
        XCTAssertEqual(manifest, ElectronUpdateManifest(
            version: "0.368.1",
            path: "Loom-0.368.1-arm64-mac.zip",
            sha512: "2Zv2HaFQJnWiWlTWw/WKQb1nu7ACxIt10/bSl7oV8cFliI8XQzhJ8xJ1z/4EKUQYTXVSHAtihyVUgMgRk8+R0A=="
        ))
    }

    func testFallsBackToTopLevelPairWhenNoArm64FileEntryExists() {
        let yaml = """
        version: 1.2.3
        files:
          - url: App-mac.zip
            sha512: onlyBuildHash==
        path: App-mac.zip
        sha512: onlyBuildHash==
        """
        let manifest = ElectronUpdateManifestParser.parse(yaml)
        XCTAssertEqual(manifest, ElectronUpdateManifest(version: "1.2.3", path: "App-mac.zip", sha512: "onlyBuildHash=="))
    }
}
