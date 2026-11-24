import SwiftUI
import UIKit

// THE 24 THEMES (his ask 11-24, S353·7b1e: "redesign a few, that means the whole thing ... each theme should have a different
// wallpaper, or in the settings I should be able to choose ... A lot of these themes looked the same").
// 15 house, 9 Fun. A theme owns: colours, light or dark, title face, text face, card style, shape, spacing, Home's tile shape and
// tile look, icon set, wallpaper, motion and app icon. Colours are Design Kit values (palettes, brand, families); the Fun ones are
// sampled from his references. scripts/check_themes.py holds the distinctness test.

extension HousePalette {
    private static func th(_ id: String, _ ground: String, _ text: String, _ key: String, _ accent: String, _ surface: String? = nil) -> HousePalette {
        HousePalette(name: "th-" + id, ground: ground, text: text, key: key, accent: accent, surface: surface)
    }
    /// One palette per theme, built in so a theme works before the Design Kit has been fetched, and offline.
    static let themed: [HousePalette] = [
        th("studio-night", "#0e0c08", "#efe9dc", "#c9a84c", "#dfb536"),
        th("ember", "#0a0807", "#efe9dc", "#d4550a", "#c99472", "#1d1d19"),
        th("totem", "#162a4d", "#f0ece4", "#c9a84c", "#327ad3", "#1d3560"),
        th("indigo", "#1c1e65", "#e6e8f5", "#c1ab7c", "#785fce"),
        th("silver", "#070707", "#c4c4c3", "#b0b8c8", "#b8c5d5", "#1c1d22"),
        th("oxblood", "#5e1622", "#f0ece4", "#c98fb0", "#e7cf86", "#74202e"),
        th("forest", "#14301a", "#f0ece4", "#2d8a6e", "#178e45", "#1e4226"),
        th("archive", "#000000", "#f0ece4", "#dfb536", "#e7cf86", "#14110a"),
        th("drop", "#ccc3bf", "#171310", "#7c1f1f", "#b24b1b", "#ddd6d2"),
        th("ledger", "#e6e4bb", "#13170f", "#33307e", "#50583c", "#f1efd0"),
        th("linen", "#edeae0", "#171310", "#1a3d1e", "#178e45", "#f6f4ec"),
        th("copper", "#d5c09c", "#131516", "#a9743a", "#466097", "#e6d6b8"),
        th("smoke", "#bcb8b0", "#0c0b0d", "#7c1f1f", "#7a5b41", "#d3cfc8"),
        th("pearl", "#cabce5", "#171310", "#785fce", "#b0842c", "#e4dcf2"),
        th("macos", "#3aa6b9", "#111111", "#3366cc", "#9c9cff", "#dddddd"),
        th("linux", "#2c1b12", "#f3e9e1", "#e95420", "#f6b28c", "#42291a"),
        th("glass", "#0b2a45", "#eef8ff", "#7fd4ff", "#ffffff"),
        th("eink", "#f2f0e9", "#111111", "#2b2b2b", "#777777", "#f2f0e9"),
        th("synthwave", "#14061f", "#ffe9fb", "#ff2a9d", "#2de2e6", "#25103a"),
        th("cyberpunk", "#140a1e", "#f2e9f7", "#ff4f5e", "#19e3c8", "#1d0f2a"),
        th("retro", "#cdbaf5", "#2a1a4a", "#7a3cff", "#ff6ec7", "#fff0fb"),
        th("hyperspace", "#02010a", "#e6f0ff", "#7b5cff", "#3cf2ff", "#130f30"),
        th("vibe", "#050805", "#d8ffd0", "#39ff14", "#bd93f9", "#282a36"),
    ]
}

struct PLThemePreset: Identifiable, Hashable {
    enum Card: String { case frosted, clear, solid, outline }
    let id: String, title: String, palette: String, face: String, text: String, note: String, dark: Bool
    /// radius: 0.1 sharp, 0.5 cut, 1 house, 1.5 round.
    let card: Card, radius: Double, space: Double, tile: String
    /// The tile look drawn over the glass: glass, typewriter, keycap, bubble, terminal, neon, flat, bevel, dome, bare.
    let look: String
    /// "curves", "mask|url", "invert|url", "color|url", "kit|path" or "code|name" (ThemeGround draws each).
    let wall: String
    var calm = false, curves = 0.5, repeatSize = 300.0, tint = 0.3, through = 0.5
    var icon: String? = nil
    /// "pl" = his drawn icons where he drew one; "sf" = system symbols only. A new open-licence set gets its own name here.
    var icons = "pl"
    /// One of his glyph marks beside Home's name.
    var mark: String? = nil
    var fun = false
    /// The title's finish: "chrome" (Synthwave's lettering), "glow" (neon), or none.
    var titleFX = ""

    private static func house(_ f: String) -> String { "file:fonts/house/\(f)" }
    private static let art = "https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/"

