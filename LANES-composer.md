DONE
# Lane: composer (wave 3), branch `wave-composer`

## Compile check: unproven for Composer (run 43521096235, publish=false)
The run failed on errors in other lanes' files in the merged base (Shop/ArchiveViews.swift `ArchiveWork` redeclared, ThreeD/ThreeDKit.swift, GlyphBot/GlyphBotStage.swift `FlowChips` redeclared). It reported no error in a Composer, Shared/Composer* or PLDevWidgets/Composer* file, but a redeclaration failure can hide later type errors, so Composer is not proven to compile. Re-run the check after the lead fixes those clashes and read the Composer errors then. Nothing was run on a device.

## What was built (twin of pl-composer: app/page.tsx, components/*, lib/*; live page screenshotted at 430 px)
- Logic port (ComposerKit.swift): socket types and colours, the 11-node catalog, canConnect, toOps/fromOps, layout, deriveGraph, emitSpec, the render-card body. Same spec text as the web (em-dash shot headings, `-> shot_id`, graph block, args formatted as emit.ts does). Pieces use the web's own JSON (the-practice-v1.piece.json shape).
- Skin (ComposerSkin.swift): pl-composer tokens on its ink ground, gold hairline, serif piece name, mono numbers, small-cap labels, glass cards and clear-glass pills.
- Segments under the title: Piece · Library · Board · More.
- Piece: strip (name, piece transition with seconds, pieces menu with new/duplicate/share JSON/import/delete, shots, duration, fps, resolution, Build spec, Board); shot cards (number, thumbnail of first visual source, title, duration, entering transition, short-source warning, named sources with remove, graph list); reorder, swipe (left send, right delete), touch-and-hold menu, TipView; Build spec warns about untitled shots, shows the spec, Copy and Share as .spec.md.
- Graph (ComposerGraphView.swift): the canvas the web only draws on a desktop, native: pan, pinch, drag nodes, drag from output dot to input, typed validation with the reason shown, wire select and remove, Add node menu, add a source, fit, tidy, back to default wiring, inspector with every param (select, number+slider, range) and per-input wiring menus (the accessible way to wire). Writes the same ops into the shot; opening is not editing.
- Library: full 1,654-row index, filter by name/ext/tag, catalog chips and type chips (counts follow the filter), 100 per page, thumbnails, attach on tap (sheet from a shot stays open), details sheet, copy id/path, offline from the HTTP cache.
- Board: lanes Sent, Rendering, Mixing, Filed, Ruled, Failed as filter chips and sections, progress bar, polls every 10 s, Lock Screen follow (Live Activity), Rule it opens native Curate; "Waiting for the house" outbox with retry and discard.
- More: native handbook (9 pages), piece list, defaults for new pieces, library index status, board status.
- System: widget (small, medium, rectangular, circular), Siri `RenderBoardIntent` and `OpenPieceIntent`, Spotlight for rooms and pieces (index "composer"), `OpenComposerRoomIntent`/`OpenComposerPieceIntent`, deep links `pldev://section/composer/<piece|library|board|more>` and `.../piece/<id>`, tips, haptics.

## Gap check
- Built: every feature of the web board incl. the graph canvas, spec sheet, render board, pieces, transitions, library.
- Not fitting: notification buttons (a card moving asks only to open /curate, not a real action).
- Not built: the board's `taste` lane (web page passes none either; "ruled" shows only if the house writes it); the web's Settings panel (the app has its own Settings).
- Unproven: everything on a device (gestures in the graph, widget, Siri, Spotlight), and the compile (see above).
- Send to render cannot reach the PC yet: see the route below. Cards wait on the phone and flush on every board load.

## Server route needed (for the lead; I did not touch pl-composer)
The worker has no disk and answers POST /api/board with 503 `no-disk`. Proposed, in `C:\dev\pl-composer\app\api\board\route.ts` POST: when the disk is missing, require `Authorization: Bearer <COMPOSER_KEY>` (secret), validate the body exactly as today, build the same job object (id, piece, shot, created, render, bed, card), and append it to an array in R2 `composer/inbox.json` (VAULT binding); return `{ok:true,id}`. In `scripts/refresh/composer_jobs.py` `once()`: first pull `pl-vault/composer/inbox.json` with wrangler r2 object get, write each job to `composer-jobs/<id>.json` if absent, then put an empty array back. Test: POST a body with no `render.look` (expect 400), then a real card (expect ok) and see the job file appear within one 5-minute loop. Without the bearer the route must stay refused: the worker is public.
Config: add to the `composer` origin `auth: {header: "Authorization", scheme: "Bearer", key: "composer"}` and a key `composer` in pldev-config.json (the phone sends it automatically through RequestPlan).

## Lines the lead must wire
1. `PLDevWidgets/PLDevWidgetsBundle.swift`: add `ComposerWidget()` (PLDevHomeWidgets has 9; this is the 10th, so move one group member elsewhere if another lane adds more).
2. `PLDev/PLDevApp.swift`, next to the Spotlight calls: `await ComposerSpotlight.index()`.
3. `Shared/AppShortcuts.swift` (keep the app at 10 or fewer):
```swift
AppShortcut(intent: RenderBoardIntent(), phrases: ["How are the renders going in \(.applicationName)"], shortTitle: "Render board", systemImageName: "film.stack")
AppShortcut(intent: OpenPieceIntent(), phrases: ["What am I composing in \(.applicationName)"], shortTitle: "Open piece", systemImageName: "film")
```
4. Deleted `ComposerAuthor.swift` (its types are replaced); nothing outside the Composer folder referenced them.
