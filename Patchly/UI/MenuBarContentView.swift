import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updater: AppUpdater
    @ObservedObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showBatchUpdateConfirm = false
    @State private var showCLIToolBatchUpdateConfirm = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            if filteredApps.isEmpty && filteredCLITools.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredApps) { app in
                            AppRowView(
                                app: app,
                                isSelected: app.updateStatus.isUpdateAvailable ? selectionBinding(for: app) : nil,
                                isInstalling: appState.installingBundlePaths.contains(app.bundlePath),
                                onUpdate: {
                                    Task { await appState.installUpdates(for: [app.bundlePath]) }
                                },
                                onInstallMas: {
                                    Task { await appState.installMasCLI() }
                                }
                            )
                            Divider()
                        }

                        if !filteredCLITools.isEmpty {
                            cliToolsHeader
                            ForEach(filteredCLITools) { tool in
                                CLIToolRowView(
                                    tool: tool,
                                    isSelected: tool.updateStatus.isUpdateAvailable ? cliToolSelectionBinding(for: tool) : nil,
                                    isInstalling: appState.installingCLIToolNames.contains(tool.name),
                                    onUpdate: {
                                        Task { await appState.installCLIToolUpdates(for: [tool.name]) }
                                    }
                                )
                                Divider()
                            }
                        }
                    }
                }
                // `maxHeight` alone gives ScrollView no reliable intrinsic size in a
                // MenuBarExtra `.window` popover, and it can collapse to zero height.
                // Compute an explicit height from row count instead, floored to a
                // whole number of rows — a partial row peeking at the clipped edge
                // reads as if the footer below is covering it.
                .frame(height: listHeight)

                if !appState.selectedBundlePaths.isEmpty {
                    Divider()
                    selectionBar
                }
                if !appState.selectedCLIToolNames.isEmpty {
                    Divider()
                    cliToolSelectionBar
                }
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var filteredApps: [ScannedApp] {
        guard !searchText.isEmpty else { return appState.sortedApps }
        return appState.sortedApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredCLITools: [CLITool] {
        guard settings.showsCLITools else { return [] }
        guard !searchText.isEmpty else { return appState.sortedCLITools }
        return appState.sortedCLITools.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var cliToolsHeader: some View {
        Text("CLI Tools")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func selectionBinding(for app: ScannedApp) -> Binding<Bool> {
        Binding(
            get: { appState.selectedBundlePaths.contains(app.bundlePath) },
            set: { isOn in
                if isOn {
                    appState.selectedBundlePaths.insert(app.bundlePath)
                } else {
                    appState.selectedBundlePaths.remove(app.bundlePath)
                }
            }
        )
    }

    private var selectionBar: some View {
        HStack {
            Text("\(appState.selectedBundlePaths.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Update Selected") {
                showBatchUpdateConfirm = true
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .confirmationDialog(
            "Update \(appState.selectedBundlePaths.count) apps?",
            isPresented: $showBatchUpdateConfirm,
            titleVisibility: .visible
        ) {
            Button("Update") {
                let targets = appState.selectedBundlePaths
                Task { await appState.installUpdates(for: targets) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func cliToolSelectionBinding(for tool: CLITool) -> Binding<Bool> {
        Binding(
            get: { appState.selectedCLIToolNames.contains(tool.name) },
            set: { isOn in
                if isOn {
                    appState.selectedCLIToolNames.insert(tool.name)
                } else {
                    appState.selectedCLIToolNames.remove(tool.name)
                }
            }
        )
    }

    private var cliToolSelectionBar: some View {
        HStack {
            Text("\(appState.selectedCLIToolNames.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Update Selected") {
                showCLIToolBatchUpdateConfirm = true
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .confirmationDialog(
            "Update \(appState.selectedCLIToolNames.count) CLI tools?",
            isPresented: $showCLIToolBatchUpdateConfirm,
            titleVisibility: .visible
        ) {
            Button("Update") {
                let targets = appState.selectedCLIToolNames
                Task { await appState.installCLIToolUpdates(for: targets) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Patchly").font(.headline)
                    Text("v\(AppVersion.shortVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            .help("Refresh")
        }
        .padding(12)
    }

    private var emptyState: some View {
        Text(emptyStateText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(24)
    }

    private var emptyStateText: String {
        if !searchText.isEmpty {
            return "No matches"
        }
        return appState.isRefreshing ? "Scanning applications…" : "No applications found"
    }

    private var footer: some View {
        VStack(spacing: 2) {
            menuRow(title: "Check for Updates…", shortcut: nil) {
                dismiss()
                // LSUIElement apps never activate themselves, so Sparkle's
                // update alert would otherwise land behind whatever app
                // currently has focus.
                NSApp.activate(ignoringOtherApps: true)
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            menuRow(title: "Settings…", shortcut: "⌘,") {
                dismiss()
                // Same reasoning as above — see the settings-gear fix this
                // replaced.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            menuRow(title: "Quit Patchly", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 6)
    }

    private func menuRow(title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var listHeight: CGFloat {
        let estimatedRowHeight: CGFloat = 44
        let estimatedSectionHeaderHeight: CGFloat = 22
        let maxHeight: CGFloat = 420
        var contentHeight = CGFloat(filteredApps.count) * estimatedRowHeight
        if !filteredCLITools.isEmpty {
            contentHeight += estimatedSectionHeaderHeight
            contentHeight += CGFloat(filteredCLITools.count) * estimatedRowHeight
        }
        guard contentHeight > maxHeight else {
            return max(contentHeight, estimatedRowHeight)
        }
        // Floor to a whole number of rows within the cap — a partial row
        // peeking at the clipped edge reads as though the footer below it
        // is covering the text, rather than as a normal scroll boundary.
        return (maxHeight / estimatedRowHeight).rounded(.down) * estimatedRowHeight
    }

    private var lastRefreshedText: String {
        guard let date = appState.lastRefreshDate else { return "Not yet refreshed" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

#Preview {
    let settings = AppSettings()
    return MenuBarContentView(appState: AppState(settings: settings), updater: AppUpdater(), settings: settings)
}
