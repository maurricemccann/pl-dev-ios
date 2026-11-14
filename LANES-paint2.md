DONE (paint2 lane, 11-13). Every feature `LANES-paint.md` listed under Not built is ported from `C:\dev\pl-paint\src` into `PLDev/Sections/Paint/`, on branch `wave-paint2`. Compile-checked in CI with publish off (result at the foot). Nothing has run on a device.

# What was built (new files in `PLDev/Sections/Paint/Native/` unless noted)

| Feature | Laptop source | Where |
|---|---|---|
| Facet and Curve: a stroke drawn again as straight segments with rounded corners (all strokes, or "Facet the next stroke" = the laptop's Shift) | `facetPath`, `endStroke` | `NativeFacet.swift`; hook in `end()` |
| Seam mode: Hoodie 717 template (`Seam717.json/.png` copied from `pl-paint/src/seams`), the chain-of-pens carry across sewn edges with turn, the band-rail replay, the template and numbered coloured seams drawn over the art, on/off toggle, saved in the work (`guide.seam`) | `seamLoad`, `seamMap`, `seamFrame`, `seamCopies`, `seamReplay`, `seamGuide`, `seamLines` | `NativeSeam.swift`; hook in `copies(of:)` (`NativeModel+Assist.swift`); New canvas has "Hoodie 717 zip (seams)" |
| Save print files: each piece cut from the sheet and scaled to Printful's size, plus the pocket and the ground file; share sheet | `saveSeamFiles` | `NativeSeam.swift` |
| Tile ghost (the live ghost for the stroke in hand, and where an arriving line must end), tile gate (art that touches an edge with nothing meeting it), middle cross guide, Show the tiles around (faint, outside the picture only); Make tile now turns the preview on, as the laptop does | `ghostGeom`, `tilePorts`, `tileGuides`, `tileSheet` | `NativeTileGuides.swift`; overlay hooks in `NativeCanvasStage.swift` |
| Echo Fill (chamfer distance field, concentric lines; step, weight, count, start-inside), Light one (a new glowing "Lit cell" layer), Lights off (non-glowing layers dim to 10 %, glow brighter, dark ground), Other ground | `echoFill`, `edtMask`, `echoAlpha`, `lightOne`, `lightsOff`, `otherGround` | `NativeEcho.swift`; Stage dims layers |
| Node mode (RDP nodes on the stroke just drawn; drag one and the stroke is drawn again through the new path, smoothstep falloff between neighbours; a touch on another line gives it the nodes; a tap on an older line takes back the dot; "Finish this line?") | `nodeFit` ... `nodeUp`, `tweakAny` | `NativeNodes.swift`; `tweakLast` and `restyleLayer` take a new path |
| Hand Trace: the one-page PNG (picture, strokes, pen time, path, speed, pressure, tremor, brushes, two histograms, SHA-256 of the log) and its JSON | `traceData`, `tremorOf`, `handTrace` | `NativeHandTrace.swift` |
| Colourways (one tap recolours every colour of a brush; swatch per colour slot with a picker), the Colour card's two Random palettes after the House one (new each launch, a Shuffle button), the merged kit palettes list | `qcSlots`, `qcWays`, `qcApply`, `kit.js` | `NativeColourways.swift`; `NativeToolkit.palettes`; Colour sheet. A change to a built-in brush's colours is kept on the phone by brush id; a Mine brush keeps it in the brush |
| Timelapse by colour pass (the picture built one colour at a time from the stroke log, on a scratch canvas that never saves or counts), and the alive loop (build + 6 s of the finished picture breathing, mesh-warped, loops with no seam; MP4 through the share sheet) | `tlBuildPasses`, `breatheFrames`, `tlSave(0,'alive')` | `NativePasses.swift`; `NativeTimelapse.swift` sheet |
| Transform resampling (Bicubic / Bilinear / Nearest) and Magnetics (turn locks to 15 degrees, a move locks to the middle of the picture within 12 points) | `TR.interp`, `TR.mag` | `NativeTransform.swift`; transform bar |
| Pencil buttons: double tap runs "Pen side button", a Pencil Pro squeeze runs "Pen second button"; Settings has "Swap the Pencil's two buttons" | `penbtn`, `penbtn2` | `NativeCanvasStage.swift`, `NativeSheets.swift` |
| iOS add-ons for the canvas: App Intents (Open PL Paint's canvas; How is my Daily Mark, spoken), Spotlight (13 rooms, `IndexedEntity` + `OpenIntent`, indexed in `PaintSection.refresh`), deep links `pldev://section/paint/canvas/<room>`, two Tips | DESIGN.md §6 | `PaintSystem.swift`, `PaintSection.swift` |

New panels: **More tools** (Facet, Node mode, Echo Fill, Light one, Lights off, Other ground, tile guides, seams, hand trace; reached from the ••• menu, the Assists sheet, the Quick menu and gestures as "More tools") and a share sheet for files. Eleven new action names join the Quick menu and Gesture controls lists (Facet next stroke, Echo Fill, Node mode, Lights off, Light one, Other ground, Hand trace, Seam mode (toggle), Save print files (seam mode), Tile (cycle), Show the tiles around, Tangent Lock, Export alive, More tools).

# Differences from the laptop (named so nothing is mistaken for exact)
- Facet: no mid-stroke trigger (the laptop's Shift held part-way). The facet is chosen before the stroke, for all strokes or the next one.
- Tile guides, the seam template and the node dots are drawn in the screen overlay above the layers; the laptop draws the template and the tile neighbours beneath the art. The template is a faint line image so it reads, but a very dense piece shows it through the lines.
- Echo Fill and Light one use the shared flood fill (per-channel tolerance 24); the laptop's `floodMask` may measure the colour distance a little differently, so an antialiased shape can differ by a pixel.
- Node mode: bending a stroke that is not the last one rebuilds the layer through Restyle, so it refuses a layer that holds fills, pasted or smudged parts (the laptop's rule too). Restyle uses each stroke's brush by id as the toolkit has it now.
- Passes: the scratch canvas is a second full-size document in memory (64 MB at 16 MP) while it runs. The alive loop draws 144 frames at 960 px off the main thread.
- Lights off is not applied on the CPU-composed path (the nine PSD-only blends); it dims correctly in the normal path.
- Not built: a Live Activity (a video is written in seconds; the share sheet takes it from there) and notification buttons (Paint never pushes). Both are "not fitting" under DESIGN.md §6.

# Unproven (no device, no Mac)
Every pixel of the new overlays; the seam carry on a real hoodie (geometry is a straight port, the numbers at the corners are untested); the alive loop's frame time; AVAssetWriter at 24 fps from mixed JPEG sets; `UIPencilInteraction` squeeze on a Pencil Pro; the gate scan time on a 16 MP picture (it runs 120 ms after the picture stops changing, on the main thread).

# Shared-file lines the lead must wire
`Shared/AppShortcuts.swift` (the whole app is capped at 10 shortcuts; today it holds 8 or more, so these two replace whichever two the lead ranks lowest):

```swift
AppShortcut(
    intent: OpenPaintCanvasIntent(),
    phrases: ["Open the canvas in \(.applicationName)", "Paint in \(.applicationName)"],
    shortTitle: "Open the canvas",
    systemImageName: "paintbrush.pointed.fill"
)
AppShortcut(
    intent: PaintDailyMarkIntent(),
    phrases: ["How is my Daily Mark in \(.applicationName)"],
    shortTitle: "Daily Mark",
    systemImageName: "flame"
)
```
Nothing else: Spotlight is indexed from `PaintSection.refresh`, deep links go through `PaintSection.handle`, Tips need only `Tips.configure` (already in `PLDevApp`). `Info.plist`: nothing new.

# Server routes needed
None.

# Twin rule (one change, every body)
Twins named: the laptop app (`C:\dev\pl-paint`) and its handbook; nothing was changed on the laptop side. The laptop's handbook already describes each of these features, and `NativeHandbook.json` is generated from it, so no handbook text was missing. Sync is unchanged: the work file's `guide.seam` is the laptop's own field, so a hoodie started on either side opens on the other. Left alone on purpose: the gallery's `/paint/` web build and the R1 (it has no PL Paint app).
