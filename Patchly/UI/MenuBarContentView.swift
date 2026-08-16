import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.sortedApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.sortedApps) { app in
                            AppRowView(app: app) {
                                Task { await appState.installMasCLI() }
                            }
                            Divider()
                        }
                    }
                }
                // `maxHeight` alone gives ScrollView no reliable intrinsic size in a
                // MenuBarExtra `.window` popover, and it can collapse to zero height.
                // Compute an explicit height from row count instead.
                .frame(height: listHeight)
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Patchly").font(.headline)
                Text(lastRefreshedText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.refresh()
            } label: {
                if appState.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.isRefreshing)
        }
        .padding(12)
    }

    private var emptyState: some View {
        Text(appState.isRefreshing ? "Scanning applications…" : "No applications found")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(24)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit Patchly") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var listHeight: CGFloat {
        let estimatedRowHeight: CGFloat = 44
        let contentHeight = CGFloat(appState.sortedApps.count) * estimatedRowHeight
        return min(max(contentHeight, estimatedRowHeight), 420)
    }

    private var lastRefreshedText: String {
        guard let date = appState.lastRefreshDate else { return "Not yet refreshed" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
