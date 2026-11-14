# Non-site repos vs PL DEV (read-only sweep, 2026-11-13)

Alive = updated within ~45 days of 11-13 (since ~09-29). Local clones checked at C:\dev; PL DEV = C:\dev\pl-dev-ios\PLDev.

| repo | what it is | alive? | relation | detail |
|---|---|---|---|---|
| personal, personal-cron | personal, never rides PL | n/a | EXCLUDED | not read |
| pl-paint | Tauri/web painting app for the laptop | alive (11-12) | MIRRORED | Sections/Paint/Native/* (NativeStroker, NativeSeam, NativeExport, NativeLift, NativePSD, NativeHandbook, NativeSync). Seam mode (S348, kangaroo/bleed) is in NativeSeam.swift. |
| pl-toolkit | brushes, canvases, quickmenu, gestures, study data; build.mjs -> toolkit.json | alive (11-03) | SOURCE, stale-risk | PL DEV holds a hand-made copy, Paint/Native/NativeToolkit.json (63 KB vs 68 KB source). build.mjs line 43 lists only pl-paint as consumer. Phone copy lacks `ranges`/`sense`, adds `kitPalettes`/`kitAccent`; packs, quickmenu, gestures, papers differ. Last toolkit commit 11-02 (pen second button), so drift is unverified, not proven. |
| pl-design-kit | tokens, palettes, fonts, glass, icons; sync.py -> gallery kit.json | alive (11-10) | SOURCE, current | PL DEV fetches gallery `kit.json` at run time (UI/HouseKit.swift, Pick/PickSection.swift, Library/GalleryRooms.swift), cached offline. Bundled PLIcons and Shared/AppleTokens.swift are copies. |
| pl-vj-studio | Third Eye VJ studio, Tauri desktop plus phone controller | alive (11-03) | MIRRORED | CodeArt/VJEngine.swift, VJModel, VJViews, VJAudio (header calls it the twin of the gallery VJEngine). No remote for the desktop app's phone controller (:8917). |
| pl-call-ios | native iPhone call app (Psyclaupse) | alive (11-12) | DEVICE-ONLY | Separate iPhone app with its own contract. PL DEV has no reference to it (grep psyclaupse / pl-call: none). |
| pl-call | PC side of the call: serve.py :8791, Kokoro TTS, bridge pass-through | alive (11-13) | BACKEND | Server only. |
| jarvis-os | PC local board :8800 | alive (11-10) | DEVICE-ONLY | PC and LAN only. PL DEV has just a "jarvis" icon asset; Status reads pl-cron. |
| pl-cron | CF Worker: crons, social, AI, all /api/* | alive (11-12) | BACKEND | PL DEV is its client (House/ConsoleAPI.swift, Status, Practice, Pick, Paint sync). |
| pl-r1-launcher, pl-r1-homebase | R1 home screen and House board | alive | DEVICE-ONLY | PL DEV House section is the iPhone twin of the R1 House board. |
| pl-r1-curate | R1 curate app | alive | MIRRORED | Sections/Curate/*. |
| pl-r1-practice | R1 daily practice plus GlyphBot | alive | MIRRORED | Sections/Practice/*, Sections/GlyphBot/*. |
| pl-r1-town | R1 Task Town | alive | MIRRORED | Sections/Town/* (native painter, no web view). |
| pl-r1-call | R1 voice call with Claude Code | alive | DEVICE-ONLY | iPhone equivalent is pl-call-ios, separate app. |
| pl-r1-keyboard | R1 input method | alive | DEVICE-ONLY | iPhone has its own keyboard. |
| pl-r1-kit | shared R1 hand font, motion, feel | alive | DEVICE-ONLY | PL DEV gets the hand font from gallery /fonts/ via HouseKit. |
| pl-r1-buddy, pl-r1-pet | R1 companion / pet | alive | DEVICE-ONLY | No PL DEV twin (grep companion/pet: only unrelated paint hits). |
| pl-r1-school | R1 Production School (offline lessons beside FL Studio on the iPhone) | alive | GAP (low) | No school/lesson section in PL DEV (grep: none). Built R1-only on purpose so the iPhone stays on FL Studio. |
| pl-r1-midi | R1 as BLE MIDI device the iPhone connects to | alive | DEVICE-ONLY | iPhone is the receiver; nothing for PL DEV. |
| even-hub-status-glance | glasses status glance | 09-17, parked | DEVICE-ONLY | PL DEV Status and widgets carry the same data. |
| even-hub-moderation, even-hub-decision-queue, even-hub-deck | glasses approvals | 09-17, parked | DEVICE-ONLY | House approvals (House/FounderViews.swift, OutboundViews) is the phone twin. |
| even-hub-library-glance, even-hub-curve-hero | glasses library / curve | 09-17, parked | DEVICE-ONLY | Library and CodeArt sections cover them. |
| even-hub-ask-glyphbot, even-hub-send-to-pl, even-hub-voice-correction | glasses GlyphBot, send inbox, voice fix | 09-17, parked | DEVICE-ONLY | GlyphBot section; Capture section (inbox, dictation) cover them. |
| even-hub-cue-sheet, even-hub-pl-games-glance | glasses cue sheet / games glance | 09-17, parked | DEVICE-ONLY | Games reachable in Congregation Me > Games. |
| even-hub-teleprompter, focus-dots | glasses teleprompter (PL PROMPTER); vision drills (PL FOCUS) | 10-16 | DEVICE-ONLY | Public store-listed glasses apps. A phone teleprompter is plausible but nothing shows he asked. |
| pl-beta-games | 35 standalone HTML games | 10-16 | SOURCE, shelved | PL DEV has only a Games tab pointer in Congregation; no ports, none needed. |
| pl-home-base, pl-xr-native | Unity VR builds (Quest) | parked 09-23 | DEVICE-ONLY | PL DEV Worlds room is the phone's world. |
| pl-mockup-pipeline, pl-scripts, pl-watchdog | Python/Blender mockups; helper scripts; PC watchdog.ps1 | parked | BACKEND | No screen. |
| OpenMontage | third-party video-agent project | 11-07 | BACKEND | Local tool. |
| psyched-luxuries-vault | the Obsidian vault | 11-12 | SOURCE | PL DEV Library/VaultFileView.swift reads vault files. |
| philo | old vault repo, migrated into psyched-luxuries-vault (S271) | 11-09 | BACKEND | Superseded; no clone at C:\dev\philo. |
| vault-mcp-server, rag-assistant, pl-cron-b, pl-video | MCP server, RAG, old cron copy, video tooling | 07-04 to 07-10 | BACKEND | Parked. |
| PLO, PLOS, PLQ, PLQUIZ2, Pl-questions-, Plquiz, pltools | June quiz / HTML experiments | 06-09 | BACKEND | Old, not alive. |
| maurricemccann | GitHub profile README | 10-16 | BACKEND | No screen. |

## Real gaps, ranked

1. **pl-toolkit to PL DEV is a hand-made copy with no generator (SOURCE, drift unverified).** Port: add pl-dev-ios as a consumer in `C:\dev\pl-toolkit\build.mjs` (line 43, phone shape: `kitPalettes`, `kitAccent`, `colourSense`, no `ranges`) writing `C:\dev\pl-dev-ios\PLDev\Sections\Paint\Native\NativeToolkit.json`. Diff packs/quickmenu/gestures/papers first; the 11-02 pen second-button gesture may be missing. Belongs under PL Paint (twin rule).
2. **Verify laptop seam-mode commits reached the phone** (pl-paint 11-11, kangaroo pocket y 2086-5962, bleed-only overhang). NativeSeam.swift mentions kangaroo and bleed, so likely current, not proven. Source `C:\dev\pl-paint\src\app.js` (seamLoad..seamLines) and `src\seams\`; target `Paint/Native/NativeSeam.swift` plus Seam717.json.
3. **Third Eye phone controller** (optional): PL DEV has its own VJ engine, not a remote for the desktop app. Source `C:\dev\pl-vj-studio\src-tauri`; target `CodeArt/VJViews.swift`. Only if he wants to drive the desktop from PL DEV.
4. **R1 School phone twin** (low, deliberately R1-only): lesson deck at `C:\dev\pl-r1-school\assets\school\`.
5. **Link to Psyclaupse** (low): a House row opening pl-call-ios by URL scheme; no feature port.

## Counts per relation (rows group several repos; approximate)
- MIRRORED: 5 (pl-paint, pl-vj-studio, pl-r1-curate, pl-r1-practice, pl-r1-town)
- SOURCE: 4 (pl-toolkit stale-risk, pl-design-kit current, psyched-luxuries-vault, pl-beta-games)
- DEVICE-ONLY: about 33 (pl-call-ios, jarvis-os, 9 R1 apps, 12 even-hub apps plus focus-dots, pl-home-base, pl-xr-native)
- BACKEND: about 19 (pl-cron, pl-call, pl-mockup-pipeline, pl-scripts, pl-watchdog, OpenMontage, philo, vault-mcp-server, rag-assistant, pl-cron-b, pl-video, 7 quiz repos, maurricemccann)
- GAP: 1 (pl-r1-school, low)
- EXCLUDED: 2 (personal, personal-cron)
