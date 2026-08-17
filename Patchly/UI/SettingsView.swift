import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            SettingsUpdatesTab(updater: updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

            SettingsGeneralTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 420, height: 380)
    }
}

#Preview {
    SettingsView(updater: AppUpdater(), settings: AppSettings())
}