    static let all: [PLThemePreset] = [
        .init(id: "home", title: "Your Home Screen", palette: "home-screen", face: "v1", text: "jost",
              note: "Your hand, frosted squircles, the curves as you drew them", dark: true,
              card: .frosted, radius: 1, space: 1, tile: "squircle", look: "glass", wall: "curves",
              tint: 0.45, icon: "AppIcon-HomeScreen", mark: "glyph-guy"),
        .init(id: "studio-night", title: "Studio night", palette: "th-studio-night", face: house("pirata-one.ttf"), text: "jost",
              note: "Blackletter titles, gold hairlines, sharp and tight, Studio night on the wall", dark: true,
              card: .outline, radius: 0.1, space: 0.85, tile: "square", look: "neon", wall: "mask|" + art + "abstract-pattern_organic-curves_monochrome_digital_970.png",
              curves: 0.65, tint: 0.1, icon: "AppIcon-ObsidianGold"),
        .init(id: "ember", title: "Ember", palette: "th-ember", face: house("rubik-burned.ttf"), text: house("texturina.ttf"),
              note: "Burned titles over a book face, round domed keys, Ember burning behind", dark: true,
              card: .frosted, radius: 1.5, space: 1, tile: "circle", look: "dome", wall: "mask|" + art + "abstract-pattern_organic-interlocking_black-white_ink-marker_1239.jpg",
              curves: 0.8, tint: 0.55, icon: "AppIcon-VoidEmber"),
        .init(id: "totem", title: "Totem", palette: "th-totem", face: house("unifrakturcook.ttf"), text: house("medievalsharp.ttf"),
              note: "Fraktur over a carved face, clear glass, your tile pattern in gold on deep blue", dark: true,
              card: .clear, radius: 1, space: 1.2, tile: "squircle", look: "bevel", wall: "kit|patterns/pl_tile.png",
              curves: 0.45, tint: 0.2, through: 0.7),
        .init(id: "indigo", title: "Deep indigo", palette: "th-indigo", face: house("major-mono-display.ttf"), text: house("syne-mono.ttf"),
              note: "Mono display and mono text, cut outlines, a small dense curve grid", dark: true,
              card: .outline, radius: 0.5, space: 0.85, tile: "square", look: "terminal", wall: "kit|patterns/ar-curve-tile.png",
              curves: 0.35, repeatSize: 200, tint: 0, icon: "AppIcon-DeepIndigo", icons: "iconoir"),
        .init(id: "silver", title: "Night silver", palette: "th-silver", face: house("big-shoulders-stencil.ttf"), text: house("cutive-mono.ttf"),
              note: "Stencil titles, typewriter text, metal keycaps on brushed steel, still", dark: true,
              card: .solid, radius: 0.5, space: 1, tile: "square", look: "chrome", wall: "code|brushed",
              calm: true, tint: 0.1, through: 0.2),
        .init(id: "oxblood", title: "Oxblood room", palette: "th-oxblood", face: house("new-rocker.ttf"), text: "jost",
              note: "Rocker titles, soft solid panels, domed keys, a velvet wall", dark: true,
              card: .solid, radius: 1.5, space: 1.2, tile: "circle", look: "fuzzy", wall: "code|velvet",
              tint: 0.25, through: 0.25, mark: "love-yourself"),
        .init(id: "forest", title: "Forest room", palette: "th-forest", face: house("grenze-gotisch.ttf"), text: house("xanh-mono.ttf"),
              note: "Gotisch titles, a serif mono, sharp frosted panes over contour lines", dark: true,
              card: .frosted, radius: 0.1, space: 1, tile: "squircle", look: "flat", wall: "code|contour",
              tint: 0.3, icons: "iconoir"),
        .init(id: "archive", title: "From the archive", palette: "th-archive", face: "file:fonts/PLRansom-Regular.ttf", text: house("veteran-typewriter.ttf"),
              note: "Your ledger scraps as titles, bare icons, gold labyrinth from your archive", dark: true,
              card: .outline, radius: 1.5, space: 0.85, tile: "circle", look: "bare", wall: "invert|" + art + "glyph-abstract_organic-labyrinthine_monochrome_ink_017.jpg",
              curves: 0.55, tint: 0, mark: "poverty-to-luxury"),
        .init(id: "drop", title: "Drop day", palette: "th-drop", face: "ransom", text: "jost",
              note: "Your Ransom titles on blush paper, solid sharp stamps, Drop day on the wall", dark: false,
              card: .solid, radius: 0.1, space: 0.85, tile: "square", look: "flat", wall: "color|" + art + "abstract-pattern_organic-interlocking_red-warm_digital_2437.png",
              curves: 0.2, tint: 0.5, through: 0.15, icon: "AppIcon-BoneOxblood", mark: "money"),
        .init(id: "ledger", title: "The ledger", palette: "th-ledger", face: "ledger", text: "courier",
              note: "Your Ledger hand on ledger paper, typewriter keys, ruled outlines, still", dark: false,
              card: .outline, radius: 0.5, space: 1, tile: "circle", look: "typewriter", wall: "invert|" + art + "abstract-pattern_organic-interlocking_monochrome_digital-ink_5373.png",
              calm: true, curves: 0.05, tint: 0),
        .init(id: "linen", title: "Linen", palette: "th-linen", face: "v2", text: "jost",
              note: "Your second hand on sage cloth, clear glass bubbles, airy", dark: false,
              card: .clear, radius: 1.5, space: 1.2, tile: "circle", look: "bubble", wall: "code|weave",
              tint: 0.2, through: 0.75, icons: "iconoir"),
        .init(id: "copper", title: "Copper", palette: "th-copper", face: house("saira-stencil-one.ttf"), text: house("dirty-enough.ttf"),
              note: "Stencil over worn type, solid bevelled plates, Copper as you made it", dark: false,
              card: .solid, radius: 1, space: 1, tile: "squircle", look: "clay", wall: "color|" + art + "abstract-pattern_organic-flowing_warm-pink_digital_4693.png",
              curves: 0.15, tint: 0.35, through: 0.2),
        .init(id: "smoke", title: "Warm smoke", palette: "th-smoke", face: house("pencilant.otf"), text: house("special-elite.ttf"),
              note: "Pencil titles, typed text, round soft outlines on smoke, still", dark: false,
              card: .outline, radius: 1.5, space: 1.2, tile: "circle", look: "flat", wall: "code|smoke",
              calm: true, tint: 0.15),
        .init(id: "pearl", title: "Pearl", palette: "th-pearl", face: house("fruktur.ttf"), text: house("germania-one.ttf"),
              note: "Fruktur over Germania, pearl bubbles, a slow lilac sheen", dark: false,
              card: .clear, radius: 1, space: 1, tile: "squircle", look: "glaze", wall: "code|pearl",
              tint: 0.35, through: 0.65),

        // Fun (his list and references 11-24). Genre looks only: no maker's logo, icons or menu art.
        .init(id: "fun-macos", title: "Mac OS", palette: "th-macos", face: "bundle:system", text: "system",
              note: "The platinum era: grey square windows, raised buttons, blue bars, a teal wave desktop, still", dark: false,
              card: .solid, radius: 0.1, space: 1, tile: "square", look: "bevel", wall: "code|waves",
              calm: true, tint: 0, through: 0, icons: "pixel", fun: true),
        .init(id: "fun-linux", title: "Linux", palette: "th-linux", face: "bundle:Ubuntu-Bold", text: "bundle:Ubuntu-Regular",
              note: "The netbook look: dark brown frosted panels, orange bubble keys, the Ubuntu font", dark: true,
              card: .frosted, radius: 1, space: 1.1, tile: "squircle", look: "bubble", wall: "code|ubuntu",
              tint: 0.35, through: 0.35, icons: "tabler", fun: true),
        .init(id: "fun-glass", title: "Glass", palette: "th-glass", face: "bundle:Michroma-Regular", text: "system",
              note: "Liquid Glass at its fullest: clear and airy over aero light", dark: true,
              card: .clear, radius: 1.5, space: 1.2, tile: "squircle", look: "glass", wall: "code|aero",
              tint: 0.15, through: 0.9, icons: "sf", fun: true),
        .init(id: "fun-eink", title: "E ink", palette: "th-eink", face: "bundle:Literata-Regular", text: "bundle:Literata-Regular",
              note: "Paper and ink: a book face, flat square panels, no curves, no motion", dark: false,
              card: .solid, radius: 0.1, space: 1.1, tile: "square", look: "flat", wall: "code|paper",
              calm: true, curves: 0, tint: 0, through: 0, icons: "iconoir", fun: true),
        .init(id: "fun-synthwave", title: "Synthwave", palette: "th-synthwave", face: "bundle:MrDafoe-Regular", text: "jost",
              note: "Pink script titles, neon rings, a sunset over the grid floor", dark: true,
              card: .outline, radius: 1, space: 1, tile: "circle", look: "neon", wall: "code|synth",
              curves: 0.8, tint: 0.2, through: 0.45, icons: "sf", fun: true, titleFX: "chrome"),
        .init(id: "fun-cyberpunk", title: "Cyberpunk", palette: "th-cyberpunk", face: "bundle:ChakraPetch-SemiBold", text: "bundle:GeistMono-Regular",
              note: "Night city OS: coral hairline frames, teal, scanlines on violet-black", dark: true,
              card: .outline, radius: 0.5, space: 0.85, tile: "notch", look: "terminal", wall: "code|night",
              tint: 0.1, through: 0.3, icons: "tabler", fun: true, titleFX: "glow"),
        .init(id: "fun-retro", title: "Retro 90s", palette: "th-retro", face: "bundle:PixelifySans-Regular", text: "jost",
              note: "Vaporwave windows: raised pink panels on a lavender grid, pixel titles", dark: false,
              card: .solid, radius: 0.5, space: 1, tile: "square", look: "bevel", wall: "code|vapor",
              tint: 0.2, through: 0.1, icons: "pixel", fun: true),
        .init(id: "fun-hyperspace", title: "Hyperspace", palette: "th-hyperspace", face: "bundle:Audiowide-Regular", text: "jost",
              note: "Violet and cyan in deep space, frosted domes, the tunnel behind", dark: true,
              card: .frosted, radius: 1.5, space: 1.2, tile: "circle", look: "dome", wall: "invert|" + art + "abstract-pattern_organic-flowing_monochrome_digital_5457.png",
              curves: 0.8, tint: 0.4, through: 0.6, fun: true, titleFX: "glow"),
        .init(id: "fun-vibe", title: "Vibe coded", palette: "th-vibe", face: "bundle:JetBrainsMono-Regular", text: "bundle:JetBrainsMono-Regular",
              note: "Editor night: acid green on black, terminal keys, code lines on the wall", dark: true,
              card: .outline, radius: 0.1, space: 0.85, tile: "square", look: "terminal", wall: "code|editor",
              tint: 0, through: 0.2, icons: "pixel", fun: true, titleFX: "glow"),
    ]

