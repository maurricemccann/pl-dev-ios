import SwiftUI

/// The Curve Library's own skin (his ruling 11-13: each app looks exactly like its web app). Every value is pl-curves-gallery
/// `app/globals.css`: obsidian ground and its `[data-psytheme="dark"]` twin of the cream page, gold as the one accent, the gold
/// hairline, caps in Jost (the system face here) spaced 0.28 em, titles in Cormorant italic (New York italic here), and his
/// curve tile faint under everything. Library, Curate, Pick, Town and every room read from here; none invents a colour.
enum PLG {
    static func bg(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x0e0c08) : Color(hex: 0xfaf7f0) }
    static func surface(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x1a1610) : Color(hex: 0xfdf9f1) }
    static func ink(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xefe6d2) : Color(hex: 0x1a1510) }
    static func dim(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xb3a585) : Color(hex: 0x6b5d48) }
    static func line(_ s: ColorScheme) -> Color { s == .dark ? gold.opacity(0.22) : Color(red: 160 / 255, green: 140 / 255, blue: 110 / 255).opacity(0.28) }
    static let gold = Color(hex: 0xc9a84c)
    static func goldDim(_ s: ColorScheme) -> Color { s == .dark ? gold : Color(hex: 0x8a7235) }
    static let red = Color(hex: 0xC8402A)      // studio red: the live marker, the active tab, a cut
    static let teal = Color(hex: 0x2d8a6e)     // a keep
    static let amber = Color(hex: 0xdb9314)    // a maybe
    static let orange = Color(hex: 0xd9702a)   // the ring on cloud batches and API renders
    static let radius: CGFloat = 18
}

/// The page ground: obsidian (or cream) with his curve tile faint over it.
struct GalleryGround: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            PLG.bg(scheme)
            HouseGround().opacity(0.55).blendMode(scheme == .dark ? .screen : .multiply)
        }
        .ignoresSafeArea()
    }
}

/// `.pl-index-card`: the surface under glass, a hairline, the sheen across the top.
struct GalleryCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 14
    var radius: CGFloat = PLG.radius
    var active = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(PLG.surface(scheme).opacity(scheme == .dark ? 0.62 : 0.72))
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.08 : 0.2), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(maxHeight: .infinity, alignment: .top).mask(shape).allowsHitTesting(false)
                }
                .glassEffect(.regular, in: shape)
            }
            .overlay { shape.strokeBorder(active ? PLG.gold.opacity(0.72) : PLG.line(scheme), lineWidth: active ? 1.2 : 0.8) }
    }
}

extension View {
    func gCard(padding: CGFloat = 14, radius: CGFloat = PLG.radius, active: Bool = false) -> some View { modifier(GalleryCard(padding: padding, radius: radius, active: active)) }
    /// The small gold label: caps in the sans, spaced 0.28 em.
    func gEyebrow(_ size: CGFloat = 10) -> some View { font(.system(size: size, weight: .medium)).textCase(.uppercase).tracking(size * 0.28) }
    /// The page title and card names: Cormorant italic (New York italic natively).
    func gTitle(_ size: CGFloat = 34, relativeTo style: Font.TextStyle = .largeTitle) -> some View { font(.system(size: size, weight: .regular, design: .serif).italic()) }
    /// A figure or id in the instrument face.
    func gMono(_ size: CGFloat = 12) -> some View { font(.system(size: size, weight: .semibold, design: .monospaced)) }
    /// Gallery screens: the page ground, gold tint, lists see-through with glass rows, the nav bar kept quiet.
    func gScreen() -> some View {
        scrollContentBackground(.hidden).background { GalleryGround() }.tint(PLG.gold)
            .listRowBackground(GalleryRowBG())
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// A list row's backing: the hairline glass the web rooms use.
struct GalleryRowBG: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PLG.surface(scheme).opacity(0.6))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PLG.line(scheme), lineWidth: 0.6) }
            .padding(.vertical, 2)
    }
}

/// `.chip`: a pill with a gold hairline; the active one is filled bone with ink text, as the Library's verdict row draws it.
struct GalleryChip: View {
    let title: String
    var count: Int? = nil
    var on = false
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 6) {
            Text(title).gEyebrow(10.5)
            if let count { Text(count.formatted()).font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit() }
        }
        .foregroundStyle(on ? Color(hex: 0x15120b) : (tint ?? PLG.dim(scheme)))
        .padding(.horizontal, 14).frame(minHeight: 40)
        .background { Capsule().fill(on ? Color(hex: 0xf1ece1) : Color.clear) }
        .overlay { Capsule().strokeBorder(on ? Color.clear : (tint ?? PLG.gold).opacity(0.45), lineWidth: 0.9) }
        .contentShape(Capsule())
    }
}

/// A section header the web draws as a gold label over a hairline.
struct GalleryHeader: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View { Text(text).gEyebrow(10).foregroundStyle(PLG.goldDim(scheme).opacity(0.9)).padding(.top, 6) }
}

/// The big page heading: a small gold eyebrow over the title in italics (the Library's "THE CURVE LIBRARY / Library").
struct GalleryHeading: View {
    let eyebrow: String
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow).gEyebrow(10).foregroundStyle(PLG.gold)
            Text(title).gTitle(38).foregroundStyle(PLG.ink(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}
