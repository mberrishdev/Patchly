import SwiftUI

struct CLIToolSourceBadgeView: View {
    let source: CLIToolSource

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
        case .homebrewFormula: "Homebrew"
        case .none: nil
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        CLIToolSourceBadgeView(source: .homebrewFormula)
        CLIToolSourceBadgeView(source: .none)
    }
    .padding()
}
