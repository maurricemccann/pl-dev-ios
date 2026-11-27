import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Rising: the last check-in on the Home Screen and the Lock Screen (his pick 11-26, item 89)

struct RisingEntry: TimelineEntry {
    let date: Date
    let glance: RisingGlance?
}

struct RisingProvider: TimelineProvider {
    func placeholder(in context: Context) -> RisingEntry {
        RisingEntry(date: .now, glance: RisingGlance(band: "Steady", step: "Add a little", level: 4, at: .now, shiftEnds: .now.addingTimeInterval(3600)))
    }
    func getSnapshot(in context: Context, completion: @escaping (RisingEntry) -> Void) {
        completion(RisingEntry(date: .now, glance: RisingGlance.read() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RisingEntry>) -> Void) {
        let g = RisingGlance.read()
        var entries = [RisingEntry(date: .now, glance: g)]
        if let g, g.shiftEnds > .now { entries.append(RisingEntry(date: g.shiftEnds, glance: g)) }   // flips to "check in" when the shift ends
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3 * 3600))))
    }
}

struct RisingWidgetView: View {
    let entry: RisingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance, entry.date < g.shiftEnds {
            switch family {
            case .accessoryInline:
                Text("\(g.band) · \(g.at, style: .time)")
            case .accessoryCircular:
                Gauge(value: Double(g.level + 1), in: 0...7) { Image(systemName: "arrow.up.heart") } currentValueLabel: { Text(String(g.band.prefix(1))) }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .accessibilityLabel("\(g.band), step \(g.level + 1) of 7")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.band).font(.headline).widgetAccentable()
                    Text(g.step)
                    Text("at \(g.at, style: .time)").foregroundStyle(.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Rising", systemImage: "arrow.up.heart.fill").font(.caption.bold()).widgetAccentable()
                    Text(g.band).font(.system(.title, design: .rounded, weight: .bold))
                    Text(g.step).font(.callout).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("Checked in \(g.at, style: .time)").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryInline: Text("Rising: check in")
            case .accessoryCircular: Image(systemName: "arrow.up.heart").font(.title2).accessibilityLabel("Check in")
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Rising", systemImage: "arrow.up.heart").font(.headline)
                    Text("How is it in you right now? Tap to check in.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RisingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.risingWidget, provider: RisingProvider()) { entry in
            RisingWidgetView(entry: entry)
                .widgetURL(URL(string: "pldev://home"))   // the check-in waits on Home whenever the app opens
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rising")
        .description("Your last check-in this shift. Tap to check in again.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - The shift's check-ins as a Live Activity

struct RisingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RisingAttributes.self) { ctx in
            HStack(alignment: .center, spacing: 12) {
                Gauge(value: Double(ctx.state.level + 1), in: 0...7) {
                    Image(systemName: "arrow.up.heart")
                } currentValueLabel: {
                    Text(String(ctx.state.band.prefix(1))).font(.headline)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.state.band).font(.headline.weight(.semibold))
                    Text(ctx.state.step).font(.subheadline).lineLimit(1)
                    Text(ctx.isStale ? "New shift. Tap to check in." : "Checked in \(ctx.state.at.formatted(date: .omitted, time: .shortened)). Tap to check in again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.35))
            .smallFamilyFit()
            .widgetURL(URL(string: "pldev://home"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.state.band, systemImage: "arrow.up.heart").font(.headline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ctx.state.at, style: .time).font(.headline.weight(.medium)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ctx.state.step + ". Tap to check in again.").font(.subheadline).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "arrow.up.heart")
            } compactTrailing: {
                Text(ctx.state.band).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
            } minimal: {
                Text(String(ctx.state.band.prefix(1))).font(.caption.weight(.bold))
            }
            .widgetURL(URL(string: "pldev://home"))
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
