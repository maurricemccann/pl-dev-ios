import Foundation

/// Themes over the air (his ask 11-24, S353·7b1e: "something within PL DEV" because SideStore will not update without Wi-Fi).
/// A small public file of theme values (colours and shapes only, nothing private) is fetched once a launch over any connection,
/// kept for offline, and laid over the built-in themes: a patch changes any field of a theme by id, adds a new theme built from
/// looks and walls the app already draws, or hides one; its palettes override or add colourways by name. New code still needs
/// SideStore. Sessions publish it: `Plans/SPEC — PL DEV THEMES OVER THE AIR (S353).md`.
enum ThemeFeed {
    /// The public archive bucket (art and this feed). One constant: Themes, the wallpapers and the feed all read it.
    static let r2 = "https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/"
    static let url = URL(string: r2 + "pldev/themes.json")!

    struct Patch: Codable, Equatable {
        var id: String
        var title, palette, face, text, note: String?
        var dark: Bool?
        var card: String?
        var radius, space: Double?
        var tile, look, wall: String?
        var calm: Bool?
        var curves, repeatSize, tint, through: Double?
        var icon, icons, mark: String?
        var fun: Bool?
        var titleFX: String?
        var hidden: Bool?
    }

    /// Every block is optional (config over the air, phase 1, S353·7b1e): a missing block leaves that screen on its built-in value.
    /// Builds before this one still need `version`, `themes` and `palettes` in the file; only ever add optional fields.
    struct Feed: Codable, Equatable {
        var version: Int
        var themes: [Patch]? = nil
        var palettes: [HousePalette]? = nil
        var home: Home? = nil
        var calendar: CalendarList? = nil
        var copy: [String: String]? = nil
        var words: Words? = nil
        var truths: [String]? = nil
        var house: House? = nil
        var wallpapers: [Wallpaper]? = nil
        var timing: Timing? = nil
        var links: Links? = nil
        // phase 2 (his "build all phases", 11-25)
        var practice: Practice? = nil
        var lists: Lists? = nil
        var shop: Shop? = nil
        /// Buddy's check-in lines by group: low, middle, high, body (the Rising Scale).
        var buddy: [String: [String]]? = nil
    }

    /// Home over the air (his "Sure", 11-24): the sections' order, which are hidden, what each is called, and its SF Symbol.
    struct Home: Codable, Equatable {
        var order: [String]?
        var hidden: [String]?
        var names: [String: String]?
        var symbols: [String: String]?
    }

    /// One calendar in Calendar's Add picker: id (what the server stores), label, SF Symbol, accent (true) or grey, and the
    /// reminder time for an item of that kind with no time of its own ("09:00"; left out = no reminder).
    struct CalendarKind: Codable, Equatable {
        var id: String
        var label: String?
        var symbol: String?
        var accent: Bool?
        var time: String?
        var color: String? = nil   // accent | blue | green | red | purple | orange | pink | teal | grey (CalendarKinds.color)
    }
    struct CalendarList: Codable, Equatable {
        var kinds: [CalendarKind]?
        var `default`: String?
        var days: Int?
    }

    struct Words: Codable, Equatable {
        var banned: [String]?
        var voice: [String]?
    }

    /// House: the doors, plus its lists. Pairs are [id, label]; council rows are [id, name, blurb]; job paths must be
    /// `run/<name>` routes the console already serves.
    struct House: Codable, Equatable {
        var doors: Doors?
        var council: [[String]]?
        var seasons: [[String]]?
        var jobs: [Job]?
        var platforms: [String]?
        var pipeline: [String]?
        var generators: [String: String]?
    }
    struct Job: Codable, Equatable {
        var path: String
        var title: String
        var symbol: String
    }

    /// Practice wording and lists. boardSources are [id, label]; rooms rename a room or change its SF Symbol by id;
    /// rehearsal is the five stage titles; wordLists are "runner" (the jumping game) and "restore" (the sliding puzzle).
    struct Practice: Codable, Equatable {
        var moods: [String]?
        var boardSources: [[String]]?
        var rooms: [String: Room]?
        var rehearsal: [String]?
        var notifications: [String: String]?
        var wordLists: [String: [String]]?
    }
    struct Room: Codable, Equatable {
        var title: String?
        var symbol: String?
    }

