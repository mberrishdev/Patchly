import Foundation

/// Runs all Update Sources concurrently and applies the Mac App Store >
/// Homebrew Cask > Electron > Sparkle Feed priority merge from CONTEXT.md.
actor UpdateAggregator {
    private let scanner: ApplicationScanner
    private let macAppStoreChecker: any UpdateSource
    private let homebrewCaskChecker: any UpdateSource
    private let electronUpdateChecker: any UpdateSource
    private let sparkleFeedChecker: any UpdateSource

    init(
        scanner: ApplicationScanner = ApplicationScanner(),
        macAppStoreChecker: any UpdateSource = MacAppStoreChecker(),
        homebrewCaskChecker: any UpdateSource = HomebrewCaskChecker(),
        electronUpdateChecker: any UpdateSource = ElectronUpdateChecker(),
        sparkleFeedChecker: any UpdateSource = SparkleFeedChecker()
    ) {
        self.scanner = scanner
        self.macAppStoreChecker = macAppStoreChecker
        self.homebrewCaskChecker = homebrewCaskChecker
        self.electronUpdateChecker = electronUpdateChecker
        self.sparkleFeedChecker = sparkleFeedChecker
    }

    /// Re-runs only the Mac App Store Source check — used after installing
    /// `mas`, which per CONTEXT.md should only affect Mac App Store Source
    /// apps, not trigger a full Refresh.
    func recheckMacAppStore(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult] {
        await macAppStoreChecker.checkUpdates(for: apps)
    }

    func refresh() async -> [ScannedApp] {
        let discovered = await scanner.scanInstalledApps()
        return await Self.mergeResults(
            discovered: discovered,
            macAppStoreChecker: macAppStoreChecker,
            homebrewCaskChecker: homebrewCaskChecker,
            electronUpdateChecker: electronUpdateChecker,
            sparkleFeedChecker: sparkleFeedChecker
        )
    }

    static func mergeResults(
        discovered: [DiscoveredApp],
        macAppStoreChecker: any UpdateSource,
        homebrewCaskChecker: any UpdateSource,
        electronUpdateChecker: any UpdateSource,
        sparkleFeedChecker: any UpdateSource
    ) async -> [ScannedApp] {
        async let macResults = macAppStoreChecker.checkUpdates(for: discovered)
        async let homebrewResults = homebrewCaskChecker.checkUpdates(for: discovered)
        async let electronResults = electronUpdateChecker.checkUpdates(for: discovered)
        async let sparkleResults = sparkleFeedChecker.checkUpdates(for: discovered)

        let (mas, homebrew, electron, sparkle) = await (macResults, homebrewResults, electronResults, sparkleResults)
        let now = Date()

        return discovered.map { app in
            let (source, status) = attribute(app: app, mas: mas, homebrew: homebrew, electron: electron, sparkle: sparkle)
            return ScannedApp(
                id: app.bundleIdentifier ?? app.bundlePath,
                name: app.name,
                bundlePath: app.bundlePath,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: app.installedVersion,
                source: source,
                updateStatus: status,
                lastCheckedAt: now
            )
        }
    }

    private static func attribute(
        app: DiscoveredApp,
        mas: [String: UpdateCheckResult],
        homebrew: [String: UpdateCheckResult],
        electron: [String: UpdateCheckResult],
        sparkle: [String: UpdateCheckResult]
    ) -> (AppSource, UpdateStatus) {
        if app.hasMacAppStoreReceipt {
            return (.macAppStore, mas[app.bundlePath]?.status ?? .unknownMasCliMissing)
        }
        if let result = homebrew[app.bundlePath] {
            return (.homebrewCask, result.status)
        }
        if app.electronUpdateConfig != nil {
            return (.electron, electron[app.bundlePath]?.status ?? .checkFailed(reason: "No result"))
        }
        if app.sparkleFeedURL != nil {
            return (.sparkleFeed, sparkle[app.bundlePath]?.status ?? .checkFailed(reason: "No result"))
        }
        return (.unknown, .unknownNoSource)
    }
}
