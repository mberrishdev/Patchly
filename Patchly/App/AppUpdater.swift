import Combine
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController` so SwiftUI
/// can observe it. This is Patchly self-updating — distinct from the
/// read-only Sparkle Feed Source, which parses *other* apps' appcasts with
/// `XMLParser` and never touches the Sparkle framework. See CONTEXT.md.
@MainActor
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            guard controller.updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        self.lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
