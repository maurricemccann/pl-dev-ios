import SwiftUI

/// pl-os's own skin for House (his word 11-13: "house should literally be plos but using Apple's stuff"; "look at the Chrome
/// version"). Every value is pl-os `app/globals.css`: the ivory console and its `[data-psytheme="dark"]` flip, gold as the only
/// accent, the glass card with its gold hairline and top sheen, the hand on panel names, the instrument face on numbers.
/// Native twins: SF Mono for JetBrains Mono, the system face for DM Sans, New York italic for Cormorant (native first).
enum PLOS {
    static func bg(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x0e0c08) : Color(hex: 0xfaf7f0) }
    static func surface(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x1a1610) : Color(hex: 0xfdf9f1) }
    static func surface2(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x221d15) : Color(hex: 0xf5efe2) }
    static func line(_ s: ColorScheme) -> Color { s == .dark ? Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255).opacity(0.18) : Color(red: 160 / 255, green: 140 / 255, blue: 110 / 255).opacity(0.22) }
    static func text(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xefe6d2) : Color(hex: 0x1a1510) }
    static func dim(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xb3a585) : Color(hex: 0x6b5d48) }
    static func goldDim(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xb8973f) : Color(hex: 0x8a7235) }
    static let gold = Color(hex: 0xc9a84c)
    static let muted = Color(hex: 0x8a8270)
    static let ok = Color(hex: 0x2d8a6e)
    static let warn = Color(hex: 0xb07d2a)
    static let danger = Color(hex: 0xc0392b)
    static let philosophy = Color(hex: 0x9b72cf)
    static let radius: CGFloat = 18
    /// pl-os ModerationPanel PLATFORM_COLORS: every draft wears its platform's colour.
    static func platform(_ p: String?) -> Color {
        switch p ?? "instagram" {
        case "instagram": return Color(hex: 0xc9679a); case "threads": return Color(hex: 0x8a8a8a)   // pl-os #3a3a3a, lifted to read on obsidian
        case "tumblr": return Color(hex: 0x4a64a8); case "bluesky": return Color(hex: 0x3a8ede); case "facebook": return Color(hex: 0x4267b2)
        case "linkedin": return Color(hex: 0x0a7d99); case "youtube": return Color(hex: 0xb23a3a); case "pinterest": return Color(hex: 0xd1603a)
        case "substack": return Color(hex: 0xe08a2c); case "pl_feed": return gold
        default: return Color(hex: 0x8a7d6a)
        }
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255) }
}

/// The ground behind House: the console colour with his glyph field faint over it (pl-os `.glyph-bg-img`).
struct OSGround: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            PLOS.bg(scheme)
            HouseGround().opacity(0.9).blendMode(scheme == .dark ? .screen : .multiply)
        }
        .ignoresSafeArea()
    }
}

/// pl-os `.glass-card`: the surface under Liquid Glass, a gold hairline, the white sheen across the top 42 %.
struct OSCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var owed = false
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PLOS.radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(PLOS.surface(scheme).opacity(scheme == .dark ? 0.28 : 0.34))
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.08 : 0.16), .white.opacity(0.02), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(maxHeight: .infinity, alignment: .top).mask(shape).allowsHitTesting(false)
                }
                .glassEffect(.regular, in: shape)
            }
            .overlay { shape.strokeBorder(owed ? PLOS.danger.opacity(0.7) : PLOS.line(scheme), lineWidth: owed ? 1.2 : 0.8) }
    }
}

extension View {
    func osCard(owed: Bool = false, padding: CGFloat = 14) -> some View { modifier(OSCard(owed: owed, padding: padding)) }
    /// `.label` / `.o-eyebrow`: the instrument face, uppercase, spaced 0.18 em.
    func osEyebrow(_ size: CGFloat = 10) -> some View { font(.system(size: size, weight: .medium, design: .monospaced)).textCase(.uppercase).tracking(size * 0.18) }
    /// `.dash-kpi-value`: numbers and states in the instrument face.
    func osValue(_ size: CGFloat = 30) -> some View { font(.system(size: size, weight: .regular, design: .monospaced)).monospacedDigit() }
    /// House screens on the console ground, gold as the tint, Lists see-through so the glass shows.
    func osScreen() -> some View { modifier(OSScreen()) }
}

