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

// MARK: - The practice's controls (app.css: textarea / select / input, button.ghost, .hint, .coach-note, .card h2)

/// `textarea, input`: `#0f0d09` field, `#2a2518` line, radius 6, 0.6 rem of padding, ink text. A textarea has a 4.5 rem floor.
struct PField: View {
    let prompt: String
    @Binding var text: String
    var lines: Int = 1
    var serif = false
    var small = false

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Candle.ink.opacity(0.38)), axis: .vertical)
            .lineLimit(lines > 1 ? lines...max(lines, 10) : 1...6)
            .font(serif ? .system(size: 15, design: .serif).italic() : .system(size: small ? 13 : 16))
            .foregroundStyle(serif ? Candle.goldHi : Candle.ink)
            .padding(small ? EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10) : EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .frame(maxWidth: .infinity, minHeight: lines > 1 ? 72 : nil, alignment: .topLeading)
            .background(Candle.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
            .autocorrectionDisabled(false)
    }
}

/// `<select>`: a field that opens a menu.
struct PSelect<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var value: T
    var fill = true
    var body: some View {
        Menu {
            Picker("", selection: $value) { ForEach(options, id: \.0) { Text($0.1).tag($0.0) } }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == value }?.1 ?? "").font(.system(size: 16)).foregroundStyle(Candle.ink).lineLimit(1)
                if fill { Spacer(minLength: 0) }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Candle.ink.opacity(0.5))
            }
            .padding(10).frame(maxWidth: fill ? .infinity : nil, minHeight: 44, alignment: .leading)
            .background(Candle.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
        }
        .menuStyle(.button).buttonStyle(.plain)
    }
}

/// `button.ghost`: outline, ink, regular weight, 0.8 rem.
struct CandleGhost: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13)).foregroundStyle(Candle.ink)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(configuration.isPressed ? Candle.gold : Candle.pillLine, lineWidth: 1) }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
    }
}

/// `.coach-note`: serif italic gold-hi, loose leading. Empty text draws nothing (`:empty { display: none }`).
struct CoachNote: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text(text).font(.system(size: 14.7, design: .serif).italic()).foregroundStyle(Candle.goldHi).lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.top, 4)
        }
    }
}

/// One line after an action (DESIGN.md section 2): never a modal, in the practice's own quiet voice.
struct CandleResult: View {
    let text: String?
    var body: some View {
        if let text, !text.isEmpty { Text(text).candleHint().frame(maxWidth: .infinity, alignment: .leading).transition(.opacity) }
    }
}

/// `.card` with its `h2`, an optional `.hint`, and the anchor the deep links scroll to.
struct PCard<Content: View>: View {
    let title: String
    var hint: String?
    var id: String?
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).candleH2().accessibilityAddTraits(.isHeader)
            if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5)) }
            content()
        }
        .candleCard(padding: 17.6)
        .id(id ?? title)
    }
}

/// `.log-kind`: the small uppercase pill on a log line.
struct KindPill: View {
    let kind: String
    var body: some View {
        let win = kind == "win"
        Text(win ? "win" : "noticed").font(.system(size: 10.9)).textCase(.uppercase).tracking(0.9)
            .foregroundStyle(win ? Candle.goldHi : Candle.ink.opacity(0.8))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(win ? Candle.gold.opacity(0.18) : .clear, in: Capsule())
            .overlay { Capsule().strokeBorder(win ? Candle.gold.opacity(0.4) : Candle.pillLine, lineWidth: 1) }
    }
}

/// `.dot`: a day of the week, gold when ticked.
struct WeekDots: View {
    let week: [Bool]
    var body: some View {
        HStack(spacing: 4) { ForEach(week.indices, id: \.self) { Circle().fill(week[$0] ? Candle.gold : Candle.fieldLine).frame(width: 7, height: 7) } }
            .accessibilityHidden(true)
    }
}

/// A hairline between list items inside a card (`border-top: 1px solid #221e15`).
struct CandleRule: View { var body: some View { Rectangle().fill(Candle.rule).frame(height: 1) } }

/// `.vision-empty`.
struct QuietLine: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.5)) }
}

/// `<details><summary>`: a disclosure with the hint-style summary.
struct PDetails<Content: View>: View {
    let summary: String
    @Binding var open: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "triangle.fill").font(.system(size: 7)).rotationEffect(.degrees(open ? 180 : 90))
                    Text(summary)
                }
                .font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5)).frame(minHeight: 36, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityAddTraits(.isButton).accessibilityValue(open ? "expanded" : "collapsed")
            if open { content() }
        }
    }
}
