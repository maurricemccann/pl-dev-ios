DONE (wave 4, worlds). Compile check green: run 43527247771 on `wave-worlds`, publish off. Nothing here has run on a device.

# Worlds: The Haul, The Money Room, The Weight, the walk-through archive (all RealityKit, no web view)
Files: `PLDev/Sections/Worlds/` (WorldsKit, HaulWorld, WeightWorld, MoneyRoomWorld, ArchiveSpaceWorld, WorldsRoom, WorldsSystem), models `blue-pallet`, `pallet-jack`, `walking-box`, `yellow-tote` (from lane-3d) and `eyt2.usdz` (new, decimated to 3% with `scripts/glb_to_usdz_light.py`, 11.7 MB) in `PLDev/Resources/Models/`.

## Lines the lead wires
- `GalleryRooms.swift`: `.space` -> `ArchiveSpaceWorld(model: model)`; `.worlds` -> `WorldsRoom(model: model)`; the "Walk it in 3D" link in ArchiveRoom (~line 248) -> `ArchiveSpaceWorld(model: model)`; delete `GalleryRoom.worldPages`.
- Library link handler (~line 154): if `path == ["worlds", id]`, set `WorldsNav.shared.room = WorldRoom(rawValue: id)` and `GalleryNav.shared.room = .worlds`.
- App launch, beside the other Spotlight indexes: `await WorldsSpotlight.index()`. `OpenWorldIntent` is an OpenIntent (no new App Shortcut, the count stays).
- No server routes. No Info.plist lines.

## What was ported (each page read in full first)
- Haul: 24 m room, 12 framed works (same archive indices, title and year caption within 3.2 m), 4 EYT2 pallets, 2 blue pallets, 3 gold/obsidian jacks, 4 totes, gold walking box pacing the west side. Floating left-thumb stick, right-thumb look, wall bounds.
- Weight: 54 works, the page's mulberry32 seed 20260620 so the layout is the same, drift and turn, fog tint, free flight along the view, PL number caption within 4 m.
- Money Room ("The Take"): gold GlyphGuy samba, rolling bed of 1,900 bills, 210 bills and 14 coins as rigid bodies on a drifting wind with the dancer's capsule shoving them, orbiting camera with the page's tall-screen pull-back.
- Archive walk: rails camera, drag slides, pinch walks, tap opens a lightbox (image, title, PL, category, medium, share, "View in archive"), thumbnails stream within 40 m, 200 kept. Added: year chips to jump, lane legend, VoiceOver adjustable walk.
- Added everywhere: archive manifest copy kept for offline, "try again" notice, Reduce Motion stops drift and orbit, tips, haptics, Spotlight per world.

## Finding on the web page (not fixed, not mine)
`app/archive/space/SpaceClient.tsx` is stale: `CAT_X` lists six old categories (manifest now has digital, physical, seeds, finished_works, studies), and it uses `piece.n` as depth but `n` is now a per-subject counter. Live, almost every work collapses to x=0 and far back. Fix: `n = parseInt(piece.cr.slice(3))`, lanes from the real categories. The native room already does this.

## Gap check
Built: all four rooms, controls, captions, lightbox, offline copy, tips, Spotlight, VoiceOver, Reduce Motion.
Differences / unproven (no device):
- Fog is a tint on the self-lit pictures (RealityKit has no scene fog); lit props and walls have none.
- Money Room bed is merged chunks that ride the swell, bed coins omitted (falling coins kept). Light intensities are guesses and need his eye.
- Walking-box facing direction assumed (+z); jack recolour split at 42% height as the page does.
- Archive pinch direction copies the page (spread = back).
- "View in archive" opens the archive room, not pre-searched (ArchiveRoom has no query init; lead may add one).
- Widget, Live Activity, notification buttons: not fitting (places, not numbers or events); Library's cover the section.
- Sweep (WKWebView removal in Shop/Congregation/Library/Town) is the other wave-4 lane, not touched.
