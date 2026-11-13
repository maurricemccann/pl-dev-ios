import SwiftUI
import WidgetKit

struct ComposerEntry: TimelineEntry { let date: Date; let glance: ComposerGlance? }

struct ComposerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComposerEntry {
        ComposerEntry(date: .now, glance: ComposerGlance(sent: 1, rendering: 1, mixing: 0, filed: 4, ruled: 2, failed: 0, newestShot: "comp-10 velvet", newestLane: "rendering", pieces: 2, piece: "the-practice-v1", shots: 9, seconds: 38.5, updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (ComposerEntry) -> Void) { completion(ComposerEntry(date: .now, glance: SharedState.readComposer() ?? placeholder(in: context).glance)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComposerEntry>) -> Void) {
        let g = SharedState.readComposer()
        completion(Timeline(entries: [ComposerEntry(date: .now, glance: g)], policy: .after(.now.addingTimeInterval((g?.inFlight ?? 0) > 0 ? 900 : 3600))))
    }
}

struct ComposerWidgetView: View {
    let entry: ComposerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "film.stack"); Text("\(g.inFlight)").font(.headline) }.widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Composer").font(.headline).widgetAccentable()
                    Text(g.inFlight > 0 ? "\(g.inFlight) rendering or waiting" : "Nothing rendering").lineLimit(1)
                    Text("\(g.filed) filed · \(g.failed) failed").font(.caption2).lineLimit(1)
                }
            case .systemMedium:
                HStack(alignment: .top, spacing: 14) {
                    board(g)
                    Divider()
                    piece(g)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Composer", systemImage: "film.stack").font(.caption.bold()).widgetAccentable()
                    Text("\(g.inFlight)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(g.inFlight == 1 ? "render in flight" : "renders in flight").font(.caption2).foregroundStyle(.secondary)
                    if let s = g.newestShot { Text("\(s) · \((g.newestLane ?? "").capitalized)").font(.caption2).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading) { Label("Composer", systemImage: "film.stack").font(.headline); Text("Open Composer once to fill this.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func board(_ g: ComposerGlance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Render board", systemImage: "square.grid.3x2").font(.caption.bold()).widgetAccentable()
            ForEach([("Sent", g.sent), ("Rendering", g.rendering), ("Mixing", g.mixing), ("Filed", g.filed), ("Failed", g.failed)], id: \.0) { n, c in
                HStack { Text(n).font(.caption2); Spacer(); Text("\(c)").font(.caption2.bold()).monospacedDigit() }.foregroundStyle(n == "Failed" && c > 0 ? Color.red : Color.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func piece(_ g: ComposerGlance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Open piece", systemImage: "film").font(.caption.bold()).widgetAccentable()
            Text(g.piece ?? "No piece yet").font(.subheadline.bold()).lineLimit(2)
            Text("\(g.shots) \(g.shots == 1 ? "shot" : "shots") · \(String(format: "%.1f", g.seconds)) s").font(.caption).foregroundStyle(.secondary)
            if let s = g.newestShot { Text("Newest: \(s)").font(.caption2).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ComposerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.composerWidget, provider: ComposerProvider()) { e in
            ComposerWidgetView(entry: e).widgetURL(URL(string: "pldev://section/composer/board")).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Composer")
        .description("The render board in counts, and the piece you have open.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
