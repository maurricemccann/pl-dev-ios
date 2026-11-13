DONE — curate (wave 1). Branch `wave-curate`, compile-check run 43461844671 passed (`build.yml`, publish=false). Files: `PLDev/Sections/Curate/` only (CurateSection, CurateModel, CurateViews, CurateCards, CurateSkin).

## What was built (against `C:\dev\pl-curves-gallery\components\CurateDeck.tsx` and the live /curate at 430 px)
- **Every deck of the web picker**, grouped as the web groups them (`CurateMode`): New · Cloud + API (cloud, API, "not yet seen" for shorts / stills / everything, "every verdict" for shorts / stills) · Trash · Curate (8 classes) · Maybes (8 classes) · Re-pass (6 classes + Keeps: star the favourites) · Categories · tag decks (a Tags submenu from `/api/tags`). Base decks are dealt by PLDevCore's `CurateQueue` (unchanged); the categories deck, tag decks, and the archive redo order (`/archive-redo.json`) are built here as the web builds them.
- **Re-pass rules** exactly as the web: a keep on a keep or favourite leaves it as it was (note and comment kept); a re-pass maybe goes through the image / phrase / layout strip (no swipe up, no maybe key; seeds excepted); keep key reads "Leave as keep / favourite"; the favourite key sits pressed when the card already is one; the caption says "was maybe, liked the image", "was cut", "new".
- **His words box** above the piece on every swipe deck, saved the moment he leaves the box, with the web's states (saving… / saved ✓ / NOT SAVED: tap the box and tap away to retry), 1,000 characters.
- **Maybes deck:** its own note box ("What is wrong with this one?") sent with the verdict.
- **Categories deck:** Digital / Physical / Seeds buttons, the machine's guess pre-lit, a swipe never marks taste, `/api/classify` POST and undo; keys 1 / 2 / 3 from the R1 Remote.
- **Full view:** the Full / × button, three taps on the picture, any verdict key turns it on (R1 Remote), nothing around the picture, status bar hidden, back swipe stays on.
- **Clips:** poster first, the clip loops over it, a speaker button with the choice remembered (and in Settings > Curate), as the web's SoundVideo. Archive works paint the 40 KB thumb and fade the original in. Essays scroll whole inside the card with italics; seeds in his hand sized 30 / 23 / 17 / 14 by length; a work with only a palette shows its four colours. Code pieces keep the live `LivePieceCard`.
- **Orange wash and ring** for cloud batches, API renders and Claude's own words, with the label above the title (colours from globals.css `--claude-wash`, `--claude-orange`, dark twin).
- **Caption** as the web: id · moving · by hand · sub · was… · the machine's QA flaw read (`/curate-qa.json`). **Locked-device banner** from `/api/unlock`. **Not-saved count** (taste + classify). **The cleared screen** with a door into every other deck and how many cards wait in each, and this session's +keep / ~maybe / x cut.
- **Favourites viewer** (the web's /library?v=fav): every starred keep newest first with its comment box, saved on leaving the box.
- **Apple:** swipe + five keycap images, haptics on every write and undo, Dynamic Type headers, accessibility actions (Keep, Cut, Maybe, Favourite) on the card, touch-and-hold menu (copy name, copy id, keep the original, full view), tip group (swipe, then full screen), Spotlight index of the decks (`CurateSpotlight`, refreshed in `CurateSection.refresh`), Siri "open a Curate deck" and "cards waiting in a deck", Settings rows (sound, open on the last deck, Spotlight again), deep links `pldev://section/curate/<kind>[:<class>]` (`new`, `cloud`, `trash`, `maybes:still`, `repass:seed`, `categories`, `tag:<name>`).
- **Offline:** marks queue in `MarkOutbox` (LibraryData), reads fall back to the saved copy; the categories deck needs the network for its POST and counts a failure.

## Tested against the live service (reads only; no key printed)
`curate-qa.json` 200 (map id → text) · `api/unlock` 200 `{"unlocked":false}` for an unkeyed client (the app's keyed call is what the banner reads) · `api/classify` GET 200 `{ok, cats:{id:{cat,by}}}` · `api/tags` 200 `{tags:{id:[…]}}` · `archive-redo.json` 200 `{was_keep:[…]}` · `seed-index.json` 200 · `cinematic/manifest.json` 200. An **unkeyed** POST to `api/classify` is refused 401 `locked`, so the write is gated as the web's. I did **not** write marks, comments or categories to his live store (they would change his real taste data); the taste writes are the same `LibraryData.post` path Library and the old Curate already used, and the classify write is built to the route's own contract (`{cr, cat}`, `{cr, undo:true}`, same-origin header).

## Gap check (web feature → state)
| | |
|---|---|
| Deck picker, all groups, counts | built |
| Swipe, stamps, five keycaps, undo, favourite star | built |
| Comment box + save state | built |
| Maybes note, re-pass maybe tag strip, leave-as-is rules | built |
| Categories deck, tag decks, trash restore | built |
| Full view, 3-tap, remote keys, sound | built |
| Orange wash, caption, QA line, lock banner | built |
| Archive thumb fade, essay, seed, palette card | built |
| Keep · use the original (edited archive works) | built |
| Cleared screen with doors and counts | built |
| Favourites viewer | built |
| Back to the library link | the system back button (the app is its own tile) |
| `?days=N` and `?recent=1` on the New deck | not built: URL-only variants the picker never offers |
| Recorded-MP4 fallback for a slow live piece | already in `LivePieceCard` (lane D), untouched |
| Widget | exists in Library's folder (`LibraryGlance`: queue, kept, newest batch); every mark here refreshes it |
| Live Activity | **not built** (needs ActivityAttributes in `Shared/` and a widget view in `PLDevWidgets/`, outside this folder). Block below. |
| Notification buttons | **not fitting**: nothing arrives for Curate, a pass is something he starts |
| Siri / Shortcuts | built; lines below |
| Spotlight, tips, deep links | built |

## Lines the lead must wire
1. `Shared/AppShortcuts.swift` (the app stays at 10 or fewer): add
```swift
AppShortcut(intent: CurateDeckCountIntent(), phrases: ["How many cards are in \(\.$target) in \(.applicationName)", "Cards waiting in \(\.$target) in \(.applicationName)"], shortTitle: "Cards in a deck", systemImageName: "rectangle.stack")
AppShortcut(intent: OpenCurateDeckIntent(), phrases: ["Open \(\.$target) in \(.applicationName)"], shortTitle: "Open a deck", systemImageName: "rectangle.stack")
```
   (If the count is at 10, drop the open-a-deck one; Spotlight already opens decks.)
2. `PLDevApp.swift` line 20: add `await CurateSpotlight.index()` beside the others (it also runs in `CurateSection.refresh`).
3. `Info.plist`: nothing new. The clip sound uses `AVAudioSession.playback` and needs no key.
4. Optional Live Activity "a Curate pass" (start on the first mark, update on every 10th, end when the queue clears): `struct CuratePassAttributes: ActivityAttributes { struct ContentState: Codable, Hashable { var left: Int; var kept: Int }; var deck: String }` in `Shared/CuratePass.swift`, a widget view in `PLDevWidgets/` copying `ShiftLive`'s pattern, and in `CurateModel.advance` an `Activity.request` / `update` / `end`. Left unbuilt because it spans two folders that are not this lane's.

## Unproven (no device)
The AVPlayerLayer clip with sound on a real iPhone, the three-tap against the swipe on the glass, the hidden-bar back gesture (copied from House's `SwipeBackEnabler`), and Dynamic Type at the largest size. Compile is green; he tests at the end.
