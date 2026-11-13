DONE
# Lane: pick (wave 1), branch `wave-pick`, compile-check green (run 43462591212, unsigned build, publish=false)

## What was built (twin of `pl-curves-gallery/public/pick/index.html`, checked against its code; screenshots not taken, the page is static HTML with no login)
- Vote room: the 13 Design Kit palettes as the page's swatches (same control points), the number bottom-left like the page, "This one" bar, the "Kept." thank-you, same words.
- Results room: ranked, count top-right, "N picks, most first." Touch a swatch for the closer look.
- Segmented Vote / Results control under the title (DESIGN §1); replaces the toolbar button.
- Closer look sheet: large swatch, the four colours with hex (tap to copy), the vote split by door (Library, R1, Link, This app), "This one" from inside.
- Touch and hold: Look closer, Copy the colours, Share the vote (link to the web `/pick/`). A TipView names it.
- Phone-only: your last pick is marked on its swatch; a vote made offline is kept and sent the next time the cron answers (on load, refresh or app refresh); 429 says "Too many picks just now."; pull to try again; spinner while loading.
- Offline reads come from the app-wide GET cache (kit.json, tally).
- System add-ons: widget (small, medium, Lock Screen rectangular and circular; leader's swatch, count, your pick), Siri intent `ColourwayLeaderIntent` (says leader and counts), Spotlight (Vote and Results rooms, index "pick"), `OpenPickRoomIntent`, deep links `pldev://section/pick/vote|results`, haptics, rolling counts.

## Gap check
- Built: every feature of the web page except the R1 kiosk door (wheel and press), which is the R1's own app.
- Not fitting: Live Activity (a vote has no start and end); notification buttons (Pick never pushes); a key (the route is public).
- Unproven (no device): widget render, Siri phrase, Spotlight, offline vote flush. The server calls (GET kit.json and GET /api/color-pick = `{"ok":true,"tally":{}}`) were read live; no POST was made (it would add a real vote).

## Lines the lead must wire
1. `PLDevWidgets/PLDevWidgetsBundle.swift`, in `PLDevHomeWidgets`: add `PickWidget()` (the group is 7; one more is 8, under the builder's ten).
2. `PLDev/PLDevApp.swift` line ~20, next to the other Spotlight calls: `await PickSpotlight.index()`.
3. `Shared/AppShortcuts.swift`: add (and keep the whole app at 10 or fewer; trim another to fit if needed):
```swift
AppShortcut(intent: ColourwayLeaderIntent(), phrases: ["Which colourway is winning in \(.applicationName)"], shortTitle: "Colourway vote", systemImageName: "paintpalette")
```
4. Optional: `AppModel` is untouched; `PickSection.refresh` loads the tally and flushes a pending offline pick on the app's refresh.
No server route needed.
