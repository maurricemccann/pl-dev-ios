DONE (sweep lane, branch wave-sweep, S348·9a3e, 11-13). Compile check green: build.yml run 43525688373 (publish=false) on the first sweep commit; the last commit only deletes a stale `import WebKit`.

## What changed
- **Human checks: no web view left.** `Shop/SiteHumanCheck.swift` no longer holds a WKWebView. `HumanGate(siteKey:)` is now a native note ("the check opens in Apple's secure sheet on the site's own page"). When the site reports a check key, the form's button reads "Continue on the site", keeps what the visitor typed on the pasteboard, and opens the matching page in `SafariSheet`: signal (`signal?src=app`, email copied), contact (`contact`, message copied, photo attached there), request ballot (`catalogue/<cr>`, email copied), the congregation wall (`congregation#state-your-reality`, desire copied). A signed-in member's request needs no check and still posts natively. If the site runs without a key, the native POST runs as before.
- **Congregation:** `TurnstileView` deleted; `import WebKit` removed.
- **Library:** the Town row opens the native `TownView(model:state: TownSection.state)`; vault files open in a new native `VaultFileView` (downloaded through the gallery door, shown in Quick Look, Share beside it).

## Gap check: what the grep still finds (not mine to swap; the lead wires)
`grep -rn "WKWebView\|GalleryCanvas(\|GalleryWeb(\|PaintWeb" PLDev` still returns:
- `Library/GalleryRooms.swift` line 51 `.space` and line 248 "Walk it in 3D" -> the worlds lane's archive/space view.
- Line 58 `.labs` and 166/175 (`WebListRoom`, Living Curves) -> the labs lane's rows.
- Line 59 `.worlds` -> the worlds lane's room list.
- `Paint/PaintSection.swift` (handbook `GalleryCanvas`, `PaintWeb`) -> the paint lane.
- Struct definitions `GalleryCanvas`, `GalleryWeb`, `WebListRoom`, `PaintWeb`: the lead deletes after the swaps above.
I did not touch those files' rows because the replacement views live on other lanes' branches.

## Not proven (no device)
- The secure-sheet hand-off works but the token cannot come back to the app, so those four forms finish on the site. Optional upgrade for the lead: a site page that runs Turnstile and redirects to `pldev://check?token=...`, opened with `ASWebAuthenticationSession`, would let the native forms post themselves. That needs a new pl-headless route; not built.
- Quick Look preview of a vault file is unrun on a device.

## Shared-file lines needed
None.
