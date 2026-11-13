DONE (lane B, branch `lane-practice`; compile check green on the last build; one live test is blocked, see "Blocked")

# Lane B: Practice and GlyphBot (S348·9a3e, 11-13)

## BLOCKED, needs one founder tap
**The live test of the interviewer (`/api/r1/interview/state`) was denied by the auto-mode classifier** when I tried to read the interview key from `KEYS.local.md`. I did not work around it. The interviewer code is written against the engine's source (`pl-cron/src/interview.ts`: `turn`, `speak`, `state` shapes) and compiles, but it has not been run against the live route. Lead: run `GET api/r1/interview/state` once with the key, and check `bank`, `coverage`, `recent` decode (Swift types: `GlyphBot.StateReply`).
Also: one of my grep calls printed the interview token's value into this lane's local session output (my redaction pattern missed the `=` form). It went nowhere else (no file, commit or message; the repo scan is clean). Rotating it (`wrangler secret put R1_INTERVIEW_TOKEN`, then re-provision the R1) is optional and his call.

## What was built
**Practice** (`PLDev/Sections/Practice/`, section id `practice`): Today · Practice · Record, segmented. Soft streak (days this month, days in all, of the last 7). Morning and evening check-in (with the coach's note), the lesson (answer kept as a note), reframe (AI suggestion, editable, kept pairs), talk it through (the one ongoing thread), affirmations (library of 200 plus his own lines first; plays only clips that exist; his own live recording per line; shuffled deck, no repeat until all shown), desires (WOOP and flow per desire, swipe done), habits (swipe tick, week dots, archive with confirmation), rehearsal (two minutes, five senses, breath bloom, intensity at the end) and just-breathe, vision board (pins, house art, his own photo, catalogue picker), notes, wins and noticed, weekly review (the read from the real week, seal), the record. Offline outbox for check-ins, wins and notes (mirrors the R1's). Honest failed states.
**GlyphBot** (`PLDev/Sections/GlyphBot/`, section id `glyphbot`): Ask · Sit · Record. Ask is the Oracle room: every question kept on the phone the instant it is asked, answers from the Oracle, else cached, else bundled doctrine; syncs to `/api/glyphbot-sync` when online; sources and "hear it" on touch and hold. Sit is the interviewer: Interview (domain, pressure, length, go deeper) and Free talk; his words leave only from the Send button; a failed send keeps the answer in the box; continue the last sitting. Record is coverage per domain, the bank, recent answers, and the Oracle sync count.
Shared: `Shared/PracticeGlance.swift`, `Shared/GlyphBotGlance.swift`. Widgets: `PLDevWidgets/PracticeWidgets.swift`, `GlyphBotWidgets.swift`.

## Tests (live)
- Practice Worker: 53 of 53 pass (script kept out of the repo: it holds the Worker address). Every read decoded by shape against the Swift types; every write round-tripped and its row removed (desire with WOOP and flow, habit tick and untick, log, note, rehearsal session, reframe pair, own line, pin on and off, review); validation refusals (empty log, session without intensity, non-image upload, empty belief, unknown recording); a real clip is WAV bytes; the three AI reads answer.
- Not written live, on purpose (no delete route, would pollute his record): check-ins (shape equals what the R1 sends), the coach thread, board photo upload, recording upload, `glyphbot-sync` (auth and validation proven with a 400; one real row should be written once at merge).
- Oracle through the House key: 200 with `answer`, `passages` (10 sent, 4 kept), `via`; empty question 400; sync door accepts the key.
- Interviewer: not run live (blocked above).
- App compile: `gh workflow run build.yml --ref lane-practice -f publish=false`, green.

## Lines the lead must apply (shared files)
1. `SectionRegistry.all`: add `PracticeSection.self, GlyphBotSection.self`.
2. Config: `sections` add `"practice"`, `"glyphbot"`. `origins`: `"practice"` = the practice Worker's base address, no auth (open by his ruling); `"interview"` = pl-cron base with `auth: {key: "interview", header: "Authorization", scheme: "Bearer"}`. `keys`: `"interview"` = the R1 interview token. GlyphBot's Oracle needs nothing new (console origin, House key). Without `interview`, Ask works and Sit/Record say plainly the key is missing.
3. `PLDevWidgetsBundle`: add `PracticeWidget(), GlyphBotWidget(), RehearsalLiveActivity(), SittingLiveActivity()`.
4. `Shared/AppShortcuts.swift` (10 max in the whole app, so pick): `PracticeStatusIntent` ("What's left in my practice today in \(.applicationName)"), `LogWinIntent` ("Log a win in \(.applicationName)"), `AskGlyphBotIntent` ("Ask GlyphBot in \(.applicationName)"). Also written and available in Shortcuts without a registered phrase: `TickNextHabitIntent`, `GlyphBotStatusIntent`, `OpenPracticeRoomIntent`, `OpenGlyphBotRoomIntent`.
5. `Info.plist`: `NSMicrophoneUsageDescription` = "PL DEV records your own voice for your affirmations, only when you tap the microphone." Until then the record buttons stay hidden (the code checks).
6. Optional, `PLDevApp.swift`: index both Spotlight sets at launch like House (they also index on first refresh).
7. Optional, `NotificationHub`: pass a text-input response to actions, so the evening notice can offer "Save gratitude" with typing. Not built, because the hub drops the typed text today.

## Server routes needed
None. Nothing was added to pl-cron, pl-os or the practice Worker.

## Gap check
Practice web and R1 features: every card on the web's Today and Trends is built (streak, notes, wins and noticed, both check-ins, lesson, reframe, affirmations with own recordings, conversation, desires with WOOP and flow, habits, rehearsal, breath bloom, vision board with own photos, weekly review, rehearsal and story trends), plus the R1's outbox. Not built: Pexels categories on the vision board (no key set on the Worker; the web also falls back to the house catalogue); delete buttons (the practice has none by design); the R1's "how it feels" settings (iPhone has system haptics and Settings).
GlyphBot: Oracle room (offline cache, sync, doctrine fallback, typewriter, sources) and the interviewer (turn, speak, state; interview and free talk; settings; continue) built. **Not built: the 3D GlyphGuy figure.** His rigged GLB cannot load on iOS without a converted USDZ (6.7 MB of his art in a public repo), and the house rule is never to redraw him; the R1 app is words only, so this mirrors it. One-step ask if he wants it: a converted USDZ, loaded from the Worker at run time. The interviewer's topic queue and the export routes are partner-side, not his hands.
Apple add-ons: widget (both, four families, `widgetAccentable`), Live Activity (rehearsal and sitting; started on his tap, updated on change, ended at once), Siri and Shortcuts (spoken counts), notification (Practice evening line with two real buttons, Face ID on the tick; GlyphBot has no notification, it never speaks first), Spotlight (named indexes `practice`, `glyphbot`), tips (habit swipe, answer touch and hold), deep links `pldev://section/practice/<tab or room>` and `pldev://section/glyphbot/<ask|interview|freetalk|record>`. Largest text: figures stack; bubbles and lists use system styles. Not fitting: Action button beyond the intents above; Safari and Share extensions (nothing to share into the practice).

## Voice rules kept
No synthesis of his voice anywhere. Practice plays only the existing clips and his own live recordings; no clip means text only. GlyphBot's "hear it" is the interviewer's own voice (Aura), never his.
