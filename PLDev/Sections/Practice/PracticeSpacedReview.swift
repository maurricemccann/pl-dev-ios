import Foundation

/// Spaced review (council 11-17, Codex and Gemini agreeing): an item answered right comes back after 1, 3, 7, 14, then 30 days;
/// a miss moves only that item back to tomorrow. Nothing here is ever shown as debt, overdue or a count against him.
/// Stored per item as [stage, due time], beside the course record in the phone's defaults.
enum SpacedReview {
    static let days: [Double] = [1, 3, 7, 14, 30]
    private static let key = "course.review.state"
    private static var store: UserDefaults { .standard }

    static func state() -> [String: [Double]] { (store.dictionary(forKey: key) as? [String: [Double]]) ?? [:] }

    /// Record one graded answer for an item.
    static func record(_ item: String, right: Bool, now: Date = .now) {
        var s = state()
        let stage = right ? min(Int(s[item]?.first ?? -1) + 1, days.count - 1) : 0
        s[item] = [Double(stage), now.addingTimeInterval(days[stage] * 86_400).timeIntervalSince1970]
        store.set(s, forKey: key)
    }

    /// Items he has met whose time has come, the longest-waiting first.
    static func due(now: Date = .now) -> [String] {
        state().filter { $0.value.count == 2 && $0.value[1] <= now.timeIntervalSince1970 }
            .sorted { $0.value[1] < $1.value[1] }.map(\.key)
    }
}
