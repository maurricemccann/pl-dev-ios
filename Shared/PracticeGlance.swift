import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// What the Practice widget shows, written by the app after it reads the practice. Counts and words only: no key, no address.
struct PracticeGlance: Codable, Equatable, Sendable {
    var monthDays: Int          // days practised this month (either check-in counts)
    var totalDays: Int          // days practised in all
    var weekDays: Int           // days of the last 7 with both check-ins
    var morning: Bool
    var evening: Bool
    var habitsDone: Int
    var habitsTotal: Int
    var lessonTitle: String?
    var line: String?           // an affirmation line, when the app has one for the widget
    var updatedAt: Date
}

extension PLDevKinds {
    static let practiceWidget = "com.psychedluxuries.dev.practice"
}

extension PracticeGlance {
    /// Redraws the widget only when something other than the time changed.
    static func write(_ g: PracticeGlance) {
        guard let id = SharedState.groupID, let store = UserDefaults(suiteName: id) else { return }
        var next = g
        next.line = g.line ?? read()?.line   // the line is kept until the app has a new one
        var before = read()
        before?.updatedAt = g.updatedAt
        guard let data = try? JSONEncoder().encode(next) else { return }
        store.set(data, forKey: "practice")
        if before != next { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.practiceWidget) }
    }

    static func read() -> PracticeGlance? {
        guard let id = SharedState.groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "practice") else { return nil }
        return try? JSONDecoder().decode(PracticeGlance.self, from: data)
    }
}

#if canImport(ActivityKit)
/// A rehearsal on the Lock Screen and in the Dynamic Island: two minutes, five senses. Started by his tap on Begin,
/// updated only when the sense changes, ended the moment the rehearsal ends. Local only.
struct RehearsalAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: Int          // 0 to 4
        var title: String       // "See it", "Hear it"...
    }
    var desire: String
    var started: Date
    var ends: Date
}
#endif
