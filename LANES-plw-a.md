WORKING (lane A: engine, hero, save, camera, palette, GlyphGirl). Milestone 1: runtime + greybox written, compile pending.

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

## Proven / unproven
Nothing here has run (no Mac, no device). See the milestone log below.
