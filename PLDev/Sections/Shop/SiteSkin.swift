import SwiftUI

/// psychedluxuries.com's own skin (his look ruling 11-13: each native app looks exactly like its web app). Every value is
/// pl-headless `app/globals.css` + `app/psyglass.css`: the bone ground, ink for reading, gold as the one accent, the hairline
/// `#ddd5c4`, Cormorant for the declaring voice (italic gold on the one word that carries it), Jost light for the speaking voice,
/// small capitals tracked 0.34 em for labels, ink pill buttons, the raised cream card with its soft lift. The site is light by
/// design; in Dark Appearance the ground becomes the site's obsidian (the footer and the Room) and ink flips to bone.
/// Native twins: New York serif for Cormorant Garamond (its closest system face), bundled Jost for Jost.
enum Bone {
    static func ground(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x0e0c08) : Color(hex: 0xf1ece1) }
    static func raised(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x1c1813) : Color(hex: 0xfaf6ec) }
    static func ink(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xf1ece1) : Color(hex: 0x15120b) }
    static func inkSoft(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xc9c1ad) : Color(hex: 0x4f4a3b) }
    static func inkFaint(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x9b937f) : Color(hex: 0x6f6857) }
    static func line(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xc9a84c).opacity(0.22) : Color(hex: 0xddd5c4) }
    static let gold = Color(hex: 0xc9a84c)
    static let goldDim = Color(hex: 0x8a7235)
    static let oxblood = Color(hex: 0x5e1622)
    static let teal = Color(hex: 0x2d8a6e)
    static let amber = Color(hex: 0xdb9314)
    static let proof = Color(hex: 0xc0392b)
    static let philosophy = Color(hex: 0x9b72cf)
    static let cardRadius: CGFloat = 24
    static let rowRadius: CGFloat = 14
}

/// The site's two typefaces as SwiftUI fonts.
enum SiteFont {
    /// `font-display` (Cormorant): the system serif at a light weight, scaling with Dynamic Type.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title, italic: Bool = false) -> Font {
        let f = Font.system(size: size, weight: .light, design: .serif)
        return italic ? f.italic() : f
    }
    /// `font-body` (Jost): Book is the lightest weight bundled; Medium and Semi are the emphasised steps.
    static func body(_ size: CGFloat = 15, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let name = weight == .semibold || weight == .bold ? "Jost-Semi" : (weight == .medium ? "Jost-Medium" : "Jost-Book")
        return .custom(name, size: size, relativeTo: style)
    }
}

/// Wearable *doctrine.*: a headline whose last word is the italic gold one, as on every page of the site.
struct SiteHeadline: View {
    let lead: String
    let accent: String
    var size: CGFloat = 34
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        (Text(lead + " ").font(SiteFont.display(size)).foregroundColor(Bone.ink(scheme))
            + Text(accent).font(SiteFont.display(size, italic: true)).foregroundColor(Bone.gold))
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The page opening: the eyebrow line, the headline, the lede (`THE SHOP — 89 PIECES` / `Wearable doctrine.` / a paragraph).
struct SitePageHead: View {
    let eyebrow: String
    let lead: String
    let accent: String
    var lede: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow).siteLabel()
            SiteHeadline(lead: lead, accent: accent)
            if let lede { Text(lede).font(SiteFont.body(15)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
    }
}

struct SiteGround: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Bone.ground(scheme).ignoresSafeArea() }
}

/// The raised cream card: paper lifted off bone, a hairline, a soft warm shadow (`--psylight-shadow` on the light ground).
struct SiteCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    var radius: CGFloat = Bone.cardRadius
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Bone.raised(scheme), in: shape)
            .overlay { shape.strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
            .shadow(color: scheme == .dark ? .clear : Color(red: 60 / 255, green: 45 / 255, blue: 20 / 255).opacity(0.12), radius: 14, y: 8)
    }
}

extension View {
    func siteCard(padding: CGFloat = 16, radius: CGFloat = Bone.cardRadius) -> some View { modifier(SiteCard(padding: padding, radius: radius)) }
    /// `.label`: Jost 11 px, 0.34 em tracking, uppercase, ink-faint.
    func siteLabel(_ size: CGFloat = 11) -> some View { modifier(SiteLabel(size: size)) }
    /// The site's reading text: Jost, ink-soft.
    func siteBody(_ size: CGFloat = 15) -> some View { modifier(SiteBody(size: size)) }
    /// A page on the bone ground. Navigation stays Apple's; the content is the site's.
    func siteScreen() -> some View {
        modifier(SiteScreen())
    }
}

