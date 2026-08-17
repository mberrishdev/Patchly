import AppKit
import CryptoKit
import Foundation

enum SparkleDirectInstallError: Error, LocalizedError, Equatable {
    case invalidSignatureEncoding
    case invalidPublicKeyEncoding
    case signatureVerificationFailed
    case downloadFailed(String)
    case unsupportedArchiveType(String)
    case extractionFailed(String)
    case noAppFoundInArchive
    case couldNotQuitRunningApp
    case replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSignatureEncoding: "the appcast's signature isn't valid base64"
        case .invalidPublicKeyEncoding: "the app's SUPublicEDKey isn't a valid Ed25519 key"
        case .signatureVerificationFailed: "signature verification failed — the download doesn't match what the developer signed"
        case .downloadFailed(let reason): "download failed: \(reason)"
        case .unsupportedArchiveType(let ext): "unsupported update archive type: .\(ext)"
        case .extractionFailed(let reason): "couldn't extract the update: \(reason)"
        case .noAppFoundInArchive: "the downloaded update didn't contain an .app"
        case .couldNotQuitRunningApp: "couldn't quit the running app to replace it"
        case .replaceFailed(let reason): "couldn't install the update: \(reason)"
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

    init(session: URLSession = SparkleDirectInstaller.makeSession(), processRunner: ProcessRunning = ProcessRunner()) {
        self.session = session
        self.processRunner = processRunner
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

            let extractedAppURL = try await extract(downloadedFileURL: downloadedFileURL, workDir: workDir)

            try await quitIfRunning(bundlePath: targetBundlePath)
            try replace(targetBundlePath: targetBundlePath, withAppAt: extractedAppURL)
            await relaunch(bundlePath: targetBundlePath)

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

    private func extract(downloadedFileURL: URL, workDir: URL) async throws -> URL {
        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        switch downloadedFileURL.pathExtension.lowercased() {
        case "zip":
            // ditto (not unzip) preserves resource forks / extended
            // attributes / the code signature intact.
            let result = try await processRunner.run(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", downloadedFileURL.path, extractDir.path],
                timeout: 300
            )
            guard result.succeeded else {
                throw SparkleDirectInstallError.extractionFailed(result.standardError)
            }
            return try Self.findApp(in: extractDir)

        case "dmg":
            let mountDir = workDir.appendingPathComponent("mount", isDirectory: true)
            try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
            let attach = try await processRunner.run(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["attach", downloadedFileURL.path, "-nobrowse", "-readonly", "-mountpoint", mountDir.path],
                timeout: 120
            )
            guard attach.succeeded else {
                throw SparkleDirectInstallError.extractionFailed(attach.standardError)
            }
            do {
                let appInDMG = try Self.findApp(in: mountDir)
                let destAppURL = extractDir.appendingPathComponent(appInDMG.lastPathComponent)
                let copy = try await processRunner.run(
                    executablePath: "/usr/bin/ditto",
                    arguments: [appInDMG.path, destAppURL.path],
                    timeout: 300
                )
                _ = try? await processRunner.run(executablePath: "/usr/bin/hdiutil", arguments: ["detach", mountDir.path, "-quiet"], timeout: 30)
                guard copy.succeeded else {
                    throw SparkleDirectInstallError.extractionFailed(copy.standardError)
                }
                return destAppURL
            } catch {
                _ = try? await processRunner.run(executablePath: "/usr/bin/hdiutil", arguments: ["detach", mountDir.path, "-quiet"], timeout: 30)
                throw error
            }

        case let ext:
            throw SparkleDirectInstallError.unsupportedArchiveType(ext)
        }
    }

    private static func findApp(in directory: URL) throws -> URL {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              let appURL = entries.first(where: { $0.pathExtension == "app" })
        else {
            throw SparkleDirectInstallError.noAppFoundInArchive
        }
        return appURL
    }

    /// Quits the app if it's currently running, so its bundle isn't being
    /// replaced out from under a live process. Tries a graceful terminate
    /// first, escalates to a force-terminate, and gives up rather than
    /// replacing files under a process that won't exit.
    @MainActor
    private func quitIfRunning(bundlePath: String) async throws {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == bundleURL }) else {
            return
        }

        running.terminate()
        if await waitForTermination(of: running, timeout: 10) { return }

        running.forceTerminate()
        if await waitForTermination(of: running, timeout: 5) { return }

        throw SparkleDirectInstallError.couldNotQuitRunningApp
    }

    @MainActor
    private func waitForTermination(of app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !app.isTerminated, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return app.isTerminated
    }

    private func replace(targetBundlePath: String, withAppAt newAppURL: URL) throws {
        let targetURL = URL(fileURLWithPath: targetBundlePath)
        do {
            _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: newAppURL)
        } catch {
            throw SparkleDirectInstallError.replaceFailed(error.localizedDescription)
        }
    }

    @MainActor
    private func relaunch(bundlePath: String) async {
        _ = try? await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: bundlePath),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
