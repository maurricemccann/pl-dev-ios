import Foundation
import WidgetKit

/// The Daily Mark for the widget: strokes today, days marked this month, works synced. Counts only.
struct PaintGlance: Codable, Equatable, Sendable {
    var today: Int
    var monthDays: Int
    var works: Int
    var updatedAt: Date
}

extension PLDevKinds {
    static let paintWidget = "com.psychedluxuries.dev.paint"
}

extension SharedState {
    static func writePaint(_ g: PaintGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readPaint()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "paint")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.paintWidget) }
    }

    static func readPaint() -> PaintGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "paint") else { return nil }
        return try? JSONDecoder().decode(PaintGlance.self, from: data)
    }
}
