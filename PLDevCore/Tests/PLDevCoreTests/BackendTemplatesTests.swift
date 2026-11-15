import XCTest
@testable import PLDevCore

/// The Backend page's matching rules (Plans/SPEC — PL DEV BACKEND PAGE (S348), acceptance test 7).
final class BackendTemplatesTests: XCTestCase {
    func testTheStartingSetIsExactlyThree() {   // four since 11-14 (his pick N23: Pinterest); the name is kept for history
        XCTAssertEqual(BackendTemplates.builtIn.map(\.id), ["cloudflare", "printful", "pinterest", "horizon"])
        XCTAssertTrue(BackendTemplates.builtIn[0].isReady)
        XCTAssertTrue(BackendTemplates.builtIn[1].isReady)
        XCTAssertTrue(BackendTemplates.builtIn[2].isReady)
        XCTAssertFalse(BackendTemplates.builtIn[3].isReady, "Horizon waits for his first share, its address is not guessed")
    }

    func testANewBuiltInAppearsOnceAndARemovedOneStaysGone() {
        let old = Array(BackendTemplates.builtIn.filter { $0.id != "pinterest" })
        XCTAssertTrue(BackendTemplates.addingNew(old, seen: ["cloudflare", "printful", "horizon"]).contains { $0.id == "pinterest" })
        let removed = old.filter { $0.id != "printful" }
        XCTAssertFalse(BackendTemplates.addingNew(removed, seen: ["cloudflare", "printful", "horizon", "pinterest"]).contains { $0.id == "printful" })
    }

    func testMatchFindsTheBuiltInBySite() {
        XCTAssertEqual(BackendTemplates.match("https://dash.cloudflare.com/abc/workers")?.id, "cloudflare")
        XCTAssertEqual(BackendTemplates.match("https://cloudflare.com")?.id, "cloudflare")
        XCTAssertEqual(BackendTemplates.match("https://www.printful.com/dashboard/orders")?.id, "printful")
        XCTAssertNil(BackendTemplates.match("https://example.org/"))
        XCTAssertNil(BackendTemplates.match("http://www.printful.com/"), "plain http is not a tile")
    }

    func testAllowsRefusesLookAlikes() {
        let cf = BackendTemplates.builtIn[0]
        XCTAssertTrue(BackendTemplates.allows("dash.cloudflare.com", for: cf))
        XCTAssertTrue(BackendTemplates.allows("cloudflare.com", for: cf))
        XCTAssertFalse(BackendTemplates.allows("evil-cloudflare.com", for: cf))
        XCTAssertFalse(BackendTemplates.allows("cloudflare.com.evil.org", for: cf))
        XCTAssertFalse(BackendTemplates.allows("example.org", for: cf))
        XCTAssertTrue(BackendTemplates.allows("accounts.google.com", for: cf), "a Google sign-in stays in the tile")
        XCTAssertTrue(BackendTemplates.allows("accounts.youtube.com", for: cf), "Google's session hop stays in the tile")
        XCTAssertTrue(BackendTemplates.allows("www.google.com", for: cf))
        XCTAssertTrue(BackendTemplates.allows("idmsa.apple.com", for: cf))
        XCTAssertFalse(BackendTemplates.allows("evil-google.com", for: cf))
        XCTAssertFalse(BackendTemplates.allows("google.com.evil.org", for: cf))
    }

    func testCustomTilesAreNamedAndLimitedToTheirHost() {
        let t = BackendTemplates.custom(address: "https://www.example.org/console", title: "  Example Console ")
        XCTAssertEqual(t?.name, "Example Console")
        XCTAssertEqual(t?.allowedHosts, ["example.org"])
        XCTAssertEqual(t?.id, "custom-example.org")
        XCTAssertEqual(BackendTemplates.custom(address: "https://example.org", title: nil)?.name, "example.org")
        XCTAssertNil(BackendTemplates.custom(address: "http://example.org", title: "x"))
        XCTAssertNil(BackendTemplates.custom(address: "javascript:alert(1)", title: "x"))
    }

    func testAllowingAddsOneHostOnce() {
        let cf = BackendTemplates.builtIn[0]
        let more = cf.allowing("Auth.Example.org")
        XCTAssertTrue(BackendTemplates.allows("auth.example.org", for: more))
        XCTAssertFalse(BackendTemplates.allows("auth.example.org", for: cf))
        XCTAssertEqual(more.allowing("auth.example.org").allowedHosts, more.allowedHosts, "no duplicate")
        XCTAssertEqual(cf.allowing("").allowedHosts, cf.allowedHosts)
    }

    func testRefreshedBringsOldSavedTilesUpToDate() {
        var oldHorizon = BackendTemplates.builtIn.first { $0.id == "horizon" }!   // by name: its place in the list moves when a tile is added
        oldHorizon.allowedHosts = ["meta.com", "my-extra.example"]   // as saved by an earlier build
        oldHorizon.startURL = "https://www.meta.com/horizon/creators/"
        let custom = BackendTemplates.custom(address: "https://example.org/x", title: "Ex")!
        let out = BackendTemplates.refreshed([oldHorizon, custom])
        XCTAssertTrue(out[0].allowedHosts.contains("fb.com"), "the code's current list reaches an old saved tile")
        XCTAssertTrue(out[0].allowedHosts.contains("my-extra.example"), "a site he allowed is kept")
        XCTAssertEqual(out[0].startURL, "https://www.meta.com/horizon/creators/", "the address he set is kept")
        XCTAssertEqual(out[1], custom, "a tile he added is untouched")
    }

    func testTemplateForFillsHorizonFromTheSharedAddress() {
        let t = BackendTemplates.template(for: "https://www.meta.com/horizon/creators/", title: "Creators")
        XCTAssertEqual(t?.id, "horizon")
        XCTAssertEqual(t?.startURL, "https://www.meta.com/horizon/creators/")
        XCTAssertTrue(t?.isReady == true)
        XCTAssertEqual(BackendTemplates.template(for: "https://dash.cloudflare.com/", title: nil)?.startURL, "https://dash.cloudflare.com/")
        XCTAssertNil(BackendTemplates.template(for: "ftp://x", title: nil))
    }
}
