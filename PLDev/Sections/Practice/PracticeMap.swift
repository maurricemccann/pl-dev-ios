import SwiftUI

// One Teacher (S348·9a3e): the Path as a map. His rulings 11-15: "One of my hand study curves drawing itself across the glyphs the
// glyphs look like islands"; the curve is The Direction ("The piece named the direction"); the islands are his 5 drawn glyphs ("Only
// the 5 with images"). His six strokes draw in, in his order and stagger, in his colour, with the ground showing through where they
// cross (as the piece does). Stroke 1, his top-to-bottom spine, carries one island per unit. The art is PracticeMapArt, generated from
// his files by .claude/scripts/pl-path-art.py; nothing here redraws it.

enum PracticeMapGeometry {
    /// A smooth curve through his points (Catmull-Rom, as the piece's spline), scaled to the frame.
    static func stroke(_ pts: [CGPoint], in size: CGSize) -> Path {
        let p = pts.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        guard p.count > 1 else { return path }
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    /// The point a share `f` of the way along a path.
    static func point(on path: Path, at f: CGFloat) -> CGPoint {
        path.trimmedPath(from: 0, to: max(0.001, min(1, f))).currentPoint ?? .zero
    }

    /// A glyph's filled outlines (even-odd), fitted inside a square of side `side` centred on `c`, keeping its own shape.
    static func glyph(_ g: (slug: String, name: String, aspect: CGFloat, outlines: [[CGPoint]]), side: CGFloat, centre c: CGPoint) -> Path {
        let w = g.aspect >= 1 ? side : side * g.aspect, h = g.aspect >= 1 ? side / g.aspect : side
        var path = Path()
        for o in g.outlines where o.count > 2 {
            path.move(to: CGPoint(x: c.x - w / 2 + o[0].x * w, y: c.y - h / 2 + o[0].y * h))
            for q in o.dropFirst() { path.addLine(to: CGPoint(x: c.x - w / 2 + q.x * w, y: c.y - h / 2 + q.y * h)) }
            path.closeSubpath()
        }
        return path
    }

    static func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
}

struct PracticeMap: View {
    let course: Course
    let start: (CourseUnit) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began = Date()
    private let record = CourseRecord.shared

    private var colour: Color { Color(hex: PracticeMapArt.strokeColour) }
    private var total: Double { Double(PracticeMapArt.strokes.count - 1) * PracticeMapArt.stagger + PracticeMapArt.build }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(paused: reduceMotion)) { ctx in
                    let t = reduceMotion ? total : ctx.date.timeIntervalSince(began)
                    Canvas { g, sz in draw(&g, sz, t: t) }
                }
                ForEach(course.units) { u in island(u, size) }
            }
        }
        .frame(height: CGFloat(course.units.count) * 128 + 60)
        .clipShape(RoundedRectangle(cornerRadius: Candle.radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Candle.radius, style: .continuous).strokeBorder(Candle.hairline, lineWidth: 1) }
        .onAppear { began = .now }
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, t: Double) {
        let w = min(size.width, size.height) * PracticeMapArt.strokeWidth
        let gap = max(4, min(size.width, size.height) * 0.010)
        for (i, pts) in PracticeMapArt.strokes.enumerated() {
            let u = PracticeMapGeometry.ease((t - Double(i) * PracticeMapArt.stagger) / PracticeMapArt.build)
            guard u > 0 else { continue }
            let path = PracticeMapGeometry.stroke(pts, in: size).trimmedPath(from: 0, to: u)
            // the ground showing through where his strokes cross, then the stroke, as the piece draws them
            g.stroke(path, with: .color(Candle.bg), style: StrokeStyle(lineWidth: w + gap * 2, lineCap: .round, lineJoin: .round))
            g.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }

    /// One unit's island on his spine: one of his glyphs, gold when the unit is gold. Tap to play its next lesson (or its quiz).
    private func island(_ u: CourseUnit, _ size: CGSize) -> some View {
        let spine = PracticeMapGeometry.stroke(PracticeMapArt.strokes[0], in: size)
        let n = CGFloat(course.units.count)
        let c = PracticeMapGeometry.point(on: spine, at: (CGFloat(u.n) - 0.5) / n * 0.86 + 0.07)
        let glyph = PracticeMapArt.glyphs[(u.n - 1) % PracticeMapArt.glyphs.count]
        let open = record.isOpen(u, in: course), gold = record.isGold(u)
        let isNext = open && !gold && record.next(in: course)?.0.n == u.n
        let side: CGFloat = 64
        // not `.disabled`: that fades the whole island and the stroke showed through its disc (sweep 11-15); a closed unit ignores the tap
        let playable = open && !u.playableLessons.isEmpty
        return Button { if playable { start(u) } } label: {
            ZStack {
                Circle().fill(Candle.bg).overlay { Circle().strokeBorder(gold ? Candle.gold : (isNext ? Candle.goldHi : Candle.pillLine), lineWidth: isNext ? 3 : 1.5) }
                PracticeMapGeometry.glyph(glyph, side: side * 0.56, centre: CGPoint(x: side / 2, y: side / 2))
                    .fill(gold ? Candle.gold : (open ? Candle.ink : Candle.ink.opacity(0.35)), style: FillStyle(eoFill: true))
            }
            .frame(width: side, height: side)
            .overlay(alignment: .bottomTrailing) {
                Text("\(u.n)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(gold ? Color.black : Candle.ink)
                    .frame(width: 22, height: 22).background(gold ? Candle.gold : Candle.card, in: Circle())
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(playable ? [] : .isStaticText)
        .position(c)
        .accessibilityLabel("Unit \(u.n), \(u.title), \(gold ? "gold" : (open ? (isNext ? "next" : "open") : "not open yet")). Glyph: \(glyph.name).")
    }
}
