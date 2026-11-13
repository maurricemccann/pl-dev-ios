# PL DEV: one look, one feel, every app

*His ruling, 11-13: "So we know what the overall UI/UX is like and don't have to change it each app like we did for PL Call."*
*This page is that answer. House is the reference app: every section is built to this page and checked against House, never redesigned on its own.
Apple's guidance behind each line was read at the source on 11-13 (Human Interface Guidelines and the framework pages).
`CONTRACT.md` is how the code fits together; this page is how it looks and behaves.*

## 1. The shape of every app

- **Home is the Home Screen.** The grid shows glass icons over his curve-tile wallpaper, washed in one tint. Each icon has a frosted white symbol, a white name and a red count badge. An app that is not ready is dimmed and carries a key. (`SectionTile`, `Wallpaper`.)
- **An app opens as a pushed screen.** It gets an inline title and the zoom transition from its icon. There are no nested tab bars.
- **More than one area gets a segmented control,** pinned under the title on the bar material (House: Founder · Inbound · Outbound · More). It never gets a second tab bar.
- **The body is a grouped `List`,** and a `Form` when it is all settings or fields. Cards are only used for media: images get a 14 pt continuous corner.
- **Rooms are `NavigationLink` rows** with an SF Symbol and a count badge (`.badge`). Each room is also a case in the app's room enum, so a link, Siri, Spotlight or a notification can land on it by name (`HouseRoom`).
- **Glass belongs only to the floating layer:** the Home control row, toolbars, and sheets from the system. It is never used on content (HIG Materials).

## 2. States: the same four everywhere

| State | What shows | Component |
|---|---|---|
| Loading | A spinner in place, never a blank screen | `Loaded` |
| Empty | `ContentUnavailableView`: a symbol, a short title, one sentence saying what will appear here | `ContentUnavailableView` |
| Failed | One plain sentence and "Pull to try again". Any numbers already on screen stay | `Loaded` / `ResultLine` |
| After an action | One line: "Saved.", "Not saved. <why>." It is never a modal alert | `ResultLine` |

## 3. Actions and gestures

- **Swipe actions** handle the one decision on a row. Swipe left gives the yes (Approve, Done, Keep, Resolve) and swipe right gives the no (Hold, Skip, Reject). This mirror is the same on every list.
- **Touch and hold** (`contextMenu`) holds everything else about the row: copy, open, rewrite, change. Because it cannot be seen, a `TipView` names it once.
- **Many at once:** a Select button puts the list in edit mode. The bulk verbs sit in the bottom toolbar and show their counts.
- **Changes are optimistic.** The row changes at once and comes back if the server refuses, with a `ResultLine` saying why.
- **Anything that publishes, sends to people or closes the site** gets a `confirmationDialog` that says what will happen. Destructive buttons use the destructive role.
- **Every write gets a haptic** (`sensoryFeedback`, from the `PLHaptic` map). Counts roll (`contentTransition(.numericText())`) and ticks bounce (`symbolEffect(.bounce)`).

## 4. Words

- Use his voice from the rules: short, declarative, no exclamation marks, no "Oops".
- **Name the thing, not the system.** Write "Drafts waiting", never "posts_queue status=draft". Never show an id, a key, a URL path or a status code unless it is the subject.
- Dates are relative ("3 h ago", `Ago`). Money is in USD with cents. Counts appear as "12 of 40", never as a bare ratio.

## 5. Colour and type

- Use the system colours (`PLTone`), so light, dark and Increase Contrast work for free. His orange (`Wallpaper.line`) is the one accent: the wallpaper, the tile wash, the founder's own bubbles and the Live Activity tint.
- Use the system text styles. His title face is used only where a theme pack loads it. Every screen must work at the largest accessibility size, where Home switches to two across.

## 5b. Apple's iOS 27 tokens (his ruling 11-13: "complete Apple iOS 27 design token and kits")

- **One source:** Apple's iOS 27 UI-kit export in the Design Kit (`reference/apple-ios27/apple-ios-27-ui-kit.tokens.json`), the same file the R1 apps follow. `python scripts/apple_tokens.py` writes `Shared/AppleTokens.swift` (`IOS27.*`), so the app, the widgets and the extensions all read the same values. Re-run it when Apple's kit is re-exported. Never type a token by hand.
- **Native first.** Where iOS has the real thing, use it:
  - Liquid Glass: `glassEffect`, with `GlassEffectContainer` where pieces sit together.
  - Type: the system text styles, which already carry the kit's sizes and normal leading.
  - Materials: `.thinMaterial` and its siblings.
  - Separators and backgrounds: the List and system colours.
