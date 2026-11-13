import SwiftUI

// The p5 sketches of the Mirror (components/art/sketches.ts: glyphPlotter, phyllotaxis, kinematicBeziersVoid) and the Golden Mend
// instrument (app/lab/golden-mend). p5's canvas that keeps what it drew is a bitmap here; the one that clears every frame is a SwiftUI Canvas.

/// A bitmap that keeps its marks between frames, in points (y down) at the screen's scale.
final class LabBitmap {
    private(set) var ctx: CGContext?
    private(set) var size: CGSize = .zero
    private(set) var scale: CGFloat = 2

    /// True when it was (re)made, so the sketch can reseed.
    @discardableResult func ensure(_ s: CGSize, scale sc: CGFloat, ground: CGColor) -> Bool {
        if s.width < 20 || s.height < 20 { return false }
        if ctx != nil, abs(s.width - size.width) < 1, abs(s.height - size.height) < 1 { return false }
        size = s; scale = sc
        let w = max(1, Int(s.width * sc)), h = max(1, Int(s.height * sc))
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: sc, y: -sc)
        c.setFillColor(ground); c.fill(CGRect(origin: .zero, size: s))
        c.setLineCap(.round)
        ctx = c
        return true
    }
    func image() -> CGImage? { ctx?.makeImage() }
}

private func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 255) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a / 255)
}

/// Runs a sketch at p5's 60 frames a second whatever the display's rate, and draws its bitmap.
struct LabBitmapSketch: View {
    let ground: CGColor
    let step: (CGContext, CGSize, Int) -> Void          // draws one frame (frame number from 1)
    let reseed: (CGSize) -> Void
    @State private var bitmap = LabBitmap()
    @State private var clock = LabFrameClock()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { gc, size in
                if bitmap.ensure(size, scale: displayScale, ground: ground) { reseed(size); clock.reset() }
                if let c = bitmap.ctx {
                    for _ in 0..<clock.due(tl.date) { step(c, size, clock.frame) }
                }
                if let img = bitmap.image() { gc.draw(Image(decorative: img, scale: displayScale), in: CGRect(origin: .zero, size: size)) }
            }
        }
        .drawingGroup(opaque: true)
    }
}

/// How many 60 fps frames are due since the last draw (never more than 4, so a pause does not race).
final class LabFrameClock {
    private var start: Date?
    private(set) var frame = 0
    func reset() { start = nil; frame = 0 }
    func due(_ now: Date) -> Int {
        guard let s = start else { start = now; frame = 1; return 1 }
        let target = Int(now.timeIntervalSince(s) * 60) + 1
        let n = max(0, min(4, target - frame))
        frame += n
        if target - frame > 4 { frame = target }   // after a pause: catch up without racing
        return n
    }
}

// MARK: - Glyph plotter (The Hand)

struct LabPlotterView: View {
    private struct Pen { var x: Double; var y: Double; var angle: Double; var weight: Double; var alpha: Double }
    private static let angles: [Double] = [0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 315, 330]
    @State private var pens = PenBox()
    private final class PenBox { var pens: [Pen] = [] }

    var body: some View {
        LabBitmapSketch(ground: rgba(10, 10, 10), step: { c, size, _ in
            let W = Double(size.width), H = Double(size.height)
            for i in pens.pens.indices {
                var pen = pens.pens[i]
                let rad = pen.angle * .pi / 180
                let nx = pen.x + cos(rad) * 2, ny = pen.y + sin(rad) * 2
                c.setStrokeColor(rgba(201, 168, 76, pen.alpha * 255))
                c.setLineWidth(pen.weight)
                c.move(to: CGPoint(x: pen.x, y: pen.y)); c.addLine(to: CGPoint(x: nx, y: ny)); c.strokePath()
                pen.x = nx; pen.y = ny
                if pen.x < -4 { pen.x = W + 4 }
                if pen.x > W + 4 { pen.x = -4 }
                if pen.y < -4 { pen.y = H + 4 }
                if pen.y > H + 4 { pen.y = -4 }
                let r = Double.random(in: 0..<1)
                if r < 0.01 { pen.x = .random(in: 0..<W); pen.y = .random(in: 0..<H); pen.angle = Self.angles.randomElement() ?? 0 }
                else if r < 0.06 {
                    let deltas: [Double] = [-45, -30, 0, 0, 30, 45]
                    let delta: Double = deltas.randomElement() ?? 0
                    let target = ((pen.angle + delta).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                    pen.angle = Self.angles.min(by: { abs($0 - target) < abs($1 - target) }) ?? 0
                }
                pens.pens[i] = pen
            }
        }, reseed: { size in
            pens.pens = (0..<4).map { _ in Pen(x: .random(in: 0..<Double(size.width)), y: .random(in: 0..<Double(size.height)), angle: Self.angles.randomElement() ?? 0, weight: .random(in: 0.6..<1.4), alpha: .random(in: 0.55..<0.85)) }
        })
    }
}

// MARK: - Phyllotaxis (The Unfolding)

struct LabPhyllotaxisView: View {
    @State private var drawn = Counter()
    private final class Counter { var n = 0 }
    private let golden = Double.pi * (3 - 5.0.squareRoot())
    private let maxN = 1800

