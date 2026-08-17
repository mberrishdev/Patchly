import AppKit
import Foundation

struct UpdateInstallResult: Sendable {
    let bundlePath: String
    let succeeded: Bool
    let failureReason: String?
}

struct CLIToolUpdateInstallResult: Sendable {
    let name: String
    let succeeded: Bool
    let failureReason: String?
}

/// Runs a Scanned App's `UpdateAction`. Homebrew Cask and Mac App Store apps
/// are upgraded directly via their CLI (`brew upgrade --cask`, `mas upgrade`)
/// — both already handle download/verify/install safely. Sparkle and
/// Electron apps get a direct install too when there's enough published to
/// verify one safely (see `SparkleDirectInstaller`, `ElectronDirectInstaller`);
/// otherwise Patchly falls back to just activating the app and letting its
/// own linked updater take over, never downloading or replacing a bundle it
/// couldn't verify. See CONTEXT.md.
struct UpdateInstaller: Sendable {
    private let processRunner: ProcessRunning
    private let brewPath: String?
    private let masPath: String?
    private let sparkleDirectInstaller: SparkleDirectInstaller
    private let electronDirectInstaller: ElectronDirectInstaller

    init(
        processRunner: ProcessRunning = ProcessRunner(),
        brewPath: String? = ExecutableLocator.locateBrew(),
        masPath: String? = ExecutableLocator.locateMas(),
        sparkleDirectInstaller: SparkleDirectInstaller = SparkleDirectInstaller(),
        electronDirectInstaller: ElectronDirectInstaller = ElectronDirectInstaller()
    ) {
        self.processRunner = processRunner
        self.brewPath = brewPath
        self.masPath = masPath
        self.sparkleDirectInstaller = sparkleDirectInstaller
        self.electronDirectInstaller = electronDirectInstaller
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
                identifier: app.bundlePath
            )
        case .runMasUpgrade(let appID):
            return await runUpgrade(
                executablePath: masPath,
                missingToolMessage: "mas CLI not found",
                arguments: ["upgrade", appID],
                identifier: app.bundlePath
            )
        case .installSparkleUpdate(let enclosureURL, let edSignatureBase64, let publicKeyBase64):
            return await sparkleDirectInstaller.install(
                enclosureURL: enclosureURL,
                edSignatureBase64: edSignatureBase64,
                publicKeyBase64: publicKeyBase64,
                targetBundlePath: app.bundlePath
            )
        case .installElectronUpdate(let archiveURL, let expectedSHA512Base64):
            return await electronDirectInstaller.install(
                archiveURL: archiveURL,
                expectedSHA512Base64: expectedSHA512Base64,
                targetBundlePath: app.bundlePath,
                expectedBundleIdentifier: app.bundleIdentifier
            )
        case .launchApp:
            return await launchApp(bundlePath: app.bundlePath, source: app.source, bundleIdentifier: app.bundleIdentifier)
        case .runBrewUpgradeFormula:
            // Only ever produced for a CLITool's updateAction, never a ScannedApp's.
            return UpdateInstallResult(bundlePath: app.bundlePath, succeeded: false, failureReason: "Not a Scanned App update action")
        }
    }

    /// Runs a CLI Tool's `UpdateAction` by handing off to Homebrew — the
    /// same "hand off to a CLI that already downloads, verifies, and
    /// installs" reasoning as the Homebrew Cask/Mac App Store Update
    /// Actions. See CONTEXT.md.
    func install(_ tool: CLITool) async -> CLIToolUpdateInstallResult {
        guard let action = tool.updateAction else {
            return CLIToolUpdateInstallResult(name: tool.name, succeeded: false, failureReason: "No update action available")
        }

        let result: UpdateInstallResult
        switch action {
        case .runBrewUpgradeFormula(let formulaName):
            result = await runUpgrade(
                executablePath: brewPath,
                missingToolMessage: "Homebrew not found",
                arguments: ["upgrade", formulaName],
                identifier: tool.name
            )
        case .runBrewUpgrade, .runMasUpgrade, .installSparkleUpdate, .installElectronUpdate, .launchApp:
            // Only ever produced for a ScannedApp's updateAction, never a CLITool's.
            return CLIToolUpdateInstallResult(name: tool.name, succeeded: false, failureReason: "Not a CLI Tool update action")
        }
        return CLIToolUpdateInstallResult(name: result.bundlePath, succeeded: result.succeeded, failureReason: result.failureReason)
    }

    private func runUpgrade(
        executablePath: String?,
        missingToolMessage: String,
        arguments: [String],
        identifier: String
    ) async -> UpdateInstallResult {
        guard let executablePath else {
            return UpdateInstallResult(bundlePath: identifier, succeeded: false, failureReason: missingToolMessage)
        }
        do {
            // Installs can mean a real download, unlike the ~15-30s checks —
            // give this much more headroom before treating it as stuck.
            let result = try await processRunner.run(executablePath: executablePath, arguments: arguments, timeout: 300)
            if result.succeeded {
                return UpdateInstallResult(bundlePath: identifier, succeeded: true, failureReason: nil)
            }
            let reason = result.standardError.isEmpty
                ? "exited \(result.terminationStatus)"
                : result.standardError
            return UpdateInstallResult(bundlePath: identifier, succeeded: false, failureReason: reason)
        } catch {
            return UpdateInstallResult(bundlePath: identifier, succeeded: false, failureReason: error.localizedDescription)
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
