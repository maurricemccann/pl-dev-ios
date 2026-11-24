import XCTest
@testable import PLDevCore

/// A saved GlyphBot sitting resumes only when it is recent: under 12 hours old and on the same calendar day.
final class SittingFreshnessTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }

    func testAnHourOldSameDayIsFresh() {
        XCTAssertTrue(SittingFreshness.isFresh(savedAt: at(24, 15), now: at(24, 16), calendar: cal))
    }

    func testAMonthOldIsNot() {
        XCTAssertFalse(SittingFreshness.isFresh(savedAt: at(24, 15).addingTimeInterval(-30 * 86_400), now: at(24, 15), calendar: cal))
    }

    func testNoTimeIsNotFresh() {
        XCTAssertFalse(SittingFreshness.isFresh(savedAt: nil, now: at(24, 15), calendar: cal))
    }

    func testANewCalendarDayIsNotFreshEvenUnderTwelveHours() {
        XCTAssertFalse(SittingFreshness.isFresh(savedAt: at(24, 23, 30), now: at(25, 1), calendar: cal))
    }

    func testOverTwelveHoursSameDayIsNot() {
        XCTAssertFalse(SittingFreshness.isFresh(savedAt: at(24, 0, 10), now: at(24, 12, 20), calendar: cal))
        XCTAssertTrue(SittingFreshness.isFresh(savedAt: at(24, 0, 10), now: at(24, 12, 0), calendar: cal))
    }

    func testAClockSetBackIsNotFresh() {
        XCTAssertFalse(SittingFreshness.isFresh(savedAt: at(24, 16), now: at(24, 15), calendar: cal))
    }
}
