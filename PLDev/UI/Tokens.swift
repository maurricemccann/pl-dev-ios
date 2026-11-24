import SwiftUI
import UIKit
import CoreText

/// The spacing scale, in points. Use these, not loose numbers.
/// Scaled by the theme's spacing (S353·7b1e: compact 0.85, house 1, airy 1.2); tap targets never shrink (PLMetric.touch).
enum PLSpace {
    static var hair: CGFloat { 2 }
    static var tight: CGFloat { 4 * PLStyle.space }
    static var gap: CGFloat { 8 * PLStyle.space }
    static var snug: CGFloat { 10 * PLStyle.space }
    static var pad: CGFloat { 12 * PLStyle.space }
    static var margin: CGFloat { 16 * PLStyle.space }
    static var roomy: CGFloat { 20 * PLStyle.space }
    static var block: CGFloat { 36 * PLStyle.space }
}

/// Corner radii, always with the continuous curve. Scaled by the theme's shape (sharp 0.35, house 1, soft 1.35).
enum PLRadius {
    static var card: CGFloat { 28 * PLStyle.radius }
    static var sheet: CGFloat { 32 * PLStyle.radius }
    static var row: CGFloat { 14 * PLStyle.radius }
    static var list: CGFloat { 26 * PLStyle.radius }
}

/// The theme's shape and rhythm (his ask 11-24: "15 distinct themes, each with their own style and unique ui/ux"). Written by
/// PLThemePreset.apply(); read from anywhere. Unset keys mean the house defaults, so no theme = the app as it was.
enum PLStyle {
    static var radius: CGFloat { scale("pldev.styleRadius") }
    static var space: CGFloat { scale("pldev.styleSpace") }
    /// Home's app tiles: squircle, circle or square.
    static var tile: String { UserDefaults.standard.string(forKey: "pldev.styleTile") ?? "squircle" }
    /// True once a theme or a colourway is worn: section skins then take the theme's ground, cards and faces.
    static var themed: Bool { _ = PLCarry.epoch.n; return PLCarry.snap.active || UserDefaults.standard.string(forKey: "pldev.themeId") != nil }
    /// The card style when the Glass page has never been touched (the old "Glass controls off" switch still means solid).
    static var cardStyle: String {
        let d = UserDefaults.standard
        return d.string(forKey: "pldev.glass.card.style") ?? (d.object(forKey: "pldev.glassBlur") as? Bool == false ? "solid" : "frosted")
    }
    /// The chosen text face as a font name; nil = Apple's own.
    static var textFont: String? {
        _ = PLCarry.epoch.n   // a view that drew text redraws when the theme changes
        let face = UserDefaults.standard.string(forKey: "pldev.font") ?? "system"
        switch face {
        case "system": return nil
        case "jost": return "Jost-Book"
        case "courier": return "CourierPrime-Regular"
        case "v2": return PLFace.handV2
        default: let n = HouseFonts.name(face); return n == "system" ? nil : n
        }
    }
    /// The chosen title face as a font name, only once themed; nil = leave the screen's own.
    static var titleFont: String? {
        guard themed else { return nil }
        let face = UserDefaults.standard.string(forKey: "pldev.titleFace") ?? "v1"
        switch face {
        case "v1": return PLFace.handV1
        case "v2": return PLFace.handV2
        case "ransom": return PLFace.ransom
        case "ledger": return PLFace.ledger
        default: let n = HouseFonts.name(face); return n == "system" ? nil : n
        }
    }
    /// One repeat of the curve wallpaper, in points (his reference is 300).
    static var repeatSize: CGFloat { let v = UserDefaults.standard.double(forKey: "pldev.styleRepeat"); return v > 0 ? v : 300 }
    private static func scale(_ key: String) -> CGFloat { let v = UserDefaults.standard.double(forKey: key); return v > 0 ? v : 1 }
}

/// House fonts from the Design Kit on the gallery (kit.json → fonts), fetched the first time a theme names one, cached, and
/// registered for the process. A face token is "file:<gallery path>", e.g. "file:fonts/house/pirata-one.ttf".
enum HouseFonts {
    private static var dir: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("house/fonts", isDirectory: true) }
    private static func local(_ token: String) -> URL { dir.appendingPathComponent((token as NSString).lastPathComponent) }

    /// The PostScript name for a face token once its file is registered; nil for built-in faces or before it arrives.
    /// "bundle:<PostScript name>" is a font shipped in the app (the Fun themes' open fonts); "bundle:system" is Apple's own face
    /// (Font.custom and UIFont(name:) fall back to the system font for a name that is not installed).
    static func name(_ token: String) -> String? {
        if token.hasPrefix("bundle:") { return String(token.dropFirst(7)) }
        return token.hasPrefix("file:") ? UserDefaults.standard.string(forKey: "pldev.ps." + token) : nil
    }

    /// At launch: every font already cached is registered again (registration lasts one process).
    static func registerCached() {
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { register(url) }
    }

    /// Makes a face usable: fetched once from the gallery, then from the cache. False = offline and not cached yet.
    @MainActor static func ensure(_ token: String) async -> Bool {
        guard token.hasPrefix("file:") else { return true }
        let url = local(token)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let http = AppModel.shared.http,
                  let d = try? await http.send(RequestPlan(origin: "gallery", path: String(token.dropFirst(5))), timeout: 40), !d.isEmpty else { return false }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard (try? d.write(to: url)) != nil else { return false }
        }
        guard let ps = register(url) else { try? FileManager.default.removeItem(at: url); return false }   // not a font: drop it, fetch again next time
        UserDefaults.standard.set(ps, forKey: "pldev.ps." + token)
        return true
    }

    @discardableResult private static func register(_ url: URL) -> String? {
        guard let p = CGDataProvider(url: url as CFURL), let f = CGFont(p), let n = f.postScriptName as String? else { return nil }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)   // false only means it was already registered
        return n
    }
}

