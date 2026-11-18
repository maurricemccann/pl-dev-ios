DONE: lane B first pass (hub, ring layout, all 23 tunnels). COMPILES (CI run 44249311690 on branch `plw-b-ci`, base 018ca57, success). Not run on a device or Simulator.

Take branch `plw-b-ci` (my four commits only, on 018ca57, no merge). `plw-b` is the same plus a merge of plworld (lane A runtime) and may conflict with the CI base.

# LANES-plw-b: hub, ring layout, 23 tunnels

## Files (mine only)
- `Layout/PLWLayout.swift`: `PLWLayout.roomTransform(page:)` (origin at entry lip C - 30T, local -Z along T), `place(room, under:)`, `toWorld/toLocal`, `area(at:)` (hub, entrance and outer band = `.hub`), `links` (23 `PLWLink`, each with a `PLWGate`), `link(containing:)` (oriented volume + progress t, for the first-person switch), `selfCheck()` (returns failures; not yet called anywhere).
- `Layout/PLWTunnels.swift`: all 23 arched tunnels (page 6 m x 5 m, hub doors 8 m x 6 m), one wash t: hold 15%, ease, hold 15%, his tile on the walls, one light each, seal at the destination mouth when the gate is shut, `sync(save)`, `stream(around:)`.
- `Layout/PLWRingWorld.swift`: eleven sector floors in `PLWRing.pageHex`, green entrance wedge and outer band, 12 boundary ridges (24 m thick, 10 m high, cut by their tunnel, lintel above), outer ridge closed except the gap. `apply(saturation:)`, `sync(save)`.
- `Layout/PLWGeometry.swift`: ring maths, mesh builder (quads wound to their normals), tint book (re-tints on saturation), static-collision helper.
- `Hub/PLWRoomHub.swift`: `PLWRoomHub` (disc r 330 with his curve tile, moat 330-366 with ramped bed, 36 m south causeway, inner ridge 366-390 with 11 door gaps and lintels, page-coloured spokes and mats, gold pedestal, Heart from `heart1.usdz` about 6 m turning, one warm light). Ports: start, gap, exit, door1...door11. Triggers: hub.arrive, hub.door.N (checkpoints).
- `Resources/PLWorld/Hub/plw-hub-tile.png`: his curve tile, 1024 px, 71 KB.

## Wiring for the lead / lane A
1. `PLWRoomRegistry`: `PLWRoomHub()` for `.hub`.
2. Runtime: one `PLWRingWorld()`; `await ring.load()`; add `ring.root` to the scene; for each room `PLWLayout.place(room, under: ring.root)` (hub stays at the origin; page rooms need `start` at local origin, forward -Z to the centrepiece). Each frame `ring.tunnels.stream(around: playerWorld)`; on save change `ring.sync(save)`; on look change `ring.apply(saturation: look.saturation)`.
3. First person: `PLWLayout.link(containing: playerWorld)` non-nil means inside a tunnel; keep the last area while inside.
4. Ports named in the gates: page rooms need "start" and "exit" only; hub door and gap ports are mine.

## Unproven (compiled, never run)
Compile is proven (CI 44249311690); behaviour is not. Not checked on device: collision of static-mesh shapes (`generateStaticMesh` on 330-1 degree revolves), tile repeat on the walls (sampler), lighting and the 23 point lights (stream limits them), draw calls, the Heart orientation of `heart1.usdz`, face winding (quads are wound to their normals, still to be seen).

## Not built / choices
- Hub water: his strokes are the tile's black strokes on the green disc (tile repeat `PLWRoomHub.strokeMetres` = 110 m, my guess, tune against his drawing); not carved or reflective water.
- No tunnel mouth rounding or distinct per-tunnel portal art (only the lintel); no page landmarks at r 430, no stations, no sector roads: next rounds.
- Sector floors are flat colour, not rooms' own ground; rooms C-E own what stands inside.
- Gating: `PLWGating.enforced` false means every seal stays off.

## Fit with lane A's runtime (read after merging plworld)
The runtime loads ONE room at a time (`PLWRoomRegistry.make`, `engine.add(r.root)`), so `PLWRoomHub` works alone at the origin. The ring (`PLWRingWorld`, tunnels, other rooms placed round it) is not instantiated by it yet: that is the integrator step in Wiring 2. The runtime's `solidify` leaves my bodies as they are (I already set static bodies).
