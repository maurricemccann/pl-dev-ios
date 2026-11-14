# PL DEV coverage: pl-os, gallery, composer, r1, other workers

Method: route lists from page.tsx / public html; native status from grep of C:\dev\pl-dev-ios\PLDev (no WKWebView anywhere; the only web surfaces are SFSafariViewController in SiteAPI.swift and iOS WebPage in Congregation/AccountViews.swift:242). "Built in" = session tags read from the code and first-add git commits, because pl-ask-session.py timed out (over 2 min, then matched its own --help). Founder quotes were not pulled from transcripts. Status for Labs/Worlds/CodeArt rests on the room lists plus file headers, not on running the app.

## 1. pl-os (plos.beta.psychedluxuries.com), native home Sections/House

| route | what it is | built in | native status | gap |
|---|---|---|---|---|
| / | Dashboard: Do next, Needs you, Shift (day plan), Standing, stat tiles, crew/health/cost, Brains status | init 06-05; S192 S246 S266 S295 S308 S312 S319 S330 S335 | BUILT: HouseSection.swift founder tab (Needs you, Approvals, Shift, Standing, Rooms) | BrainsStatus (local brains) not checked as a panel; Stack health/Crew/Costs exist as rooms |
| /academy | Curriculum map + launch pad to pl-academy | 06-28 | MISSING (native). MoreViews.swift:31 is a Link to Safari; AccountViews.swift:242 opens a WebPage (a web view) | whole academy: curriculum, reader, forge, drills |
| /atlas | The whole house drawn: map, journeys, week, control | 07-02 | BUILT: RoomViews.swift AtlasView + AtlasMap (real pinch/drag map, 3 tabs, node detail) | none seen |
| /calendar | Content calendar, day by day, every platform | S312 | BUILT: HouseCalendar.swift (one month grid, dots per calendar, real merch pictures) + CalendarView | none |
| /catalog | Catalog matrix per design, build queue | S218 S246 | BUILT: RoomViews.swift CatalogMatrixView + CatalogQueueView (list, not the sticky grid) | web's colourway grid/cell sheet not checked; list form |
| /codex | Sovereign Language Codex tool (anchors, diagnostic, desires, entry) | init | BUILT: RoomViews.swift CodexToolView | none seen |
| /comments | Comment drafts to copy and post | S308 | BUILT: RoomViews.swift CommentsView | none |
| /craft | Wouldn't It Be Nice game + archive caption crafting | S143 S146 S242 | BUILT: RoomViews.swift CraftView (web prompts word for word) | none |
| /inbox | Member DMs | 06-26 | BUILT: InboundViews.swift InboxView + DMThreadView | none |
| /jarvis | Local board chat terminal (streaming, voice, brains, flows) | 06-19 | MISSING (native). HouseSection.swift:282 is only a Link to the LAN board | chat room, voice in/out, brain picker; LAN/Tailscale only |
| /merch | Merch calendar, seasons per colourway, drop candidates, ask tally | S319 | BUILT: MoreViews.swift MerchView + HouseCalendar (pictures) + TallyView | none |
| /ops | Ops AI concierge chat | 06-19 | BUILT: MoreViews.swift OpsView | none |
| /oracle | GlyphBot room | 06-19 | BUILT: Sections/GlyphBot (own section, 6 files) | none |
| /precedent | House UI library of screens | S269 | BUILT: MoreViews.swift PrecedentView | none seen |
| /seed-registrations | Seed COA review | S295 (09-17) | BUILT: InboundViews.swift SeedRegistrationsView + SeedAuthView | none |
| /settings | Design Kit settings panel, notifications | S334 | BUILT: UI/SettingsView.swift | none |
| /source | Deep Source Interview | 07-31 | BUILT: RoomViews.swift SourceInterviewView | none |
| /support | contact_messages inbox, resolved toggle | S266 (09-11) | BUILT: InboundViews.swift SupportView | none |
| /tempo | Tempo Engine: angles, performance, email, manual posts, reels | S119 S129 S186 | BUILT: OutboundViews.swift TempoView (+ compose in FounderViews) | none |

Counts: 19 pages. BUILT 17, MISSING 2 (academy, jarvis), PARTIAL 0.

## 2. pl-curve-library (gallery), native: Library/GalleryRooms, Labs, Worlds, CodeArt, ThreeD, Curate, Pick, Town, Paint