/// The theme's face wherever a screen asked for Apple's (S353·7b1e: "a lot of these themes looked the same" — the text face only
/// reached views that used plFont). Same arguments as Font.system; with no face chosen it IS Font.system.
extension Font {
    static func pl(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        guard let face = PLStyle.textFont else { return .system(size: size, weight: weight, design: design) }
        let f = Font.custom(face, fixedSize: face.contains("Mono") ? size * 0.92 : size)
        return weight.map { f.weight($0) } ?? f
    }

    static func pl(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        guard let face = PLStyle.textFont else { return .system(style, design: design, weight: weight) }
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline, .body: size = 17
        case .callout: size = 16
        case .subheadline: size = 15
        case .footnote: size = 13
        case .caption: size = 12
        default: size = 11
        }
        let f = Font.custom(face, size: face.contains("Mono") ? size * 0.92 : size, relativeTo: style)
        let w = weight ?? (style == .headline ? .semibold : nil)
        return w.map { f.weight($0) } ?? f
    }

    /// A screen's display line: the theme's title face once themed, else the font the screen already used.
    static func plDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .title, or fallback: Font) -> Font {
        PLStyle.titleFont.map { .custom($0, size: size, relativeTo: style) } ?? fallback
    }
}

enum PLMetric {
    static let touch: CGFloat = 44   // the smallest thing a finger is asked to hit
}

/// Neutral colour roles. All are Apple's system colours, so light, dark and Increase Contrast come for free.
/// The only colour a theme pack can change is the accent (and the tile wash that is mixed from it).
enum PLTone {
    static let canvas = Color(uiColor: .systemGroupedBackground)          // behind everything
    static let surface = Color(uiColor: .secondarySystemGroupedBackground) // a card or tile on the canvas
    static let plate = Color(uiColor: .systemFill)
    static let well = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)
    static let good = Color(uiColor: .systemGreen)
    static let bad = Color(uiColor: .systemRed)
    static let warn = Color(uiColor: .systemOrange)
    static let quiet = Color(uiColor: .systemGray)

    /// The tint for controls and marks: the theme pack's accent when one is loaded, else the asset catalog's.
    @MainActor static var accent: Color { ThemePack.shared.accent ?? HouseKit.shared.palette.keyColor }   // the PL remix: his palette, not Apple's blue

    /// The wash on a home tile: the pack's "tile" colour, else the accent.
    @MainActor static var tileWash: Color { ThemePack.shared.colors["tile"] ?? accent }
}

/// Good, warn, bad: one shared tint for a number whose meaning is known (his note 11-14 on the PC tiles: "the number and percent
/// that's green to be green when good and red when bad, and so should most of any information: a slight red tint when it is bad,
/// a slight green tint when it is good"). The value takes the full tone, its tile a faint wash of it and the name a slight hint
/// of it. A number whose good and bad are not known is passed as nil and wears no tint at all: never guess a threshold.
enum PLStatus: Equatable {
    case good, warn, bad

    var tone: Color { switch self { case .good: return PLTone.good; case .warn: return PLTone.warn; case .bad: return PLTone.bad } }

    /// A reading where a LOWER number is worse (free RAM, free disk): under `bad` is red, under `warn` is amber.
    static func lowerIsWorse(_ v: Double, warn: Double, bad: Double) -> PLStatus { v < bad ? .bad : v < warn ? .warn : .good }
    /// A reading where a HIGHER number is worse (heat, load, kernel pool): from `bad` is red, from `warn` is amber.
    static func higherIsWorse(_ v: Double, warn: Double, bad: Double) -> PLStatus { v >= bad ? .bad : v >= warn ? .warn : .good }
    /// A count of things waiting: none is good; any is `whenAny` (amber for "waiting on a tap", red for "owed").
    static func waiting(_ n: Int, whenAny: PLStatus = .warn) -> PLStatus { n <= 0 ? .good : whenAny }
}

extension View {
    /// The value text of a number in its tone (full strength), or untouched when no level is known.
    func plStatusValue(_ level: PLStatus?) -> some View { foregroundStyle(level?.tone ?? Color.primary) }
    /// The name of a number: secondary, with a slight hint of the tone.
    func plStatusName(_ level: PLStatus?) -> some View {
        foregroundStyle(level.map { Color(uiColor: .secondaryLabel).mix(with: $0.tone, by: 0.45) } ?? Color(uiColor: .secondaryLabel))
    }
    /// A tile for one number: a faint wash of its tone and a hairline of it. No level, no tile (the number sits as it did).
    func plStatusTile(_ level: PLStatus?, radius: CGFloat = PLRadius.row) -> some View {
        background {
            if let level {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(level.tone.opacity(0.13))
                    .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(level.tone.opacity(0.28), lineWidth: 0.7) }
            }
        }
    }
}
