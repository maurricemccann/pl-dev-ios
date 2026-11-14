import XCTest

/// The notes4 lane's proof (his notes from build 152, 11-14), driven on the iPhone simulator and photographed step by step into SHOTS:
/// the tinted PC and house tiles, the approve line that opens the approvals list, GlyphGuy inside his frame, theme packs carried through
/// the sections, Mindful minutes with the exact result, and the push and pop with no white behind them, in Light and Dark.
/// Public addresses and dummy key names only: the workflow writes the config; nothing private is read. `-simDemo` gives the Today page
/// fixed numbers (one of each level); `-simNoHealthKit` acts out a build signed on a free Apple account.
final class Notes4FlowsTests: XCTestCase {
    private var app: XCUIApplication!
    private static var counter = 0
    private let cfg = ProcessInfo.processInfo.environment["SIMCFG"] ?? ""

    override func setUp() { continueAfterFailure = true }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .dark
    }

    // MARK: helpers

    private func launch(_ extra: [String] = [], link: String? = nil, page: Int? = nil) {
        app = XCUIApplication(bundleIdentifier: "com.psychedluxuries.dev")
        app.terminate()
        var args = ["-simConfig", cfg] + extra
        if let link { args += ["-simLink", "pldev://" + link] }
        if let page { args += ["-simHomePage", "\(page)"] }
        app.launchArguments = args
        app.launch()
    }

    private func shot(_ name: String) {
        Self.counter += 1
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%03d-%@.png", Self.counter, name)))
        }
    }

    private func el(_ label: String) -> XCUIElement { app.descendants(matching: .any)[label].firstMatch }
    private func like(_ part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    private func wait(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
    private func scrollTo(_ e: XCUIElement, tries: Int = 10) {
        var n = 0
        while !e.isHittable && n < tries { app.swipeUp(); n += 1 }
    }
    private func appearance(_ a: XCUIDevice.Appearance) { XCUIDevice.shared.appearance = a; wait(1) }

    // MARK: 1 and 2 · the tiles tinted by what they mean (his note on the PC tiles)

    func test01_TodayTints() {
        // (pool is 3.4 GB in the demo: amber, so the approve line, not the reboot line, heads the page)
        for (name, ap) in [("dark", XCUIDevice.Appearance.dark), ("light", .light)] {
            appearance(ap)
            launch(["-simDemo", "YES"], page: 0)
            XCTAssertTrue(like("to approve").waitForExistence(timeout: 40), "the approve line shows")
            wait(4)
            shot("today-\(name)")
            app.swipeUp(); wait(1)
            shot("today-\(name)-scrolled")
        }
    }

    // MARK: 3 · the approve line opens the approvals list

    func test02_ApproveLineOpensApprovals() {
        appearance(.dark)
        launch(["-simDemo", "YES"], page: 0)
        let line = like("230 to approve")
        XCTAssertTrue(line.waitForExistence(timeout: 40), "the line says 230 to approve")
        shot("approve-line-before")
        line.tap()
        let opened = el("Approvals")
        XCTAssertTrue(opened.waitForExistence(timeout: 40), "the approvals list opens, not the House front")
        wait(5)
        shot("approve-line-after")
    }

    // MARK: 4 · GlyphGuy inside his frame, portrait and landscape

    func test03_GlyphFits() {
        appearance(.dark)
        launch(link: "section/glyphbot")
        wait(14)
        shot("glyph-stage-portrait")
        let see = el("See GlyphGuy")
        if see.waitForExistence(timeout: 20) {
            see.tap(); wait(10)
            shot("glyph-room-portrait")
            XCUIDevice.shared.orientation = .landscapeLeft; wait(4)
            shot("glyph-room-landscape")
            XCUIDevice.shared.orientation = .portrait; wait(2)
        } else { XCTFail("the GlyphGuy room link is not there") }
    }

    // MARK: 5 · a pack carried through the sections (a dark palette and a light one, in both appearances)

    func test04_PacksCarry() throws {
        if FileManager.default.fileExists(atPath: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("skip-packs").path) { throw XCTSkip("packs already photographed") }
        let links = ["section/house", "section/library", "section/composer", "section/shop"]
        for (pack, face) in [("void-ember", "v2"), ("bone-oxblood", "ledger")] {
            for (apName, ap) in [("dark", XCUIDevice.Appearance.dark), ("light", .light)] {
                appearance(ap)
                for l in links {
                    launch(["-pldev.palette", pack, "-pldev.titleFace", face], link: l)
                    wait(16)
                    shot("pack-\(pack)-\(apName)-\(l.replacingOccurrences(of: "/", with: "-"))")
                }
            }
        }
        // the default look, untouched, for the same sections (the claim: with no pack, nothing changes)
        for ap in [("dark", XCUIDevice.Appearance.dark), ("light", .light)] {
            appearance(ap.1)
            for l in ["section/house", "section/library", "section/practice", "section/composer", "section/shop"] {
                launch(link: l); wait(16)
                shot("default-\(ap.0)-\(l.replacingOccurrences(of: "/", with: "-"))")
            }
        }
    }

    // MARK: 6 · Mindful minutes: the exact result and the test button (a free-account build)

    func test05_HealthResult() {
        appearance(.dark)
        launch(["-simNoHealthKit", "YES"], link: "settings")
        let test = app.buttons.matching(NSPredicate(format: "label CONTAINS 'minute test'")).firstMatch
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 40), "settings opened")
        var n = 0
        while !test.exists && n < 14 { app.swipeUp(); n += 1 }
        XCTAssertTrue(test.exists, "the test button is under the switch")
        shot("health-before")
        test.tap(); wait(3)
        shot("health-after-test")
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'Mindful'")).firstMatch
        if toggle.exists { toggle.tap(); wait(3); shot("health-after-switch") }
    }

    // MARK: 7 · the push and the pop with nothing white behind them

    /// Holds a screen half-way through the interactive pop (the finger down at the left edge, dragged half across) and photographs it:
    /// whatever shows behind the sliding page is what the old build flashed white.
    private func halfPop(_ name: String) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.6) { [self] in
            let s = XCUIScreen.main.screenshot()
            let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
            if let dir = ProcessInfo.processInfo.environment["SHOTS"], !dir.isEmpty {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("flash-" + name + ".png"))
            }
        }
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 3)
    }

    func test06_NoWhiteFlash() {
        for (name, ap, extra) in [("light-default", XCUIDevice.Appearance.light, [String]()), ("dark-default", .dark, [String]()),
                                  ("light-pack", .light, ["-pldev.palette", "void-ember"]), ("light-bone", .light, ["-pldev.palette", "bone-oxblood"])] {
            appearance(ap)
            launch(extra, page: 1)
            wait(10)
            let tile = app.buttons["Library"].firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 30), "the Library tile is on the apps page")
            tile.tap(); wait(7)
            halfPop(name + "-library")
            wait(2)
        }
    }

    // MARK: 8 · Settings: the sign-in page is pushed and works

    func test07_SettingsSignIn() {
        appearance(.dark)
        launch(link: "settings")
        let sign = el("Sign in")
        XCTAssertTrue(sign.waitForExistence(timeout: 40), "the Accounts row has Sign in")
        scrollTo(sign)
        shot("settings-accounts")
        sign.tap(); wait(2)
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10), "the sign-in page stays open with its fields")
        wait(2)
        shot("settings-sign-in-page")
    }
}
