DONE
# Lane: capture (wave 3), branch `wave-capture`, compile-check green (run 43521020480, unsigned build, publish=false)

## What was built
Twin of pl-os `components/Intake.tsx` + `CaptureTrail.tsx` (pl-os is behind its login, so I read the code, not a screenshot). Wears House's pl-os skin (`PLOS`, `OSCard`, `OSPanel`, `OSRow`, `OSPill`, `OSKpis`); Capture adds `CaptureSkin.swift`. Files: `PLDev/Sections/Capture/` (Section, Model, Skin, Views, Inputs, System, Tips), `Shared/CaptureGlance.swift`, `PLDevWidgets/CaptureWidget.swift`.
- **Add** (Intake): the four modes in its order and words. Artwork: picture (Photos or camera), title, medium, year, notes. Text: body. Quote: the words in the display italic, attribution. Link: address, "Pull it" (Open Graph title, description, picture, read on the phone), a Paste button. Gold "Add to the system →", the "Added to the system." screen with "Add another", and "Where it went" under the form with "Saving…" rows the instant it is saved.
- **Where it went**: the trail (state boxes In the pool / In Notion / Rejected / Waiting, with pl-os's details and the sweep times), phone-only rows "To send" for what is still on the phone, the moderation deck with swipe Keep / Reject (same `api/captures/moderate` House uses), a detail sheet (full text, picture, copy, open link, share), touch and hold on rows.
- **Waiting**: the four numbers, what is still on the phone with Send now and today's count against the 100 cap, every "waiting on you" count (each opens its House room), where captures go.
- Phone-only: works offline (shared inbox + send queue), the share sheet and Safari still land here, the board's inbox toggle, dictation ("Speak it", on-device), camera, deep links `pldev://section/capture/<add|trail|waiting>?mode=<artwork|text|quote|link>`.
- Send path: text kinds go through the console door `api/pldev/x/intake` (keeps type quote/link/text, 8000 chars), falling back to `api/widget/capture` (500 chars) if the console is missing or refuses; photos go through `api/widget/photo`.
- System add-ons: widget (small, medium with quick-capture links, Lock Screen rectangular and circular), Siri/Shortcuts `CaptureThoughtIntent`, `WaitingOnMeIntent`, `LastCaptureIntent` (counts spoken), Spotlight (3 rooms + 4 ways in, index "capture"), `OpenCaptureRoomIntent`, a TipView for the swipe, haptics, rolling counts.

## Tested live (server side, keys not printed)
GET `widget/waiting`, GET `pldev/q/capturetrail` and `q/captures`, POST `pldev/x/intake` (type quote, landed with source `pl-dev`), POST `captures/moderate` reject (row became `rejected`, so the test left no live item), empty note refused with 400 "Add a note." (the app never sends one). Script: scratchpad `capture_live_test.py`. Photo POST not re-run (existing, proven route; it would put a file in the public bucket).

## Gap check
- Built: every Intake mode and field; link preview; success state; the trail with optimistic rows; the sweeps text; camera ("capture=environment"); all System add-ons that fit.
- Differences from the web, on purpose: photos go as JPEG under 4 MB (the phone door only takes JPEG), so a PNG's transparency is flattened and a photo is stored as a plain capture with its picture link, not as type `art` with `[image]`; web allows 14 MB originals. Optional server fix below.
- Not fitting: Live Activity (a capture sends in about a second); notification buttons (Capture never pushes).
- Unproven (no device): camera, dictation (both stay hidden until the plist lines below exist), widget render, Siri phrases, Spotlight, offline send, swipe feel.

## Lines the lead must wire
1. `PLDevWidgets/PLDevWidgetsBundle.swift`, in the widget group: add `CaptureWidget()` (the group is 8 with Pick; 9 is under the builder's ten).
2. `PLDev/PLDevApp.swift`, next to the other Spotlight calls: `await CaptureSpotlight.index()`.
3. `Shared/AppShortcuts.swift`: already 10. Replace two of the weakest (suggest Shop status and Congregation status) with:
```swift
AppShortcut(intent: CaptureThoughtIntent(), phrases: ["Capture a thought in \(.applicationName)", "\(.applicationName) capture"], shortTitle: "Capture a thought", systemImageName: "square.and.arrow.down")
AppShortcut(intent: WaitingOnMeIntent(), phrases: ["What is waiting on me in \(.applicationName)"], shortTitle: "Waiting on me", systemImageName: "tray")
```
(`LastCaptureIntent` stays available in Shortcuts without a phrase.)
4. `PLDev/Info.plist` (camera and dictation stay off without these):
```xml
<key>NSCameraUsageDescription</key><string>Take a photo to capture into the intake.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Turns your spoken note into text on this phone. Nothing is recorded or kept.</string>
```
(`NSMicrophoneUsageDescription` is already there.)
5. Merge note: my branch merged `main` once; files outside `Sections/Capture`, `Shared/CaptureGlance.swift`, `PLDevWidgets/CaptureWidget.swift` are identical to main.

## Server (optional, not needed for the app to work)
To make photos land like the web's (type `art`, `[image]` line), `pldev.ts` `intake` could accept `image_base64`, put it in `ARCHIVE` under `intake/<date>/<uuid>.jpg` and store `note + "\n[image] " + url` as type `art`. Not written: it would need a new public file path and a decision on the URL base; flag if he wants it.
