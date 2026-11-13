import SwiftUI
import WidgetKit

struct CaptureEntry: TimelineEntry { let date: Date; let glance: CaptureGlance? }

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: .now, glance: CaptureGlance(drafts: 12, pins: 3, tasks: 2, shiftOpen: 4, captures: 1, queued: 0, lastLabel: "A line worth keeping", updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now, glance: SharedState.readCapture() ?? placeholder(in: context).glance))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now, glance: SharedState.readCapture())], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct CaptureWidgetView: View {
    let entry: CaptureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = entry.glance {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "square.and.arrow.down")
                    Text("\(g.owed)").font(.headline)
                }.widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Waiting on you").font(.headline).widgetAccentable()
                    Text(line(g)).lineLimit(2)
                    if g.queued > 0 { Text("\(g.queued) to send").font(.caption2) }
                }
            case .systemMedium:
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Waiting on you", systemImage: "tray.and.arrow.down").font(.caption.bold()).widgetAccentable()
                        Text("\(g.owed)").font(.system(size: 44, weight: .regular, design: .monospaced)).minimumScaleFactor(0.6)
                        if g.queued > 0 { Text("\(g.queued) to send from this phone").font(.caption2).foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        row("Drafts", g.drafts); row("Pins", g.pins); row("Tasks", g.tasks); row("Shift", g.shiftOpen)
                        Spacer(minLength: 2)
                        HStack(spacing: 6) {
                            quick("Text", "text.alignleft", "text")
                            quick("Quote", "quote.opening", "quote")
                            quick("Link", "link", "link")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Waiting", systemImage: "tray.and.arrow.down").font(.caption.bold()).widgetAccentable()
                    Text("\(g.owed)").font(.system(size: 40, weight: .regular, design: .monospaced))
                    Text(g.owed == 0 ? "Nothing on you." : line(g)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    if g.queued > 0 { Text("\(g.queued) to send").font(.caption2) }
                }
            }
        } else {
            VStack(alignment: .leading) {
                Label("Capture", systemImage: "tray.and.arrow.down").font(.headline)
                Text("Open Capture once to fill this.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func line(_ g: CaptureGlance) -> String {
        let parts: [(Int, String)] = [(g.drafts, "drafts"), (g.pins, "Pins"), (g.tasks, "tasks"), (g.shiftOpen, "shift"), (g.captures, "captures")]
        let shown = parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return shown.isEmpty ? "Nothing waiting on you" : shown.joined(separator: " · ")
    }

    private func row(_ label: String, _ n: Int) -> some View {
        HStack { Text(label).font(.caption); Spacer(); Text("\(n)").font(.system(.caption, design: .monospaced)) }
    }

    private func quick(_ title: String, _ symbol: String, _ mode: String) -> some View {
        Link(destination: URL(string: "pldev://section/capture/add?mode=\(mode)")!) {
            Label(title, systemImage: symbol).font(.caption2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 28)
                .background(.fill.tertiary, in: Capsule())
        }
    }
}

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLDevKinds.captureWidget, provider: CaptureProvider()) { e in
            CaptureWidgetView(entry: e).widgetURL(URL(string: "pldev://section/capture/waiting")).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Waiting on you")
        .description("What waits on you across the house, and a way to capture a text, a quote or a link.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
