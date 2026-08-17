import CryptoKit
import Foundation

enum ElectronDirectInstallError: Error, LocalizedError, Equatable {
    case downloadFailed(String)
    case checksumMismatch
    case codeSignatureInvalid(String)
    case teamIdentifierMismatch
    case bundleIdentifierMismatch

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason): "download failed: \(reason)"
        case .checksumMismatch: "the downloaded update's checksum doesn't match what the developer published — discarding it"
        case .codeSignatureInvalid(let reason): "the downloaded update's code signature is invalid: \(reason)"
        case .teamIdentifierMismatch: "the downloaded update is signed by a different developer than the installed app — discarding it"
        case .bundleIdentifierMismatch: "the downloaded update's bundle identifier doesn't match the installed app — discarding it"
        }
    }
}

/// Downloads an Electron app's update artifact and, only if it passes three
/// independent checks, replaces the app. Electron has no signed-appcast
/// equivalent to Sparkle's EdDSA scheme (see `SparkleDirectInstaller`), so
/// verification here can't lean on a single developer-controlled secret the
/// way Sparkle's does. Instead it chains checks that all have to hold:
///
/// 1. The downloaded bytes match the sha512 electron-builder published in
///    the same `latest-mac[-arm64].yml` manifest the archive's URL came
///    from (protects against a corrupted or tampered-in-transit download).
/// 2. The extracted app's code signature is internally valid (`codesign
///    --verify --deep --strict` — the same check Gatekeeper itself runs).
/// 3. The extracted app's Team Identifier and bundle identifier match the
///    app already installed on disk.
///
/// (2) and (3) together are the load-bearing check: an attacker who
/// compromises only the download host or GitHub repo can publish a
/// malicious archive with a matching sha512 (they control both), but they
/// can't make it pass as signed by the same Apple Developer Team unless
/// they also possess the vendor's actual signing certificate — a secret
/// hosting compromise alone doesn't give them. This is why Patchly doesn't
/// reimplement electron-updater's own (weaker, documented-vulnerable)
/// verification: this scheme is a different, independent one. A failure at
/// any step discards the download; Patchly never installs anything it
/// couldn't verify. See CONTEXT.md.
struct ElectronDirectInstaller: Sendable {
    private let session: URLSession
    private let processRunner: ProcessRunning
    private let replacer: RunningAppReplacer

    init(
        session: URLSession = ElectronDirectInstaller.makeSession(),
        processRunner: ProcessRunning = ProcessRunner(),
        replacer: RunningAppReplacer = RunningAppReplacer()
    ) {
        self.session = session
        self.processRunner = processRunner
        self.replacer = replacer
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }

    func install(
        archiveURL: URL,
        expectedSHA512Base64: String,
        targetBundlePath: String,
        expectedBundleIdentifier: String?
    ) async -> UpdateInstallResult {
        do {
            let fileData = try await download(archiveURL)
            try Self.verifyChecksum(fileData: fileData, expectedSHA512Base64: expectedSHA512Base64)

            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PatchlyElectronUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }

            let downloadedFileURL = workDir.appendingPathComponent(archiveURL.lastPathComponent)
            try fileData.write(to: downloadedFileURL)

            let extractedAppURL = try await UpdateArchiveExtractor.extract(downloadedFileURL: downloadedFileURL, workDir: workDir, processRunner: processRunner)

            try await verifyAuthenticity(
                extractedAppURL: extractedAppURL,
                targetBundlePath: targetBundlePath,
                expectedBundleIdentifier: expectedBundleIdentifier
            )

            try await replacer.quitIfRunning(bundlePath: targetBundlePath)
            try replacer.replace(targetBundlePath: targetBundlePath, withAppAt: extractedAppURL)
            await replacer.relaunch(bundlePath: targetBundlePath)

            return UpdateInstallResult(bundlePath: targetBundlePath, succeeded: true, failureReason: nil)
        } catch {
            return UpdateInstallResult(bundlePath: targetBundlePath, succeeded: false, failureReason: error.localizedDescription)
        }
    }

    /// Matches electron-builder's own `sha512` field: SHA-512 digest of the
    /// raw archive bytes, base64-encoded — the same value electron-updater
    /// itself checks the download against.
    static func verifyChecksum(fileData: Data, expectedSHA512Base64: String) throws {
        let digest = SHA512.hash(data: fileData)
        let actualBase64 = Data(digest).base64EncodedString()
        guard actualBase64 == expectedSHA512Base64.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ElectronDirectInstallError.checksumMismatch
        }
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ElectronDirectInstallError.downloadFailed("unexpected server response")
        }
        return data
    }

    private func verifyAuthenticity(extractedAppURL: URL, targetBundlePath: String, expectedBundleIdentifier: String?) async throws {
        let verify = try await processRunner.run(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", extractedAppURL.path],
            timeout: 30
        )
        guard verify.succeeded else {
            throw ElectronDirectInstallError.codeSignatureInvalid(verify.standardError)
        }

        let newTeamID = try await teamIdentifier(ofBundleAt: extractedAppURL.path)
        let installedTeamID = try await teamIdentifier(ofBundleAt: targetBundlePath)
        guard newTeamID == installedTeamID else {
            throw ElectronDirectInstallError.teamIdentifierMismatch
        }

        if let expectedBundleIdentifier {
            guard Bundle(url: extractedAppURL)?.bundleIdentifier == expectedBundleIdentifier else {
                throw ElectronDirectInstallError.bundleIdentifierMismatch
            }
        }
    }

    /// Requires an actual Team Identifier on both sides — an unsigned or
    /// ad-hoc-signed bundle (`TeamIdentifier=not set`, or no such line at
    /// all) always fails here rather than comparing equal to another
    /// equally-unsigned bundle, which would otherwise let two untrusted
    /// bundles trivially "match."
    private func teamIdentifier(ofBundleAt path: String) async throws -> String {
        let result = try await processRunner.run(executablePath: "/usr/bin/codesign", arguments: ["-dvv", path], timeout: 15)
        // codesign writes -dvv's diagnostic output to stderr, not stdout.
        for line in result.standardError.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("TeamIdentifier=") else { continue }
            let value = String(line.dropFirst("TeamIdentifier=".count))
            guard value != "not set" else { throw ElectronDirectInstallError.teamIdentifierMismatch }
            return value
        }
        throw ElectronDirectInstallError.teamIdentifierMismatch
    }
}
