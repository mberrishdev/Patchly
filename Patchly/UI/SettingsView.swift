import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image("MenuBarIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary)

            Text("Patchly")
                .font(.headline)

            Text(AppVersion.displayString)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 260)
    }
}

#Preview {
    SettingsView()
}
