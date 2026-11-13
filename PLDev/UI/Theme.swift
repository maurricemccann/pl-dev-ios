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
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize   // read so a Dynamic Type change redraws the scaled system size

    init(text: PLText, emphasized: Bool, isTitle: Bool) {
        self.text = text
        self.emphasized = emphasized
        self.isTitle = isTitle
    }

    func body(content: Content) -> some View {
        let _ = dynamicTypeSize
        let scale = min(1.3, max(0.9, textSize / 100))
        if isTitle, let pack = ThemePack.shared.titleFont {
            content.font(text.packFont(pack, scale: scale))
        } else {
            content.font(text.font(face: face, scale: scale, bold: legibilityWeight == .bold, emphasized: emphasized))
        }
    }
}

private struct GlassControl<S: Shape>: ViewModifier {
    let tint: Color?
    let shape: S
    @AppStorage("pldev.glassBlur") private var glass = true
    @AppStorage("pldev.glassClear") private var clear = false

    init(tint: Color?, shape: S) {
        self.tint = tint
        self.shape = shape
    }

    func body(content: Content) -> some View {
        if glass {
            content.glassEffect((clear ? Glass.clear : Glass.regular).tint(tint).interactive(), in: shape)
        } else {
            content.background(tint ?? PLTone.plate, in: shape)   // glass switched off in Settings: a plain solid control
        }
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
    static func standard(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : .smooth }
    static func spring(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.68) }
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
