# LANES-plw-d: rooms 5 to 8 (lane D, branch plw-d)

IN PROGRESS (compile pending). Becomes DONE when CI is green and the lead has read this.

## What is here
- `Rooms/P5/PLWDKit.swift`: lane D's own kit (mesh builders, skins that re-saturate with `PLWLook`, the `PLWDRoom` base: glyph keys, one moment, look/exposure, light drive).
- `Rooms/P5..P8/PLWRoomP5..P8.swift`: `PLWRoomP5` Equation, `PLWRoomP6` Dwarfing, `PLWRoomP7` Transcendence, `PLWRoomP8` Launch, each `init()`, ports `start` and `exit`, route, triggers (`p5.table`, `p5.dig`, `p5.seed`, `p6.look`, `p6.carving`, `p7.d0..2`, `p7.arch`, `p7.study`, `p7.summit`, `p8.test`, `p8.study`), 3 glyph keys each (slots 0 to 2).
- `Resources/PLWorld/P5..P8`: his tile, bubbles 5 and 7, tree faces, pupil, clouds and bolt (all resized to at most 1024 px, about 1.7 MB).
- Uses the new `.lift` (P6 updraft) and `.rail` (P8 zip) commands.

## Lines the lead must wire
- `PLWRoomRegistry`: `PLWRoomP5()`, `PLWRoomP6()`, `PLWRoomP7()`, `PLWRoomP8()`.
- The resource folders are looked up by file name (bundle root first, then `PLWorld/P5` etc.), so either a group or a folder reference works.

## Placeholders owed (named so he can be asked for the art)
1. P7 stick figures (3 stelae): built from solids (head sphere, bars); his `folk/fig-*.png` are not in the reference folder.
2. P7 mauve X marks: two lit bars; his `folk/x-*.png` missing. P7 study tablet shows a glow plaque, not his mauve study art.
3. P5 seed curve under the table and P6 curve in the root: glow plaques; his `curve-comp-09.svg` / `-04.svg` are not rasterised.
4. Glyph key art: all keys are a turning gold gem (`PLWKey` / `PLWGlyph` carried in the placement); Glyph Field images are not in the repo resources.
5. P8 dome: his curve tile tinted gold on a translucent sphere; the web's "clear between the lines" needs the tile as an alpha mask.
6. All stone and plaster is one tint on his curve tile or a flat PBR colour; the Poly Haven PBR sets (about 3 m repeat) are not in the references, so no normal maps yet.
7. No fog (RealityKit has none): page colour comes from lights and `pageMix` only. Skies and moon are plain meshes (P5 crescent from two spheres).
8. The hero's curl pose in P8 and the kneel in P5 are not driven (the room cannot pose the hero); the dome and camera carry it.

## Unproven (nothing here ran on a Mac or device)
Compile status: see log below. Not proven at all: mesh winding and lighting look, collision on `generateStaticMesh` shapes with the character controller, light intensity scale (copied from WorldsKit values), texture repeat via the sampler, material APIs on device, frame cost (P7 terrain is 90 x 90 vertices, P8 cliffs 2 x 23 x 51), triangle and draw-call budgets.

## Log
- M1: kit + P5 pushed to CI (run cancelled, superseded).
- M2: rooms 6 to 8, `.lift` and `.rail` wired; compile run in progress.
