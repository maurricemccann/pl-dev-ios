DONE (site lane, branch `wave-site`, `PLDev/Sections/Shop/` only)

Built from the real web source of each page (pl-headless `app/…` and `components/…`), with the live data the page reads. Compile check green (`build.yml`, publish=false); screens run on the simulator, every new screen looked at.

## What was built (GAPS-site.md items 1 to 13, 16, 17)
| gap | screen | file | data |
|---|---|---|---|
| 1 Home | `ShopHomeView`: hero over the gold curves, proof band, thesis, Three Truths, New Drop row, four doors, Forge, congregation wall, closing line. Above the grid on the Shop tab; a search or filter goes straight to the pieces. | `ShopHomeView.swift` | live archive count (manifest), shop pieces, wall declarations read off the live home page |
| 2 Wardrobe | `WardrobeView`/`WardrobeCard`/`WardrobeStage`: RealityKit turntable + Apple AR Quick Look. The piece page's web sheet (`ShopViews.swift:383`) is gone. | `SiteWardrobe.swift` | the site's own `…/3d/<slug>.usdz` (already on R2 for iPhone AR, so no conversion and no model in the repo). All three models are `hidden: true` on the site (his S308 ruling: model does not match the garment sold), so the page shows its words, the doors and one quiet line, exactly as the site redirects away today. Flip a `hidden` flag in `WardrobePiece.all` when he un-hides one |
| 3 Seeds | 2019/2026/2029 window, "you are here" in his hand, live countdown to April 19 2029 (Pacific midnight, still under Reduce Motion), closing line | `SiteCollectionPages.swift` | the site's words |
| 4 Glyphs | manifesto, GlyphBot pair (his model, hammered gold and clay), the four glyph cards (masked glyph PNGs), the set line | same | his `glyphguy-v4` USDZ; glyph PNGs from the site |
| 5 Heart + World | the Heart: manifesto, 3D heart coin (his heart1.usdz, true gold), the spinning ring. `/world` (`SiteWorldView`): hero, every collection as a tile with its own glyph pattern (`TileGlyphs`, seeded as the site's), manifesto, "The signal, live" (his newest Instagram posts) | `SiteCollectionPages.swift`, `SiteWorldView.swift`, `SiteDesignGlyphs.swift` (generated from `lib/design-glyphs.ts`) | pl-cron public `api/ig-feed` |
| 6 Chosen + archive strips | `ChosenView`; archive tab now carries Living Curves, the B&W GlyphGuy, the Mirror doors (each opens its native Lab), the Chosen strip, the close, the Wardrobe (while a model is visible) and the Sanctuary | `SiteChosen.swift`, `SiteArchiveStrips.swift`, `ArchiveViews.swift` | live `/chosen` page (see route request 1) |
| 7 Work meta rows | Body of Work, Pillar, Category, Medium, Year, and the Chosen badge on a work | `ArchiveViews.swift` | the manifest fields already decoded |
| 8 Living Curves | I to VII ported line for line from `components/art/sketches.ts` (cloth + blood from one engine, transmission, field with p5's own `noise()`, spiral = the Labs' view, chain, the Mind force graph); source page reads the live page's code blocks | `SiteLivingCurves.swift` | live `/catalogue/living-curves/source` |
| 9 Study | the opening, the name, the mechanism, the practice, sixteen concepts + three beyond, each opening to a reflection kept on the phone only (the site's `pl-study-<roman>` keys), the Mirror, the close | `SiteStudy.swift`, `SiteStudyConcepts.swift` (generated from `lib/study-concepts.ts`) | |
| 10 Curve name ritual | "You were gifted a seed.", GlyphBot waving, three seals held 0.9 s to stamp, social doors, the name in Curvedabc, saved as a 1200 x 400 picture, the register door (the site's human-check form, Apple's sheet) | `SiteCurveName.swift` | his heart mark read from the site's `logo.svg` |
| 11 System | every section of `/system`: veils you tap to part, the architecture laid flat, the fleet (his vector plates read from `/fleet/*.svg`), the workflow, receipts with the live archive count, the dialogue by model, the record drawn from its own numbers (`TelemetryFigure`, same seeded figure), the timeline, laws, bodies, under the hood, the inner veil (sealed for a stranger, his own mark for a member) | `SiteSystemView.swift` | pl-cron public `api/stats` |
| 12 /tag | `SiteTagView`; opens by `pldev://section/shop/tag/<tag>` | `SiteTagView.swift` | live `/tag/<tag>` page |
| 13 /room | `SiteRoomView` in RealityKit: the gallery, his heart on the wall, six drawings in the niches, GlyphGuy beside the door ajar, the site's keyframed camera path as a 16 s tour with a drag to scrub, "Enter the congregation", leave. Opened by the hero's "Enter the room". | `SiteRoomView.swift` | `/room-art/*.png`, `logo.svg` |
| 16 Journal | `SiteReaderView` with the gold line; in the Pages list and More | `ShopMoreViews.swift`, `ShopSystem.swift` | |
| doctrine art | the reader keeps each page's art: Three Truths = gold curves + the faint flow field, Forge = the corridor footage scrubbed by scroll, Brand/Journal = the gold line under headings | `SiteReaderArt.swift`, `SiteReader.swift` | `/videos/forge-corridor.mp4` |
| new rooms | `ShopRoom` gained: world, wardrobe, chosen, living-curves, source, study, curve-name, system, room, journal (listed under More; `pldev://section/shop/<room>`, Spotlight and Siri pick them up through the existing entity) | `ShopSystem.swift` | |

No web view anywhere in these screens. Sheets used: Apple's secure sheet for the register form only (as before). AR Quick Look is Apple's own viewer.

## Screenshots checked (simulator, looked at each)
home hero and proof band, Wardrobe, Collections, Chosen (empty line, the live record is empty today), Living Curves (cloth running), the source (code), Study, More list, Room (heart, door, GlyphGuy, Enter), Journal, Seeds (window), Glyphs, Heart, #seeds (live posts), System (hero, law, flow, fleet plate, veil, telemetry, inner veil), the curve page parts and the archive's featured card. Fixed from them: dead space at the top of dark bands; the gold-curves layer sat unsized inside a scroll view and froze System (now a background); the same greedy-layer freeze on the curve page (now a background); GlyphGuy lay flat (now the upright model); cloth sketch opened blank (now pre-warmed). **Last compile after the final fix is green; the curve page and Glyph pair were not re-screenshotted after it** (see "left").

## Server routes wanted (for the lead; nothing edited in pl-headless)
1. **`GET /api/chosen`** → `{ ok, entries: [{ chosen_no, cr, product, fourthwall_url, created_at }] }` from `listChosen()` (`app/actions.ts:423`), public, `Cache-Control: s-maxage=300`. Today the app reads the live `/chosen` page; when this lands only `ChosenStore.load` changes.
2. **`GET /api/tag/<tag>`** → `{ ok, posts: [{ id, body, media_url, author_handle, created_at }] }` from the query in `app/tag/[tag]/page.tsx` (`load`). Today the app reads the live tag page. Only `SiteTagView.load/parse` changes.
3. **`GET /api/desires`** (approved only, limit 3, `{ text, name, anon }`) for the home page's wall. Today parsed off the home page's HTML (`ShopHomeView.parseDesires`).
4. **Signal form (item 17).** `ShopSignalView` posts `api/signal`, which does not exist, so it always ends in the sheet. The site's signup is the server action `subscribe(email, source, token)` (`app/actions.ts:53`), which **requires a Turnstile token** (`verifyTurnstile`, fail-closed). A route that takes `{ email, source }` with no token would be an unguarded public write, so it must not be added as is. Either add `app/api/signal/route.ts` the way `app/api/contact/route.ts` does it (token required, native form gets the token from the same Apple sheet flow `SiteHumanCheck.swift` uses for contact), or drop the native form and keep the sheet, which is what happens now. **I left the sheet in place and did not touch `ShopSignalView`.**
5. LANES-storefront.md still says the order detail is "not built"; `OrderDetailView` exists (`ShopOrders.swift`). Lead's file, not edited.

## Lines for the lead to wire
- `CongregationSkin.swift:291` (not my file): a tapped hashtag opens `Site.page("tag/…")`; change to `pldev://section/shop/tag/<tag>` so it opens `SiteTagView`.
- Nothing else shared is needed: new rooms ride the existing `ShopRoom` entity; no new App Shortcut, no `Info.plist` or project change (the app already links RealityKit, QuickLook, AVFoundation).
- `SiteGlyphMask`, `SiteKit.swift` helpers and `SiteLogo.parse` (a potrace/Inkscape path reader) are reusable by other lanes.

## Left, with the reason
- **Forge course pages and the Interviewer**: skipped as briefed.
- **The Wardrobe's 3D stage is built but shows no garment today**: all three models are hidden by the site's own flag (S308). Untestable on the simulator for that reason; the turntable shares `OrbitStage` with the Lab heart, which does render.
- **Not re-screenshotted after the last fix**: the curve-name page (its freeze fix is by elimination: every piece rendered alone, the page did not) and the Glyph pair's closer camera. Worth one look on the device or one more `screens.yml` run: `links='section/shop/curve-name section/shop/collection/glyphs'`.
- **GlyphGuy's partner "her"** is the same model in clay; the site's `buildHer` (her dress) is not ported.
- **Press-and-hold seals, Quick Look AR, the Room's drag-scrub, the corridor scrub: none were tried on a device.** The simulator has no touch history or AR.
- **Home "New Drop" row** shows the first four pieces of the site's own order, not the site's `getFeaturedProducts()` favourites-first order (that order is server-side, no route).
- **Sizes, no live widget/Live Activity for these screens**: static story pages, not fitting (no start/end, no live count beyond the archive count the Shop widget already carries).
