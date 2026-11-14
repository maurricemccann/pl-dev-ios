# PL DEV native coverage: public sites (pl-headless, the-forge, pl-interview, pl-manifestation-practice)

Method: web side = every `app/**/page.tsx` read; native side = grep of `C:\dev\pl-dev-ios\PLDev\Sections\*` (all native work is S348·9a3e, 2026-11-12/13; see LANES-*.md).
"Built in (sessions)" = the S-numbers found in each page's git history (creation commit first), plus sessions whose transcripts mention the route (one pass over all 224 transcripts with `pl-ask-session` logic; fingerprints there are the most-frequent one per transcript, so treat them as "discussed", not "built"). S271 and S334 are repo-wide rename/cascade sweeps, not page builds.
Founder words are quoted only where a code comment or transcript line carries them.
Status key: BUILT / PARTIAL / SHEET (Apple secure sheet, allowed only for checkout, human-check forms, size guides) / MISSING / EXCLUDED.
"The text reader" = `Shop/SiteReader.swift` (`SiteReaderView`): fetches the live page, draws h1-h4, p, li, blockquote natively; drops forms, svg, nav, animation and any art. Section: all Shop pages sit under the `shop` section (`ShopSection.swift`, tabs Shop / Closet / Archive / More).

## 1. pl-headless (psychedluxuries.com), 65 pages (the brief said 71; `find app -name page.tsx` returns 65; `app/philosophy`, `app/sanctuary`, `app/dev/square-test` are empty dirs and `/philosophy`, `/sanctuary` are 308s in next.config.ts)

