import CoreText
import SwiftUI
import UIKit

// THE PL REMIX (his ask 11-13: "give it the PL UI/UX remix with full Apple experience and capabilities").
// Apple's structure, behaviours and capabilities stay whole; the house is laid over them where he ruled it for the R1 (S347):
// his hand on titles, Courier Prime on panel labels, his palettes for colour (Apple's colours only for status dots), his curve
// tile under everything. Every asset comes from the Design Kit on the gallery at run time (kit.json, /fonts/, the psyground
// stencil) and is cached on the phone, so none of his art or type ships in this public repo.

struct HousePalette: Codable, Hashable, Identifiable {
    let name: String
    let ground: String
    let text: String
    let key: String
    let accent: String
    var id: String { name }
    init(name: String, ground: String, text: String, key: String, accent: String) { self.name = name; self.ground = ground; self.text = text; self.key = key; self.accent = accent }
    private enum K: String, CodingKey { case name, ground, text, key, accent }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name); ground = try c.decode(String.self, forKey: .ground)
        text = try c.decode(String.self, forKey: .text); key = try c.decode(String.self, forKey: .key)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? key
    }
    var groundColor: Color { Color(hex: ground) ?? .black }
    var textColor: Color { Color(hex: text) ?? .white }
    var keyColor: Color { Color(hex: key) ?? .orange }
    var accentColor: Color { Color(hex: accent) ?? .orange }
    var title: String { name.replacingOccurrences(of: "-", with: " ").capitalized }

    /// His own Home Screen (the 11-13 reference: orange curves on deep brown, sampled), the default until he picks another.
    static let homeScreen = HousePalette(name: "home-screen", ground: "#5a1f0e", text: "#efe9dc", key: "#b85536", accent: "#f0a070")
    /// The Fun themes' palettes (S353·7b1e, his ask 11-24: "a few fun ones"). Built in, not in the Design Kit: they are play, not house colour.
    static let fun: [HousePalette] = [
        HousePalette(name: "fun-macos", ground: "#3aa6b9", text: "#111111", key: "#3366cc", accent: "#9c9cff"),   // his Mac OS reference 11-24: teal desktop, platinum, blue bars
        HousePalette(name: "fun-terminal", ground: "#0055aa", text: "#ffffff", key: "#ff8800", accent: "#ffffff"),   // his Linux reference 11-24: blue, white, orange
        HousePalette(name: "fun-glass", ground: "#0e1b2a", text: "#eef6ff", key: "#9fd4ff", accent: "#ffffff"),
        HousePalette(name: "fun-eink", ground: "#f2f0e9", text: "#111111", key: "#2b2b2b", accent: "#777777"),
        HousePalette(name: "fun-synthwave", ground: "#14061f", text: "#ffe9fb", key: "#ff2a9d", accent: "#2de2e6"),   // his retrowave reference 11-24: hot pink and teal neon
        HousePalette(name: "fun-cyberpunk", ground: "#140a1e", text: "#f2e9f7", key: "#ff4f5e", accent: "#19e3c8"),   // his references 11-24: violet-black, coral frames, teal
        HousePalette(name: "fun-retro", ground: "#008080", text: "#ffffff", key: "#ffff55", accent: "#ff55ff"),
        HousePalette(name: "fun-hyperspace", ground: "#02010a", text: "#e6f0ff", key: "#7b5cff", accent: "#3cf2ff"),
        HousePalette(name: "fun-vibe", ground: "#282a36", text: "#f8f8f2", key: "#bd93f9", accent: "#ff79c6"),
    ]
}

