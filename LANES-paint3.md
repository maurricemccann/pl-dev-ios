DONE (paint3 lane, 11-13/14, branch `wave-paint3`). PL Paint opens to the Gallery, and the flows are driven on the iPhone simulator by an XCUITest: last run 43576894155, 11 of 12 flows pass, 1 fails (two-finger tap, below). Compile with publish off: build run 43567016015, success. Nothing here has run on a device.

# What changed (all inside `PLDev/Sections/Paint/`, plus the test project and one workflow)
- **The first screen is the Gallery** (`PaintGallery.swift`, replaces the old Paint home panel list). Like the laptop and Procreate: a grid of works (thumbnail, name, size, age), a dashed "New canvas" card, stacks as folder cards (tap opens the stack, a back card returns), the Daily Mark above, then Waiting to be filed, Sync, and the Handbook below. Tap a work: it opens its canvas. Tap a laptop-only work: it downloads, then opens. Touch and hold a card: Open, Rename, Duplicate, Share (PNG, JPEG, PSD, PDF), Put in a stack, Take out of its stack, Delete (with a confirmation). Toolbar: Import (a photo as a new work from the Photos picker, or a file: PSD, a picture, a work file from the laptop, a brush pack or `.abr`) and the plus (New canvas).
- **New canvas** is one sheet shared by the Gallery and the canvas (`NativeNewCanvasSheet(make:)`): his sizes, phone screen size, width and height, paper stock, transparent background, the Hoodie 717 garment sheet. It makes the canvas, then the canvas opens (`PaintCanvasRequest.setup`).
- **The canvas has the laptop's slim sidebar**: brush size slider, eyedropper, opacity slider, Adjust strokes, down the left edge (`SideSlider`, vertical, VoiceOver adjustable). The two bottom sliders are gone. The top-left button is "Gallery" (saves, syncs, returns to the Gallery). The canvas surface is an accessibility element named "Canvas".
- **PDF export** (the one export the laptop and Procreate have that the phone lacked): `NativeExport.pdf`, a row in Save or share, and in a Gallery card's Share menu. JPEG, PNG, PSD, both SVGs and the work file were already there.
- Not changed on purpose: the engine, layers, brushes, colour, selection, transform, assists, adjustments, the new tools of paint2, Sync. They were read against the laptop's `index.html` Actions list and its Colour, Brushes, Layers, Adjust and Tweak cards: every row has a native twin except the one gap below.

# The gap check against the laptop (read `C:\dev\pl-paint\src\index.html` and `app.js`)
Built and present: everything in LANES-paint.md and LANES-paint2.md, plus now the Gallery, PDF and the side sliders. **Not built, with the reason:**
- **Brush cursor** (an outline at the brush size): the laptop draws it under a mouse pointer. An iPhone has no hover, so there is nothing to show before the finger lands. Left out.
- MP4 time-lapse of a work in the Gallery's card menu: the time-lapse and its MP4/alive exports are in the canvas More menu as before; the Gallery card does not export them.

# End-to-end proof (the harness)
- `PLDevUITests/` is a stand-alone Xcode project with one UI-testing bundle (`PaintFlowTests.swift`). It drives the installed PL DEV by bundle id, so the main project file is untouched (`check_pbxproj.py` still passes).
- `.github/workflows/paint-e2e.yml` builds PL DEV for the simulator, boots an iPhone, seeds the simulator's Photos library with three generated test pictures (`xcrun simctl addmedia`, 640x480 PNG rings made by a Python snippet, nothing of his), writes the same public-address config `screens.yml` writes (dummy key names, no real key, no private address), runs the tests, and uploads every step's screenshot plus the log (`paint-e2e` artifact). It runs when `PLDevUITests/RUN` changes on the branch (a branch-only workflow cannot be dispatched by hand) or by dispatch once on main.
- Each step's screenshot was downloaded with `gh run download` and looked at. Results from run 43576894155 (artifact `paint-e2e`):

