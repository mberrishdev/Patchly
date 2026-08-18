import CryptoKit
import XCTest
@testable import Patchly

/// Mirrors `SparkleDirectInstallerTests`: the security-critical unit here is
/// `verifyChecksum`, exercised with the real CryptoKit SHA-512 primitive
/// so this tests the actual verification path, not a mock of it. The
/// codesign/Team-Identifier authenticity checks and the full `install()`
/// flow need real signed bundles and network access to exercise end to end,
/// so they're covered by manual verification against real installed apps
/// instead (see CONTEXT.md's Relationships section for what each check
/// guards against).
final class ElectronDirectInstallerTests: XCTestCase {
    func testMatchingChecksumPasses() {
        let data = Data("update archive contents".utf8)
        let expected = Data(SHA512.hash(data: data)).base64EncodedString()

        XCTAssertNoThrow(try ElectronDirectInstaller.verifyChecksum(fileData: data, expectedSHA512Base64: expected))
    }

    func testTamperedDataFailsChecksum() {
        let originalData = Data("update archive contents".utf8)
        let expected = Data(SHA512.hash(data: originalData)).base64EncodedString()
        let tamperedData = Data("update ARCHIVE contents".utf8)

        XCTAssertThrowsError(try ElectronDirectInstaller.verifyChecksum(fileData: tamperedData, expectedSHA512Base64: expected)) { error in
            XCTAssertEqual(error as? ElectronDirectInstallError, .checksumMismatch)
        }
    }

    func testWrongExpectedChecksumFails() {
        let data = Data("update archive contents".utf8)

        XCTAssertThrowsError(try ElectronDirectInstaller.verifyChecksum(fileData: data, expectedSHA512Base64: "not-the-real-hash==")) { error in
            XCTAssertEqual(error as? ElectronDirectInstallError, .checksumMismatch)
        }
    }

    func testChecksumComparisonToleratesSurroundingWhitespace() {
        let data = Data("update archive contents".utf8)
        let expected = Data(SHA512.hash(data: data)).base64EncodedString()

        XCTAssertNoThrow(try ElectronDirectInstaller.verifyChecksum(fileData: data, expectedSHA512Base64: " \(expected)\n"))
    }

    func testMatchingBundleIdentifiersPass() {
        XCTAssertTrue(ElectronDirectInstaller.bundleIdentifiersMatch(actual: "com.example.app", expected: "com.example.app"))
    }

    func testMismatchedBundleIdentifiersFail() {
        XCTAssertFalse(ElectronDirectInstaller.bundleIdentifiersMatch(actual: "com.example.app", expected: "com.other.app"))
    }

    func testNoExpectedBundleIdentifierFailsRatherThanSkippingTheCheck() {
        // The installed app's own CFBundleIdentifier can be nil/malformed —
        // that must fail verification, not silently skip it, since
        // CONTEXT.md requires this check unconditionally before replacing a
        // live app's bundle.
        XCTAssertFalse(ElectronDirectInstaller.bundleIdentifiersMatch(actual: "com.example.app", expected: nil))
    }
}