@MainActor @Observable final class HouseKit {
    static let shared = HouseKit()
    private(set) var palettes: [HousePalette] = [.homeScreen]
    /// More colourways from the Design Kit (11-13): his archive's palettes, his works' families, and each palette's harmonies.
    private(set) var archivePalettes: [HousePalette] = []
    private(set) var familyPalettes: [HousePalette] = []
    struct Mix: Codable, Hashable { let palette: HousePalette; let base: String; let rule: String }
    private(set) var mixes: [Mix] = []
    /// The title face for navigation titles (his words stay in his V1 hand everywhere): v1, v2, ransom, ledger.
    var titleFace: String = UserDefaults.standard.string(forKey: "pldev.titleFace") ?? "v1" {
        didSet { UserDefaults.standard.set(titleFace, forKey: "pldev.titleFace"); apply() }
    }
    var allPalettes: [HousePalette] { palettes + archivePalettes + familyPalettes + mixes.map(\.palette) + HousePalette.fun }
    func harmonies(of base: String) -> [Mix] { mixes.filter { $0.base == base } }
    private(set) var titleFont: String?          // his hand, V1 (main), once registered
    var paletteName: String = UserDefaults.standard.string(forKey: "pldev.palette") ?? "home-screen" {
        didSet { UserDefaults.standard.set(paletteName, forKey: "pldev.palette"); apply() }
    }
    var palette: HousePalette { allPalettes.first { $0.name == paletteName } ?? .homeScreen }

    private let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("house", isDirectory: true)

