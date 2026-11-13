import SwiftUI
import WidgetKit

struct TownEntry: TimelineEntry { let date: Date; let glance: TownGlance? }

struct TownProvider: TimelineProvider {
    func placeholder(in context: Context) -> TownEntry {
        TownEntry(date: .now, glance: TownGlance(open: 6, done: 3, his: 1, blocked: 0, stale: 1, working: true, at: "STUDIO", calls: 1634, updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (TownEntry) -> Void) {
        completion(TownEntry(date: .now, glance: SharedState.readTown() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TownEntry>) -> Void) {
        completion(Timeline(entries: [TownEntry(date: .now, glance: SharedState.readTown())], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct TownWidgetView: View {
    let entry: TownEntry
    @Environment(\.widgetFamily) private var family
    private let gold = Color(red: 1, green: 0.878, blue: 0.478)

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "building.2"); Text("\(g.open)").font(.headline) }.widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Task Town").font(.headline).widgetAccentable()
                    Text("\(g.open) open · \(g.done) done")
                    Text(g.working ? "Session at \((g.at ?? "work").capitalized)" : "Session quiet").lineLimit(1)
                }
            case .systemMedium:
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Task Town", systemImage: "building.2").font(.caption.bold()).widgetAccentable()
                        Text("\(g.open)").font(.system(size: 40, weight: .heavy, design: .monospaced)).foregroundStyle(gold).contentTransition(.numericText())
                        Text("open on the Roadmap").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        row("Done", g.done); row("Waiting on you", g.his); row("Blocked", g.blocked); row("Stale", g.stale)
                        Text(g.working ? "Session at \((g.at ?? "work").capitalized)" : "Session quiet").font(.caption2.bold()).foregroundStyle(gold).lineLimit(1)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Task Town", systemImage: "building.2").font(.caption.bold()).widgetAccentable()
                    Text("\(g.open)").font(.system(size: 38, weight: .heavy, design: .monospaced)).foregroundStyle(gold).contentTransition(.numericText())
                    Text("open · \(g.done) done").font(.caption2).foregroundStyle(.secondary)
                    if g.his > 0 { Text("\(g.his) waiting on you").font(.caption2.bold()) }
                    Text(g.working ? "At \((g.at ?? "work").capitalized)" : "Session quiet").font(.caption2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading) { Label("Task Town", systemImage: "building.2").font(.headline); Text("Open Town once to fill this.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func row(_ k: String, _ v: Int) -> some View {
        HStack { Text(k).font(.caption2).foregroundStyle(.secondary); Spacer(minLength: 8); Text("\(v)").font(.caption.bold().monospacedDigit()) }
    }
}

struct TownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.townWidget, provider: TownProvider()) { e in
            TownWidgetView(entry: e).widgetURL(URL(string: "pldev://section/town")).containerBackground(for: .widget) { Color(red: 0.071, green: 0.047, blue: 0.024) }
        }
        .configurationDisplayName("Task Town")
        .description("How many tasks are open, what waits on you, and where the session is working.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
