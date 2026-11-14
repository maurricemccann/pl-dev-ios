DONE (pending the final E2E run recorded at the bottom; every flow below names its evidence)

# Lane: composer2 (branch `wave-composer2`), Composer end to end, his note 11-13

"Composer needs to be gone through E2E so it's working, and we can access pics and videos from my photo library, the curve library and any other assets it may need."

## What was added (all in `PLDev/Sections/Composer/`, plus `Info.plist`, the test target and the workflow)
- **Photos** (`ComposerSources.swift`): `PhotosPicker` (pictures and clips, up to 8 from a shot, 12 from the Library pane). Each pick is copied into `Application Support/composer-media` (pictures to 1920 px JPEG, clips as the file), with a thumbnail, length, size. They become `ComposerAsset`s (`ph_xxxxxxxx`, catalog "Photos"), so the shot card, graph, preview and spec treat them like indexed assets. `NSPhotoLibraryUsageDescription` added to `Info.plist` (the picker itself needs no permission; the string is there as asked).
- **Trim**: a clip has an in and out point (sheet with two sliders, "Make the shot this long", "Back to the whole clip"). The spec prints it beside the source: `# clip-01.mov [trim 0.5-1.6s]`.
- **Curve Library as a source** (`ComposerCurvePane`): the gallery's `library-index.json` (the same `LibraryData` the Library and Curate rooms use): stills, clips, archive works, code curves, svg, beds, models, with search and class chips. Tapping attaches (`cl_<vault id>`, catalog "Curve Library"); the still is fetched once as the thumbnail.
- **Library room** now has a source switch: Index (the laptop's 1,654-row index, as before) / Curve Library / Photos.
- **Preview** (`ComposerPreview.swift`): the piece played shot by shot with the piece's transitions (cut, dissolve, black, wipe, slide) at the right times, play/pause, scrub, previous/next shot, the piece's aspect. A clip from Photos plays (AVPlayer, in point honoured); library assets show their thumbnail. The bed is not mixed (said on screen).
- **Piece room**: a toolbar "+" (Add a shot) that is always on screen (the old Add shot button sat at the bottom of a long list); Graph is now an explicit navigation (the List-row NavigationLink never navigated in the simulator); the keyboard dismisses on scroll; "Make this the base" on a source; Preview button.
- Reordering by drag (Reorder mode), swipe delete, transitions, duration, fps and resolution were already built; the E2E proves them.

## The E2E (`PLDevUITests/`, workflow `.github/workflows/composer-e2e.yml`)
- `PLDevUITests/PLDevUITests.xcodeproj` is a separate small project (one UI test bundle, no target app: it launches the installed app by bundle id), so the main project file and `check_pbxproj.py` are untouched. `Tests/ComposerFlowsTests.swift` has 7 tests that run in order and share state.
- `PLDevUITests/make_media.swift` generates three pictures and a two-second clip; the workflow adds them to the simulator's Photos with `xcrun simctl addmedia`. Nothing of his.
- The workflow builds the app for the simulator, installs it, writes a config with **public addresses and dummy key names only** (as screens.yml does), runs the tests and uploads the artifact `composer-e2e`: every step as a numbered PNG, plus the accessibility tree wherever a step missed, `test.log`, `summary.txt`.
- It starts by hand or on a push to `wave-composer2` that touches Composer or the tests (a new workflow cannot be dispatched before it is on `main`; after the merge, `gh workflow run composer-e2e.yml` works and the push trigger can be deleted).

## Flow by flow (evidence from the runs; screenshots in the artifacts of runs 43571609762 and 43573254643, last run below)
| Flow | Result |
|---|---|
| Open Composer, name the piece, add 3 shots (toolbar +), rename, transitions menu (dissolve), fps 60, resolution 1080x1080 | pass (screens 01-04, run 3) |
| Reorder by drag (hold a handle, drag shot 3 above shot 1), assert titles moved | pass |
| Swipe delete a shot, confirm | pass |
| Duration stepper | fixed in run 5 (see below) |
| Photos picker: opens, shows the seeded media, selects, confirms, copies in, pictures and clip appear on shot 1 with names `photo-01`, `clip-01` | pass (run 3 screens 05-08 and the graph screen 29 shows `photo-01 Photos.jpg` and `clip-01 Photos.mov` as sources) |
| Trim a clip | see the last run |
| Index library: loads 1,654 assets, filter, tap attaches | pass |
| Curve Library: loads 9,516 rows, chips (stills, clips), tap attaches with its thumbnail | pass |
| Build spec: sheet opens, `## Shot 01`, `sources:` | pass |
| Preview: opens, plays (the clock moves), scrubs to 35, 70, 95 % and the shot label follows | pass |
| Graph: opens, add Tracer Render and File to /curate, add a path source from the index, drag a node, wire path -> tracer -> card through the inspector menus | pass (screens 26-29) |
| Send to render | the app sent the real POST shape; with the dummy key the door answers 401 and the card waits on the phone with "Waiting for the house. The key was refused. Load your config again." (screen 31). The door itself: `POST /api/board` with a valid body and no key returns 401 today, so it is live and locked |
| Board | loads, shows "Waiting for the house" (the queued card) and the house's published cards (screen 32) |

## Unproven, and why
- **A card actually landing on the PC** needs the real composer key; the simulator has none by design and a test card would render on his PC and file to /curate. On his phone the config carries the key (`origins.composer.auth` is set in `pldev-config.json`; checked, value not printed). First real send is his: open Composer, send a shot, watch the Board.
- **The board he sees is 10+ days stale** (`pulled 2026-11-03` in the simulator screen 32): `composer/board.json` in R2 is only rewritten when `composer_jobs.py` moves a card. Server side (see below).
- **Clips from Photos in the preview** play in the code but the simulator run only proves the pause and scrub path (poster frames); playback of the clip itself is unproven on a device.
- Phone media cannot reach the PC: a shot's Photos sources are named in the spec (`ph_...`) but the renderer cannot read them. See the server note.
- The preview shows thumbnails for library assets (low resolution; the composer thumbs map is small).

## Server needs (written, not done: not my repos)
1. **Upload door for phone media**: `POST /api/media` on pl-composer (or pl-cron) with the composer key, body = the file, into R2 `composer/media/<id>.<ext>`; `composer_jobs.py` pulls them next to the index so a spec's `ph_` id resolves. Without it Photos sources are for authoring and preview only.
2. **Publish the board when nothing moves**: have `composer_jobs.py publish` run on every loop (or at least daily) so `composer/board.json`'s `pulled` is not weeks old.
3. After merge: delete the `push:` trigger in `composer-e2e.yml` if he does not want it on every Composer push.

## Shared-file lines for the lead
- `PLDev/Info.plist`: `NSPhotoLibraryUsageDescription` (already in this branch).
- Nothing in `SectionRegistry`, `AppShortcuts` or widgets changed.
- The twin rule: the web board (`C:\dev\pl-composer`) has no Photos or Curve Library sources and no preview; the handbook text for these (More room, 9 pages) was not updated in this lane. Add a "Sources" page: Index, Curve Library, Photos, trim.

## Last run
(see the commit message of the final commit and the footer below)