    /// GlyphBot, Congregation, Town, Library and Curate lists. notifyKinds are [key, label]; townAreas map a session area to a
    /// building id the town already draws. The taxonomy must match the server's.
    struct Lists: Codable, Equatable {
        var interviewDomains: [String]?
        var modelCosts: [String: Double]?
        var notifyKinds: [[String]]?
        var roles: [String]?
        var townAreas: [String: String]?
        var taxonomy: Taxonomy?
    }
    /// pillars, media, bodies: names. categories (the Library's file-in rooms): [label, id]. classes: [id, label].
    /// archive (Curate's three archive categories): [id, label].
    struct Taxonomy: Codable, Equatable {
        var pillars: [String]?
        var categories: [[String]]?
        var media: [String]?
        var bodies: [String]?
        var classes: [[String]]?
        var archive: [[String]]?
    }

    /// The app's shop. collections: a piece is in one when its upper-cased name contains any `match` entry and no `exclude`
    /// entry ("^X" = starts with X, "=X" = is exactly X); a slug the app has replaces that collection, `order` places it.
    struct Shop: Codable, Equatable {
        var collections: [ShopRule]?
        var system: System?
        var study: [String]?
        var code: [String]?
        var engines: [String]?
        var truths: [[String]]?
        var orderSteps: [String]?
    }
    struct ShopRule: Codable, Equatable {
        var slug: String?
        var name: String
        var match: [String]
        var exclude: [String]?
        var order: Int?
    }
    /// The system page's numbers: lines are [value, label, detail]; specs are [value, label]; models are name, total, share (%).
    struct System: Codable, Equatable {
        var lines: [[String]]?
        var specs: [[String]]?
        var stack: [String]?
        var models: [Model]?
    }
    struct Model: Codable, Equatable {
        var name: String
        var total: String
        var share: Double
    }
    /// The House rooms, by room id: the Rooms panel's order, the doors hidden anywhere, and their names.
    struct Doors: Codable, Equatable {
        var order: [String]?
        var hidden: [String]?
        var names: [String: String]?
    }

    /// A wallpaper from the archive: `url` is a full https address or a file name in the public bucket; `mode` is how it is
    /// drawn (color, mask or invert; color when left out). An id the app already has replaces that wallpaper.
    struct Wallpaper: Codable, Equatable {
        var id: String
        var title: String
        var url: String
        var mode: String?
    }

    /// Refresh rates in seconds, the stream page size, and the defaults for the practice hour and quiet hours ("HH:MM").
    struct Timing: Codable, Equatable {
        var poll, pcPoll: Double?
        var streamLimit, practiceHour: Int?
        var quietFrom, quietTo: String?
    }

    struct Social: Codable, Equatable {
        var name: String
        var url: String
    }
    /// `compose` maps a platform to its composer address; `{text}` in it becomes the caption, encoded.
    struct Links: Codable, Equatable {
        var socials: [Social]?
        var compose: [String: String]?
        var horizon: String?
        var academy: String?
        var shopDebug: String?
        /// Status's health path per origin name ("cron": "health"); paths only, never an address.
        var healthPaths: [String: String]?
    }

    /// Composer and PL World stay off Home unless the feed's `home.hidden` says otherwise (a list there replaces this one).
    static let defaultHidden = ["composer", "plworld"]

    /// The config's section order with the feed's laid over it: its order first, then any section it did not name (so a new
    /// section is never lost), minus the hidden ones.
    static func homeOrder(_ base: [String]) -> [String] {
        let h = cached?.home
        let first = (h?.order ?? []).filter(base.contains)
        let hidden = Set(h?.hidden ?? defaultHidden)
        return (first + base.filter { !first.contains($0) }).filter { !hidden.contains($0) }
    }

    static func sectionSymbol(_ id: String, _ fallback: String) -> String { nonEmpty(cached?.home?.symbols?[id]) ?? fallback }

    // MARK: the phase-1 blocks, read by the screens (nil or empty = the screen keeps its built-in value)

    static func text(_ key: String, _ fallback: String) -> String { nonEmpty(cached?.copy?[key]) ?? fallback }

    /// The cached feed, for the phase-2 screens; read with the helpers below so an empty list falls back.
    static var feed: Feed? { cached }

