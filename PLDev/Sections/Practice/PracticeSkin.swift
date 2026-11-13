import SwiftUI

/// The practice's own skin (his look ruling 11-13). Every value is `pl-manifestation-practice/public/app.css`: always dark and
/// warm (`#0b0a07` with the slow radial gradient), ink `#efe7d2`, gold `#c9a84c` and gold-hi `#f3e6b0` for headings, the glass
/// card (`rgba(20,18,13,.55)`, a gold hairline at 16 %, radius 12), outline pills in `#3a331f` that turn gold when chosen, the
/// gold button with dark text, the assistant's lines in a serif italic gold-hi, the system face for everything else.
/// The practice is the house's one private surface and it is dark only, so the screens pin the dark appearance.
enum Candle {
    static let bg = Color(hex: 0x0b0a07)
    static let ink = Color(hex: 0xefe7d2)
    static let gold = Color(hex: 0xc9a84c)
    static let goldHi = Color(hex: 0xf3e6b0)
    static let card = Color(hex: 0x14120d)
    static let field = Color(hex: 0x0f0d09)
    static let fieldLine = Color(hex: 0x2a2518)
    static let pillLine = Color(hex: 0x3a331f)
    static let rule = Color(hex: 0x221e15)
    static let hairline = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255).opacity(0.16)
    static let radius: CGFloat = 12
}

/// `body` background: two radial warms over the base, fixed.
struct CandleGround: View {
    var body: some View {
        ZStack {
            Candle.bg
            RadialGradient(colors: [Color(hex: 0x17130a), .clear], center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x120e14), .clear], center: UnitPoint(x: 0.9, y: 1), startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

/// `.card`: the glass surface with its gold hairline. `h2` is the card's heading in gold-hi.
struct CandleCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Candle.radius, style: .continuous)
        content
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Candle.card.opacity(0.55), in: shape)
            .background(.ultraThinMaterial.opacity(0.5), in: shape)
            .overlay { shape.strokeBorder(Candle.hairline, lineWidth: 1) }
    }
}

extension View {
    func candleCard(padding: CGFloat = 16) -> some View { modifier(CandleCard(padding: padding)) }
    /// `.card h2`: 0.95 rem, weight 500, gold-hi.
    func candleH2() -> some View { font(.system(size: 15, weight: .medium)).foregroundStyle(Candle.goldHi) }
    /// `.hint` / `.streak-label`: the quiet line under a thing.
    func candleHint() -> some View { font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5)) }
    /// A page of the practice: the warm ground, dark appearance, gold as the tint.
    func candleScreen() -> some View {
        scrollContentBackground(.hidden).background { CandleGround() }.tint(Candle.gold)
            .foregroundStyle(Candle.ink).preferredColorScheme(.dark)
    }
    /// A List or Form as stacked glass cards on the warm ground.
    func practiceList() -> some View {
        listRowBackground(Candle.card.opacity(0.55))
            .listRowSeparatorTint(Candle.rule)
            .scrollContentBackground(.hidden).background { CandleGround() }
            .tint(Candle.gold).foregroundStyle(Candle.ink)
            .preferredColorScheme(.dark)
    }
}

/// The gold button: gold fill, near-black text, radius 6 (the practice's `button`).
struct CandleButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Candle.bg)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(configuration.isPressed ? Candle.goldHi : Candle.gold, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
    }
}

/// `.tab` / `.board-src` / `.med-src`: an outline pill that is dim until chosen, then gold.
struct CandleChip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5)).foregroundStyle(on ? Candle.goldHi : Candle.ink)
                .padding(.horizontal, 15).frame(minHeight: 36)
                .overlay { Capsule().strokeBorder(on ? Candle.gold : Candle.pillLine, lineWidth: 1) }
                .opacity(on ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The practice's header: `the practice` in gold-hi, the tabs as outline pills, a hairline under.
struct CandleTabs: View {
    let titles: [String]
    @Binding var index: Int
    var body: some View {
        HStack(spacing: 8) {
            Text("the practice").font(.system(size: 17.6)).tracking(0.7).foregroundStyle(Candle.goldHi)
            Spacer(minLength: 8)
            ForEach(titles.indices, id: \.self) { i in CandleChip(title: titles[i], on: index == i) { withAnimation(.snappy) { index = i } } }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Candle.bg.opacity(0.92))
        .overlay(alignment: .bottom) { Rectangle().fill(Candle.rule).frame(height: 1) }
    }
}
