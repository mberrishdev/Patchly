import Foundation

/// A Scanned App merged with its Update Source and Update Status. See CONTEXT.md.
struct ScannedApp: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let bundlePath: String
    let bundleIdentifier: String?
    let installedVersion: String
    var source: AppSource
    var updateStatus: UpdateStatus
    var lastCheckedAt: Date?
    /// How to actually install this app's update, if Patchly knows how.
    /// See CONTEXT.md's Relationships section for what each case does.
    var updateAction: UpdateAction? = nil
}

enum UpdateAction: Codable, Hashable, Sendable {
    case runBrewUpgrade(caskToken: String)
    case runMasUpgrade(appID: String)
    /// Patchly downloads the appcast enclosure, verifies its EdDSA (Ed25519)
    /// signature against the app's own declared public key, and — only if
    /// that succeeds — replaces the app itself. Falls back to `.launchApp`
    /// when the app or its appcast doesn't publish everything needed to
    /// verify. See CONTEXT.md.
    case installSparkleUpdate(enclosureURL: URL, edSignatureBase64: String, publicKeyBase64: String)
    /// Patchly downloads the update archive electron-builder's
    /// `latest-mac[-arm64].yml` manifest points at, verifies it (sha512
    /// checksum, code signature, and a Team Identifier + bundle identifier
    /// match against the already-installed app), and — only if all of that
    /// succeeds — replaces the app itself. Falls back to `.launchApp` when
    /// that manifest isn't published (an older electron-builder version, or
    /// a hand-rolled feed) and there's nothing to verify a download against.
    /// See CONTEXT.md.
    case installElectronUpdate(archiveURL: URL, expectedSHA512Base64: String)
    /// Electron's fallback when its manifest doesn't publish enough to
    /// verify a download, and the Sparkle Feed Source's fallback when it
    /// can't verify an appcast item — Patchly activates the app and its own
    /// linked updater takes over instead.
    case launchApp
    /// The CLI Tool Update Action: hand off to Homebrew, the same package
    /// manager that installed the tool. See CONTEXT.md ("CLI Tool Source").
    case runBrewUpgradeFormula(formulaName: String)
}

enum AppSource: String, Codable, Hashable, Sendable {
    case macAppStore
    case homebrewCask
    case electron
    case sparkleFeed
    case customApp
    case unknown
}

/// The origin Patchly attributes a CLI Tool to for update-checking purposes:
/// only Homebrew Formula, derived by resolving the tool's symlink chain back
/// to a `Cellar/<formula>/` path — never by guessing from its name. A wholly
/// separate concept from `AppSource`, since none of its cases apply to a
/// standalone binary. See CONTEXT.md ("CLI Tool Source").
enum CLIToolSource: String, Codable, Hashable, Sendable {
    case homebrewFormula
    case none
}

enum UpdateStatus: Codable, Hashable, Sendable {
    case checking
    case upToDate
    case updateAvailable(latestVersion: String)
    case unknownNoSource
    case unknownMasCliMissing
    case checkFailed(reason: String)

    var isUpdateAvailable: Bool {
        if case .updateAvailable = self { return true }
        return false
    }

    /// Sort priority within the dropdown list, per CONTEXT.md's Relationships section.
    var sortPriority: Int {
        switch self {
        case .updateAvailable: return 0
        case .unknownMasCliMissing: return 1
        case .checkFailed: return 2
        case .upToDate: return 3
        case .checking: return 4
        case .unknownNoSource: return 5
        }
    }
}
