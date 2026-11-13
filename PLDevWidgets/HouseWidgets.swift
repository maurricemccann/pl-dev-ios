import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - House widget: drafts waiting and the shift, from the app's last read

struct HouseEntry: TimelineEntry {
    let date: Date
    let glance: HouseGlance?
}

struct HouseProvider: TimelineProvider {
    func placeholder(in context: Context) -> HouseEntry {
        HouseEntry(date: .now, glance: HouseGlance(drafts: 12, done: 3, total: 8, next: "Approve the morning drafts", nextTime: "6:00 PM", updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (HouseEntry) -> Void) {
        completion(HouseEntry(date: .now, glance: SharedState.readHouse() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HouseEntry>) -> Void) {
        // the app reloads this kind when its numbers change; the half-hour refresh only keeps the "updated" age honest
        completion(Timeline(entries: [HouseEntry(date: .now, glance: SharedState.readHouse())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct HouseWidgetView: View {
    let entry: HouseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("House").font(.headline).widgetAccentable()
                    Text("\(g.drafts) drafts · \(g.done)/\(g.total) shift")
                    if let n = g.next { Text(n).lineLimit(1) }
                }
            case .accessoryCircular:
                Gauge(value: Double(g.done), in: 0...Double(max(g.total, 1))) { Image(systemName: "house") } currentValueLabel: { Text("\(g.drafts)") }
                    .gaugeStyle(.accessoryCircularCapacity)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("House", systemImage: "house.fill").font(.caption.bold()).widgetAccentable()
                        Spacer()
                        Text(g.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(g.drafts)").font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                        Text("drafts").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(g.done), total: Double(max(g.total, 1))) {
                        Text("Shift \(g.done) of \(g.total)").font(.caption)
                    }
                    .widgetAccentable()
                    if family != .systemSmall, let n = g.next {
                        Text(n).font(.callout).lineLimit(2)
                        if let t = g.nextTime { Text(t).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("House", systemImage: "house").font(.headline)
                Text("Open House once to fill this.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HouseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.houseWidget, provider: HouseProvider()) { entry in
            HouseWidgetView(entry: entry)
                .widgetURL(URL(string: "pldev://section/house"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("House")
        .description("Drafts waiting and how far the shift has come.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - The shift as a Live Activity

struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftAttributes.self) { ctx in
            HStack(alignment: .center, spacing: 12) {
                Gauge(value: Double(ctx.state.done), in: 0...Double(max(ctx.state.total, 1))) {
                    Image(systemName: "checklist")
                } currentValueLabel: {
                    Text("\(ctx.state.done)").font(.headline)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(HouseTint.key)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.isStale ? "Open House to refresh" : "Now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(ctx.state.task).font(.headline.weight(.semibold)).lineLimit(2)
                    Text("\(ctx.state.done) of \(ctx.state.total) done\(ctx.state.time.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.35))
            .activitySystemActionForegroundColor(HouseTint.key)
            .widgetURL(URL(string: "pldev://section/house"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(ctx.state.done)/\(ctx.state.total)", systemImage: "checklist").font(.headline.weight(.semibold)).foregroundStyle(HouseTint.key)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let t = ctx.state.time { Text(t).font(.headline.weight(.medium)).monospacedDigit() }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ctx.state.task).font(.headline.weight(.semibold)).lineLimit(2)
                        ProgressView(value: Double(ctx.state.done), total: Double(max(ctx.state.total, 1))).tint(HouseTint.key)
                    }
                }
            } compactLeading: {
                Image(systemName: "checklist").foregroundStyle(HouseTint.key)
            } compactTrailing: {
                Text("\(ctx.state.done)/\(ctx.state.total)").font(.caption.weight(.semibold)).monospacedDigit()
            } minimal: {
                Text("\(ctx.state.total - ctx.state.done)").font(.caption.weight(.bold)).foregroundStyle(HouseTint.key)
            }
            .widgetURL(URL(string: "pldev://section/house"))
        }
    }
}
