import SwiftUI

/// The dropdown's Usage tab: every Scanned App with its Use Count, Last Used
/// Date, and App Size, in the chosen `UsageOrder`. Read-only — it never
/// changes Update Status, Selection, or the Badge Count. See CONTEXT.md
/// ("Usage view").
struct UsageListView: View {
    let apps: [ScannedApp]
    @Binding var order: UsageOrder

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(order.sorted(apps)) { app in
                        UsageRowView(app: app)
                        Divider()
                    }
                }
            }
            .frame(height: DropdownListHeight.height(rowCount: apps.count))
        }
    }

    private var summary: some View {
        HStack {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Sort", selection: $order) {
                ForEach(UsageOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var summaryText: String {
        let total = apps.compactMap(\.sizeInBytes).reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(apps.count) \(apps.count == 1 ? "app" : "apps") · \(size)"
    }
}
