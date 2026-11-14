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
    var allPalettes: [HousePalette] { palettes + archivePalettes + familyPalettes + mixes.map(\.palette) }
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
    func apply() {
        let face: String? = { switch titleFace { case "v2": return PLFace.handV2; case "ransom": return PLFace.ransom; case "ledger": return PLFace.ledger; default: return titleFont } }()
        if let name = face ?? titleFont {
            let nav = UINavigationBarAppearance()
            nav.configureWithDefaultBackground()
            if let large = UIFont(name: name, size: 38) { nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)] }
            if let small = UIFont(name: name, size: 22) { nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: small)] }
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().compactAppearance = nav
            let edge = UINavigationBarAppearance(); edge.configureWithTransparentBackground()
            edge.largeTitleTextAttributes = nav.largeTitleTextAttributes; edge.titleTextAttributes = nav.titleTextAttributes
            UINavigationBar.appearance().scrollEdgeAppearance = edge
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
struct HouseGround: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduce
    @State private var kit = HouseKit.shared
    var body: some View {
        let p = kit.palette
        ZStack {
            if scheme == .dark { p.groundColor } else { ZStack { Color(uiColor: .systemGroupedBackground); p.textColor.opacity(0.45) } }
            if !reduce, let tile = Wallpaper.stencil {
                Image(uiImage: tile).renderingMode(.template).resizable(resizingMode: .tile)
                    .foregroundStyle(scheme == .dark ? p.textColor.opacity(0.07) : p.groundColor.opacity(0.06))
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
        scrollContentBackground(.hidden).background { HouseGround() }
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
struct PLThemePreset: Identifiable, Hashable {
    let id: String, title: String, palette: String, face: String, note: String
    static let all: [PLThemePreset] = [
        .init(id: "home", title: "Your Home Screen", palette: "home-screen", face: "v1", note: "Orange curves on deep brown, your hand"),
        .init(id: "studio-night", title: "Studio night", palette: "obsidian-gold", face: "v1", note: "pl-os at night: gold on obsidian"),
        .init(id: "ember", title: "Ember", palette: "void-ember", face: "v2", note: "Void and ember, the second hand"),
        .init(id: "totem", title: "Totem", palette: "totem-blue-gold", face: "v1", note: "Totem blue with gold"),
        .init(id: "drop", title: "Drop day", palette: "bone-oxblood", face: "ransom", note: "Bone and oxblood, Ransom titles"),
        .init(id: "ledger", title: "The ledger", palette: "cream-indigo", face: "ledger", note: "Cream and indigo, Ledger titles"),
        .init(id: "silver", title: "Night silver", palette: "night-silver", face: "v2", note: "Silver on night"),
        .init(id: "archive", title: "From the archive", palette: "archive-0a", face: "v1", note: "A palette pulled from your archive"),
        .init(id: "pearl", title: "Pearl", palette: "pearl-gold", face: "v1", note: "Pearl and gold, light"),
    ]
}
