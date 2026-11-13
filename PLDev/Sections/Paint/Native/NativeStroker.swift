import CoreGraphics
import Foundation

/// One dab from the stroke generator: where, how pressed, how big (a factor of the brush radius), turned how far, how opaque.
/// `tw` is the companion band beside it; `span > 0` marks the filled middle of a band; `edge` marks a band's edge line.
struct Dab: Sendable {
    var x: Double, y: Double, p: Double, f: Double, ang: Double, am: Double
    var tw: Twin?
    var dir: Double
    var span: Double
    var edge: Bool
}
struct Twin: Sendable { var dx: Double, dy: Double, f: Double }

/// Port of the laptop's `Stroker` (`C:\dev\pl-paint\src\brush.js`): pen points in, dabs out. Spacing and its jitter, StreamLine and
/// Stabilization smoothing, taper, flare, caps, swell, tremor, speed, tilt, scatter, twin, parallel lines, and band mode. The same stroke
/// always jitters the same way (seeded), so a replay lands on the same pixels. Pure: no drawing, no UIKit.
struct NativeStroker: Sendable {
    let B: Brush
    let size: Double
    var total: Double?
    private(set) var dist = 0.0
    private var tab: [Double]
    private var seed = 7919.0
    private var last: (x: Double, y: Double, p: Double)?
    private var rem = 0.0
    private var sp: (Double, Double)?
    private var win: [(Double, Double)] = []
    private var speed = 0.0
    private var tPrev: Double?
    private var dir = 0.0
    private var tilt: (Double, Double)?
    private var pend: (Double, Double, Double)?
    private var tubeSide: Double?
    private var dirS: Double?
    private var fprev: (x: Double, y: Double, a: Double, d: Double)?
    private let tau = Double.pi * 2

    init(_ B: Brush, size: Double, total: Double? = nil) {
        self.B = B; self.size = size; self.total = total
        var q = 90210.0
        tab = (0..<64).map { _ in q = (q * 16807).truncatingRemainder(dividingBy: 2147483647); return q / 1073741823.5 - 1 }
    }

