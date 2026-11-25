import Foundation

/// Themes over the air (his ask 11-24, S353·7b1e: "something within PL DEV" because SideStore will not update without Wi-Fi).
/// A small public file of theme values (colours and shapes only, nothing private) is fetched once a launch over any connection,
/// kept for offline, and laid over the built-in themes: a patch changes any field of a theme by id, adds a new theme built from
/// looks and walls the app already draws, or hides one; its palettes override or add colourways by name. New code still needs
/// SideStore. Sessions publish it: `Plans/SPEC — PL DEV THEMES OVER THE AIR (S353).md`.
enum ThemeFeed {
    static let url = URL(string: "https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/pldev/themes.json")!

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

    struct Feed: Codable, Equatable {
        var version: Int
        var themes: [Patch]
        var palettes: [HousePalette]
        var home: Home? = nil
    }

    /// Home over the air (his "Sure", 11-24): the sections' order, which are hidden, and what each is called.
    struct Home: Codable, Equatable {
        var order: [String]?
        var hidden: [String]?
        var names: [String: String]?
    }

    /// The config's section order with the feed's laid over it: its order first, then any section it did not name (so a new
    /// section is never lost), minus the hidden ones.
    static func homeOrder(_ base: [String]) -> [String] {
        guard let h = cached?.home else { return base }
        let first = (h.order ?? []).filter(base.contains)
        let hidden = Set(h.hidden ?? [])
        return (first + base.filter { !first.contains($0) }).filter { !hidden.contains($0) }
    }

    static func sectionName(_ id: String, _ fallback: String) -> String {
        guard let name = cached?.home?.names?[id]?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return fallback }
        return name
    }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("house/themes-feed.json")
    }

    // written only on the main actor (refresh), read by views; the file is small
    nonisolated(unsafe) private static var cached: Feed? = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Feed.self, from: $0) }

    /// Fetches the feed; returns the ids of themes whose values changed (so the worn one can be applied again). Offline = no change.
    @MainActor static func refresh() async -> Set<String> {
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
        let ids = Set((old?.themes ?? []).map(\.id)).union(new.themes.map(\.id))
        for id in ids where old?.themes.first(where: { $0.id == id }) != new.themes.first(where: { $0.id == id }) { changed.insert(id) }
        let palettesChanged = Set((old?.palettes ?? []).map(\.name)).symmetricDifference(new.palettes.map(\.name))
            .union(new.palettes.filter { p in old?.palettes.first(where: { $0.name == p.name }) != p }.map(\.name))
        for t in PLThemePreset.all where palettesChanged.contains(t.palette) { changed.insert(t.id) }
        return changed
    }

    /// The built-in themes with the feed laid over them.
    static func merge(_ base: [PLThemePreset]) -> [PLThemePreset] {
        guard let feed = cached else { return base }
        var out = base.compactMap { b -> PLThemePreset? in
            guard let p = feed.themes.first(where: { $0.id == b.id }) else { return b }
            return p.hidden == true ? nil : apply(p, to: b)
        }
        for p in feed.themes where p.hidden != true && !base.contains(where: { $0.id == p.id }) {
            if let t = whole(p) { out.append(t) }
        }
        return out
    }

    /// The built-in palettes with the feed's: a palette of the same name is replaced, a new one is added.
    static func palettes(_ base: [HousePalette]) -> [HousePalette] {
        guard let feed = cached, !feed.palettes.isEmpty else { return base }
        let names = Set(feed.palettes.map(\.name))
        return base.filter { !names.contains($0.name) } + feed.palettes
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