private struct SiteLabel: ViewModifier {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.font(SiteFont.body(size, relativeTo: .caption)).textCase(.uppercase).tracking(size * 0.3).foregroundStyle(Bone.inkFaint(scheme))
    }
}

private struct SiteBody: ViewModifier {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.font(SiteFont.body(size)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(5)
    }
}

private struct SiteScreen: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { SiteGround() }
            .tint(Bone.goldDim)
    }
}

/// The ink pill: obsidian fill, bone text, tracked capitals (`ENTER THE CONGREGATION`). `gold` is the hero call (`ENTER THE ROOM →`).
struct SitePill: ButtonStyle {
    var gold = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = gold ? Bone.gold : (scheme == .dark ? Color(hex: 0xf1ece1) : Color(hex: 0x15120b))
        let text: Color = gold ? Color(hex: 0x15120b) : (scheme == .dark ? Color(hex: 0x15120b) : Color(hex: 0xf1ece1))
        configuration.label
            .font(SiteFont.body(12, relativeTo: .footnote, weight: .medium)).textCase(.uppercase).tracking(2.6)
            .foregroundStyle(text)
            .padding(.horizontal, 26).frame(minHeight: 50).frame(maxWidth: .infinity)
            .background(fill, in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// The outline pill: the hairline and gold-dim text, the site's quiet second button.
struct SiteGhost: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SiteFont.body(12, relativeTo: .footnote, weight: .medium)).textCase(.uppercase).tracking(2.4)
            .foregroundStyle(Bone.ink(scheme))
            .padding(.horizontal, 22).frame(minHeight: 48).frame(maxWidth: .infinity)
            .overlay { Capsule().strokeBorder(Bone.ink(scheme).opacity(0.55), lineWidth: 0.8) }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// A filter or option chip: tracked capitals, a hairline outline, gold wash when chosen.
struct SiteChip: View {
    let title: String
    let on: Bool
    var dim = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Text(title).font(SiteFont.body(11, relativeTo: .caption, weight: on ? .medium : .regular)).textCase(.uppercase).tracking(2)
                .foregroundStyle(on ? Color(hex: 0x15120b) : Bone.inkSoft(scheme))
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background { if on { Capsule().fill(Bone.gold) } }
                .overlay { Capsule().strokeBorder(on ? Color.clear : Bone.line(scheme), lineWidth: 0.9) }
                .opacity(dim ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A hairline between sections (`border-top: 1px solid var(--color-line)`).
struct SiteRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(Bone.line(scheme)).frame(height: 0.6) }
}

/// The site's nav as tabs: tracked capitals on the bone ground, the chosen one in ink with a gold rule under it
/// (the site's `SIGN IN · CART` row, which has no counterpart in a native app, becomes the app's own page switch).
struct SiteTabs: View {
    let titles: [String]
    @Binding var index: Int
    @Environment(\.colorScheme) private var scheme
    @Namespace private var rule
    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                Button { withAnimation(.snappy) { index = i } } label: {
                    VStack(spacing: 8) {
                        Text(titles[i]).font(SiteFont.body(11, relativeTo: .caption, weight: index == i ? .medium : .regular)).textCase(.uppercase).tracking(3)
                            .foregroundStyle(index == i ? Bone.ink(scheme) : Bone.inkFaint(scheme))
                        ZStack {
                            Rectangle().fill(.clear).frame(height: 1.5)
                            if index == i { Rectangle().fill(Bone.gold).frame(height: 1.5).matchedGeometryEffect(id: "rule", in: rule) }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == i ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12).padding(.top, 4)
        .background(Bone.ground(scheme).opacity(0.94))
        .overlay(alignment: .bottom) { SiteRule() }
    }
}

private struct SiteList: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(SiteFont.body(16))
            .foregroundStyle(Bone.ink(scheme))
            .scrollContentBackground(.hidden)
            .background { SiteGround() }
            .listRowBackground(Bone.raised(scheme))
            .listRowSeparatorTint(Bone.line(scheme))
            .tint(Bone.goldDim)
    }
}

extension View {
    /// A List or Form on the bone ground: the rows are the site's raised cream, the separators its hairline, text Jost in ink.
    func siteList() -> some View { modifier(SiteList()) }
}