/// `.o-section-label` / Panel: a collapsible glass panel named in his hand, a mono badge on the right, a chevron.
struct OSPanel<Content: View>: View {
    let title: String
    var badge: String? = nil
    var owed = false
    var startOpen = false
    @ViewBuilder let content: () -> Content
    @State private var open: Bool?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let isOpen = open ?? startOpen
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.snappy) { open = !isOpen } } label: {
                HStack {
                    Text(title).plHand(19, relativeTo: .headline).foregroundStyle(owed ? PLOS.danger : PLOS.dim(scheme))
                    Spacer()
                    if let badge { Text(badge).osValue(13).foregroundStyle(PLOS.gold) }
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(PLOS.goldDim(scheme))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Closes this panel" : "Opens this panel")
            if isOpen { content().transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .osCard(owed: owed)
    }
}

/// A row inside a panel: pl-os's inner `.glass-card` on `surface-2`.
struct OSRow<Trailing: View>: View {
    let title: String
    var meta: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).foregroundStyle(PLOS.text(scheme)).multilineTextAlignment(.leading)
                if let meta { Text(meta).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(12)
        .background(PLOS.surface2(scheme).opacity(scheme == .dark ? 0.32 : 0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PLOS.line(scheme), lineWidth: 0.6) }
    }
}
extension OSRow where Trailing == EmptyView { init(title: String, meta: String? = nil) { self.init(title: title, meta: meta) { EmptyView() } } }

/// `.dash-strip-settings`: the pill buttons of the strip and the call bar.
struct OSPill: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme))
            .padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: .infinity)
            .glassEffect(.clear.interactive(), in: Capsule())
            .overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The header: his wordmark in his hand and the live LA clock in the display italic (pl-os `.time-display`).
struct OSHeader: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(alignment: .center) {
            // the way home, inside the header card, never floating over the page (his word 11-13: "no way to go back home")
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Image("PLIcons/pl-mark").resizable().scaledToFit().frame(width: 28, height: 28)
                }
                .foregroundStyle(PLOS.gold)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Home")
            Text("Psyched Luxuries").plHand(24, relativeTo: .title2).foregroundStyle(PLOS.gold).lineLimit(1).minimumScaleFactor(0.55)
            Spacer()
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ctx.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(identifier: "America/Los_Angeles")!)))
                        .font(.system(.title3, design: .serif).italic()).foregroundStyle(PLOS.gold)
                    Text("LA · " + ctx.date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "America/Los_Angeles")!).weekday(.abbreviated).month(.abbreviated).day()))
                        .osEyebrow(8).foregroundStyle(PLOS.dim(scheme))
                }
            }
        }
        .osCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// `.o-tabbar`: Inbound · Founder (the gold centre, a badge) · Outbound · More, on glass at the bottom.
struct OSTabBar: View {
    @Binding var tab: HouseModel.Tab
    var badge: Int = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 6) {
                item(.inbound, "square.and.arrow.down", "Inbound")
                item(.founder, "circle.circle", "Founder")
                item(.outbound, "square.and.arrow.up", "Outbound")
                item(.more, "ellipsis", "More")
            }
            .padding(6)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    private func item(_ t: HouseModel.Tab, _ symbol: String, _ title: String) -> some View {
        let on = tab == t
        return Button { withAnimation(.snappy) { tab = t } } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                Text(title).osEyebrow(8)
            }
            .foregroundStyle(on ? Color.black : PLOS.dim(scheme))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background { if on { Capsule().fill(PLOS.gold) } }
            .overlay(alignment: .topTrailing) {
                if t == .founder, badge > 0 {
                    Text("\(badge)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(PLOS.gold, in: Capsule()).overlay { Capsule().strokeBorder(.black.opacity(0.3)) }
                        .offset(x: -6, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// `.dash-kpi`: four numbers with their names in his hand, a status line under them.
struct OSKpis: View {
    let items: [(String, String, String?)]
    var status: (String, Color)? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items[i].0).plHand(15, relativeTo: .footnote).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(items[i].1).osValue(28).foregroundStyle(PLOS.text(scheme)).contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                        if let sub = items[i].2 { Text(sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            if let status {
                HStack(spacing: 6) {
                    Circle().fill(status.1).frame(width: 7, height: 7)
                    Text(status.0).font(.system(size: 12, design: .monospaced)).foregroundStyle(PLOS.dim(scheme))
                }
            }
        }
        .osCard()
    }
}

/// pl-os's row inside a room: the first glass on the console ground, held by its hairline (every List row in House wears it).
struct OSRowBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(PLOS.surface(scheme).opacity(scheme == .dark ? 0.42 : 0.5))
            .overlay(alignment: .bottom) { Rectangle().fill(PLOS.line(scheme)).frame(height: 0.5) }
    }
}


/// House's screen: the console ground, gold as the tint, Lists see-through, and pl-os's dark theme unless he chose light
/// (Settings > House look). His screenshot of pl-os dark on the PC, 11-13: "this looked really cool".
struct OSScreen: ViewModifier {
    @AppStorage("house.look") private var look = "dark"
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background { OSGround() }.tint(PLOS.gold)
            .environment(\.colorScheme, look == "light" ? .light : .dark)
    }
}
