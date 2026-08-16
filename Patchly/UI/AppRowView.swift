import AppKit
import SwiftUI

struct AppRowView: View {
    let app: ScannedApp
    var onInstallMas: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body)
                Text(versionText).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            SourceBadgeView(source: app.source)

            statusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.bundlePath)])
        }
    }

    private var versionText: String {
        switch app.updateStatus {
        case .updateAvailable(let latest):
            "\(app.installedVersion) → \(latest)"
        default:
            app.installedVersion
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch app.updateStatus {
        case .updateAvailable:
            Circle().fill(Color.orange).frame(width: 8, height: 8)
        case .checkFailed:
            Circle().fill(Color.red).frame(width: 8, height: 8)
        case .unknownMasCliMissing:
            Button("Install mas", action: onInstallMas)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
        case .upToDate, .checking, .unknownNoSource:
            EmptyView()
        }
    }
}
