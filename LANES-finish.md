DONE (finish lane, branch wave-finish; compile-check run 43539487119 green, unsigned, publish=false)

## Built
1. **Town walk and dance (native, his real frames).** Baked offline by running the web's own `bakeGlyphRaw` (three.js, `glyphguy-v4-world.glb` + `glyphguy-v4-clips.glb`, same lights, camera, yaw, arm flag) in headless Chrome. Four grey sheets, 390 KB total, in `PLDev/Resources/Models/Clips/town-{him,her}-{walk,dance}.png` (R = light, G = arm flag, A = silhouette; 96x132 frames; walk rows down/left/right/up = 8 stride + 4 breath, dance = 12). `TownSprites` (TownPainter.swift) now runs the web's `colorize` (6-tone ramp, Bayer dither, outline, glint) per person on demand, cached; the SceneKit three-turn bake and the colour-blend are gone. `TownScene.step`: stride while moving (step += dt*11, 8 frames), 4-frame breath standing, his dance clip for 3.2 s on a task-done celebration (fireworks moment), bob removed. Reduce Motion: standing frame, no stride, no dance.
2. **The Curve.** `Shop/SiteCurve.swift`: `GoldCurves.tsx` ported line for line (15 cubics, 24-point Verlet ropes, finger push, destination-out channel, thin-first draw order, DEFAULT_GOLD) in SwiftUI `TimelineView(.animation)` + `Canvas`, full screen on black, ticks at the web's 60/s pace on ProMotion. Reduce Motion = one still frame. Reached from Shop > More > "The Curve" and by `pldev://section/shop/curve` (new `ShopRoom.curve`).
3. **The preview.** `Practice/PracticeVision.swift`: `/manifestation-preview` natively, House look (PLOS skin, OSHeader/OSCard/OSRow, glass tab bar Home/Pipeline/Signals/More), same layout and copy, count-ups, trend charts. Reached from a "Vision preview" card on Practice > Trends and `pldev://section/practice/preview` (new `PracticeRoom.preview`). Every figure is hardcoded by design; nothing reads a server. It labels itself: a "A vision · not live data" pill under the header and the web's own footer line; the one web badge reading "live" (Recent Signals) reads "vision" here (the one copy change).

## Gap check / not done
- **The widget tap:** there is no curve widget (the Library widget is "Curate", tap = curate; the Site widget tap = shop). I did not repoint either: that would remove a real route. If you want a tap to the curve, set `.widgetURL("pldev://section/shop/curve")` on whichever widget, one line.
- Fallback (sheet unreadable) sprites are plain white, untinted. Not reachable unless the bundle is broken.
- Unproven on device (no device here): the destination-out channel look in `Canvas`, ProMotion pacing, sprite colour parity with the web at 40x56 pt. Compile only.
- The made-up figures are now in a public repo (the page is already public on the gallery). Your call if you'd rather not.
- Dance only plays for the gold session figure on celebration; the web town has no dance (the clip is the R1 lock-face one).

## Shared-file lines for the lead
None needed. All edits inside Town, Shop (SiteCurve.swift + ShopSystem.swift rooms) and Practice (PracticeSection/Trends/Vision).