    var body: some View {
        LabBitmapSketch(ground: rgba(14, 12, 8), step: { c, size, frame in
            let sc = Double(min(size.width, size.height)) * 0.0082
            let cx = Double(size.width) / 2, cy = Double(size.height) / 2
            for _ in 0..<4 where drawn.n < maxN {
                let i = Double(drawn.n)
                let angle = i * golden, r = sc * i.squareRoot()
                let x = cx + r * cos(angle), y = cy + r * sin(angle)
                let sz = 1.2 + (4.5 - 1.2) * i / Double(maxN)
                if drawn.n % 5 == 0 { c.setFillColor(rgba(241, 236, 225, 130)) } else { c.setFillColor(rgba(201, 168, 76, 90 + (220 - 90) * i / Double(maxN))) }
                c.fillEllipse(in: CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz))
                drawn.n += 1
            }
            if drawn.n >= maxN {
                let maxR = Double(min(size.width, size.height)) * 0.55
                for k in 0..<3 {
                    let r = ((Double(frame) + Double(k) * (maxR / 3.6)) * 1.2).truncatingRemainder(dividingBy: maxR)
                    let alpha = max(0, 32 - (r / maxR) * 34)
                    c.setStrokeColor(rgba(201, 168, 76, alpha)); c.setLineWidth(0.4)
                    c.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
            }
        }, reseed: { _ in drawn.n = 0 })
    }
}

// MARK: - Kinematic chains (The Following)

struct LabKinematicView: View {
    private struct Chain { var links: [CGPoint]; var rootX: Double; var rootY: Double; var phase: Double }
    private final class Box { var chains: [Chain] = []; var size: CGSize = .zero }
    @State private var box = Box()
    @State private var start = Date()
    private let linkLen = 50.0

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { gc, size in
                if box.size != size { reseed(size) }
                if box.chains.isEmpty { return }
                let frame = tl.date.timeIntervalSince(start) * 60
                let t = frame * 0.013
                gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)))
                for ci in box.chains.indices {
                    var ch = box.chains[ci]
                    ch.links[0].x = ch.rootX + sin(t * 0.72 + ch.phase) * 62 + sin(t * 1.31 + ch.phase * 1.4) * 26
                    ch.links[0].y = ch.rootY + cos(t * 0.55 + ch.phase) * 42 + cos(t * 1.13 + ch.phase * 0.9) * 18
                    for j in 1..<ch.links.count {
                        let prev = ch.links[j - 1], cur = ch.links[j]
                        let dx = Double(cur.x - prev.x), dy = Double(cur.y - prev.y)
                        let d = max(0.0001, (dx * dx + dy * dy).squareRoot())
                        ch.links[j] = CGPoint(x: Double(prev.x) + dx / d * linkLen, y: Double(prev.y) + dy / d * linkLen)
                    }
                    box.chains[ci] = ch
                    let curve = Self.spline(ch.links)
                    let gold = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255)
                    gc.stroke(curve, with: .color(gold.opacity(30 / 255)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    gc.stroke(curve, with: .color(gold.opacity(220 / 255)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    for (j, l) in ch.links.enumerated() {
                        let frac = Double(j) / Double(ch.links.count - 1)
                        let d = 4.5 + (1.2 - 4.5) * frac
                        gc.fill(Path(ellipseIn: CGRect(x: l.x - d / 2, y: l.y - d / 2, width: d, height: d)), with: .color(gold.opacity((210 - frac * 150) / 255)))
                    }
                }
            }
        }
        .drawingGroup(opaque: true)
    }

    private func reseed(_ size: CGSize) {
        box.size = size
        guard size.width > 20, size.height > 20 else { box.chains = []; return }
        box.chains = (0..<5).map { _ in
            let rx = Double.random(in: (Double(size.width) * 0.18)..<(Double(size.width) * 0.82)), ry = Double.random(in: (Double(size.height) * 0.22)..<(Double(size.height) * 0.78))
            return Chain(links: (0..<9).map { CGPoint(x: rx, y: ry - Double($0) * linkLen) }, rootX: rx, rootY: ry, phase: .random(in: 0..<(2 * .pi)))
        }
    }

    /// p5's curveVertex through every point, ends doubled: a Catmull-Rom spline as cubic segments.
    static func spline(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        let q = [pts[0]] + pts + [pts[pts.count - 1]]
        p.move(to: q[1])
        for i in 1..<(q.count - 2) {
            let p0 = q[i - 1], p1 = q[i], p2 = q[i + 1], p3 = q[i + 2]
            p.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6), control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return p
    }
}

