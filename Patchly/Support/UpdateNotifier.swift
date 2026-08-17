import UserNotifications

/// Posts a macOS user notification when a Refresh finds Scanned Apps that
/// newly entered Update Available — never for ones that were already in that
/// status before this Refresh. See CONTEXT.md.
enum UpdateNotifier {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(newlyAvailableAppNames names: [String]) {
        guard !names.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = names.count == 1 ? "Update Available" : "\(names.count) Updates Available"
        content.body = names.count <= 3
            ? names.joined(separator: ", ")
            : "\(names.prefix(3).joined(separator: ", ")) and \(names.count - 3) more"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
