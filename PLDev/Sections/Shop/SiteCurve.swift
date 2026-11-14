import SwiftUI

/// The Curve: the homepage's gold curve hero alone, full screen on black (the site's `/curve-live`, `components/art/GoldCurves.tsx`, ported
/// line for line). Fifteen drifting cubics, each sampled into a 24-point rope: ends held, interior points spring back toward the drawn spot
/// (Verlet, damped), a finger pushes them aside and the push spreads along the rope. Each curve punches its own clearance corridor through
/// everything drawn beneath it (destination-out), so crossings read over and under with a gap, never a blend. Draw order is depth: thin
/// echoes first, the heavy bands last. Reduce Motion draws one still frame and nothing moves.
@MainActor final class CurveRig {
    static let channel = 9.0, n = 24, radius = 110.0, spring = 0.06, damp = 0.86, spread = 0.35, count = 15

    struct Curve {
        var sweep: Bool, phase: Double, speed: Double, width: Double, opacity: Double
        var sxB: Double, syB: Double, exB: Double, eyB: Double
        var sdx: Double, sdy: Double, edx: Double, edy: Double
        var c1xB: Double, c1yB: Double, c2xB: Double, c2yB: Double
        var c1xa: Double, c1ya: Double, c2xa: Double, c2ya: Double
        var c1xf: Double, c1yf: Double, c2xf: Double, c2yf: Double
        var headX: Double, headY: Double, travelDist: Double, travelDur: Double, travelStart: Double
        var px = [Double](repeating: 0, count: CurveRig.n), py = [Double](repeating: 0, count: CurveRig.n)
        var ox = [Double](repeating: 0, count: CurveRig.n), oy = [Double](repeating: 0, count: CurveRig.n)
        var gx = [Double](repeating: 0, count: CurveRig.n), gy = [Double](repeating: 0, count: CurveRig.n)
        var live = false
    }

    var curves: [Curve] = []
    var size: CGSize = .zero
    var t = 0.0
    var mx = -1e9, my = -1e9          // the finger, in points; -1e9 = none
    var reduce = false
    private var acc = 0.0, last: Date?

    private func rand(_ a: Double, _ b: Double) -> Double { a + Double.random(in: 0..<1) * (b - a) }

    private func endpoints(_ w: Double, _ h: Double, _ dir: Int) -> (Double, Double, Double, Double) {
        let m = 140.0
        switch dir {
        case 0: return (rand(-m * 2, -m), rand(-h * 0.2, h * 1.2), rand(w + m, w + m * 2), rand(-h * 0.2, h * 1.2))
        case 1: return (rand(-w * 0.2, w * 1.2), rand(-m * 2, -m), rand(-w * 0.2, w * 1.2), rand(h + m, h + m * 2))
        case 2: return (rand(-m * 2, -m), rand(-h * 0.1, h * 0.6), rand(-w * 0.1, w * 1.1), rand(h + m, h + m * 2))
        default: return (rand(-w * 0.1, w * 1.1), rand(-m * 2, -m), rand(w + m, w + m * 2), rand(-h * 0.1, h * 1.1))
        }
    }

