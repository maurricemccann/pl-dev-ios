import Foundation

/// The app proposes one change to its own layout (Plans/SPEC — PL DEV PROPOSES ITS OWN CHANGES (S348); his pick N19, 11-14). It reads only
/// what he did and what came of it, never time spent in the app; it changes layout and emphasis only, never a number.
public enum ProposalRules {
    public struct Input: Sendable {
        public var movesLast7: [String: Int]          // his Tonight taps this week, by room
        public var oldestWaitingCaptureDays: Int?     // the oldest capture still waiting, in days
        public var settled: Set<String>               // proposals already applied or declined
        public init(movesLast7: [String: Int], oldestWaitingCaptureDays: Int?, settled: Set<String>) {
            self.movesLast7 = movesLast7; self.oldestWaitingCaptureDays = oldestWaitingCaptureDays; self.settled = settled
        }
    }
    public struct Proposal: Sendable, Equatable, Codable {
        public let id: String, text: String, setting: String, value: String
    }

    /// At most one proposal, the first rule that fires and is not settled.
    public static func pick(_ i: Input) -> Proposal? {
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
