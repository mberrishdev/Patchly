import SwiftUI

struct SettingsUpdatesTab: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Updates")
                    .font(.largeTitle.bold())
                Text("Keep Patchly current")
                    .foregroundStyle(.secondary)
            }

            SettingsCard(label: "Version") {
                SettingsCardRow(title: AppVersion.displayString, subtitle: lastCheckedText) {
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }

            SettingsCard(label: "Automatic") {
                SettingsCardRow(
                    title: "Check for updates automatically",
                    subtitle: "Runs when Patchly launches and periodically after that."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                SettingsCardDivider()

                SettingsCardRow(
                    title: "Download updates automatically",
                    subtitle: "Fetch the update in advance. Installing still waits for you to confirm."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { updater.automaticallyDownloadsUpdates },
                            set: { updater.automaticallyDownloadsUpdates = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!updater.automaticallyChecksForUpdates)
                }
            }

            Text("Updates are downloaded from GitHub and verified with an EdDSA signature before they're installed. An update that fails verification is discarded.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last checked \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

#Preview {
    SettingsUpdatesTab(updater: AppUpdater())
}
