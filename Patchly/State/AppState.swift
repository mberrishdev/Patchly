import AppKit
import Foundation

/// The published source of truth the UI observes. Owns cache-first loading,
/// the manual/auto Refresh loop, and the wake-from-sleep subscription.
/// See CONTEXT.md.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var scannedApps: [ScannedApp] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?

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

    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init(
        aggregator: UpdateAggregator = UpdateAggregator(),
        cacheStore: CacheStore = CacheStore(),
        settings: AppSettings
    ) {
        self.aggregator = aggregator
        self.cacheStore = cacheStore
        self.settings = settings
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

    /// Runs `brew install mas`, then re-checks Mac App Store Source apps.
    /// See CONTEXT.md ("Unknown — mas Missing").
    func installMasCLI() async {
        guard let brewPath = ExecutableLocator.locateBrew() else { return }
        _ = try? await ProcessRunner().run(executablePath: brewPath, arguments: ["install", "mas"], timeout: 180)
        refresh()
    }

    private func performRefresh() async {
        isRefreshing = true
        let results = await aggregator.refresh()
        guard !Task.isCancelled else {
            isRefreshing = false
            return
        }
        scannedApps = results
        lastRefreshDate = Date()
        isRefreshing = false
        cacheStore.save(results)
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