    /// The wallpaper this theme wears: his own choice for it when he made one, else the theme's.
    var chosenWall: String { UserDefaults.standard.string(forKey: "pldev.wall." + id) ?? wall }

    /// Fetches the theme's house fonts (first time only), then sets every switch it owns; the views read the same keys.
    /// Returns false when a font could not be fetched (offline, never cached): the rest still applies, titles fall back to his V1.
    @MainActor func apply() async -> Bool {
        let titleOK = await HouseFonts.ensure(face)
        let textOK = await HouseFonts.ensure(text)
        let kit = HouseKit.shared, d = UserDefaults.standard
        d.set(id, forKey: "pldev.themeId")
        d.set(radius, forKey: "pldev.styleRadius"); d.set(space, forKey: "pldev.styleSpace")
        d.set(tile, forKey: "pldev.styleTile"); d.set(look, forKey: "pldev.styleLook"); d.set(icons, forKey: "pldev.styleIcons")
        d.set(mark ?? "", forKey: "pldev.styleMark"); d.set(repeatSize, forKey: "pldev.styleRepeat")
        d.set(titleFX, forKey: "pldev.styleTitleFX")
        resetGlass()
        d.set(chosenWall, forKey: "pldev.styleWall")
        d.set(curves, forKey: "pldev.tileStrength"); d.set(calm ? "reduce" : "full", forKey: "pldev.motion")
        d.set(textOK ? text : "jost", forKey: "pldev.font")
        d.set(dark ? "dark" : "light", forKey: "pldev.theme")
        kit.paletteName = palette; kit.titleFace = face   // last: their didSet re-applies the bars with everything above in place
        PLCarry.epoch.n += 1   // fonts and shapes changed even when the colours did not
        if let icon, UIApplication.shared.alternateIconName != icon { UIApplication.shared.setAlternateIconName(icon, completionHandler: nil) }
        return titleOK && textOK
    }

