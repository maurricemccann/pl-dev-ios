import SwiftUI
import UIKit

// THE THEME CARRY (his note 11-14: "Theme packs should change the whole thing, not just the Home Screen").
//
// A theme pack or a colourway sets HouseKit's palette and title face. Until now only the Home ground, PLTone.accent and a few views read
// it, while every section's skin (HouseSkin, SiteSkin, GallerySkin, PracticeSkin, ComposerSkin, TownSkin, CurateSkin) drew fixed colours.
// Each skin now asks this one place for its grounds, cards, lines, text and accent, by ROLE. With no pack chosen (the default Home Screen
// palette and no theme.json) `tone` hands back the skin's own colour untouched, so every section looks exactly as it did. With a pack
// chosen, the roles come from the palette: its dark member is the dark ground and the light ink, its light member the light ground and the
// dark ink, and its key is the accent. Each section keeps its layout, type and character; only the colour carries.
//
// The state is a plain value written on the main actor by HouseKit.apply() and read from anywhere (skins are nonisolated).

struct CarrySnapshot: Equatable, Sendable {
    var active = false
    /// The palette's dark and light members as 0xRRGGBB (a dark palette: ground is deep; a light palette: ground is pale).
    var deep: UInt32 = 0x0e0c08, pale: UInt32 = 0xefe9dc
    var key: UInt32 = 0xc9a84c
    var accent: UInt32 = 0xe7cf86
}

enum CarryRole {
    case ground       // behind everything
    case surface      // a card on the ground
    case surface2     // a card on a card, a row
    case well         // sunk below the ground: a field, a tray
    case ink          // the main text
    case dim          // secondary text
    case faint        // tertiary text
    case line         // a hairline (the accent, low)
    case accent       // the one accent: gold in the house skins
    case accentDim    // the accent where it must sit quieter on a ground (light mode gold)
    case accentHi     // the accent at its brightest: a highlight
}

/// Bumped whenever the carry changes. Every `tone` call reads it, so a view that drew a skin colour redraws when the pack changes
/// (the palette can arrive after a section has opened: the first run fetches it from the Design Kit).
@Observable final class CarryEpoch: @unchecked Sendable { var n = 0 }

enum PLCarry {
    nonisolated(unsafe) static var snap = CarrySnapshot()
    static let epoch = CarryEpoch()

    private static func rgb(_ h: UInt32) -> (Double, Double, Double) { (Double((h >> 16) & 0xff) / 255, Double((h >> 8) & 0xff) / 255, Double(h & 0xff) / 255) }
    private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
    private static func color(_ c: (Double, Double, Double), _ a: Double = 1) -> Color { Color(red: c.0, green: c.1, blue: c.2).opacity(a) }

    /// The skin's colour for a role. Untouched (the skin's own) unless a pack is chosen.
    static func tone(_ role: CarryRole, _ scheme: ColorScheme, _ orig: Color, alpha: Double = 1) -> Color {
        _ = epoch.n   // registers the view that is drawing with the carry, so it redraws when the pack changes
        let s = snap
        guard s.active else { return orig }
        let dark = scheme == .dark
        let g = rgb(dark ? s.deep : s.pale), t = rgb(dark ? s.pale : s.deep), key = rgb(s.key)
        switch role {
        case .ground: return color(g, alpha)
        case .surface: return color(mix(g, t, dark ? 0.07 : 0.045), alpha)
        case .surface2: return color(mix(g, t, dark ? 0.11 : 0.08), alpha)
        case .well: return color(dark ? mix(g, (0, 0, 0), 0.30) : mix(g, t, 0.03), alpha)
        case .ink: return color(t, alpha)
        case .dim: return color(mix(t, g, 0.30), alpha)
        case .faint: return color(mix(t, g, 0.48), alpha)
        case .line: return color(key, alpha * (dark ? 0.22 : 0.28))
        case .accent: return color(key, alpha)
        case .accentDim: return color(dark ? mix(key, g, 0.16) : mix(key, t, 0.30), alpha)
        case .accentHi: return color(mix(key, (1, 1, 1), 0.55), alpha)
        }
    }

    /// A step between the ground and the ink (0 = ground, 1 = ink): the field lines and rules of a skin.
    static func blend(_ amount: Double, _ scheme: ColorScheme, _ orig: Color) -> Color {
        _ = epoch.n
        let s = snap
        guard s.active else { return orig }
        let dark = scheme == .dark
        return color(mix(rgb(dark ? s.deep : s.pale), rgb(dark ? s.pale : s.deep), amount))
    }

    /// The palette's ground as a UIKit colour that follows light and dark, for the bars and the window behind every push.
    static func uiGround(fallback: UIColor) -> UIColor {
        UIColor { trait in
            let s = PLCarry.snap
            guard s.active else { return fallback }
            let h = trait.userInterfaceStyle == .dark ? s.deep : s.pale
            let c = PLCarry.rgb(h)
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }
    static func uiInk(fallback: UIColor) -> UIColor {
        UIColor { trait in
            let s = PLCarry.snap
            guard s.active else { return fallback }
            let h = trait.userInterfaceStyle == .dark ? s.pale : s.deep
            let c = PLCarry.rgb(h)
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    // MARK: building the snapshot from the chosen palette

    @MainActor static func update(palette p: HousePalette, packAccent: Color?, defaultPalette: Bool, packLoaded: Bool) {
        let g = hexValue(p.ground), t = hexValue(p.text)
        let groundIsLight = luminance(g) > 0.5
        var next = CarrySnapshot()
        next.active = !defaultPalette || packLoaded
        next.deep = groundIsLight ? t : g
        next.pale = groundIsLight ? g : t
        next.key = hexValue(p.key)
        next.accent = hexValue(p.accent)
        if let packAccent, let h = Self.hex(of: packAccent) { next.key = h }   // a theme.json accent wins, as it does for PLTone.accent
        if next != snap { snap = next; epoch.n += 1 }
    }

    private static func hexValue(_ s: String) -> UInt32 {
        var t = s.trimmingCharacters(in: .whitespaces); if t.hasPrefix("#") { t.removeFirst() }
        return UInt32(t.prefix(6), radix: 16) ?? 0x888888
    }
    private static func luminance(_ h: UInt32) -> Double { let c = rgb(h); return 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
    private static func hex(of color: Color) -> UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }
}
