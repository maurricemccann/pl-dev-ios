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

## Corrections after phase 2 (Gemini + Codex; vault Plans/ files "REVIEW — PL WORLD NATIVE, GEMINI ..." and "... CODEX ...")
- **Page hues are the shipped web PAGE array** (frozen in `PLWRing.pageHex`): C7AF52, AF6D4B, 971701, 42347F, 7174AB, 2E5A4B, 4DA6A2, 153566, 5FB1C7, 039AF3, E8B21A. My Gemini brief guessed other colours for pages 3 to 10, so **its hexes for those pages are void**; its materials and effects stay as ideas. The page-colour words in Section Designs (Codex S340) for pages 3 to 10 are stale too; the rooms' verbs and moments stand.
- **Gates (his ruling 11-17, after Codex P0): all open for testing, gated later.** One switch, `PLWGating.enforced` (default false), in the contract; moments still record completion and unlocks. RING-DESIGN "sealed until reached" and the 80% quota stay void.
- **Layout (Codex P0): 23 links**, not 11: ten neighbour tunnels, two entrance cut ends, eleven hub doors. Geometry is RING-DESIGN.md (hub r 330, moat to 366, ridge to 390, ring to 1000, page i centre angle 210+30(i-1) deg, entrance gap 165 to 195). One owner: lane B. Rooms expose ports only.
- **Order:** contract + device proof, greybox ring, integrated Birth, then parallel room production, then review. Lane A lands the runtime first; room lanes build assets and Swift against the frozen contract meanwhile and integrate when A merges.
- **Scope (RULED 11-17: "Yes, hub + 11 rooms first"):** acceptance 3 reads "the eleven moments". Next rounds, in order: the game stations, archive walls, the 2.5 km world, the marble run, fluid water.
- GlyphGirl derived from GlyphGuy v4 by the `buildHer` recipe, and speeds 6 / 10.5 as debug tunables: ruled by him (via main).

## Blueprint (frozen; every lane reads this first)

