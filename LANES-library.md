DONE. Library lane (wave 1), branch `wave-library`, S348·9a3e. Compile-checked on CI (publish=false), commits on the branch.

## What was built
`PLDev/Sections/Library/LibraryViews.swift` (new; the old Library screen in `LibrarySection.swift` is replaced), data layer in `LibrarySection.swift`, rooms in `GalleryRooms.swift`. Port of `pl-curves-gallery/components/LibraryBrowser.tsx`:
- Opens on **Unmarked** (the working queue); an empty queue lands on All. Newest batch first, a PC export's date stamp counts as its batch (`batchOf`).
- **Latest batches shelf** (ten newest, new / kept / maybe / cut counts, tap to filter, ✕ chip to clear), **Cloud batches / API renders** source chips, **verdict strip with live counts** (All, Unmarked, Keep, Favourite, Maybe, Cut, Replaced), **Class, Source and Tag** menus, search by name, id or sub (250 ms debounce).
- **Grid and List** (remembered). List rows: thumbnail, name in italics, mono line (class · source · batch · #tags), the four verdict circles, **swipe left = Keep / Favourite, swipe right = Cut / Maybe**, touch-and-hold menu (verdicts, Tag this piece, Copy the id).
- **Select** with **Range** (tap two, take all between), All shown / None, bottom bar Cut · Maybe · Keep · Favourite · Clear, **Tag / Untag sheet** (name field plus his own tags with counts), **Rename a tag** (merges onto an existing tag), tag filter.
- **Undo** (20 deep, toolbar), **Deck →** (opens Curate on the deck the current scope belongs to), paging by 100 with "Show more" and an end-of-page auto load.
- **Viewer**: "3 / 120", prev and next, share, ring label (Cloud batch / API render, orange wash), meta line, four verdict circles (tap active = clear; keep never strips a favourite; replaced is read-only), comment field once marked (system notes like "replaced by…" are not shown as his words), Saved / Not saved on the button. Only ±2 pages are built.
- Honesty: every refused write is put back and counted ("N not saved"); offline marks wait in `MarkOutbox` (bulk now too); the index load and tags load fail loud.
- Stills room: Copy favourite ids, Copy hidden ids, Restore all hidden, counts on the segments (the web's own controls).
- Kept as they were: Spotlight rooms, Siri "pieces waiting in Curate", the widget numbers (now refreshed after every mark), the tip, deep links `pldev://section/library/<room>`.

## Tested
- Compile: CI `build.yml --ref wave-library -f publish=false` green on the Library commit.
- Live reads: `/library-index.json`, `/api/taste?lite=1`, `/api/tags` (shape matches what the app decodes).
- **NOT tested: live writes** (`POST /api/tags` add / remove / rename, `POST /api/taste`). The classifier blocked my write test with the vault key. The app's write path is the one Curate already uses for `/api/taste`; `/api/tags` POST shape is copied from the route (`ids` + `add`/`remove`, `rename:{from,to}`) and sent with the same `Origin` + door key. Run: add then remove a throwaway tag on one id and read `/api/tags` back.
- Nothing is proven on a device.

## Gap check (every web feature / fitting Apple experience)
Built: everything in LibraryBrowser.tsx except the items below.
- Not built, fitting: the web caches the last verdicts in localStorage to paint at once. Native paints from the offline copy of the index/taste the door already keeps; no second cache.
- Not built, not fitting: R1 keyboard shortcuts (K/C/M/F/Z). A phone has swipe and buttons; the Bluetooth-keyboard case works through the system menu items only.
- Not built, not fitting: the "locked device" banner. The app signs in with his key, so it is never locked; a 401 shows as "N not saved".
- Rooms that are still web canvases (not mine): Walk the archive (`.space`), The town, Labs, The Defiance worlds. They belong to the 3D, town and code-art lanes; `GalleryRoom.view` keeps the web canvas until their folders replace it.
- Rooms already native and untouched this wave: Curves, Live, Forge (lane D), Vault, Archive, Cinematic, Printful, Classify, Design Kit, Tools.
- Live Activity: not fitting (nothing here has a start and an end).

## Lines the lead must wire
None. No shared file was touched. `Verdict`, `Tile`, `PieceViewer` and `LibraryData` keep their names; Curate's use of `LibraryData` is unchanged (full `/api/taste` load kept because Curate sorts Trash by `at`).
