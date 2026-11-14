import SwiftUI

/// Composer's own skin: pl-composer `app/globals.css` (the pl-os tokens in the inner tongue, on the ink ground the web board always uses),
/// the gold hairline, the recessed graph well, the display serif on the piece name, the instrument face on every number, small
/// spaced capitals on labels. Native twins: New York for Cormorant Garamond, the system face for DM Sans, SF Mono for JetBrains Mono.
/// Panels lean Liquid Glass (thin fills, clear glass pills); the well, nodes and wires are drawn, never glass.
enum CMP {
    static var bg: Color { PLCarry.tone(.ground, .dark, Color(hex: 0x0e0c09)) }
    static var surface: Color { PLCarry.tone(.surface, .dark, Color(hex: 0x1a1510)) }
    static var surface2: Color { PLCarry.tone(.surface2, .dark, Color(hex: 0x262018)) }
    static var line: Color { PLCarry.tone(.ink, .dark, Color.white.opacity(0.12), alpha: 0.12) }
    static var gold: Color { PLCarry.tone(.accent, .dark, Color(hex: 0xc9a84c)) }
    static var goldDim: Color { PLCarry.tone(.accentDim, .dark, Color(hex: 0x8a7235)) }
    static var text: Color { PLCarry.tone(.ink, .dark, Color(hex: 0xf2ece0)) }
    static var dim: Color { PLCarry.tone(.dim, .dark, Color(hex: 0xb8a890)) }
    static var muted: Color { PLCarry.tone(.faint, .dark, Color(hex: 0x9a8d78)) }
    static let ok = Color(hex: 0x2d8a6e)
    static let warn = Color(hex: 0xb07d2a)
    static let danger = Color(hex: 0xc0392b)
    static let info = Color(hex: 0x5f93a3)
    static var well: Color { PLCarry.tone(.well, .dark, Color(hex: 0x14110c)) }
    static var node: Color { PLCarry.tone(.surface2, .dark, Color(hex: 0x201a13)) }
    static var nodeLine: Color { PLCarry.tone(.line, .dark, Color(hex: 0xc9a84c).opacity(0.20), alpha: 0.9) }
    static var edge: Color { PLCarry.tone(.accent, .dark, Color(hex: 0xc9a84c).opacity(0.55), alpha: 0.55) }
    static let radius: CGFloat = 14

    /// A board lane's colour: the house's own, never a new hue.
    static func lane(_ id: String) -> Color {
        switch id {
        case "sent": return info; case "rendering": return gold; case "rendered", "mixing": return Color(hex: 0x9b72cf)
        case "filed": return ok; case "ruled": return goldDim; default: return danger
        }
    }
}

/// The ground behind every Composer screen: ink with his curve tile faint over it.
struct CMPGround: View {
    var body: some View {
        ZStack { CMP.bg; HouseGround().opacity(0.35).blendMode(.screen) }.ignoresSafeArea()
    }
}

/// `.border rule bg-surface` as glass: a thin fill, the hairline, a soft sheen across the top.
struct CMPCard: ViewModifier {
    var padding: CGFloat = 12
    var selected = false
    var warn = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CMP.radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(CMP.surface.opacity(0.42))
                    LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom).frame(maxHeight: .infinity, alignment: .top).mask(shape).allowsHitTesting(false)
                }
                .glassEffect(.regular, in: shape)
            }
            .overlay { shape.strokeBorder(selected ? CMP.gold : (warn ? CMP.danger.opacity(0.7) : CMP.line), lineWidth: selected ? 1.4 : 0.8) }
    }
}

extension View {
    func cmpCard(padding: CGFloat = 12, selected: Bool = false, warn: Bool = false) -> some View { modifier(CMPCard(padding: padding, selected: selected, warn: warn)) }
    /// `text-[10px] uppercase tracking-[0.12em] text-muted`.
    func cmpLabel(_ size: CGFloat = 10) -> some View { font(.system(size: size, weight: .regular, design: .monospaced)).textCase(.uppercase).tracking(size * 0.12).foregroundStyle(CMP.muted) }
    /// `.num`: numbers are data, tabular, in the instrument face.
    func cmpNum(_ size: CGFloat = 12) -> some View { font(.system(size: size, design: .monospaced)).monospacedDigit() }
    /// The display face on the piece name and panel headings (Cormorant on the web, New York here).
    func cmpDisplay(_ size: CGFloat = 22, relativeTo style: Font.TextStyle = .title2) -> some View { font(.system(size: size, weight: .regular, design: .serif)) }
    /// The screen: ink ground, gold tint, dark scheme (the web board has no light mode), Lists see-through.
    func cmpScreen() -> some View {
        scrollContentBackground(.hidden).background { CMPGround() }.tint(CMP.gold).environment(\.colorScheme, .dark)
    }
}

/// The pill buttons of the strip (`border rule px-3 py-1 text-[12px]`), clear glass with the hairline; `primary` is Build spec's gold.
struct CMPPill: ButtonStyle {
    var primary = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(primary ? CMP.text : CMP.dim)
            .padding(.horizontal, compact ? 12 : 16).frame(minHeight: compact ? 36 : 44)
            .background { if primary { Capsule().fill(CMP.gold.opacity(0.14)) } }
            .glassEffect(.clear.interactive(), in: Capsule())
            .overlay { Capsule().strokeBorder(primary ? CMP.gold : CMP.line, lineWidth: primary ? 1 : 0.8) }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// A filter chip (`rounded-full border px-2 py-0.5 text-[11px]`, gold when on).
struct CMPChip: View {
    let title: String
    var count: Int? = nil
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12))
                if let count { Text("\(count)").cmpNum(10).opacity(0.6) }
            }
            .foregroundStyle(on ? CMP.text : CMP.dim)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background(on ? CMP.gold.opacity(0.14) : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(on ? CMP.gold : CMP.line, lineWidth: 0.8) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A socket's coloured dot (the coloured square and badge the web gives each asset).
struct CMPDot: View {
    let color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true) }
}

func composerClock(_ sec: Double) -> String { let s = Int(sec.rounded()); return "\(s / 60):" + String(format: "%02d", s % 60) }
func composerBytes(_ n: Int) -> String {
    if n < 1024 { return "\(n) B" }
    if n < 1 << 20 { return "\(n / 1024) KB" }
    if n < 1 << 30 { return String(format: "%.1f MB", Double(n) / Double(1 << 20)) }
    return String(format: "%.2f GB", Double(n) / Double(1 << 30))
}
