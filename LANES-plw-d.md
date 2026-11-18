# LANES-plw-d: rooms 5 to 8 (lane D, branch plw-d)

DONE. Lane D, rooms 5 to 8, compiled green in CI (run 44249394152, everything committed, base 018ca57). Nothing has run on a Mac or device.


## What is here
- `Rooms/P5/PLWDKit.swift`: lane D's own kit (mesh builders, skins that re-saturate with `PLWLook`, the `PLWDRoom` base: glyph keys, one moment, look and exposure, light drive).
- `Rooms/P5..P8/PLWRoomP5..P8.swift`: `PLWRoomP5` Equation, `PLWRoomP6` Dwarfing, `PLWRoomP7` Transcendence, `PLWRoomP8` Launch, each with `init()`, ports `start` and `exit`, route, triggers (`p5.table`, `p5.dig`, `p5.seed`, `p6.look`, `p6.carving`, `p7.d0..2`, `p7.arch`, `p7.study`, `p7.summit`, `p8.test`, `p8.study`), 3 glyph keys each (slots 0 to 2).
- `Resources/PLWorld/P5..P8`: his tile, bubbles 5 and 7, tree faces, pupil, clouds and bolt (resized to at most 1024 px), plus the lifted art below.
- Uses `.lift` (P6 updraft, hold JUMP in the green column) and `.rail` (P8 zip, hold ACT at either end of the gold curve).

## Lines the lead must wire
- `PLWRoomRegistry`: `PLWRoomP5()`, `PLWRoomP6()`, `PLWRoomP7()`, `PLWRoomP8()`.
- Resource files are found by file name (bundle root first, then `PLWorld/P5` etc.), so a group or a folder reference both work.
- The contract and `scripts/plw-compile.sh` in this worktree are refreshed copies from `plworld`, left uncommitted on purpose.

## Art lifted from his files (the lead confirms each with main before anything ships; all small, under 200 KB each folder of crops)
| File (in `Resources/PLWorld/`) | Source | What |
|---|---|---|
| `P7/plw-fig-1.png`, `-2`, `-3` | lifted from plate 03 (Curve Who) | three of the small stick figures, cropped with their paper, line untouched, downscaled |
| `P7/plw-x-1.png`, `-2`, `-3` | lifted from plate 07 | his three mauve X marks, colour-masked to alpha, line untouched; `-2` also stands as the P7 study tablet |
| `P5/plw-carve5.png` | `curve-comp-09.svg` | his curve rasterised (ink to alpha), the carved seed under the P5 table |
| `P6/plw-carve6.png` | `curve-comp-04.svg` | his curve rasterised, carved in the P6 root |
| `P5/plw-key-glyph-guy.png`, `-love-yourself`, `-money`, `-smiley` | `pl-headless/public/glyphs` | four Glyph Field glyphs, 256 px, used as glyph keys |
| `P5/plw-key-poverty-to-luxury.png` | `pl-curves-gallery/public/glyphs/poverty-to-luxury.png` | glyph key (P7 slot 0), 512 px |
| `P5/plw-key-money-grin.png` | `pl-headless/public/emblems/money-grin.png` | glyph key (P8 slot 2), 512 px |
| `P5/plw-tile.png`, `plw-bubble5`, `plw-treeface5`, `plw-pupil`; `P6/plw-treeface6`; `P7/plw-bubble7`; `P8/plw-bolt8`, `plw-cloud8a`, `plw-cloud8b` | `plw-ref/brand` | his tile, bubbles, tree faces, clouds and bolt, as the web build used them |

## Still owed (named so he can be asked)
1. Glyph keys: all six now have art (the kit still falls back to a gold gem if one is missing).
2. P7 X marks fade in; the web's stroke-by-stroke wipe is not done.
3. P8 dome: his tile tinted gold on a translucent sphere; "clear between the lines" needs the tile as an alpha mask.
4. All stone, plaster and rock are one tint or his curve tile; the Poly Haven PBR sets (about 3 m repeat) are not in the references, so no normal maps yet.
5. No fog in RealityKit: page colour comes from lights and `pageMix` only. Skies and the P5 moon are plain meshes.
6. The hero's curl pose (P8) and kneel (P5) are not driven (a room cannot pose the hero); the dome and camera carry it. The P5 / P6 / P7 / P8 rings of the dream (the persistent P7 ring) live only while the room is loaded; the room sets the `ring` room flag.

## Unproven (nothing here ran on a Mac or device)
Compiled green; not proven at all: mesh winding and the look, collision on `generateStaticMesh` shapes with the character controller, light intensity scale (copied from WorldsKit values), texture repeat via the sampler, material APIs on device, frame cost (P7 terrain 91 x 91 vertices, P8 cliffs 2 x 23 x 51), triangle and draw-call budgets (not measured).

## Log
- M1 (kit + P5): CI run cancelled, superseded.
- M2 (rooms 6 to 8, `.lift` and `.rail`): run 44243648896 showed one error (an opacity literal, fixed); run 44244512279 result was never read (API rate limit).
- M3 (his art lifted in, keys as glyph pictures, all six glyphs): CI run 44249394152 built green. Compile only, not run.