    /// The theme's own glass: cards and Home tiles.
    func resetGlass() {
        let d = UserDefaults.standard
        d.set(card.rawValue, forKey: "pldev.glass.card.style"); d.set(tint, forKey: "pldev.glass.card.tint"); d.set(through, forKey: "pldev.glass.card.through")
        let tileStyle: Card = look == "neon" || look == "terminal" || look == "bare" ? .outline : card
        d.set(tileStyle.rawValue, forKey: "pldev.glass.tile.style"); d.set(max(tint, 0.45), forKey: "pldev.glass.tile.tint"); d.set(through, forKey: "pldev.glass.tile.through")
    }

    static var current: PLThemePreset? {
        let id = UserDefaults.standard.string(forKey: "pldev.themeId")
        return all.first { $0.id == id }
    }
}

// MARK: - The faces

/// Every face in the Design Kit (kit.json → fonts) plus the open faces bundled in the app, for the face pickers.
enum KitFaces {
    private static func h(_ name: String, _ file: String) -> (String, String) { (name, "file:fonts/house/" + file) }
    static let his: [(String, String)] = [("Your hand (V1)", "v1"), ("Your hand (V2)", "v2"), ("Ransom", "ransom"), ("Ledger", "ledger"),
                                          ("Ransom scraps", "file:fonts/PLRansom-Regular.ttf"), ("Curved ABC", "file:fonts/Curvedabc-Regular.ttf")]
    static let house: [(String, String)] = [
        h("Pirata One", "pirata-one.ttf"), h("UnifrakturCook", "unifrakturcook.ttf"), h("Grenze Gotisch", "grenze-gotisch.ttf"), h("New Rocker", "new-rocker.ttf"),
        h("Texturina", "texturina.ttf"), h("Fruktur", "fruktur.ttf"), h("Germania One", "germania-one.ttf"), h("Jacquard 24", "jacquard-24.ttf"),
        h("MedievalSharp", "medievalsharp.ttf"), h("Special Elite", "special-elite.ttf"), h("Veteran Typewriter", "veteran-typewriter.ttf"),
        h("Cutive Mono", "cutive-mono.ttf"), h("Courier Prime", "courier-prime.ttf"), h("Syne Mono", "syne-mono.ttf"), h("Xanh Mono", "xanh-mono.ttf"),
        h("Major Mono Display", "major-mono-display.ttf"), h("VT323", "vt323.ttf"), h("Dirty Enough", "dirty-enough.ttf"), h("Capture It", "capture-it.ttf"),
        h("Rubik Dirt", "rubik-dirt.ttf"), h("Rubik Distressed", "rubik-distressed.ttf"), h("Rubik Burned", "rubik-burned.ttf"),
        h("Rubik Wet Paint", "rubik-wet-paint.ttf"), h("Nosifer", "nosifer.ttf"), h("Punk Kid", "punk-kid.ttf"), h("JoGrunge", "jogrunge.otf"),
        h("Beyond Wonderland", "beyond-wonderland.ttf"), h("Pencilant", "pencilant.otf"), h("Saira Stencil One", "saira-stencil-one.ttf"),
        h("Big Shoulders Stencil", "big-shoulders-stencil.ttf")]
    static let bundled: [(String, String)] = [("System", "system"), ("Jost", "jost"), ("Courier Prime", "courier"), ("Literata", "bundle:Literata-Regular"),
        ("Ubuntu", "bundle:Ubuntu-Regular"), ("JetBrains Mono", "bundle:JetBrainsMono-Regular"), ("Geist Mono", "bundle:GeistMono-Regular"),
        ("Chakra Petch", "bundle:ChakraPetch-SemiBold"), ("Pixelify Sans", "bundle:PixelifySans-Regular"), ("Audiowide", "bundle:Audiowide-Regular"),
        ("Michroma", "bundle:Michroma-Regular"), ("Mr Dafoe", "bundle:MrDafoe-Regular")]
}