    func setup(_ s: CGSize) {
        guard s.width > 1, s.height > 1, s != size || curves.isEmpty else { return }
        size = s
        let w = Double(s.width), h = Double(s.height)
        curves = (0..<Self.count).map { i in
            let r = Double.random(in: 0..<1)
            let dir = r < 0.45 ? 0 : r < 0.7 ? 1 : r < 0.85 ? 2 : 3
            let p = endpoints(w, h, dir)
            let thick = i < 5, med = i >= 5 && i < 10
            let dx0 = p.2 - p.0, dy0 = p.3 - p.1, hl = max(0.0001, hypot(dx0, dy0))
            return Curve(
                sweep: i < 4, phase: rand(0, .pi * 2), speed: rand(0.15, 0.5),
                width: thick ? rand(5, 12) : med ? rand(2, 4.5) : rand(0.4, 1.5),
                opacity: thick ? rand(0.28, 0.55) : med ? rand(0.13, 0.28) : rand(0.05, 0.15),
                sxB: p.0, syB: p.1, exB: p.2, eyB: p.3,
                sdx: rand(15, 40), sdy: rand(15, 40), edx: rand(15, 40), edy: rand(15, 40),
                c1xB: rand(w * 0.05, w * 0.95), c1yB: rand(h * 0.05, h * 0.95), c2xB: rand(w * 0.05, w * 0.95), c2yB: rand(h * 0.05, h * 0.95),
                c1xa: rand(80, 320), c1ya: rand(80, 320), c2xa: rand(80, 320), c2ya: rand(80, 320),
                c1xf: rand(0.3, 1.9), c1yf: rand(0.3, 1.9), c2xf: rand(0.3, 1.9), c2yf: rand(0.3, 1.9),
                headX: dx0 / hl, headY: dy0 / hl, travelDist: rand(70, 170), travelDur: rand(260, 420), travelStart: 0)
        }
        step()   // the first frame, so a still frame has ropes to draw
    }

    /// Advance by real time at the web's pace (one tick per 60th of a second), so a 120 Hz screen is as smooth and no faster.
    func advance(_ now: Date) {
        defer { last = now }
        guard !reduce, let last else { return }
        acc += min(0.1, now.timeIntervalSince(last)) * 60
        var guardN = 0
        while acc >= 1, guardN < 4 { step(); acc -= 1; guardN += 1 }
    }

    /// One tick of the web's `frame()`: place every drifting cubic, then solve its rope toward it.
    func step() {
        let w = Double(size.width), h = Double(size.height), N = Self.n
        for ci in curves.indices {
            var c = curves[ci]
            let sx: Double, sy: Double, ex: Double, ey: Double, c1x: Double, c1y: Double, c2x: Double, c2y: Double
            if c.sweep {
                if t - c.travelStart > c.travelDur {   // exited: respawn from a fresh entry
                    let p2 = endpoints(w, h, Int(rand(0, 4)))
                    let dx0 = p2.2 - p2.0, dy0 = p2.3 - p2.1, hl = max(0.0001, hypot(dx0, dy0))
                    c.sxB = p2.0; c.syB = p2.1; c.exB = p2.2; c.eyB = p2.3
                    c.c1xB = rand(w * 0.05, w * 0.95); c.c1yB = rand(h * 0.05, h * 0.95); c.c2xB = rand(w * 0.05, w * 0.95); c.c2yB = rand(h * 0.05, h * 0.95)
                    c.headX = dx0 / hl; c.headY = dy0 / hl
                    c.travelDist = rand(70, 170); c.travelDur = rand(260, 420); c.travelStart = t; c.live = false
                }
                let progress = min(1, max(0, (t - c.travelStart) / c.travelDur)), ease = 1 - pow(1 - progress, 3), d = ease * c.travelDist
                sx = c.sxB + c.headX * d; sy = c.syB + c.headY * d; ex = c.exB + c.headX * d; ey = c.eyB + c.headY * d
                c1x = c.c1xB + c.headX * d * 0.6; c1y = c.c1yB + c.headY * d * 0.6; c2x = c.c2xB + c.headX * d * 0.8; c2y = c.c2yB + c.headY * d * 0.8
            } else {
                let s = c.speed * t * 0.008, p = c.phase
                sx = c.sxB + sin(s * 0.2 + p) * c.sdx; sy = c.syB + cos(s * 0.17 + p * 1.1) * c.sdy
                ex = c.exB + sin(s * 0.18 + p * 0.8) * c.edx; ey = c.eyB + cos(s * 0.22 + p * 1.3) * c.edy
                c1x = c.c1xB + sin(s * c.c1xf + p) * c.c1xa; c1y = c.c1yB + cos(s * c.c1yf + p * 1.4) * c.c1ya
                c2x = c.c2xB + sin(s * c.c2xf + p * 0.6) * c.c2xa; c2y = c.c2yB + cos(s * c.c2yf + p * 1.8) * c.c2ya
            }
            for k in 0..<N {
                let u = Double(k) / Double(N - 1), v = 1 - u
                let a = v * v * v, b = 3 * v * v * u, dd = 3 * v * u * u, e = u * u * u
                let tx = a * sx + b * c1x + dd * c2x + e * ex, ty = a * sy + b * c1y + dd * c2y + e * ey
                c.gx[k] = tx; c.gy[k] = ty
                if !c.live || k == 0 || k == N - 1 { c.px[k] = tx; c.ox[k] = tx; c.py[k] = ty; c.oy[k] = ty; continue }
                let vx = (c.px[k] - c.ox[k]) * Self.damp, vy = (c.py[k] - c.oy[k]) * Self.damp
                c.ox[k] = c.px[k]; c.oy[k] = c.py[k]
                c.px[k] += vx + (tx - c.px[k]) * Self.spring; c.py[k] += vy + (ty - c.py[k]) * Self.spring
                let qx = c.px[k] - mx, qy = c.py[k] - my, q2 = qx * qx + qy * qy
                if q2 < Self.radius * Self.radius && q2 > 0.01 {   // the finger shoves the point out toward the radius edge
                    let dl = q2.squareRoot(), f = ((Self.radius - dl) / dl) * 0.35
                    c.px[k] += qx * f; c.py[k] += qy * f
                }
            }
            if c.live {   // let the bend travel along the rope: smooth the displacement from the drawn curve, not the positions
                for k in 1..<(N - 1) {
                    let dx = (c.px[k - 1] - c.gx[k - 1] + c.px[k + 1] - c.gx[k + 1]) * 0.5 - (c.px[k] - c.gx[k])
                    let dy = (c.py[k - 1] - c.gy[k - 1] + c.py[k + 1] - c.gy[k + 1]) * 0.5 - (c.py[k] - c.gy[k])
                    c.px[k] += dx * Self.spread; c.py[k] += dy * Self.spread
                }
            }
            c.live = !reduce
            curves[ci] = c
        }
        t += 1
    }

