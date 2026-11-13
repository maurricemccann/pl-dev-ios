import CoreGraphics
import Foundation
import UIKit

/// Transform, as the laptop does it (`trEnter` ... `trCommit` in app.js): the layer's pixels (inside the selection, if there is one) are
/// lifted, shown floating, and put down again on Done. Free (sides stretch one way), Uniform (corners keep the shape), Distort (four
/// corners, with perspective) and Warp (a 4 x 4 grid of nodes the surface passes through).
@MainActor final class NativeTransform {
    enum Mode: String, CaseIterable { case free, uni, distort, warp }

    let layer: Int
    let src: CGImage                 // the lifted pixels, cropped to their box
    let w0: Double, h0: Double
    let home: CGPoint
    var cx: Double, cy: Double
    var sx = 1.0, sy = 1.0, fx = 1.0, fy = 1.0, rot = 0.0
    var pivot: CGPoint?
    var mode: Mode = .free
    var q: [CGPoint] = []            // distort corners (top-left, top-right, bottom-right, bottom-left)
    var q0: [CGPoint] = []
    var D: [CGPoint] = []            // warp: displacement of each of the 16 nodes
    var smooth = true                // bicubic or nearest
    var magnetic = false
    let before: Data                 // the layer before it was lifted
    let selBefore: NativeSelection.Snap?
    var drag: Drag?

    struct Drag {
        enum Kind { case qc(Int), qmove, wn(Int), wpull, edge(Int), piv, rotp, outside, move, rot, scale(Int) }
        var kind: Kind
        var x = 0.0, y = 0.0
        var q: [CGPoint] = []
        var d = CGPoint.zero
        var D: [CGPoint] = []
        var nodes: [CGPoint] = []
        var R = 0.0
        var a = 0.0, b = 0.0
        var opp = CGPoint.zero
        var rot0 = 0.0
        var v0 = CGPoint.zero
        var P = CGPoint.zero
        var c0 = CGPoint.zero
        var ph0 = 0.0
        var cx = 0.0, cy = 0.0
        var moved = false
    }

    init(layer: Int, src: CGImage, box: CGRect, before: Data, selBefore: NativeSelection.Snap?) {
        self.layer = layer; self.src = src; w0 = box.width; h0 = box.height
        cx = box.midX; cy = box.midY; home = CGPoint(x: box.midX, y: box.midY)
        self.before = before; self.selBefore = selBefore
    }

    static let node: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    private func turn(_ x: Double, _ y: Double, _ a: Double) -> (Double, Double) { (x * cos(a) - y * sin(a), x * sin(a) + y * cos(a)) }

    // MARK: geometry

    /// Where the lifted picture's point (u, v), each from 0 to 1, is now, for the plain scale and rotate transform.
    func aff(_ u: Double, _ v: Double) -> CGPoint {
        let (x, y) = turn((u - 0.5) * w0 * fx * sx, (v - 0.5) * h0 * fy * sy, rot)
        return CGPoint(x: cx + x, y: cy + y)
    }
    func corner(_ i: Int) -> CGPoint {
        let (a, b) = Self.node[i]
        let (x, y) = turn(a * sx * w0 / 2, b * sy * h0 / 2, rot)
        return CGPoint(x: cx + x, y: cy + y)
    }
    func rotNode(_ scale: Double) -> CGPoint { let (x, y) = turn(0, -(sy * h0 / 2 + 46 / scale), rot); return CGPoint(x: cx + x, y: cy + y) }
    func pivotNode(_ scale: Double) -> CGPoint { let (x, y) = turn(0, sy * h0 / 2 + 46 / scale, rot); return CGPoint(x: cx + x, y: cy + y) }
    func edgeNodes() -> [CGPoint] {
        [(0.0, -1.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0)].map { a, b in
            let (x, y) = turn(a * sx * w0 / 2, b * sy * h0 / 2, rot)
            return CGPoint(x: cx + x, y: cy + y)
        }
    }

