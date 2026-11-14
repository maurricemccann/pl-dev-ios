import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Practice widget: today's loop and the soft streak, from the app's last read

struct PracticeEntry: TimelineEntry {
    let date: Date
    let glance: PracticeGlance?
}

struct PracticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PracticeEntry {
        PracticeEntry(date: .now, glance: PracticeGlance(monthDays: 14, totalDays: 62, weekDays: 5, morning: true, evening: false, habitsDone: 2, habitsTotal: 3,
                                                         lessonTitle: "Prepared for Luxury", line: "I am prepared for every opportunity that comes my way now.", updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (PracticeEntry) -> Void) {
        completion(PracticeEntry(date: .now, glance: PracticeGlance.read() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PracticeEntry>) -> Void) {
        // the app reloads this kind when its numbers change; the hourly refresh only keeps "today" honest across midnight
        completion(Timeline(entries: [PracticeEntry(date: .now, glance: PracticeGlance.read())], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct PracticeWidgetView: View {
    let entry: PracticeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Practice").font(.headline).widgetAccentable()
                    Text("\(g.morning ? "Morning ✓" : "Morning") · \(g.evening ? "Evening ✓" : "Evening")")
                    if g.habitsTotal > 0 { Text("\(g.habitsDone) of \(g.habitsTotal) habits") }
                }
            case .accessoryCircular:
                Gauge(value: Double(done(g)), in: 0...Double(max(total(g), 1))) { Image(systemName: "heart.text.square") } currentValueLabel: { Text("\(done(g))") }
                    .gaugeStyle(.accessoryCircularCapacity)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Practice", systemImage: "heart.text.square.fill").font(.caption.bold()).widgetAccentable()
                        Spacer()
                        Text(g.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(g.monthDays)").font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                        Text("days this month").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(done(g)), total: Double(max(total(g), 1))) { Text("Today \(done(g)) of \(total(g))").font(.caption) }
                        .widgetAccentable()
                    if family != .systemSmall, let line = g.line ?? g.lessonTitle {
                        Text(line).font(.callout).lineLimit(3)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Practice", systemImage: "heart.text.square").font(.headline)
                Text("Open Practice once to fill this.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Today's loop: the two check-ins and the habits.
    private func total(_ g: PracticeGlance) -> Int { 2 + g.habitsTotal }
    private func done(_ g: PracticeGlance) -> Int { (g.morning ? 1 : 0) + (g.evening ? 1 : 0) + g.habitsDone }
}

struct PracticeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.practiceWidget, provider: PracticeProvider()) { entry in
            PracticeWidgetView(entry: entry)
                .widgetURL(URL(string: "pldev://section/practice"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Practice")
        .description("Today's check-ins and habits, and the days you have practised.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - The rehearsal as a Live Activity

struct RehearsalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RehearsalAttributes.self) { ctx in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "wind").font(.title2).foregroundStyle(HouseTint.key)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.isStale ? "Open Practice" : ctx.state.title).font(.headline.weight(.semibold))
                    Text(ctx.attributes.desire).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(timerInterval: ctx.attributes.started...ctx.attributes.ends, countsDown: true).font(.title3.monospacedDigit()).frame(width: 64, alignment: .trailing)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.35))
            .smallFamilyFit()
            .activitySystemActionForegroundColor(HouseTint.key)
            .widgetURL(URL(string: "pldev://section/practice/rehearsal"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("\(ctx.state.stage + 1) of 5", systemImage: "wind").font(.headline.weight(.semibold)).foregroundStyle(HouseTint.key) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: ctx.attributes.started...ctx.attributes.ends, countsDown: true).font(.headline.monospacedDigit()).frame(width: 60, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ctx.state.title).font(.headline.weight(.semibold))
                        ProgressView(value: Double(ctx.state.stage + 1), total: 5).tint(HouseTint.key)
                    }
                }
            } compactLeading: {
                Image(systemName: "wind").foregroundStyle(HouseTint.key)
            } compactTrailing: {
                Text(timerInterval: ctx.attributes.started...ctx.attributes.ends, countsDown: true).font(.caption.monospacedDigit()).frame(width: 40).lineLimit(1).minimumScaleFactor(0.6)   // iOS 27: the island in landscape cannot grow wider
            } minimal: {
                Image(systemName: "wind").foregroundStyle(HouseTint.key)
            }
            .widgetURL(URL(string: "pldev://section/practice/rehearsal"))
        }
        .supplementalActivityFamilies([.small, .medium])   // iOS 27 forwards it to the Watch Smart Stack and CarPlay
    }
}
