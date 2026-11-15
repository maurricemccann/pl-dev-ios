import SwiftUI

/// The parts that turn a number, a stage, a state or a trend into a picture (his ask 11-14: "most of this information can be shown
/// visually instead where it's not dire to see the text"). Each part takes its colours from the screen that uses it, so every section
/// keeps its own app's look. The exact number always stays on the picture and in the VoiceOver label: nothing is hidden.

/// Counts across stages as one bar, each segment as wide as its share, with the numbers named underneath.
struct PLStageBar: View {
    struct Stage: Identifiable { let name: String; let count: Int; let tint: Color; var id: String { name } }
    let stages: [Stage]
    var text: Color = .primary
    var dim: Color = .secondary
    var height: CGFloat = 14

    var body: some View {
        let total = max(stages.map(\.count).reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stages.filter { $0.count > 0 }) { s in
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(s.tint.gradient)
                            .frame(width: max(height, (geo.size.width - CGFloat(stages.count) * 2) * CGFloat(s.count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: height)
            .background(dim.opacity(0.14), in: Capsule())
            HStack(alignment: .top, spacing: 12) {
                ForEach(stages) { s in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(s.count)").font(.system(.title2, design: .monospaced)).monospacedDigit().foregroundStyle(text).contentTransition(.numericText())
                        HStack(spacing: 4) {
                            Circle().fill(s.tint).frame(width: 7, height: 7)
                            Text(s.name).font(.system(size: 10, weight: .medium, design: .monospaced)).textCase(.uppercase).foregroundStyle(dim).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stages.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
    }
}

/// A share or a rate as a ring with the number in the middle. `value` is 0 to 1; anything outside is held to the ends.
struct PLRing: View {
    let value: Double
    let center: String
    var label: String? = nil
    var tint: Color = .accentColor
    var text: Color = .primary
    var dim: Color = .secondary
    var size: CGFloat = 84

    var body: some View {
        let v = min(max(value, 0), 1)
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(dim.opacity(0.18), lineWidth: size * 0.1)
                Circle().trim(from: 0, to: v).stroke(tint.gradient, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: v)
                Text(center).font(.system(size: size * 0.24, weight: .regular, design: .monospaced)).monospacedDigit().foregroundStyle(text).minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.horizontal, size * 0.16)
            }
            .frame(width: size, height: size)
            if let label { Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).textCase(.uppercase).foregroundStyle(dim).lineLimit(1).minimumScaleFactor(0.7) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label ?? "") \(center)")
    }
}

/// A state as a coloured dot and one word. A live state can breathe.
struct PLStateDot: View {
    let word: String
    let tint: Color
    var text: Color = .primary
    var live = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 10, height: 10)
                .overlay { if live && !reduce { Circle().stroke(tint.opacity(0.6), lineWidth: 2).scaleEffect(on ? 2.2 : 1).opacity(on ? 0 : 0.9) } }
                .onAppear { if live && !reduce { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true } } }
            Text(word).font(.callout.weight(.semibold)).foregroundStyle(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A length bar behind a row, for ranked lists: the row's own number decides how far it reaches.
struct PLBarBehind: ViewModifier {
    let fraction: Double
    let tint: Color
    func body(content: Content) -> some View {
        content.background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.22))
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
    }
}

extension View {
    /// Draws a length bar behind this row, `count` out of `top` (the largest in the list).
    func plBar(_ count: Double, of top: Double, tint: Color) -> some View { modifier(PLBarBehind(fraction: top > 0 ? count / top : 0, tint: tint)) }
}

/// A tiny trend: bars, with the last one lit (the album's "7-day bars with today lit").
struct PLSpark: View {
    let values: [Double]
    var tint: Color = .accentColor
    var dim: Color = .secondary
    var height: CGFloat = 28

    var body: some View {
        let top = max(values.max() ?? 0, 0.0001)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(i == values.count - 1 ? tint : dim.opacity(0.45))
                    .frame(height: max(2, height * CGFloat(values[i] / top)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Days as cells, each as strong as its amount: a calendar read at a glance.
struct PLHeatGrid: View {
    struct Cell: Identifiable { let id: String; let label: String; let amount: Double; var mark: Color? = nil }
    let cells: [Cell]
    var tint: Color = .accentColor
    var text: Color = .primary
    var dim: Color = .secondary
    var columns = 7

    var body: some View {
        let top = max(cells.map(\.amount).max() ?? 0, 0.0001)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(cells) { c in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(c.amount > 0 ? tint.opacity(0.25 + 0.75 * c.amount / top) : dim.opacity(0.12))
                        .frame(height: 26)
                        .overlay { if let m = c.mark { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(m, lineWidth: 1.5) } }
                        .overlay { Text(c.amount > 0 ? "\(Int(c.amount))" : "").font(.system(size: 10, design: .monospaced)).foregroundStyle(text) }
                    Text(c.label).font(.system(size: 8, design: .monospaced)).foregroundStyle(dim).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(c.label): \(Int(c.amount))")
            }
        }
    }
}

/// One huge number, a tiny label, one small visual beside it (the album's tile).
struct PLBigTile<Micro: View>: View {
    let number: String
    let label: String
    var tint: Color = .accentColor
    var text: Color = .primary
    var dim: Color = .secondary
    @ViewBuilder var micro: () -> Micro

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(number).font(.system(size: 34, weight: .regular, design: .monospaced)).monospacedDigit().foregroundStyle(text).lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText())
                Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).textCase(.uppercase).foregroundStyle(dim).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            micro()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(number)")
    }
}

extension PLBigTile where Micro == EmptyView {
    init(number: String, label: String, tint: Color = .accentColor, text: Color = .primary, dim: Color = .secondary) {
        self.init(number: number, label: label, tint: tint, text: text, dim: dim) { EmptyView() }
    }
}

/// A small tag: a body, a doctrine cluster, a platform, a stage.
struct PLChip: View {
    let word: String
    var tint: Color = .secondary
    var body: some View {
        Text(word).font(.system(size: 10, weight: .semibold, design: .monospaced)).textCase(.uppercase).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}
