import XCTest
@testable import PLDevCore

final class GenScreenTests: XCTestCase {
    private let all = GenScreen(blocks: GenPart.allCases.map { GenBlock($0, size: 9, variant: -3) }, shape: 9, motion: 9)

    func testEveryBandHoldsItsLimits() {
        for band in 0...6 {
            let s = GenRules.fit(all, band: band, hasNote: true, hasVision: true)
            XCTAssertLessThanOrEqual(s.blocks.count, band == 0 ? 3 : 6)
            XCTAssertTrue(s.blocks.contains { $0.part.acts }, "band \(band) lost its move")
            if band < 5 { XCTAssertFalse(s.blocks.contains { $0.part == .vision }) }
            if band <= 1 { XCTAssertEqual(s.motion, 0) }
            XCTAssertTrue(s.blocks.allSatisfy { (0...2).contains($0.size) && (0...2).contains($0.variant) })
        }
    }

    func testEmptyProposalStillGivesAScreenWithAMove() {
        let s = GenRules.fit(GenScreen(blocks: []), band: 4, hasNote: false, hasVision: false)
        XCTAssertGreaterThanOrEqual(s.blocks.count, 3)
        XCTAssertTrue(s.blocks.contains { $0.part.acts })
    }

    func testWrittenTextFilter() {
        let banned = ["manifest", "amazing"]
        func ok(_ t: String, _ band: Int = 4) -> Bool { GenRules.clean(t, maxWords: 18, band: band, banned: banned) != nil }
        XCTAssertTrue(ok("Make one small thing tonight."))
        XCTAssertFalse(ok("What will you make?"))
        XCTAssertFalse(ok("Go now!"))
        XCTAssertFalse(ok("Walk 10 minutes."))
        XCTAssertFalse(ok("Walk ten minutes."))
        XCTAssertFalse(ok("This is amazing."))
        XCTAssertFalse(ok("Manifest it."))
        XCTAssertFalse(ok("Luxury is yours.", 0))
        XCTAssertFalse(ok(""))
    }

    func testHeavyShowsAtMostEightWordsAndFallsBackToTheCrownedLine() {
        let crowned = "Heavy is allowed. One small thing, then rest."
        let bad = GenRules.written(heading: "Rest now", line: "Wealth is waiting.", band: 0, crowned: crowned, banned: [])
        XCTAssertNil(bad.heading)
        XCTAssertEqual(bad.line, crowned)
        let long = GenRules.written(heading: "Rest for now", line: "Sit down and let the night be quiet.", band: 0, crowned: crowned, banned: [])
        XCTAssertLessThanOrEqual(GenRules.words((long.heading ?? "") + " " + long.line).count, 8)
    }

    func testSameSeedSameScreenAndRepeatsAreReseeded() {
        let base = GenRules.fit(GenScreen(blocks: [GenBlock(.move), GenBlock(.buddy), GenBlock(.wall), GenBlock(.week)]),
                                band: 4, hasNote: false, hasVision: false)
        let seed = GenVariety.seed("2026-11-27/1/4")
        XCTAssertEqual(GenVariety.vary(base, band: 4, seed: seed), GenVariety.vary(base, band: 4, seed: seed))
        var recent: [[String]] = []
        for _ in 0..<5 {   // the model repeating itself with the same seed still gives five different screens
            let s = GenVariety.distinct(base, band: 4, seed: seed, recent: recent)
            let sig = GenVariety.signature(s)
            XCTAssertFalse(recent.contains(sig))
            XCTAssertTrue(s.blocks.contains { $0.part.acts })
            XCTAssertEqual(Set(s.blocks.map(\.part)), Set(base.blocks.map(\.part)))
            recent.append(sig)
        }
    }
}