| route | what it is | built in (sessions) | native status | gap |
|---|---|---|---|---|
| `/` | Home: hero + "Since April 2019", thesis, doctrine, New Drop (Seeds) product row, Collections, Enter the World doors, The Forge teaser, Congregation CTA | 2026-06-02 initial; S110 S128 S142 S149 S154 S295 S308 | MISSING | No native home. `rg "Wear the argument\|The Thesis\|Enter the World"` finds only a button in `Congregation/StreamViews.swift:352`. The shop opening (`ShopGridView`) carries the shop page's lede and the three collections, not the home page. |
| `/shop` | The shop grid, 89 pieces: collections shelf, filter drawer (garment, line, price), 3 orders, search, the Closet above the grid | init; S104 S154 S238 S347 | BUILT | `Shop/ShopViews.swift:76` `ShopGridView` + `ShopCollections.swift` (`CollectionsShelf`, `ShopFilterSheet`) + `ClosetView.swift` tab. Not ported: marquee, OrderConfirmedBanner, "?debug=open" founder cards. |
| `/shop/[slug]` | Piece page: gallery, variants (design/colour/size), price, buy, sticky bar, provenance, size guide, details/care/delivery folds, argument, digital twin | init; S222 S238 S240 S241 S308 S310 S316 S345 | BUILT | `ShopViews.swift:229` `PieceView` (+ `SizeGuideView`, `SiteFold`, `ShopSitePages.swift` PieceDetail). Buy opens Square checkout in the secure sheet (allowed). |
| `/collections/[slug]` | A collection's pieces | init; S271 (S206 S266 S292 discussed) | BUILT | `ShopCollections.swift:272` `CollectionView`; same name tests as `lib/square.ts` COLLECTIONS. |
| `/gift-card` | Digital gift card picker, Turnstile-gated purchase | S235 (2026-08-26, Heart Mark Gift Card) | SHEET | `ShopMoreViews.swift:121` `SitePagesView` opens `gift-card` in `SafariSheet`. Allowed (checkout + human check). |
| `/orders/track` | Guest order lookup (email + order number) | audit fix 2026-08-22 | BUILT | `ShopMoreViews.swift:22` `TrackOrderView` (calls `api/orders/lookup`). |
| `/orders/[id]` | Signed-in order detail: tracker, line items, totals, address | S222 (2026-08-19) | BUILT | `ShopOrders.swift:136` `OrderDetailView`, linked from `MyOrdersView` (`ShopOrders.swift:92`). Note LANES-storefront.md still says "not built"; the code says built. |
| `/contact` | Contact form, Turnstile | init; S154 S266 | BUILT | `ShopContactView.swift:35` `ContactView`; the human check runs in Apple's sheet (`SiteHumanCheck.swift`, `ShopContactView.swift:145`). Allowed. |
| `/signal` | The Signal signup landing, email + Turnstile | S335 (2026-09-01); S289 S342 discussed | SHEET | `ShopSignalView.swift:7` `SignalView` is a native form, but it posts to `api/signal`, which does not exist in `pl-headless/app/api` (no `signal/` folder), so it always falls back to `Site.page("signal?src=app")` in the sheet (line 49). Allowed (sign-up behind human check). |
| `/the-brand` | Brand statement page | init | BUILT | The text reader: `ShopMoreViews.swift:125` (path `the-brand`). Text only; GoldCurves/motion not drawn. |
| `/the-three-truths` | The Three Truths | 2026-06-11 cascade; S295 | BUILT | The text reader, `ShopMoreViews.swift:125`; also linked from `PieceView` (`ShopViews.swift:400`). |
| `/three-bodies` | Three Bodies of Work | init | BUILT | The text reader, `ShopMoreViews.swift:126`. |
| `/the-forge` | Discovery page for THE FORGE course | 2026-07-30 | BUILT | The text reader, `ShopMoreViews.swift:126`. TheBasement art not drawn; the course itself is a separate site (section 2). |
| `/returns` | Returns & FAQ (h2 + p) | init; S154 | BUILT | The text reader, `ShopMoreViews.swift:129`. |
| `/terms` | Terms of Service | init; S316 | BUILT | The text reader, `ShopMoreViews.swift:131`. Legal; readable. |
| `/privacy` | Privacy policy | init; S171 S316 | BUILT | The text reader, `ShopMoreViews.swift:131`. Legal; readable. |
| `/catalogue` | The Archive: complete-works viewer (iframe), Living Curves showcase, Mirror doors, The Chosen strip, compact Wardrobe, CTAs | init; S104 S144 S148 S308 | PARTIAL | Viewer is native: `Shop/ArchiveViews.swift:166` `ArchiveView` (manifest, search, lenses, favourites, ballot). Missing from the page: LivingCurvesShowcase, MirrorDoors, ChosenSection, WardrobeGrid (LANES-shop.md says so). |
| `/catalogue/[cr]` | One archive work: image, meta rows (Body of Work, Pillar, Category, Medium, Year), request widget, share, prev/next | 2026-06-13 (S33 checkpoint); S295 | PARTIAL | `ArchiveViews.swift:342` `ArchiveEntryView`: image, note, `RequestBallot`, `ArchivePin`, share, prev/next. No grep hit for Body of Work / Pillar / Medium meta rows. |
| `/catalogue/living-curves` | Living Curves: seven p5 sketches I-VII (Cloth, Cloth in Blood, Transmission, Field, Spiral, Chain, Mind) with copy | 2026-06-13; S292 S295 discussed | PARTIAL | No page with the I-VII order and copy. Sketches exist elsewhere: Cloth and Red cloth/Matrix in `Labs/LabCurveMotion.swift`, Spiral = `LabPhyllotaxisView`, Chain = `LabKinematicView` (`Labs/LabSketches.swift:112,146`). No Field (flow field) and no Mind (slime-mold colony): `rg "slimeMold\|The Mind"` hits nothing in Labs. |
| `/catalogue/living-curves/source` | The exact code of the seven algorithms | 2026-06-13 | PARTIAL | `Library/GalleryRooms.swift:591` `ToolsRoom` + `SourceView` shows every code piece's source from `/api/source`; not the page's seven-algorithm listing. |
| `/chosen` | The Chosen: numbered record of requested pieces made real | 2026-06-11 (Request & Vote); S266 S330 discussed | MISSING | No native page. A member's own chosen works show on `MemberView`, not the public record. |
| `/living-curves` | Redirect to `/catalogue/living-curves` | init | EXCLUDED | Redirect. |
| `/movement` | Permanent redirect to `/study` | S104 | EXCLUDED | Redirect. |
| `/products/[slug]` | Fourthwall-era redirect to `/shop/<slug>` | S282 | EXCLUDED | Redirect (SEO bridge). |
| `/glyphs` | Glyphs collection: manifesto, GlyphBot hero (3D pair), glyph vocabulary cards, product grid | init; S218 S295 S310 | PARTIAL | Glyph pieces are native as a collection (`ShopCollections.swift`, "Glyphs"). Not ported: the page's manifesto copy, vocabulary cards, the 3D GlyphBot hero pair (`components/glyphbot/GlyphBotHero.tsx`). |
| `/seeds` | Seeds 2026-2029: timeline (2019/2026/2029), SeedsCountdown, product grid | init; S334 (S304 S305 discussed) | PARTIAL | Seeds collection with "Closing 2029" pill (`ShopCollections.swift:237`). No timeline, no countdown (`rg countdown` in Shop: nothing). |
| `/the-heart` | Permanent collection: manifesto, 3D spinning ring, Heart pieces | init | PARTIAL | "Classic / Permanent Collection" shelf with its blurb and the `heart-logo` collection (`ShopCollections.swift:35,62`); 3D heart is `Labs/Lab3D.swift:11` `LabHeartView` (lab, not on this page). No manifesto page. |
| `/world` | The Collections page: tiles, glyph tiles, IG feed, doors | init; S295 S308 S311 | PARTIAL | The three collections are native (`CollectionsShelf`); the page's intro, TileGlyphs, IgFeed and doors are not. |
| `/wardrobe` | Garments rendered in 3D (WardrobeGrid, model viewer) | 2026-06-14; S296 S308 discussed | MISSING | Only a link: `ShopViews.swift:383` opens `Site.page("wardrobe")` in a web sheet. That is not an allowed sheet use (not checkout, human check or size guide). No native 3D garment viewer. |
| `/study` | The Study: mechanism, "The luxury is not a garment", sixteen concepts + beyond | init; S308 S332 discussed | MISSING | `Labs/LabStories.swift:17` `LabStudyView` is the `/lab/study` door-and-Three-Truths scene, a different page. No native `/study` (sixteen concepts). |
| `/system` | The apparatus: live stats (pl-cron `/api/stats`), flowchart, system map, telemetry | 2026-06-15; S160 S282 S295 S308 | MISSING | No `/system` view. (`House/*` reads `api/stats` for the founder console, not this public page.) |
| `/journal` | "Words from the Architecture": placeholder, journal is being written | init; S338 discussed | MISSING | Nothing native. Low value: the page itself is a "coming" placeholder. |
| `/curve` | Seed-card tap page: type your name, see it in the house alphabet (CurveNameRitual), register door | 2026-08-07 (Curvedabc + GlyphBot); S218 S295 | MISSING | `rg "house alphabet\|CurveNameRitual"` finds nothing. Only `/curve-live` is ported. |
| `/curve-live` | Homepage gold-curve hero alone, full screen on black (the phone widget opens it) | S295·21ca (2026-09-27) | BUILT | `Shop/SiteCurve.swift:154` `CurveLiveView` (GoldCurves ported line for line; Rooms: `ShopRoom.curve`). |
| `/register` | Seed COA registration: name, email, photo, Turnstile | 2026-09-17; S284 S331 discussed | SHEET | `Congregation/AccountViews.swift:115` opens `Site.page("register")` in the sheet. Allowed (human-check form). |
| `/signin` | Sign in (email/password, Google) | S33 checkpoint; S269 | BUILT | Email+password sign-in is native in `AccountViews.swift:67` `AccountTabView`; Create account / Google / forgot password open the site sheet (`AccountViews.swift:115-116`), allowed. |
| `/reset` | Password reset (emailed link) | 2026-06-13 | EXCLUDED | Web-only recovery; the app sends people to the site (`AccountViews.swift:116`). |
| `/mark` | The member's own page: order history, pinned, profile, the climb, colour picker, badges | 2026-06-13; S104 S141 S295 | BUILT | `AccountViews.swift:67` `AccountTabView` (profile, glyph, accent, orders, pins, activity) + `Congregation/MemberViews.swift` (the climb). |
| `/member/[handle]` | Public member profile hub | 2026-06-26 (Phase 3a) | BUILT | `MemberViews.swift:168` `MemberView` + `MemberPostsView` (follow, climb, chosen works). |
| `/activity` | Bell: reactions, answers, follows | 2026-06-26 | BUILT | `AccountViews.swift:334` `ActivityView`. |
| `/congregation` | The room: stream, post feed, desire form, signal form, feed stream | init; S148 S308 | BUILT | `Congregation/CongregationSection.swift:94` (tabs stream/room/members/me): `StreamViews.swift`, `MembersRoomViews.swift`. Desire form wall posts go through the site's human-check sheet (`CongregationDesire.swift:121`, allowed). |
| `/congregation/moderate` | Moderation by key (desire wall approval) | init | EXCLUDED | Admin. Founder moderation is native in the room tab (swipes) per LANES-congregation.md. |
| `/tag/[tag]` | Every published post carrying #tag | 2026-06-26 (social app P5) | MISSING | A tapped hashtag only links out: `CongregationSkin.swift:291` `Site.page("tag/...")` opens the site, no native tag list. |
| `/room` | The Room: scroll-driven 3D tour, Enter door to /congregation | 2026-06-13; S319 S340 discussed | MISSING | Not ported. `Worlds/*` are the Defiance worlds and archive walk (gallery pages), not this tour. |
| `/lab` | Lab index: GPU ribbon curves | 2026-06-15 | BUILT | `Labs/LabRibbons.swift:337` `LabRibbonView` (via `Labs/LabsRoom.swift:94`). |
| `/lab/home` | Home study: 2,000 curves drawn on scroll | 2026-06-17 | BUILT | `Labs/LabStories.swift:124` `LabHomeStudyView`. |
| `/lab/study` | The Study as a room: door opens on scroll, Three Truths | 2026-06-17 | BUILT | `LabStories.swift:17` `LabStudyView`. |
| `/lab/room` | WorldGalleryLab elevated Room (noindex lab) | 2026-06-17 | MISSING | No native counterpart (same gap as `/room`). Lab-only, low priority. |
| `/lab/warp` | Shader study (The Breath) | 2026-06-15 | BUILT | `Labs/LabMetal.swift:283` `LabWarpView`. |
| `/lab/reaction-diffusion` | Gray-Scott (The Seed) | 2026-06-15 | BUILT | `LabMetal.swift:400` `LabReactionView`. |
| `/lab/glitch` | Block glitch (The Mend) | 2026-06-15 | BUILT | `LabMetal.swift:288` `LabGlitchView`. |
| `/lab/glyph-plotter` | Four pens on fixed angles (The Hand) | 2026-06-15 | BUILT | `Labs/LabSketches.swift:73` `LabPlotterView`. |
| `/lab/phyllotaxis` | Golden angle (The Unfolding) | 2026-06-15 | BUILT | `LabSketches.swift:112` `LabPhyllotaxisView`. |
| `/lab/kinematic` | Five chains following (The Following) | 2026-06-15 | BUILT | `LabSketches.swift:146` `LabKinematicView`. |
| `/lab/closet` | Closet sandbox (S319: pickers studio/locker/grid/carousel; his word "Closet in sandbox") | S319·d4e8 (2026-10-14) | BUILT | `Shop/ClosetView.swift:74` `ClosetView` (studio picker only, flats only; the other three picker variants were a sandbox for his pick; no house-model renders used). |
| `/lab/congregation-gate` | Prototype threshold interaction (noindex, never crowned) | S151 (2026-07-18) | EXCLUDED | Lab prototype for a spec, "founder crowns before deploy"; not a shipped page. |
| `/the-mirror` | Door to the seven reflections (Mirror) | 2026-06-15; S216 S237 discussed | BUILT | `LabsRoom.swift:137` "The Mirror" section, eight pieces with numeral, line and technique (`LabsRoom.swift:68`). |
| `/settings` | This device: Design Kit settings panel, activity-bell kinds | S334·c5e2 (2026-10-25), S336 | BUILT | The app's own Settings: `ShopSection.swift:103` `ShopSettingsRows` + the shell's settings; bell switches per LANES-storefront.md. (His ruling S334: every app gets one.) |
| `/capture` | Founder intake page (key-gated): artwork, text, quote, link | init; S196 S308 S324 | BUILT | `Capture/CaptureSection.swift` (pl-os intake twin, `CaptureViews.swift`, `CaptureInputs.swift`). Founder tool, not a stranger page. |
| `/install` | Add to Home Screen instructions | 2026-06-26 | EXCLUDED | Web-only (the app is the install). |
| `/offline` | Service-worker offline shell | S295 | EXCLUDED | Web-only; the app has its own offline layer. |
| `/thank-you` | Post-purchase NFC packaging page | 2026-08-08 | EXCLUDED | Checkout/packaging return page. |
| `/onboard` | Beta tester onboarding (noindex): five steps + DeclareIntent | S33 checkpoint | EXCLUDED | Tester page, noindex. DeclareIntent is native in the congregation. |
| `/onboard/founder` | Onboard-a-tester (founder) | S33 checkpoint | EXCLUDED | Admin. |
| `/transmission/compose` | Founder publishes a transmission (mod key) | init | EXCLUDED | Admin. |

