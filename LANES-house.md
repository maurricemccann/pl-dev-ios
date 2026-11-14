DONE (house lane, branch `wave-house`; every compile check green, the last two edits after the final screens run are small and listed under "Unchecked")

# House lane: what was built

## Built, each ported from its real web source
1. **Academy, native** (`House/AcademyViews.swift`, `AcademyHTML.swift`, `AcademyBanks.swift`). Source: `pl-academy/src/index.ts` + `drills.ts`, `pl-os/app/academy/page.tsx`. The pl-os hub (header with live state, four rooms, seven-section curriculum with absorbed counts), the **Reader** (the Worker's canon, parsed from its `<article>` into native headings, lists, quotes, tables, code; kept offline once read; Mark absorbed; email link and "Claim 200 pts" to `/api/complete`), the **Oracle** (`/api/ask`), the **Forge** (three fixed decks + `/api/forge`), the **Drills** (Purge, Sequence, Rewrite graded by `/api/drill/rewrite`, scores kept). Replaces the Safari Link in `MoreViews.swift`, the web sheet in `Congregation/AccountViews.swift` (now a NavigationLink), and `HouseRoom` gained `.academy` and `.jarvis` (deep links `pldev://section/house/academy`, `.../jarvis`).
2. **V.A.U.L.T. board chat** (`House/JarvisView.swift`). Source: `pl-os/components/JarvisRoom.tsx` + `lib/jarvis-api.ts`, over the config's `board` origin with its key. Terminal look, present/asleep states, Conductor default + the board's brains, streaming chat, flows and their reports (opened natively), recent turns, Apple on-device speech in, the board's own `/api/tts` out, VJ code replies shown as code with copy. Tested against the live board (config, status, conversation, flows, note, ask all answer from this PC).
3. **Curve Who scroll reader** (`Labs/LabCurveWhoReader.swift`): the page's four colour stops, chaos curve, dissolve to the Totem, 12 fps stop-motion, scroll = story. New Labs row "The Curve Who, reader".
4. **The Lab Room** (`Labs/LabRoom.swift`): scroll room + world gallery in RealityKit: obsidian shell, gold trim, six framed glyphs from the gallery, his gold GlyphGuy, the ajar door with spill light, the page's six-key camera path and smoothing, odometer, Enter. Row "The room". The site's `/room` is this same piece.
5. **Seed phrase draw and PL tarot** in Practice (`Practice/PracticeDrawCards.swift`, data generated from the R1 files into `PracticeDraws.swift`): shuffled-deck draws (no repeat until all shown), his hand for his words, three-card spread read together through the Oracle. Rooms `seeds` and `tarot` added to `PracticeRoom`.
6. **Congregation tag page** (`Congregation/TagViews.swift`): tapped #tags stay in the app (`pltag://`), deep link `pldev://section/congregation/tag/<tag>`.
7. **Interviewer voice** (`GlyphBot/InterviewVoice.swift`, edits in `GlyphBotViews.swift`, `GlyphBotAPI.swift`): Apple Speech in (on device), Apple voices out only (Personal Voice filtered out and never requested), hands free vs push to talk with the gold orb, pause and speed, voice picker with samples, model, deep, adventure, reply length, bank mode, session length, cost estimate, plus the page's domain doors (with coverage) and the 501 bank card on the setup screen.
8. **Toolkit sync** (`Paint/Native/NativeToolkit.json`): rebuilt from `pl-toolkit/toolkit.json`. It was stale in gestures (the 11-02 `penbtn2` pen second button was missing), packs, papers and quickmenu; study, canvases, defaults, names were equal. Phone-only keys `kitPalettes` and `kitAccent` kept; `ranges`->`schema`, `sense`->`colourSense` as the app reads them. `penbtn2` is already read by `NativeCanvasStage.swift`.

## Lines for the lead
- **pl-toolkit/build.mjs**: after the `consumers` array (line ~43) add a phone writer, because the shape differs:
  ```js
  const phone = { ...out, schema: out.ranges, colourSense: out.sense }; delete phone.ranges; delete phone.sense;
  const pf = 'C:/dev/pl-dev-ios/PLDev/Sections/Paint/Native/NativeToolkit.json';
  if (fs.existsSync(pf)) { const keep = JSON.parse(fs.readFileSync(pf, 'utf8')); phone.kitPalettes = keep.kitPalettes; phone.kitAccent = keep.kitAccent; fs.writeFileSync(pf, JSON.stringify(phone)); console.log('wrote PL DEV', pf); }
  ```
- **pl-headless route for the tag page** (the app reads the public room's newest 50 until this exists): `app/api/congregation/tag/route.ts`, GET `?tag=`, public. Same SQL as `app/tag/[tag]/page.tsx` (`status='published' AND lower(body) LIKE %#tag%`, limit 60). Return `{ ok: true, posts: [...] }` where each post is `{ id, body, mediaUrl: media_url, createdAt: created_at, authorKind: author_handle ? 'member' : 'founder', authorGlyph: author_glyph, authorHandle: author_handle, reactions: 0, reacted: false, comments: [] }` (the app's `RoomPost` needs `reactions`, `reacted`, `comments` present). Test: `curl /api/congregation/tag?tag=seeds`.
- **Info.plist**: nothing new (speech and microphone strings already there).
- **Academy list**: the Worker has no JSON for the curriculum, so the app reads the home page's markup. A `GET /api/index` returning `[{section:{id,title,blurb},docs:[{key,name}]}]` would remove that coupling (optional).
- **OpenCode runner** (in JarvisRoom.tsx) is left out: it needs the board's action token, which the phone does not hold. If wanted: a pl-os `api/pldev/jarvis-action` route behind the PL DEV bearer, proxying like `app/api/jarvis-action/route.ts`.

## Left, with the reason
- **Item 5, a House row opening Psyclaupse**: `pl-call-ios` declares no URL scheme (checked: no `CFBundleURLSchemes`, no `onOpenURL`). Not built. It needs a scheme added there first.
- **Shirt preview**: skipped as told.
- **Lab Room, Curve Who reader: not seen in a screenshot.** The Labs have no deep link to a single lab, so the screens workflow cannot reach them; the Labs index (with the two new rows) was checked. They compile; the lighting values (RealityKit lumens) and the gold mark's transparency are untuned guesses and need one look on a device or simulator. RealityKit has no planar mirror or fog: the floor is glossy dark, distance falls off through the lights.
- **Interviewer voice and the Jarvis chat were not run with keys** (the simulator has none): the key-refused and asleep states were seen; live behaviour of the orb, speech and streaming is unproven on a device. The board endpoints themselves were exercised with curl.
- **Tag page** reads the newest 50 room posts until the route above exists (shown with a note when a tag is empty).
- Founder's voice: nothing here synthesises it.

## Screenshots looked at (run 43557430535)
Academy hub (matches pl-os: header, live dot, four rooms, curriculum with 0 of N absorbed; real canon counts 14/2/2/1), Jarvis (asleep state, as expected without a key; duplicate title fixed after), Interviewer setup (doors list), Practice (seed draw and tarot cards in place), Tag `#seeds` (real posts, gold links), Labs index.

## Unchecked
Two edits after the last screens run: the Jarvis header label removed, and the lab-room type-check split (compiled green before the Jarvis edit).