    /// A non-empty list of non-empty strings, else nil.
    static func list(_ a: [String]?) -> [String]? {
        let l = (a ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return l.isEmpty ? nil : l
    }
    /// Rows of exactly two non-empty strings, else nil.
    static func pairs(_ a: [[String]]?) -> [(String, String)]? {
        let p = (a ?? []).filter { $0.count == 2 && !$0[0].isEmpty && !$0[1].isEmpty }.map { ($0[0], $0[1]) }
        return p.isEmpty ? nil : p
    }
    /// Rows of exactly three non-empty strings, else nil.
    static func triples(_ a: [[String]]?) -> [(String, String, String)]? {
        let p = (a ?? []).filter { $0.count == 3 && !$0.contains(where: \.isEmpty) }.map { ($0[0], $0[1], $0[2]) }
        return p.isEmpty ? nil : p
    }
    /// An https address from the links block, else nil.
    static func https(_ s: String?) -> URL? {
        guard let s = nonEmpty(s), s.hasPrefix("https://") else { return nil }
        return URL(string: s)
    }

    static var calendarKinds: [CalendarKind]? {
        // the id shape pl-cron stores (^[a-z0-9-]{1,24}$, b8fd54e); anything else would save as a reminder
        let k = (cached?.calendar?.kinds ?? []).filter { $0.id.range(of: "^[a-z0-9-]{1,24}$", options: .regularExpression) != nil }
        return k.isEmpty ? nil : k
    }
    static var calendarDefault: String? { nonEmpty(cached?.calendar?.default) }
    static var calendarDays: Int? { cached?.calendar?.days.flatMap { (1...400).contains($0) ? $0 : nil } }

    static var banned: [String]? { list(cached?.words?.banned) }
    static var voice: [String]? { list(cached?.words?.voice) }

    /// The Three Truths, only when the file carries all three.
    static var truths: [String]? { list(cached?.truths).flatMap { $0.count == 3 ? $0 : nil } }

    static func doorName(_ id: String, _ fallback: String) -> String { nonEmpty(cached?.house?.doors?.names?[id]) ?? fallback }
    static func doorHidden(_ id: String) -> Bool { cached?.house?.doors?.hidden?.contains(id) ?? false }
    /// The ids in the feed's order first, then the rest in their own order.
    static func doorOrder(_ base: [String]) -> [String] {
        let first = (cached?.house?.doors?.order ?? []).filter(base.contains)
        return first + base.filter { !first.contains($0) }
    }

    static var wallpapers: [Wallpaper] {
        (cached?.wallpapers ?? []).filter { !$0.id.isEmpty && !$0.title.isEmpty && !$0.url.isEmpty }
    }

    static var poll: Double? { cached?.timing?.poll.flatMap { $0 >= 30 && $0 <= 3600 ? $0 : nil } }
    static var pcPoll: Double? { cached?.timing?.pcPoll.flatMap { $0 >= 15 && $0 <= 3600 ? $0 : nil } }
    static var streamLimit: Int? { cached?.timing?.streamLimit.flatMap { (1...100).contains($0) ? $0 : nil } }
    static var practiceHour: Int? { cached?.timing?.practiceHour.flatMap { (0...23).contains($0) ? $0 : nil } }
    static var quietFrom: String? { hhmm(cached?.timing?.quietFrom) }
    static var quietTo: String? { hhmm(cached?.timing?.quietTo) }

    static var socials: [(String, String)]? {
        let s = (cached?.links?.socials ?? []).filter { !$0.name.isEmpty && $0.url.hasPrefix("https://") }.map { ($0.name, $0.url) }
        return s.isEmpty ? nil : s
    }
    static func social(_ name: String) -> String? { socials?.first { $0.0 == name }?.1 }
    static func compose(_ platform: String) -> String? { nonEmpty(cached?.links?.compose?[platform]).flatMap { $0.hasPrefix("https://") ? $0 : nil } }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }
    private static func hhmm(_ s: String?) -> String? {
        guard let s, Quiet.minutes(s) != nil else { return nil }
        return s
    }

