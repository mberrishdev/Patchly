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

    init(
        name: String,
        bundlePath: String,
        bundleIdentifier: String?,
        installedVersion: String,
        hasMacAppStoreReceipt: Bool,
        sparkleFeedURL: URL?,
        electronUpdateConfig: ElectronUpdateConfig? = nil
    ) {
        self.name = name
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.installedVersion = installedVersion
        self.hasMacAppStoreReceipt = hasMacAppStoreReceipt
        self.sparkleFeedURL = sparkleFeedURL
        self.electronUpdateConfig = electronUpdateConfig
    }

    var bundleFilename: String {
        (bundlePath as NSString).lastPathComponent
    }
}
