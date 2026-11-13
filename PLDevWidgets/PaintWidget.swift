import SwiftUI
import WidgetKit

struct PaintEntry: TimelineEntry { let date: Date; let glance: PaintGlance? }

struct PaintProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaintEntry { PaintEntry(date: .now, glance: PaintGlance(today: 28, monthDays: 9, works: 3, updatedAt: .now)) }
    func getSnapshot(in context: Context, completion: @escaping (PaintEntry) -> Void) { completion(PaintEntry(date: .now, glance: SharedState.readPaint() ?? placeholder(in: context).glance)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PaintEntry>) -> Void) {
        // the day turns at midnight: refresh then, so "today" is never yesterday's number
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        completion(Timeline(entries: [PaintEntry(date: .now, glance: SharedState.readPaint())], policy: .after(midnight)))
    }
}

struct PaintWidgetView: View {
    let entry: PaintEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let g = entry.glance
        let marked = Calendar.current.isDateInToday(g?.updatedAt ?? .distantPast) && (g?.today ?? 0) > 0
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) { Image(systemName: marked ? "paintbrush.pointed.fill" : "paintbrush.pointed"); Text("\(g?.monthDays ?? 0)").font(.headline) }.widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("Daily Mark", systemImage: "paintbrush.pointed.fill").font(.caption.bold()).widgetAccentable()
                Text(marked ? "Marked today" : "Not yet today").font(.headline)
                Text("\(g?.monthDays ?? 0) days this month").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(g?.works ?? 0) works").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PaintWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.paintWidget, provider: PaintProvider()) { e in
            PaintWidgetView(entry: e).widgetURL(URL(string: "pldev://section/paint/canvas")).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Mark")
        .description("Whether today has its mark, and the days this month. Tap to paint.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
