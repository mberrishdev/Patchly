import SwiftUI

/// A single CLI Tool row: name + version, plus an Update Status slot when
/// the tool is attributed to a CLI Tool Source — a tool with no attributed
/// source shows nothing beyond its version, same as before source
/// attribution existed. No checkbox and no Selection; a CLI Tool updates
/// one row at a time. See CONTEXT.md ("CLI Tool").
struct CLIToolRowView: View {
    let tool: CLITool
    var isInstalling = false
    var onUpdate: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.body)
                Text(versionText).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            CLIToolSourceBadgeView(source: tool.source)

            statusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var versionText: String {
        switch tool.updateStatus {
        case .updateAvailable(let latest):
            "\(tool.version) → \(latest)"
        default:
            tool.version
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch tool.updateStatus {
        case .updateAvailable:
            if isInstalling {
                ProgressView().controlSize(.small)
            } else {
                Button("Update", action: onUpdate)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        case .checkFailed:
            Circle().fill(Color.red).frame(width: 8, height: 8)
        case .upToDate, .checking, .unknownNoSource, .unknownMasCliMissing:
            EmptyView()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        CLIToolRowView(tool: .preview(name: "rg", source: .homebrewFormula, status: .updateAvailable(latestVersion: "14.1.1")))
        Divider()
        CLIToolRowView(tool: .preview(name: "jq", source: .homebrewFormula, status: .upToDate))
        Divider()
        CLIToolRowView(tool: .preview(name: "curl", source: .none, status: .unknownNoSource))
    }
    .frame(width: 340)
}

private extension CLITool {
    static func preview(name: String, source: CLIToolSource, status: UpdateStatus) -> CLITool {
        CLITool(name: name, version: "1.0.0", source: source, updateStatus: status)
    }
}
