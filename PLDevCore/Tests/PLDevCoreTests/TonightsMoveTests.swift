import XCTest
@testable import PLDevCore

final class TonightsMoveTests: XCTestCase {
    func testADryLaneComesFirst() {
        let m = TonightsMove.pick(lanes: [.init(platform: "threads", days: 0.4), .init(platform: "bluesky", days: 9)], target: 14,
                                  waiting: [.init(label: "Drafts to approve", count: 36, room: "approvals")], firstTask: "Close an account", postsThisWeek: 3)
        XCTAssertEqual(m, .init(text: "Fill Threads: it runs dry today.", room: "approvals"))
    }

    func testTapReleasedWorkBeatsALowLaneAndSkipsFounderTasks() {
        let m = TonightsMove.pick(lanes: [.init(platform: "bluesky", days: 5)], target: 14,
                                  waiting: [.init(label: "Founder tasks open", count: 2, room: "founder"), .init(label: "Pins waiting for your tap", count: 6, room: "pinterest")],
                                  firstTask: nil, postsThisWeek: 1)
        XCTAssertEqual(m.room, "pinterest")
        XCTAssertTrue(m.text.hasPrefix("Pins waiting for your tap: 6"))
    }

    func testFallsToTheTaskThenToReach() {
        let full = [TonightsMove.Lane(platform: "threads", days: 20)]
        XCTAssertEqual(TonightsMove.pick(lanes: full, target: 14, waiting: [], firstTask: "Test curate on the TV", postsThisWeek: 2).room, "founder")
        XCTAssertTrue(TonightsMove.pick(lanes: full, target: 14, waiting: [], firstTask: nil, postsThisWeek: 0).text.hasPrefix("Nothing went out"))
    }
}
