import SwiftUI

struct MenuBarLabelView: View {
    let badgeCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }
}

#Preview {
    MenuBarLabelView(badgeCount: 3)
}
