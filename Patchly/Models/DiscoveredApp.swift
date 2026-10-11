import Foundation

/// A scan-only intermediate: identity and version fields read from an app bundle's
/// Info.plist, before any Update Source has been attributed. See CONTEXT.md.
struct DiscoveredApp: Hashable, Sendable {
    let name: String
    let bundlePath: String
    let bundleIdentifier: String?
    let installedVersion: String
    let hasMacAppStoreReceipt: Bool
    let sparkleFeedURL: URL?
    let electronUpdateConfig: ElectronUpdateConfig?
    /// The app's own EdDSA public key (`SUPublicEDKey`, base64), if it declares
    /// one — needed to verify a Sparkle update before Patchly installs it
    /// directly. See CONTEXT.md.
    let sparklePublicEDKey: String?
    /// Spotlight's record of when the app was last opened, if it has one.
    /// See CONTEXT.md ("Last Used Date").
    let lastUsedDate: Date?
    /// Spotlight's count of how many times the app was opened, if it has one.
    /// See CONTEXT.md ("Use Count").
    let useCount: Int?
    /// The bundle's size on disk, from Spotlight when it has one; filled in
    /// by measuring the bundle otherwise. See CONTEXT.md ("App Size").
    let sizeInBytes: Int64?

    init(
        name: String,
        bundlePath: String,
        bundleIdentifier: String?,
        installedVersion: String,
        hasMacAppStoreReceipt: Bool,
        sparkleFeedURL: URL?,
        electronUpdateConfig: ElectronUpdateConfig? = nil,
        sparklePublicEDKey: String? = nil,
        lastUsedDate: Date? = nil,
        useCount: Int? = nil,
        sizeInBytes: Int64? = nil
    ) {
        self.name = name
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.installedVersion = installedVersion
        self.hasMacAppStoreReceipt = hasMacAppStoreReceipt
        self.sparkleFeedURL = sparkleFeedURL
        self.electronUpdateConfig = electronUpdateConfig
        self.sparklePublicEDKey = sparklePublicEDKey
        self.lastUsedDate = lastUsedDate
        self.useCount = useCount
        self.sizeInBytes = sizeInBytes
    }

    var bundleFilename: String {
        (bundlePath as NSString).lastPathComponent
    }
}