// MARK: - Golden Mend: a heavy stone lifted by the voice (or a held touch); the strain cracks it, and gold seeps in

@MainActor @Observable final class GoldenMendModel {
    struct Crack { var x: Double; var y: Double; var len: Double; var gold: Double; var seg: [(dx: Double, dy: Double)] }
    var status = "Give it your voice — or press and hold."
    var mic = false
    var crackCount = 0
    @ObservationIgnored var lift = 0.0
    @ObservationIgnored var strain = 0.0
    @ObservationIgnored var push = 0.0
    @ObservationIgnored var hold = false
    @ObservationIgnored var cracks: [Crack] = []
    @ObservationIgnored var addCrackAt = 0.0
    @ObservationIgnored var size: CGSize = .zero

    func enableMic() async {
        do { try await VJAudio.shared.startMic(); mic = true; status = "Hold the note. Feel the weight lift." }
        catch { status = "No mic — press and hold the stone instead." }
    }

    /// One 60 fps tick (the page's loop body).
    func step() {
        let W = Double(size.width), H = Double(size.height)
        guard W > 0, H > 0 else { return }
        var target = hold ? 0.85 : 0
        if mic { let b = VJAudio.shared.read(); target = max(target, min(1, (b.bass * 0.4 + b.mid * 0.6) * 1.25)) }
        push += (target - push) * 0.12
        lift += (push - lift) * 0.05
        lift = max(0, min(1, lift))
        if push > 0.35 && lift > 0.35 {
            strain += push * 0.016
            if strain > addCrackAt {
                addCrackAt += 0.6 + Double.random(in: 0..<0.5)
                let cx = W / 2 + (Double.random(in: 0..<1) - 0.5) * W * 0.34
                let cy = H * 0.62 + (Double.random(in: 0..<1) - 0.5) * H * 0.22
                var a = Double.random(in: 0..<(2 * .pi))
                var seg: [(dx: Double, dy: Double)] = []
                for _ in 0..<6 { a += (Double.random(in: 0..<1) - 0.5) * 1.1; seg.append((cos(a) * (10 + Double.random(in: 0..<18)), sin(a) * (10 + Double.random(in: 0..<18)))) }
                cracks.append(Crack(x: cx, y: cy, len: 0, gold: 0, seg: seg))
                crackCount = cracks.count
            }
        } else { strain *= 0.985 }
        for i in cracks.indices {
            cracks[i].gold += (min(1, strain * 0.5) - cracks[i].gold) * 0.03
            cracks[i].len = min(1, cracks[i].len + 0.03)
        }
    }
}

struct LabGoldenMendView: View {
    @State private var m = GoldenMendModel()
    private let obsidian = Color(hex: 0x0e0c08)

