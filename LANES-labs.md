DONE — labs lane (wave 3), branch `wave-labs`, compile check green (run 43526275656, publish=false).

# Labs, native

All 25 rows of `GalleryRoom.labPages` are native views in `PLDev/Sections/Labs/`; no web view anywhere in the folder.

| Lab | File | Built with |
|---|---|---|
| Warp, Glitch, Reaction, Life, Fluid, Metal probe | LabMetal.swift | Metal |
| Ribbon curves | LabRibbons.swift | Metal |
| Plotter, Phyllotaxis, Kinematic, Golden Mend | LabSketches.swift | Core Graphics, mic via VJAudio |
| Heart, Wordmark, Cards, Curve who | Lab3D.swift | RealityKit (his converted models) |
| AR curves | LabAR.swift | AVFoundation camera |
| The fly | LabFly.swift | connectome engine, native |
| Hero grammar | LabHero.swift | native grammar |
| Study, Home study, Hand, Components | LabStories.swift | SwiftUI |
| The curve in motion (6 pieces) | LabCurveMotion.swift | Canvas |
| GlyphGuy dances / GlyphBot | ThreeD `GlyphGuyRoom` | RealityKit |

The curve in motion: cloth, red cloth, 3D curve engine, matrix code spine, matrix TV, ascension lite, all ported from `public/living-curves-art/index.html`. Pieces run only while on screen (`onScrollVisibilityChange`), except the Matrix TV bitmap.

## Lines the lead wires
1. `PLDev/Sections/Library/GalleryRooms.swift` line 58: replace `WebListRoom(model: model, title: "Labs", items: GalleryRoom.labPages)` with `LabsRoom(model: model)`.
2. Then `GalleryRoom.labPages` has no user; delete it.
3. Nothing else is shared: `LabStubs.swift` is deleted; no shared file, server route or Info.plist line is needed. Camera and mic use strings: AR curves needs `NSCameraUsageDescription`, Golden Mend and Life need `NSMicrophoneUsageDescription` (add if not already in Info.plist).

## Gap check
- Three.js tubes in the curve-in-motion engine and matrix spine are projected into a Canvas (geometry is rebuilt every frame on the web too), not RealityKit; glyph count is 276 per curve instead of 1,120 to hold 60 fps on a phone. Same behaviours, camera path, colours, fog.
- Matrix TV cannot pause off-screen (shared bitmap sketch); it is 260 pt tall.
- Not run on a device: Metal labs, AR, the mic labs, and all frame rates are unproven. Compile only.
- Server: none of the labs writes anything; the Fly and the models load from the gallery (public design assets).
