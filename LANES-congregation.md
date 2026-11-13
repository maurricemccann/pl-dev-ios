DONE. Wave 2, congregation: the app rebuilt screen for screen in psychedluxuries.com's own look, with every feature of the web's congregation and member pages working against the live site. Branch `wave-congregation`, compile-checked (run ids at the bottom). Nothing outside `PLDev/Sections/Congregation/` was touched.

# What was built (folder `PLDev/Sections/Congregation/`)

Rule 0 first: the live `/congregation` and `/member/<handle>` pages were screenshotted at 430 px and their code read (`components/congregation/*`, `components/member/*`, `MemberDmPanel`, `app/activity`, `app/settings`, `lib/glyphs`, `lib/brand-color`). The old screens were List rows on the site's ground; they are now the site's own cards, in the order the page shows them. The skin is the shop lane's `SiteSkin.swift` (Bone, SiteFont, SiteCard, SitePill, SiteGhost, SiteTabs, SitePageHead), untouched; what the Congregation adds lives in `CongregationSkin.swift`.

## Stream (the first tab)
- The page's head, then **@psychedluxuries** (round obsidian avatar with his mark, "Since April 2019 · Decide → Persist → Obtain", archive count from the live stream, "7 yr unbroken", "90% curve-governed", the line about the evidence), **State your reality →** and **Receive the signal** (the Shop's signal room).
- **"Why are you here?"** (the one-tap intent card, shown once to a signed-in member who has not said; five answers).
- **The stream | The grid** toggle. The stream is the site's five cards: archive (pillar, reference, title, year, "View in the archive →"), generated seal, **drop (the transparent flat only, hanger if none)**, declaration (italic quote and author), and the **doctrine card on obsidian with the numeral in his hand**. The grid is the masonry of every picture; tapping a tile jumps to its card.
- Under each card: react (the member's own glyph), **Answer** (opens the answers with a field; his ✕ remove with a confirmation), **Share** (the site's `/congregation#<id>` link), **✧ save** to the Saved board. Pictures open in a **lightbox** (pinch to zoom). Endless scroll; "Watch this." at the end in his hand.

## Room (the members' room)
- "The room where the *congregation* lives." Compose card (the site's wording for a member and for him: "State your reality" / "Post to the congregation"; **+ add a visual** opens the archive picker with link paste; the post is confirmed first). Signed out: "You are watching the room." with **Enter the congregation**.
- **The House | Following** (Following is the personal feed from `/api/congregation/following`, paged; empty it shows "who to follow" from the directory).
- Posts are the site's cards: round mark (glyph, his mark for the Founder, a dot for anonymous), handle that opens the member, date, "↻ reposted", the post in the display face with **#tags, @handles and links alive**, picture (opens full), **video plays**, a living piece is a link out never a frame. Pills: React, Repost (confirmed), Save, Report. **Answers thread one level** (reply button, "replying to …"), anonymous toggle, held answers dimmed with "held". **His moderation is inline as on the site** (Approve post / Remove on a held post, Approve / Remove on a held answer, each removal confirmed), with a TipView.
- Real time: the room refreshes every 90 s while open (the site's own fallback poll under its socket).

## Members and a member's page
- Directory: grid of glyph + @handle + tier, search through `/api/search`.
- **A member's page is the site's hub**: Profile (112 pt obsidian avatar with the real glyph in their colour, @handle, first name, tier in their colour, Founding Member, "In the congregation since …", followers / following and Follow, **the climb** with points, a bar in their colour and "N to Kin.", **chosen works** opening their catalogue pages) and Posts. For the page's owner the same tabs the site gives: **Boards · Settings · Social · Games · Ask**.
- **Boards**: the owner's collections, create a board, open one into a masonry, tap a picture to open it.
- **Settings**: the five glyphs with the climb's locks and their reason, the eight brand colours plus a custom picker, @handle and first name, **chosen works** (the archive picker with the tier's slot count), "I am here as", the five bell switches, Persona Academy.
- **Social**: State your reality (the wall form), the room, the stream. **Games**: the roster of 33 games with live play counts and **Enter PL Games**, which mints the site's play token (the launch route's redirect is read, not followed) and opens the hub with it. **Ask**: the private line to the Founder (bubbles as the site draws them); for him it says member messages are in House.

