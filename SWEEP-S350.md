# SWEEP S350 (lane worker, branch pldev-sweep-s350, from 857a7dd)

Scope: every section except Practice, PLWorld, Worlds; plus PLDev/Services. Method: pattern sweeps over ~59k lines (force unwraps, `try!`, `as!`, silent catches, empty actions, sub-44 pt controls, retired names, stale hosts, missing exits), then a read of each hit. Nothing was run on a device.

## Fixed
| Where | Defect | Commit |
|---|---|---|
| Paint/Native/NativeCanvasView.swift:78,128 | round toolbar buttons 38 pt | 1140914 |
| Paint/Native/NativeCanvasView.swift:298 | dock buttons 34x30 (hit area padded to 44 high, look unchanged) | 1140914 |
| Paint/Native/NativeLayersSheet.swift:66,89 | group chevron 22 pt wide, eye toggle 26 pt wide | 1140914 |
| Paint/Native/NativeTimelapse.swift:164 | play/pause 34 pt wide | 1140914 |
| Composer/ComposerGraphView.swift:172 | zoom buttons 40 pt | 2ccc25a |
| Composer/ComposerPieceViews.swift:421,424 | shot trim and remove buttons 36 pt | 2ccc25a |
| House/JarvisView.swift:334-341 | mic, speak, stop, send controls 32-36 pt wide | 1922b78 |
| Shop/SiteSystemView.swift:619 | V.A.U.L.T. node still names Ollama (uninstalled S346) | 1922b78 |
| House/JarvisView.swift:50 | brain order still lists "ollama" | 1922b78 |

## Found, not fixed
- `fourthwall_url` in Shop/SiteChosen.swift:28: it is the live `/api/chosen` field name, not a shown feature. Renaming it breaks decoding; the fix is server-side if ever wanted.
- Silent `catch {}` at Pick/PickSection.swift:138 (offline pick flush retries later, by design), Shop/ShopSitePages.swift:117 and Shop/SiteReader.swift:56 (fall through to the offline copy, then show an error line). Judged correct fallbacks.
- `layer as! AVPlayerLayer` style casts (5 places) sit inside `layerClass` overrides, so they cannot fail.
- Force-unwrapped `URL(string:)` calls all take string literals; safe.
- Chrome/size checks for Capture, CodeArt, Congregation, Curate, GlyphBot, Labs, Library, Pick, Town, Status, ThreeD were pattern-level only. No per-screen visual pass (no device, no simulator here).
- `import PLDevCore` in app files: none found.
- R1 features still shown: none found in app strings (only keyboard-shortcut comments).

## Improvements, ranked by how much he would feel them
1. Run a real device smoke pass on the 44 pt changes in Paint's toolbar (S, ~10 min). The dock may feel tighter; I did not see it.
2. A single `Hit44` view modifier in HouseKit, so no screen hand-sizes tap targets again (S, 1 file plus swaps).
3. A lint in `logic.yml` that fails on `.frame(width: <44` inside a `Button` label (S).
4. Surface the offline-pick-pending state on Pick home, so a held vote is visible (S).
5. Retire the hardcoded system copy in SiteSystemView (stack, specs, tiers) in favour of the live `/system` data, so it stops going stale (M).
6. One shared `OfflineFallback` helper for the three "try network, else cached copy, else message" blocks (S-M).
7. UI tests for the Jarvis input row and Paint toolbar identifiers (M).
8. Add a visible error line for the Pick flush failure after N retries (S).
9. Audit remaining `.frame(width:` icon-only controls in Labs and Town, which the Button-line grep could not catch when the frame sits on a following line (M).
10. Gemini or screenshot critique of each section against its web twin (L), since this sweep is code-pattern only.

## Build
Run 44298192729 (publish=false): BUILD SUCCEEDED (11:50 to 12:04 UTC). The build workflow compiles only: it printed no Test Case lines and no crash, so no tests ran and none of the 44 pt changes were seen on a device.
