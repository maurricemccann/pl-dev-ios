DONE (wave 2, glyphbot lane, branch `wave-glyphbot`; compile check green, run 43465215287)

# GlyphBot (S348·9a3e, 11-13)

## What this lane changed
The app already had Ask, Sit and Record (lane B), in the pl-os skin (`GlyphBotSkin.swift`). Reading the live room's code (`pl-os components/GlyphRoom.tsx`, `GlyphGuy3D.tsx`) showed one real gap: the web room is a stage, his GlyphGuy seated at the left beside a speech bubble, and the app had only a thread. Built:
- `GlyphBotStage.swift` (new): his GlyphGuy v4 seated, in RealityKit (a non-AR `ARView`, clear background), breathing (the web's sine on position and roll), warm key, cool fill and rim lights, a gold aura that brightens while the room is speaking. Reduce Motion stops the breathing. If the model is missing it shows a seated-figure symbol, never a blank.
- `glyphbot-sitting.usdz` (new, 12 MB): `pl-os/public/glyphguy/sitting.glb` (his crowned v4 in the seated pose) converted with Blender 5.1 headless (`--factory-startup`, `scripts/glb_to_usdz.py` from `lane-3d`). His model, never redrawn; it is a public design asset (his ruling 11-13), so it sits in the repo like `town-glyphguy.usdz`.
- Ask tab rebuilt as the web room: stage on top (figure 112 x 176 and the latest answer in the room's bubble with the tail corner on the left, typewriter with Reduce Motion respected, mono source chips `source · score` once typed, three pulsing dots while the Oracle thinks), then the earlier turns as the thread, then the `›` prompt line. The greeting "Ask. I answer from the practice." shows when nothing has been asked. Touch and hold on any answer (including the stage bubble): Sources, Hear it, Copy.
- `TypewriterText` gained `onDone`, so the aura follows the real end of the typing.

## Tests
- Compile: `gh workflow run build.yml --ref wave-glyphbot -f publish=false`, green (run 43465215287). The first run failed on `RealityViewEnvironment.background` (not an iOS API); fixed by the `ARView` route.
- Live, read-only, done this lane (the one test lane B was blocked on): `GET /api/r1/interview/state` with the interview key from the config, read in a script, never printed: 200, `{ok, bank{asked:5,total:501,next_round}, coverage{8 domains}, recent[30]{id,answer,at,domain,question(null)}}`. Every field decodes into `GlyphBot.StateReply` (`question` is null in real rows: the Swift type is optional, correct). Note: the route answers 403 to a default Python user agent; a normal client UA is fine (URLSession sends one).
- Not written live, on purpose: `/api/r1/interview/turn` and `speak` (they write into his interview record and spend the interviewer), `glyphbot-sync` (lane B proved auth and validation).

## Unproven (no device)
1. The seated pose: the recline lives in the GLB's single-frame clip; the code plays `availableAnimations.first` before measuring, as the web does. If Blender's USD export dropped the clip, the figure would show in his bind pose. First thing to look at on the phone.
2. The clear background of the `ARView` over the dark ground, and the framing (sphere fit, camera at 2.6, fov 33) against the web's.
3. The figure uses the model's own materials (v4 is already house gold). The web's "glass" look (`glyphLook`) is a three.js shader and is not ported.

## Gap check (web room and interviewer, each built or not)
- Oracle room: stage + bubble + chips + typewriter + thread + prompt line + offline cache + doctrine fallback + sync + online dot: built. "‹ board": the navigation bar's back, inside the page.
- Interviewer (Sit): domain, pressure, length, go deeper, free talk, continue, nothing sent until Send, failed send keeps the answer: built (lane B), state route now tested live.
- Record: coverage per domain, bank, recent answers, Oracle sync count: built, shape tested live.
- Not built: the lab's clip buttons inside the room (the web room does not have them; the toolbar figure still opens the gallery's `/lab/glyphbot` page, and the 3D lane's native `GlyphGuyRoom` on `lane-3d` replaces it at merge); the web "glass" look; a notification (GlyphBot never speaks first).
- Apple add-ons unchanged: widgets, Live Activity (sitting), Siri phrases, Spotlight, tips, deep links (`pldev://section/glyphbot/<ask|interview|freetalk|record>`).
- Voice: no synthesis of his voice; "Hear it" is the interviewer's own voice (Aura).

## Lines the lead must wire
Nothing new beyond lane B's list in `LANES-practice.md` (registry entry, `interview` origin and key in the config, widget bundle, shortcuts, microphone text). If `lane-3d` merges: its `ThreeD/GlyphGuyRoom.swift` could replace the toolbar's `GalleryCanvas(path: "lab/glyphbot")` link in `GlyphBotView` (one line).
## Server routes needed
None.
