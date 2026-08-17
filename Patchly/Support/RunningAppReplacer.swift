import AppKit
import Foundation

enum RunningAppReplaceError: Error, LocalizedError, Equatable {
    case couldNotQuitRunningApp
    case replaceFailed(String)
    /// macOS blocks any write inside another app's bundle unless Patchly has
    /// been granted "App Management" (System Settings > Privacy & Security >
    /// App Management) — there's no API to request this proactively, the OS
    /// just blocks the first attempt and adds Patchly to that list for the
    /// user to turn on. `replaceItemAt` surfaces this as a generic
    /// "Operation not permitted" NSCocoaErrorDomain/NSFileWriteNoPermission
    /// error, which isn't actionable on its own — this case exists so the
    /// UI can say what to actually do instead.
    case missingAppManagementPermission

    var errorDescription: String? {
        switch self {
        case .couldNotQuitRunningApp: "couldn't quit the running app to replace it"
        case .replaceFailed(let reason): "couldn't install the update: \(reason)"
        case .missingAppManagementPermission:
            "Patchly needs \"App Management\" permission to install this update — grant it in System Settings → Privacy & Security → App Management, then try again"
        }
    }
}

/// Safely swaps a verified update into place: quits the app if it's running
/// (escalating from a graceful to a forced quit, giving up rather than
/// replacing files under a process that won't exit), replaces the bundle,
/// then relaunches it. Shared by every direct-install path — by the time
/// this runs, the caller has already verified the replacement is trustworthy;
/// this step is purely mechanical and identical regardless of source.
struct RunningAppReplacer: Sendable {
    @MainActor
    func quitIfRunning(bundlePath: String) async throws {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == bundleURL }) else {
            return
        }

        running.terminate()
        if await waitForTermination(of: running, timeout: 10) { return }

        running.forceTerminate()
        if await waitForTermination(of: running, timeout: 5) { return }

        throw RunningAppReplaceError.couldNotQuitRunningApp
    }

    @MainActor
    private func waitForTermination(of app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !app.isTerminated, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return app.isTerminated
    }

    func replace(targetBundlePath: String, withAppAt newAppURL: URL) throws {
        let targetURL = URL(fileURLWithPath: targetBundlePath)
        do {
            _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: newAppURL)
        } catch {
            if Self.isPermissionDenied(error) {
                throw RunningAppReplaceError.missingAppManagementPermission
            }
            throw RunningAppReplaceError.replaceFailed(error.localizedDescription)
        }
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(EPERM) {
            return true
        }
        return false
    }

    @MainActor
    func relaunch(bundlePath: String) async {
        _ = try? await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: bundlePath),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
