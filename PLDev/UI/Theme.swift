import CoreText
import SwiftUI
import UIKit

/// Apple's text styles. The default face is the system font; Jost is bundled and can be picked in Settings.
/// Either way every style scales with Dynamic Type through AX5, and the Text size setting multiplies on top.
enum PLText {
    case largeTitle, title, title2, title3, headline, body, callout, subhead, footnote, caption, caption2

    /// Apple's own size for the style at the default Dynamic Type size.
    private var systemSize: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subhead: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        }
    }

    /// Jost draws small for its point size, so the text styles sit one point up.
    private var jostSize: CGFloat {
        switch self {
        case .largeTitle, .title, .title2, .title3: return systemSize
        default: return systemSize + 1
        }
    }

    private var style: Font.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subhead: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }

    private var uiStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subhead: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        }
    }

    private var weight: Int {
        switch self {
        case .largeTitle, .title, .title2, .title3: return 500
        case .headline: return 600
        default: return 400
        }
    }

    /// Emphasis adds 200 to the weight, the Bold Text setting adds 100; the heaviest Jost file bundled is 700.
    /// `scale` is the Text size setting as a factor (0.9 to 1.3).
    func font(face: String, scale: Double, bold: Bool, emphasized: Bool) -> Font {
        let w = min(700, weight + (emphasized ? 200 : 0) + (bold ? 100 : 0))
        if face == "courier" {   // Courier Prime, his R1 panel face (OFL); one weight file, so emphasis is synthesized bold
            let f = Font.custom("CourierPrime-Regular", size: jostSize * scale, relativeTo: style)
            return w >= 600 ? f.bold() : f
        }
        if let house = HouseFonts.name(face) {   // a theme's house font (one weight file), emphasis synthesized
            let f = Font.custom(house, size: jostSize * scale, relativeTo: style)
            return w >= 600 ? f.bold() : f
        }
        if face == "v2" { return .custom(PLFace.handV2, size: jostSize * scale, relativeTo: style) }
        if face == "jost" {
            let name = w >= 700 ? "Jost-Bold" : w >= 600 ? "Jost-Semi" : w >= 500 ? "Jost-Medium" : "Jost-Book"
            return .custom(name, size: jostSize * scale, relativeTo: style)
        }
        let systemWeight: Font.Weight = w >= 700 ? .bold : w >= 600 ? .semibold : w >= 500 ? .medium : .regular
        if scale == 1 { return .system(style, weight: systemWeight) }   // exactly Apple's own text style
        let size = UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: systemSize * scale)   // still follows Dynamic Type
        return .system(size: size, weight: systemWeight)
    }

    /// A title in the theme pack's own font file.
    func packFont(_ name: String, scale: Double) -> Font {
        .custom(name, size: systemSize * scale, relativeTo: style)
    }
}

private struct PLFontModifier: ViewModifier {
    let text: PLText
    let emphasized: Bool
    let isTitle: Bool
    @AppStorage("pldev.font") private var face = "system"
    @AppStorage("pldev.textSize") private var textSize = 100.0
    @AppStorage("pldev.styleText") private var styleText = 1.0   // the Daily look's size by band (0 = never set)
    @AppStorage("pldev.styleTitleFX") private var titleFX = ""
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize   // read so a Dynamic Type change redraws the scaled system size

    init(text: PLText, emphasized: Bool, isTitle: Bool) {
        self.text = text
        self.emphasized = emphasized
        self.isTitle = isTitle
    }

    func body(content: Content) -> some View {
        let _ = dynamicTypeSize
        let scale = min(1.3, max(0.9, textSize / 100 * (styleText > 0 ? styleText : 1)))
        Group {
            if isTitle, let pack = ThemePack.shared.titleFont {
                content.font(text.packFont(pack, scale: scale))
            } else if isTitle, let title = PLStyle.titleFont {
                content.font(text.packFont(title, scale: scale))
            } else {
                content.font(text.font(face: face, scale: scale, bold: legibilityWeight == .bold, emphasized: emphasized))
            }
        }
        .modifier(TitleFX(active: isTitle, fx: titleFX))
    }
}

