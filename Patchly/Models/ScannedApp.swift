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
