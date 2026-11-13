DONE. Lane A, the psychedluxuries.com app: built in full, compiled clean on branch lane-storefront (run 43426310871 and the closing run), tested against the live site, premium pass and gap check below. No stops were needed.

# What was built

Two sections replace the two placeholders (`PLDev/Sections/Paint/PlaceholderSections.swift` is deleted).

## Shop (`PLDev/Sections/Shop/`, section id `shop`)
Segmented under the title, as House: **Shop · Closet · Archive · More**.
- **Shop grid**: the site's whole catalogue (53 pieces, 1,982 variants today), filter chips by kind with counts, search, order (the shop's order, price both ways, name), in-stock only, "12 of 53 pieces", pull to refresh, skeleton while loading, a designed failure state. Touch and hold a piece: Share, Put in the Closet (a `TipView` says so once).
- **Piece page**: swipe through the piece's flat pictures, colour chips and size chips (sold-out ones struck through), the colour's own pictures lead, price per variant, description, **Buy on psychedluxuries.com** (opens that exact variant on the site in Safari's sheet, because checkout is a Square-hosted page behind a human check), Closet, Share, "Size guide and care on the site".
- **Closet**: one piece per slot (Layer, Top, Bottom, Accessory), the three house looks, a size each, the total, Buy per piece, Clear (confirmation). Flats side by side, no model, no body. Remembered on the phone.
- **Archive**: the 1,193 archive pieces in a 3-up grid, 24 a page, endless; a piece opens in full with its reference, pillar, answers, react/answer (signed in), Pin (signed in), Share, and **Request this piece** (the vote is Turnstile-gated, so it opens on the site).
- **More**: The signal (the signup form opens on the site), Track an order (native: email + order number to the site's lookup, status, carrier link), Your orders (the signed-in account's own, with a Track swipe), The site (creator awake/asleep, catalogue freshness), Pages (brand, Three Truths, Three bodies, the Forge, contact, gift cards, returns, terms, privacy).
- Rooms are in a `ShopRoom` enum, so a link, Siri, Spotlight or a notice lands on one by name.

## Congregation (`PLDev/Sections/Congregation/`, section id `congregation`)
Segmented: **Stream · Room · Members · Me**.
- **Stream**: the public stream the site weaves (declarations, archive pieces, generated curves, drops, the Three Truths), endless, react and answer when signed in. A drop's picture is drawn only if it is one of the site's transparent flats (70 of 183 drops carry a raw Square picture, so this filter matters).
- **Room**: the members' room. Posting (confirmation first: "public to the whole congregation"), reposting (confirmation), reacting, answering (held until he approves, as the site does), report. **His moderation**: swipe left to approve a held post or answer, swipe right to remove (confirmation), a `TipView` says so while anything waits. Optimistic, restored with a plain sentence if the site refuses.
- **Members**: the directory, search by handle, a member's page (their glyph in their colour, followers and following, their posts, Follow).
- **Me**: email and password sign-in (the site's own; the session token lives in the Keychain only), sign-up and Google sign-in open on the site. Signed in: header (name, handle, tier, points), Activity (the site's bell, with its five kinds switchable), Messages to the Founder (members; for him, "member messages are in House"), Your orders, Pins, Edit profile (name, handle, colour), glyph picker, "I am here as", Sign out (confirmation).
- Rooms in a `CongregationRoom` enum; `pldev://section/congregation/member/<handle>` lands on a member.

## System add-ons (DESIGN section 6)
1. **Widget "The site"** (`PLDevWidgets/StorefrontWidgets.swift`, data from `Shared/StorefrontGlance.swift`): small, medium, Lock Screen rectangular and circular; `widgetAccentable`; pieces, in stock, newest piece, members, and "N waiting for you" when he is signed in as the founder. App Group copy only, no key.
2. **Live Activity**: not fitting. A Live Activity needs a defined start and end that the app can follow; the only candidate here is an order in transit, and the site gives no push for it, so it would only move when the app is open (the same reason House's would be stale). Order tracking is the native lookup instead.
3. **Siri and Shortcuts**: `ShopStatusIntent` ("What's in the Shop": says pieces, in stock, what is new) and `CongregationStatusIntent` (says members, what waits for his word, new activity). Neither publishes, so neither needs `requestConfirmation`. Plus `OpenShopRoomIntent` and `OpenCongregationRoomIntent` (OpenIntents for Spotlight).
4. **Notification buttons**: not fitting, with a reason. A new piece opens the piece. A held post is a judgement on each item, so a bulk "Approve all" on a lock screen would be wrong; the notice opens the room, where the swipes are. The three types are declared (`shop.new`, `congregation.held`, `congregation.activity`) so each gets its own switch in Settings.
5. **Spotlight**: every room of both sections is an `IndexedEntity` in its own named index ("shop", "congregation"), opened by an `OpenIntent`. Indexed once per launch from the first refresh.
6. **Tips**: `PieceHoldTip` and `RoomSwipeTip` (the two gestures that cannot be seen).
7. **Deep links**: `pldev://section/shop/<room>`, `/shop/piece/<slug>`, `pldev://section/congregation/<tab or room>`, `/congregation/member/<handle>`.

## Rules honoured
- **Product imagery** (hard-limits): the catalogue reader keeps only pictures on the site's `product-transparent` path ending in `.png` (`ShopCatalogue.isFlat`) and drops every other picture before anything can draw it; the Closet draws flats only; the stream's drops and the orders list apply the same test. A piece with no flat yet (one trucker cap today) shows a hanger, never a borrowed photo. The Closet's house-model exception is not used (no renders are published).
- **Public repo**: `scripts/scan.sh` is clean. The site address arrives from the config like every other origin.
- **House patterns**: `Loaded`, `ResultLine`, `Ago`, `EmptyNote`, `SkeletonRow`, `SettingsLabel`, `PLHaptic`, `PLTone`, `PLSpace`, the segmented-under-title shape, the room enum, the glance-writer pattern. No new look.

# Shared-file lines the lead must apply at merge (exact)

1. **Config** (`C:\Tools\pl-dev-builds\pldev-config.json`): add one origin, no auth, no key:
   `"site": { "base": "https://psychedluxuries.com/" }`
   (`shop` and `congregation` are already in `sections`.) Until it is there both tiles show "Needs an address".
2. **`PLDevWidgets/PLDevWidgetsBundle.swift`**: add `StorefrontWidget()` to the bundle body, after `HouseWidget()`.
3. **`Shared/AppShortcuts.swift`**: add two App Shortcuts (that brings the app to 8 of 10 before the practice lane adds its own; the practice lane should take the last two):
   ```swift
   AppShortcut(
       intent: ShopStatusIntent(),
       phrases: ["What's in the shop in \(.applicationName)", "\(.applicationName) shop status"],
       shortTitle: "Shop status",
       systemImageName: "bag"
   )
   AppShortcut(
       intent: CongregationStatusIntent(),
       phrases: ["What's in the congregation in \(.applicationName)", "\(.applicationName) congregation status"],
       shortTitle: "Congregation status",
       systemImageName: "person.3"
   )
   ```
4. **Nothing else.** No Info.plist change (every address is https, no new permission), no new key name, no new Keychain group, `PLDevApp.swift` needs nothing (the rooms index themselves on the first refresh; if you prefer the House pattern, add `Task { await ShopSpotlight.index(); await CongregationSpotlight.index() }` beside the House line).

# Server routes needed

**None are required**; everything uses routes the site already serves. One is a worthwhile improvement, ready to paste, **untested because it is not deployed**:

The shop reads the site's Google product feed (`/feed/products.xml`: 91 KB compressed, cached an hour, read in about half a second on the phone's first launch and cached on disk after). It carries price, stock and pictures per variant, but not the piece's own line (`argument`, `axiom`) or its family designs. A lean JSON route would add those and drop the XML reader:

`pl-headless/app/api/shop/catalogue/route.ts`
```ts
import { getProducts } from '@/lib/square';

export const dynamic = 'force-dynamic';
export const fetchCache = 'default-cache';   // same as /shop: the catalogue call stays cached for five minutes

const FLAT = (u?: string) => !!u && u.includes('/product-transparent/') && /\.png(\?|$)/i.test(u);

export async function GET(): Promise<Response> {
  try {
    const products = await getProducts();
    return Response.json({
      ok: true,
      pieces: products.map(p => ({
        slug: p.slug, name: p.name, argument: p.argument, axiom: p.axiom, description: p.description, kind: p.kind,
        images: p.images.filter(FLAT),
        variants: p.variants.map(v => ({ id: v.id, color: v.color ?? null, size: v.size ?? null, cents: v.price, inStock: v.inStock, image: FLAT(v.image) ? v.image : null, design: v.design ?? null })),
        designs: p.designs ?? [],
      })),
    }, { headers: { 'Cache-Control': 'public, max-age=300' } });
  } catch { return Response.json({ ok: false, pieces: [] }, { status: 503 }); }
}
```
Test: `curl -s https://psychedluxuries.com/api/shop/catalogue | python -c "import sys,json;d=json.load(sys.stdin);print(len(d['pieces']))"` should print the piece count, and no picture in the output may lack `/product-transparent/`. Then `ShopCatalogue.build` gets a second reader for the JSON and the piece page can show `argument`. Not needed for the app to work today.

# Testing

Server side, against the live site (`LANES-storefront-live-test.py` in this worktree: `python LANES-storefront-live-test.py`, about two minutes, read-only; all 49 checks passed):
- The feed: 53 pieces, 1,982 variants, prices parse, every kept picture is on the transparent path (a Python mirror of `ShopCatalogue.build` asserted it); the one piece with no flat is handled.
- The stream: every page of every kind decodes (archive 1,193 items over 50 pages, drop 183, doctrine 265, generated 1,192, declaration 1, mixed). The model's required fields (`kind`, `id`) were present on every item; the rest are optional.
- The room feed (anonymous): 50 posts decode with their answers. Directory, follow counts, a member's posts, search, creator status, auth/me (anonymous) all decode.
- Every write route refused an unauthenticated call with the site's own sentence and the status the app expects (401, or 403 for the founder-only moderate route): feed post, react, answer, stream react and answer, follow, messages, report, moderate, profile, intent, notifications. Every members' read answered 401. Sign-in with a wrong password answered 401 with a sentence and no cookie. Order lookup answered 400 and 404 with sentences.
- All 14 pages the app opens in the sheet answer 200 after redirects.
- **Not tested, and why:** the signed-in paths (sign-in success, posting, reacting, moderating, pins, glyph, profile, orders, messages). They need his account, and posting or reacting on the live site is public. They are written to the routes' code as read (`lib/auth.ts` for the `pl_session` cookie, each route's body and reply), and the app restores state and says the site's own sentence on any refusal. Those are the first things for him to try on the phone: sign in, react to one item, approve one held answer.
- **Compile**: `gh workflow run build.yml --ref lane-storefront -f publish=false`: success (2 m 11 s first clean run, then 3 m 17 s with pins, glyph and bell kinds). One real defect was caught by it and fixed: two `RoomViews.swift` in one target collide (mine is `MembersRoomViews.swift`).
- Nothing was run on a device or simulator (there is no Mac here): layout, gestures, the Safari sheet and the widget are unproven until his pass.