private struct GlassControl<S: Shape>: ViewModifier {
    let tint: Color?
    let shape: S
    @AppStorage("pldev.glass.card.style") private var style = ""

    init(tint: Color?, shape: S) {
        self.tint = tint
        self.shape = shape
    }

    func body(content: Content) -> some View {
        let s = style.isEmpty ? PLStyle.cardStyle : style
        if s == "frosted" || s == "clear" {
            content.glassEffect((s == "clear" ? Glass.clear : Glass.regular).tint(tint).interactive(), in: shape)
        } else {
            content.background(tint ?? PLTone.plate, in: shape)
        }
    }
}

/// Every glass surface (cards, tiles, bars, pills) reads the Glass page: style, tint and see-through, with Home tiles set apart
/// from cards (his ruling 11-24: "the full panel").
struct PLSurface<S: Shape>: ViewModifier {
    enum Part: String { case card, tile }
    let part: Part
    let tint: Color?
    let interactive: Bool
    let shape: S
    @AppStorage private var style: String
    @AppStorage private var amount: Double
    @AppStorage private var through: Double
    @AppStorage("pldev.styleTile") private var tile = "squircle"   // one shape per theme: notched tiles notch every surface (his 11-24)
    @AppStorage("pldev.styleLook") private var look = "glass"
    @AppStorage("pldev.themeId") private var themeId = ""
    @AppStorage("pldev.styleEdge") private var edge = ""
    @Environment(\.colorScheme) private var scheme

    init(part: Part, tint: Color?, interactive: Bool, shape: S) {
        self.part = part
        self.tint = tint
        self.interactive = interactive
        self.shape = shape
        _style = AppStorage(wrappedValue: PLStyle.cardStyle, "pldev.glass.\(part.rawValue).style")
        _amount = AppStorage(wrappedValue: part == .tile ? 0.45 : 0, "pldev.glass.\(part.rawValue).tint")
        _through = AppStorage(wrappedValue: 0.5, "pldev.glass.\(part.rawValue).through")
    }

    func body(content: Content) -> some View {
        let shape: AnyShape = tile == "notch" ? AnyShape(NotchShape(cut: 12)) : AnyShape(self.shape)
        let surface = PLCarry.tone(.surface, scheme, Color(uiColor: .secondarySystemGroupedBackground))
        styled(content, shape: shape, surface: surface)
            .modifier(CardEdge(on: part == .card, look: look, theme: edge.isEmpty ? themeId : edge, shape: shape, key: PLTone.accent, surface: surface))
    }

    @ViewBuilder private func styled(_ content: Content, shape: AnyShape, surface: Color) -> some View {
        let key = PLTone.accent
        let wash: Color? = tint ?? (amount > 0 ? key.opacity(amount * 0.6) : nil)
        // see-through 0.5 and no tint = Apple's glass as it was; lower lays the card colour behind it
        let backing = max(0, 0.5 - through) * 1.8
        switch style {
        case "clear":
            content.glassEffect(Glass.clear.tint(wash).interactive(interactive), in: shape).background(surface.opacity(backing), in: shape)
        case "solid":
            content.background(wash ?? .clear, in: shape).background(surface.opacity(1 - through * 0.6), in: shape)
        case "outline":
            content.background(wash?.opacity(0.5) ?? .clear, in: shape).background(surface.opacity((1 - through) * 0.8), in: shape)
                .overlay(shape.stroke(key.opacity(0.85), lineWidth: 1).allowsHitTesting(false))
        default:
            content.glassEffect(Glass.regular.tint(wash).interactive(interactive), in: shape).background(surface.opacity(backing), in: shape)
        }
    }
}

private struct PackEdge: ViewModifier {
    let theme: String, shape: AnyShape, key: Color, surface: Color

