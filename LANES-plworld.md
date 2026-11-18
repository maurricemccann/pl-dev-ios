# LANES-plworld: PL World native on iOS (lane "PL World iOS", branch `plworld`, worktree `C:\dev\pl-dev-ios--plworld`)

Spec: vault `Plans/SPEC — PL WORLD NATIVE ON iOS, IN PL DEV (S349).md`. His words: vault `Plans/RESEARCH — PL WORLD, HIS WORDS 10-28 TO 11-03 (S349).md` (cited below as W + date/time PT). Web base read from `pl-world-b.zip` (Babylon, `src/*.js`, RING-DESIGN.md, GAMES-MATCH.md, WORLD-NOTES.md) and the spec chain S340, S341 (DEPTH, MARBLE RUN), Section Designs (Codex S340).

## Log (dated, newest last)
- 11-17 PHASE 1 written (recon + plan). Worktree made with plain `git worktree add` because `pl-wt.sh` does not know pl-dev-ios. Archives unzipped to the lane scratchpad, nothing run from them.

## 1. The last ruled design (what he was building toward)

**One world (S347, 11-09, widget, in DEPTH spec):** the Curve Who is the ring of 11 areas inside PL World; one app. The 33 Beta Games stay rooms. **"The open world is the game, the areas are the Curve Who's story ... nothing's really locked except the customisations"** (S341, DEPTH).

**Layout** (RING-DESIGN, his drawing `reference/ring-founder-s341.png`, W 10-31 various): hub disc at the centre (green, his curve strokes as water: "black lines in my image are water", W 10-31 1:48 PM; only solid strokes), 11 page sectors round it in book order, tunnels between neighbours that shift to the next room's colour ("tunnels between areas, not thin walls", W 10-31 1:04 PM), wide outer green band, the 12th sector an open gap = entrance and open world; page 11 opens back into the hub. Each page's play fills its whole sector (story room at the heart + its three Beta Game stations, GAMES-MATCH.md). Map 0.9 scale. Hub portals are the door into story mode.

