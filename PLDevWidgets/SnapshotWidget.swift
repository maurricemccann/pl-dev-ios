import SwiftUI
import WidgetKit

/// One reading of what the app last shared.
struct SnapshotEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil when the app has shared nothing yet, or this install has no shared store
}

/// Reads the snapshot the app wrote. No network: the app redraws this widget whenever the snapshot changes.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot(updatedAt: Date(), inboxCount: 0, badges: [:], statusLine: "All clear"))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        let next = Date().addingTimeInterval(15 * 60)   // a slow safety refresh; the app's own reload is the fast path
        completion(Timeline(entries: [current()], policy: .after(next)))
    }

    private func current() -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: SharedState.readSnapshot())
    }
}

struct SnapshotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.snapshotWidget, provider: SnapshotProvider()) { entry in
            SnapshotWidgetView(entry: entry)
        }
        .configurationDisplayName("PL DEV")
        .description("Shows what is waiting and the last status.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct SnapshotWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int { entry.snapshot?.inboxCount ?? 0 }

    private var symbol: String { count > 0 ? "tray.full.fill" : "tray" }

    private var title: String {
        switch count {
        case 0: return "Inbox clear"
        case 1: return "1 waiting"
        default: return "\(count) waiting"
        }
    }

    private var detail: String {
        guard let snapshot = entry.snapshot else { return "Open to start" }
        return snapshot.statusLine
    }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(DeepLink.home.url)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3.weight(.semibold))
                        .minimumScaleFactor(0.6)
                }
                .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .widgetAccentable()
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(title, systemImage: symbol)
        default:
            small
        }
    }

    /// The Home Screen and StandBy square.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            if let updated = entry.snapshot?.updatedAt {
                Text("Updated \(updated, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
