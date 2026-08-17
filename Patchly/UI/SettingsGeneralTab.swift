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

            SettingsCard(label: "List") {
                SettingsCardRow(
                    title: "Show CLI tools",
                    subtitle: "List installed developer command-line tools (git, node, npm, and similar) with their versions. Display only — no update checks."
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

            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    SettingsGeneralTab(settings: AppSettings())
}
