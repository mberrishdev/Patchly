import SwiftUI

struct SourceBadgeView: View {
    let source: AppSource

    var body: some View {
        if let label {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var label: String? {
        switch source {
        case .macAppStore: "App Store"
        case .homebrewCask: "Homebrew"
        case .sparkleFeed: "Sparkle"
        case .unknown: nil
        }
    }
}
