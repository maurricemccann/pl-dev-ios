DONE. Gallery lane, branch `curves-gallery`, session S350·3b7f. Brief: `Plans/BRIEF — CURVES LIBRARY NATIVE LANES (S350).md`; rows from `Plans/AUDIT — CURVES LIBRARY VS PL DEV (S350).md`.

## What was built
- `PLDev/Sections/Library/VaultRoom.swift` (new). The Vault as `app/library/vault/page.tsx` + `components/VaultHub.tsx` + `components/VaultExplorer.tsx` draw it:
  - heading and the page's line, the Labs card, the **six count cards** (Generated, Cinematic, Archive from the index by class; Curves LIVE, Forge OPEN, Tools REG) with the page's note under them, each opening its room;
  - the **section cards** (category and count), each opening the **tree by media type, then provenance**: Living Code (Living Curves, Curve Archive, Jarvis-Crafted, Wave Two, Wave One, Defiance, the three Labs buckets), Stills (The Hand, Seal Marks, Renders, TouchDesigner, Wave One Stills, filed by hand), Video, 3D and Motion, Vector, Audio (with the affirmations), Type, The Complete Works, UI Components, Provenance and Tools, Rabbit R1, and any stray R2 prefix;
  - every shelf shows its label, count and provenance line (the provenance opens Tools at that shelf's Registry entry, as `/tools#reg-<shelf>` does); 80 rows then "Show all";
  - **tap a row copies its Vault ID** (the chip turns "copied", a success haptic); touch and hold: Copy the ID, Open the file (R2 files, in the native previewer `VaultFileView`), Share the file link; lead rows ("Open the grid", "Open the gallery", "Open the reel", the Archive, the Registry) open their room;
  - search by name, ID or meta across the whole tree, and inside one category; the page's own empty line ("Nothing holds that name.");
  - the footer cards Archive (the real count), Tools, Source; the app's own "What the gallery holds" by-class list kept at the bottom.
  - Data: `vault-manifest.json` (required: a failure shows the Loaded error screen), `generated/manifest.json`, `cinematic/manifest.json`, `api/vault-list`, the pl-manifestation-practice `/api/affirmations`, the pieces from the native runtime (`PieceRuntime`, its own `set` and `live` per piece, the web's own shelf rules). Each source that fails is named on the screen; the rest still draws.
  - IDs follow `lib/vault-id.ts` line for line (`VaultID`), with the web's own fixtures as a self-check that runs in a debug build.
  - Cut stills and clips are hidden by **file name**. The web's filter matches on a `name` field the manifests do not have, so on the website it hides nothing; his S282 ruling (a cut piece is hidden everywhere) is what the app follows.
- `PLDev/Sections/Library/ToolsReference.swift` (new). The reference text of `app/tools/page.tsx` + `ToolsClient.tsx` (Provenance Registry, languages in use and available with their examples, tools in use and available, the folder map) and the **API reference block** of `app/source/page.tsx` (Endpoint, Usage, For models, Machine-readable).
- `GalleryRooms.swift`: `ToolsRoom` is now the reference page, opening at a Registry entry when a Vault shelf asks; the piece code list moved one tap in (`ToolsPiecesView`). The old `VaultRoom` removed. The two stale web canvas comments rewritten (lines 5 to 8, and the `// MARK: - The web canvas for code art` header now `// MARK: - Source: one piece's code`). The rooms sheet reads the archive count from `archive/manifest.json` (fails loud: "Count not read." and the reason); the static Spotlight line is now "The complete works", no number.
- Rename, Library to Gallery, audit items 1 to 14 and 16: section title (`id` stays `library`), the nav title, the heading title, "Opening the gallery…", the rooms sheet title, "What the gallery holds", Spotlight and Siri names ("Gallery Room", "Open a Gallery Room"), the watch label, the backdrop's VoiceOver line, the Curves room's empty line, the three Lab Stories links, the NFT Candidates and Trained Hero eyebrows, and the UI test (`Notes4FlowsTests.swift:165-166` now finds "Gallery"). Not touched, as ruled: item 15 (Pick chip), Composer, Town ids, the affirmations text.

## Tested
- CI compile: run 44680744597 (`build.yml --ref curves-gallery -f publish=false`), job `ios` success, log read: `** BUILD SUCCEEDED **`, 0 compile errors. Warnings in my files only: four `Text +` deprecations in `ToolsReference.swift` (242 to 244, 274) and two strict-memory-safety notes in `VaultRoom.swift` (213, 220); none blocks. (The two `error:` strings in the log are another file's source quoted under a warning.)
- Live reads (curl, 11-19): `vault-manifest.json` keys and shapes, `generated/manifest.json` and `cinematic/manifest.json` items (`id, file, collection, w, h, duration`, no `name`), `/api/affirmations` (200 lines), `api/vault-list` refuses without the key (401, the app sends it), `archive/manifest.json` (count 1347, 1347 pieces).

## Not tested
- Nothing on a device. No screen of the new Vault or Tools has been seen.
- CI runs no test cases: `build.yml` builds the PLDev target only, so the UI test line was neither compiled nor run, and the debug-only ID self-check was not run (Release build).
- The piece shelves are rows, not the web's live-canvas grids (the web caps those at 8 tiles and sends the rest to /curves; the app's Curves room is one tap away from the lead row).

## Lines needed in files I do not own
1. **The second deep link, `pldev://section/gallery`**: `PLDevCore/Sources/PLDevCore/DeepLink.swift:21`, change
   `self = .section(id: id, path: Array(segs.dropFirst()), query: q)` to
   `self = .section(id: id == "gallery" ? "library" : id, path: Array(segs.dropFirst()), query: q)`
   (one place covers the URL handler, notifications and the share paths; `pldev://section/library` keeps working). A PLDevCore test beside the existing DeepLink tests would hold it.

## Found on the way
- **The website's archive number is the stale one.** The live manifest holds 1,347 works (`count` 1347, 1347 pieces). The web writes "1,768" in the Vault footer, the Tools folder map and the Registry. The app's old "1,347 works" was right; it now reads the number live. The ported Tools text drops the 1,768 rather than repeat it.
- The website's "a cut piece is hidden" filter on stills and video matches nothing (see above).

## Assets I could not find
None. Every row reads a live file the website reads.

## Text changed from the web
Em dashes turned to commas; "the Manifestation Preview" written as "the Preview board", "manifest build" as "vault build", "the full tools manifest" as "the full tools list" (labels I wrote; file names keep their names); the For models step "Never: excited, blessed, amazing, manifest." written as "Never the house's banned words (CLAUDE.md, Voice Rules)." Left out: the Machine & Device Map block (machine paths and the dead D: drive; not in the audit row).
