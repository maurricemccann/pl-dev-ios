import XCTest

// Drives Composer on the iPhone simulator, flow by flow, and screenshots every step into $PL_SHOTS_DIR (numbered, so the order reads).
// The app is already installed; the workflow gives it a config with public addresses and dummy key names (never his config) and seeds the
// simulator's Photos with generated pictures and a clip (never his media). Tests run in name order and share the app's saved state:
// the piece built in test 1 is the one the later tests attach to, preview, spec and send.

final class ComposerFlowsTests: XCTestCase {
    static var counter = 0
    let bundle = "com.psychedluxuries.dev"
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        // A system alert (notifications) must never sit between a tap and its target.
        addUIInterruptionMonitor(withDescription: "system alerts") { alert in
            for name in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow", "Not Now"] where alert.buttons[name].exists { alert.buttons[name].tap(); return true }
            return false
        }
    }

    // MARK: helpers

    func launch(_ link: String = "section/composer/piece") {
        app = XCUIApplication(bundleIdentifier: bundle)
        let cfg = ProcessInfo.processInfo.environment["PL_SIM_CONFIG"] ?? ""
        app.launchArguments = ["-simConfig", cfg, "-simLink", "pldev://" + link]
        app.launch()
        sleep(6)
        app.tap()   // lets the interruption monitor see an alert, if one is up
    }

    func shot(_ name: String) {
        Self.counter += 1
        let file = String(format: "%02d-", Self.counter) + name
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = file; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["PL_SHOTS_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file + ".png"))
        }
    }

    /// The accessibility tree, for the step that did not find its target.
    func tree(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["PL_SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? app.debugDescription.write(toFile: dir + "/tree-" + name + ".txt", atomically: true, encoding: .utf8)
    }

    func any(_ label: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: label).firstMatch }
    func has(_ pred: String, in q: XCUIElementQuery? = nil) -> XCUIElementQuery { (q ?? app.buttons).matching(NSPredicate(format: pred)) }

    @discardableResult func tap(_ e: XCUIElement, _ what: String, wait: Double = 8) -> Bool {
        guard e.waitForExistence(timeout: wait) else { XCTFail("not found: \(what)"); tree("missing-" + what.replacingOccurrences(of: " ", with: "-")); return false }
        e.tap(); return true
    }

    func clear(_ f: XCUIElement) {
        guard let v = f.value as? String, !v.isEmpty else { return }
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()   // the caret goes to the end, so the deletes take everything
        f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
    }

    func type(_ f: XCUIElement, _ text: String, _ what: String) {
        guard f.waitForExistence(timeout: 8) else { XCTFail("no field: \(what)"); tree("nofield-" + what.replacingOccurrences(of: " ", with: "-")); return }
        f.tap(); clear(f); f.typeText(text)
        if app.keyboards.buttons["Return"].exists { app.keyboards.buttons["Return"].tap() } else if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
    }

    func area(_ name: String) {
        let seg = app.segmentedControls["composer.area"].exists ? app.segmentedControls["composer.area"] : app.segmentedControls.firstMatch
        tap(seg.buttons[name], "area " + name)
        sleep(1)
    }

    // MARK: 1. build a piece

    func test1_BuildPiece() {
        launch()
        shot("composer-opens")
        XCTAssertTrue(app.textFields["Piece name"].waitForExistence(timeout: 15), "the Piece room did not open")
        type(app.textFields["Piece name"], "e2e-piece", "piece name")
        XCTAssertEqual(app.textFields["Piece name"].value as? String, "e2e-piece")
        shot("piece-named")

        // add three shots
        for n in 1...3 {
            tap(app.buttons["composer.addshot"], "add shot \(n)")
            sleep(1)
        }
        shot("three-shots")

        // titles
        let names = ["entry", "the curve", "the fill"]
        for (i, t) in names.enumerated() { type(app.textFields["Title of shot \(i + 1)"], t, "title \(i + 1)") }
        shot("titles")
        XCTAssertEqual(app.textFields["Title of shot 2"].value as? String, "the curve")

        // duration: raise shot 1 by two steps of 0.5 s
        for _ in 0..<8 where !app.steppers["Duration"].firstMatch.isHittable { app.swipeUp() }
        let step = app.steppers["Duration"].firstMatch
        if tap(step.buttons["Increment"], "duration increment") { step.buttons["Increment"].tap(); step.buttons["Increment"].tap() }
        shot("duration-raised")
        for _ in 0..<8 { app.swipeDown() }

        // how shot 2 enters
        let enter = has("label CONTAINS 'inherit'")
        if tap(enter.element(boundBy: 0), "transition menu (shot 2)") {
            tap(has("label BEGINSWITH 'dissolve'").firstMatch, "transition dissolve")
        }
        sleep(1)
        shot("transition-dissolve")

        // fps and resolution
        if tap(has("label CONTAINS 'fps'").firstMatch, "fps menu") { tap(app.buttons["60"].firstMatch, "fps 60") }
        if tap(has("label CONTAINS 'resolution'").firstMatch, "resolution menu") { tap(app.buttons["1080x1080"].firstMatch, "resolution 1080x1080") }
        shot("fps-and-resolution")

        // reorder: pull shot 3 above shot 1
        if tap(app.buttons["Reorder"], "reorder") {
            sleep(1)
            shot("reorder-mode")
            let h1 = has("label BEGINSWITH 'Reorder Shot 1'").firstMatch
            let h3 = has("label BEGINSWITH 'Reorder Shot 3'").firstMatch
            if h1.waitForExistence(timeout: 5), h3.waitForExistence(timeout: 5) {
                h3.press(forDuration: 0.6, thenDragTo: h1)
                sleep(1)
            } else { tree("reorder"); XCTFail("no reorder handles") }
            shot("reordered")
            tap(app.buttons["Done"], "reorder done")
            XCTAssertEqual(app.textFields["Title of shot 1"].value as? String, "the fill", "shot 3 did not move to the top")
        }

        // delete shot 2 (swipe right, then confirm)
        let n2 = app.staticTexts["02"].firstMatch
        if n2.waitForExistence(timeout: 5) {
            n2.swipeRight()
            if tap(app.buttons["Delete"].firstMatch, "swipe delete") { tap(app.buttons["Delete shot"], "confirm delete") }
        }
        sleep(1)
        shot("one-deleted")
        XCTAssertFalse(app.textFields["Title of shot 3"].exists, "the deleted shot is still there")
        // keep two shots for the rest: add one back
        tap(app.buttons["composer.addshot"], "add shot back")
        type(app.textFields["Title of shot 3"], "last", "title 3")
        shot("piece-ready")
    }

    // MARK: 2. pictures and a clip from Photos

    func test2_PhotosPicker() {
        launch()
        let pick = app.buttons["composer.shot.photos"].firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 15), "no Add from Photos button")
        pick.tap()
        sleep(4)
        shot("photos-picker")
        tree("picker")
        // the picker runs out of process; its pictures show up as images
        let imgs = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo' OR label BEGINSWITH 'Video' OR label BEGINSWITH 'Live'"))
        XCTAssertTrue(imgs.firstMatch.waitForExistence(timeout: 40), "the picker shows no photos")
        for _ in 0..<20 where imgs.count < 4 { sleep(2) }   // the library fills in after the first cell
        shot("photos-loaded")
        tree("picker-loaded")
        let total = imgs.count
        XCTAssertGreaterThanOrEqual(total, 2, "the seeded media is not in the library")
        for i in 0..<min(total, 4) { imgs.element(boundBy: i).tap() }
        shot("photos-selected")
        // the picker's confirm is a check mark at the top right; its label has varied, so try the names, then the spot
        let confirm = ["Add", "Done", "Select"].map { app.buttons[$0] }.first { $0.exists }
        if let c = confirm { c.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap() }
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Added'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 30), "the picks were not copied in")
        sleep(1)
        shot("photos-attached")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'photo-'")).firstMatch.exists, "no picture is named on the shot")
        // trim the clip
        let trimBtn = has("label BEGINSWITH 'Trim clip'").firstMatch
        if trimBtn.waitForExistence(timeout: 5) {
            trimBtn.tap()
            sleep(1)
            shot("trim-open")
            app.sliders["In point"].adjust(toNormalizedSliderPosition: 0.25)
            app.sliders["Out point"].adjust(toNormalizedSliderPosition: 0.8)
            shot("trim-set")
            tap(app.buttons["Use this trim"], "use trim")
            sleep(1)
            shot("trim-saved")
        } else { tree("clip"); XCTFail("no clip came in to trim") }
    }

    // MARK: 3. the laptop's index, 4. the Curve Library

    func test3_IndexLibrary() {
        launch()
        area("Library")
        let row = has("label CONTAINS ', Media,'")
        XCTAssertTrue(row.firstMatch.waitForExistence(timeout: 45), "the index did not load")
        shot("index-loaded")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) { search.tap(); search.typeText("curve"); sleep(1); shot("index-filtered") }
        if row.firstMatch.waitForExistence(timeout: 10) { row.firstMatch.tap() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Attached'")).firstMatch.waitForExistence(timeout: 8), "tapping an asset did not attach it")
        shot("index-attached")
    }

    func test4_CurveLibrary() {
        launch()
        area("Library")
        let src = app.segmentedControls["composer.library.source"]
        tap(src.buttons["Curve Library"], "source Curve Library")
        let still = has("label CONTAINS ', still'")
        XCTAssertTrue(has("label CONTAINS ', code-piece'").firstMatch.waitForExistence(timeout: 60), "the Curve Library did not load")
        shot("curve-loaded")
        tap(has("label BEGINSWITH 'clips'").firstMatch, "clips chip")
        sleep(2)
        shot("curve-clips")
        tap(has("label BEGINSWITH 'stills'").firstMatch, "stills chip")
        sleep(2)
        if still.firstMatch.waitForExistence(timeout: 10) { still.firstMatch.tap() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Attached'")).firstMatch.waitForExistence(timeout: 20), "the library piece was not attached")
        shot("curve-attached")
        tap(src.buttons["Photos"], "source Photos")
        sleep(1)
        shot("photos-pane")
        area("Piece")
        sleep(1)
        shot("piece-with-sources")
    }

    // MARK: 5. the spec, 6. the preview

    func test5_Spec() {
        launch()
        tap(app.buttons["Build spec"], "build spec")
        if app.buttons["Build it anyway"].waitForExistence(timeout: 3) { app.buttons["Build it anyway"].tap() }
        let first = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '## Shot 01'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "the spec did not open")
        shot("spec")
        let txt = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'sources:'")).firstMatch
        XCTAssertTrue(txt.exists, "the spec lists no sources")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'trim '")).firstMatch.exists, "the clip's trim is not in the spec")
        tap(app.navigationBars["The spec"].buttons["Close"], "close spec")
    }

    func test6_Preview() {
        launch()
        tap(app.buttons["composer.preview"], "preview")
        let stage = app.otherElements["composer.preview.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 8) || any("composer.preview.play").exists, "the preview did not open")
        shot("preview-start")
        let before = app.staticTexts["composer.preview.time"].label
        tap(app.buttons["composer.preview.play"], "play")
        sleep(2)
        shot("preview-playing")
        let after = app.staticTexts["composer.preview.time"].label
        XCTAssertNotEqual(before, after, "the timeline did not move while playing")
        tap(app.buttons["composer.preview.play"], "pause")
        let slider = app.sliders["composer.preview.scrub"]
        for p in [0.35, 0.7, 0.95] {
            slider.adjust(toNormalizedSliderPosition: p)
            sleep(1)
            shot("preview-at-\(Int(p * 100))")
        }
        tap(app.buttons["Done"], "close preview")
    }

    // MARK: 7. the graph, then send to render and watch the board

    func test7_GraphSendBoard() {
        launch()
        // open the first shot's graph
        let graph = app.buttons["composer.shot.graph"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 15), "no Graph button on the shot")
        graph.tap()
        sleep(3)
        shot("graph-open")
        // add a tracer render and the card node
        tap(app.buttons["Add node"], "add node menu")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tracer Render'")).firstMatch, "add tracer render")
        sleep(1)
        tap(app.buttons["Add node"], "add node menu 2")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'File to /curate'")).firstMatch, "add file to curate")
        sleep(1)
        shot("graph-two-nodes")
        // a tracer job from the index
        tap(app.buttons["Add node"], "add node menu 3")
        tap(app.buttons["Add a source from the library"], "add source")
        let path = has("label BEGINSWITH 'path'").firstMatch
        if tap(path, "path chip") {
            sleep(2)
            let row = has("label CONTAINS ', Path,'").firstMatch
            if tap(row, "a path asset") { sleep(1) }
        }
        shot("graph-path-attached")
        tap(app.buttons["Done"], "close the source sheet")
        sleep(1)
        // drag the tracer node across the canvas (a stroke), then select it
        let node = any("Tracer Render, Tracer Render")
        if node.waitForExistence(timeout: 5) {
            let from = node.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            shot("graph-node-dragged")
            node.tap()
            sleep(1)
            shot("graph-node-selected")
        } else { tree("graph"); XCTFail("the tracer node is not on the canvas") }
        // wire the path into the tracer, and the tracer into the card, through the inspector's menus
        let pathInput = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Not wired'")).firstMatch
        if tap(pathInput, "tracer path input") {
            tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'PL-'")).firstMatch, "the path source in the menu")
        }
        sleep(1)
        shot("graph-path-wired")
        let card = any("File to /curate, File to /curate")
        if tap(card, "file to curate node") {
            sleep(1)
            if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Not wired'")).firstMatch, "card media input") {
                tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tracer Render'")).firstMatch, "the tracer in the menu")
            }
        }
        sleep(1)
        shot("graph-card-wired")
        tree("graph-end")
        // back to the piece, then send this shot to the house
        tap(app.navigationBars.buttons["BackButton"].firstMatch, "back from the graph")
        sleep(2)
        shot("piece-after-graph")
        if tap(app.buttons["Shot actions"].firstMatch, "shot actions") {
            tap(app.buttons["Send to render"].firstMatch, "send to render")
            if tap(app.buttons["Send to render"].firstMatch, "confirm send") { sleep(5) }
        }
        shot("sent")
        // with no key the door refuses and the card waits on the phone; with the key it lands on the board. Either way the line says which.
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Waiting for the house' OR label BEGINSWITH 'Sent' OR label BEGINSWITH 'Not sent'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 20) || app.buttons["Board"].exists, "send gave no answer")
        area("Board")
        sleep(5)
        shot("board")
        tree("board")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Waiting for the house' OR label CONTAINS 'Filed' OR label CONTAINS 'filed'")).firstMatch.waitForExistence(timeout: 15), "the board shows neither the waiting card nor the house's cards")
    }
}
