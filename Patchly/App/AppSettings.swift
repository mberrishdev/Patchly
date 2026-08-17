import Foundation

/// UserDefaults-backed preferences. The key strings are load-bearing (stored
/// picks) — do not rename without a migration.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let showsBadgeCount = "showsBadgeCount"
        static let showsCLITools = "showsCLITools"
        static let notifiesOnUpdateAvailable = "notifiesOnUpdateAvailable"
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

    /// Registers/unregisters Patchly as a login item. Backed by
    /// `SMAppService`, not UserDefaults, since the login item registration
    /// itself is the source of truth — see `LaunchAtLoginManager`.
    @Published var launchAtLoginEnabled: Bool {
        didSet { LaunchAtLoginManager.setEnabled(launchAtLoginEnabled) }
    }

    /// Gates posting a user notification when a Refresh finds Scanned Apps
    /// newly in Update Available — off by default, same opt-in reasoning as
    /// `showsCLITools`.
    @Published var notifiesOnUpdateAvailable: Bool {
        didSet {
            defaults.set(notifiesOnUpdateAvailable, forKey: Keys.notifiesOnUpdateAvailable)
            if notifiesOnUpdateAvailable {
                UpdateNotifier.requestAuthorizationIfNeeded()
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = storedInterval > 0 ? storedInterval : Self.defaultRefreshIntervalSeconds
        self.showsBadgeCount = defaults.object(forKey: Keys.showsBadgeCount) as? Bool ?? true
        self.showsCLITools = defaults.object(forKey: Keys.showsCLITools) as? Bool ?? false
        self.launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        self.notifiesOnUpdateAvailable = defaults.object(forKey: Keys.notifiesOnUpdateAvailable) as? Bool ?? false
    }
}
