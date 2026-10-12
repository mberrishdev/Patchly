import AppKit
import SwiftUI

/// A Scanned App in the Usage view: how often and how recently it was
/// opened, and its App Size. Clicking it reveals the app in Finder, same as
/// an `AppRowView`. See CONTEXT.md ("Usage view").
struct UsageRowView: View {
    let app: ScannedApp
    let isOpenNow: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body).lineLimit(1)
                Text(usageText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(sizeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.bundlePath)])
        }
    }

    /// A missing Use Count or Last Used Date says nothing about whether the
    /// app was ever opened (an update clears both), so the fallback is
    /// "No usage recorded", never "Never opened". An app that's Open Now says
    /// so instead of its Last Used Date, which only moves on launch — an app
    /// left open for a week would otherwise read "last week". See CONTEXT.md.
    private var usageText: String {
        let lastUsed = isOpenNow ? "open now" : app.lastUsedDate?.formatted(.relative(presentation: .named))
        switch (app.useCount, lastUsed) {
        case let (count?, lastUsed?) where count > 0:
            return "\(count) \(count == 1 ? "open" : "opens") · \(lastUsed)"
        case (_, _?) where isOpenNow:
            return "Open now"
        case let (_, lastUsed?):
            return "Opened \(lastUsed)"
        default:
            return "No usage recorded"
        }
    }

    private var sizeText: String {
        app.sizeInBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }
}
