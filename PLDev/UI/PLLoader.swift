import SwiftUI

/// The house loader (his "build all", 11-13; the idea from uiverse.io, made his): one gold curve drawing itself, again and again,
/// in place of the system spinner. It takes the colour the screen already gave its spinner (`.tint`), so every section keeps its look.
/// Reduce Motion: the curve stands still, half drawn.
struct PLLoader: View {
    var size: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            let t = reduce ? 0.5 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            // draw on over the first 60%, then the tail follows it off: a line that is always being made
            let head = min(1, t / 0.6), tail = max(0, (t - 0.45) / 0.55)
            HouseCurve()
                .trim(from: reduce ? 0 : tail, to: reduce ? 0.6 : head)
                .stroke(.tint, style: StrokeStyle(lineWidth: max(2, size / 10), lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size * 0.62)
        }
        .frame(minWidth: size, minHeight: size)
        .accessibilityElement().accessibilityLabel("Loading")
    }
}

/// One of his curves, simplified: an S that swells and turns back on itself.
struct HouseCurve: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY * 0.8))
        p.addCurve(to: CGPoint(x: r.midX, y: r.midY), control1: CGPoint(x: r.minX + r.width * 0.15, y: r.minY - r.height * 0.2), control2: CGPoint(x: r.midX - r.width * 0.2, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.2), control1: CGPoint(x: r.midX + r.width * 0.2, y: r.maxY), control2: CGPoint(x: r.maxX - r.width * 0.15, y: r.maxY + r.height * 0.2))
        return p
    }
}

/// GlyphBot thinking: a soft gold orb that breathes (the "Generating" orb on uiverse.io, in his gold).
struct PLThinkingOrb: View {
    var size: CGFloat = 54
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            let s = reduce ? 0.5 : (sin(tl.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0xf6e3a1), Color(hex: 0xc9a84c), Color(hex: 0x8a6420).opacity(0.0)],
                                             center: .center, startRadius: 2, endRadius: size * 0.62))
                    .scaleEffect(0.86 + 0.14 * s)
                    .blur(radius: 6 + 4 * s)
                Circle().strokeBorder(Color(hex: 0xf6e3a1).opacity(0.35 + 0.3 * s), lineWidth: 1)
                    .frame(width: size * 0.7, height: size * 0.7)
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement().accessibilityLabel("Thinking")
    }
}