    private func path(_ c: Curve) -> Path {
        var p = Path(); let N = Self.n
        p.move(to: CGPoint(x: c.px[0], y: c.py[0]))
        for k in 1..<(N - 1) {
            p.addQuadCurve(to: CGPoint(x: (c.px[k] + c.px[k + 1]) * 0.5, y: (c.py[k] + c.py[k + 1]) * 0.5), control: CGPoint(x: c.px[k], y: c.py[k]))
        }
        p.addLine(to: CGPoint(x: c.px[N - 1], y: c.py[N - 1]))
        return p
    }

    func draw(_ ctx: inout GraphicsContext, rgb: Color) {
        let butt = StrokeStyle(lineWidth: 1, lineCap: .butt)
        for c in curves.reversed() {   // thin echoes first, heavy structure last: the heavy passes over
            let p = path(c)
            var cut = ctx
            cut.blendMode = .destinationOut   // the channel: punch this band's clearance out of everything beneath it
            var cs = butt; cs.lineWidth = c.width + Self.channel * 2
            cut.stroke(p, with: .color(.black), style: cs)
            var s = butt; s.lineWidth = c.width
            ctx.stroke(p, with: .color(rgb.opacity(c.opacity)), style: s)
        }
    }
}

struct CurveLiveView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rig = CurveRig()

    /// The site's DEFAULT_GOLD (`lib/brand-color.ts`); a signed-in member's own accent is a site-account feature this view does not have.
    private let gold = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                rig.reduce = reduceMotion
                rig.setup(size)
                rig.advance(tl.date)
                rig.draw(&ctx, rgb: gold)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in rig.mx = v.location.x; rig.my = v.location.y }
            .onEnded { _ in rig.mx = -1e9; rig.my = -1e9 })
        .navigationTitle("The Curve")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accessibilityLabel("Animated gold curves on black")
    }
}
