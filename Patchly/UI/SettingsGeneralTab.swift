import SwiftUI

struct SettingsGeneralTab: View {
    @ObservedObject var settings: AppSettings

    private static let refreshIntervalOptions: [(label: String, seconds: TimeInterval)] = [
        ("1 hour", 1 * 60 * 60),
        ("3 hours", 3 * 60 * 60),
        ("6 hours", 6 * 60 * 60),
        ("12 hours", 12 * 60 * 60),
        ("24 hours", 24 * 60 * 60)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("General")
                    .font(.largeTitle.bold())
                Text("Refresh behavior and what shows in the list")
                    .foregroundStyle(.secondary)
            }

            SettingsCard(label: "Refresh") {
                SettingsCardRow(
                    title: "Auto-refresh interval",
                    subtitle: "How often Patchly re-scans in the background."
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { settings.refreshIntervalSeconds },
                            set: { settings.refreshIntervalSeconds = $0 }
                        )
                    ) {
                        ForEach(Self.refreshIntervalOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }

            SettingsCard(label: "Menu Bar") {
                SettingsCardRow(
                    title: "Show badge count",
                    subtitle: "Show the number of apps with an update available next to the menu bar icon."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.showsBadgeCount },
                            set: { settings.showsBadgeCount = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            SettingsCard(label: "List") {
                SettingsCardRow(
                    title: "Show CLI tools",
                    subtitle: "List Homebrew-installed developer command-line tools with their versions, and check for updates."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.showsCLITools },
                            set: { settings.showsCLITools = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            SettingsCard(label: "Startup") {
                SettingsCardRow(
                    title: "Launch at login",
                    subtitle: "Start Patchly automatically when you sign in."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { settings.launchAtLoginEnabled = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    SettingsGeneralTab(settings: AppSettings())
}
