import SwiftUI

/// A single CLI Tool row: name + version, nothing else — no checkbox, no
/// source badge, no update button. CLI Tools are display-only, so this is
/// deliberately simpler than `AppRowView`. See CONTEXT.md ("CLI Tool").
struct CLIToolRowView: View {
    let tool: CLITool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.body)
                Text(tool.version).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

#Preview {
    VStack(spacing: 0) {
        CLIToolRowView(tool: CLITool(name: "git", executablePath: "/usr/bin/git", version: "git version 2.43.0"))
        Divider()
        CLIToolRowView(tool: CLITool(name: "node", executablePath: "/opt/homebrew/bin/node", version: "v20.11.0"))
    }
    .frame(width: 340)
}
