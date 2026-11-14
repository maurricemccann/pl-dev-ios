import XCTest

/// PL Paint, driven end to end on the iPhone simulator: the Gallery, a new canvas, drawing, every sheet, the exports, the Gallery's own actions and a photo
/// picked from the simulator's Photos library. Every step is photographed into the folder named by SHOTS (and attached to the result bundle).
/// Public addresses and dummy key names only: the workflow writes the config; nothing private is ever read.
final class PaintFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private static var counter = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "com.psychedluxuries.dev")
        app.terminate()
        app.launchArguments = ["-simConfig", ProcessInfo.processInfo.environment["SIMCFG"] ?? "", "-simLink", "pldev://section/paint"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Gallery"].waitForExistence(timeout: 60), "the Gallery is the first screen")
    }

    // MARK: helpers

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
    private func tap(_ label: String, wait: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(label)
        XCTAssertTrue(e.waitForExistence(timeout: wait), "\(label) is on screen", file: file, line: line)
        if e.exists { e.tap() }
    }
    private func tapButton(_ label: String, wait: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let e = app.buttons[label].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: wait), "\(label) is on screen", file: file, line: line)
        if e.exists { e.tap() }
    }
    /// The ••• opens Actions (a sheet in tabs, 11-14); pick the tab, then the row.
    private func actions(_ tab: String) {
        tapButton("Actions"); sleepFor(1)
        // the selected segment is not reported as a button, so a tab already showing is fine as it is
        let seg = app.buttons[tab].firstMatch
        if seg.waitForExistence(timeout: 4) { seg.tap() }
        sleepFor(0.6)
    }
    private func works() -> XCUIElementQuery { app.buttons.matching(identifier: "gallery.work") }

    /// A new canvas from the Gallery's plus, as it comes (the default size), landing on the canvas.
    private func makeCanvas() {
        tap("gallery.new")
        XCTAssertTrue(app.navigationBars["New canvas"].waitForExistence(timeout: 10))
        tapButton("Make it")
        XCTAssertTrue(app.buttons["canvas.gallery"].waitForExistence(timeout: 20), "the canvas opens")
    }
    private func backToGallery() {
        tap("canvas.gallery")
        XCTAssertTrue(app.navigationBars["Gallery"].waitForExistence(timeout: 20))
    }
    private func ensureWork() {
        if works().count == 0 { makeCanvas(); sleepFor(1); backToGallery() }
    }
    private func sleepFor(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
    private func stroke(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: a.0, dy: a.1)), to = app.coordinate(withNormalizedOffset: CGVector(dx: b.0, dy: b.1))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.05)
    }
    private func closeSheet() {
        for l in ["Done", "Cancel", "Close"] { let b = app.buttons[l].firstMatch; if b.exists { b.tap(); return } }
        app.swipeDown(velocity: .fast)
    }

    // MARK: 01 the Gallery is first

    func test01_GalleryFirst() {
        XCTAssertTrue(el("gallery.newcard").exists, "the + New canvas card is in the grid")
        XCTAssertTrue(el("gallery.import").exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "The Daily Mark")).firstMatch.exists)
        shot("gallery-first")
    }

    // MARK: 02 the New canvas card and its sizes

    func test02_NewCanvasCard() {
        tap("gallery.new")
        XCTAssertTrue(app.navigationBars["New canvas"].waitForExistence(timeout: 10))
        shot("new-canvas-card")
        XCTAssertTrue(app.staticTexts["Sizes"].exists || app.staticTexts["SIZES"].exists)
        app.swipeUp(); shot("new-canvas-card-lower")
        app.swipeDown()
        tapButton("Cancel")
        XCTAssertTrue(app.navigationBars["Gallery"].waitForExistence(timeout: 10))
    }

    // MARK: 03 make a canvas, draw, size and opacity, undo and redo

    func test03_DrawOnACanvas() {
        makeCanvas()
        shot("canvas-empty")
        XCTAssertTrue(el("side.size").exists, "the size slider is on the side")
        XCTAssertTrue(el("side.opacity").exists, "the opacity slider is on the side")
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertFalse(undo.isEnabled, "nothing to undo yet")
        // 11-14, his note on build 152: a finger must draw with no switch touched (Procreate's rule; an iPhone has no Pencil)
        stroke((0.3, 0.3), (0.7, 0.35)); sleepFor(0.8); shot("finger-draws-by-default")
        XCTAssertTrue(undo.isEnabled, "a finger stroke drew with Finger paints untouched")
        undo.tap(); sleepFor(0.5)
        // size and opacity: drag each slider and read it back
        let size = el("side.size"), before = size.value as? String ?? ""
        size.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05, thenDragTo: size.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        let after = el("side.size").value as? String ?? ""
        XCTAssertNotEqual(before, after, "dragging the size slider changes the size (\(before) to \(after))")
        let op = el("side.opacity"), obefore = op.value as? String ?? ""
        op.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).press(forDuration: 0.05, thenDragTo: op.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        XCTAssertNotEqual(obefore, el("side.opacity").value as? String ?? "", "dragging the opacity slider changes it")
        shot("sliders-moved")
        stroke((0.35, 0.35), (0.85, 0.45)); stroke((0.4, 0.5), (0.8, 0.6)); stroke((0.5, 0.3), (0.6, 0.62))
        sleepFor(1)
        shot("three-strokes")
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled, "drawing makes an undo step")
        app.buttons["Undo"].firstMatch.tap(); sleepFor(0.5)
        shot("undo-button")
        XCTAssertTrue(app.buttons["Redo"].firstMatch.isEnabled, "undo makes a redo step")
        app.buttons["Redo"].firstMatch.tap(); sleepFor(0.5)
    }

    // MARK: 03b gestures: two fingers undo, three fingers redo, pinch, rotate (fingers are gestures when Finger paints is off)

    func test03b_Gestures() {
        makeCanvas()
        // the setting is remembered between launches: whichever way it is, make fingers paint, draw, then turn it off
        tap("Finger paints")
        stroke((0.4, 0.4), (0.85, 0.5)); sleepFor(0.8)
        if !app.buttons["Undo"].firstMatch.isEnabled { tap("Finger paints"); stroke((0.4, 0.4), (0.85, 0.5)); sleepFor(0.8) }
        stroke((0.4, 0.55), (0.8, 0.62))
        sleepFor(1)
        tap("Finger paints")   // off again
        sleepFor(0.5)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        shot("gestures-start")
        let surface = app.descendants(matching: .any)["canvas.surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 8), "the canvas surface is an element")
        for attempt in 0..<3 where !app.buttons["Redo"].firstMatch.isEnabled {   // the simulator's synthesized touches land unevenly: try again, then say so
            if attempt == 0 { surface.twoFingerTap() } else if attempt == 1 { surface.tap(withNumberOfTaps: 1, numberOfTouches: 2) } else { app.windows.firstMatch.twoFingerTap() }
            sleepFor(1.0)
        }
        XCTAssertTrue(app.buttons["Redo"].firstMatch.isEnabled, "a two-finger tap undoes a step")
        shot("two-finger-undo")
        surface.tap(withNumberOfTaps: 1, numberOfTouches: 3); sleepFor(0.8)
        XCTAssertFalse(app.buttons["Redo"].firstMatch.isEnabled, "a three-finger tap redoes it")
        shot("three-finger-redo")
        surface.pinch(withScale: 1.6, velocity: 1); sleepFor(0.5); shot("pinched-in")
        surface.rotate(.pi / 4, withVelocity: 1); sleepFor(0.5); shot("rotated")
        surface.pinch(withScale: 0.6, velocity: -1); sleepFor(0.5)
    }

    // MARK: 04 the brush library with his packs

    func test04_BrushLibrary() {
        makeCanvas()
        let brush = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Brush: '")).firstMatch
        XCTAssertTrue(brush.waitForExistence(timeout: 10)); brush.tap()
        sleepFor(1.5); shot("brush-library")
        app.swipeUp(); sleepFor(0.5); shot("brush-library-lower")
        closeSheet()
    }

    // MARK: 05 colour: disc, classic, harmony, value, palettes

    func test05_Colour() {
        makeCanvas()
        tapButton("Colour"); sleepFor(1.5)
        shot("colour")
        app.swipeUp(); sleepFor(0.5); shot("colour-lower")
        app.swipeUp(); sleepFor(0.5); shot("colour-lowest")
        closeSheet()
    }

    // MARK: 06 layers: add, blend, group, mask, alpha lock, clip

    func test06_Layers() {
        makeCanvas()
        tapButton("Layers"); sleepFor(1.5)
        shot("layers")
        let plus = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add' OR label CONTAINS[c] 'new layer'")).firstMatch
        if plus.exists { plus.tap(); sleepFor(0.8); shot("layer-added") }
        app.swipeUp(); sleepFor(0.5); shot("layers-lower")
        closeSheet()
    }

    // MARK: 07 the three-dots menu, adjustments, selection, transform, quick menu

    func test07_MenuAndTools() {
        makeCanvas()
        actions("Canvas"); shot("actions-canvas")
        tapButton("Adjustments and effects", wait: 8); sleepFor(1.5); shot("adjustments")
        closeSheet(); sleepFor(0.5)
        tap("Select", wait: 8); sleepFor(0.8); shot("selection-bar")
        tapButton("Done", wait: 8); sleepFor(0.5)
        tap("Transform", wait: 8); sleepFor(0.8); shot("transform-bar")
        let cancel = app.buttons["Cancel"].firstMatch; if cancel.exists { cancel.tap() }
        sleepFor(0.5)
        tap("Pick a colour", wait: 8); sleepFor(0.5); shot("eyedropper-bar")
        tapButton("Done", wait: 8)
        actions("Assist")
        let mt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More tools'")).firstMatch
        if !mt.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(mt.waitForExistence(timeout: 8), "More tools is in Actions, Assist"); mt.tap(); sleepFor(1.5); shot("more-tools")
        closeSheet()
    }

    // MARK: 07b his note 11-14: Settings must be reachable inside Paint (the old menu jumped back to its top)

    func test07b_SettingsReachable() {
        makeCanvas()
        actions("Prefs"); shot("actions-prefs")
        let s = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings'")).firstMatch
        XCTAssertTrue(s.waitForExistence(timeout: 8), "Settings row in Actions"); s.tap(); sleepFor(1.5); shot("paint-settings")
        XCTAssertTrue(app.switches["Finger paints after the Pencil is used"].firstMatch.waitForExistence(timeout: 8), "Paint's Settings opened")
        closeSheet()
    }

    // MARK: 08 export: PNG, JPEG, PSD, PDF, and the timelapse

    func test08_Export() {
        makeCanvas()
        stroke((0.35, 0.4), (0.85, 0.5))
        actions("Video"); tapButton("Timelapse", wait: 8); sleepFor(1.5); shot("timelapse")   // first: a share sheet left open would cover it
        closeSheet(); sleepFor(0.8)
        actions("Canvas"); tapButton("Save or share the picture", wait: 8); sleepFor(1.5); shot("export-sheet")
        for fmt in ["PDF", "JPEG", "PNG"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", fmt)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(fmt) export row")
            row.tap(); sleepFor(2.5); shot("export-\(fmt.lowercased())-share")
            let close = app.buttons["Close"].firstMatch
            if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
            sleepFor(0.8)
        }
        closeSheet()
    }

    // MARK: 09 the Gallery's own actions: open, rename, duplicate, share, stack, delete

    func test09_GalleryActions() {
        ensureWork()
        let first = works().firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10)); shot("gallery-with-a-work")
        // rename
        first.press(forDuration: 1.2); sleepFor(0.8); shot("context-menu")
        tapButton("Rename", wait: 8)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        field.typeText("Renamed piece")
        shot("rename-alert")
        app.alerts.buttons["Rename"].tap(); sleepFor(1)
        XCTAssertTrue(app.buttons["Work, Renamed piece"].waitForExistence(timeout: 10), "the card carries the new name")
        shot("renamed")
        // duplicate
        let n = works().count
        app.buttons["Work, Renamed piece"].firstMatch.press(forDuration: 1.2); tapButton("Duplicate", wait: 8); sleepFor(1.2)
        XCTAssertEqual(works().count, n + 1, "duplicate adds a card")
        shot("duplicated")
        // share
        app.buttons["Work, Renamed piece"].firstMatch.press(forDuration: 1.2); tapButton("Share", wait: 8); sleepFor(0.5); shot("share-menu")
        tapButton("PDF", wait: 8); sleepFor(2.5); shot("gallery-share-pdf")
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
        sleepFor(1)
        // stack
        app.buttons["Work, Renamed piece"].firstMatch.press(forDuration: 1.2); tapButton("Put in a stack…", wait: 8)
        let sf = app.textFields.firstMatch; XCTAssertTrue(sf.waitForExistence(timeout: 8)); sf.tap(); sf.typeText("Studies")
        shot("stack-alert")
        app.alerts.buttons["Put it there"].tap(); sleepFor(1)
        XCTAssertTrue(el("gallery.stack.Studies").waitForExistence(timeout: 10), "the stack is a card")
        shot("stack-card")
        el("gallery.stack.Studies").tap(); sleepFor(0.8)
        XCTAssertTrue(el("gallery.stackback").waitForExistence(timeout: 8)); shot("inside-the-stack")
        // delete the one inside
        works().firstMatch.press(forDuration: 1.2); tapButton("Delete", wait: 8)
        sleepFor(0.5); shot("delete-confirm")
        app.buttons["Delete"].firstMatch.tap(); sleepFor(1.2)
        shot("after-delete")
    }

    // MARK: 10 import a photo from the simulator's Photos library as a new work

    func test10_ImportPhoto() {
        let before = works().count
        tap("gallery.import"); sleepFor(0.8); shot("import-menu")
        tapButton("A photo, as a new work", wait: 8)
        sleepFor(3); shot("photos-picker")
        sleepFor(6)   // the picker loads the library slowly on a fresh simulator
        let pic = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        if pic.waitForExistence(timeout: 15) { pic.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.42)).tap() }   // the first picture, left of the top row
        sleepFor(1.5); shot("photo-picked")
        let addBtn = app.buttons["Add"].firstMatch; if addBtn.waitForExistence(timeout: 3) { addBtn.tap() }
        XCTAssertTrue(app.buttons["canvas.gallery"].waitForExistence(timeout: 40), "the photo opens as a new work")
        sleepFor(1.5); shot("photo-as-a-work")
        backToGallery()
        XCTAssertEqual(works().count, before + 1, "the photo is a card in the Gallery")
        shot("gallery-after-photo")
    }

    // MARK: 11 the work survives leaving and coming back

    func test11_ReopenAWork() {
        ensureWork()
        works().firstMatch.tap()
        XCTAssertTrue(app.buttons["canvas.gallery"].waitForExistence(timeout: 20), "a card opens its canvas")
        sleepFor(1); shot("reopened")
        backToGallery(); shot("back-in-the-gallery")
    }
}