# Gap check (every web feature and every fitting Apple experience)

Built = yes. Reasons are given for every "no".

| Item | State |
|---|---|
| Shop grid, filter, search, order | built |
| Piece page: gallery, colours, sizes, price, description | built |
| Buying (cart and checkout) | **not built in-app**: checkout is a Square-hosted payment page, and the cart and the purchase action are server actions behind Cloudflare Turnstile, which a native screen cannot pass. "Buy" opens the exact variant on the site. |
| Size guide and care text | opens on the site (the guides are per-product tables the feed does not carry; the optional route above is where they would come from) |
| The Closet | built, flats only; the site's house-model render is not used (no renders published, and flats comply) |
| Collections (`/collections/<slug>`) and tags (`/tag/<tag>`) | not built: Square collections are not in the feed; the kind chips cover browsing. Add `collections` to the optional route if wanted. |
| The Ask (one visitor poll on /shop) | not built: a Turnstile-gated visitor poll, not for him |
| Archive browse, piece page, react, answer, pin, share | built |
| Request and vote | opens on the site (Turnstile) |
| His keeps filter on the archive | not built: the stream cannot filter by reference, and the full manifest is 1.2 MB |
| Pin thumbnails | not built: the pin list shows the reference; thumbnails need the 1.2 MB manifest |
| Transmission signup | opens on the site (Turnstile) |
| Track an order (no account) | built, native |
| Order detail page (`/orders/<id>`) | the list shows status, total, carrier and a Track swipe; the full page is not built |
| Contact form, gift cards, returns, terms, privacy | open on the site (contact is Turnstile-gated) |
| Congregation stream | built |
| Members' room: post, repost, react, answer, report | built |
| His moderation of held posts and answers | built (swipes, confirmation on remove) |
| Members, member page, follow | built |
| Own page: profile, glyph, intent, activity, messages, orders, pins | built |
| Sign-up, Google sign-in, forgot password | open on the site (Turnstile / OAuth) |
| Boards, Games, Ask-the-points question on the member hub | not built: boards need a larger editor; games launch separate web experiences; they are not part of "feed, requests and votes, the member's own page" |
| The site's Settings (bell kinds) | built (five switches in Settings, also drive the activity list and its notice) |
| Shop debug (founder) and the lab, curve, world, room, study, journal, glyph pages | out of this lane (experiments and the practice) |
| Live Activity | not fitting (above) |
| Notification buttons | not fitting (above) |
| Widget, Siri, Spotlight, Tips, deep links | built |
| Control Centre control | not fitting: the Home control already opens the app; a Shop-specific one has no action a tap should take without opening the app |
| Share sheet and Safari extension | the lead's shell; nothing Shop-specific needed |
| Handoff, Quick Look, drag and drop | not fitting: no documents; pictures open in the piece page |

# Risks he should know

- The catalogue is the Google feed: if the site ever stops serving it or changes a field name, the Shop shows its last good list and then "Could not load the shop". The optional route removes that dependency.
- The signed-in features cannot be proven from here (above). Sign-in uses the site's own rate limit (10 tries per 10 minutes).
- The feed reads about half a second from the site; Cloudflare cached it for an hour, so a new piece can take up to an hour to appear.
