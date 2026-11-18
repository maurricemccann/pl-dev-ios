WORKING (lane A: engine, hero, save, camera, palette, GlyphGirl). Milestone 1 merged by the lead (compiled, run 44243406265). Commands lift/rail/heroPose/dreamOrbVisible and GlyphGirl are committed; their compile is waiting for the API reset (10:08 PM PT).

## Lines the lead must wire (shared files I may not edit)
1. `PLWorldSection.swift`: `makeRoot` must return `PLWHome()` (my title + hero pick, `Home/PLWHome.swift`) instead of the placeholder `PLWorldHome()`. I cannot reuse the name `PLWorldHome` because that struct is declared in the lead's file; delete the placeholder struct when you switch.
2. `PLWRoomRegistry.make` (`Engine/PLWRoomRegistry.swift`, my file): add one `case` per room at merge; the comment line marks the spot. Unregistered areas load the greybox.
3. Info.plist: nothing needed for a connected pad (polled through `GCController`). `GCSupportsControllerUserInteraction` only matters for the on-screen virtual controller, which I did not build.

## Conventions the runtime gives rooms (write these into your rooms)
- `PLWFrame.position` is the hero's FEET in room-local metres (capsule centre minus 0.85). `lookDirection` is the camera's forward.
- A trigger whose id starts with `tunnel` puts the camera in first person while he is inside it (lane B names tunnel triggers that way).
- The runtime adds a static physics body next to every non-trigger `CollisionComponent` under `root` (character controller), and builds trigger volumes from `triggers`.
- A room may only complete its own moment, set its own flags and checkpoints, and collect keys it published in `glyphs`; other commands are dropped.
- Captions are dropped if longer than 140 characters or containing "manifest"; an em dash becomes a comma.
- Look: `PLWPalette.look(area, save)`; `PLWPalette.saturate(rgb, factor)` scales saturation about luminance (copy the one-liner if you prefer).

## GlyphGirl
`Resources/PLWorld/Hero/glyphgirl-v4-world.usdz`, made by `derive_glyphgirl.py` (same folder) from `glyphguy-v4-world.glb`: the `buildHer` recipe (body `rect9` and `UV SphereASSEMBLY` reshaped to a triangle, neck 0.3, flare 0.86; arm strokes `path14` and `path16` moved in to the new shoulders). Checked by a Blender render (triangle body, arms meet the shoulders).
Deliberate differences from `buildHer`: the skeleton is NOT touched and the 5 degree arm tilt is skipped, because the clip pack rewrites joint transforms, so moved or tilted bones would not survive playback and the arm strokes would detach. Cost: an arm swings about the old shoulder pivot (about 3 percent of body height off). Same joint names as GlyphGuy, so the same 16 clips play on her (unproven until run on device).

## Commands handled by the runtime
completeMoment, collect, mark, roomFlag, dream, checkpoint, camera, raiseDream, caption, lift (clamped 0 to 30 m/s^2, applied next frame), rail (2 to 64 points, speed 0.5 to 40, input locked, ends at the last point), heroPose ("curl" = tucked squash since the pack has no curl clip; "stand" clears; others ignored), dreamOrbVisible.

## Proven / unproven
PROVEN: milestone 1 Swift compiles in CI (run 44243406265). GlyphGirl mesh looks right in a Blender render.
UNPROVEN (needs a Mac or device): everything that runs. Specifically: where the capsule origin sits (assumed its centre); whether `CollisionEvents.Began` fires for the character controller entering a trigger; head-bump detection through `CharacterControllerStateComponent.velocity`; model facing (`facingOffset` in `PLWRuntime`); clip retargeting onto GlyphGirl; the feel of walk 6 / run 10.5 and the camera.
NOT BUILT: the light path that guides him back (rooms publish `route`; no renderer); glyph key art (plain gold spheres); GCVirtualController; Core Haptics beyond the app's existing `PLHaptics` and impact generators.