    private mutating func rnd() -> Double { seed = (seed * 16807).truncatingRemainder(dividingBy: 2147483647); return seed / 2147483647 }
    private func vn(_ x: Double, _ off: Int) -> Double {
        let i = Int(floor(x)), t = x - floor(x), a = tab[(i + off) & 63], c = tab[(i + off + 1) & 63], u = t * t * (3 - 2 * t)
        return a + (c - a) * u
    }
    private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }

    private func sizeFactor(_ dist: Double) -> Double {
        var f = 1.0
        if B.n("taperStart") > 0 { f *= min(1, 0.12 + dist / (B.n("taperStart") * size * 6)) }
        if B.n("taperEnd") > 0, let total { f *= min(1, 0.05 + (total - dist) / (B.n("taperEnd") * size * 6)) }
        if B.n("speedSize") > 0 { f *= 1 - B.n("speedSize") * clamp(speed / 3, 0, 0.7) }
        let L = size * 1.3
        func cap(_ kind: String, _ u: Double) -> Double { kind == "diamond" ? u : pow(u, 0.6) }   // an end that folds closed
        if B.n("flareStart") > 0 { f *= 1 + B.n("flareStart") * max(0, 1 - dist / (size * 1.4)) }
        let cs = B.t("capStart")
        if !cs.isEmpty, cs != "flat", dist < L { f *= cap(cs, dist / L) }
        if let total {
            let r = total - dist
            if B.n("flareEnd") > 0 { f *= 1 + B.n("flareEnd") * max(0, 1 - r / (size * 1.4)) }
            let ce = B.t("capEnd")
            if !ce.isEmpty, ce != "flat", r < L { f *= cap(ce, max(0, r / L)) }
        }
        if B.n("swell") > 0 { f *= 1 + B.n("swell") * 0.45 * vn(dist / (size * (B.n("swellLen") == 0 ? 6 : B.n("swellLen"))), 3) }
        if B.n("tremor") > 0 { f *= 1 + B.n("tremor") * (vn(dist / (size * 0.8), 17) - vn(dist / (size * 0.8), 41)) }   // each rail shakes on its own
        return max(0.05, f)
    }

    private func opacityMul(_ p: Double, _ dist: Double) -> Double {
        var m = 1 - B.n("pressOp") + B.n("pressOp") * pow(p, B.n("pressCurve"))
        if B.n("fall") > 0 { m *= max(0, 1 - dist / (B.n("fall") * size * 40)) }
        return m
    }

    private mutating func step(_ r: Double) -> Double { max(1, r * 2 * B.n("spacing") * (1 + (rnd() - 0.5) * 2 * B.n("spacingJit"))) }

    private mutating func dab(_ x: Double, _ y: Double, _ p: Double, _ dist: Double, _ out: inout [Dab]) {
        let tiltBoost: Double = {
            guard let t = tilt, B.n("tiltSize") > 0 else { return 1 }
            return 1 + B.n("tiltSize") * min(1, hypot(t.0, t.1) / 90) * 1.5
        }()
        let f = sizeFactor(dist) * tiltBoost, r = B.radius(size: size, pressure: p, f: f), perp = dir + .pi / 2
        var ox = 0.0, oy = 0.0
        if B.n("jitLat") != 0 { let j = (rnd() - 0.5) * 2 * B.n("jitLat") * size; ox += cos(perp) * j; oy += sin(perp) * j }
        if B.n("jitLin") != 0 { let j = (rnd() - 0.5) * 2 * B.n("jitLin") * size; ox += cos(dir) * j; oy += sin(dir) * j }
        if B.n("tremor") > 0 { let j = (vn(dist / (size * 0.8), 17) + vn(dist / (size * 0.8), 41)) / 2 * B.n("tremor") * size; ox += cos(perp) * j; oy += sin(perp) * j }
        if B.n("scatter") != 0 { let a = rnd() * tau, d = rnd() * B.n("scatter") * r * 2; ox += cos(a) * d; oy += sin(a) * d }
        let strokeRot = B.t("rotMode") == "stroke"
        var ang = (strokeRot ? dir : 0) + B.n("angle") * .pi / 180
        if B.shape == "tube" {   // the light stays on one side of the tube for the whole stroke
            if tubeSide == nil { tubeSide = cos(dir) < 0 ? .pi : 0 }
            ang += tubeSide ?? 0
        }
        if let t = tilt, B.usesTilt {
            let m = min(1, hypot(t.0, t.1) / 90)
            if B.n("tiltAngle") > 0, m > 0.05 {
                var d = atan2(t.1, t.0) - ang; d = atan2(sin(d), cos(d))
                ang += d * min(1, B.n("tiltAngle") * m * 3)
            }
        }
        var tw: Twin?
        if B.n("twin") > 0 {
            let rt = r * B.n("twin"), off = (r + rt + B.n("twinGap") * size) * (B.t("twinSide") == "left" ? -1 : 1)
            tw = Twin(dx: cos(perp) * off, dy: sin(perp) * off, f: f * B.n("twin"))
        }
        let N = max(1, Int(B.n("lines").rounded()))
        let W = 2 * r + (B.n("twin") > 0 ? B.n("twinGap") * size + 2 * r * B.n("twin") : 0)
        let pitch = W + B.n("lineGap") * size, am = opacityMul(p, dist)
        if N > 1, B.t("gapFill") == "colour", B.n("edge") > 0 {   // band mode: the size is the whole band, a thin line down each edge, the middle filled
            let R = r, rl = R * B.n("edge"), off = max(0, R - rl), er = B.n("edgeRound")
            if dirS == nil { dirS = dir }
            let s0 = dirS ?? dir
            let dd = atan2(sin(dir - s0), cos(dir - s0)), dStep = dd * (er > 0 ? 1 - exp(-1 / (1 + er * 5)) : 1)
            let len = max(2, B.n("spacing") * size * 1.6)
            let n = er > 0 ? max(1, min(14, Int(ceil(abs(dStep) * R / max(2, len * 0.45))))) : 1
            let fe = f * B.n("edge") * (1 + B.n("edgeSwell") * min(1.3, abs(dd) * 4))
            let dE = s0 + dStep, aE = ang + (strokeRot ? dE - dir : 0), X1 = x + ox, Y1 = y + oy
            if let fp = fprev {
                let da = atan2(sin(aE - fp.a), cos(aE - fp.a)), run = hypot(X1 - fp.x, Y1 - fp.y) + off * abs(da)
                let m = max(1, min(64, Int(ceil(run / (len * 0.5)))))
                let dd2 = atan2(sin(dE - fp.d), cos(dE - fp.d))
                for k in 1...m { let u = Double(k) / Double(m); out.append(Dab(x: fp.x + (X1 - fp.x) * u, y: fp.y + (Y1 - fp.y) * u, p: p, f: f, ang: fp.a + da * u, am: am, tw: nil, dir: fp.d + dd2 * u, span: off * 2, edge: false)) }
            } else {
                out.append(Dab(x: X1, y: Y1, p: p, f: f, ang: aE, am: am, tw: nil, dir: dE, span: off * 2, edge: false))
            }
            fprev = (X1, Y1, aE, dE)
            for j in 1...n {
                let dj = s0 + dStep * Double(j) / Double(n), angS = ang + (strokeRot ? dj - dir : 0), pj = dj + .pi / 2
                for sgn in [-1.0, 1.0] { out.append(Dab(x: x + ox + cos(pj) * off * sgn, y: y + oy + sin(pj) * off * sgn, p: p, f: fe, ang: angS, am: am, tw: tw, dir: dj, span: 0, edge: true)) }
            }
            dirS = dE
            return
        }
        if N > 1, B.t("gapFill") == "colour" { out.append(Dab(x: x + ox, y: y + oy, p: p, f: f, ang: ang, am: am, tw: nil, dir: dir, span: Double(N - 1) * pitch, edge: false)) }   // the middle first, so the lines lie over its edges
        for li in 0..<N {
            let lo = (Double(li) - Double(N - 1) / 2) * pitch
            out.append(Dab(x: x + ox + cos(perp) * lo, y: y + oy + sin(perp) * lo, p: p, f: f, ang: ang, am: am, tw: tw, dir: dir, span: 0, edge: false))   // parallel lines move together, as one hand draws them
        }
    }

    /// A tap that never moved still lays its one dab.
    mutating func flush() -> [Dab] {
        guard let q = pend else { return [] }
        pend = nil
        var out: [Dab] = []; dab(q.0, q.1, q.2, 0, &out); return out
    }

    /// One pen point. `t` is milliseconds since the stroke began. Returns the dabs it lays down.
    mutating func add(x: Double, y: Double, p: Double, t: Double, tilt tl: (Double, Double)? = nil) -> [Dab] {
        if let tl { tilt = tl }
        let stream = B.n("stream")
        if sp == nil { sp = (x, y) }
        let k = 1 - 0.92 * stream
        sp = (sp!.0 + (x - sp!.0) * k, sp!.1 + (y - sp!.1) * k)   // StreamLine: the line follows the pen with a little lag
        var sx = sp!.0, sy = sp!.1
        let sb = B.n("stab")
        if sb > 0 {   // Stabilization: a moving average
            let n = 1 + Int((sb * 10).rounded())
            win.append((sx, sy)); if win.count > n { win.removeFirst() }
            sx = win.reduce(0) { $0 + $1.0 } / Double(win.count); sy = win.reduce(0) { $0 + $1.1 } / Double(win.count)
        }
        guard let l = last else {
            last = (sx, sy, p); tPrev = t
            rem = step(B.radius(size: size, pressure: p, f: sizeFactor(0)))
            pend = (sx, sy, p)   // the first dab waits until the pen has moved, so it knows which way the stroke runs
            return []
        }
        let dx = sx - l.x, dy = sy - l.y, d = hypot(dx, dy)
        if d < 0.01 { return [] }
        let dt = max(1, t - (tPrev ?? t)); speed = speed * 0.7 + (d / dt) * 0.3; tPrev = t; dir = atan2(dy, dx)
        var out = flush()
        var pos = rem
        while pos <= d {
            let u = pos / d, pp = l.p + (p - l.p) * u
            dab(l.x + dx * u, l.y + dy * u, pp, dist + pos, &out)
            pos += step(B.radius(size: size, pressure: pp, f: sizeFactor(dist + pos)))
        }
        rem = pos - d; dist += d; last = (sx, sy, p)
        return out
    }
}
