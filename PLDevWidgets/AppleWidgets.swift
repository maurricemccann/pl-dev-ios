import AppIntents
import SwiftUI
import WidgetKit

// The apple lane's widget: buttons that act (Button(intent:)). Small and medium on the Home Screen and in StandBy (a small
// widget is what StandBy shows), plus Lock Screen rectangular, circular and inline. A tap writes to the queue; the app sends it.

struct AppleEntry: TimelineEntry { let date: Date; let glance: AppleGlance? }

struct AppleProvider: TimelineProvider {
    func placeholder(in context: Context) -> AppleEntry {
        AppleEntry(date: .now, glance: AppleGlance(draftCount: 3, draftID: "x", draftPlatform: "instagram", draftCaption: "A draft waits for your word.", habitsLeft: 2))
    }
    func getSnapshot(in context: Context, completion: @escaping (AppleEntry) -> Void) { completion(AppleEntry(date: .now, glance: SharedState.readApple() ?? placeholder(in: context).glance)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AppleEntry>) -> Void) {
        completion(Timeline(entries: [AppleEntry(date: .now, glance: SharedState.readApple())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct AppleWidgetView: View {
    let entry: AppleEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let g = entry.glance ?? AppleGlance()
        switch family {
        case .accessoryInline:
            Text(g.draftCount > 0 ? "\(g.draftCount) drafts waiting" : (g.habitsLeft > 0 ? "\(g.habitsLeft) habits left" : "Nothing waiting"))
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: g.draftCount > 0 ? "tray.full" : "checkmark.circle")
                Text("\(g.draftCount)").font(.headline).monospacedDigit()
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(g.draftCount > 0 ? "\(g.draftCount) drafts waiting" : "No drafts waiting").font(.headline).widgetAccentable()
                if let c = g.draftCaption { Text(c).font(.caption2).lineLimit(2) }
                else if let h = g.habitLabel { Text("Next habit: \(h)").font(.caption2).lineLimit(2) }
                else { Text("Up to date").font(.caption2) }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                draftBlock(g).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    curateBlock(g)
                    habitBlock(g)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            draftBlock(g)   // also StandBy: a small widget is what the night clock shows
        }
    }

    private func queuedNote(_ g: AppleGlance) -> some View {
        Group {
            if g.queued > 0 { Text("\(g.queued) sending when PL DEV next refreshes").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2) }
        }
    }

    @ViewBuilder private func draftBlock(_ g: AppleGlance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(g.draftCount > 0 ? "\(g.draftCount) drafts" : "Drafts", systemImage: "tray.full").font(.caption.bold()).widgetAccentable()
            if let id = g.draftID, let c = g.draftCaption {
                Text(c).font(.caption).lineLimit(3)
                HStack(spacing: 8) {
                    Button(intent: HoldDraftIntent(draft: id)) { Image(systemName: "pause.fill") }
                        .accessibilityLabel("Hold this draft")
                    Button(intent: ApproveDraftIntent(draft: id)) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Approve this draft")
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Text(g.draftCount > 0 ? "Open House to see them." : "Nothing waits for your word.").font(.caption).foregroundStyle(.secondary)
            }
            queuedNote(g)
        }
    }

    @ViewBuilder private func curateBlock(_ g: AppleGlance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Curate", systemImage: "rectangle.stack").font(.caption.bold()).widgetAccentable()
            if let id = g.curateID {
                Text(g.curateLabel ?? "Top card").font(.caption2).lineLimit(2)
                HStack(spacing: 8) {
                    Button(intent: MarkCurateCardIntent(card: id, verdict: "cut")) { Image(systemName: "xmark") }
                        .accessibilityLabel("Cut this card")
                    Button(intent: MarkCurateCardIntent(card: id, verdict: "keep")) { Image(systemName: "heart") }
                        .accessibilityLabel("Keep this card")
                }
                .buttonStyle(.bordered).controlSize(.mini)
            } else {
                Text("Open Curate once.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func habitBlock(_ g: AppleGlance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Practice", systemImage: "sun.horizon").font(.caption.bold()).widgetAccentable()
            if let id = g.habitID, let h = g.habitLabel {
                Text(h).font(.caption2).lineLimit(2)
                Button(intent: TickHabitIntent(habit: id)) { Label("Tick", systemImage: "checkmark.circle") }
                    .buttonStyle(.bordered).controlSize(.mini)
            } else {
                Text(g.habitsLeft == 0 ? "Every habit is ticked." : "Open Practice once.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct AppleActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.appleWidget, provider: AppleProvider()) { e in
            AppleWidgetView(entry: e).widgetURL(URL(string: "pldev://section/house/approvals")).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Act from here")
        .description("Approve or hold the draft on top, keep or cut the top Curate card, tick the next habit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
