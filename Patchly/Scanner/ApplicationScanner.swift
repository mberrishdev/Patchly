import CoreServices
import Foundation

/// Enumerates `/Applications`, `/Applications/Utilities`, and `~/Applications` for
/// `.app` bundles, reading each one's Info.plist. Also looks one level into any
/// non-`.app` subfolder of each root directory (e.g. `/Applications/Development`),
/// since users commonly organize `/Applications` into subfolders — but never
/// descends further than that, and never looks inside a matched `.app` bundle
/// itself (those are also directories, but their contents aren't more apps to
/// scan). Explicitly skips `/System/Applications` — OS-managed, not
/// user-updatable — and Patchly itself, which self-updates via Sparkle
/// outside the Refresh cycle. See CONTEXT.md.
actor ApplicationScanner {
    private let rootDirectories: [URL]
    private let excludedBundleIdentifier: String?
    private let lastUsedDateReader: @Sendable (URL) -> Date?

    init(
        rootDirectories: [URL] = ApplicationScanner.defaultRootDirectories(),
        excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        lastUsedDateReader: @escaping @Sendable (URL) -> Date? = ApplicationScanner.spotlightLastUsedDate
    ) {
        self.rootDirectories = rootDirectories
        self.excludedBundleIdentifier = excludedBundleIdentifier
        self.lastUsedDateReader = lastUsedDateReader
    }

    /// Spotlight's `kMDItemLastUsedDate` — the same "Last opened" date Finder
    /// shows. Often missing: macOS doesn't record every kind of launch, and
    /// replacing an app's bundle (including via an Update Action) clears it.
    /// See CONTEXT.md ("Last Used Date").
    static func spotlightLastUsedDate(for bundleURL: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, bundleURL as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
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
                    // Patchly is never one of its own Scanned Apps — it
                    // self-updates via Sparkle, separately from the Refresh
                    // cycle, so a row for it would offer an Update Action
                    // that duplicates "Check for Updates…" at best. Matched
                    // by bundle identifier, not path, so an installed copy
                    // is excluded even when the running build lives
                    // elsewhere (e.g. Xcode's DerivedData).
                    if let excludedBundleIdentifier, app.bundleIdentifier == excludedBundleIdentifier {
                        continue
                    }
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
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                results.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let nested = (try? fileManager.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                results.append(contentsOf: nested.filter { $0.pathExtension == "app" })
            }
        }
        return results
    }

    private func readApp(at bundleURL: URL) -> DiscoveredApp? {
        // Reads Info.plist directly rather than via `Bundle(url:)` —
        // `Bundle` caches a bundle's Info.plist per path for the life of
        // the process, so once Patchly (a long-running menu bar app) has
        // read an app once, a later scan after that app's bundle was
        // replaced (e.g. by `SparkleDirectInstaller`) would keep returning
        // the pre-replacement version forever, making an installed update
        // look like it never happened.
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlistURL) as? [String: Any] else { return nil }

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

        let publicEDKey = info["SUPublicEDKey"] as? String

        return DiscoveredApp(
            name: name,
            bundlePath: bundleURL.path,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            installedVersion: version,
            hasMacAppStoreReceipt: hasReceipt,
            sparkleFeedURL: feedURL,
            electronUpdateConfig: electronConfig,
            sparklePublicEDKey: publicEDKey,
            lastUsedDate: lastUsedDateReader(bundleURL)
        )
    }
}
