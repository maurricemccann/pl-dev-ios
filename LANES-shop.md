DONE. Wave 2, shop (`Sections/Shop/`, owns SiteSkin): built to the live site's own pages, compile-checked on branch `wave-shop` (unsigned build, publish=false), server reads tested against the live site (25 of 25).

# What changed from the first storefront lane (read this first)

The first lane's Shop read Google's product feed. Checking the live pages found it **short by 37 pieces**: the site's `/shop` lists 89, the feed carries 52 (every patch, sticker, towel, journal, bandana, hat, the curve-pattern home goods and more were missing). The list is now the site's own `/shop` page (the grid it shows, in its order) joined to the feed, and each piece's own page is read for what neither carries. Everything below is read from the live pages, so the app cannot disagree with the site, and kept for offline.

## Screens, each against the live page (screenshots taken at 430 px: /shop, /archive, the Closet section of /shop; the rest read from `pl-headless` code and live HTML)
- **Shop** (`/shop`): the page's own opening ("The shop, 89 pieces", Wearable *doctrine.*, its lede), **the three collections** (Classic, Glyphs, Seeds, with live counts and the site's words, "Closing 2029" pill on Seeds), a rail to every other collection (the site's `COLLECTIONS` name tests ported: Heart Mark, the four glyphs, Poverty to Luxury, Psyched, tees, hoodies, sweats, crops, crewnecks, Men's, Women's, Art supplies, Home goods), then "Everything" with the site's **filter drawer** (garment, line, price, order; counts per facet; "Show N"; the in-stock switch is the app's own), search, the cards with the site's one-line argument. Touch and hold a piece: Share, Put in the Closet.
- **A collection** (`/collections/<slug>`): "Shop / Name", "The collection, N pieces", the name in italic gold, the pieces. Deep link `pldev://section/shop/collection/<slug>`.
- **A piece** (`/shop/<slug>`), the page in full: the axiom as the eyebrow, name, gold rule, price per variant, the **Provenance** panel, **Size & fit** (the manufacturer's table, on the 13 pieces that carry one), **design** pick first on family pages (12 of them), colour, size (sold-out struck through), Buy (opens that exact variant on the site: Square's checkout is the site's), Closet, Share, the returns line, About this piece, Production / Care / Delivery & returns, **The argument**, the digital twin note where the piece has one, The congregation (opens the Congregation's wall in the app), **The Truth** (the axiom as the blockquote, "The Three Truths" read natively), **More from the drop** (the page's own four). The 37 pieces the feed lacks get their colours, sizes, prices and flats from their own page.
- **The Closet**: rebuilt in the site's look (the page's "Hang a look. *Wear it together.*"): the stage with the look's flats, the slot rail (Top, Layer, Bottom, Accessory), the rack, the gold progress bar, a size per piece with its price, "Hung by the house" (the three house looks), the count and total, "Wear this together" (opens a sheet that sends each piece to the site at its chosen size), "Each piece keeps its own price." Flats only. The house-model exception is not used.
- **The archive** (`/catalogue`): rebuilt on the site's own viewer (`public/archive-embed/app.js`): the R2 manifest of the complete works (1,328 shown, the 19 third-party marks never), **his keeps leading** (1,232 keeps, with their dates), "From the archive" (PL-0627, as the page features it), search by number, motif and colour, the lenses **All works / HeartMark / The Lab** (353 Lab entries, joined each Friday), the gold star (kept on the phone), a work in full with its colourways, the notes, step to the previous and next work (buttons or a swipe across), Share, Pin (signed in), and **Request this piece as a native ballot**: the six forms, "Seeds arrive as stickers first", a member's weeks of voice, an email for anyone else, and **the site's human check run in the app**. A piece already requested shows green.
- **Contact** (`/contact`): the form, native: name, email, order number, **photo from the Photos picker** (up to the site's 5 MB, jpg png webp heic gif), message, the human check, Send; "Received" in gold; Email and Instagram.
- **The signal** (`/signal`): the page's own words and a native form with the human check (needs the one route below to be live; until then the form says so plainly and opens the site's page).
- **Orders**: the account's list opens **one order in full** (`/orders/<id>`: the four-step tracker, line items, shipping, total, where it ships, track with the carrier); the guest "Track an order" shows the same tracker.
- **The human check** (`SiteHumanCheck.swift`): the site's Cloudflare Turnstile widget in a small web view that carries the site's address as its origin, invisible unless Cloudflare asks for a challenge, with a retry. This is what turned Contact, the request ballot and the signal from "opens on the site" into native forms. A signed-in member needs none (the site takes the session as the proof, as on the web).

## Rules honoured
- **Product imagery**: every picture drawn is on the site's `product-transparent` path and ends `.png` (`ShopCatalogue.isFlat`); the card pictures, the page's variants and the Closet all filter through it. 12 pieces have no flat on their card and show the hanger until their own page is read; one trucker cap has none at all and keeps the hanger. The archive shows his art, not products.
- **Third-party marks**: the archive's block list is the site's own (19 works); the app never shows them.
- **Public repo**: `scripts/scan.sh` is clean for this lane's files (the contact address is built from the site's host, not typed). The scan's remaining failures are older lanes' files (a test script with an example address, a Tailscale address and the word the town in history, the font's file name) and are the lead's to squash.

# Gap check (every web feature and every fitting Apple experience)

| Item | State |
|---|---|
| The 89 pieces, in the site's order | built (was 52) |
| Three collections and every other collection page | built |
| Filter drawer, search, orders | built |
| Piece page: gallery, design, colour, size, price, provenance, size and fit, about, production, care, delivery, argument, the Truth, related | built |
| Buying (cart, checkout) | **opens the exact variant on the site.** Checkout is Square's hosted page and the cart is a server action behind Cloudflare's human check; the web view cannot be handed that action. Honest limit, not a missing screen |
| The Closet | built in the site's look; "Wear this together" sends each piece to the site |
| The Ask (the visitor poll on /shop) | not fitting: it is a visitor survey whose results belong to the founder's tally, not a thing he answers on his own phone |
| Archive: manifest, keeps first, search, lenses, The Lab, star, colourways, step, share | built |
| Archive: request ballot | built, native (human check in the app) |
| Archive: Pin | built (signed in) |
| Archive: react and answer | live in the Congregation's stream (they are stream features, not the archive viewer's) |
| Archive page's Living Curves, Mirror doors and The Chosen | not built: the first two are doors to the Library and the Curves; The Chosen comes from a server action. Noted for the lead |
| Contact with photo | built |
| The signal | built; **needs `app/api/signal/route.ts` (below)** |
| Track an order, Your orders, one order in full | built |
| Gift cards | opens the site (Square's gift-card checkout) |
| Order confirmed banner, the shop's debug mode | not fitting: site-side tools |
| Widget, Siri, Spotlight, Tips, deep links | built (unchanged, now counting 89; the new-piece notice was reset so the 37 added pieces are not announced as new) |
| Live Activity | not fitting (an order in transit has no push to follow) |
| Notification buttons | not fitting (the notice opens the piece) |

# Server route needed (one, ready to paste, untested because it is not deployed)

The site's signup is a server action (`subscribe` in `app/actions.ts`), which a native screen cannot call. Add to `pl-headless`:

`app/api/signal/route.ts`
```ts
import { subscribe } from '@/app/actions';

export const dynamic = 'force-dynamic';

// The native app's door to the same signup the footer form uses: same human check, same table, same welcome.
export async function POST(req: Request): Promise<Response> {
  let b: { email?: string; source?: string; token?: string };
  try { b = await req.json(); } catch { return Response.json({ ok: false, message: 'Malformed request.' }, { status: 400 }); }
  const source = String(b.source || 'app').slice(0, 32).replace(/[^a-z0-9_-]/gi, '') || 'app';
  const r = await subscribe(String(b.email || ''), source, String(b.token || ''));
  return Response.json(r, { status: r.ok ? 200 : 400 });
}
```
Test (do not run it with a real address you do not mean to add): `curl -s -X POST https://psychedluxuries.com/api/signal -H 'content-type: application/json' -d '{"email":"not-an-email"}'` must answer `{"ok":false,"message":"That email does not look right."}` with status 400. Until it is live the app's form shows "Not sent. The app's door to the signal is not open on the site yet" and a link to the site's page.

# Shared-file lines the lead must apply

**None required.** Widgets, App Shortcuts, Spotlight, `PLDevApp.swift`, `Info.plist` and the config are untouched (the human check loads Cloudflare's script over https; the photo picker needs no permission string). `ShopRoom` gained `contact`, so Spotlight indexes it and `pldev://section/shop/contact` lands on it.

Merge notes:
- Squash this branch at merge: its first commit (`2e8b60f`) carries a literal support address that a later commit removed, and the public-repo scan reads history. (A force-push to rewrite it was blocked by the permission classifier, so it was left for the lead.)
- `FlowLayout` already exists in Curate; this lane's chip wrap is `ShopFlowLayout`.
- The archive no longer uses the Congregation's `StreamModel`; nothing in this lane depends on a Congregation file.

# Testing

Server side, against the live site (`LANES-shop-live-test.py`, read-only, GETs only, about 40 seconds; 25 of 25 pass):
- /shop: 89 cards parse, each with a name and price, slugs unique, only flats kept; the feed is a subset of the grid (52 of 89), so 37 pieces are thin until their page is read.
- All 89 piece pages answer 200 and parse: axiom, argument, variants with ids and prices (1,982 variants in all), Production, Care and Delivery (Delivery streams in late on some pages; the reader takes it from the page's flight data), 13 size guides, 12 family pages with designs. A card's price equals its page's lowest variant on every piece.
- Archive: the manifest decodes (1,347 records; 19 blocked), PL-0627 is present, the keeps answer (1,232), the Lab decodes (353).
- Request config answers with the check's key and the six forms. Order list and order detail refuse an anonymous read with 401.
- **Not tested, and why:** the writes (contact, request, signal, order detail with a session, pin). Contact and the signal would send a real message and add a real subscriber; the request would add a real vote. They are written to the routes' code as read. First things for him to try on the phone: open a piece and an archive work, open Contact and Send with the check, cast one request.
- **Compile**: `gh workflow run build.yml --ref wave-shop -f publish=false`: first pass green (run 43514435094), then the final run below. One real defect was caught by the first attempt and fixed: a second `FlowLayout`.
- Nothing was run on a device or simulator (no Mac here): layout, the web-view human check, the Photos picker, the swipe-to-step gesture and the widget are unproven until his pass.

# Risks he should know
- The shop page's markup is the source of the list: if the site changes its card markup, the app falls back to the feed (52 pieces) and says nothing is wrong; the live test above is the check to run after a site redesign.
- The human check in a web view is Cloudflare's own and bound to the site's address; if Cloudflare ever refuses an embedded page the form says so and offers a retry, and the site's pages still work.
- A new piece's page can carry sizes the app has not seen; they appear on the next read.