## 2. the-forge (forge.psychedluxuries.com), 8 pages

Origin: 2026-07-25 "THE FORGE v1 live" (S167-S172, S182, S191); product pages 2026-08-01 (S191 S292 S300 S333 S342). The course content is behind a Square entitlement (`getEntitlements(session_id)`). Native search: `rg -i "the-forge\|forge\.psyched\|field-notes\|enrolled"` hits only `Sections/Shop/ShopMoreViews.swift:126` (the text reader on pl-headless `/the-forge`) and the Town building label. `CodeArt/ForgeRoom.swift` is the gallery's AI piece generator, an unrelated "Forge". Also in the repo: `starter-kit/board/index.html` and `starter-kit/pwa/index.html` are files shipped inside the purchased kit (customer-side apps), not pages of the site: EXCLUDED.

| route | what it is | built in (sessions) | native status | gap |
|---|---|---|---|---|
| `/` | Explainer: title, Enroll, demo, curriculum, proof of work, enrollment, piece-by-piece (Vault/Skills/Installer), overview PDF | 2026-07-25; S191 S292 S300 S316 S333 | MISSING | Port from `C:\dev\the-forge\app\page.tsx`. Checkout buttons may open as sheet (allowed). The pl-headless `/the-forge` text page is read natively, but that is a different page. |
| `/product/[slug]` | One product page per SKU (kit, course, complete, vault, skills, installer): bullets, argument, price, checkout | 2026-08-01; S191 S292 S300 S333 S342 | MISSING | Port from `app/product/[slug]/page.tsx` + `lib/catalog`. Buy = Square checkout in the sheet (allowed). |
| `/enrolled` | Post-purchase: downloads per grant, links to course and field notes | 2026-07-25 | MISSING | Port from `app/enrolled/page.tsx`. Entitlement-gated (session_id). |
| `/course` | Gated index of 11 modules with progress badges | 2026-07-26 | MISSING | Port from `app/course/page.tsx`. Gated. |
| `/course/[num]` | One module's text with prev/next | 2026-07-26 (S169) | MISSING | Port from `app/course/[num]/page.tsx`. Gated. |
| `/course/field-notes` | Living field notes | 2026-07-26 | MISSING | Port from `app/course/field-notes/page.tsx`. Gated. |
| `/course/full` | Full-course listen player (audio via `/api/course-audio/[num]`) | 2026-07-28 | MISSING | Port from `app/course/full/page.tsx`. Gated. |
| `/lab/ribbon` | HAND validate-one ribbon hero experiment | 2026-07-26 | EXCLUDED | Experiment (the pl-headless ribbon lab is native, `LabRibbonView`). |