### Rules for every lane
1. Repo `C:\dev\pl-dev-ios` is PUBLIC. Make your own worktree and branch off `plworld` (its head when you start; the compile base is `fe16be3`): `git -C C:\dev\pl-dev-ios--plworld worktree add C:\dev\pl-dev-ios--plw-<x> -b plw-<x> plworld`. Work only there. Never push to origin from your worktree (this machine's local history is not safe to publish). Compile with `bash scripts/plw-compile.sh plw-<x> fe16be3` (first run `sed -i 's/\r$//' scripts/plw-compile.sh`), at most once per milestone, one at a time; read the result with `gh run view <id> -R maurricemccann/pl-dev-ios --log-failed`. Nothing here runs on a Mac or device: say plainly what is unproven.
2. No keys, tokens, addresses, names or personal data in any file or commit (`scripts/scan.sh` must pass in the clean clone). No `import PLDevCore` in app files. New Swift files in your own folder join the build automatically.
3. Touch only your files (ownership below). Never edit `Contract/PLWContract.swift`, `PLWorldSection.swift`, `SectionRegistry.swift`, another lane's folder, or `LANES-plworld.md` (the lead owns them). If you need a contract change or a shared-file line, write the exact lines in `LANES-plw-<x>.md` in your worktree and message the lead; do not work around it.
4. Reuse before building: `PLDev/Sections/Worlds/WorldsKit.swift` (WorldEngine, WorldView, WorldLight, controls helpers; read-only: copy patterns, never edit), `ThreeD/GlyphGuyRoom.swift`, `Resources/Models/*.usdz` (his GlyphGuy v4 plus 15 clips), `scripts/glb_to_usdz*.py`. Never redraw his models. New binaries (USDZ, textures) go under `PLDev/Resources/PLWorld/<your folder>/`, kept small (textures at most 1024 px, under 25 MB per lane). No new dependency without the lead's word.
5. His rulings outrank everything: read `C:\dev\plw-ref\` and the vault research file (his words). Hard rules: GlyphGuy is faceless (emotion by head shape and motion); no people mockups; never synthesise his voice; the word "manifest" never appears in copy; no em dashes in copy; times in 12-hour format; no seeing through walls; art is carved INTO hills and walls, never on posts; clearance gaps or black lines, never both; one dominant page hue per area, fog = page hue, never black; vividness is a runtime saturation factor (0.5 to 0.7, 1.0, 1.1) that rooms apply through `apply(_ look:)`.
6. Comments go at the end of a line, never before code on the same line (the "swallowed line" bug). Match the surrounding code's Swift settings.
7. Report each milestone to the lead with `SendMessage` (the lead is named **PL World iOS**) and finish with `LANES-plw-<x>.md` whose first line says DONE, with what is proven versus unproven and the exact lines the lead must wire.

### Quality bar (the same everywhere)
Real PBR (tiled sets at about 3 m per repeat), real lights, one post look, his curve tile on floors and the original tile on walls, curved walls with curve-hero engravings seated flush (no floating gap), filled worlds (no empty floor between beats), no flat-colour stand-ins, no low poly. Budget per area: at most 120k visible triangles and 150 draw calls, shared materials, one signature effect (Gemini's list in its review file). Camera: low, behind, slow, locked (first person only in tunnels); no shake, no strobe. Each room ends with a quiet afterimage and no cards in the focal area.

### References (outside git, read-only): `C:\dev\plw-ref\`
`gemini-s340/` (00 map, 01 to 15 paintings, `NN-*-spec.md` text, `babylon-build-guide.md`, `AUDIT-rooms-1-10.md`; 06 to 15 are marked UNREVIEWED: direction, not law) · `sector1/` (page 1 sector afters) · `founder/` (his drawings: ring, hub water, art encased) · `web-src/` (the Babylon source: `src/roomN.js` has each room's numbers and verbs; RING-DESIGN.md, GAMES-MATCH.md, WORLD-NOTES.md) · `models/` (`glyphguy-v4-clips.glb` 24 clips, `heart1.glb`) · `brand/` (his curve tile and comps) · the two REVIEW files. His words: vault `Plans/RESEARCH — PL WORLD, HIS WORDS 10-28 TO 11-03 (S349).md`; spec chain in vault `Plans/` (SPEC PL WORLD ON BABYLON S340, DEPTH S341, Section Designs Codex S340).

### The shared engine API
`PLDev/Sections/PLWorld/Contract/PLWContract.swift` is the API: `PLWRoom`, `PLWFrame`, `PLWCommand`, `PLWSave`, `PLWLook`, `PLWRing`. A room builds its entity tree in a local frame (`root`), publishes `ports` ("start", "exit", plus tunnel ends), `route`, `triggers` and `glyphs`, reacts in `step` and `receive`, and returns commands. It never touches the save, another room, the camera rig or the engine's frame callback. Metres, Y up, local -Z forward. Every solid piece gets a static `CollisionComponent` inside `root`; the integrator's character controller walks on them. Name your classes `PLWRoomP1` ... `PLWRoomP11` and `PLWRoomHub`, each with a no-argument `init()`; the lead adds the registry lines (`PLWRoomRegistry`, lane A's file) at merge.

### Lanes, folders, ownership
| Lane | Branch | Owns (only these) | Delivers |
|---|---|---|---|
| A engine + hero | `plw-a` | `PLWorld/Engine/**`, `PLWorld/Hero/**`, `PLWorld/Home/**`, `Resources/PLWorld/Hero/**` | The runtime: view over `WorldEngine`; `PLWRuntime` integrator (character controller, gravity, double jump, orb; left stick, right look, tap jump, ACT; haptics; GameController); camera rig; save store (atomic, on every moment and on scenePhase); palette owner producing `PLWLook`; gate evaluator; trigger plumbing (`CollisionEvents`); room loader and `PLWRoomRegistry`; debug frame counter (a key like PL Paint) with the walk 6 / run 10.5 tunables; tunnel first-person switch; the title and the hero pick (replaces `PLWorldHome` via `Home/`). GlyphGuy hero (USDZ + clips) and **GlyphGirl derived from GlyphGuy v4 with the `buildHer` recipe (`pl-curves-gallery/scripts/glyphguy/glyph-rig.js` line 67), Blender headless `--factory-startup`, sharing the 24 clips**. A built-in greybox room so the runtime runs alone. Lane A merges first (runtime + greybox). |
| B hub + layout + tunnels | `plw-b` | `PLWorld/Hub/**`, `PLWorld/Layout/**`, `Resources/PLWorld/Hub/**` | `PLWRoomHub` (the Paradise hub: green disc, his curve strokes as water, moat, 11 portals, entrance gap, the Heart; Gemini `12-paradise-hub`, `founder/hub-water`), the ring layout (places each room's root by its ports into the RING-DESIGN geometry), and **all 23 tunnels** (colour shifting from the room behind to the room ahead, first person, his tiled art on the walls). |
| C rooms 1 to 4 | `plw-c` | `PLWorld/Rooms/P1..P4/**`, `Resources/PLWorld/P1..P4/**` | `PLWRoomP1` Birth (the quality benchmark; first 90 s = statue, well, one ACT hint, the dream rises, a quiet beat), P2 Look, P3 Crowd (modelled maze), P4 Hiding. |
| D rooms 5 to 8 | `plw-d` | `PLWorld/Rooms/P5..P8/**`, `Resources/PLWorld/P5..P8/**` | P5 Equation, P6 Dwarfing, P7 Transcendence, P8 Launch. |
| E rooms 9 to 11 | `plw-e` | `PLWorld/Rooms/P9..P11/**`, `Resources/PLWorld/P9..P11/**` | P9 Rising, P10 Homeland, P11 Embrace. |
Shared helpers (trees, rock, tile materials): whoever needs one first builds it inside their own folder; no cross-lane imports (copy instead).

### Merge and verify (lead)
The lead merges lanes into `plworld`, adds the registry lines, compiles through the clean clone, shoots every room in the Simulator where CI allows, files Gemini's comparison and a Codex critique per milestone in vault `Plans/`, and hands the build to main and the founder to review before any publish.
- 11-17 PHASE 2 done: Gemini thread + Codex critique filed in vault Plans/; plan corrected; contract (Swift) + tile + blueprint committed on plworld. CI compile of contract + tile: run 44237827693.
- **Stations round (his ruling 11-17, next round, changes nothing now):** "For the 33 games just work on the ones not in pl practice". Before any station is built, put a cross-check table here: the 33 against what `PLDev/Sections/Practice/` already plays (exercise kinds and pack); build only the ones Practice does not have. Game specs: vault `Plans/SPEC — GAMES, FIRST THREE / WAVE 1-3 / ARCADE GAMES (S348)`.
- 11-17 9:03 PM lanes A-E launched (Sonnet, own worktrees C:\dev\pl-dev-ios--plw-a..e, branches plw-a..e, from plworld 018ca57); past the trust prompt per main. Contract compile CI run 44237827693 success.
