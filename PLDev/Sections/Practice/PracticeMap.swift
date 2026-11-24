import SwiftUI

// One Teacher (S348·9a3e): the Path as fields of his curves. His rulings 11-15:
// - the curve is The Direction ("The piece named the direction"), his six strokes, generated into PracticeMapArt from his files;
// - "Lesson 1 rides stroke 1, lesson 2 stroke 2 … then when all are drawn it stays like the curve hero";
// - "Fields of 6 wrapped around the curve, appearing as lessons complete; the island appears in gold when that chapter is complete";
// - "Yes, one per unit" (his glyph is the island), "Yes, like the hero" (the finger pushes the curves), "Turns gold, keeps moving".
// So: a unit's lessons split into chapters of six. A finished lesson's stroke draws itself in and turns gold; the next lesson's stroke
// shows as a faint trace to tap; later strokes are not drawn yet. Drawn strokes live like the storefront's curve hero (SiteCurve.swift):
// each is a 24-point rope that springs home, drifts slowly, parts around the finger, carries the bend along itself, and cuts its own
// clearance channel through what lies beneath. Reduce Motion: no drift, no draw-in, the strokes rest where he drew them.

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

/// Six lessons of one unit: one field.
struct PracticeChapter: Identifiable {
    let unit: Int
    let index: Int          // 0-based chapter within its unit
    let count: Int          // chapters in the unit
    let lessons: [CourseLesson]
    var id: String { "\(unit)-\(index)" }

    static func of(_ u: CourseUnit) -> [PracticeChapter] {
        let ls = u.playableLessons, n = (ls.count + 5) / 6
        return (0..<n).map { i in PracticeChapter(unit: u.n, index: i, count: n, lessons: Array(ls[(i * 6)..<min(ls.count, i * 6 + 6)])) }
    }
}

/// The hero's rope physics (SiteCurve.swift `CurveRig`, its constants), with homes taken from his strokes instead of random cubics.
@MainActor final class FieldRig {
    static let n = 24, radius = 110.0, spring = 0.06, damp = 0.86, spread = 0.35, channel = 9.0
    struct Rope { var hx: [Double], hy: [Double], px: [Double], py: [Double], ox: [Double], oy: [Double], phase: Double, speed: Double }
    var ropes: [Rope] = []
    var size: CGSize = .zero
    var t = 0.0
    var mx = -1e9, my = -1e9
    var reduce = false
    private var acc = 0.0, last: Date?

    func setup(_ s: CGSize) {
        guard s.width > 1, s.height > 1, s != size || ropes.isEmpty else { return }
        size = s
        ropes = PracticeMapArt.strokes.enumerated().map { i, pts in
            let path = PracticeMapGeometry.stroke(pts, in: s)
            var hx = [Double](), hy = [Double]()
            for k in 0..<Self.n {
                let p = PracticeMapGeometry.point(on: path, at: CGFloat(k) / CGFloat(Self.n - 1))
                hx.append(Double(p.x)); hy.append(Double(p.y))
            }
            return Rope(hx: hx, hy: hy, px: hx, py: hy, ox: hx, oy: hy, phase: Double(i) * 1.7, speed: 0.6 + Double(i) * 0.11)
        }
    }

    func advance(_ now: Date) {
        defer { last = now }
        guard !reduce, let last else { return }
        acc += min(0.1, now.timeIntervalSince(last)) * 60
        var g = 0
        while acc >= 1, g < 4 { step(); acc -= 1; g += 1 }
    }