// MARK: - The ground

/// The wallpaper under every screen: the palette's ground, then the theme's wall (or the one he picked for it). `quiet` is the
/// strength behind a section's text; Home shows it in full.
struct ThemeGround: View {
    var spec: String? = nil   // nil = the live setting; the pickers pass their own to preview it
    var quiet = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduce
    @State private var kit = HouseKit.shared
    @AppStorage("pldev.styleWall") private var wall = ""
    @AppStorage("pldev.tileStrength") private var strength = 0.5
    @AppStorage("pldev.styleRepeat") private var repeatSize = 300.0
    @State private var tile: UIImage?

    init(spec: String? = nil, quiet: Bool = true) {
        self.spec = spec
        self.quiet = quiet
    }

    var body: some View {
        let p = kit.palette
        let ground = PLCarry.tone(.ground, scheme, p.groundColor)
        let plain = !PLStyle.themed && quiet   // no theme worn: the section ground as it was (light = Apple's grey, washed)
        let ink = plain ? (scheme == .dark ? p.textColor : p.groundColor) : p.keyColor
        // a screen pinned to the other appearance (the practice is dark only) takes the deep ground and only a trace of the art
        let clash = !plain && (TileLook.luminance(p.groundColor) > 0.5) == (scheme == .dark)
        let parts = (spec ?? wall).split(separator: "|", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "curves", arg = parts.count == 2 ? parts[1] : ""
        // Color.clear takes exactly the offered size, so a filled picture cannot stretch the screen or catch a neighbour's tap
        Color.clear.overlay {
            ZStack {
                if plain && scheme == .light { Color(uiColor: .systemGroupedBackground); p.textColor.opacity(0.45) } else { ground }
                if !reduce {
                    Group {
                        switch kind {
                        case "code": CodeGround(name: arg, key: p.keyColor, accent: p.accentColor, ink: p.textColor, ground: p.groundColor)
                        case "mask", "invert", "color": ThemeWall(spec: kind + "|" + arg, key: ink, strength: strength)
                        case "kit":
                            if let tile {
                                Image(uiImage: tile).renderingMode(.template).resizable(resizingMode: .tile).foregroundStyle(ink).opacity(min(1, 0.1 + strength))
                            }
                        default:
                            if let s = Wallpaper.stencil {
                                Image(uiImage: s).renderingMode(.template).resizable(resizingMode: .tile).foregroundStyle(ink)
                                    .opacity(strength <= 0 ? 0 : min(1, 0.15 + strength * 1.7))
                            }
                        }
                    }
                    .opacity(clash ? 0.12 : quiet ? (kind == "code" ? 0.7 : 0.3) : 1)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: kind + arg + String(repeatSize)) { if kind == "kit" { tile = await KitPattern.load(arg, size: repeatSize) } }
    }
}

/// A Design Kit pattern from the gallery's /kit, cached on the phone (none of his art ships in this public repo).
enum KitPattern {
    @MainActor static func load(_ path: String, size: Double) async -> UIImage? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let file = dir.appendingPathComponent("kit-" + (path as NSString).lastPathComponent)
        var data = try? Data(contentsOf: file)
        if data == nil, let http = AppModel.shared.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "kit/" + path), timeout: 40), UIImage(data: d) != nil {
            try? d.write(to: file)
            data = d
        }
        guard let data, let cg = UIImage(data: data)?.cgImage, size > 0 else { return nil }
        return UIImage(cgImage: cg, scale: CGFloat(cg.width) / CGFloat(size), orientation: .up).withRenderingMode(.alwaysTemplate)
    }
}

