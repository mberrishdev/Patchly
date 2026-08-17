import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case notifications
    case updates

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .notifications: "Notifications"
        case .updates: "Updates"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var settings: AppSettings
    @State private var section: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                List(SettingsSection.allCases, selection: $section) { item in
                    Label(item.label, systemImage: item.systemImage)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                detailView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 640, height: 460)
    }

    @ViewBuilder
    private var detailView: some View {
        switch section ?? .general {
        case .general:
            SettingsGeneralTab(settings: settings)
        case .notifications:
            SettingsNotificationsTab(settings: settings)
        case .updates:
            SettingsUpdatesTab(updater: updater)
        }
    }
}

#Preview {
    SettingsView(updater: AppUpdater(), settings: AppSettings())
}
