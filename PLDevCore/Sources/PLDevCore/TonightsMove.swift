import Foundation

/// Tonight's move (his ruling 11-14, from the Codex and Gemini answers to "the screen is a practice"): the one finishable thing to do
/// tonight, picked from real numbers only. Nothing is invented: every line names a count or a lane the house reported.
public enum TonightsMove {
    public struct Lane: Sendable { public let platform: String; public let days: Double; public init(platform: String, days: Double) { self.platform = platform; self.days = days } }
    public struct Waiting: Sendable { public let label: String; public let count: Int; public let room: String; public init(label: String, count: Int, room: String) { self.label = label; self.count = count; self.room = room } }
    public struct Move: Sendable, Equatable { public let text: String; public let room: String }

    /// Priority: a lane that runs dry today, then work only his tap releases (drafts, Pins, ads), then a lane under its target, then his
    /// first open task, then reach itself.
    public static func pick(lanes: [Lane], target: Double, waiting: [Waiting], firstTask: String?, postsThisWeek: Int?) -> Move {
        let low = lanes.sorted { $0.days < $1.days }
        if let l = low.first, l.days < 1 {
            return Move(text: "Fill \(l.platform.capitalized): it runs dry today.", room: "approvals")
        }
        if let w = waiting.first(where: { $0.count > 0 && !$0.room.isEmpty && $0.room != "founder" }) {
            return Move(text: "\(w.label): \(w.count). Your tap sends them out.", room: w.room)
        }
        if let l = low.first, l.days < target {
            return Move(text: "\(l.platform.capitalized) has \(String(format: "%.1f", l.days)) days of posts left. Queue more.", room: "approvals")
        }
        if let t = firstTask, !t.isEmpty { return Move(text: t, room: "founder") }
        if postsThisWeek == 0 { return Move(text: "Nothing went out this week. Put one piece in front of people tonight.", room: "make") }
        return Move(text: "Put one piece in front of new people tonight.", room: "make")
    }
}