    static func sectionName(_ id: String, _ fallback: String) -> String {
        guard let name = cached?.home?.names?[id]?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return fallback }
        return name
    }

    // MARK: larger content beside the feed (phase 2): School's lessons and the Paint handbook

    private static func extraFile(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("house/feed-" + name)
    }

    /// The last good copy of `pldev/<name>` fetched from the bucket, or nil (the screen then reads its bundled copy).
    static func extra(_ name: String) -> Data? { try? Data(contentsOf: extraFile(name)) }

    /// Each file is kept only when it reads as the bundled shape; a 404 removes the copy (back to the bundle); offline keeps it.
    @MainActor private static func fetchExtras() async {
        let files: [(String, (Data) -> Bool)] = [("school.json", SchoolModel.valid), ("prog.json", ProgModel.valid), ("handbook.json", { !NativeHandbook.parse($0).isEmpty })]
        for (name, valid) in files {
            guard let u = URL(string: r2 + "pldev/" + name) else { continue }
            var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("PLDev", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { continue }
            if code == 404 { try? FileManager.default.removeItem(at: extraFile(name)); continue }
            guard code == 200, valid(data) else { continue }
            try? FileManager.default.createDirectory(at: extraFile(name).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: extraFile(name))
        }
    }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("house/themes-feed.json")
    }

    // written only on the main actor (refresh), read by views; the file is small
    nonisolated(unsafe) private static var cached: Feed? = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Feed.self, from: $0) }

    /// Fetches the feed; returns the ids of themes whose values changed (so the worn one can be applied again). Offline = no change.
    @MainActor static func refresh() async -> Set<String> {
        await fetchExtras()
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("PLDev", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let new = try? JSONDecoder().decode(Feed.self, from: data) else { return [] }
        let old = cached
        guard new != old else { return [] }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
        cached = new
        if new.home != old?.home { AppModel.shared.reloadHome() }
        var changed = Set<String>()
        let oldThemes = old?.themes ?? [], newThemes = new.themes ?? []
        let oldPalettes = old?.palettes ?? [], newPalettes = new.palettes ?? []
        let ids = Set(oldThemes.map(\.id)).union(newThemes.map(\.id))
        for id in ids where oldThemes.first(where: { $0.id == id }) != newThemes.first(where: { $0.id == id }) { changed.insert(id) }
        let palettesChanged = Set(oldPalettes.map(\.name)).symmetricDifference(newPalettes.map(\.name))
            .union(newPalettes.filter { p in oldPalettes.first(where: { $0.name == p.name }) != p }.map(\.name))
        for t in PLThemePreset.all where palettesChanged.contains(t.palette) { changed.insert(t.id) }
        return changed
    }

    /// The built-in themes with the feed laid over them.
    static func merge(_ base: [PLThemePreset]) -> [PLThemePreset] {
        guard let themes = cached?.themes, !themes.isEmpty else { return base }
        var out = base.compactMap { b -> PLThemePreset? in
            guard let p = themes.first(where: { $0.id == b.id }) else { return b }
            return p.hidden == true ? nil : apply(p, to: b)
        }
        for p in themes where p.hidden != true && !base.contains(where: { $0.id == p.id }) {
            if let t = whole(p) { out.append(t) }
        }
        return out
    }

    /// The built-in palettes with the feed's: a palette of the same name is replaced, a new one is added.
    static func palettes(_ base: [HousePalette]) -> [HousePalette] {
        guard let feedPalettes = cached?.palettes, !feedPalettes.isEmpty else { return base }
        let names = Set(feedPalettes.map(\.name))
        return base.filter { !names.contains($0.name) } + feedPalettes
    }

    private static func apply(_ p: Patch, to b: PLThemePreset) -> PLThemePreset {
        var t = PLThemePreset(id: b.id, title: p.title ?? b.title, palette: p.palette ?? b.palette, face: p.face ?? b.face, text: p.text ?? b.text,
                              note: p.note ?? b.note, dark: p.dark ?? b.dark, card: p.card.flatMap({ PLThemePreset.Card(rawValue: $0) }) ?? b.card,
                              radius: p.radius ?? b.radius, space: p.space ?? b.space, tile: p.tile ?? b.tile, look: p.look ?? b.look, wall: p.wall ?? b.wall)
        t.calm = p.calm ?? b.calm; t.curves = p.curves ?? b.curves; t.repeatSize = p.repeatSize ?? b.repeatSize
        t.tint = p.tint ?? b.tint; t.through = p.through ?? b.through
        t.icon = p.icon ?? b.icon; t.icons = p.icons ?? b.icons; t.mark = p.mark ?? b.mark
        t.fun = p.fun ?? b.fun; t.titleFX = p.titleFX ?? b.titleFX
        return t
    }

    /// A new theme needs every core field; one missing and it is left out rather than drawn half-made.
    private static func whole(_ p: Patch) -> PLThemePreset? {
        guard let title = p.title, let palette = p.palette, let face = p.face, let text = p.text, let note = p.note, let dark = p.dark,
              let card = p.card.flatMap({ PLThemePreset.Card(rawValue: $0) }), let radius = p.radius, let space = p.space,
              let tile = p.tile, let look = p.look, let wall = p.wall else { return nil }
        let base = PLThemePreset(id: p.id, title: title, palette: palette, face: face, text: text, note: note, dark: dark,
                                 card: card, radius: radius, space: space, tile: tile, look: look, wall: wall)
        return apply(p, to: base)
    }
}