    func body(content: Content) -> some View {
        if theme == "pack-stitched" {   // stitching just inside the leather
            content.overlay(shape.stroke(key.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).padding(5).allowsHitTesting(false))
                .background { shape.fill(surface).shadow(color: .black.opacity(0.4), radius: 5, y: 4) }
        } else if theme == "pack-386" {        // DOS double line
            content.overlay(shape.stroke(Color.white, lineWidth: 1.5).allowsHitTesting(false))
                .overlay(shape.stroke(Color.white, lineWidth: 1).padding(4).allowsHitTesting(false))
        } else if theme == "pack-quest" {      // a wood frame with a gold inner line
            content.overlay(shape.stroke(Color(red: 107 / 255, green: 74 / 255, blue: 36 / 255), lineWidth: 5).allowsHitTesting(false))
                .overlay(shape.stroke(key, lineWidth: 1.2).padding(4).allowsHitTesting(false))
        } else if theme == "pack-elite" {      // light caught on the top edge
            content.overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.06)], startPoint: .top, endPoint: .center), lineWidth: 1).allowsHitTesting(false))
        } else {
            content
        }
    }
}

/// A card's edge in its theme, with the values of North-Abyss/ui-themes (MIT, Licences.swift); CSS blur halves to a SwiftUI radius.
private struct CardEdge: ViewModifier {
    let on: Bool, look: String, theme: String, shape: AnyShape, key: Color, surface: Color

    func body(content: Content) -> some View {
        if !on {
            content
        } else if theme.hasPrefix("pack-") {   // a pack's cards never borrow another look's edge
            content.modifier(PackEdge(theme: theme, shape: shape, key: key, surface: surface))
        } else if look == "brutal" {        // Neo-Brutalism: border 2.5px solid #000, shadow 4px 4px 0 #000
            content.background { shape.fill(Color.black).offset(x: 4, y: 4) }
                .overlay(shape.stroke(Color.black, lineWidth: 2.5).allowsHitTesting(false))
        } else if look == "neu" {           // Neumorphism: 8px 8px 16px dark, -8px -8px 16px light
            content.background {
                shape.fill(surface)
                    .shadow(color: surface.mix(with: .black, by: 0.15), radius: 8, x: 8, y: 8)
                    .shadow(color: surface.mix(with: .white, by: 0.7), radius: 8, x: -8, y: -8)
            }
        } else if look == "neon" {          // Vaporwave / Cyberpunk: glow 0 0 20px at 0.35
            content.background { shape.stroke(key.opacity(0.6), lineWidth: 1).shadow(color: key.opacity(0.35), radius: 10) }
        } else if look == "terminal" {      // Phosphor terminal: border 1px, glow 0 0 10px at 0.2
            content.background { shape.stroke(key, lineWidth: 1).shadow(color: key.opacity(0.2), radius: 5) }
        } else if look == "clay" {          // Claymorphism: 16px 16px 32px at 0.22
            content.background { shape.fill(surface).shadow(color: key.opacity(0.22), radius: 16, x: 16, y: 16) }
        } else if look == "skeuo" {         // Skeuomorphism: border 1px .15, shadow 0 4px 12px .12 + 0 1px 3px .08, inset top white .9
            content.background { shape.fill(surface).shadow(color: .black.opacity(0.12), radius: 6, y: 4).shadow(color: .black.opacity(0.08), radius: 1.5, y: 1) }
                .overlay(shape.stroke(Color.black.opacity(0.15), lineWidth: 1).allowsHitTesting(false))
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.9), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.15)), lineWidth: 1).allowsHitTesting(false))
        } else if look == "aurora" {        // Aurora: border 1px white .18, shadow 0 12px 36px violet .22, inset top white .3
            content.background { shape.stroke(Color.white.opacity(0.01)).shadow(color: key.opacity(0.22), radius: 18, y: 12) }
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1).allowsHitTesting(false))
        } else if look == "paper" {         // Papercraft: border 1px #E5E0D5, shadow 0 4px 12px .08 + 0 1px 3px .06
            let ink = Color(red: 43 / 255, green: 38 / 255, blue: 32 / 255)
            content.background { shape.fill(surface).shadow(color: ink.opacity(0.08), radius: 6, y: 4).shadow(color: ink.opacity(0.06), radius: 1.5, y: 1) }
                .overlay(shape.stroke(Color(red: 229 / 255, green: 224 / 255, blue: 213 / 255), lineWidth: 1).allowsHitTesting(false))
        } else if theme == "fun-swiss" {    // Swiss: border 1px solid #000, no shadow
            content.overlay(shape.stroke(Color.black, lineWidth: 1).allowsHitTesting(false))
        } else if theme == "fun-eink" {     // E-Ink paper: border 1.5px #1A1A1A, shadow 2px 2px 0 at 0.12
            let ink = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
            content.background { shape.fill(ink.opacity(0.12)).offset(x: 2, y: 2) }
                .overlay(shape.stroke(ink, lineWidth: 1.5).allowsHitTesting(false))
        } else if theme == "fun-glass" {    // Frutiger Aero: border 1px white 0.85, shadow 0 4px 12px sky at 0.12
            content.overlay(shape.stroke(Color.white.opacity(0.85), lineWidth: 1).allowsHitTesting(false))
                .background { shape.stroke(Color.white.opacity(0.01)).shadow(color: Color(red: 2 / 255, green: 132 / 255, blue: 199 / 255).opacity(0.12), radius: 6, y: 4) }
        } else {
            content
        }
    }
}