/// The grounds drawn in code (his references 11-24), in the palette's own colours.
struct CodeGround: View {
    static let names: [(String, String)] = [("synth", "Sunset and grid floor"), ("waves", "Desktop waves"), ("night", "Night scanlines"), ("ubuntu", "Warm glow"),
        ("bluedesk", "Blue retro desktop"), ("aero", "Aero light"), ("editor", "Code lines"), ("vapor", "Vapor grid"), ("paper", "Plain paper"),
        ("brushed", "Brushed steel"), ("velvet", "Velvet"), ("contour", "Contour lines"), ("weave", "Linen weave"), ("smoke", "Smoke"), ("pearl", "Pearl sheen")]
    let name: String, key: Color, accent: Color, ink: Color, ground: Color

    var body: some View {
        switch name {
        case "synth": canvas { c, s in synth(&c, s) }
        case "waves": canvas { c, s in
            for row in stride(from: 0.0, through: s.height, by: 18) { wave(&c, s, y: row, amp: 5, length: 46, color: .white.opacity(0.16), width: 6) } }
        case "night": ZStack {
            LinearGradient(colors: [ground, Color(hex: 0x3b1466), Color(hex: 0x6a1b6e)], startPoint: .top, endPoint: .bottom)
            canvas { c, s in lines(&c, s, every: 4, color: .black.opacity(0.28)); frame(&c, s) } }
        case "ubuntu": ZStack {
            RadialGradient(colors: [Color(hex: 0x7a3216), ground], center: .init(x: 0.5, y: 0.15), startRadius: 0, endRadius: 600)
            RadialGradient(colors: [key.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380) }
        case "bluedesk": ZStack {
            Color(hex: 0x0055aa)
            canvas { c, s in
                for i in 0..<4 {
                    let r = CGRect(x: 24 + Double(i % 2) * s.width * 0.36, y: 70 + Double(i) * s.height * 0.22, width: s.width * 0.52, height: s.height * 0.16)
                    c.stroke(Path(r), with: .color(.white.opacity(0.5)), lineWidth: 2)
                    c.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 16)), with: .color(.white.opacity(0.55)))
                    c.fill(Path(CGRect(x: r.maxX - 15, y: r.minY + 3, width: 10, height: 10)), with: .color(Color(hex: 0xff8800))) } } }
        case "aero": ZStack {
            LinearGradient(colors: [Color(hex: 0x0d4a78), ground], startPoint: .top, endPoint: .bottom)
            blob(key.opacity(0.65), 0.15, 0.2); blob(Color(hex: 0x5ee6b0).opacity(0.4), 0.95, 0.55); blob(.white.opacity(0.3), 0.55, 0.02); blob(Color(hex: 0x6a7fd4).opacity(0.6), 0.2, 0.9) }
        case "editor": canvas { c, s in
            var row = 0
            for y in stride(from: 20.0, to: s.height, by: 19) {
                let indent = Double((row * 7) % 4) * 16, w = 40 + Double((row * 53) % 190)
                c.fill(Path(CGRect(x: 8, y: y, width: 10, height: 3)), with: .color(ink.opacity(0.18)))
                c.fill(Path(CGRect(x: 34 + indent, y: y, width: min(w, s.width - 44 - indent), height: 3)), with: .color((row % 5 == 0 ? accent : key).opacity(0.22)))
                row += 1 } }
        case "vapor": ZStack {
            LinearGradient(colors: [ground, Color(hex: 0xf4b8e4), Color(hex: 0xfbe7a1)], startPoint: .top, endPoint: .bottom)
            canvas { c, s in grid(&c, s, every: 26, color: .white.opacity(0.55)) } }
        case "brushed": ZStack {
            LinearGradient(colors: [Color(hex: 0x2a2c33), ground, Color(hex: 0x23252b), ground], startPoint: .topLeading, endPoint: .bottomTrailing)
            canvas { c, s in
                for i in 0..<Int(s.height / 2) {
                    c.fill(Path(CGRect(x: 0, y: Double(i) * 2, width: s.width, height: 1)), with: .color(key.opacity(Double((i * 37) % 11) / 110))) } } }
        case "velvet": ZStack {
            RadialGradient(colors: [Color(hex: 0x8c2436), ground, Color(hex: 0x1c050a)], center: .top, startRadius: 0, endRadius: 760)
            canvas { c, s in for x in stride(from: 0.0, to: s.width, by: 34) { c.fill(Path(CGRect(x: x, y: 0, width: 14, height: s.height)), with: .color(.black.opacity(0.14))) } } }
        case "contour": canvas { c, s in
            for ring in 1..<22 {
                let r = Double(ring) * 26
                for centre in [CGPoint(x: s.width * 0.1, y: s.height * 0.2), CGPoint(x: s.width * 0.95, y: s.height * 0.8)] {
                    var p = Path()
                    for step in 0...72 {
                        let a = Double(step) / 72 * 2 * Double.pi, rr = r * (1 + 0.09 * sin(a * 3 + Double(ring) * 0.5))
                        let pt = CGPoint(x: centre.x + cos(a) * rr, y: centre.y + sin(a) * rr)
                        if step == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
                    c.stroke(p, with: .color(key.opacity(0.16)), lineWidth: 1) } } }
        case "weave": canvas { c, s in
            lines(&c, s, every: 5, color: key.opacity(0.1))
            for x in stride(from: 0.0, to: s.width, by: 5) { c.fill(Path(CGRect(x: x, y: 0, width: 1.5, height: s.height)), with: .color(.white.opacity(0.4))) } }
        case "smoke": ZStack { blob(.white.opacity(0.65), 0.2, 0.15); blob(ink.opacity(0.2), 0.9, 0.4); blob(.white.opacity(0.45), 0.35, 0.75); blob(key.opacity(0.18), 0.85, 0.95) }
        case "pearl": ZStack {
            AngularGradient(colors: [ground, Color(hex: 0xf6dfe8), Color(hex: 0xdcefee), Color(hex: 0xf3ecd2), ground], center: .init(x: 0.7, y: 0.3))
            blob(.white.opacity(0.7), 0.25, 0.65) }
        default: Color.clear
        }
    }

    private func canvas(_ draw: @escaping (inout GraphicsContext, CGSize) -> Void) -> some View {
        Canvas { c, s in draw(&c, s) }.drawingGroup()
    }
    private func blob(_ color: Color, _ x: Double, _ y: Double) -> some View {
        RadialGradient(colors: [color, .clear], center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: 340)
    }
    private func lines(_ c: inout GraphicsContext, _ s: CGSize, every: Double, color: Color) {
        for y in stride(from: 0.0, to: s.height, by: every) { c.fill(Path(CGRect(x: 0, y: y, width: s.width, height: 1.5)), with: .color(color)) }
    }
    private func grid(_ c: inout GraphicsContext, _ s: CGSize, every: Double, color: Color) {
        for y in stride(from: 0.0, to: s.height, by: every) { c.fill(Path(CGRect(x: 0, y: y, width: s.width, height: 1)), with: .color(color)) }
        for x in stride(from: 0.0, to: s.width, by: every) { c.fill(Path(CGRect(x: x, y: 0, width: 1, height: s.height)), with: .color(color)) }
    }
    private func wave(_ c: inout GraphicsContext, _ s: CGSize, y: Double, amp: Double, length: Double, color: Color, width: Double) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        for x in stride(from: 0.0, through: s.width, by: 4) { p.addLine(to: CGPoint(x: x, y: y + sin(x / length * 2 * Double.pi + y / 11) * amp)) }
        c.stroke(p, with: .color(color), lineWidth: width)
    }
    private func frame(_ c: inout GraphicsContext, _ s: CGSize) {
        var p = Path()
        p.move(to: CGPoint(x: 10, y: s.height * 0.12)); p.addLine(to: CGPoint(x: 10, y: s.height * 0.9)); p.addLine(to: CGPoint(x: 34, y: s.height * 0.93))
        p.addLine(to: CGPoint(x: s.width * 0.6, y: s.height * 0.93))
        c.stroke(p, with: .color(key.opacity(0.55)), lineWidth: 1.2)
        c.fill(Path(CGRect(x: s.width - 70, y: s.height * 0.1, width: 58, height: 4)), with: .color(accent.opacity(0.7)))
    }
    private func synth(_ c: inout GraphicsContext, _ s: CGSize) {
        let horizon = s.height * 0.62, r = s.width * 0.3
        c.fill(Path(CGRect(x: 0, y: 0, width: s.width, height: horizon)),
               with: .linearGradient(Gradient(colors: [ground, Color(hex: 0x4a0f52)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        let sun = CGRect(x: s.width / 2 - r, y: horizon - r * 1.7, width: r * 2, height: r * 2)
        c.fill(Path(ellipseIn: sun), with: .linearGradient(Gradient(colors: [Color(hex: 0xffd15c), key]), startPoint: CGPoint(x: 0, y: sun.minY), endPoint: CGPoint(x: 0, y: sun.maxY)))
        for i in 0..<6 { c.fill(Path(CGRect(x: sun.minX, y: sun.midY + Double(i) * r * 0.17, width: r * 2, height: 2 + Double(i))), with: .color(Color(hex: 0x4a0f52))) }
        c.fill(Path(CGRect(x: 0, y: horizon, width: s.width, height: s.height - horizon)), with: .color(ground))
        var floor = Path()
        var y = horizon, step = 4.0
        while y < s.height { floor.move(to: CGPoint(x: 0, y: y)); floor.addLine(to: CGPoint(x: s.width, y: y)); y += step; step *= 1.35 }
        for i in -8...8 { floor.move(to: CGPoint(x: s.width / 2 + Double(i) * 14, y: horizon)); floor.addLine(to: CGPoint(x: s.width / 2 + Double(i) * s.width * 0.19, y: s.height)) }
        c.stroke(floor, with: .color(accent.opacity(0.75)), lineWidth: 1.2)
    }
}

// MARK: - The tile look

/// What a theme draws over a tile's glass: the key, ring or frame that makes its Home Screen its own. Drawn in code (the Design
/// Kit's rendered keys carry one app's name baked in, so they cannot sit under every app).
struct TileLook: View {
    let look: String, shape: AnyShape, key: Color, accent: Color

    var body: some View {
        ZStack {
            switch look {
            case "typewriter":
                Circle().strokeBorder(LinearGradient(colors: [.white, Color(white: 0.45), .white, Color(white: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 6)
                Circle().inset(by: 6).fill(Color(white: 0.12).opacity(0.92))
            case "keycap":
                shape.fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
                shape.fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.42)], startPoint: .top, endPoint: .bottom)).padding(.horizontal, 7).padding(.top, 4).padding(.bottom, 11)
            case "bubble":
                shape.fill(LinearGradient(colors: [key.opacity(0.85), key], startPoint: .top, endPoint: .bottom))
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)).frame(width: 44, height: 22).offset(y: -17)
            case "dome":
                shape.fill(RadialGradient(colors: [accent, key, key.mix(with: .black, by: 0.55)], center: .init(x: 0.35, y: 0.28), startRadius: 0, endRadius: 60))
            case "terminal":
                shape.fill(Color.black.opacity(0.65))
                shape.stroke(key.opacity(0.9), lineWidth: 1.5)
                Text("_").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(key).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(5)
            case "neon":
                shape.stroke(key, lineWidth: 2).shadow(color: key, radius: 7)
                shape.stroke(accent.opacity(0.7), lineWidth: 0.8).padding(4)
            case "bevel":
                shape.fill(Color(white: 0.84))
                Rectangle().strokeBorder(Color(white: 0.5), lineWidth: 3).clipShape(shape)
                Rectangle().strokeBorder(Color.white, lineWidth: 3).padding(.trailing, 3).padding(.bottom, 3).clipShape(shape)
                shape.stroke(Color(white: 0.04), lineWidth: 1)
                shape.fill(key.opacity(0.22))
            case "chrome":
                shape.fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.55), Color(white: 0.9), Color(white: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.stroke(Color.white.opacity(0.8), lineWidth: 1).padding(2)
            case "glaze":
                shape.fill(LinearGradient(colors: [accent.opacity(0.9), key], startPoint: .top, endPoint: .bottom))
                Ellipse().fill(Color.white.opacity(0.55)).frame(width: 30, height: 12).offset(x: -8, y: -18).blur(radius: 1.5)
            case "clay":
                shape.fill(key.mix(with: .white, by: 0.12))
                shape.stroke(key.mix(with: .black, by: 0.35), lineWidth: 3)
            case "fuzzy":
                shape.fill(RadialGradient(colors: [accent.opacity(0.9), key], center: .center, startRadius: 2, endRadius: 40)).blur(radius: 1.2)
                shape.stroke(accent.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 3.5]))
            case "flat":
                shape.fill(key)
            default:
                Color.clear
            }
        }
        .frame(width: 64, height: 64)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The glyph's colour on that look.
    static func glyph(_ look: String, key: Color, scheme: ColorScheme) -> Color {
        switch look {
        case "terminal", "neon", "bare": return key
        case "bevel", "chrome": return Color(white: 0.08)
        case "flat": return luminance(key) > 0.55 ? .black : .white
        case "glass": return scheme == .dark ? Color(red: 1, green: 0.95, blue: 0.9) : Color.primary
        default: return .white
        }
    }

    static func luminance(_ c: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}
