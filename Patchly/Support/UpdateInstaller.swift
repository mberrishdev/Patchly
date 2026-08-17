import AppKit
import Foundation

struct UpdateInstallResult: Sendable {
    let bundlePath: String
    let succeeded: Bool
    let failureReason: String?
}

/// Runs a Scanned App's `UpdateAction`. Homebrew Cask and Mac App Store apps
/// are upgraded directly via their CLI (`brew upgrade --cask`, `mas upgrade`)
/// — both already handle download/verify/install safely. Sparkle and
/// Electron apps have no such handoff, so Patchly only activates the app and
/// lets its own linked updater take over; it never downloads or replaces
/// another app's bundle itself. See CONTEXT.md.
struct UpdateInstaller: Sendable {
    private let processRunner: ProcessRunning
    private let brewPath: String?
    private let masPath: String?
    private let sparkleDirectInstaller: SparkleDirectInstaller

    init(
        processRunner: ProcessRunning = ProcessRunner(),
        brewPath: String? = ExecutableLocator.locateBrew(),
        masPath: String? = ExecutableLocator.locateMas(),
        sparkleDirectInstaller: SparkleDirectInstaller = SparkleDirectInstaller()
    ) {
        self.processRunner = processRunner
        self.brewPath = brewPath
        self.masPath = masPath
        self.sparkleDirectInstaller = sparkleDirectInstaller
    }

    func install(_ app: ScannedApp) async -> UpdateInstallResult {
        guard let action = app.updateAction else {
            return UpdateInstallResult(bundlePath: app.bundlePath, succeeded: false, failureReason: "No update action available")
        }

        switch action {
        case .runBrewUpgrade(let caskToken):
            return await runUpgrade(
                executablePath: brewPath,
                missingToolMessage: "Homebrew not found",
                arguments: ["upgrade", "--cask", caskToken],
                bundlePath: app.bundlePath
            )
        case .runMasUpgrade(let appID):
            return await runUpgrade(
                executablePath: masPath,
                missingToolMessage: "mas CLI not found",
                arguments: ["upgrade", appID],
                bundlePath: app.bundlePath
            )
        case .installSparkleUpdate(let enclosureURL, let edSignatureBase64, let publicKeyBase64):
            return await sparkleDirectInstaller.install(
                enclosureURL: enclosureURL,
                edSignatureBase64: edSignatureBase64,
                publicKeyBase64: publicKeyBase64,
                targetBundlePath: app.bundlePath
            )
        case .launchApp:
            return await launchApp(bundlePath: app.bundlePath, source: app.source, bundleIdentifier: app.bundleIdentifier)
        }
    }

    private func runUpgrade(
        executablePath: String?,
        missingToolMessage: String,
        arguments: [String],
        bundlePath: String
    ) async -> UpdateInstallResult {
        guard let executablePath else {
            return UpdateInstallResult(bundlePath: bundlePath, succeeded: false, failureReason: missingToolMessage)
        }
        do {
            // Installs can mean a real download, unlike the ~15-30s checks —
            // give this much more headroom before treating it as stuck.
            let result = try await processRunner.run(executablePath: executablePath, arguments: arguments, timeout: 300)
            if result.succeeded {
                return UpdateInstallResult(bundlePath: bundlePath, succeeded: true, failureReason: nil)
            }
            let reason = result.standardError.isEmpty
                ? "exited \(result.terminationStatus)"
                : result.standardError
            return UpdateInstallResult(bundlePath: bundlePath, succeeded: false, failureReason: reason)
        } catch {
            return UpdateInstallResult(bundlePath: bundlePath, succeeded: false, failureReason: error.localizedDescription)
        }
    }

    @MainActor
    private func launchApp(bundlePath: String, source: AppSource, bundleIdentifier: String?) async -> UpdateInstallResult {
        if source == .sparkleFeed, let bundleIdentifier {
            await clearSparkleLastCheckTime(bundleIdentifier: bundleIdentifier)
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: bundlePath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return UpdateInstallResult(bundlePath: bundlePath, succeeded: true, failureReason: nil)
        } catch {
            return UpdateInstallResult(bundlePath: bundlePath, succeeded: false, failureReason: error.localizedDescription)
        }
    }

    /// Sparkle only checks in the background once every 24 hours by default,
    /// so simply relaunching a recently-checked app can silently do nothing.
    /// Clearing this key is Sparkle's own documented way to force a check on
    /// the next launch (used for testing, but equally valid here). A missing
    /// key (never checked yet, or automatic checks disabled) is not an error
    /// — `defaults delete` exiting non-zero for that case is expected and
    /// ignored.
    private func clearSparkleLastCheckTime(bundleIdentifier: String) async {
        _ = try? await processRunner.run(
            executablePath: "/usr/bin/defaults",
            arguments: ["delete", bundleIdentifier, "SULastCheckTime"],
            timeout: 10
        )
    }
}
