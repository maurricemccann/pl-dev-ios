import Foundation
import WidgetKit

/// What the Task Town widget shows: the Roadmap's counts and where the session is. Counts and words only: no key, no address.
struct TownGlance: Codable, Equatable, Sendable {
    var open: Int
    var done: Int
    var his: Int          // tasks waiting on him
    var blocked: Int
    var stale: Int        // a week old or more
    var working: Bool
    var at: String?       // the building the session is at, in the town's own word (STUDIO, TERMINAL)
    var calls: Int?
    var updatedAt: Date
}

extension PLDevKinds {
    static let townWidget = "com.psychedluxuries.dev.town"
}

extension SharedState {
    static func writeTown(_ g: TownGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readTown()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "town")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.townWidget) }   // redraws only when a number changed, not with the clock
    }

    static func readTown() -> TownGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "town") else { return nil }
        return try? JSONDecoder().decode(TownGlance.self, from: data)
    }
}
