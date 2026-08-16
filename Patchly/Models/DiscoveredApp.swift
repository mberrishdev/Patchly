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

    var bundleFilename: String {
        (bundlePath as NSString).lastPathComponent
    }
}
