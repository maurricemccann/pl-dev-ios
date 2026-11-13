DONE (wave 2, practice lane, branch `wave-practice`; compile check green: run 43465792261, BUILD SUCCEEDED; nothing here has been run on a device)

# Practice, rebuilt as the web app's own screen (S348·9a3e, 11-13)

Lane B's first pass had every feature but drew it as a list of rooms. This pass redraws it to match the live web practice
(`pl-manifestation-practice`, rule 0: screenshotted at 430 px, `index.html`, `app.css`, `app.js` read whole). Same order, same words, same controls.

## What changed (all in `PLDev/Sections/Practice/`)
- **Two screens, as the web has them: Today and Trends** (header "the practice" with outline pills). Today is one scroll of 13 glass cards in the web's order: streak, Scratchpad, Wins & Noticed, Morning, Lesson, Reframe, Affirmations, Conversation, Desire List, Habits, Meditation, Vision board, Evening. Trends: Weekly review, Rehearsals, Story history. The old Practice/Record room lists and the 12 pushed screens are gone (`PracticeCheckinViews`, `PracticeRoomViews` deleted in this commit).
- **Skin** (`PracticeSkin.swift`): the web's field (`#0f0d09`, `#2a2518`, radius 6), select, gold button, ghost button, coach note, `h2` card, kind pill, week dots, details disclosure, rule lines.
- **Speak-first entry** (`PracticeEntry.swift`): the web's opening screen, nothing but the line. One tap draws a line that has his clip (never the same twice running), shows it, plays it, fades in when the clip ends; a second tap skips. Plays only existing clips; no clip means four seconds of text. Once per launch; a deep link skips it.
- **Affirmations**: the day's line (same all day), a real player (play, seek, time), "another" (shuffled deck, no repeat until all shown), browse the library (tap to show), "+ write your own" with his live recording, "send me tonight's line" (the phone's twin of the web push button: asks notification permission and arms the evening notice). His words in his hand (`plHand`, his 11-13 ruling) where the web used a serif.
- **Desire List**: priority, tick to complete, and **map it** per desire: the flow (trigger, I will, then, which leads to, with its chips and arrows) and the WOOP (outcome, obstacle, if/then, the plan line). Both read and write the same routes as the web.
- **Habits**: cue → response → reward line, week dots, tap box to tick (optimistic, comes back on refusal), "+ new habit", touch and hold to archive (with confirmation).
- **Meditation**: the Coherence Bloom (the web's canvas, ported petal for petal: golden angle, eleven-second cosine, ink shadow) and **the Prism** (the web's WebGL fragment shader ported to Metal, `PracticePrism.metal`, same constants, time at 1/6 speed, swelling with the breath); one clock drives the picture and "breathe in... / breathe out...". The two-minute rehearsal under it: desire select, five stages of 24 s, "end early", the 1 to 5 rating, "Logged. The scene compounds." Live Activity and haptic at each stage kept.
- **Vision board**: the catalogue, abundance, love, success (Pexels, live now), "+ your own" photo; chosen pictures lead, the rest fill to twelve; tap to choose or let go.
- **Weekly review** (due after seven days, Read my week, Seal the week), **Rehearsals** (count, average, last five), **Story history**.
- **Return-moment measure**: the one quiet `POST pl-cron /api/practice/open` per cold start the web sends (`via: direct`, local hour); fails silent.
- Pull to refresh reloads every card. Deep links `pldev://section/practice/<room>` still land (they now scroll to the card and switch to Trends where needed; the old `record` and `practice` tabs map to Trends and Today).
- Apple add-ons kept: widget (four families), rehearsal Live Activity, Siri and Shortcuts, evening notice with Face ID habit button, Spotlight index, tips (the habit tip now says tap the box), outbox for notes, wins and check-ins.

## Tests
- Compile: `gh workflow run build.yml --ref wave-practice -f publish=false`, green.
- Live reads (server side, no key needed): every route the cards read answers in the shape the Swift types decode: streak, lesson, habits, scripts, logs, notes, pins, messages, reframes, reviews, trends, sessions, affirmations (200 lines, 200 with clips, audio path `/api/affirmation?id=N`), `vision-board?source=house` and `?category=` abundance, love, success (12 images each).
- The writes were proven by lane B's 53 of 53 round-trip run (desire, WOOP, flow, habit and tick, log, note, session, reframe, own line, pin, review). This pass added no new write route. The new `/api/practice/open` ping was checked by reading its handler (`pl-cron/src/index.ts` ~5371: validates via and hour, 10 per IP per day, 50 per day in all) and by a malformed post, which was refused 400 as designed; a valid post was not sent so as not to add a false row to his return-moment data.
- Unproven (no device): the Metal shader's look against the web's, the player's seek, haptics, the entry's clip hand-off, the Live Activity from the card. Checks for him: open Meditation > the prism beside the web's; tap the opening screen and let a line finish; map a desire.

## Gap check (web feature → phone)
Streak, Scratchpad stack, Wins and Noticed, Morning and Evening with coach notes, Lesson (calendar-advanced; plus a "Keep it as a note" the web lacks), Reframe with kept pairs, Affirmations (all of it), Conversation, Desire List with flow and WOOP, Habits, both meditation visuals, Rehearsal with rating, Vision board with every source and upload, Weekly review, Rehearsals trend, Story history, speak-first entry, push button (as the local evening notice), open ping: all built. Not built, on purpose: web push subscription (the phone's local notice replaces it), PWA service worker (n/a). Not fitting: Action button beyond lane B's intents; Share/Safari extensions.

## Lines the lead must apply
None new. Lane B's wiring (registry, config origins, widgets bundle, shortcuts, microphone line) is already in `main` (checked: `PracticeWidget()` in the bundle, `NSMicrophoneUsageDescription` in Info.plist). The practice origin must stay in the config.

## Server routes needed
None.

## Voice rule
Nothing is synthesised. The entry and the player play only clips the practice already has; his own recordings are live from the microphone, on his device, only on his tap.

---
*Earlier record (lane B, branch `lane-practice`): the app's data layer, widgets, Live Activity, intents, Spotlight and the GlyphBot section were built there; the live test of the interviewer was blocked (see GlyphBot's own lane notes).*
