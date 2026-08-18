import SwiftUI

struct MenuBarLabelView: View {
    let badgeCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
            // The status bar flattens this whole label into one template
            // image and recolors it from its alpha channel alone, so any
            // tint or color (an orange dot, a colored "D") gets discarded
            // just like the icon itself — only actual text glyphs survive
            // that as a legible marker, hence plain text here instead of
            // a color-coded badge.
            #if DEBUG
            Text("D")
                .font(.system(size: 10, weight: .bold))
            #endif
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