## 3. pl-interview (pl-interview.psychedluxuries.workers.dev), 1 page

Key-locked standalone Worker (`?k=` cookie), proxy to pl-cron `/api/interview/*`. Origin S297·255b (2026-09-29; founder: "I need a interviewer or a podcast partner through glyphbot"), then S298 S310 S314-S319.

| route | what it is | built in (sessions) | native status | gap |
|---|---|---|---|---|
| `/` (`public/app.html`) | GlyphBot Interview: Home (Let GlyphBot run it, Free talk, "The 501" bank card, domain doors), sitting (face, question, voice orb or text, thread), Record, Settings (phone vs cloud voice, pause length, speed, hands-free vs push-to-talk, theme/text/density, engine tags, seat label, motion, model auto/haiku/sonnet, deep, boldness, adventure, reply length) | S297 S298 S310 S314-S319 | PARTIAL | Native: `GlyphBot/GlyphBotViews.swift:178` `SittingModel` (Interview/Free talk, domain, pressure, length, "Go deeper", resume, "Hear it") + Record (`GlyphBotViews.swift:362` bank asked/answers/next round) + `GlyphBotAPI.swift` (turn/state). Missing: voice-in (orb, hands-free, push-to-talk, no `SFSpeech` use outside Capture), voice picker and cloud voices, pause and speed settings, the 501 bank card with progress bar on Home, per-domain doors, engine/seat labels, adventure and reply-length settings, theme/size/density. |

