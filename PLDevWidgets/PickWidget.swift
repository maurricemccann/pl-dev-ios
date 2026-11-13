import SwiftUI
import WidgetKit

struct PickEntry: TimelineEntry { let date: Date; let glance: PickGlance? }

struct PickProvider: TimelineProvider {
    func placeholder(in context: Context) -> PickEntry {
        PickEntry(date: .now, glance: PickGlance(leader: "ember", leaderVotes: 7, total: 19, ground: "#0e0c08", key: "#c9a84c", accent: "#d9702a", text: "#efe6d2", mine: nil, updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (PickEntry) -> Void) { completion(PickEntry(date: .now, glance: SharedState.readPick() ?? placeholder(in: context).glance)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PickEntry>) -> Void) {
        completion(Timeline(entries: [PickEntry(date: .now, glance: SharedState.readPick())], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct PickWidgetView: View {
    let entry: PickEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let g = entry.glance, let leader = g.leader {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "paintpalette"); Text("\(g.leaderVotes)").font(.headline) }.widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Colourway").font(.headline).widgetAccentable()
                    Text("\(leader) leads, \(g.leaderVotes) of \(g.total)").lineLimit(1)
                    if let m = g.mine { Text("You picked \(m)").font(.caption2).lineLimit(1) }
                }
            case .systemMedium:
                HStack(spacing: 12) {
                    swatch(g).frame(width: 96).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    info(g, leader)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    swatch(g).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(leader).font(.caption.bold()).lineLimit(1)
                    Text("\(g.leaderVotes) of \(g.total)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading) { Label("Colourway", systemImage: "paintpalette").font(.headline); Text("No picks yet. Open Pick once to fill this.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func swatch(_ g: PickGlance) -> some View {
        if let gr = g.ground, let k = g.key, let a = g.accent, let t = g.text { PickSwatchArt(ground: gr, text: t, key: k, accent: a) } else { Color.secondary.opacity(0.2) }
    }

    private func info(_ g: PickGlance, _ leader: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next colourway", systemImage: "paintpalette").font(.caption.bold()).widgetAccentable()
            Text(leader).font(.title3.bold()).lineLimit(1)
            Text("leads with \(g.leaderVotes) of \(g.total) \(g.total == 1 ? "pick" : "picks")").font(.caption).foregroundStyle(.secondary)
            if let m = g.mine { Text("You picked \(m).").font(.caption2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.pickWidget, provider: PickProvider()) { e in
            PickWidgetView(entry: e).widgetURL(URL(string: "pldev://section/pick/results")).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Colourway vote")
        .description("Which colourway leads the vote for the next piece.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
