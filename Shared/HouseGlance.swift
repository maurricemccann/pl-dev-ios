import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// What the House widget and the shift Live Activity show, written by the app after it reads the console.
/// Counts and words only: no key, no address.
struct HouseGlance: Codable, Equatable, Sendable {
    var drafts: Int
    var done: Int
    var total: Int
    var next: String?
    var nextTime: String?
    var updatedAt: Date
}

extension PLDevKinds {
    static let houseWidget = "com.psychedluxuries.dev.house"
}

extension SharedState {
    static func writeHouse(_ g: HouseGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readHouse()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "house")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.houseWidget) }
    }

    static func readHouse() -> HouseGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "house") else { return nil }
        return try? JSONDecoder().decode(HouseGlance.self, from: data)
    }
}

#if canImport(ActivityKit)
/// The shift on the Lock Screen and in the Dynamic Island. Started by him from House, updated as he ticks tasks,
/// ended when the shift is done. Local only (no push on this account); well under the 4 KB limit.
struct ShiftAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var task: String          // the task in front of him now
        var time: String?         // its time, as the plan writes it
        var done: Int
        var total: Int
    }
    var planDate: String
}
#endif
