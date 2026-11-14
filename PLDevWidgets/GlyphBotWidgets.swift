import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - GlyphBot widget: how far the interview has come, from the app's last read

struct GlyphBotEntry: TimelineEntry {
    let date: Date
    let glance: GlyphBotGlance?
}

struct GlyphBotProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlyphBotEntry {
        GlyphBotEntry(date: .now, glance: GlyphBotGlance(asked: 118, total: 501, answers: 342, thinnest: "Legacy", thinnestCount: 9, waiting: 0, updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (GlyphBotEntry) -> Void) {
        completion(GlyphBotEntry(date: .now, glance: GlyphBotGlance.read() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GlyphBotEntry>) -> Void) {
        // the app reloads this kind when its numbers change; the half-hour refresh only keeps the "updated" age honest
        completion(Timeline(entries: [GlyphBotEntry(date: .now, glance: GlyphBotGlance.read())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct GlyphBotWidgetView: View {
    let entry: GlyphBotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("GlyphBot").font(.headline).widgetAccentable()
                    Text("\(g.asked) of \(g.total) asked")
                    if let t = g.thinnest { Text("Thinnest: \(t)").lineLimit(1) }
                }
            case .accessoryCircular:
                Gauge(value: Double(g.asked), in: 0...Double(max(g.total, 1))) { Image(systemName: "bubbles.and.sparkles") } currentValueLabel: { Text("\(g.asked)") }
                    .gaugeStyle(.accessoryCircularCapacity)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("GlyphBot", systemImage: "bubbles.and.sparkles.fill").font(.caption.bold()).widgetAccentable()
                        Spacer()
                        Text(g.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(g.answers)").font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                        Text("answers").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(g.asked), total: Double(max(g.total, 1))) { Text("Bank \(g.asked) of \(g.total)").font(.caption) }
                        .widgetAccentable()
                    if family != .systemSmall, let t = g.thinnest {
                        Text("Thinnest: \(t), \(g.thinnestCount) answers").font(.callout).lineLimit(2)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("GlyphBot", systemImage: "bubbles.and.sparkles").font(.headline)
                Text("Open GlyphBot once to fill this.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct GlyphBotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.glyphbotWidget, provider: GlyphBotProvider()) { entry in
            GlyphBotWidgetView(entry: entry)
                .widgetURL(URL(string: "pldev://section/glyphbot/record"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("GlyphBot")
        .description("How many bank questions are asked, how many answers are kept, and the thinnest domain.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - A sitting as a Live Activity

struct SittingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SittingAttributes.self) { ctx in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bubbles.and.sparkles").font(.title2).foregroundStyle(HouseTint.key)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.isStale ? "Open GlyphBot" : ctx.attributes.mode).font(.headline.weight(.semibold))
                    Text("\(ctx.state.answers) answers · \(ctx.state.seat)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(ctx.attributes.started, style: .timer).font(.title3.monospacedDigit()).frame(width: 72, alignment: .trailing)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.35))
            .smallFamilyFit()
            .activitySystemActionForegroundColor(HouseTint.key)
            .widgetURL(URL(string: "pldev://section/glyphbot/interview"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("\(ctx.state.answers)", systemImage: "text.bubble").font(.headline.weight(.semibold)).foregroundStyle(HouseTint.key) }
                DynamicIslandExpandedRegion(.trailing) { Text(ctx.attributes.started, style: .timer).font(.headline.monospacedDigit()).frame(width: 64, alignment: .trailing) }
                DynamicIslandExpandedRegion(.bottom) { Text("\(ctx.attributes.mode) · \(ctx.state.seat)").font(.headline.weight(.semibold)) }
            } compactLeading: {
                Image(systemName: "bubbles.and.sparkles").foregroundStyle(HouseTint.key)
            } compactTrailing: {
                Text("\(ctx.state.answers)").font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)   // iOS 27: the island in landscape cannot grow wider
            } minimal: {
                Image(systemName: "bubbles.and.sparkles").foregroundStyle(HouseTint.key)
            }
            .widgetURL(URL(string: "pldev://section/glyphbot/interview"))
        }
        .supplementalActivityFamilies([.small, .medium])   // iOS 27 forwards it to the Watch Smart Stack and CarPlay
    }
}