    /// The unit square onto any four-cornered shape, with perspective.
    static func quadMap(_ q: [CGPoint]) -> (Double, Double) -> CGPoint {
        let x0 = Double(q[0].x), y0 = Double(q[0].y), x1 = Double(q[1].x), y1 = Double(q[1].y), x2 = Double(q[2].x), y2 = Double(q[2].y), x3 = Double(q[3].x), y3 = Double(q[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3, dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        var a, b, c, d, e, f, g: Double, h: Double
        g = 0; h = 0
        if abs(dx3) < 1e-7 && abs(dy3) < 1e-7 { a = x1 - x0; b = x3 - x0; c = x0; d = y1 - y0; e = y3 - y0; f = y0 }
        else {
            var den = dx1 * dy2 - dx2 * dy1; if den == 0 { den = 1e-9 }
            g = (dx3 * dy2 - dx2 * dy3) / den; h = (dx1 * dy3 - dx3 * dy1) / den
            a = x1 - x0 + g * x1; b = x3 - x0 + h * x3; c = x0; d = y1 - y0 + g * y1; e = y3 - y0 + h * y3; f = y0
        }
        return { u, v in let w = g * u + h * v + 1; return CGPoint(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w) }
    }

    nonisolated private static func catmull(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
        0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
    }

    /// Warp: the surface passes through the 16 nodes (a Catmull-Rom surface of their displacements from the flat shape).
    func warpMap() -> (Double, Double) -> CGPoint {
        let rest = Self.quadMap(q0), D = self.D
        return { u, v in
            let b = rest(u, v)
            let s = u * 3, t = v * 3, i = min(2, Int(floor(s))), j = min(2, Int(floor(t))), fu = s - Double(i), fv = t - Double(j)
            func cl(_ k: Int) -> Int { max(0, min(3, k)) }
            func row(_ jj: Int) -> (Double, Double) {
                let r = cl(jj) * 4
                return (Self.catmull(Double(D[r + cl(i - 1)].x), Double(D[r + i].x), Double(D[r + cl(i + 1)].x), Double(D[r + cl(i + 2)].x), fu),
                        Self.catmull(Double(D[r + cl(i - 1)].y), Double(D[r + i].y), Double(D[r + cl(i + 1)].y), Double(D[r + cl(i + 2)].y), fu))
            }
            let r0 = row(j - 1), r1 = row(j), r2 = row(j + 1), r3 = row(j + 2)
            return CGPoint(x: Double(b.x) + Self.catmull(r0.0, r1.0, r2.0, r3.0, fv), y: Double(b.y) + Self.catmull(r0.1, r1.1, r2.1, r3.1, fv))
        }
    }
    func warpNodes() -> [CGPoint] {
        let m = warpMap()
        return (0..<4).flatMap { j in (0..<4).map { i in m(Double(i) / 3, Double(j) / 3) } }
    }

    // MARK: drawing it

    /// One triangle of the picture laid on its new place (affine inside the triangle; a fine mesh of them makes the curve).
    private func tri(_ c: CGContext, _ s0: CGPoint, _ s1: CGPoint, _ s2: CGPoint, _ d0: CGPoint, _ d1: CGPoint, _ d2: CGPoint) {
        let cx = (d0.x + d1.x + d2.x) / 3, cy = (d0.y + d1.y + d2.y) / 3
        func gr(_ p: CGPoint) -> CGPoint { let dx = p.x - cx, dy = p.y - cy; let l = max(1e-9, hypot(dx, dy)); return CGPoint(x: p.x + dx / l * 0.7, y: p.y + dy / l * 0.7) }   // grown a little so no hairline shows between neighbours
        let det = Double((s1.x - s0.x) * (s2.y - s0.y) - (s2.x - s0.x) * (s1.y - s0.y))
        if abs(det) < 1e-9 { return }
        let A = Double((d1.x - d0.x) * (s2.y - s0.y) - (d2.x - d0.x) * (s1.y - s0.y)) / det
        let B = Double((d1.y - d0.y) * (s2.y - s0.y) - (d2.y - d0.y) * (s1.y - s0.y)) / det
        let C = Double((s1.x - s0.x) * (d2.x - d0.x) - (s2.x - s0.x) * (d1.x - d0.x)) / det
        let Dd = Double((s1.x - s0.x) * (d2.y - d0.y) - (s2.x - s0.x) * (d1.y - d0.y)) / det
        let E = Double(d0.x) - A * Double(s0.x) - C * Double(s0.y), F = Double(d0.y) - B * Double(s0.x) - Dd * Double(s0.y)
        let g0 = gr(d0), g1 = gr(d1), g2 = gr(d2)
        c.saveGState()
        c.move(to: g0); c.addLine(to: g1); c.addLine(to: g2); c.closePath(); c.clip()
        c.concatenate(CGAffineTransform(a: A, b: B, c: C, d: Dd, tx: E, ty: F))
        c.translateBy(x: 0, y: h0); c.scaleBy(x: 1, y: -1)   // the picture is upright; the document is y-down
        c.draw(src, in: CGRect(x: 0, y: 0, width: w0, height: h0))
        c.restoreGState()
    }

    private func mesh(_ c: CGContext, _ map: (Double, Double) -> CGPoint, _ N: Int) {
        var P: [[CGPoint]] = []
        for j in 0...N { P.append((0...N).map { map(Double($0) / Double(N), Double(j) / Double(N)) }) }
        c.saveGState(); c.interpolationQuality = .high
        for j in 0..<N { for i in 0..<N {
            let a0 = CGPoint(x: Double(i) / Double(N) * w0, y: Double(j) / Double(N) * h0), a1 = CGPoint(x: Double(i + 1) / Double(N) * w0, y: Double(j) / Double(N) * h0)
            let a2 = CGPoint(x: Double(i + 1) / Double(N) * w0, y: Double(j + 1) / Double(N) * h0), a3 = CGPoint(x: Double(i) / Double(N) * w0, y: Double(j + 1) / Double(N) * h0)
            tri(c, a0, a1, a3, P[j][i], P[j][i + 1], P[j + 1][i])
            tri(c, a1, a2, a3, P[j][i + 1], P[j + 1][i + 1], P[j + 1][i])
        } }
        c.restoreGState()
    }

    /// The transformed picture drawn into a document-space (y-down) context.
    func paint(into c: CGContext, fine: Bool) {
        switch mode {
        case .distort: mesh(c, Self.quadMap(q), fine ? 32 : 16)
        case .warp: mesh(c, warpMap(), fine ? 32 : 16)
        default:
            c.saveGState()
            c.translateBy(x: cx, y: cy); c.rotate(by: rot); c.scaleBy(x: fx * sx, y: fy * sy)
            c.interpolationQuality = smooth ? .high : .none
            c.translateBy(x: -w0 / 2, y: h0 / 2); c.scaleBy(x: 1, y: -1)   // upright picture on a y-down canvas
            c.draw(src, in: CGRect(x: 0, y: 0, width: w0, height: h0))
            c.restoreGState()
        }
    }

    /// For the plain modes the float layer shows the picture by transform alone (about its centre, placed at cx, cy).
    var floatTransform: CGAffineTransform { CGAffineTransform(rotationAngle: CGFloat(rot)).scaledBy(x: CGFloat(fx * sx), y: CGFloat(fy * sy)) }
    var isPlain: Bool { mode == .free || mode == .uni }

    // MARK: modes

    func setMode(_ m: Mode) {
        guard m != mode else { return }
        if m == .free || m == .uni {
            if mode == .distort || mode == .warp { reset() }
            mode = m
        } else if mode == .free || mode == .uni {
            q = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map { aff($0.0, $0.1) }
            q0 = q; D = Array(repeating: .zero, count: 16); mode = m
        } else if m == .distort {
            let f = warpMap()
            q = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map { f($0.0, $0.1) }
            mode = .distort
        } else {
            q0 = q; D = Array(repeating: .zero, count: 16); mode = .warp
        }
    }
    func reset() { cx = Double(home.x); cy = Double(home.y); sx = 1; sy = 1; fx = 1; fy = 1; rot = 0; mode = .free; q = []; q0 = []; D = []; pivot = nil }
    func fit(docW: Int, docH: Int) -> Bool {
        guard isPlain else { return false }
        let k = min(Double(docW) / w0, Double(docH) / h0)
        sx = k; sy = k; cx = Double(docW) / 2; cy = Double(docH) / 2; rot = 0
        return true
    }
    func flip(horizontal: Bool) -> Bool {
        if mode == .warp { return false }
        if mode == .distort { q = horizontal ? [q[1], q[0], q[3], q[2]] : [q[3], q[2], q[1], q[0]] }
        else if horizontal { fx *= -1 } else { fy *= -1 }
        return true
    }
    func turn45() -> Bool {
        guard isPlain else { return false }
        let P = pivot ?? CGPoint(x: cx, y: cy), (vx, vy) = turn(cx - Double(P.x), cy - Double(P.y), .pi / 4)
        cx = Double(P.x) + vx; cy = Double(P.y) + vy; rot += .pi / 4
        return true
    }

    // MARK: touches (document coordinates; `scale` is the view's zoom, so handles keep one size on screen)

    func down(_ p: CGPoint, scale: Double) {
        let x = Double(p.x), y = Double(p.y), hit = 22 / scale
        func near(_ a: CGPoint) -> Bool { hypot(x - Double(a.x), y - Double(a.y)) < hit }
        if mode == .distort {
            for i in 0..<4 where near(q[i]) { drag = Drag(kind: .qc(i)); return }
            drag = Drag(kind: .qmove, x: x, y: y, q: q); return
        }
        if mode == .warp {
            let nodes = warpNodes()
            for k in 0..<16 where near(nodes[k]) { drag = Drag(kind: .wn(k), x: x, y: y, d: D[k]); return }
            let gap = hypot(Double(nodes[1].x - nodes[0].x), Double(nodes[1].y - nodes[0].y)) + hypot(Double(nodes[4].x - nodes[0].x), Double(nodes[4].y - nodes[0].y))
            drag = Drag(kind: .wpull, x: x, y: y, D: D, nodes: nodes, R: max(40, gap * 0.7)); return
        }
        let rn = rotNode(scale), yn = pivotNode(scale)
        if near(yn) { drag = Drag(kind: .piv, x: x, y: y); return }
        if mode == .free {
            let ed = edgeNodes()
            let axes: [(Double, Double)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]
            for i in 0..<4 where near(ed[i]) { drag = Drag(kind: .edge(i), a: axes[i].0, b: axes[i].1, opp: ed[(i + 2) % 4], rot0: rot); return }
        }
        if near(rn) {
            if let P = pivot { drag = Drag(kind: .rotp, rot0: rot, P: P, c0: CGPoint(x: cx, y: cy), ph0: atan2(y - Double(P.y), x - Double(P.x))) }
            else { drag = Drag(kind: .rot) }
            return
        }
        for i in 0..<4 where near(corner(i)) {
            let (a, b) = Self.node[i]
            drag = Drag(kind: .scale(i), opp: corner((i + 2) % 4), rot0: rot, v0: CGPoint(x: a * sx * w0, y: b * sy * h0)); return
        }
        let k = (0..<4).map { corner($0) }
        var inside = false
        var j = 3
        for i in 0..<4 {
            if (k[i].y > CGFloat(y)) != (k[j].y > CGFloat(y)), CGFloat(x) < (k[j].x - k[i].x) * (CGFloat(y) - k[i].y) / (k[j].y - k[i].y) + k[i].x { inside.toggle() }
            j = i
        }
        if !inside { drag = Drag(kind: .outside, x: x, y: y); return }   // a tap outside the box nudges it one pixel toward the tap
        drag = Drag(kind: .move, x: x, y: y, cx: cx, cy: cy)
    }

    func move(_ p: CGPoint, scale: Double) {
        guard var d = drag else { return }
        let x = Double(p.x), y = Double(p.y)
        switch d.kind {
        case .qc(let i): q[i] = p
        case .qmove: q = d.q.map { CGPoint(x: $0.x + CGFloat(x - d.x), y: $0.y + CGFloat(y - d.y)) }
        case .wn(let k): D[k] = CGPoint(x: Double(d.d.x) + x - d.x, y: Double(d.d.y) + y - d.y)
        case .wpull:
            let dx = x - d.x, dy = y - d.y
            for k in 0..<16 {
                let w = exp(-pow(hypot(Double(d.nodes[k].x) - d.x, Double(d.nodes[k].y) - d.y) / d.R, 2))
                D[k] = CGPoint(x: Double(d.D[k].x) + dx * w, y: Double(d.D[k].y) + dy * w)
            }
        case .edge(let i):
            let (lx, ly) = turn(x - Double(d.opp.x), y - Double(d.opp.y), -d.rot0)
            if d.a != 0 { let nx = max(6, d.a * lx); sx = nx / w0; let (ox, oy) = turn(d.a * nx / 2, 0, d.rot0); cx = Double(d.opp.x) + ox; cy = Double(d.opp.y) + oy }
            else { let ny = max(6, d.b * ly); sy = ny / h0; let (ox, oy) = turn(0, d.b * ny / 2, d.rot0); cx = Double(d.opp.x) + ox; cy = Double(d.opp.y) + oy }
            _ = i
        case .piv:
            if !d.moved && hypot(x - d.x, y - d.y) < 5 / scale { return }
            d.moved = true
            pivot = hypot(x - cx, y - cy) < 10 / scale ? CGPoint(x: cx, y: cy) : p
        case .rotp:
            var dl = atan2(y - Double(d.P.y), x - Double(d.P.x)) - d.ph0
            let qq = Double.pi / 12
            if magnetic { let n = (d.rot0 + dl) / qq; let nn = n.rounded() * qq; if abs(d.rot0 + dl - nn) < 0.07 { dl = nn - d.rot0 } }
            let (vx, vy) = turn(Double(d.c0.x - d.P.x), Double(d.c0.y - d.P.y), dl)
            cx = Double(d.P.x) + vx; cy = Double(d.P.y) + vy; rot = d.rot0 + dl
        case .outside: if hypot(x - d.x, y - d.y) > 4 / scale { d.moved = true }
        case .move:
            cx = d.cx + x - d.x; cy = d.cy + y - d.y
        case .rot:
            var a = atan2(y - cy, x - cx) + .pi / 2
            let qq = Double.pi / 12, n = (a / qq).rounded() * qq
            if magnetic && abs(a - n) < 0.07 { a = n }
            rot = a
        case .scale(let i):
            let (lx, ly) = turn(x - Double(d.opp.x), y - Double(d.opp.y), -d.rot0)
            let (a, b) = Self.node[i]
            var nx, ny: Double
            if mode == .free { nx = a * max(6, a * lx); ny = b * max(6, b * ly) }
            else {
                let v0x = Double(d.v0.x), v0y = Double(d.v0.y)
                let k = max(0.02, (lx * v0x + ly * v0y) / (v0x * v0x + v0y * v0y)); nx = v0x * k; ny = v0y * k
            }
            sx = abs(nx) / w0; sy = abs(ny) / h0
            let (ox, oy) = turn(nx / 2, ny / 2, d.rot0)
            cx = Double(d.opp.x) + ox; cy = Double(d.opp.y) + oy
        }
        drag = d
    }

    /// A release; a tap outside the box nudges it one pixel toward the tap, and a tap on the yellow node without a drag clears the pivot.
    func up() {
        guard let d = drag else { return }
        switch d.kind {
        case .outside where !d.moved: break
        case .piv where !d.moved: pivot = nil
        default: break
        }
        drag = nil
    }
    func nudge(toward p: CGPoint) {
        let vx = Double(p.x) - cx, vy = Double(p.y) - cy
        if abs(vx) >= abs(vy) { cx += vx > 0 ? 1 : -1 } else { cy += vy > 0 ? 1 : -1 }
    }
}
