import XCTest
@testable import PLDevCore

/// Smart capture's suggestion rules (Plans/SPEC — PL DEV SMART CAPTURE (S348)).
final class SmartCaptureTests: XCTestCase {
    func testAnImageIsArt() {
        XCTAssertEqual(SmartCapture.suggest(kind: "image", text: nil, url: nil), .art)
        XCTAssertEqual(SmartCapture.available(kind: "image", url: nil), [.art])
    }

    func testALinkToABackendSiteIsATileAndAnyOtherLinkIsTheBoard() {
        XCTAssertEqual(SmartCapture.suggest(kind: "url", text: nil, url: "https://dash.cloudflare.com/x"), .tile)
        XCTAssertEqual(SmartCapture.suggest(kind: "url", text: nil, url: "https://www.printful.com/dashboard"), .tile)
        XCTAssertEqual(SmartCapture.suggest(kind: "url", text: nil, url: "https://example.org/post"), .board)
        XCTAssertEqual(SmartCapture.available(kind: "url", url: "https://example.org/post"), [.board, .tile, .thought, .task])
        XCTAssertEqual(SmartCapture.available(kind: "url", url: "http://example.org/post"), [.board, .thought, .task], "no tile for plain http")
    }

    func testALinkWithHighlightedTextOffersQuoteAndSeedAndLeadsWithTheText() {
        XCTAssertEqual(SmartCapture.available(kind: "url", url: "https://example.org/a", hasText: true), [.board, .quote, .seed, .tile, .thought, .task])
        XCTAssertEqual(SmartCapture.suggest(kind: "url", text: "What persists in the mind becomes your reality.", url: "https://example.org/a"), .seed)
        XCTAssertEqual(SmartCapture.suggest(kind: "url", text: nil, url: "https://dash.cloudflare.com/"), .tile)
        XCTAssertEqual(SmartCapture.suggest(kind: "url", text: "   ", url: "https://example.org/a"), .board)
    }

    func testAShortAttributedLineIsAQuote() {
        XCTAssertEqual(SmartCapture.suggest(kind: "text", text: "\u{201C}Do not go gentle into that good night.\u{201D} \u{2014} Dylan Thomas", url: nil), .quote)
        XCTAssertEqual(SmartCapture.suggest(kind: "text", text: "The mind that opens to a new idea never returns to its original size. ~ Oliver Holmes", url: nil), .quote)
    }

    func testTextCanAlwaysBeRoutedToThoughtOrTask() {
        XCTAssertEqual(SmartCapture.available(kind: "text", url: nil), [.board, .quote, .seed, .thought, .task])
        XCTAssertEqual(CaptureRoute(rawValue: "thought"), .thought)
        XCTAssertEqual(CaptureRoute(rawValue: "task"), .task)
    }

    func testAShortPlainLineIsASeed() {
        XCTAssertEqual(SmartCapture.suggest(kind: "text", text: "What persists in the mind becomes your reality.", url: nil), .seed)
    }

    func testLongOrLinkedTextGoesToTheBoard() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        XCTAssertEqual(SmartCapture.suggest(kind: "text", text: long, url: nil), .board)
        XCTAssertEqual(SmartCapture.suggest(kind: "text", text: "Look at this https://example.org/a", url: nil), .board)
        XCTAssertEqual(SmartCapture.suggest(kind: "text", text: "   ", url: nil), .board)
    }

    func testAHyphenInsideASentenceIsNotAnAttribution() {
        XCTAssertFalse(SmartCapture.hasAttribution("A well-known idea stays quiet for years."))
        XCTAssertFalse(SmartCapture.hasAttribution("Sit still - then move. It works."))
    }

    func testSeedTextIsTagged() {
        XCTAssertEqual(SmartCapture.seedText("  A line.  "), "SEED: A line.")
    }
}
