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
}
