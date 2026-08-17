import ServiceManagement

/// Registers/unregisters Patchly as a login item via `SMAppService`, which is
/// itself the source of truth (not UserDefaults) — the user can also remove
/// it from System Settings → General → Login Items directly.
enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best effort: SMAppService surfaces registration problems (e.g.
            // needing approval) via System Settings itself.
        }
    }
}
