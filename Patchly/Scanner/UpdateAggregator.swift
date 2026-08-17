import Foundation

/// Runs all Update Sources concurrently and applies the Mac App Store >
/// Homebrew Cask > Electron > Sparkle Feed > Custom App priority merge from
/// CONTEXT.md.
actor UpdateAggregator {
    private let scanner: ApplicationScanner
    private let macAppStoreChecker: any UpdateSource
    private let homebrewCaskChecker: any UpdateSource
    private let electronUpdateChecker: any UpdateSource
    private let sparkleFeedChecker: any UpdateSource
    private let customAppSourceChecker: any UpdateSource

    init(
        scanner: ApplicationScanner = ApplicationScanner(),
        macAppStoreChecker: any UpdateSource = MacAppStoreChecker(),
        homebrewCaskChecker: any UpdateSource = HomebrewCaskChecker(),
        electronUpdateChecker: any UpdateSource = ElectronUpdateChecker(),
        sparkleFeedChecker: any UpdateSource = SparkleFeedChecker(),
        customAppSourceChecker: any UpdateSource = CustomAppSourceChecker()
    ) {
        self.scanner = scanner
        self.macAppStoreChecker = macAppStoreChecker
        self.homebrewCaskChecker = homebrewCaskChecker
        self.electronUpdateChecker = electronUpdateChecker
        self.sparkleFeedChecker = sparkleFeedChecker
        self.customAppSourceChecker = customAppSourceChecker
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
            sparkleFeedChecker: sparkleFeedChecker,
            customAppSourceChecker: customAppSourceChecker
        )
    }

    static func mergeResults(
        discovered: [DiscoveredApp],
        macAppStoreChecker: any UpdateSource,
        homebrewCaskChecker: any UpdateSource,
        electronUpdateChecker: any UpdateSource,
        sparkleFeedChecker: any UpdateSource,
        customAppSourceChecker: any UpdateSource
    ) async -> [ScannedApp] {
        async let macResults = macAppStoreChecker.checkUpdates(for: discovered)
        async let homebrewResults = homebrewCaskChecker.checkUpdates(for: discovered)
        async let electronResults = electronUpdateChecker.checkUpdates(for: discovered)
        async let sparkleResults = sparkleFeedChecker.checkUpdates(for: discovered)
        async let customAppResults = customAppSourceChecker.checkUpdates(for: discovered)

        let (mas, homebrew, electron, sparkle, customApp) = await (macResults, homebrewResults, electronResults, sparkleResults, customAppResults)
        let now = Date()

        return discovered.map { app in
            let (source, status, action) = attribute(app: app, mas: mas, homebrew: homebrew, electron: electron, sparkle: sparkle, customApp: customApp)
            return ScannedApp(
                id: app.bundleIdentifier ?? app.bundlePath,
                name: app.name,
                bundlePath: app.bundlePath,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: app.installedVersion,
                source: source,
                updateStatus: status,
                lastCheckedAt: now,
                updateAction: action
            )
        }
    }

    private static func attribute(
        app: DiscoveredApp,
        mas: [String: UpdateCheckResult],
        homebrew: [String: UpdateCheckResult],
        electron: [String: UpdateCheckResult],
        sparkle: [String: UpdateCheckResult],
        customApp: [String: UpdateCheckResult]
    ) -> (AppSource, UpdateStatus, UpdateAction?) {
        if app.hasMacAppStoreReceipt {
            let result = mas[app.bundlePath]
            return (.macAppStore, result?.status ?? .unknownMasCliMissing, result?.action)
        }
        if let result = homebrew[app.bundlePath] {
            return (.homebrewCask, result.status, result.action)
        }
        if app.electronUpdateConfig != nil {
            let result = electron[app.bundlePath]
            return (.electron, result?.status ?? .checkFailed(reason: "No result"), result?.action)
        }
        if app.sparkleFeedURL != nil {
            let result = sparkle[app.bundlePath]
            return (.sparkleFeed, result?.status ?? .checkFailed(reason: "No result"), result?.action)
        }
        // Custom App Source is checked last, and only takes effect when it
        // actually produced a result — unlike the other fallback branches
        // above, there's no per-app scan-time signal that says "this app
        // belongs here" the way `electronUpdateConfig`/`sparkleFeedURL` do;
        // membership in the (small, explicit) checker registry is itself
        // the signal, and that's exactly what a non-nil result means.
        if let result = customApp[app.bundlePath] {
            return (.customApp, result.status, result.action)
        }
        return (.unknown, .unknownNoSource, nil)
    }
}