    /// One tick: each interior point springs toward its home plus a slow drift (the hero's breathing), the finger shoves it toward the
    /// radius edge, then the displacement is smoothed along the rope so a push travels. The two ends stay where he drew them.
    func step() {
        let N = Self.n
        for ri in ropes.indices {
            var r = ropes[ri]
            for k in 0..<N {
                let u = Double(k) / Double(N - 1), s = r.speed * t * 0.008
                let amp = 14 * sin(.pi * u)
                let tx = r.hx[k] + sin(s * 1.1 + r.phase + u * 3) * amp, ty = r.hy[k] + cos(s * 0.9 + r.phase * 1.3 + u * 2.4) * amp
                if k == 0 || k == N - 1 { r.px[k] = r.hx[k]; r.py[k] = r.hy[k]; r.ox[k] = r.hx[k]; r.oy[k] = r.hy[k]; continue }
                let vx = (r.px[k] - r.ox[k]) * Self.damp, vy = (r.py[k] - r.oy[k]) * Self.damp
                r.ox[k] = r.px[k]; r.oy[k] = r.py[k]
                r.px[k] += vx + (tx - r.px[k]) * Self.spring; r.py[k] += vy + (ty - r.py[k]) * Self.spring
                let qx = r.px[k] - mx, qy = r.py[k] - my, q2 = qx * qx + qy * qy
                if q2 < Self.radius * Self.radius && q2 > 0.01 {
                    let dl = q2.squareRoot(), f = ((Self.radius - dl) / dl) * 0.35
                    r.px[k] += qx * f; r.py[k] += qy * f
                }
            }
            for k in 1..<(N - 1) {
                let dx = (r.px[k - 1] - r.hx[k - 1] + r.px[k + 1] - r.hx[k + 1]) * 0.5 - (r.px[k] - r.hx[k])
                let dy = (r.py[k - 1] - r.hy[k - 1] + r.py[k + 1] - r.hy[k + 1]) * 0.5 - (r.py[k] - r.hy[k])
                r.px[k] += dx * Self.spread; r.py[k] += dy * Self.spread
            }
            ropes[ri] = r
        }
        t += 1
    }

    func path(_ i: Int) -> Path {
        let r = ropes[i], N = Self.n
        var p = Path()
        p.move(to: CGPoint(x: r.px[0], y: r.py[0]))
        for k in 1..<(N - 1) {
            p.addQuadCurve(to: CGPoint(x: (r.px[k] + r.px[k + 1]) * 0.5, y: (r.py[k] + r.py[k + 1]) * 0.5), control: CGPoint(x: r.px[k], y: r.py[k]))
        }
        p.addLine(to: CGPoint(x: r.px[N - 1], y: r.py[N - 1]))
        return p
    }

    /// The rope closest to a point, if within reach of a finger.
    func hit(_ p: CGPoint, among idx: [Int]) -> Int? {
        var best: (Int, Double)?
        for i in idx where i < ropes.count {
            let r = ropes[i]
            for k in 0..<Self.n {
                let d = hypot(r.px[k] - Double(p.x), r.py[k] - Double(p.y))
                if d < 34, d < (best?.1 ?? .infinity) { best = (i, d) }
            }
        }
        return best?.0
    }
}

/// Lessons whose draw-in he has already seen, so a finished lesson draws itself in once, on the first return to the Path.
enum FieldSeen {
    static var set: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "course.map.seen") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "course.map.seen") }
    }
}

struct PracticeField: View {
    let unit: CourseUnit
    let chapter: PracticeChapter
    let open: Bool
    let play: (CourseLesson) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rig = FieldRig()
    @State private var drawing: [Int: Date] = [:]   // stroke index -> when its draw-in began
    @State private var dragged = false
    private let record = CourseRecord.shared