    private init() {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: cache.appendingPathComponent("palettes.json")), let p = try? JSONDecoder().decode([HousePalette].self, from: d), !p.isEmpty { palettes = [.homeScreen] + p.filter { $0.name != HousePalette.homeScreen.name } }
        loadExtras(from: try? Data(contentsOf: cache.appendingPathComponent("extras.json")))
        registerFont(at: cache.appendingPathComponent("hand-v1.ttf"))
        HouseFonts.registerCached()   // the themes' house fonts fetched on earlier launches
        if titleFont == nil, UIFont(name: PLFace.handV1, size: 12) != nil { titleFont = PLFace.handV1 }   // bundled since 11-13: his hand from the first frame, offline too
        apply()
    }

    /// Once per launch: the palettes from kit.json and his hand from /fonts/, both cached for the next cold start and offline.
    func refresh(model: AppModel) async {
        guard let http = model.http else { return }
        struct Kit: Decodable { struct C: Decodable { let palettes: [HousePalette]? }; let colors: C? }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "kit.json"), timeout: 40),
           let p = try? JSONDecoder().decode(Kit.self, from: d).colors?.palettes, !p.isEmpty {
            palettes = [.homeScreen] + p.filter { $0.name != HousePalette.homeScreen.name }
            try? JSONEncoder().encode(p).write(to: cache.appendingPathComponent("palettes.json"))
            if let x = extrasJSON(d) { loadExtras(from: x); try? x.write(to: cache.appendingPathComponent("extras.json")) }
        }
        let fontURL = cache.appendingPathComponent("hand-v1.ttf")
        if titleFont == nil, let d = try? await http.send(RequestPlan(origin: "gallery", path: "fonts/MaurriceMccannPsychedHandwrit-Regular.ttf"), timeout: 40) {
            try? d.write(to: fontURL)
            registerFont(at: fontURL)
        }
        apply()
    }

    /// archive, families and mixes out of kit.json, kept as one small file for offline.
    private func extrasJSON(_ kit: Data) -> Data? {
        struct RawMix: Decodable { let name: String; let ground: String; let text: String; let key: String; let accent: String?; let base: String?; let rule: String? }
        struct Kit: Decodable { struct C: Decodable { let archive: [HousePalette]?; let families: [HousePalette]?; let mixes: [RawMix]? }; let colors: C? }
        guard let c = (try? JSONDecoder().decode(Kit.self, from: kit))?.colors else { return nil }
        let mixes = (c.mixes ?? []).compactMap { m -> Mix? in
            guard let base = m.base, let rule = m.rule else { return nil }
            return Mix(palette: HousePalette(name: m.name, ground: m.ground, text: m.text, key: m.key, accent: m.accent ?? m.key), base: base, rule: rule)
        }
        struct Out: Encodable { let archive: [HousePalette]; let families: [HousePalette]; let mixes: [Mix] }
        return try? JSONEncoder().encode(Out(archive: c.archive ?? [], families: c.families ?? [], mixes: mixes))
    }

    private func loadExtras(from d: Data?) {
        struct In: Decodable { let archive: [HousePalette]; let families: [HousePalette]; let mixes: [Mix] }
        guard let d, let x = try? JSONDecoder().decode(In.self, from: d) else { return }
        archivePalettes = x.archive; familyPalettes = x.families; mixes = x.mixes
    }

    private func registerFont(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path), let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              let name = font.postScriptName as String? else { return }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        titleFont = name
    }

    /// Pushes the house into UIKit's shared chrome: his hand on every navigation title, the palette's key as the window tint,
    /// and the palette to the widgets (App Group) so the Lock Screen and Home Screen wear the same colour.
    /// The title face he chose (v1, v2, Ransom, Ledger), or his V1 hand until another is picked. One answer for every title in the app.
    var titleFaceName: String? {
        if let house = HouseFonts.name(titleFace) { return house }   // a theme's house font, once fetched
        switch titleFace { case "v2": return PLFace.handV2; case "ransom": return PLFace.ransom; case "ledger": return PLFace.ledger; default: return titleFont }
    }
    private var barsCarried = false

    func apply() {
        // the carry first: every skin reads it, and the bars below are drawn from it (his note 11-14: a pack changes the whole app)
        PLCarry.update(palette: palette, packAccent: ThemePack.shared.accent, defaultPalette: paletteName == HousePalette.homeScreen.name, packLoaded: ThemePack.shared.isLoaded)
        let carry = PLCarry.snap.active
        let bg = PLCarry.uiGround(fallback: .systemBackground), ink = PLCarry.uiInk(fallback: .label)
        if let name = titleFaceName ?? titleFont {
            let nav = UINavigationBarAppearance()
            nav.configureWithDefaultBackground()
            var large: [NSAttributedString.Key: Any] = [:], small: [NSAttributedString.Key: Any] = [:]
            if let f = UIFont(name: name, size: 38) { large[.font] = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: f) }
            if let f = UIFont(name: name, size: 22) { small[.font] = UIFontMetrics(forTextStyle: .headline).scaledFont(for: f) }
            if carry { large[.foregroundColor] = ink; small[.foregroundColor] = ink; nav.backgroundColor = bg.withAlphaComponent(0.9) }
            nav.largeTitleTextAttributes = large; nav.titleTextAttributes = small
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().compactAppearance = nav
            let edge = UINavigationBarAppearance(); edge.configureWithTransparentBackground()
            edge.largeTitleTextAttributes = nav.largeTitleTextAttributes; edge.titleTextAttributes = nav.titleTextAttributes
            UINavigationBar.appearance().scrollEdgeAppearance = edge
        }
        // tab bars and toolbars wear the pack too; back to the system's own when it is dropped
        if carry || barsCarried {
            let tab = UITabBarAppearance(); tab.configureWithDefaultBackground()
            let tool = UIToolbarAppearance(); tool.configureWithDefaultBackground()
            if carry { tab.backgroundColor = bg.withAlphaComponent(0.92); tool.backgroundColor = bg.withAlphaComponent(0.92) }
            UITabBar.appearance().standardAppearance = tab; UITabBar.appearance().scrollEdgeAppearance = tab
            UIToolbar.appearance().standardAppearance = tool; UIToolbar.appearance().scrollEdgeAppearance = tool; UIToolbar.appearance().compactAppearance = tool
            barsCarried = carry
        }
        SharedState.writeHouseTint(palette.key, ground: palette.ground)
    }
}

extension PLTone {
    /// The house key colour of the chosen palette (a theme pack's accent still wins when one is loaded).
    @MainActor static var house: Color { HouseKit.shared.palette.keyColor }
}

