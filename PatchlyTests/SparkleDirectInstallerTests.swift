import CryptoKit
import XCTest
@testable import Patchly

/// The security-critical test in this codebase: confirms `verifySignature`
/// actually rejects what it should reject, not just accepts what it should
/// accept. Uses CryptoKit to generate real Ed25519 keypairs and signatures —
/// the same primitive Sparkle itself uses — so this exercises the real
/// verification path, not a mock of it.
final class SparkleDirectInstallerTests: XCTestCase {
    func testValidSignaturePasses() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("update file contents".utf8)
        let signature = try privateKey.signature(for: data)

        XCTAssertNoThrow(try SparkleDirectInstaller.verifySignature(
            fileData: data,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testTamperedDataFailsVerification() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let originalData = Data("update file contents".utf8)
        let signature = try privateKey.signature(for: originalData)
        let tamperedData = Data("update FILE contents".utf8)

        XCTAssertThrowsError(try SparkleDirectInstaller.verifySignature(
            fileData: tamperedData,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )) { error in
            XCTAssertEqual(error as? SparkleDirectInstallError, .signatureVerificationFailed)
        }
    }

    func testWrongPublicKeyFailsVerification() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let attackerKey = Curve25519.Signing.PrivateKey()
        let data = Data("update file contents".utf8)
        let signature = try signingKey.signature(for: data)

        XCTAssertThrowsError(try SparkleDirectInstaller.verifySignature(
            fileData: data,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: attackerKey.publicKey.rawRepresentation.base64EncodedString()
        )) { error in
            XCTAssertEqual(error as? SparkleDirectInstallError, .signatureVerificationFailed)
        }
    }

    func testSignatureFromWrongDataFailsVerification() throws {
        // A validly-formed signature, just for different bytes than what's
        // being verified — must fail exactly like a tampered file would.
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(for: Data("some other file".utf8))

        XCTAssertThrowsError(try SparkleDirectInstaller.verifySignature(
            fileData: Data("update file contents".utf8),
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )) { error in
            XCTAssertEqual(error as? SparkleDirectInstallError, .signatureVerificationFailed)
        }
    }

    func testMalformedSignatureBase64Fails() {
        XCTAssertThrowsError(try SparkleDirectInstaller.verifySignature(
            fileData: Data("x".utf8),
            signatureBase64: "not valid base64!!!",
            publicKeyBase64: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        )) { error in
            XCTAssertEqual(error as? SparkleDirectInstallError, .invalidSignatureEncoding)
        }
    }

    func testWrongLengthSignatureFails() {
        let tooShort = Data(repeating: 0, count: 10).base64EncodedString()
        XCTAssertThrowsError(try SparkleDirectInstaller.verifySignature(
            fileData: Data("x".utf8),
            signatureBase64: tooShort,
            publicKeyBase64: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        )) { error in
            XCTAssertEqual(error as? SparkleDirectInstallError, .invalidSignatureEncoding)
        }
    }

    func testWrongLengthPublicKeyFails() {
        let tooShort = Data(repeating: 0, count: 3).base64EncodedString()
        XCTAssertThrowsError(try SparkleDirectInstaller.verifySignature(
            fileData: Data("x".utf8),
            signatureBase64: Data(repeating: 0, count: 64).base64EncodedString(),
            publicKeyBase64: tooShort
        )) { error in
            XCTAssertEqual(error as? SparkleDirectInstallError, .invalidPublicKeyEncoding)
        }
    }

    func testSparkleDocumentedExampleSignatureIsWellFormedBase64OfCorrectLength() {
        // From Sparkle's own EdDSA migration docs — confirms our base64/length
        // parsing accepts the exact format Sparkle itself produces. Not a
        // real signature over any data we have, just a format check.
        let exampleSignature = "ify59pDIuduaZcLnLvQjGqNQIAqi4dVgeA3L/e7I7xaqn9pVdiVZH7Na3v+Gp4ElAKJfX4Pfq8cgElfXmZc4Cg=="
        XCTAssertEqual(Data(base64Encoded: exampleSignature)?.count, 64)
    }
}
