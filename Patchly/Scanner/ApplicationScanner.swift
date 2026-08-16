import Foundation

/// Enumerates `/Applications`, `/Applications/Utilities`, and `~/Applications` for
/// top-level `.app` bundles, reading each one's Info.plist. Explicitly skips
/// `/System/Applications` — OS-managed, not user-updatable. See CONTEXT.md.
actor ApplicationScanner {
    private let rootDirectories: [URL]

    init(rootDirectories: [URL] = ApplicationScanner.defaultRootDirectories()) {
        self.rootDirectories = rootDirectories
    }

    static func defaultRootDirectories() -> [URL] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            homeApplications
        ]
    }

    func scanInstalledApps() async -> [DiscoveredApp] {
        var discovered: [DiscoveredApp] = []
        var seenBundlePaths: Set<String> = []

        for directory in rootDirectories {
            for bundleURL in appBundleURLs(in: directory) {
                guard seenBundlePaths.insert(bundleURL.path).inserted else { continue }
                if let app = readApp(at: bundleURL) {
                    discovered.append(app)
                }
            }
        }
        return discovered
    }

    private func appBundleURLs(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.filter { $0.pathExtension == "app" }
    }

    private func readApp(at bundleURL: URL) -> DiscoveredApp? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        guard let info = bundle.infoDictionary else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "0"

        let receiptPath = bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path
        let hasReceipt = FileManager.default.fileExists(atPath: receiptPath)

        let feedURL = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))

        let updateConfigPath = bundleURL.appendingPathComponent("Contents/Resources/app-update.yml").path
        let electronConfig = FileManager.default.contents(atPath: updateConfigPath)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(ElectronUpdateConfigParser.parse)

        return DiscoveredApp(
            name: name,
            bundlePath: bundleURL.path,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            installedVersion: version,
            hasMacAppStoreReceipt: hasReceipt,
            sparkleFeedURL: feedURL,
            electronUpdateConfig: electronConfig
        )
    }
}