## 4. pl-manifestation-practice, 1 page

Key-locked PWA Worker with a Durable Object. Origin 2026-07-15 (S139 S144 S146 S147), later S310 S312 S322 S345.

| route | what it is | built in (sessions) | native status | gap |
|---|---|---|---|---|
| `/` (`public/index.html` + `app.js`) | The practice: Today (streak, Scratchpad, Wins & Noticed, Morning, Lesson, Reframe, Affirmations in his voice, Conversation, Desire List, Habits, Meditation (bloom/prism, rehearsal), Vision board, Evening) and Trends | S139-S147 S310 S312 S322 S345 | BUILT | `Practice/PracticeSection.swift` + `PracticeCards.swift`, `PracticeLifeCards.swift`, `PracticeMeditation.swift` (+ `PracticePrism.metal`), `PracticeBoard.swift`, `PracticeAffirmations.swift`, `PracticeTrends.swift`, `PracticeEntry.swift`; LANES-practice.md: "redrawn to match the live web practice, same order, same words". Not device-tested per that file. |

## Counts (statuses as above)

| site | pages | BUILT | PARTIAL | SHEET | MISSING | EXCLUDED |
|---|---|---|---|---|---|---|
| pl-headless | 65 | 32 | 8 | 3 | 10 | 12 |
| the-forge | 8 | 0 | 0 | 0 | 7 | 1 |
| pl-interview | 1 | 0 | 1 | 0 | 0 | 0 |
| pl-manifestation-practice | 1 | 1 | 0 | 0 | 0 | 0 |
| **total** | **75** | **33** | **9** | **3** | **17** | **13** |

