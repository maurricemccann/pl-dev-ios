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