extension View {
    /// A glass surface that follows Settings (see-through, glass on or off). Use this, never `.glassEffect(.regular...)` directly.
    func plGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        modifier(PLSurface(part: .card, tint: tint, interactive: interactive, shape: shape))
    }
}

extension View {
    /// The text face for a text style: the system font, or Jost when Settings says so.
    func plFont(_ text: PLText, emphasized: Bool = false) -> some View {
        modifier(PLFontModifier(text: text, emphasized: emphasized, isTitle: false))
    }

    /// A screen title: the theme pack's title font when a pack is loaded, else the text face, emphasized.
    func plTitle(_ text: PLText = .headline) -> some View {
        modifier(PLFontModifier(text: text, emphasized: true, isTitle: true))
    }

    /// Reading text (captions, messages, answers): the iOS 27 kit's loose leading for the body style, so long text breathes.
    func plReading() -> some View {
        let t = IOS27.TypeRamp.body
        return lineSpacing((t.loose - t.leading) * t.size)
    }

    /// Liquid Glass for a custom control on the floating layer: controls only, never content, never glass on glass.
    func glassControl(tint: Color? = nil, in shape: some Shape = Capsule()) -> some View {
        buttonStyle(.plain).modifier(GlassControl(tint: tint, shape: shape))
    }
}

/// Registers the bundled font files at launch, so the text face does not depend on the Info.plist list.
enum PLFonts {
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)   // false only means it was already registered
        }
    }
}

/// The haptics map. Each pattern keeps Apple's documented meaning.
@MainActor
enum PLHaptic {
    static let success = SensoryFeedback.success
    static let warning = SensoryFeedback.warning
    static let error = SensoryFeedback.error
    static let select = SensoryFeedback.selection
    static let open = SensoryFeedback.impact(weight: .light)
    static let commit = SensoryFeedback.impact(weight: .medium)
}

/// Motion: springs, or a short fade when Reduce Motion or the app's own Motion setting asks for less.
enum PLMotion {
    // the theme's pace: slower and cooler on the low bands, quicker toward Rising (felt-time evidence is weak; the Lab says so)
    static func standard(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35 * PLStyle.pace) }
    static func spring(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.3 * PLStyle.pace, dampingFraction: 0.9) }
}

/// The Theme setting as SwiftUI's colour scheme; nil follows the system.
enum PLAppearance {
    static func scheme(_ theme: String) -> ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}


/// A theme's title finish (S353·7b1e, his references 11-24): Synthwave's chrome lettering, a neon glow for the night themes.
private struct TitleFX: ViewModifier {
    let active: Bool, fx: String
    @State private var kit = HouseKit.shared

    func body(content: Content) -> some View {
        let key = kit.palette.keyColor
        if active && fx == "chrome" {
            content
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78), key, Color(white: 0.25), .white], startPoint: .top, endPoint: .bottom))
                .shadow(color: key.opacity(0.75), radius: 6)
        } else if active && fx == "glow" {
            content.shadow(color: key.opacity(0.9), radius: 5).shadow(color: key.opacity(0.5), radius: 12)
        } else {
            content
        }
    }
}
