DONE (extras lane, branch `wave-extras`). Compile check (run 43532342673, publish off): the only error left is NOT in my files: `PLDev/Sections/House/HouseCalendar.swift:136` `HouseCalendarView.Drop` has no member `fulfilled_at` (from the base the branch was cut from; the lead's file). Nothing here has run on a device.

# Built
1. **Town: GlyphGirl visitors + VT323.** `Town/TownPainter.swift`: `TownSprites` now bakes the model twice; the second pass runs a port of the web's `buildHer` (`scripts/glyphguy/glyph-rig.js`: neck 0.3, flare 0.86, armGap 1.3) on the USD mesh vertices in world space (`rect9` body and `UV_Sphere` parts narrowed to the triangle, `path14`/`path16` arm strokes slid in), stored as `her-down/left/right`. `TownScene.swift` gives role `visitor` those frames. If her parts are not found she stays him, as on the web before hers bakes. VT323 (`Town/vt323.ttf`, from `pl-design-kit/fonts/house/`) registers at first use (`TownFace`, no Info.plist change); chips, HUD, sign text, bubble and board labels use it at 1.5x size; Menlo stands in if the file fails.
2. **Worlds: View in archive.** `ArchiveRoom(model:query:)` (Library/GalleryRooms.swift) opens already searched; the lightbox button passes the piece's PL number, the "Archive" chip passes none.
3. **GlyphBot: glass look.** `GlyphBotStage.swift`: every part of the seated GlyphGuy wears a `PhysicallyBasedMaterial` (roughness 0.32, clearcoat 1 at 0.04, specular 1, tint 0xcfe2ff, opacity 0.42) plus the web's face light from the camera.
4. **Lane notes read.** Remaining "not built" items do not fit: the lab clip buttons (the web room has none), Live Activity/notifications (places, not events), the R1 kiosk modes, Press Start 2P (VT323 is the kit's pixel face).

# Unproven (no device)
- Her body: the vertex edit assumes the converted USD kept the mesh names `rect9`, `path14`, `path16`, `UV_Sphere*` (the strings are in the usdc) and that the sprite pose is the rest pose. The web also tilts the arm bones, which its clip overrides; the rest bake does not. Look at the visitors' silhouette first.
- Glass: RealityKit has no transmission, so it is a tinted translucent material; overlapping parts may sort oddly. Opacity and light intensities are guesses for his eye.
- VT323 sizes (1.5x) are by eye against Press Start 2P.

# Not built, with reason
- Town walk/dance frame animation: the web bakes a clip pack; no walking clip is in `Resources/Models/Clips`.

# Lines the lead must wire
None. No server routes, no shared files touched. Merge note: `ArchiveRoom.init(model:query:)` keeps the old call sites valid.
