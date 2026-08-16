import SwiftUI

@main
struct PatchlyApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var appState: AppState

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        let appState = AppState(settings: settings)
        _appState = StateObject(wrappedValue: appState)
        // MenuBarExtra only builds its content view once the user opens the
        // dropdown, so Refresh must be kicked off here, not in a `.task`.
        appState.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            MenuBarLabelView(badgeCount: settings.showsBadgeCount ? appState.badgeCount : 0)
        }
        .menuBarExtraStyle(.window)
    }
}
