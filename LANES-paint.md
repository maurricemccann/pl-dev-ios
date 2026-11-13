PHASE REACHED: P1 and P2 built, P3 part built (layers, 15 live blends, groups, clips, share). Everything compiles in CI (lane-paint, build.yml publish=false). Nothing has run on a device. P3's selection and transform, and P4 to P6, are not started.

# Lane C: PL Paint native engine (11-13)

## The one line the lead adds to open it
In `PaintHome` (`PLDev/Sections/Paint/PaintSection.swift`), a row and a cover:

```swift
// state: @State private var nativeOpen = false   (or a flag on PaintModel, like canvasOpen)
Section { Button { nativeOpen = true } label: { Label("Native canvas (beta)", systemImage: "paintbrush.pointed") } }
.fullScreenCover(isPresented: $nativeOpen) { NativeCanvasView(model: model) }
```

`NativeCanvasView` closes itself (its own X) and saves on close, on leaving the app and 3 s after the last change.
No other shared file needs a line: no key (it reads the same `paint` origin the web canvas uses), no intent, no notification, no Info.plist entry.

## Files (all new, all in `PLDev/Sections/Paint/Native/`)
- `NativeCanvasView.swift`: the screen (toolbar, brush, colours, size, opacity, finger-paints toggle, works sheet, share).
- `NativeCanvasModel.swift`: the open work, the live stroke, undo and redo, autosave, layer operations.
- `NativeCanvasStage.swift`: the UIKit surface: Pencil touches (coalesced), pinch, twist, two-finger pan, two/three/four-finger taps (undo, redo, fit).
- `NativeStroker.swift`: port of `Stroker` in `pl-paint/src/brush.js`. Pure.
- `NativeStamp.swift`: port of the sprite, `drawStamp`, twin, fill, grain and colour-jitter code.
- `NativeToolkit.swift` + `NativeToolkit.json`: his packs and defaults (a copy of `pl-toolkit`'s data; 4 packs, 45 brushes, 14 canvas presets).
- `NativeBrushSheet.swift`: the brush list with sample strokes drawn by the same engine.
- `NativeLayers.swift`, `NativeLayersSheet.swift`: layers, 26 blend names, groups, clip, flat export.
- `NativePixels.swift`: layer pixels and the patch-stack undo (250).
- `NativeWork.swift`: his work file read and written, the local store, the synced-works reader, gzip.

## What works (by construction; compiled, not run)
- **P1.** A canvas at any size up to 16,777,216 px. Apple Pencil: force, coalesced samples, tilt (altitude and azimuth turned into the laptop's tiltX and tiltY and logged only when the brush uses tilt). Fingers draw only if "Finger paints" (the laptop's rule); a second finger cancels a finger stroke. Pinch, twist, pan, undo (patch stack of 250, blocked mid-stroke), autosave, save and open.
- **His work files, both ways.** `NativeDoc(file:)` reads the laptop's `work-<id>.json` (v:1: w, h, bg, bgVis, active, groups, guide, layers with PNG data URLs, mask, log). Anything the engine does not use yet (groups, guide, seam, glow, ref, raw, assist, mask) is carried through untouched, so a work opened here and saved goes back whole. Synced works: `GET paint/index`, then `GET paint/work/:id` (the body is gunzipped when its first two bytes say gzip), kept on the phone under the same id with the sync fields (`sy`, `scu`, `sn`) the laptop's `pullWork` sets. The stroke log is written in the laptop's `rec` shape (tool, color, color2, size, op, brush, layer, onMask, t, pts [x, y, p, ms(, tiltX, tiltY)], bs, snapped, sym), last 4,000 kept.
- **P2.** The whole generator of `brush.js`: spacing and its jitter, lateral and linear jitter, StreamLine, Stabilization, taper, flare, caps, swell, tremor, speed, scatter, stroke rotation, tilt size and angle, twin, parallel lines, band mode (His bands), a replay on release for brushes whose ends need the length, and the 14-step catch-up. Stamp shapes round, square, diamond, bristle, tube, and tips (PNG tips from a brush file). Texturised grain (noise, paper, relief, canvas, dots) in one pass over the stroke at release. Hue, saturation and lightness jitter. His packs listed with live sample strokes.
- **P3 (part).** Layer sheet: add, duplicate, delete (asks), move, rename, opacity, blend, show or hide, alpha lock (paints only where pixels are), clip to the layer below. 15 blend modes live on screen through Core Animation; groups' visibility and opacity applied; masks he made on the laptop are shown. Share sheet exports the flat PNG through the same compositor.

## Unproven (no device, no Mac)
- Every pixel. Nothing in this lane has been drawn on, so the stamp scale, Pencil feel, gesture conflicts (twist and pinch against a finger stroke), memory at 16 MP (a layer 64 MB plus the stroke buffer 64 MB plus tiles) and the frame rate while drawing are all untested. First thing to check on the phone: draw with Round, then with Oil pastel, then with a His bands brush, compare to the laptop.
- The fidelity set (the same strokes on both, compared) is not built. The stroker is a line-by-line port, so spacing and jitter should match; the sprite blur on square and diamond is a Core Graphics shadow, close not identical.
- `NativeToolkit.json` reaching the bundle: files in a synchronized group are bundled by default, but the build was not inspected. If the brush list shows only "Round", the file is missing from the app; add it to Copy Bundle Resources.
- gzip: Apple's `.zlib` decoder is used on the raw deflate stream between the gzip header and trailer. Right in theory, never run against a real synced work.
- Large works: saving PNG-encodes every layer on the main thread (a hitch at the end of a stroke on a big canvas).

## Not built (named, so nothing is mistaken for done)
- P3: selection (automatic, freehand, rectangle, ellipse), transform (freeform, uniform, distort, warp), layer groups editing, mask painting, merge down, glow, the nine PSD-only blends (they save and show as Normal; the sub-spec says per-pixel, a CPU port of `blend.js` is the way), layer-structure undo (layer operations clear the undo stack and say so).
- Strokes the engine does not yet make: smudge, wet mix, channel clearance (the keyline), satellites, echo, weave, wick, "moving" and "along" grain, pressure grain, join modes (band-meets-band), QuickShape, tangent lock, assisted drawing, symmetry, guides, tile and seam modes, eyedropper from the pen button, adjust last stroke, rapid undo (hold two fingers).
- P4 assists, P5 (adjustments, PSD, SVG, .abr import, timelapse, Send to Curate or Archive, Daily Mark counting), P6 fidelity pass. Sync **write** (push to pl-cron, fork on conflict) is not built, so a stroke made here stays on the phone; the laptop and the web canvas do not see it. The web canvas (`PaintCanvas`) stays his working painter, as the lane brief said.
- The handbook, Settings glass and the iOS add-ons of DESIGN.md section 6 (widget, Live Activity, intents, Spotlight, tips, deep link `pldev://section/paint/native`) were not done for the native canvas; the Paint section already has its widget and deep link.

## Server routes needed
None. Only reads of `GET /api/paint/index` and `GET /api/paint/work/:id` (both exist). Sync write later needs only the existing `PUT work/:id` and `POST meta`.

## Gap check against the twin rule
Twin of the laptop app: **partial by design**. Behaviour a stroke has on the laptop that this engine does not yet produce is listed under "Strokes the engine does not yet make"; until those land, a work drawn with such a brush here will differ from the laptop's. The handbook text for the native canvas does not exist yet (rule: One change, every body).
