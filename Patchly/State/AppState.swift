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
    @Published private(set) var installingCLIToolNames: Set<String> = []
    @Published var selectedBundlePaths: Set<String> = []
    @Published var selectedCLIToolNames: Set<String> = []

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

    /// Same priority-then-name ordering as `sortedApps`, so CLI Tools that
    /// need an update aren't buried alphabetically among however many
    /// Homebrew formulae are installed.
    var sortedCLITools: [CLITool] {
        cliTools.sorted { lhs, rhs in
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
    private let cliToolUpdateAggregator: CLIToolUpdateAggregator

    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var previouslyAvailableBundlePaths: Set<String>

    init(
        aggregator: UpdateAggregator = UpdateAggregator(),
        cacheStore: CacheStore = CacheStore(),
        settings: AppSettings,
        installer: UpdateInstaller = UpdateInstaller(),
        cliToolUpdateAggregator: CLIToolUpdateAggregator = CLIToolUpdateAggregator()
    ) {
        self.aggregator = aggregator
        self.cacheStore = cacheStore
        self.settings = settings
        self.installer = installer
        self.cliToolUpdateAggregator = cliToolUpdateAggregator
        let cached = cacheStore.load()
        self.scannedApps = cached.apps
        self.cliTools = cached.cliTools
        self.previouslyAvailableBundlePaths = Set(
            cached.apps.filter(\.updateStatus.isUpdateAvailable).map(\.bundlePath)
        )
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
        cacheStore.save(apps: scannedApps, cliTools: cliTools)

        if anySucceeded {
            refresh()
        }
    }

    /// Installs the update for each given CLI Tool via `UpdateInstaller`, in
    /// parallel — one tool's failure never blocks another's, same as
    /// `installUpdates(for:)`. A successful batch re-runs only the CLI Tool
    /// discovery+check pass, never a full Refresh — a `brew upgrade` can't
    /// change anything about `scannedApps`. See CONTEXT.md.
    func installCLIToolUpdates(for names: Set<String>) async {
        let targets = cliTools.filter { names.contains($0.name) }
        guard !targets.isEmpty else { return }

        installingCLIToolNames.formUnion(targets.map(\.name))
        selectedCLIToolNames.subtract(targets.map(\.name))

        var anySucceeded = false
        await withTaskGroup(of: CLIToolUpdateInstallResult.self) { group in
            for tool in targets {
                group.addTask { await self.installer.install(tool) }
            }
            for await result in group {
                if result.succeeded {
                    anySucceeded = true
                } else if let index = cliTools.firstIndex(where: { $0.name == result.name }) {
                    cliTools[index].updateStatus = .checkFailed(reason: result.failureReason ?? "Update failed")
                }
            }
        }

        installingCLIToolNames.subtract(targets.map(\.name))

        if anySucceeded {
            let tools = await refreshCLIToolsIfEnabled()
            guard !Task.isCancelled else {
                cacheStore.save(apps: scannedApps, cliTools: cliTools)
                return
            }
            cliTools = tools
        }
        cacheStore.save(apps: scannedApps, cliTools: cliTools)
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
        cacheStore.save(apps: scannedApps, cliTools: cliTools)
    }

    /// Both passes start together, but Scanned Apps publish as soon as
    /// they're ready rather than waiting on CLI Tools too, since there's no
    /// reason to hold the app results back for an unrelated check.
    /// `isRefreshing` — and the disabled Refresh button — stays true for the
    /// whole duration, not just the apps portion. See CONTEXT.md.
    private func performRefresh() async {
        isRefreshing = true
        async let appsResult = aggregator.refresh()
        async let toolsResult = refreshCLIToolsIfEnabled()

        let results = await appsResult
        guard !Task.isCancelled else {
            isRefreshing = false
            return
        }
        scannedApps = results
        cacheStore.save(apps: results, cliTools: cliTools)
        notifyAboutNewlyAvailableUpdates(in: results)

        let tools = await toolsResult
        guard !Task.isCancelled else {
            isRefreshing = false
            return
        }
        cliTools = tools
        lastRefreshDate = Date()
        isRefreshing = false
        cacheStore.save(apps: scannedApps, cliTools: tools)
    }

    /// CLI Tool discovery and Homebrew Formula checking are both local and
    /// read-only, folded into the same Refresh, but only when the user has
    /// opted in. See CONTEXT.md ("CLI Tool").
    private func refreshCLIToolsIfEnabled() async -> [CLITool] {
        guard settings.showsCLITools else { return [] }
        return await cliToolUpdateAggregator.refresh()
    }

    /// Notifies only for Scanned Apps that newly entered Update Available
    /// this Refresh — never re-notifies for ones still pending from a prior
    /// Refresh. See CONTEXT.md.
    private func notifyAboutNewlyAvailableUpdates(in results: [ScannedApp]) {
        let currentlyAvailable = results.filter(\.updateStatus.isUpdateAvailable)
        let currentlyAvailableBundlePaths = Set(currentlyAvailable.map(\.bundlePath))
        defer { previouslyAvailableBundlePaths = currentlyAvailableBundlePaths }

        guard settings.notifiesOnUpdateAvailable else { return }
        let newlyAvailableNames = currentlyAvailable
            .filter { !previouslyAvailableBundlePaths.contains($0.bundlePath) }
            .map(\.name)
        UpdateNotifier.notify(newlyAvailableAppNames: newlyAvailableNames)
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
                self?.refreshIfIntervalHasElapsedSinceLastRefresh()
            }
        }
    }

    /// A wake-from-sleep re-check only actually runs a Refresh if the
    /// configured auto-refresh interval has elapsed since the last one —
    /// otherwise a laptop that sleeps/wakes many times a day (lid closed
    /// between short breaks) would refresh far more often than the user's
    /// chosen interval, even though the timer itself already honors it.
    /// The still-running timer task is unaffected either way: it keeps
    /// counting toward its own next scheduled Refresh regardless of what
    /// wake events do here.
    private func refreshIfIntervalHasElapsedSinceLastRefresh() {
        guard Self.shouldRefreshOnWake(lastRefreshDate: lastRefreshDate, intervalSeconds: settings.refreshIntervalSeconds, now: Date()) else { return }
        refresh()
    }

    nonisolated static func shouldRefreshOnWake(lastRefreshDate: Date?, intervalSeconds: TimeInterval, now: Date) -> Bool {
        guard let lastRefreshDate else { return true }
        return now.timeIntervalSince(lastRefreshDate) >= intervalSeconds
    }

    deinit {
        refreshTask?.cancel()
        timerTask?.cancel()
    }
}
