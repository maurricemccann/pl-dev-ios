IN PROGRESS (lane C, rooms 1 to 4). Milestone 1: Room 1 Birth written, compile pending.

## Room 1 Birth (`PLWorld/Rooms/P1/`, `Resources/PLWorld/P1/`)
- `PLWRoomP1` (no-arg init). Ports (room-local, facing OUT of the room): `start` (0,0,16) faces -Z; `well` (0,0,11); `exit` (0,0,-32) south tunnel end; `entry` (0,0,32) north tunnel end, rotated 180 deg. Tunnel stubs are 8 m; the layout lane continues them.
- Moment: hold ACT or stand still within 3.6 m of the well for 2.5 s; the dream rises (`raiseDream` 0...1), flies to his hands, then `dream(.carried)`, `completeMoment(.p1)`, `checkpoint(.p1, "start")`. Captions (once each): "Walk to the well." / "Hold ACT, or stand still." / "It is yours to carry."
- Three keys (ACT within 1.8 m): glyph-guy west of the plinth, love-yourself east of it, money on the west balcony (reached by a continuous curved ramp, because the controller has no mantle). Key visuals are his Glyph Field silhouettes (glyph-guy, love-yourself, money) recoloured gold, upright over a halo.
- Reaction is by distance in `step`; triggers are also published (`p1.well`, `p1.key0..2`) for the integrator, `receive` returns nothing.
- Textures are baked by a Python script (not committed) into 1024 px sets: rock (his original tile engraved), floor (PL-0004 engraved, flagstones), yellow marble, cream, sand, tile tier, his drawn face (decal with normal), halo, shaft. 3.9 MB.
- `apply(_ look:)`: scales the stone tints' chroma and the light colours by saturation, light intensity by exposure. No fog API in the room, so fog hue is the integrator's.

## Proven / unproven
PHONE-REVIEW ITEMS: light levels, collision feel, face decal orientation. Nothing runs here. Unproven until a CI compile and a device: every RealityKit API spelling (compile), light lumens in `Tune` (guessed), the V orientation of the face decal (`1 - v` assumed), collision feel on the ramp and sockets, triangle and draw-call budget (about 60k triangles, about 25 draw calls estimated).

## Lines the lead must wire
- `PLWRoomRegistry`: `.p1: PLWRoomP1()`.

## Room 2 Look (`PLWorld/Rooms/P2/`, `Resources/PLWorld/P2/`)
- `PLWRoomP2`. The room starts at the origin where Room 1's tunnel arrives and runs south: S-curve canyon about 63 m, 18 m walls displaced by his tile as relief (the 12 SVG comps were not usable: several carry filled backgrounds, so the tile is the relief source), woven tile path, 10 m clearing, red-lined exit tunnel. Ports (facing out): `start` (0,0,-1), `entry` (0,0,0) rotated 180 deg, `exit` at the exit tunnel end.
- Moment: hold ACT within 3 m of the clearing centre for 3 s. The camera goes over the shoulder via `.camera` (weight 0 to 1), the white-on-indigo Curve ground spreads out as 1 m rings to 18 m, then `completeMoment(.p2)`. Keys: smiley, money, glyph-guy (gold silhouettes, ACT).
- Left out: the web's light-rail ride (the contract has no ride verb; the floor is always the way). Walls carry no vertex colour (RealityKit meshes have none), so the carved grooves read through the normal map and light only.
- Phone-review items: sun and fill lumens (`Tune`), relief legibility at phone scale, camera blend, collision on the carved walls.
- Reuses lane C's `P1Mesh` and `P1Materials.load`; lines for the lead: `PLWRoomRegistry` `.p2: PLWRoomP2()`.

## Room 3 Crowd (`PLWorld/Rooms/P3/`, `Resources/PLWorld/P3/`)
- `PLWRoomP3` + `P3Maze` (the web's seeded maze, same generator and seed 3303: 12 x 8 cells of 5 m, one true way, 8 packed dead ends, 2 gates, a secret). Local origin = where room 2's tunnel arrives, rows run toward -Z. Ports (facing out): `start`, `entry`, `gate1` (checkpoint after the first gate), `exit` (end of the purple tunnel, 10 m).
- Brick walls (one static mesh), curve hero engraved into every wall by a second alpha-tested skin (baked 15-curve panel), his woven tile only on the true way, cobble elsewhere, brick arches on the straights, a dark lid and skirt so no sky shows, the mossy bench and folded drawing in the deepest dead end, 36 + 48 of his stick people (plate 3 figures, ink and paper border baked) that face him and sway.
- Moment: hold ACT within 9 m of a gate for 1.8 s and its nine doubters step to the walls (the invisible blocker across the lane is removed); `roomFlag gate0/gate1`; the last gate gives `completeMoment(.p3)`. `raiseDream` tracks the hold. Dead ends are blocked by invisible boxes under the crowd.
- Left out: the low arch crouch and the wall walk (no crouch or climb verb), the carved silhouette slices behind each figure. Keys: love-yourself and poverty-to-luxury (love-yourself art stands in, no separate silhouette file) in the two courtyards, money by the bench.
- Phone-review items: lumens, the unlit paper-white faces against dark brick, gate blocker feel.

## Room 4 Hiding (`PLWorld/Rooms/P4/`, `Resources/PLWorld/P4/`)
- `PLWRoomP4`. Origin = where room 3's purple tunnel ends. 16 m curving passage dropping 1.5 m (purple to grey in four tinted segments), 28 m grove, the 14 m tree with his plate-4 face (pupils follow him), hollow, guard branch, six roots in sockets, petrified-root exit and an 8 m lining to silver-blue. Ports (facing out): `start`, `entry`, `grove`, `exit`. Leaves are baked into the floor texture (RealityKit has no thin instancing).
- Moment: step within 2 m of the spot before the hollow: `dream(.buried)`, the dream flies into the hollow, its gold goes out, the guard branch bends, a camera frame for 3 s, then `completeMoment(.p4)`, `roomFlag hidden`, `checkpoint grove`. It runs whether or not the dream was carried, so the room can be tested alone.
- Secret: his tile carved on a stone slab under the left root (the web used curve-comp-05, an unusable SVG). Keys: glyph-guy in the passage, smiley at the grove's west, love-yourself by the secret.
- Phone-review items: lumens, the bark grain scale, pupil travel, camera framing.

## Shared notes
- The runtime (lane A) draws its own small gold sphere at each glyph and collects it on ACT within 1.8 m; the rooms draw the glyph silhouette over it. The lead may drop the runtime sphere when a room supplies art, or I can drop the room art: say which.
- Every tiled texture is sampled with an explicit repeat sampler (`P1Materials.tx`), because RealityKit's default wrap mode is not documented.
- Lines for the lead: `PLWRoomRegistry` `.p1: PLWRoomP1()`, `.p2: PLWRoomP2()`, `.p3: PLWRoomP3()`, `.p4: PLWRoomP4()`.