- **`IOS27.*` covers what has no API:**
  - `IOS27.Glass.dock` tints the floating control row, which is drawn as the Dock.
  - `IOS27.LabelsLiquidGlass` colours text on glass.
  - `plReading()` gives long text (captions, messages, answers) the kit's loose body leading.
  - `IOS27.MaterialTint`, `IOS27.Glass.*` and `IOS27.TypeRamp` serve any custom drawing.
- **The house stays only where he ruled it:** his curve-tile wallpaper, his orange as the one accent, and his title face from a theme pack.
- **The app icon has all three appearances:** default, dark (the glyph on clear) and tinted (grayscale), so it sits in his tinted Home Screen like Apple's own apps.

## 5c. The PL remix (his ask 11-13: "give it the PL UI/UX remix with full Apple experience and capabilities")

Apple's structure, gestures and capabilities stay whole. The house is laid over them only where he ruled it for the R1 (S347): his hand on titles, Courier Prime for panel labels, his palettes for colour (Apple's colours only for status dots), and his curve tile underneath. `PLDev/UI/HouseKit.swift` is the one place this lives:
- **Palettes.** 13 of his palettes come from the Design Kit (`kit.json` on the gallery), with his own Home Screen (11-13) as the first and the default. Settings → The house → House palette. The palette drives:
  - the accent (`PLTone.accent`)
  - the wallpaper's ground and lines
  - the icon glass wash
  - every screen's ground (`plGround()`)
  - the widgets and Live Activities (`HouseTint`, through the App Group)
- **His hand on every navigation title.** The main hand (V1) comes from the gallery's `/fonts/` and is cached on the phone, so it never ships in this public repo. It is applied through the navigation bar appearance. A theme pack's title font still wins when one is loaded.
- **The ground.** Each screen sits on the palette's ground with the psyground stencil (his curve tile) at about 7 %. In light mode that is Apple's grouped background washed in the palette's cream. Cards and glass stay Apple's, so they read over the tile.
- **App icons.** Plain (with dark and tinted appearances) plus five alternates in his palettes (Settings → App icon).
- **Control Center.** Controls for PL DEV, Capture, PL Paint, House and GlyphBot (Control Center, Lock Screen and the Action button).
- **His words in his hand** (his ruling 11-13): anything he said or wrote, such as seed phrases, quotes, declarations, affirmations, the Three Truths, Codex lines and hooks, uses `plHand()`. UI labels and other people's words (members' posts, captions in review) never do.
- **Never new.** No section picks its own colours or fonts. If a screen needs a colour, it takes it from the palette.

## 6. The system add-ons every app gets (the premium pass)

An app is not done until each line below is built, or is marked "not fitting" with a reason, in its gap check:

1. **Widget** with its live numbers (small, medium, Lock Screen rectangular and circular). It uses `widgetAccentable` so it tints with his Home Screen. It reads the app's App Group copy only and never holds a key.
2. **Live Activity** for anything with a real start and end (the shift, a render, a sync). It starts on his tap, updates only when the content changes, and ends the moment the thing ends.
3. **Siri, Shortcuts and the Action button:** the app's 2 to 4 most common tasks, each one saying every count in its spoken dialog. Anything that publishes asks `requestConfirmation` first. The whole app stays at 10 App Shortcuts or fewer.
4. **Notification buttons:** real actions only, never "Open". A button that changes anything requires Face ID (`.authenticationRequired`).
5. **Spotlight:** every room is an `IndexedEntity` in the app's own named index, opened by an `OpenIntent`.
6. **Tips:** one or two sentences, only for what cannot be seen, at most one a day.
7. **Deep links:** `pldev://section/<app>/<room>` lands on any room.

## 7. The loop, per app (his order)

Build the app in full, then test it in full, then give it the premium pass (section 6), then run the gap check: every web feature and every fitting Apple experience, each marked built or not built, with why. Then he gives his verdict, and only then does the next app start.

## 8. Shared pieces to reuse (never re-make)

`Console` / `OS` (calls), `Loaded`, `ResultLine`, `Ago`, `Kpi`, `DataWrap`, `Date.pl`, `SectionTile`, `Wallpaper`, `PicturePicker`, the room-enum pattern (`HouseRoom`), `ShiftLive` as the Live Activity pattern, `HouseGlance` as the widget-data pattern, and `NotificationHub.actions` for notification buttons.
