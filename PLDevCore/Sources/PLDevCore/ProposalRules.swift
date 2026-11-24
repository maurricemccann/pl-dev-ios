import Foundation

/// The app proposes one change to its own layout (Plans/SPEC — PL DEV PROPOSES ITS OWN CHANGES (S348); his pick N19, 11-14). It reads only
/// what he did and what came of it, never time spent in the app; it changes layout and emphasis only, never a number.
public enum ProposalRules {
    public struct Input: Sendable {
        public var movesLast7: [String: Int]          // his Tonight taps this week, by room
        public var oldestWaitingCaptureDays: Int?     // the oldest capture still waiting, in days
        public var settled: Set<String>               // proposals already applied or declined
        public var thisWeek: String                   // ISO week key, "2026-W47"
        public var lastActedWeek: String?             // the week he last answered Yes / Not now / Never: one answer a week
        public init(movesLast7: [String: Int], oldestWaitingCaptureDays: Int?, settled: Set<String>, thisWeek: String = "", lastActedWeek: String? = nil) {
            self.movesLast7 = movesLast7; self.oldestWaitingCaptureDays = oldestWaitingCaptureDays; self.settled = settled
            self.thisWeek = thisWeek; self.lastActedWeek = lastActedWeek
        }
    }
    public struct Proposal: Sendable, Equatable, Codable {
        public let id: String, text: String, setting: String, value: String
    }

    /// The only layout settings a proposal may touch, and the values each may take (his ruling 11-14: "Today's order only").
    /// Nothing here can hide Pulse, the weekly review, a number or Tonight.
    public static let allowed: [String: Set<String>] = ["todayLead": ["captures", "drip"]]

    /// One thing the app changed, with the setting's value before it, so Undo restores it exactly.
    public struct Change: Sendable, Equatable, Codable, Identifiable {
        public let id: String, text: String, before: String, at: String
        public init(id: String, text: String, before: String, at: String) { self.id = id; self.text = text; self.before = before; self.at = at }
    }
    /// Undo one change: the value to put back, and the list without it. Nil when the change is not in the list.
    public static func undo(_ log: [Change], id: String) -> (restore: String, rest: [Change])? {
        guard let c = log.first(where: { $0.id == id }) else { return nil }
        return (c.before, log.filter { $0.id != id })
    }

    /// At most one proposal, the first rule that fires and is not settled; none if he already answered one this week.
    public static func pick(_ i: Input) -> Proposal? {
        if let w = i.lastActedWeek, w == i.thisWeek { return nil }
        let rules: [Proposal?] = [
            (i.oldestWaitingCaptureDays ?? 0) >= 7
                ? Proposal(id: "lead-captures", text: "A capture has waited \(i.oldestWaitingCaptureDays ?? 0) days. Put Captures first on Today, under Tonight?", setting: "todayLead", value: "captures")
                : nil,
            (i.movesLast7["approvals"] ?? 0) >= 4
                ? Proposal(id: "lead-drip", text: "Tonight sent you to Approvals \(i.movesLast7["approvals"] ?? 0) times this week. Put the drip first on Today, under Tonight?", setting: "todayLead", value: "drip")
                : nil,
        ]
        return rules.compactMap { $0 }.first { !i.settled.contains($0.id) }
    }
}
