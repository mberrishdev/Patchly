import Foundation

enum UpdateArchiveExtractionError: Error, LocalizedError, Equatable {
    case unsupportedArchiveType(String)
    case extractionFailed(String)
    case noAppFoundInArchive

    var errorDescription: String? {
        switch self {
        case .unsupportedArchiveType(let ext): "unsupported update archive type: .\(ext)"
        case .extractionFailed(let reason): "couldn't extract the update: \(reason)"
        case .noAppFoundInArchive: "the downloaded update didn't contain an .app"
        }
    }
}

/// Extracts a downloaded `.zip` or `.dmg` update archive and locates the
/// `.app` bundle inside it. Shared by every direct-install path
/// (`SparkleDirectInstaller`, `ElectronDirectInstaller`) — extraction itself
/// has nothing source-specific about it, only what happens before
/// (download + verify) and after (replace) does.
enum UpdateArchiveExtractor {
    static func extract(downloadedFileURL: URL, workDir: URL, processRunner: ProcessRunning) async throws -> URL {
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
                throw UpdateArchiveExtractionError.extractionFailed(result.standardError)
            }
            return try findApp(in: extractDir)

        case "dmg":
            let mountDir = workDir.appendingPathComponent("mount", isDirectory: true)
            try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
            let attach = try await processRunner.run(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["attach", downloadedFileURL.path, "-nobrowse", "-readonly", "-mountpoint", mountDir.path],
                timeout: 120
            )
            guard attach.succeeded else {
                throw UpdateArchiveExtractionError.extractionFailed(attach.standardError)
            }
            do {
                let appInDMG = try findApp(in: mountDir)
                let destAppURL = extractDir.appendingPathComponent(appInDMG.lastPathComponent)
                let copy = try await processRunner.run(
                    executablePath: "/usr/bin/ditto",
                    arguments: [appInDMG.path, destAppURL.path],
                    timeout: 300
                )
                _ = try? await processRunner.run(executablePath: "/usr/bin/hdiutil", arguments: ["detach", mountDir.path, "-quiet"], timeout: 30)
                guard copy.succeeded else {
                    throw UpdateArchiveExtractionError.extractionFailed(copy.standardError)
                }
                return destAppURL
            } catch {
                _ = try? await processRunner.run(executablePath: "/usr/bin/hdiutil", arguments: ["detach", mountDir.path, "-quiet"], timeout: 30)
                throw error
            }

        case let ext:
            throw UpdateArchiveExtractionError.unsupportedArchiveType(ext)
        }
    }

    private static func findApp(in directory: URL) throws -> URL {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              let appURL = entries.first(where: { $0.pathExtension == "app" })
        else {
            throw UpdateArchiveExtractionError.noAppFoundInArchive
        }
        return appURL
    }
}
