import SwiftUI
import WidgetKit

// MARK: - The Site widget: the shop's pieces and what waits in the Congregation, from the app's last read

struct StorefrontEntry: TimelineEntry {
    let date: Date
    let glance: StorefrontGlance?
}

struct StorefrontProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorefrontEntry {
        StorefrontEntry(date: .now, glance: StorefrontGlance(pieces: 53, inStock: 50, fresh: ["Heart Mark Tee"], held: 2, members: 7, updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (StorefrontEntry) -> Void) {
        completion(StorefrontEntry(date: .now, glance: SharedState.readStorefront() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StorefrontEntry>) -> Void) {
        // the app reloads this kind when its numbers change; the half-hour refresh only keeps the "updated" age honest
        completion(Timeline(entries: [StorefrontEntry(date: .now, glance: SharedState.readStorefront())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct StorefrontWidgetView: View {
    let entry: StorefrontEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("The site").font(.headline).widgetAccentable()
                    Text("\(g.pieces) pieces · \(g.inStock) in stock")
                    if let h = g.held { Text(h == 0 ? "Nothing waits for you" : "\(h) waiting for you").lineLimit(1) }
                    else if let f = g.fresh.first { Text("New: \(f)").lineLimit(1) }
                }
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "bag").widgetAccentable()
                    Text("\(g.pieces)").font(.headline).monospacedDigit()
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("The site", systemImage: "bag.fill").font(.caption.bold()).widgetAccentable()
                        Spacer()
                        Text(g.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(g.pieces)").font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                        Text("pieces").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(g.inStock) in stock").font(.caption).foregroundStyle(.secondary)
                    if family != .systemSmall {
                        Divider()
                        HStack(spacing: 4) {
                            Image(systemName: "person.3").widgetAccentable()
                            Text("\(g.members) members")
                            if let h = g.held { Text("· \(h == 0 ? "nothing waits" : "\(h) waiting for you")").foregroundStyle(h == 0 ? Color.secondary : Color.orange) }
                        }.font(.callout)
                        if let f = g.fresh.first { Text("New: \(f)").font(.callout).lineLimit(1) }
                    } else if let f = g.fresh.first {
                        Text("New: \(f)").font(.caption).lineLimit(2)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("The site", systemImage: "bag").font(.headline)
                Text("Open Shop once to fill this.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct StorefrontWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.storefrontWidget, provider: StorefrontProvider()) { entry in
            StorefrontWidgetView(entry: entry)
                .widgetURL(URL(string: "pldev://section/shop"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("The site")
        .description("Pieces in the shop, and what waits for you in the Congregation.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
