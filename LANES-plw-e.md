STATUS: WRITTEN, NOT COMPILED (CI compile blocked by the scan on scripts/plw-compile.sh, lead's file). Final line DONE is added when the compile is green.

# LANES-plw-e: rooms 9 (Rising), 10 (Homeland), 11 (Embrace)

Files (all mine): `PLDev/Sections/PLWorld/Rooms/P9/{PLWEKit,PLWRoomP9}.swift`, `Rooms/P10/PLWRoomP10.swift`, `Rooms/P11/PLWRoomP11.swift`; `PLDev/Resources/PLWorld/P9/plwe-curve-tile.png` (his tile, 1024 px, 71 KB), `P10/plwe-sun.png` (43 KB). Texture names are `plwe-` prefixed because the Xcode folder group flattens into one bundle root.
`PLWEKit.swift` is the shared kit (meshes by MeshDescriptor, PBR materials, static collision, a `PLWEBaseRoom` class that holds the look, glyph keys, restore, unload). It lives in P9 because that is the first of my folders; the three rooms subclass it.

## Wire (lead)
- Registry lines (lane A's `PLWRoomRegistry`): `PLWRoomP9()`, `PLWRoomP10()`, `PLWRoomP11()` (each a no-argument init, @MainActor).
- Ports. P9 and P10: "start" at the origin facing -Z, "exit" at z = -64 (P9) and z = -42 (P10), facing -Z, at the doorway. Doorway = half-ellipse mouth 4.5 wide by 4.5 high (the web's), so the tunnel must start with that section. P11: "start" at the origin; "exit" = the middle far mouth (z = -44, facing -Z, 6 wide by 5.2 high); "forest" and "luxe" are the side mouths, rotated to face out.
- P11 side mouths stay sealed and glowing (`PLWRoomP11.openSideMouths = false`). Only the middle one opens at the embrace. If the three should all lead somewhere, lane B attaches tunnels to "forest" and "luxe" and the flag flips.
- Rooms never build tunnels or the sky: no sky dome (it would show in neighbouring sectors); the engine owns sky and fog (`look.fogRGB`).

## What each room does
- P9: crater of pale stone in the page hue (5FB1C7) round his indigo curve hill; a gold line up the slope; the summit lifts the dream (`raiseDream`, camera pull-back, valley grey to colour, `completeMoment(.p9)` at 4.5 s). Secret: his curve in the summit stone (ACT, `mark("p9.secret")`). Hill profile eased to a 36 degree steepest slope: **lane A's character controller `slopeLimit` must allow 36 degrees**.
- P10: oval garden, cliffs in the page blue (039AF3 look), seven gold curve-beings (nearest leans and warms), river, curve-tile path, stone bridge, his sun. Stepping on the bridge: sun brightens, all beings turn, low camera, `completeMoment(.p10)` at 4 s. Secret in the cliff (`mark("p10.secret")`).
- P11: berm grotto in the page gold (E8B21A), cyan pool, mossy pier. At the pier end, hold still 1 s or ACT: `dream(.embraced)`, the pearl arcs onto the water, seven gold ribbons rise, camera, `completeMoment(.p11)` at 6 s.
- Every room: 3 glyph keys (turning gold tokens, collected with ACT near them -> `collect(key)`; hidden on restore), a route, two triggers, a checkpoint on first step. Moments are detected in `step` by position AND by the trigger events, both idempotent, so trigger plumbing is not required for the rooms to work.
- Page hues come from `look.pageRGB`; vividness is `look.saturation` applied to every colour, never a multiply toward black; exposure scales the room's lights. His curve tile is recoloured on the CPU (512 px) and rebuilt when saturation moves.

## Contract changes / extras wanted (not made; for the lead)
1. A hero pose command (curl into the cyan ball on the P9 slope, uncurl at the summit) does not exist in `PLWCommand`. P9 has no ball. Proposed: `case heroPose(String)`.
2. A command or flag to place the dream orb (P11 uses its own pearl and sends `dream(.embraced)`; the integrator's carried orb must hide on that).
3. Glyph key visuals: his Glyph Field art is not in this repo (only money-field.png). Keys are gold coin tokens until it is wired.

## Proven versus unproven
- Proven: nothing yet. Not compiled, not run on a Mac or device. Written against Apple's RealityKit docs (checked with Context7: MeshDescriptor, MeshResource.generate, ShapeResource.generateStaticMesh (needs the static PhysicsBodyComponent, which the kit adds), PhysicallyBasedMaterial, light components, TextureResource image/file initialisers).
- Unproven: every Swift line compiles; mesh winding and normals face the right way (checked by hand); texture tiling beyond 0 to 1 repeats; light intensities (starting values: sun 2400 to 3200 lux, points 40k to 60k lumens) look right; frame cost and the 120k triangle / 150 draw call budgets (estimate: P9 about 40k tris, P10 about 45k, P11 about 25k, many separate entities so draw calls are the risk); static collision of every piece; the bridge and the slope are walkable; the beings' feet colliders.
- Owed against the quality bar: real PBR texture sets (Poly Haven CC0 rock, grass, bark) are not in the reference folder, so surfaces are colour + roughness with geometric relief only; shadows are on for the sun only; river and pool do not move; no GPU particles; no ShaderGraph water. Everything is lane-E-local and swappable.