BUILT includes seven pages served by the text reader only (the-brand, the-three-truths, three-bodies, the-forge, returns, terms, privacy: words faithful, art and motion dropped) and founder or device pages (`/settings`, `/capture`). The three SHEET rows are all inside the allowed list (gift-card checkout, register and signal human-check forms).
Two staleness notes found on the way: LANES-storefront.md still says the order detail page is "not built" (`OrderDetailView` exists); `SignalView` posts to `api/signal`, which is not in `pl-headless/app/api`, so it always ends in the sheet.

## Real gaps, ranked (most visible to a stranger first)

Order = how soon a stranger meets it. Plain-text pages can ride `SiteReaderView` first (one line in `Shop/ShopMoreViews.swift` `SitePagesView`); richer ports follow.

1. **`/` Home (MISSING).** First page a stranger lands on. Port from `C:\dev\pl-headless\app\page.tsx` (hero, thesis, doctrine, New Drop row, `components/home/Collections.tsx`, Enter-the-World doors, Forge and Congregation CTAs). Swift: new `Shop/ShopHomeView.swift`, shown above the grid in `Shop/ShopViews.swift` `ShopGridView`.
2. **`/wardrobe` (MISSING, and today a disallowed web sheet).** The 3D garments. Port from `app/wardrobe/page.tsx` + `components/WardrobeGrid.tsx` + `components/ModelViewer.tsx`. Swift: new `Shop/WardrobeView.swift` with RealityKit like `Labs/Lab3D.swift:11` `LabHeartView`; then replace the `Site.page("wardrobe")` sheet at `Shop/ShopViews.swift:383`. Needs GLB to USDZ conversion.
3. **`/seeds` (PARTIAL).** Missing the 2019/2026/2029 timeline and `SeedsCountdown`. Port from `app/seeds/page.tsx` + `components/seeds/SeedsCountdown.tsx`. Swift: `Shop/ShopCollections.swift` `CollectionView` (slug `seeds`), beside the "Closing 2029" pill (line 237).
4. **`/glyphs` (PARTIAL).** Missing manifesto copy, glyph vocabulary cards, 3D GlyphBot pair. Port from `app/glyphs/page.tsx` + `components/glyphbot/GlyphBotHero.tsx`. Swift: `Shop/ShopCollections.swift` `CollectionView` (slug `glyphs`); stage code exists in `GlyphBot/GlyphBotStage.swift`.
5. **`/the-heart` and `/world` (PARTIAL).** Missing manifesto, 3D spinning ring, tiles, doors. Port from `app/the-heart/page.tsx` (+ `components/art/SpinningRing.tsx`) and `app/world/page.tsx` (+ `components/world/TileGlyphs.tsx`). Swift: `Shop/ShopCollections.swift` (`CollectionView` for `classics`/`heart-logo`) and `Shop/ShopHomeView.swift` for `/world`.
6. **`/chosen` (MISSING) and the Archive page's strips (PARTIAL).** Public record of requested pieces; LivingCurvesShowcase, MirrorDoors, ChosenSection, WardrobeGrid on `/catalogue`. Port from `app/chosen/page.tsx` (data comes from a server action: read `components/catalogue/ChosenSection.tsx`) and `app/catalogue/page.tsx`. Swift: new `Shop/ChosenView.swift`; strips in `Shop/ArchiveViews.swift` `ArchiveView`, linking to the Labs/Mirror rooms that already exist.
7. **`/catalogue/[cr]` meta rows (PARTIAL).** Body of Work, Pillar, Category, Medium, Year. Port from `app/catalogue/[cr]/page.tsx` lines 67-72 into `Shop/ArchiveViews.swift:342` `ArchiveEntryView` (check `ArchiveWork`, line 7, carries the fields).
8. **`/catalogue/living-curves` I-VII and `/source` (PARTIAL).** The seven sketches with copy; Field and Mind sketches exist nowhere native. Port from `app/catalogue/living-curves/page.tsx`, `source/page.tsx`, `components/art/P5Sketch.tsx` presets `field` and `colony`. Swift: new page in `Labs/` reusing `LabCurveMotion.swift` and `LabSketches.swift` (Spiral, Chain) plus two new sketches; source listing in `Library/GalleryRooms.swift:591` `ToolsRoom`.
9. **`/study` (MISSING).** Mechanism, "The luxury is not a garment", sixteen concepts. Port from `app/study/page.tsx` + `components/study/Concept.tsx`. Cheapest: `SiteReaderView(path: "study")` in `Shop/ShopMoreViews.swift`; richer: new `Shop/StudyView.swift`.
10. **`/curve` (MISSING).** Seed-card tap page: type your name, see it in the house alphabet. Port from `app/curve/page.tsx` + `components/curve/CurveNameRitual.tsx` + `lib/curve-name.ts`. Swift: `Shop/SiteCurve.swift` next to `CurveLiveView`, or new `Shop/CurveNameView.swift`; the register door already exists as a sheet.
11. **`/system` (MISSING).** Public apparatus page with live stats. Port from `app/system/page.tsx` + `components/system/*` (data: pl-cron `/api/stats`). Swift: new `Shop/SystemView.swift`; cheap first step `SiteReaderView(path: "system")`.
12. **`/tag/[tag]` (MISSING).** Hashtag taps leave the app (`Congregation/CongregationSkin.swift:291`). Port from `app/tag/[tag]/page.tsx` (needs a JSON route in pl-headless first). Swift: tag list in `Congregation/StreamViews.swift`, link handled in `CongregationSkin.swift`.
13. **`/room` (MISSING).** Scroll-driven 3D tour with the Enter door. Port from `app/room/page.tsx` + `components/room/ScrollRoom.tsx` + `components/world/WorldGallery.tsx`. Swift: new `Worlds/RoomTourWorld.swift` on `Worlds/WorldsKit.swift`. Large; `/lab/room` is the same work, skip it.
14. **The Forge site, 7 pages (MISSING).** `/`, `/product/[slug]`, `/enrolled`, `/course`, `/course/[num]`, `/course/field-notes`, `/course/full`. Port from `C:\dev\the-forge\app\` (same paths). Swift: new `Shop/Forge*.swift`: explainer and product pages (Buy = Square checkout in the sheet, allowed); course pages are entitlement-gated by a Square `session_id`, so a sign-in-by-receipt decision comes first; `/course/full` needs an audio player (`/api/course-audio/[num]`). Founder question: does the course belong in PL DEV, or is the text page `/the-forge` the intended door.
15. **pl-interview (PARTIAL).** Voice and settings. Port from `C:\dev\pl-interview\public\app.html` (voice orb, hands-free vs push-to-talk, voice picker, pause and speed, 501 bank card, domain doors, adventure and reply length). Swift: `GlyphBot/GlyphBotViews.swift` (`SittingModel`; setup form ~line 270) and `GlyphBotAPI.swift` (`Settings`, add speak and usage routes). Needs a speech-recognition decision.
16. **`/journal` (MISSING).** A placeholder ("the journal is being written"); build only when entries exist. Port from `app/journal/page.tsx` via `SiteReaderView`.
17. **Housekeeping.** `SignalView` posts to a non-existent route (`Shop/ShopSignalView.swift` to `api/signal`): add `pl-headless/app/api/signal/route.ts` or drop the native form and keep the sheet. Update LANES-storefront.md (order detail is built).

Not gaps (checked by grep): all lab and mirror pages, `/curve-live`, orders, track, contact, congregation, members, activity, mark, settings, capture and the practice are native; legal and doctrine pages are readable through the text reader.
