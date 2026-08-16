import Foundation

/// Runs all three Update Sources concurrently and applies the Mac App Store >
/// Homebrew Cask > Sparkle Feed priority merge from CONTEXT.md.
actor UpdateAggregator {
    private let scanner: ApplicationScanner
    private let macAppStoreChecker: any UpdateSource
    private let homebrewCaskChecker: any UpdateSource
    private let sparkleFeedChecker: any UpdateSource

    init(
        scanner: ApplicationScanner = ApplicationScanner(),
        macAppStoreChecker: any UpdateSource = MacAppStoreChecker(),
        homebrewCaskChecker: any UpdateSource = HomebrewCaskChecker(),
        sparkleFeedChecker: any UpdateSource = SparkleFeedChecker()
    ) {
        self.scanner = scanner
        self.macAppStoreChecker = macAppStoreChecker
        self.homebrewCaskChecker = homebrewCaskChecker
        self.sparkleFeedChecker = sparkleFeedChecker
    }

    func refresh() async -> [ScannedApp] {
        let discovered = await scanner.scanInstalledApps()
        return await Self.mergeResults(
            discovered: discovered,
            macAppStoreChecker: macAppStoreChecker,
            homebrewCaskChecker: homebrewCaskChecker,
            sparkleFeedChecker: sparkleFeedChecker
        )
    }

    static func mergeResults(
        discovered: [DiscoveredApp],
        macAppStoreChecker: any UpdateSource,
        homebrewCaskChecker: any UpdateSource,
        sparkleFeedChecker: any UpdateSource
    ) async -> [ScannedApp] {
        async let macResults = macAppStoreChecker.checkUpdates(for: discovered)
        async let homebrewResults = homebrewCaskChecker.checkUpdates(for: discovered)
        async let sparkleResults = sparkleFeedChecker.checkUpdates(for: discovered)

        let (mas, homebrew, sparkle) = await (macResults, homebrewResults, sparkleResults)
        let now = Date()

        return discovered.map { app in
            let (source, status) = attribute(app: app, mas: mas, homebrew: homebrew, sparkle: sparkle)
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
        sparkle: [String: UpdateCheckResult]
    ) -> (AppSource, UpdateStatus) {
        if app.hasMacAppStoreReceipt {
            return (.macAppStore, mas[app.bundlePath]?.status ?? .unknownMasCliMissing)
        }
        if let result = homebrew[app.bundlePath] {
            return (.homebrewCask, result.status)
        }
        if app.sparkleFeedURL != nil {
            return (.sparkleFeed, sparkle[app.bundlePath]?.status ?? .checkFailed(reason: "No result"))
        }
        return (.unknown, .unknownNoSource)
    }
}