**Page rooms** (Codex Section Designs S340, Gemini refs 01-05 `reference/gemini-s340/`, sector 1 `SECTOR1-GEMINI.md` + `after-*.jpg`): 1 Birth (yellow; statue, well, hold still, the dream rises, orange tunnel) · 2 Look (ochre/red; gallery, stop and look, new drawing) · 3 Crowd (purple; modelled maze with curve-hero engraving, raise the dream, crowd parts) · 4 Hiding (grey; tunnel, dream lost, tree's concern) · 5 Equation (green; house, window, dig the dream out) · 6 Dwarfing (teal; look up, tree grins) · 7 Transcendence (indigo; crossed-out doubters, first ring) · 8 Launch (baby blue; curl, one gold bolt, no strobe) · 9 Rising (tall hill, see Paradise, descend) · 10 Homeland (garden, climb the curve-beings, lazy river) · 11 Embrace (set the dream in the patterned river, goes golden, free play opens). Free play = the Paradise hub.

**Verbs/controls (W 10-29..31):** left floating stick, right drag-look, short tap jump, ACT button for every interaction; double jump; JUMP twice then ACT = dream orb at 3x speed (S341); "controls cramped" so smaller spaced buttons (W 10-31 1:15 PM); "the controls are wonky, laggy, glitchy, very slow walk" (W 10-31 2:44 AM). **Conflict:** the spec's numbers (walk 6, run 10.5, jump peak 1.77) come from the old Three.js build (CHAPTERS S338); Babylon shipped WALK 5.0, jump 1.1 m + 0.95 double (`player.js` line 6). His standing ask is faster, not slower. Plan: 6 / 10.5 as defaults, one tuning struct, measure on his phone via the debug counter. [RULING NEEDED? no, defaults only; flagged to main.]

**Look rulings:** colour 50% vivid at start, climbing to 70% at page 10, 110% in free play (W 10-30 2:40 AM; Codex 11 "palette lifts to 110%"); one dominant page colour per area, never black, fog = page hue; "it's either clearance or black lines never both" (W 10-29 9:42 PM); "not low poly"/"quality the same everywhere" (S340); his tile on floors, original tile on walls (W 10-30 6:02 AM); curved walls with curve-hero engravings, no floating gap (W 10-30 4:28 PM, 10-31 2:25 AM); art carved INTO hills, framed windows and round doors, never posts (S341, `art-encased-founder-s341.png`); no seeing through walls (S341); keys = Glyph Field glyphs (glyph-guy, love-yourself, money, poverty-to-luxury, smiley, money-grin), seeds = small turning hearts with soft glow (S341); no glow stronger than needed, varied emission (W 10-29 6:59 PM); tree is a real tree, oversized, eyes and a grin (W 10-29 7:51 PM), behind the house (W 10-30 2:36 AM); the window looks out to the tree = "the universe" (W 10-29 6:31 PM); a light path guides back if he veers off (W 10-30 2:40 AM); tunnels first-person, walls his tiled art (W 10-30 2:36 AM); real lighting (W 10-29 8:00 PM); GlyphGuy carries nothing on his head; faceless, emotion by head shape (memory); no giants' legs (W 10-29 11:09 AM); filler = Crash Bandicoot-style small physical challenges (S341); pacing: finishing the moment opens the exit, marks optional (S341 ruling 6:40 AM, Codex psych review).

**Hub content:** hub shows his archive + PLG pieces (keeps only, never a cut; wall.json), Beta Game doors, marble run of his curves, art wall, 3 lab pieces, playground (S341 rulings 10-31). Credits last, credit scene carries the CC BY Babylon assets credit (S341).

## 2. What changes because it is native (checked against Apple RealityKit docs in phase 3 via Context7 before each use)
| Web limit | Native answer |
|---|---|
| Hand-fixed ground, steps, slopes, sticking (Havok capsule) | `CharacterControllerComponent` + `moveCharacter`, stepLimit, slopeLimit |
| Chests/glyph/room triggers by distance | `CollisionEvents.Began` trigger volumes |
| Wonky touch, cramped HUD, no pad | his stick layout + `GCVirtualController`/real pads + Core Haptics |
| Safari tab kills lost progress; PWA broke | save on every moment + `scenePhase`, SwiftData/JSON in app container |
| Streaming by chunks, lite/full modes | one tier, RealityKit entity enable/disable per sector, instancing |
| Fluid/water, god rays | ShaderGraph/CustomMaterial water, light + fog, simple shaft meshes |
| 4 mixamo clips missing | existing clips in `Resources/Models/Clips` (idle, walking, jump, 12 dances); the Mixamo motion list stays owed to him |
| Audio | AVAudioSession ambient, spatial audio; no synthesised voice |

## 3. Heroes and assets (no redrawing)
- GlyphGuy: `glyphguy-v4-world.usdz`, `glyphguy-v4.usdz`, `walking-box.usdz`, 15 clip USDZ already in PL DEV (from lane-3d). Web source `glyphguy-v4-clips.glb` (24 clips) in `pl-world.zip`.
- **GlyphGirl: NO 3D model file exists anywhere** (searched the three zips, vault, repos). What exists: her definition as CODE, `pl-curves-gallery/scripts/glyphguy/glyph-rig.js` `buildHer` (his model with a triangle body: neck 0.3, flare 0.86, arms), plus 2D sprites (`town-her-*.png`, `pl_sprite_glyphgirl_*`). Per spec I stop here: **question to main/founder: may I derive her in Blender headless from his GlyphGuy v4 using `buildHer`'s recipe (reshape `rect9` body to a triangle, keep rig and clips), or does he want to supply one?** Phase 3 ships GlyphGuy first and the pick screen with her slot until ruled.
- World pieces: Babylon web has no per-room GLBs beyond the heart (`heart1.glb`), trees (fbx), the Gemini-referenced Poly Haven PBR sets (CC0) and Babylon Assets (CC BY 4.0, 12 files). Rooms are mostly procedural meshes in `roomN.js`; native rebuilds them from the same numbers. USDZ conversion by Blender headless `--factory-startup`.

## 4. Build order (each a working build, via the S349 ship route; no publish before his rule: publish only when fully verified, `feedback-publish-only-when-fully-verified`; his session grant is "auto publish", the main session owns the call)
- P3a tile + engine: `Sections/PLWorld/` new folder; tile on home grid (needs the `SectionRegistry.swift` line, owned by lead: written below), reuse `WorldEngine`/`WorldView`/`WorldLight`/thumb controls from `WorldsKit.swift` (no edits to it).
- P3b hero pick (GlyphGuy; GlyphGirl pending ruling), character controller, camera (low, behind, slow, locked; first-person toggle for tunnels), dream orb, save, debug frame counter (reuses the "key like PL Paint").
- P4 in order: **Room 1 Birth** (fullest, the quality bar; first 90 s = statue, well, hold, dream rises) → hub disc + gap entrance + 11 tunnels (colour-shifting) → rooms 2..11 one at a time, each to its Gemini reference, each with its moment, exit gate and 3 glyph keys; Beta-Game stations and the open-world art walls last (they are the 33 games + 1,347 archive pieces: scope, see below).
- P5 review + publish.

## 5. Scope honesty (needs main's eyes)
The ruled design is very large: 11 rooms + hub + 33 game stations + the 2.5 km world + art walls. One lane/session cannot honestly finish all of it. Proposed **in-scope for acceptance 3** ("every room the plan lists as in scope"): hub + Room 1 to the full bar, then rooms 2-11 as the sector moments (one verb each, Codex designs) in order, to the depth reached; stations, archive walls, open-world chunks, marble run listed as OUT until after the 11 moments. His 11-17 words said "all go check ... what I was trying to do ... last ruled state", so I will build in the order above and publish at each verified working state, not hold for everything.

## 6. Lines the lead must wire (shared files not edited by this lane)
- `SectionRegistry.swift`: a `PLWorld` tile entry (id/label "PL World", icon, destination `PLWorldHome()`), written when P3a lands.
- Info.plist: `GCSupportsControllerUserInteraction`, game controller keys if needed.

## 7. Phase 2 plan (waits for main's go)
One new Gemini thread (Chrome, own tab, one block) briefed with: his ring drawing, hub-water, art-encased, ring map, SECTOR1 afters, S340 refs 00-05, the native constraints; ask native look per area + hub as images and text; each claim checked against pixels. Codex (headless, high) critiques this plan and the build order; findings filed in `Plans/` with what changed.

## Open items for main
1. GlyphGirl: derive from `buildHer` recipe (my recommendation) or he supplies a model?
2. Speeds: defaults 6 / 10.5 (spec) vs 5 (last Babylon build) acceptable as tunables?
3. Scope cut in section 5.
