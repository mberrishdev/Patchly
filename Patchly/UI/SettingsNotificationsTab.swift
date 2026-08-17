import SwiftUI

struct SettingsNotificationsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications")
                    .font(.largeTitle.bold())
                Text("Get notified when updates are found")
                    .foregroundStyle(.secondary)
            }

            SettingsCard(label: "Alerts") {
                SettingsCardRow(
                    title: "Notify when updates are available",
                    subtitle: "Post a notification when a Refresh finds apps that newly have an update available."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.notifiesOnUpdateAvailable },
                            set: { settings.notifiesOnUpdateAvailable = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            Text("You won't be notified again for an app that's still pending an update from an earlier Refresh — only for ones that newly need one.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    SettingsNotificationsTab(settings: AppSettings())
}
