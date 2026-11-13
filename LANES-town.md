DONE (town lane, wave 1). Compile check green: run 43462824940 on `wave-town` (publish=false). Nothing here has run on a device.

# What I built (`PLDev/Sections/Town/`)
The pixel town, native, matching the web page `/town` (read from `app/town/page.tsx`; the page sits behind the gallery unlock, so no screenshot: code read instead, per rule 0).
- `TownScene.swift` (SpriteKit): the gold GlyphGuy walks to each call's building, steps in at the door, a warm window glows; townspeople by role (open stroll and chat, "!" for waiting on him, "X" under the red watchtower lamp, week-old ones big and red in the stale lot); visitors on the orange cart at the dock; ghosts replay past routes; lore people in the library; pigeon on deploy/send; HOME lantern pulse on ask; sparks when a task flips to done; speech bubble per call; CLOUD board (next scheduled run) and its tap; sky and lights follow the real sun.
- `TownSection.swift`: header with the way home inside the page, chips TASKS/LIVE/LORE, SUN (auto/day/dusk/night/dawn), CAM auto/free, SND/MUTE, LIST; HUD (open, done, calls, light); mini-map (tap/drag jumps); typed dialog (tap finishes, tap closes); done-this-session chips; stale-feed banner; error line; 10 s poll; screen stays awake; left-edge swipe back kept. LIST sheet = the whole town as text (VoiceOver, reading, jump to a building).
- `TownSkin.swift` (page tokens, chip style), `TownSound.swift` (wind, crickets after dark, made live), `TownData.swift`, `TownPainter.swift` (his GlyphGuy baked from `town-glyphguy.usdz`, never redrawn; plain fallback figure only if the model cannot load), `TownSystem.swift` (rooms, Spotlight index "town", `OpenTownRoomIntent`, `TownStatusIntent`, widget numbers), `TownTips.swift`.
- `Shared/TownGlance.swift`, `PLDevWidgets/TownWidget.swift` (small, medium, lock rectangular and circular).
- Server side: only read of `GET api/town` on the gallery, tested live with the config key (never printed): ok, live, schedule, ghosts present, tasks empty at the time.

# Gap check
Built: every web control and behaviour above; deep links `pldev://section/town/<tasks|live|lore|building id>`; Spotlight rooms; Siri status (speaks every count); widget; tip; haptics; Reduce Motion.
Not built, with reason:
- Live Activity: not fitting. The session beat has no push channel to the phone, so an activity could not update in the background and would go stale.
- Notification buttons: not fitting. Town raises no notices; House already notifies on what waits on him.
- Press Start 2P face: not bundled; Menlo bold stands in.
- GlyphGirl for visitors: the web bakes a second model; I only have GlyphGuy's, so visitors are the orange-tinted GlyphGuy.
- Walk/dance frame animation: web bakes clips; native uses three baked turns plus a bob.
- The R1 `?r1` / `?full` kiosk modes: not applicable on the phone.
Unproven: SpriteKit touch/drag feel, sprite bake from the USDZ, audio, on a real device.

# Lines the lead must wire
1. `PLDevWidgets/PLDevWidgetsBundle.swift`, in `PLDevHomeWidgets`: add `TownWidget()` (that group is at 7; the builder takes ten).
2. `Shared/AppShortcuts.swift` (app only; the list is near the 10 cap, swap one if full):
```swift
AppShortcut(intent: TownStatusIntent(), phrases: ["What is the session doing in \(.applicationName)", "\(.applicationName) town status"], shortTitle: "Town status", systemImageName: "building.2")
```
3. Merge note: `lane-3d` has `ThreeD/TownData.swift`, `TownPainter.swift`, `TownScene.swift` with the same type names as mine. Do not merge those three from lane-3d; mine replace them. My `town-glyphguy.usdz` is a copy of its `glyphguy-v4-world.usdz` under another name so both can coexist.