## Me
- Signed out: "Enter the *congregation*." email and password in the site's field style; Create an account and Google open on the site (they need the human check).
- Signed in: **Activity** (the bell, unread count, marks read on view as the site does, a follow opens the follower), **Your orders**, **Pins** (pictures from the archive, touch and hold to unpin), then the owner's hub above, Sign out.
- **State your reality** (the wall): the site's three steps, the four rules of the room, the form (280 characters, anonymous or named, the **site's own human check run in a small web view**, "Speak it").

## Add-ons (DESIGN section 6)
1. **Widget**: "The site" (the shop lane's) already carries the congregation's numbers (members, and "N waiting for you" for him). Not duplicated.
2. **Live Activity**: not fitting. Nothing in the congregation has a start and an end the app can follow.
3. **Siri and Shortcuts**: `CongregationStatusIntent` (members, what waits for his word, new activity) plus the OpenIntent for rooms, now with Boards, Games and Settings rooms. A "post to the room" intent was not added: it would publish, and the app already holds 10 App Shortcuts (the cap).
4. **Notification buttons**: not fitting, with the reason from lane A (a held post is a judgement on one item; the notice opens the room, where the inline buttons are).
5. **Spotlight**: every room, including the three new ones, in the "congregation" index.
6. **Tips**: `RoomSwipeTip` (rewritten: the moderation is now buttons, so it names them and the touch-and-hold).
7. **Deep links**: `pldev://section/congregation/<stream|room|members|me|activity|messages|boards|games|settings>` and `/congregation/member/<handle>`.

# Tested against the live site (read-only, no key, signed out)
`/api/congregation/stream` (all kinds, `kind=archive` total), `/api/congregation/feed`, `/api/members/directory`, `/api/follow`, `/api/congregation/posts`, `/api/search`, `/api/games/list`, `https://assets.psychedluxuries.com/manifest.json` (1,347 pieces) all answered in the shape the models decode, and a post's picture arrives as a `.webp` (AsyncImage reads it). `/api/congregation/following`, `/api/account/*`, `/api/notifications`, `/api/dm`, `/api/congregation/intent`: answer 401 with the site's sentence when signed out, as the code expects. The member page's embedded profile was parsed with the same bracket scanner the app uses (`@prometheus`: 320 points, tier kin, founderBadge false, favorites empty). The signed-in writes were read from the routes' source and are **not exercised**: no member session was used (his password is not in the config, and a write to a live room is public).

# Gap check (web feature → native)
| Web | Native |
|---|---|
| Room feed, compose, visual picker, repost, report, save, threads, reply, anonymous, held, moderation | built |
| The House / Following | built |
| Stream cards (5 kinds), react, answer, share, save, lightbox, grid toggle, intent card, end line | built |
| Stream comment removal (his) | built |
| Member page: identity, follow, climb, chosen works, Posts | built |
| Owner tabs: Boards, Settings, Social, Games, Ask | built |
| Glyph marks (the real pictures, tinted) | built (`GlyphMark`) |
| Activity page (marks read) | built |
| Wall form (State your reality) | built; **posts through `api/congregation/desire`, which the site does not have yet** (see below); until it is live the form opens the site's own page with its sentence |
| Transmission signup, "what has gone out" on `/congregation` | the signup is the Shop's signal room (linked); the list of past signals is a server action with no route, so it is not shown |
| `/congregation/moderate` (desire wall approval, by MOD_KEY) | not built: it is gated by a moderation key that is not in the config, and the wall's held desires are also announced to Slack for him. A key name for it would be a config line for the lead |
| Sign up, Google sign-in, forgot password | open the site in a sheet (they carry the human check and Google's page) |
| 3D `/room` entrance | belongs to the 3D lane |
| Hero art (GoldCurves), FadeUp motion | not copied: the app's own header and the system's motion stand in |

# Server routes needed (ready to paste, **untested: not deployed**)
Both are for the lead to deploy in pl-headless. The app already calls them and falls back cleanly when they are not there.

1. `app/api/congregation/desire/route.ts`: the wall's form as a route (the site's `postDesire` is a server action, which the phone cannot call). It reuses the action, so the word filter, the human check, the length rules and the Slack note are the site's own.
```ts
import { postDesire } from '@/app/actions';

export const dynamic = 'force-dynamic';

export async function POST(req: Request): Promise<Response> {
  let b: { text?: unknown; name?: unknown; anon?: unknown; token?: unknown };
  try { b = await req.json(); } catch { return Response.json({ ok: false, message: 'Malformed request.' }, { status: 400 }); }
  const r = await postDesire(String(b.text ?? ''), String(b.name ?? ''), b.anon !== false, String(b.token ?? ''));
  return Response.json(r, { status: r.ok ? 200 : 400 });
}
```
Test: `curl -s -X POST https://psychedluxuries.com/api/congregation/desire -H 'content-type: application/json' -d '{"text":"x","anon":true,"token":""}'` should answer `{"ok":false,"message":"Say a little more."}` (the site's own refusal, 400).

2. `app/api/members/profile/route.ts`: a member's public profile as JSON (points, tier, since, chosen works). Today the app reads these out of the member page's data, which works but is a scrape; the app tries this route first.
```ts
import { getCloudflareContext } from '@opennextjs/cloudflare';
import { ensureAuthTables, getPublicProfileByHandle } from '@/lib/auth';
import { getManifest } from '@/lib/archive-manifest';

export const dynamic = 'force-dynamic';

export async function GET(req: Request): Promise<Response> {
  const handle = new URL(req.url).searchParams.get('handle') || '';
  const db = (getCloudflareContext() as { env: Record<string, any> }).env?.DB;
  if (!db) return Response.json({ ok: false }, { status: 503 });
  await ensureAuthTables(db);
  const p = await getPublicProfileByHandle(db, handle);
  if (!p) return Response.json({ ok: false, message: 'No member by that name.' }, { status: 404 });
  const pieces = p.favoriteCrs.length ? await getManifest().catch(() => []) : [];
  const byCr = new Map(pieces.filter(x => x.shareable !== false).map(x => [x.cr, x]));
  const favorites = p.favoriteCrs.map(cr => byCr.get(cr)).filter(Boolean)
    .map(x => ({ cr: x!.cr, thumb: x!.thumb || x!.url, title: x!.title?.trim() || x!.cr }));
  return Response.json({ ok: true, profile: p, favorites });
}
```
Test: `curl -s 'https://psychedluxuries.com/api/members/profile?handle=prometheus'` returns `profile.points` 320 and `favorites: []`.

# Shared-file lines the lead must apply
**None.** `CongregationSection`'s manifest, `CongregationRoomEntity` and its Siri phrase are already wired; the three new rooms index themselves through `CongregationRoom.allCases`. No Info.plist change (every address is https; the human check runs in a web view that loads Cloudflare's script, which needs no permission string), no new key, no new Keychain group.

# Unproven (nothing here has a device)
- The human check in the web view: it is loaded on the site's own address so its token belongs to the site, but only a device proves the site accepts it. If it does not, the wall form's error line says so.
- The games launch: the route answers 302 with a token only for a signed-in session; read from the source, not run.
- Layout at the largest accessibility size and VoiceOver order were reasoned, not checked.
- Pre-existing, not mine: `bash scripts/scan.sh` fails on lane code from earlier waves (a place name in `Town/TownScene.swift`, since removed, a test email in `LANES-storefront-live-test.py`, a tailnet address in history, the font file name in `Info.plist`, and the `claude.ai/code/session` trailer in commit messages). None of it is in the Congregation folder.
