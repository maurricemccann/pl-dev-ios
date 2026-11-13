# Parallel lanes (S348·9a3e, 11-13, his order: "build everything, fit every app, spawn another two sessions, use Gemini if needed for input")

Three Claude Code sessions build PL DEV at once. **The lead session** (the PL Call window) owns `main`, the merges, every
publish to the SideStore feed, and every pl-cron and pl-os deploy. Each lane works only in its own git worktree, on its
own branch, and touches only the files listed below.

## The order and the loop (his words, both rulings 11-13)
- Order: pl-os (done, House) → Curve Library (lead) → psychedluxuries.com app (lane A) → the practice in full and GlyphBot in full (lane B) → Composer and PL Paint (lead, after the Curve Library).
- Loop per app: build it in full → test it (server side: every read and write you add, against the live service) → premium pass → gap check written into your lane notes. **No stops and no check-ins with him.** "Just keep working through each app, don't stop until they are all done, then I'll test." He tests everything at the end.
- **Read `DESIGN.md` before writing anything.** It is the one UI/UX contract (shape, states, gestures, words, iOS 27 tokens, the seven system add-ons). House (`PLDev/Sections/House/`) is the reference: copy its patterns (`Console`/`OS` calls, `Loaded`, `ResultLine`, the room enum, `ShiftLive` for Live Activities, `HouseGlance` for widget data, `NotificationHub.actions`). Never invent a new look.

## Lane A: the psychedluxuries.com app (worktree `C:\dev\pl-dev-ios--storefront`, branch `lane-storefront`)
- What: the public site, as a native app for him. The storefront (shop grid, product pages with the flats and transparent PNGs only, the archive, the transmission signup, the Closet), the congregation (feed, requests and votes, the member's own page), and the site's settings. Source: `C:\dev\pl-headless` (Next.js). Read its routes and APIs first, then build it in full.
- Your files: `PLDev/Sections/Shop/` and `PLDev/Sections/Congregation/` (new folders; delete the two placeholders from `PLDev/Sections/Paint/PlaceholderSections.swift` when yours replace them), plus your own new files in `PLDevWidgets/` and `Shared/` named `Storefront*.swift`.
- The house rules that bind this lane: no model mockups and no on-model images on any product surface (flats, ghost and transparent PNGs only); the site is the outer tongue. Read `.claude/hard-limits.md` → Product imagery in the vault.

## Lane B: the practice in full and GlyphBot in full (worktree `C:\dev\pl-dev-ios--practice`, branch `lane-practice`)
- What: (1) the daily practice: source `C:\dev\pl-manifestation-practice` (a Worker) and its R1 twin `C:\dev\pl-r1-practice` (read its README; the practice plays only pre-generated clips in his voice, nothing is synthesised on device: keep that). (2) GlyphBot: the Oracle room (pl-os `components/GlyphRoom.tsx`, `GlyphGuy3D.tsx`, `lib/oracle-db.ts`: questions to pl-cron `/api/oracle`, works offline with cached answers, syncs turns via `/api/glyphbot-sync`) and the GlyphBot interviewer (pl-cron `/api/r1/interview/*`, its own token). GlyphGuy has no face: emotion is head shape and motion (memory: GlyphGuy has no face). The R1 app pairs both: mirror it.
- Your files: `PLDev/Sections/Practice/` and `PLDev/Sections/GlyphBot/` (new folders), plus your own new files in `PLDevWidgets/` and `Shared/` named `Practice*.swift` / `GlyphBot*.swift`.
- The founder's voice has one source (Voicebox; see `.claude/hard-limits.md` → Founder voice). Never synthesise him on the phone; play only the clips the practice already has.

## Rules for both lanes
1. **Never edit outside your files.** Shared files (`SectionRegistry.swift`, `Shared/AppShortcuts.swift`, `PLDevApp.swift`, `NotificationHub.swift`, `Info.plist`, `DESIGN.md`, `CONTRACT.md`, the config) belong to the lead. Write what you need from them into `LANES-<lane>.md` in your worktree (exact lines to add), and the lead applies them at merge.
2. **Never edit pl-cron, pl-os or pl-headless directly.** If you need a new server route, write it as a ready-to-paste block in `LANES-<lane>.md` (the file, where, the code, how to test it). The lead deploys it. Read-only calls to live routes for testing are fine.
3. **Compile check without publishing:** `gh workflow run build.yml --ref <your branch> -f publish=false`, then read the errors with `gh run view <id> --log-failed`. Only `main` ever publishes to his feed. One build of yours at a time.
4. **Gemini for input is allowed** (his words): for design critique or ideas, through Chrome at gemini.google.com, one thread per subject, one prompt block with no line breaks, sent once (memory: Gemini one thread one block). Gemini's UI critiques invent defects: crop and check each claim before acting on it.
5. Commit to your branch often, with clear messages ending in the two attribution lines. Push your branch. When the app has been through the whole loop, write `LANES-<lane>.md` (what you built, the gap check, server routes needed, shared-file lines needed) and say DONE in its first line. The lead merges.
6. Secrets: never print a key. The config with the keys is `C:\Tools\pl-dev-builds\pldev-config.json`. Read a key in a script and use it without echoing it, as `scripts`-style Python does.
