import AppKit
import CryptoKit
import Foundation

enum SparkleDirectInstallError: Error, LocalizedError, Equatable {
    case invalidSignatureEncoding
    case invalidPublicKeyEncoding
    case signatureVerificationFailed
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSignatureEncoding: "the appcast's signature isn't valid base64"
        case .invalidPublicKeyEncoding: "the app's SUPublicEDKey isn't a valid Ed25519 key"
        case .signatureVerificationFailed: "signature verification failed — the download doesn't match what the developer signed"
        case .downloadFailed(let reason): "download failed: \(reason)"
        }
    }
}

/// Downloads a Sparkle update, verifies its EdDSA (Ed25519) signature against
/// the target app's own declared public key, and only then replaces the app.
/// The signature scheme matches Sparkle's own `SUSignatureVerifier` exactly:
/// a raw Ed25519 signature over the unmodified downloaded file's bytes — see
/// https://github.com/sparkle-project/Sparkle/blob/master/Sparkle/SUSignatureVerifier.m.
/// An update that fails verification is discarded; Patchly never installs
/// anything it couldn't verify. See CONTEXT.md.
struct SparkleDirectInstaller: Sendable {
    private let session: URLSession
    private let processRunner: ProcessRunning
    private let replacer: RunningAppReplacer

    init(
        session: URLSession = SparkleDirectInstaller.makeSession(),
        processRunner: ProcessRunning = ProcessRunner(),
        replacer: RunningAppReplacer = RunningAppReplacer()
    ) {
        self.session = session
        self.processRunner = processRunner
        self.replacer = replacer
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // Update archives can be large; give this real headroom beyond the
        // short timeouts used for version checks.
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }

    func install(
        enclosureURL: URL,
        edSignatureBase64: String,
        publicKeyBase64: String,
        targetBundlePath: String
    ) async -> UpdateInstallResult {
        do {
            let fileData = try await download(enclosureURL)
            try Self.verifySignature(fileData: fileData, signatureBase64: edSignatureBase64, publicKeyBase64: publicKeyBase64)

            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PatchlySparkleUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }

            let downloadedFileURL = workDir.appendingPathComponent(enclosureURL.lastPathComponent)
            try fileData.write(to: downloadedFileURL)

            let extractedAppURL = try await UpdateArchiveExtractor.extract(downloadedFileURL: downloadedFileURL, workDir: workDir, processRunner: processRunner)

            try await replacer.quitIfRunning(bundlePath: targetBundlePath)
            try replacer.replace(targetBundlePath: targetBundlePath, withAppAt: extractedAppURL)
            await replacer.relaunch(bundlePath: targetBundlePath)

            return UpdateInstallResult(bundlePath: targetBundlePath, succeeded: true, failureReason: nil)
        } catch {
            return UpdateInstallResult(bundlePath: targetBundlePath, succeeded: false, failureReason: error.localizedDescription)
        }
    }

    /// The one function correctness actually hinges on. Matches Sparkle's own
    /// `ed25519_verify(signature, fileBytes, fileLength, publicKey)` exactly:
    /// both signature (64 bytes) and public key (32 bytes) are plain base64,
    /// verified with CryptoKit's `Curve25519.Signing` — Apple's Ed25519
    /// implementation — over the raw, unmodified downloaded bytes.
    static func verifySignature(fileData: Data, signatureBase64: String, publicKeyBase64: String) throws {
        guard let signatureData = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              signatureData.count == 64
        else {
            throw SparkleDirectInstallError.invalidSignatureEncoding
        }
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              publicKeyData.count == 32
        else {
            throw SparkleDirectInstallError.invalidPublicKeyEncoding
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw SparkleDirectInstallError.invalidPublicKeyEncoding
        }

        guard publicKey.isValidSignature(signatureData, for: fileData) else {
            throw SparkleDirectInstallError.signatureVerificationFailed
        }
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SparkleDirectInstallError.downloadFailed("unexpected server response")
        }
        return data
    }

}
