import AppKit
import Foundation

/// The published source of truth the UI observes. Owns cache-first loading,
/// the manual/auto Refresh loop, and the wake-from-sleep subscription.
/// See CONTEXT.md.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var scannedApps: [ScannedApp] = []
    @Published private(set) var cliTools: [CLITool] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var installingBundlePaths: Set<String> = []
    @Published var selectedBundlePaths: Set<String> = []

    var badgeCount: Int {
        scannedApps.filter(\.updateStatus.isUpdateAvailable).count
    }

    var sortedApps: [ScannedApp] {
        scannedApps.sorted { lhs, rhs in
            if lhs.updateStatus.sortPriority != rhs.updateStatus.sortPriority {
                return lhs.updateStatus.sortPriority < rhs.updateStatus.sortPriority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private let aggregator: UpdateAggregator
    private let cacheStore: CacheStore
    private let settings: AppSettings
    private let installer: UpdateInstaller
    private let cliToolScanner: CLIToolScanner

    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init(
        aggregator: UpdateAggregator = UpdateAggregator(),
        cacheStore: CacheStore = CacheStore(),
        settings: AppSettings,
        installer: UpdateInstaller = UpdateInstaller(),
        cliToolScanner: CLIToolScanner = CLIToolScanner()
    ) {
        self.aggregator = aggregator
        self.cacheStore = cacheStore
        self.settings = settings
        self.installer = installer
        self.cliToolScanner = cliToolScanner
        self.scannedApps = cacheStore.load()
    }

    func start() {
        refresh()
        scheduleTimer()
        observeWake()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
    }

    /// Runs `brew install mas`, then re-checks Mac App Store Source apps only —
    /// not a full Refresh. See CONTEXT.md ("Unknown — mas Missing").
    func installMasCLI() async {
        guard let brewPath = ExecutableLocator.locateBrew() else { return }
        _ = try? await ProcessRunner().run(executablePath: brewPath, arguments: ["install", "mas"], timeout: 180)
        await recheckMacAppStoreApps()
    }

    /// Installs the update for each given app via `UpdateInstaller`, in
    /// parallel — one app's failure never blocks another's. A failed install
    /// sets that app's Update Status to Check Failed with the reason, reusing
    /// the existing status UI rather than adding a separate error surface.
    /// Successful Homebrew/Mac App Store installs are reflected by a full
    /// Refresh afterward, since the install may have changed more than just
    /// the one app (e.g. `brew upgrade` can touch the local tap metadata).
    /// See CONTEXT.md.
    func installUpdates(for bundlePaths: Set<String>) async {
        let targets = scannedApps.filter { bundlePaths.contains($0.bundlePath) }
        guard !targets.isEmpty else { return }

        installingBundlePaths.formUnion(targets.map(\.bundlePath))
        selectedBundlePaths.subtract(targets.map(\.bundlePath))

        var anySucceeded = false
        await withTaskGroup(of: UpdateInstallResult.self) { group in
            for app in targets {
                group.addTask { await self.installer.install(app) }
            }
            for await result in group {
                if result.succeeded {
                    anySucceeded = true
                } else if let index = scannedApps.firstIndex(where: { $0.bundlePath == result.bundlePath }) {
                    scannedApps[index].updateStatus = .checkFailed(reason: result.failureReason ?? "Update failed")
                }
            }
        }

        installingBundlePaths.subtract(targets.map(\.bundlePath))
        cacheStore.save(scannedApps)

        if anySucceeded {
            refresh()
        }
    }

    private func recheckMacAppStoreApps() async {
        let targets = scannedApps.filter { $0.source == .macAppStore }
        guard !targets.isEmpty else { return }

        let discovered = targets.map { app in
            DiscoveredApp(
                name: app.name,
                bundlePath: app.bundlePath,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: app.installedVersion,
                hasMacAppStoreReceipt: true,
                sparkleFeedURL: nil
            )
        }

        let results = await aggregator.recheckMacAppStore(for: discovered)
        guard !results.isEmpty else { return }

        let now = Date()
        for index in scannedApps.indices {
            guard scannedApps[index].source == .macAppStore,
                  let result = results[scannedApps[index].bundlePath]
            else { continue }
            scannedApps[index].updateStatus = result.status
            scannedApps[index].lastCheckedAt = now
        }
        cacheStore.save(scannedApps)
    }

    private func performRefresh() async {
        isRefreshing = true
        async let appsResult = aggregator.refresh()
        async let toolsResult = scanCLIToolsIfEnabled()
        let results = await appsResult
        let tools = await toolsResult
        guard !Task.isCancelled else {
            isRefreshing = false
            return
        }
        scannedApps = results
        cliTools = tools
        lastRefreshDate = Date()
        isRefreshing = false
        cacheStore.save(results)
    }

    /// CLI Tool detection is 100% local and read-only, so it's cheap to fold
    /// into the same Refresh — but only when the user has opted in. See
    /// CONTEXT.md ("CLI Tool").
    private func scanCLIToolsIfEnabled() async -> [CLITool] {
        guard settings.showsCLITools else { return [] }
        return await cliToolScanner.scanInstalledTools()
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.settings.refreshIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    /// Not removed in deinit: AppState is held for the app's entire lifetime by
    /// PatchlyApp, so there's no earlier teardown point to remove it at.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
        timerTask?.cancel()
    }
}
