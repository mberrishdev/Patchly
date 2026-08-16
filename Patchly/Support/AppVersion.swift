import Foundation

enum AppVersion {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var displayString: String {
        "Version \(shortVersion)"
    }
}
