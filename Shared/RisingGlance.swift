import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Rising's last check-in for the widgets and the shift Live Activity (his pick 11-26, item 89). Band and time only.
struct RisingGlance: Codable, Equatable, Sendable {
    var band: String        // "Steady"
    var step: String        // that band's step, "Add a little"
    var level: Int          // 0 Heavy ... 6 Lit
    var at: Date
    var shiftEnds: Date     // after this the widget asks for a new check-in
}

extension PLDevKinds {
    static let risingWidget = "com.psychedluxuries.dev.rising"
}

extension RisingGlance {
    static func write(_ g: RisingGlance) {
        guard let id = SharedState.groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        store.set(data, forKey: "rising")
        WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.risingWidget)
    }

    static func read() -> RisingGlance? {
        guard let id = SharedState.groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "rising") else { return nil }
        return try? JSONDecoder().decode(RisingGlance.self, from: data)
    }
}

#if canImport(ActivityKit)
/// The shift on the Lock Screen and in the Dynamic Island: started by the first check-in of a shift, updated by each one after,
/// stale when the shift day ends (3 PM Pacific). Tapping it opens the app, where the check-in is waiting. Local only.
struct RisingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var band: String
        var step: String
        var level: Int
        var at: Date
    }
    var shiftDay: String
}
#endif
