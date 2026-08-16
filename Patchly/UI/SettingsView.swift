import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        SettingsUpdatesTab(updater: updater)
            .frame(width: 420)
    }
}

#Preview {
    SettingsView(updater: AppUpdater())
}
