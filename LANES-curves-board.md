DONE. Curves board lane, branch `curves-board`, S350·3b7f. Compiles on CI (publish=false); nothing run on a device.

## What was built
- `PLDev/Sections/CurvesLibrary/CurvesLibrarySection.swift` (new): section "Curves Library" (id `curveslibrary`), a room list with one row, Private board. A marked MERGE POINT comment holds the place for the `CurvesPackRoom` row; that type is not referenced here.
- `PLDev/Sections/CurvesLibrary/PrivateBoardRoom.swift` (new): `PrivateBoardRoom`, ported from `pl-curves-gallery/app/manifestation-preview/page.tsx`. Four tabs (Home, Pipeline, Signals, More), the milestone banner, The Standing with its four quarter bars, eight stat tiles, three line charts (same series, same 280x72 box math), the panels and doors, every figure and word copied. Count-up (1.1 s ease-out cubic) by clock; reduce-motion shows the final value. Page keeps its own cream ground in both appearances.
- `PLDev/Services/SectionRegistry.swift`: one line, `CurvesLibrarySection.self` added to the list (the one registration place).

## Tested
- CI `build.yml --ref curves-board -f publish=false`: run 44679903081 FAILED (one error: `CountText` Animatable conformance, Swift 6 isolation). Fixed; run 44680430543 `** BUILD SUCCEEDED **`, job green, no `error:` lines in the log. The "BUILD FAILED" strings in that log are the workflow's own echo text.
- No test cases exist for this room and none ran.

## Not tested
- Never seen on a screen: layout at 390 pt, the tab bar over the home indicator, dark-mode appearance of the nav bar, Dynamic Type at large sizes, the hand font before it loads (falls back to serif italic).
- Compared to the page by reading its source only, not side by side.

## Departures from the page (on purpose)
- Text under 11 pt raised to 11 pt (page uses 0.5 to 0.68 rem). Tab labels, tile labels and meta lines are therefore a little larger than on the web.
- Native nav bar and bottom tab bar instead of the page's fixed overlay; no hover glow or electric border; the page's `o-veil`/`o-rise` entrance is a plain fade.
- Cormorant, JetBrains Mono and DM Sans are the system serif, monospaced and sans (the same stand-ins the Gallery skin uses); his hand font is `plHand`.
- The Doors on the More tab do nothing, as on the page.

## Lines the lead must change in files I do not own
- At merge, add the `CurvesPackRoom` row at the MERGE POINT comment in `CurvesLibrarySection.swift` (that file is mine; the pack lane must not edit it).
- The registry line may conflict with the other lanes' edits to `SectionRegistry.swift`; keep both entries.

## Assets not found
None needed. No image, font or endpoint was used beyond his hand font already in the app.
