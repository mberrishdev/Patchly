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
    /// Electron apps have no CLI handoff and no equivalent safe verification
    /// path — Patchly activates the app and its own linked updater takes
    /// over. Also the Sparkle Feed Source's fallback when it can't verify.
    case launchApp
}

enum AppSource: String, Codable, Hashable, Sendable {
    case macAppStore
    case homebrewCask
    case electron
    case sparkleFeed
    case unknown
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