| route | what it is | built in | native status | gap |
|---|---|---|---|---|
| /library | Hub, one home | 06-20 | BUILT: LibrarySection.swift | |
| /library/vault | Grid/list/select of everything filed, verdict | S327 | BUILT: GalleryRooms VaultRoom | |
| /curate | Swipe keep/maybe/cut, A/B split cards | 08-27 | BUILT: Sections/Curate | |
| /pick (static) | Colourway vote | S348 | BUILT: Sections/Pick | |
| /town | Pixel Task Town | S330 | BUILT: Sections/Town | |
| /paint (static) + handbook | PL Paint web app | S332 | BUILT: Sections/Paint (Native canvas); PaintSection.swift:258 keeps an "open web version" button | handbook page not checked |
| /settings | Design Kit settings | S334 | BUILT: UI/SettingsView.swift | |
| /kit, /kit/glass/* | Design Kit browser, glass showcase | S332 | BUILT: KitRoom; glass showcase maybe via Labs "Components" | glass/settings.html and showcase.html not confirmed |
| /curves | Every live piece, running | S49 | BUILT: CodeArt CurvesRoom (NativeCurvesRoom) | |
| /live | VJ instrument | S49 | BUILT: NativeVJRoom (VJEngine, VJAudio, VJViews) | |
| /forge | VJ Coder AI piece writer | 07-01 | BUILT: ForgeRoom.swift | |
| /forge/embed, /pieces/embed | iframe embeds | 07-01, 07-30 | EXCLUDED: exist only to be iframed | |
| /archive | 1,347 works | S49 | BUILT: ArchiveRoom | |
| /archive/space | 3D archive hall | 06-20 | BUILT: Worlds ArchiveSpaceWorld | |
| /generated | Stills | 06-24 | BUILT: StillsRoom | |
| /cinematic | Clips | 07-01 | BUILT: CinematicRoom | |
| /printful | Template triage | 08-02 | BUILT: PrintfulRoom | |
| /classify (static) | Name and file archive | | BUILT: ClassifyRoom | |
| /tools | Code behind every piece | S49 | BUILT: ToolsRoom + SourceView | |
| /source | Piece source viewer | S49 | BUILT: SourceView (via ToolsRoom) | |
| /unlock | Device key unlock | C29 | BUILT in effect: key handled in CurateModel/ForgeRoom/VJModel (SHA256 token) | no standalone page; fine |
| /labs | Labs hub | S300 | BUILT: Labs/LabsRoom.swift (28 rooms) | |
| /lab (ribbon) | Living Curves ribbon | S49 | BUILT: LabRibbons.swift | |
| /lab/ar | Gyro AR curves | 07-07 | BUILT: LabAR.swift | |
| /lab/ar-surface | 8th Wall SLAM AR | 07-07 | BUILT: LabAR.swift (ARKit world tracking, same file) | |
| /lab/curve-who | Claymation study | 07-01 | BUILT: Lab3D LabCurveWhoView | |
| /curve-who | Claymation scroll reader (WIP): birth, storm, deep, signing | 07-01 | PARTIAL: only the orbit clay figure exists | scroll-driven colour morph and dissolve to Totem |
| /lab/dance, glyphbot, heart, wordmark, nft-candidates (cards) | 3D pieces | S49 etc | BUILT: Lab3D + ThreeD/GlyphGuyRoom (16 clips) | |
| /lab/fluid, fly, glitch, glyph-plotter, kinematic, phyllotaxis, reaction-diffusion, warp, webgpu-probe, life, golden-mend | Shader and generative labs | S49, S282, 09-02 | BUILT: LabMetal, LabFly, LabRibbons, LabSketches | |
| /lab/home, study, trained-hero, /components, hand.html, living-curves-art | Scroll studies, hero grammar, type lab | | BUILT: LabHero, LabStories, LabCurveMotion | |
| /lab/room | Scroll room + world gallery (WorldGalleryLab, ScrollRoomLab); has capture/still modes | S49 | MISSING (grep ScrollRoom/WorldGallery: no hits) | scroll room + world gallery scene |
| /lab/shirt | ShirtPreview cinematic, angle param, capture page | S49 | MISSING (no hit) | shirt 3D preview; mostly a capture target for video renders |
| /defiance/the-haul, the-money-room, the-weight | Walkable Defiance worlds | 06-19..25 | BUILT: Worlds HaulWorld, MoneyRoomWorld, WeightWorld | |
| /manifestation-preview | Private decoy board, fabricated numbers, no data | 07-07 | EXCLUDED: mock/decoy, no use | |
| /vj-preview.html | VJ embed preview | | EXCLUDED: preview iframe | |
| (components) /fly static | The fly | S282 | BUILT: LabFly | |

Counts (about 58 routes grouped to 52 rows): BUILT about 47 routes, PARTIAL 1 (/curve-who), MISSING 2 (/lab/room, /lab/shirt), EXCLUDED 4 (two embeds, vj-preview, manifestation-preview).

## 3. pl-composer (C:\dev\pl-composer)

| route | what it is | built in | native status | gap |
|---|---|---|---|---|
| / | Board: asset browser, spec sheet, graph canvas, transition picker | S267 and earlier | BUILT: Sections/Composer (Board, Graph, Library, Piece, Store; web is the secondary body) | |
| (second page) | Only app/page.tsx found; app/api only | | n/a | the "2 pages" is 1 page + api |

## 4. pl-r1 (13 html) decisions

| route | what it is | decision | native status |
|---|---|---|---|
| / | install page for the R1 | EXCLUDED, R1 only | |
| /academy | academy companion (240x282) | EXCLUDED as R1 shell; academy itself is gap, see section 1 | |
| /archive | archive viewer | EXCLUDED, native ArchiveRoom covers | BUILT elsewhere |
| /codex | codex draw card | R1 only; phone has Codex tool | BUILT (CodexToolView) |
| /curves | redirect to /library | EXCLUDED | |
| /fleet | stack health pocket | R1 only; phone has StackHealthView | BUILT |
| /games | PL tarot (oracle draw) | phone should have it? private randomizer, R1 toy | MISSING, low value |
| /jarvis | traffic-light Office state | R1 only | MISSING (low) |
| /library | R1 curve viewer | EXCLUDED, native CurvesRoom | BUILT |
| /oracle-pocket | ask oracle with PTT | EXCLUDED, GlyphBot | BUILT |
| /plos | pl-os board for R1 | EXCLUDED, House | BUILT |
| /practice | practice streak, affirmations | EXCLUDED, Sections/Practice | BUILT |
| /seeds | seed phrase draw | phone should have a seed draw | MISSING (no native "seed draw"; seeds appear only in Curate class) |

## 5. Workers with no local pages

| worker | serves | decision |
|---|---|---|
| pl-academy | HTML pages: / (curriculum), /read?k= (markdown reader), /forge (prompt forge), /drills (persona drills + /api/drill/rewrite grader) | MISSING natively (gap #1) |
| pl-live | WebSocket DO + /health, no page | EXCLUDED |
| pl-render | /dashboard wrist card (image render for watch), /render, /status | EXCLUDED as page; Services/AppleWatch.swift exists |
| pl-audit | key-gated HTML audit dashboard + /run (pass/fail counts) | EXCLUDED admin tooling; optional MISSING |
| pl-xr | Quest WebXR board (site/ + worker) | EXCLUDED (Quest device) |
| pl-world, pl-world-b | game | EXCLUDED by founder |

## Real gaps, ranked

1. pl-academy (Reader, Forge, Drills, curriculum) + pl-os /academy. Port from C:\dev\pl-academy\src\index.ts (homePage, readerPage, forgePage, drillsBody, /api/drill/rewrite, /api/forge, /api/ask) and C:\dev\pl-os\app\academy\page.tsx (SECTIONS). Swift: new Sections/House/AcademyViews.swift, replace the Link at MoreViews.swift:31 and the WebPage at Congregation/AccountViews.swift:242 (that one breaks "no web views").
2. /jarvis board chat. Port from C:\dev\pl-os\components\JarvisRoom.tsx + lib\jarvis-api.ts. Swift: new Sections/House/JarvisView.swift, replacing the Link at HouseSection.swift:282. Needs Tailscale to reach :8800; value only when home network is reachable.
3. /curve-who scroll reader. Port from C:\dev\pl-curves-gallery\app\curve-who\page.tsx. Swift: extend Labs/Lab3D.swift LabCurveWhoView with a scroll-driven morph.
4. /lab/room (ScrollRoomLab + WorldGalleryLab). Port from C:\dev\pl-curves-gallery\components\room\ScrollRoomLab.tsx and components\world\WorldGalleryLab.tsx. Swift: Labs/LabStories.swift plus a new case in LabsRoom.swift.
5. R1 seed draw (public\seeds\index.html in C:\dev\pl-r1) as a phone seed-phrase draw. Swift: Sections/Practice or Curate. Low.
6. /lab/shirt ShirtPreview (C:\dev\pl-curves-gallery\components\cinematic\ShirtPreview.tsx). Swift: Labs/Lab3D.swift. Low (render-capture target).
7. R1 /games tarot (C:\dev\pl-r1\public\games\index.html; calls pl-cron /api/oracle). Swift: Sections/Practice. Low.
8. Unverified small items: web Catalog sticky colourway grid vs native list (CatalogMatrixRoom.tsx vs RoomViews.swift CatalogMatrixView); Brains status panel (components\BrainsStatus.tsx); kit/glass/showcase.html.

## Counts
- pl-os: BUILT 17, MISSING 2, PARTIAL 0 (19)
- gallery: BUILT ~47, PARTIAL 1, MISSING 2, EXCLUDED 4
- composer: BUILT 1
- r1: BUILT-elsewhere 8, EXCLUDED 3, MISSING 3 (games, jarvis, seeds; all low)
- other workers: MISSING 1 (academy), EXCLUDED 6