    private var done: [Bool] { chapter.lessons.map { record.isDone(unit.n, $0.n) } }
    private var nextIndex: Int? { open ? done.firstIndex(of: false) : nil }
    private var chapterGold: Bool { !done.isEmpty && done.allSatisfy { $0 } }
    private var glyph: (slug: String, name: String, aspect: CGFloat, outlines: [[CGPoint]]) { PracticeMapArt.glyphs[(unit.n - 1) % PracticeMapArt.glyphs.count] }
    private var violet: Color { Color(hex: PracticeMapArt.strokeColour) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                island
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.count > 1 ? "\(unit.title) · chapter \(chapter.index + 1) of \(chapter.count)" : unit.title).candleH2()
                    Text(status).candleHint()
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                TimelineView(.animation(paused: reduceMotion)) { tl in
                    Canvas { ctx, size in
                        rig.reduce = reduceMotion
                        rig.setup(size)
                        rig.advance(tl.date)
                        draw(&ctx, size: size, now: tl.date)
                    }
                }
                .contentShape(Rectangle())
                // simultaneous, not exclusive: the field sits inside the scrolling Path, so the page must still scroll under the thumb
                .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        rig.mx = v.location.x; rig.my = v.location.y
                        if hypot(v.translation.width, v.translation.height) > 10 { dragged = true }
                    }
                    .onEnded { v in
                        rig.mx = -1e9; rig.my = -1e9
                        defer { dragged = false }
                        guard !dragged else { return }
                        let tappable = chapter.lessons.indices.filter { done[$0] || $0 == nextIndex }
                        if let i = rig.hit(v.location, among: tappable) { play(chapter.lessons[i]) }
                    })
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: Candle.radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Candle.radius, style: .continuous).strokeBorder(Candle.hairline, lineWidth: 1) }
            .accessibilityElement()
            .accessibilityLabel("\(unit.title), chapter \(chapter.index + 1): \(done.filter { $0 }.count) of \(done.count) lessons done")
            .accessibilityAction(named: "Play the next lesson") { if let i = nextIndex { play(chapter.lessons[i]) } }
        }
        .opacity(open ? 1 : 0.55)
        .onAppear { startDrawIns() }
    }

    private var status: String {
        let d = done.filter { $0 }.count
        if chapterGold { return "Complete. All \(done.count) lessons drawn." }
        if !open { return "Opens when the unit before it has every lesson played." }
        if let i = nextIndex { return "\(d) of \(done.count) drawn. Next: lesson \(chapter.lessons[i].n), tap its trace or the glyph." }
        return "\(d) of \(done.count) drawn."
    }

    /// The unit's glyph; gold once every lesson of this chapter is drawn. Tapping it plays the chapter's next lesson.
    private var island: some View {
        let side: CGFloat = 56
        return Button { if let i = nextIndex { play(chapter.lessons[i]) } } label: {
            ZStack {
                Circle().fill(Candle.bg).overlay { Circle().strokeBorder(chapterGold ? Candle.gold : (nextIndex != nil ? Candle.goldHi : Candle.pillLine), lineWidth: nextIndex != nil ? 2.5 : 1.5) }
                PracticeMapGeometry.glyph(glyph, side: side * 0.56, centre: CGPoint(x: side / 2, y: side / 2))
                    .fill(chapterGold ? Candle.gold : (open ? Candle.ink : Candle.ink.opacity(0.4)), style: FillStyle(eoFill: true))
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(glyph.name). \(chapterGold ? "Chapter complete" : (nextIndex != nil ? "Play the next lesson" : "Not open yet"))")
    }

    /// Finished lessons he has not watched draw in yet: draw them now, one after another at the piece's stagger.
    private func startDrawIns() {
        var seen = FieldSeen.set
        var order = 0
        for (i, l) in chapter.lessons.enumerated() where done[i] {
            let key = "\(unit.n)-\(l.n)"
            if seen.contains(key) || reduceMotion { continue }
            drawing[i] = Date().addingTimeInterval(Double(order) * PracticeMapArt.stagger)
            order += 1
            seen.insert(key)
        }
        FieldSeen.set = seen
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let w = min(size.width, size.height) * PracticeMapArt.strokeWidth
        constellation(&ctx, size: size)
        for i in chapter.lessons.indices where i < rig.ropes.count {
            let path = rig.path(i)
            if done[i] {
                let u = drawing[i].map { PracticeMapGeometry.ease(now.timeIntervalSince($0) / PracticeMapArt.build) } ?? 1
                guard u > 0 else { continue }
                let shown = u < 1 ? path.trimmedPath(from: 0, to: u) : path
                var cut = ctx
                cut.blendMode = .destinationOut   // the hero's channel: this stroke's clearance through everything beneath it
                cut.stroke(shown, with: .color(.black), style: StrokeStyle(lineWidth: w + FieldRig.channel * 2, lineCap: .butt))
                // drawing in, it is his violet; landed, it turns gold
                ctx.stroke(shown, with: .color(u < 1 ? violet : Candle.gold), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            } else if i == nextIndex {
                ctx.stroke(path, with: .color(Candle.ink.opacity(0.22)), style: StrokeStyle(lineWidth: max(3, w * 0.18), lineCap: .round, dash: [2, 9]))
            }
        }
        // glyph stops (his ruling 11-15 "On the curves, as stops"): each drawn lesson's curve, and the next one's trace, ends at one of
        // his glyphs; a tap on the stop lands on its rope, so it plays that lesson like a tap on the curve
        for i in chapter.lessons.indices where i < rig.ropes.count && (done[i] || i == nextIndex) {
            let c = PracticeMapGeometry.point(on: rig.path(i), at: 0.84), r: CGFloat = 15
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(ring, with: .color(Candle.bg))
            ctx.stroke(ring, with: .color(done[i] ? Candle.gold : Candle.goldHi.opacity(0.7)), lineWidth: done[i] ? 2 : 1.5)
            let g = PracticeMapArt.glyphs[(unit.n * 6 + i) % PracticeMapArt.glyphs.count]
            ctx.fill(PracticeMapGeometry.glyph(g, side: r * 1.1, centre: c), with: .color(done[i] ? Candle.gold : Candle.ink.opacity(0.7)), style: FillStyle(eoFill: true))
        }
    }

    /// The constellation (his ruling 11-15: "each lesson is a star, each star is a glyph, the total is the amount completed"): every lesson
    /// he has finished in the whole course is one small glyph of his, lit behind the curves at a place fixed by its lesson, joined in the
    /// order of the course; the count of lit stars is the number finished. Nothing shows for lessons not yet done.
    private func constellation(_ ctx: inout GraphicsContext, size: CGSize) {
        let keys = record.lessonsDone.sorted { a, b in
            let x = a.split(separator: "-").compactMap { Int($0) }, y = b.split(separator: "-").compactMap { Int($0) }
            return x.lexicographicallyPrecedes(y)
        }
        guard !keys.isEmpty else { return }
        func spot(_ k: String) -> CGPoint {
            var h: UInt64 = 1469598103934665603
            for u in k.utf8 { h = (h ^ UInt64(u)) &* 1099511628211 }
            let fx = CGFloat(h & 0xFFFF) / 65535, fy = CGFloat((h >> 16) & 0xFFFF) / 65535
            return CGPoint(x: (0.06 + 0.88 * fx) * size.width, y: (0.06 + 0.88 * fy) * size.height)
        }
        let pts = keys.map(spot)
        var line = Path(); line.move(to: pts[0]); pts.dropFirst().forEach { line.addLine(to: $0) }
        ctx.stroke(line, with: .color(Candle.gold.opacity(0.14)), lineWidth: 1)
        for (j, p) in pts.enumerated() {
            let g = PracticeMapArt.glyphs[j % PracticeMapArt.glyphs.count]
            ctx.fill(PracticeMapGeometry.glyph(g, side: 11, centre: p), with: .color(Candle.goldHi.opacity(0.45)), style: FillStyle(eoFill: true))
        }
        ctx.draw(Text("\(keys.count) lit").font(Font.pl(size: 11).monospacedDigit()).foregroundStyle(Candle.goldHi.opacity(0.6)),
                 at: CGPoint(x: size.width - 10, y: size.height - 10), anchor: .bottomTrailing)
    }
}
