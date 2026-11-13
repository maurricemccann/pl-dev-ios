import ActivityKit
import SwiftUI
import WidgetKit

/// A render on the Lock Screen and in the Dynamic Island, from start to filed.
struct RenderLiveActivity: Widget {
    private static let lanes = ["sent", "rendering", "mixing", "filed"]

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RenderAttributes.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: ctx.state.lane == "failed" ? "xmark.octagon.fill" : ctx.state.lane == "filed" ? "checkmark.seal.fill" : "film.stack")
                    .font(.title2).foregroundStyle(ctx.state.lane == "failed" ? Color.red : HouseTint.key)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.attributes.shot).font(.headline.weight(.semibold)).lineLimit(1)
                    Text("\(ctx.state.lane.capitalized)\(ctx.state.progress.map { " · \($0)" } ?? "")").font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: Double((Self.lanes.firstIndex(of: ctx.state.lane) ?? 0) + 1), total: Double(Self.lanes.count)).tint(HouseTint.key)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.35))
            .widgetURL(URL(string: "pldev://section/composer"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(ctx.state.lane.capitalized, systemImage: "film.stack").font(.headline.weight(.semibold)).foregroundStyle(HouseTint.key) }
                DynamicIslandExpandedRegion(.trailing) { if let p = ctx.state.progress { Text(p).font(.headline.weight(.medium)).monospacedDigit() } }
                DynamicIslandExpandedRegion(.bottom) { Text(ctx.attributes.shot).font(.headline.weight(.semibold)).lineLimit(1) }
            } compactLeading: {
                Image(systemName: "film.stack").foregroundStyle(HouseTint.key)
            } compactTrailing: {
                Text(ctx.state.progress ?? ctx.state.lane.prefix(4).capitalized).font(.caption.weight(.semibold)).monospacedDigit()
            } minimal: {
                Image(systemName: "film.stack").foregroundStyle(HouseTint.key)
            }
            .widgetURL(URL(string: "pldev://section/composer"))
        }
    }
}
