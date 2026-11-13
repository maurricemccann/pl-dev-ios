import SwiftUI
import WidgetKit

struct LibraryEntry: TimelineEntry { let date: Date; let glance: LibraryGlance? }

struct LibraryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry { LibraryEntry(date: .now, glance: LibraryGlance(unmarked: 609, kept: 2826, batch: "11-09 yt", batchNew: 6, updatedAt: .now)) }
    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) { completion(LibraryEntry(date: .now, glance: SharedState.readLibrary() ?? placeholder(in: context).glance)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        completion(Timeline(entries: [LibraryEntry(date: .now, glance: SharedState.readLibrary())], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct LibraryWidgetView: View {
    let entry: LibraryEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "rectangle.stack"); Text("\(g.unmarked)").font(.headline) }.widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Curate").font(.headline).widgetAccentable()
                    Text("\(g.unmarked) waiting")
                    if let b = g.batch { Text("\(b): \(g.batchNew) new").lineLimit(1) }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Curate", systemImage: "rectangle.stack").font(.caption.bold()).widgetAccentable()
                    Text("\(g.unmarked)").font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                    Text("waiting for a mark").font(.caption).foregroundStyle(.secondary)
                    if let b = g.batch { Text("Newest \(b) · \(g.batchNew) new").font(.caption2).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading) { Label("Curate", systemImage: "rectangle.stack").font(.headline); Text("Open Curate once to fill this.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct LibraryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.libraryWidget, provider: LibraryProvider()) { e in
            LibraryWidgetView(entry: e).widgetURL(URL(string: "pldev://section/curate")).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Curate")
        .description("How many pieces wait for your mark, and the newest batch.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}