| Flow | Result | What the screenshots show |
|---|---|---|
| 01 Gallery is the first screen | PASS | "Gallery" title, Daily Mark, dashed New canvas card, Sync, Handbook |
| 02 New canvas card and its sizes | PASS | the sheet with Sizes, pixels, Garment, Paper; Cancel returns |
| 03 Make a canvas, draw, size and opacity, undo and redo | PASS | three finger strokes appear; the size slider reads 28 then 197 after a drag; opacity 100% then 66%; Undo enables after drawing, Redo after undo |
| 03b Gestures | **FAIL on one assertion** | pinch (zoomed in) and rotate (canvas turned about 45 degrees) are visible in the shots; the two-finger tap and the three-finger tap did not register (see below) |
| 04 Brush library | PASS | his packs listed with live stroke previews, Round ticked, Find a brush |
| 05 Colour | PASS | the colour sheet, scrolled to its lowest section |
| 06 Layers | PASS (opens) | the layers panel with opacity, Blend, Glow, Alpha lock; no add-layer, blend-change, group, mask or clip step is driven |
| 07 More menu, adjustments, selection, transform, eyedropper, More tools | PASS | each sheet or bar appears |
| 08 Export: PDF, JPEG, PNG, then Timelapse | PASS | each row opens the system share sheet with a real file ("... PDF Document, 77 KB" for the PDF); the Timelapse sheet opens |
| 09 Gallery actions | PASS | touch and hold menu; Rename to "Renamed piece" (card carries the new name); Duplicate adds a card; Share menu then PDF share sheet; Put in a stack "Studies" (a stack card appears, opening it shows the work and a back card); Delete with a confirmation |
| 10 Import a photo from Photos | PASS | the Photos picker lists the three seeded pictures; picking one opens a new 640 x 480 work named "Photo" with the picture on its layer; back in the Gallery the card count is one higher |
| 11 Reopen a work | PASS | a card opens its canvas, Gallery returns |

- **The one failure, said plainly:** XCUITest's `twoFingerTap()` and `tap(numberOfTouches: 2/3)` did not run Undo/Redo on the simulator, tried three ways in the last run (the canvas element, the same call with explicit touches, the window). Pinch and rotate, which also use two touches, did work, and the app's recognizers are the laptop-parity ones (`UITapGestureRecognizer`, 2 to 4 touches, defaults tap2 = Undo and tap3 = Redo from the toolkit). I could not tell from here whether the simulator's synthesized taps never reach a two-finger tap recognizer or the recognizer misses them; it needs one real two-finger tap on his phone.

# Not driven (named so nothing is mistaken for tested)
Importing a PSD or a work file through the Files picker (the Files picker needs a file in the simulator's Files storage, which the runner cannot seed); layer add, blend change, groups, masks, alpha lock, clip; the selection and transform handles being dragged; the colour disc and palettes being tapped; the QuickMenu and the gesture settings; the Study recorder, Lift and an adjustment being applied; the MP4 and alive time-lapse exports; Sync (there is no key in the run); the Pencil. The photo import and PDF were proven; a video import does not exist in the app, so no video was seeded.

# Server routes needed
None.

# Shared-file lines the lead must wire
None. `PaintSection.makeRoot` still returns `PaintHome(model:state:)`; the section's registration, origins and keys are unchanged. The `AppShortcuts.swift` lines from LANES-paint2.md still apply.

# Note for the lead
- `logic.yml` fails its hygiene scan on this branch and on main alike (`your@email.com` placeholders in House and Shop files, an email in `LANES-storefront-live-test.py`); none of it is in Paint.
- The sidebar covers the left edge of a full-width canvas (the canvas can be panned from under it). If he prefers it narrower or on the right, it is one modifier in `NativeCanvasView.sideBar`.

# Twin rule (one change, every body)
Twins named: the laptop app (`C:\dev\pl-paint`), its web build at `/paint/` on the gallery, its handbook, the R1 (no PL Paint app there). Nothing on the laptop side was changed; the laptop already has the Gallery, the sidebar and no PDF export, so PDF is a phone-only addition: the laptop's Actions list has no "Save PDF". The native handbook text is generated from the laptop's handbook; the Gallery's Import and Share menus and the PDF row have no handbook text yet (the handbook lives in the laptop repo, outside this lane): add "Import" and "PDF" there and re-run `scripts/paint_handbook.py`.