    var body: some View {
        ZStack {
            obsidian.ignoresSafeArea()
            TimelineView(.animation) { _ in
                Canvas { gc, size in draw(&gc, size) }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in m.hold = true }.onEnded { _ in m.hold = false })
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text("Golden Mend").font(.system(size: 28, design: .serif).italic()).foregroundStyle(PLG.gold.opacity(0.9))
                Text(m.status).font(.system(size: 10.5)).tracking(1.8).foregroundStyle(PLG.gold.opacity(0.5)).frame(maxWidth: 320, alignment: .leading)
            }
            .padding(.leading, 20).padding(.bottom, 26).frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
            if !m.mic {
                VStack { LabPill(title: "Lift with your voice", symbol: "mic") { Task { await m.enableMic() } }.padding(.top, 60); Spacer() }
            }
        }
        .task {
            var last = Date()
            var acc = 0.0
            while !Task.isCancelled {
                let now = Date(); acc += now.timeIntervalSince(last) * 60; last = now
                var n = 0
                while acc >= 1 && n < 4 { m.step(); acc -= 1; n += 1 }
                if acc > 4 { acc = 0 }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
        .onDisappear { if m.mic { VJAudio.shared.stop() } }
        .sensoryFeedback(.impact(weight: .light), trigger: m.crackCount)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Golden Mend. \(m.status)")
    }

    private func draw(_ gc: inout GraphicsContext, _ size: CGSize) {
        m.size = size
        let W = size.width, H = size.height
        let gold = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255), goldHi = Color(red: 212 / 255, green: 184 / 255, blue: 106 / 255)
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(obsidian))
        var ground = Path(); ground.move(to: CGPoint(x: 0, y: H * 0.9)); ground.addLine(to: CGPoint(x: W, y: H * 0.9))
        gc.stroke(ground, with: .color(gold.opacity(0.14)), lineWidth: 1)

        let mw = min(W * 0.5, 360), mh = min(H * 0.42, 340)
        let restY = H * 0.9 - mh
        let lift = m.lift
        let y = restY - lift * (H * 0.22)
        let x = W / 2 - mw / 2
        // shadow on the ground, tightening as it lifts
        var sh = gc
        sh.addFilter(.blur(radius: 8))
        let sw = mw * (0.5 - lift * 0.18)
        sh.fill(Path(ellipseIn: CGRect(x: W / 2 - sw, y: H * 0.9 + 6 - 14, width: sw * 2, height: 28)), with: .color(.black.opacity(0.5 - lift * 0.3)))
        // the stone
        let body = Path(roundedRect: CGRect(x: x, y: y, width: mw, height: mh), cornerRadius: 18, style: .continuous)
        gc.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: 0x2a2e37), Color(hex: 0x20232a)]), startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + mh)))
        if m.strain > 0.1 { gc.stroke(body, with: .color(gold.opacity(min(0.5, m.strain * 0.4))), lineWidth: 2) }
        // cracks and the gold in them, in the stone's own frame
        for c in m.cracks {
            var px = x + (c.x - (W / 2 - mw / 2)), py = y + (c.y - restY)
            var path = Path(); path.move(to: CGPoint(x: px, y: py))
            var s = 0
            while Double(s) < Double(c.seg.count) * c.len { let sg = c.seg[min(s, c.seg.count - 1)]; px += sg.dx * 0.5; py += sg.dy * 0.5; path.addLine(to: CGPoint(x: px, y: py)); s += 1 }
            gc.stroke(path, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            if c.gold > 0.02 {
                gc.stroke(path, with: .color(gold.opacity(c.gold)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                gc.stroke(path, with: .color(goldHi.opacity(c.gold)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
            }
        }
        // how much you are lifting, right edge
        let barH = H * 0.5, barY = H * 0.25
        gc.fill(Path(roundedRect: CGRect(x: W - 26, y: barY, width: 8, height: barH), cornerRadius: 4), with: .color(gold.opacity(0.08)))
        let fh = barH * lift
        gc.fill(Path(roundedRect: CGRect(x: W - 26, y: barY + barH - fh, width: 8, height: fh), cornerRadius: 4), with: .color(gold))
    }
}