/// The ground under every app's screens: the palette's ground with his curve tile drawn faintly in its text colour (dark), or the
/// palette's cream with the tile in ink (light). The psyground of the Design Kit: about 11 %, so the glass and the cards stand out.
/// Pulse's ground (his ask 11-14: "the performance one have a glyph field of the money goes up glyph"): the same ground and Settings
/// dial as the curves, with his money glyph (Design Kit `glyphs/money.png`, bundled as `money-field.png`) tiled in the palette's key colour.
struct MoneyGround: View {
    @State private var kit = HouseKit.shared
    @AppStorage("pldev.tileStrength") private var strength = 0.5
    @Environment(\.accessibilityReduceTransparency) private var reduce
    @Environment(\.colorScheme) private var scheme
    private static let tile: UIImage? = Bundle.main.url(forResource: "money-field", withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }
    var body: some View {
        let p = kit.palette, k = 0.22 * max(0.2, strength) * (1 + max(0, strength - 0.5) * 3)
        ZStack {
            p.groundColor
            if !reduce, let t = Self.tile {
                let glyphs = Image(uiImage: t).renderingMode(.template).resizable(resizingMode: .tile)
                if scheme == .dark {   // emission (his ask 11-23, "too dark, add some emission"): a blurred additive bloom under the crisp glyphs
                    glyphs.foregroundStyle(p.keyColor.opacity(min(k * 2.4, 0.6))).blur(radius: 7).blendMode(.plusLighter)
                }
                glyphs.foregroundStyle(p.keyColor.opacity(min(k * 1.5, 0.5)))
            }
        }
        .drawingGroup()   // the static field flattens once, so the blur is not redrawn while Pulse scrolls
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct HouseGround: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduce
    @State private var kit = HouseKit.shared
    // the same Settings dial as Home's wallpaper: 0.5 = the quiet default; up to 1 = the bold curves behind glass he liked on pl-os (11-13 screenshot)
    @AppStorage("pldev.tileStrength") private var strength = 0.5
    var body: some View {
        let p = kit.palette, k = 0.14 * max(0.2, strength) * (1 + max(0, strength - 0.5) * 4)   // 0.5 -> 0.07 as before, 1 -> about 0.42
        ZStack {
            if PLCarry.snap.active { PLCarry.tone(.ground, scheme, .clear) }   // a chosen pack: deep ground in dark, pale in light, whichever way the palette runs
            else if scheme == .dark { p.groundColor } else { ZStack { Color(uiColor: .systemGroupedBackground); p.textColor.opacity(0.45) } }
            if !reduce, let tile = Wallpaper.stencil {
                Image(uiImage: tile).renderingMode(.template).resizable(resizingMode: .tile)
                    // a chosen pack's ink (notes4) at the strength the curve dial asks for (his 11-13 "looked really cool")
                    .foregroundStyle(PLCarry.snap.active ? PLCarry.tone(.ink, scheme, .clear, alpha: scheme == .dark ? k : k * 0.86)
                                                         : (scheme == .dark ? p.textColor.opacity(k) : p.groundColor.opacity(k * 0.86)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// His words in his hand (his ruling 11-13: "anything that sounds like it came from the founder needs the house font, anything
/// like seed phrases and quotes"): seed phrases, quotes, declarations, affirmations, the Three Truths, Codex lines, hooks.
/// Follows Dynamic Type; falls back to the serif italic until his hand has loaded.
private struct HandFont: ViewModifier {
    let size: CGFloat
    let style: Font.TextStyle
    @State private var kit = HouseKit.shared
    func body(content: Content) -> some View {
        content.font(kit.titleFont.map { Font.custom($0, size: size, relativeTo: style) } ?? .system(style, design: .serif).italic())
    }
}

extension View {
    /// His words in his hand. Use for anything he said or wrote; never for UI labels or other people's words.
    func plHand(_ size: CGFloat = 24, relativeTo style: Font.TextStyle = .title3) -> some View { modifier(HandFont(size: size, style: style)) }

    /// A screen on the house ground: the list's own grey goes, the cards stay Apple's (they read as glass over the tile).
    func plGround() -> some View {
        scrollContentBackground(.hidden)
            .background { HouseGround(); WindowGround().frame(width: 1, height: 1) }   // the window and the navigation controller behind it take the ground too
            .containerBackground(for: .navigation) { HouseGround() }                    // and the push/pop container: no system white while a page slides in
    }
}


/// His Design Kit faces, bundled (public design assets, his ruling 11-13). V1 leads (titles, his words), V2 supports
/// (his numbers in running text), Ransom V2 is the one loud word, Ledger keeps dates and tallies, Courier Prime labels panels.
enum PLFace {
    static let handV1 = "MaurriceMccannPsychedHandw-Rg"
    static let handV2 = "PL-Hand-V2-Regular"
    static let ransom = "PL-Ransom-V2-Regular"
    static let ledger = "PL Ledger"
    static let label = "CourierPrime-Regular"
}

extension View {
    /// A panel label in Courier Prime, small capitals spaced out, the way pl-os labels its panels.
    func plLabel(_ size: CGFloat = 11, relativeTo style: Font.TextStyle = .caption2) -> some View {
        font(.custom(PLFace.label, size: size, relativeTo: style)).textCase(.uppercase).tracking(1)
    }
    /// A tally or date in his Ledger face.
    func plLedger(_ size: CGFloat = 22, relativeTo style: Font.TextStyle = .title2) -> some View { font(.custom(PLFace.ledger, size: size, relativeTo: style)).monospacedDigit() }
    /// The one loud word (a drop banner): Ransom V2.
    func plRansom(_ size: CGFloat = 28, relativeTo style: Font.TextStyle = .title) -> some View { font(.custom(PLFace.ransom, size: size, relativeTo: style)) }
}

/// His 34 drawn icons (Design Kit icons/, template vectors that take the palette colour like SF Symbols) and his glyph symbols.
enum PLIcon {
    /// The section whose R1 / kit icon he drew; a section he has not drawn keeps its SF Symbol.
    static let forSection: [String: String] = ["house": "house", "curate": "curate", "practice": "practice", "town": "town", "capture": "camera",
                                               "glyphbot": "jarvis", "paint": "scribble", "library": "all_apps", "composer": "remote", "shop": "kiosk",
                                               "pick": "favorite", "status": "notifications"]
    static func image(_ name: String) -> Image { Image("PLIcons/\(name)") }
    static func symbol(_ name: String) -> Image { Image("PLSymbols/\(name)") }
    /// The mark buttons: keep, cut, maybe, fav are his icons.
    static func mark(_ v: String) -> Image { image(v == "fav" ? "favorite" : v) }
}


/// Built-in theme packs (his ask 11-13): one tap sets a palette and the title face together. His words stay in his V1 hand in
/// every pack; only navigation titles change face.
/// S353·7b1e (his ask 11-24, "theme packs updated"): every house palette in the Design Kit has a pack, each sets the text face
/// too, and the list splits dark and light. Faces follow the kit's rule: V1 leads, V2 supports, Ransom is the one loud word.
/// S353·7b1e (his ask 11-24: "use whatever house fonts and color palettes we have to craft 15 distinct themes, each with their own
/// style and unique ui/ux, no two the same"). Each theme owns: palette, light or dark, title face and text face (his hands or the
/// Design Kit's house fonts, fetched once from the gallery), card style (frosted, clear, solid, outlined), corner shape (sharp 0.35,
/// house 1, soft 1.35), spacing (compact 0.85, house 1, airy 1.2), Home's tile shape, the curve wallpaper's scale and strength,
/// motion, and the app icon where a matching icon exists. Text size stays his accessibility choice. No two share the same mix.
struct PLThemePreset: Identifiable, Hashable {
    enum Card: String { case frosted, clear, solid, outline }
    let id: String, title: String, palette: String, face: String, text: String, note: String, dark: Bool
    let card: Card, radius: Double, space: Double, tile: String, repeatSize: Double, curves: Double, calm: Bool, icon: String?
    var fun = false   // the Fun group (his ask 11-24), listed after Dark and Light
    /// One of his archive pieces as the wallpaper, "mode|url": mask (white lines take the key colour), invert (black lines do),
    /// color (the piece as he made it). His picks 11-24. nil = the curve tile.
    var wall: String? = nil

    private static func house(_ f: String) -> String { "file:fonts/house/\(f)" }
    static let all: [PLThemePreset] = [
        .init(id: "home", title: "Your Home Screen", palette: "home-screen", face: "v1", text: "jost",
              note: "Your hand, frosted glass, the curves as you drew them", dark: true,
              card: .frosted, radius: 1, space: 1, tile: "squircle", repeatSize: 300, curves: 0.5, calm: false, icon: "AppIcon-HomeScreen"),
        .init(id: "studio-night", title: "Studio night", palette: "obsidian-gold", face: house("pirata-one.ttf"), text: "jost",
              note: "Blackletter titles, gold hairline cards, sharp and tight", dark: true,
              card: .outline, radius: 0.35, space: 0.85, tile: "square", repeatSize: 240, curves: 0.65, calm: false, icon: "AppIcon-ObsidianGold", wall: "mask|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/abstract-pattern_organic-curves_monochrome_digital_970.png"),
        .init(id: "ember", title: "Ember", palette: "void-ember", face: house("rubik-burned.ttf"), text: "jost",
              note: "Burned titles, round tiles, the curves large and bright", dark: true,
              card: .frosted, radius: 1.35, space: 1, tile: "circle", repeatSize: 420, curves: 0.85, calm: false, icon: "AppIcon-VoidEmber", wall: "mask|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/abstract-pattern_organic-interlocking_black-white_ink-marker_1239.jpg"),
        .init(id: "totem", title: "Totem", palette: "totem-blue-gold", face: house("unifrakturcook.ttf"), text: house("texturina.ttf"),
              note: "Fraktur titles over a book face, clear glass, room to breathe", dark: true,
              card: .clear, radius: 1, space: 1.2, tile: "squircle", repeatSize: 360, curves: 0.4, calm: false, icon: nil),
        .init(id: "indigo", title: "Deep indigo", palette: "deep-indigo", face: house("major-mono-display.ttf"), text: house("syne-mono.ttf"),
              note: "Mono display and mono text, outlined, small dense curves", dark: true,
              card: .outline, radius: 0.35, space: 0.85, tile: "square", repeatSize: 200, curves: 0.3, calm: false, icon: "AppIcon-DeepIndigo"),
        .init(id: "silver", title: "Night silver", palette: "night-silver", face: house("vt323.ttf"), text: "courier",
              note: "Terminal titles, typewriter text, solid panels, still", dark: true,
              card: .solid, radius: 0.35, space: 1, tile: "square", repeatSize: 200, curves: 0.15, calm: true, icon: nil),
        .init(id: "oxblood", title: "Oxblood room", palette: "oxblood-ground", face: house("new-rocker.ttf"), text: "jost",
              note: "Rocker titles, soft solid panels, round tiles, airy", dark: true,
              card: .solid, radius: 1.35, space: 1.2, tile: "circle", repeatSize: 460, curves: 0.6, calm: false, icon: nil),
        .init(id: "forest", title: "Forest room", palette: "forest-ground", face: house("grenze-gotisch.ttf"), text: house("xanh-mono.ttf"),
              note: "Gotisch titles, a serif mono, frosted, sharp corners", dark: true,
              card: .frosted, radius: 0.35, space: 1, tile: "squircle", repeatSize: 300, curves: 0.45, calm: false, icon: nil),
        .init(id: "archive", title: "From the archive", palette: "archive-0a", face: house("rubik-dirt.ttf"), text: "jost",
              note: "Gold on black from your archive, dirt titles, outlined, the curves huge", dark: true,
              card: .outline, radius: 1.35, space: 0.85, tile: "circle", repeatSize: 520, curves: 0.7, calm: false, icon: nil, wall: "invert|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/glyph-abstract_organic-labyrinthine_monochrome_ink_017.jpg"),
        .init(id: "drop", title: "Drop day", palette: "bone-oxblood", face: "ransom", text: "jost",
              note: "Your Ransom titles, solid and sharp, tight like a poster", dark: false,
              card: .solid, radius: 0.35, space: 0.85, tile: "square", repeatSize: 260, curves: 0.35, calm: false, icon: "AppIcon-BoneOxblood", wall: "color|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/abstract-pattern_organic-interlocking_red-warm_digital_2437.png"),
        .init(id: "ledger", title: "The ledger", palette: "cream-indigo", face: "ledger", text: "courier",
              note: "Your Ledger hand, typewriter text, ruled outlines, still", dark: false,
              card: .outline, radius: 0.35, space: 1, tile: "square", repeatSize: 200, curves: 0.1, calm: true, icon: nil, wall: "invert|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/abstract-pattern_organic-interlocking_monochrome_digital-ink_5373.png"),
        .init(id: "linen", title: "Linen", palette: "linen-forest", face: "v2", text: "jost",
              note: "Your second hand, clear glass, soft and airy, round tiles", dark: false,
              card: .clear, radius: 1.35, space: 1.2, tile: "circle", repeatSize: 420, curves: 0.25, calm: false, icon: nil),
        .init(id: "copper", title: "Copper", palette: "ivory-copper", face: house("saira-stencil-one.ttf"), text: "jost",
              note: "Stencil titles, solid panels, the house shape", dark: false,
              card: .solid, radius: 1, space: 1, tile: "squircle", repeatSize: 300, curves: 0.4, calm: false, icon: nil, wall: "color|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/abstract-pattern_organic-flowing_warm-pink_digital_4693.png"),
        .init(id: "smoke", title: "Warm smoke", palette: "warm-smoke", face: house("pencilant.otf"), text: house("special-elite.ttf"),
              note: "Pencil titles, typed text, soft outlines, still", dark: false,
              card: .outline, radius: 1.35, space: 1.2, tile: "circle", repeatSize: 360, curves: 0.2, calm: true, icon: nil),
        .init(id: "pearl", title: "Pearl", palette: "pearl-gold", face: house("fruktur.ttf"), text: "jost",
              note: "Fruktur titles, clear glass, soft corners, wide curves", dark: false,
              card: .clear, radius: 1.35, space: 1, tile: "squircle", repeatSize: 460, curves: 0.3, calm: false, icon: nil),
        // Fun (his list 11-24: macOS, terminal/Linux, glass, E ink, synthwave/neon, cyberpunk, retro 90s, hyperspace, vibe coded).
        // Open fonts bundled in the app (OFL, Google Fonts), so they work offline.
        .init(id: "fun-macos", title: "Mac OS", palette: "fun-macos", face: "bundle:system", text: "system",
              note: "The platinum era: grey square windows on a teal desktop, blue bars, a quiet wave pattern, still", dark: false,
              card: .solid, radius: 0.15, space: 1, tile: "square", repeatSize: 120, curves: 0.2, calm: true, icon: nil, fun: true),
        .init(id: "fun-terminal", title: "Linux", palette: "fun-terminal", face: "file:fonts/house/vt323.ttf", text: "bundle:IBMPlexMono-Regular",
              note: "Retro desktop: white windows on deep blue, orange marks, pixel titles, mono text, still", dark: true,
              card: .solid, radius: 0.1, space: 0.9, tile: "square", repeatSize: 180, curves: 0.15, calm: true, icon: nil, fun: true),
        .init(id: "fun-glass", title: "Glass", palette: "fun-glass", face: "bundle:Michroma-Regular", text: "system",
              note: "All clear glass over deep blue, round and airy", dark: true,
              card: .clear, radius: 1.5, space: 1.2, tile: "circle", repeatSize: 480, curves: 0.35, calm: false, icon: nil, fun: true),
        .init(id: "fun-eink", title: "E ink", palette: "fun-eink", face: "bundle:Literata-Regular", text: "bundle:Literata-Regular",
              note: "Paper and ink: a book face, flat panels, no curves, no motion", dark: false,
              card: .solid, radius: 0.35, space: 1.1, tile: "square", repeatSize: 300, curves: 0, calm: true, icon: nil, fun: true),
        .init(id: "fun-synthwave", title: "Synthwave", palette: "fun-synthwave", face: "bundle:MrDafoe-Regular", text: "jost",
              note: "Retrowave: pink script titles, hot pink and teal neon, glowing lines on purple night", dark: true,
              card: .outline, radius: 1, space: 1, tile: "circle", repeatSize: 420, curves: 0.85, calm: false, icon: nil, fun: true),
        .init(id: "fun-cyberpunk", title: "Cyberpunk", palette: "fun-cyberpunk", face: "bundle:ChakraPetch-SemiBold", text: "bundle:GeistMono-Regular",
              note: "Night city OS: coral hairline frames on violet-black, teal, a code font", dark: true,
              card: .outline, radius: 0.6, space: 0.85, tile: "square", repeatSize: 220, curves: 0.3, calm: false, icon: nil, fun: true),
        .init(id: "fun-retro", title: "Retro 90s", palette: "fun-retro", face: "bundle:PressStart2P-Regular", text: "courier",
              note: "Pixel titles on desktop teal, chunky solid panels", dark: true,
              card: .solid, radius: 0.15, space: 1, tile: "square", repeatSize: 200, curves: 0.2, calm: false, icon: nil, fun: true),
        .init(id: "fun-hyperspace", title: "Hyperspace", palette: "fun-hyperspace", face: "bundle:Audiowide-Regular", text: "jost",
              note: "Violet and cyan in deep space, frosted, the curves vast", dark: true,
              card: .frosted, radius: 1.35, space: 1.2, tile: "circle", repeatSize: 560, curves: 0.9, calm: false, icon: nil, fun: true, wall: "invert|https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/abstract-pattern_organic-flowing_monochrome_digital_5457.png"),
        .init(id: "fun-vibe", title: "Vibe coded", palette: "fun-vibe", face: "bundle:JetBrainsMono-Regular", text: "bundle:JetBrainsMono-Regular",
              note: "Editor night: purple and pink, code font, outlined panes", dark: true,
              card: .outline, radius: 0.6, space: 1, tile: "squircle", repeatSize: 260, curves: 0.3, calm: false, icon: nil, fun: true),
    ]

    /// Fetches the theme's house fonts (first time only), then sets every switch it owns; the views read the same keys.
    /// Returns false when a font could not be fetched (offline, never cached): the rest still applies, titles fall back to his V1.
    @MainActor func apply() async -> Bool {
        let titleOK = await HouseFonts.ensure(face)
        let textOK = await HouseFonts.ensure(text)
        let kit = HouseKit.shared, d = UserDefaults.standard
        d.set(radius, forKey: "pldev.styleRadius"); d.set(space, forKey: "pldev.styleSpace")
        d.set(tile, forKey: "pldev.styleTile"); d.set(repeatSize, forKey: "pldev.styleRepeat")
        d.set(card == .frosted || card == .clear, forKey: "pldev.glassBlur"); d.set(card == .clear, forKey: "pldev.glassClear")
        d.set(card == .outline, forKey: "pldev.cardLine")
        d.set(wall ?? "", forKey: "pldev.styleWall")
        d.set(curves, forKey: "pldev.tileStrength"); d.set(calm ? "reduce" : "full", forKey: "pldev.motion")
        d.set(textOK ? text : "jost", forKey: "pldev.font")
        d.set(dark ? "dark" : "light", forKey: "pldev.theme")
        kit.paletteName = palette; kit.titleFace = face   // last: their didSet re-applies the bars with everything above in place
        if let icon, UIApplication.shared.alternateIconName != icon { UIApplication.shared.setAlternateIconName(icon, completionHandler: nil) }
        return titleOK && textOK
    }

    @MainActor static var current: PLThemePreset? {
        let d = UserDefaults.standard
        return all.first { $0.palette == HouseKit.shared.paletteName && $0.face == HouseKit.shared.titleFace && $0.tile == PLStyle.tile
            && abs($0.radius - Double(PLStyle.radius)) < 0.01 && d.string(forKey: "pldev.font") == $0.text }
    }
}
