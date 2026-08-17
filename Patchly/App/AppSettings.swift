import Foundation

/// UserDefaults-backed preferences. The key strings are load-bearing (stored
/// picks) — do not rename without a migration.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let showsBadgeCount = "showsBadgeCount"
        static let showsCLITools = "showsCLITools"
    }

    static let defaultRefreshIntervalSeconds: TimeInterval = 6 * 60 * 60

    private let defaults: UserDefaults

    @Published var refreshIntervalSeconds: TimeInterval {
        didSet { defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds) }
    }

    @Published var showsBadgeCount: Bool {
        didSet { defaults.set(showsBadgeCount, forKey: Keys.showsBadgeCount) }
    }

    /// Gates CLI Tool detection and display — off by default since it's a new,
    /// opt-in surface. See CONTEXT.md ("CLI Tool").
    @Published var showsCLITools: Bool {
        didSet { defaults.set(showsCLITools, forKey: Keys.showsCLITools) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = storedInterval > 0 ? storedInterval : Self.defaultRefreshIntervalSeconds
        self.showsBadgeCount = defaults.object(forKey: Keys.showsBadgeCount) as? Bool ?? true
        self.showsCLITools = defaults.object(forKey: Keys.showsCLITools) as? Bool ?? false
    }
}
