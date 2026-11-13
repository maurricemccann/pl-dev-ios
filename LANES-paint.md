DONE (paint lane, waves 3 and 4, 11-13). PL Paint is native from the home screen to the canvas; the web canvas is deleted. The branch compiles in CI (`wave-paint`, build.yml publish=false). Nothing has run on a device: every pixel, the Pencil feel and the memory at 16 MP are unproven (listed below).

# What changed in this pass (on top of the P1 to P3 engine already on the branch)

## The web canvas is gone
- `PaintCanvas`, `PaintWeb` and `import WebKit` are deleted from `PLDev/Sections/Paint/PaintSection.swift`. The handbook link no longer opens `GalleryCanvas`; it opens the native handbook (`NativeHandbookView`, built from the laptop's handbook, pictures load from the gallery at run time).
- `grep -rn "WKWebView\|GalleryCanvas(\|PaintWeb\|PaintCanvas(" PLDev/Sections/Paint` returns nothing. `ComingSection` stays in that file because other sections still build it.
- The Paint home is now native in PL Paint's own look (its `style.css`: ground #0e0c08, cream text, his gold, thin glass panels, his hand for the title): Back to the canvas, the Daily Mark (streak, five weeks), Your works (this phone's, then the laptop's not yet here, tap to download and open), Waiting to be filed, Sync now, the Handbook. Deep link `pldev://section/paint/canvas` (or `/native`) opens the canvas.

## Built this pass (all in `PLDev/Sections/Paint/Native/`, new files marked +)
- + `NativeAdjust.swift`: the 11 adjustments and effects of `adjust.js` (Hue/Saturation/Brightness, Colour Balance, Curves, Gradient Map, Gaussian and Motion Blur, Noise, Sharpen, Bloom, Halftone, Chromatic Aberration), a live preview on a 720 px copy, Apply to the full layer inside the selection, keeping the shape on an alpha-locked layer, one undo step.
- + `NativeLift.swift`: Lift (ink off a photo of a physical piece), port of `lift.js` (per-block paper, threshold, softness, gain, specks, light-on-dark, own colours or the current colour, fit to canvas), photo from the Photos picker, result on its own layer, then Transform.
- + `NativeExport.swift`: Save or share as PNG, JPEG, PSD (layers, names, opacity, blends, groups as folders, masks and clips baked in), SVG with layers as images, SVG with the strokes as vector paths (port of `svg.js`, with channels as masks and the eraser as a mask), and the work file; all leave through the share sheet. Bring in: a photo as a layer, a PSD as layers (groups kept), a Photoshop `.abr` file (tips into Mine), a brush pack `.json`, a work file from the laptop (opens as a new work), any picture; Make a brush from this layer (the signature stamp).
- + `NativePSD.swift`: the PSD writer and reader (8-bit RGB, raw and RLE channels, groups).
- + `NativeTimelapse.swift`: a small picture after every change (960 px JPEG, a folder per work, thinned past 2,400), replay and scrub, and a video as MP4 (every frame at 30 fps, or 10, 20, 30, 60 seconds).
- + `NativeStudy.swift`: the Study recorder (every stroke with its raw path, pressure, tilt and timing; undo; marks), the twelve guided exercises from the toolkit, the bar while it records, past sessions with share and delete. Sessions stay on the phone in `PLPaintNative/study/` unless he shares one.
- + `NativeTweak.swift`: Adjust last stroke (size, swell, clearance, companion width and gap, lines, line gap, drawn again from its pen path as a slider moves, Keep as the brush's setting) and Restyle the whole layer (every stroke redrawn with a size scale and brush overrides, one undo step).
- + `NativeExtras.swift`: ghost copy behind a layer, corner copies for a tile, the 3 by 3 repeat check, Name It (a quality from his names file plus the date), Stacks of works (put in a stack, take out; grouped in the Works list; the stack name syncs with the laptop), Passes (each stroke takes the next colour of a palette; Colour sheet).
- Edits to existing files: `defaultMeta` raw is now false (the laptop's default; it had been true, which would have blocked Restyle and mislabelled every new layer); every layer carries a stable `id` and the log names its layer by it (as the laptop does), which Restyle and the vector SVG need; Settings has a Keys row (sync key Set / Not set) and the timelapse switch; the rename alert is now a sheet with the suggestion button; the Actions list gained Adjust last stroke, Study, Lift, Timelapse, Ghost copy, Corner copies, Check the repeat.
- Fixes for the merge: `override` on `gestureRecognizerShouldBegin`, `catmull` made `nonisolated`, the duplicate `DailyMarkStrip` removed, and the two wave-2 name-clash renames (`FlowChips` in GlyphBot, `ArchiveWork` in ThreeD) cherry-picked from main so this branch builds alone.

## Already there before this pass (kept)
Engine P1 and P2 (stroker, stamp, the whole brush generator, 45 brushes in four packs), layers, 26 blends (the nine PSD ones per pixel on the CPU), groups, masks, clips, solo, reference, glow, alpha lock, selection (automatic, freehand, rectangle, ellipse, add, remove, invert, feather, history), transform (free, uniform, distort, warp, pivot), assists (symmetry, guides, vanishing points, assisted drawing, QuickShape, tangent lock, tile), smudge, wet mix, ColorDrop, eyedropper, gestures and the QuickMenu, copy and paste, Sync both ways with the laptop (works, Daily Mark, Mine brushes, fork on conflict), Send to Curate or the Archive, the native handbook.

# Gap check against the laptop's "Every feature" chapter (12)
Built: the screen, gestures, canvases and files (presets, paper stocks, transparent background, Gallery with rename, duplicate, delete and now stacks, Daily Mark, autosave, stroke journal, PNG, PSD in and out, both SVGs, open as layer, Name It), brushes (packs, Studio, import and export of packs, `.abr`, brush from a layer), adjusting what you drew, colour (disc, sliders, harmony, value, hex, history, palettes, colour sense, Passes), layers, selecting and transforming, drawing aids except those below, all 11 adjustments, Timelapse (replay, scrub, 30 s and full video), Study, Lift, phone and sync, the handbook.

**Not built (named so nothing is mistaken for done):**
- Facet and Curve (straight segments with rounded corners while drawing).
- Seam mode (a garment's pieces on one canvas) and Save print files; tile ghost, tile gate, the middle cross guide, Show the tiles around.
- Echo Fill, Node mode, Lights off / Light one (glow lighting), Hand Trace (the one-page record of a piece).
- Colourways (one tap recolours every part of a brush), the Colour card's random palettes and the merged kit palettes list (his 13 palettes are there).
- Timelapse by colour pass and the "alive" breathing loop; Transform resampling choice and Magnetics beyond the snap; the Pencil second-button swap beyond the action it is given.
- The iOS add-ons of DESIGN.md section 6 for the canvas: a Live Activity, App Intents and Spotlight entries for the rooms, notification buttons, Tips. The Paint tile already has its widget (Daily Mark) and the deep link; the new panels are reachable from the toolbar, not by Siri.
- The laptop's Settings glass panel (blur, tile strength, text size, fonts, reduce motion): the canvas follows PL DEV's Settings for look.

# Unproven (no device, no Mac)
- Every pixel: stamp scale, Pencil feel, gesture conflicts (twist and pinch against a finger stroke), memory at 16 MP (a layer 64 MB, the stroke buffer 64 MB, the compositor's temporary buffers, an adjustment's copies), frame rate while drawing.
- Adjustments, Lift and Restyle run on the main thread on full-size layers; a 16 MP layer will hitch for a second or two while they apply (the preview is a 720 px copy and is quick).
- gzip in Sync (Apple's `.zlib` decoder on the raw deflate stream between the gzip header and trailer) and the PSD reader against real Photoshop files; the PSD writer against Photoshop, Procreate or Affinity opening it.
- The ABR reader against real brush files (versions 1, 2, 6, 7, 10 are handled the way `abr.js` does; descriptor names are read without a full parser).
- Video: `AVAssetWriter` H.264 from the JPEG frames, never run.
- Restyle uses each stroke's brush by id from the toolkit as it is now, not the brush as it was when the stroke was drawn (the laptop keeps `brushFull`; this log keeps only the `bs` summary).

# Server routes needed
None. Sync uses the existing paint door: `GET index`, `GET work/:id`, `PUT work/:id`, `POST meta`, `POST delete`, `GET/PUT file/:name`, `POST send`, `GET outbox`.

# Shared-file lines the lead must wire
None required. `PaintSection` already registers the section and its origins (`gallery`, `paint`) and key (`paintSync`). Optional, for the add-ons above: an App Intent "Open PL Paint's canvas" and a Spotlight entry would go in `Shared/AppShortcuts.swift` (shared, so not touched here).
Info.plist: nothing new. The Photos picker, the Files importer and the share sheet need no usage string. If the lead later adds "Save to Photos" directly (not through the share sheet) it needs `NSPhotoLibraryAddUsageDescription`.

# Twin rule (one change, every body)
Twins named: the laptop app (`C:\dev\pl-paint`) and its handbook. Nothing was changed on the laptop side. The native handbook text is generated from the laptop's (`scripts/paint_handbook.py`); the laptop handbook already describes Lift, Adjustments, Timelapse, Study, Stacks, Name It and the exports, so no handbook text was missing for what was added. The R1 has no PL Paint app. Left alone on purpose: the gallery's `/paint/` web build (it remains the laptop's installable web twin, no longer used by this app).

# Test notes
Pure parts worth unit tests when a Linux-hosted package exists for them: `NativePSD` (write then read round trip), `NativeABR.parse`, `NativeStroker`, the work-file reader. They live in the app target here, not in `PLDevCore`, so `logic.yml` does not run them.
