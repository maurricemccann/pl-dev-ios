import XCTest
@testable import PLDevCore

final class ProposalRulesTests: XCTestCase {
    func testNothingFiresOnAQuietWeek() {
        XCTAssertNil(ProposalRules.pick(.init(movesLast7: ["approvals": 2], oldestWaitingCaptureDays: 3, settled: [])))
    }

    func testAStaleCaptureComesFirstAndOnlyOneIsProposed() {
        let p = ProposalRules.pick(.init(movesLast7: ["approvals": 6], oldestWaitingCaptureDays: 9, settled: []))
        XCTAssertEqual(p?.id, "lead-captures")
        XCTAssertEqual(p?.value, "captures")
    }

    func testASettledProposalIsNeverAskedAgain() {
        let p = ProposalRules.pick(.init(movesLast7: ["approvals": 6], oldestWaitingCaptureDays: 9, settled: ["lead-captures"]))
        XCTAssertEqual(p?.id, "lead-drip")
        XCTAssertNil(ProposalRules.pick(.init(movesLast7: ["approvals": 6], oldestWaitingCaptureDays: 9, settled: ["lead-captures", "lead-drip"])))
    }

    func testOneAnswerAWeekThenTheNextWeekAsksAgain() {
        let base = ProposalRules.Input(movesLast7: [:], oldestWaitingCaptureDays: 9, settled: [], thisWeek: "2026-W47", lastActedWeek: "2026-W47")
        XCTAssertNil(ProposalRules.pick(base))
        var next = base; next.thisWeek = "2026-W48"
        XCTAssertEqual(ProposalRules.pick(next)?.id, "lead-captures")   // "Not now" settles nothing, so it returns
    }

    func testEveryProposalTouchesOnlyTodaysOrder() {
        for moves in [["approvals": 9], [:]] {
            for days in [0, 30] {
                if let p = ProposalRules.pick(.init(movesLast7: moves, oldestWaitingCaptureDays: days, settled: [])) {
                    XCTAssertTrue(ProposalRules.allowed[p.setting]?.contains(p.value) == true, "\(p.id) strays outside Today's order")
                }
            }
        }
    }

    func testUndoRestoresTheValueBeforeExactly() {
        let log = [ProposalRules.Change(id: "lead-captures", text: "t", before: "", at: "2026-11-18"),
                   ProposalRules.Change(id: "lead-drip", text: "t", before: "captures", at: "2026-11-25")]
        let r = ProposalRules.undo(log, id: "lead-drip")
        XCTAssertEqual(r?.restore, "captures")
        XCTAssertEqual(r?.rest.map(\.id), ["lead-captures"])
        XCTAssertNil(ProposalRules.undo(log, id: "nope"))
    }
}
