import CoreGraphics
import Foundation

/// SVG path data (`d`) to a Core Graphics path: what `new Path2D(d)` holds. His twelve comps are drawn from these every frame,
/// so each string is parsed once and kept.
enum SVGPath {
    nonisolated(unsafe) private static var cache: [String: CGPath] = [:]
    nonisolated(unsafe) private static var order: [String] = []

    static func cached(_ d: String) -> CGPath? {
        if let p = cache[d] { return p }
        guard let p = parse(d) else { return nil }
        cache[d] = p
        order.append(d)
        if order.count > 600 { for k in order.prefix(150) { cache[k] = nil }; order.removeFirst(150) }
        return p
    }

    /// `isPointInPath` / `isPointInStroke`, in the path's own coordinates.
    static func contains(_ d: String, x: Double, y: Double, evenOdd: Bool, stroke: Bool, lineWidth: Double) -> Bool {
        guard let p = cached(d) else { return false }
        let pt = CGPoint(x: x, y: y)
        if stroke {
            let outline = p.copy(strokingWithWidth: CGFloat(max(0.0001, lineWidth)), lineCap: .butt, lineJoin: .miter, miterLimit: 10)
            return outline.contains(pt, using: .winding)
        }
        return p.contains(pt, using: evenOdd ? .evenOdd : .winding)
    }

    // MARK: parser

    private struct Scanner {
        let u: [UInt8]
        var i = 0
        init(_ s: String) { u = Array(s.utf8) }

        mutating func skipSep() {
            while i < u.count, u[i] == 32 || u[i] == 44 || u[i] == 10 || u[i] == 13 || u[i] == 9 { i += 1 }
        }
        var done: Bool { mutating get { skipSep(); return i >= u.count } }
        mutating func peekIsNumber() -> Bool {
            skipSep()
            guard i < u.count else { return false }
            let c = u[i]
            return (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46
        }
        mutating func number() -> Double? {
            skipSep()
            let start = i
            if i < u.count, u[i] == 45 || u[i] == 43 { i += 1 }
            var digits = 0
            while i < u.count, u[i] >= 48 && u[i] <= 57 { i += 1; digits += 1 }
            if i < u.count, u[i] == 46 {
                i += 1
                while i < u.count, u[i] >= 48 && u[i] <= 57 { i += 1; digits += 1 }
            }
            if digits == 0 { i = start; return nil }
            if i < u.count, u[i] == 101 || u[i] == 69 {
                let save = i
                i += 1
                if i < u.count, u[i] == 45 || u[i] == 43 { i += 1 }
                var ed = 0
                while i < u.count, u[i] >= 48 && u[i] <= 57 { i += 1; ed += 1 }
                if ed == 0 { i = save }
            }
            return Double(String(decoding: u[start..<i], as: UTF8.self))
        }
        /// An arc flag is a single 0 or 1, and may be glued to the next number.
        mutating func flag() -> Bool? {
            skipSep()
            guard i < u.count, u[i] == 48 || u[i] == 49 else { return nil }
            defer { i += 1 }
            return u[i] == 49
        }
    }

    static func parse(_ d: String) -> CGPath? {
        var sc = Scanner(d)
        let path = CGMutablePath()
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastC: CGPoint?, lastQ: CGPoint?
        var cmd: UInt8 = 0
        var any = false
        func pt(_ sc: inout Scanner, rel: Bool) -> CGPoint? {
            guard let x = sc.number(), let y = sc.number() else { return nil }
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }
        while !sc.done {
            let c = sc.u[sc.i]
            if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) { cmd = c; sc.i += 1 }
            else if cmd == 0 { return any ? path : nil }
            else if !sc.peekIsNumber() { return any ? path : nil }
            let rel = cmd >= 97
            switch cmd | 0x20 {   // lower-case it
            case UInt8(ascii: "z"):
                path.closeSubpath(); cur = start; lastC = nil; lastQ = nil; any = true; cmd = 0
            case UInt8(ascii: "m"):
                guard let p = pt(&sc, rel: rel) else { return any ? path : nil }
                path.move(to: p); cur = p; start = p; lastC = nil; lastQ = nil; any = true
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")   // further pairs are line-tos
            case UInt8(ascii: "l"):
                guard let p = pt(&sc, rel: rel) else { return any ? path : nil }
                if path.isEmpty { path.move(to: cur) }
                path.addLine(to: p); cur = p; lastC = nil; lastQ = nil; any = true
            case UInt8(ascii: "h"):
                guard let x = sc.number() else { return any ? path : nil }
                let p = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                if path.isEmpty { path.move(to: cur) }
                path.addLine(to: p); cur = p; lastC = nil; lastQ = nil; any = true
            case UInt8(ascii: "v"):
                guard let y = sc.number() else { return any ? path : nil }
                let p = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                if path.isEmpty { path.move(to: cur) }
                path.addLine(to: p); cur = p; lastC = nil; lastQ = nil; any = true
            case UInt8(ascii: "c"):
                guard let c1 = pt(&sc, rel: rel), let c2 = pt(&sc, rel: rel), let p = pt(&sc, rel: rel) else { return any ? path : nil }
                if path.isEmpty { path.move(to: cur) }
                path.addCurve(to: p, control1: c1, control2: c2); cur = p; lastC = c2; lastQ = nil; any = true
            case UInt8(ascii: "s"):
                guard let c2 = pt(&sc, rel: rel), let p = pt(&sc, rel: rel) else { return any ? path : nil }
                let c1 = lastC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                if path.isEmpty { path.move(to: cur) }
                path.addCurve(to: p, control1: c1, control2: c2); cur = p; lastC = c2; lastQ = nil; any = true
            case UInt8(ascii: "q"):
                guard let c1 = pt(&sc, rel: rel), let p = pt(&sc, rel: rel) else { return any ? path : nil }
                if path.isEmpty { path.move(to: cur) }
                path.addQuadCurve(to: p, control: c1); cur = p; lastQ = c1; lastC = nil; any = true
            case UInt8(ascii: "t"):
                guard let p = pt(&sc, rel: rel) else { return any ? path : nil }
                let c1 = lastQ.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                if path.isEmpty { path.move(to: cur) }
                path.addQuadCurve(to: p, control: c1); cur = p; lastQ = c1; lastC = nil; any = true
            case UInt8(ascii: "a"):
                guard let rx = sc.number(), let ry = sc.number(), let rot = sc.number(), let large = sc.flag(), let sweep = sc.flag(), let p = pt(&sc, rel: rel) else { return any ? path : nil }
                if path.isEmpty { path.move(to: cur) }
                arc(path, from: cur, rx: rx, ry: ry, rot: rot, large: large, sweep: sweep, to: p)
                cur = p; lastC = nil; lastQ = nil; any = true
            default:
                return any ? path : nil
            }
        }
        return any ? path : nil
    }

    /// The SVG endpoint arc as cubic segments (SVG 1.1 implementation notes, F.6).
    private static func arc(_ path: CGMutablePath, from p0: CGPoint, rx rx0: Double, ry ry0: Double, rot: Double, large: Bool, sweep: Bool, to p1: CGPoint) {
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 || (p0.x == p1.x && p0.y == p1.y) { path.addLine(to: p1); return }
        let phi = rot * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = Double(p0.x - p1.x) / 2, dy = Double(p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { let s = lam.squareRoot(); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = coef * (rx * y1 / ry), cyp = coef * -(ry * x1 / rx)
        let cx = cp * cxp - sp * cyp + Double(p0.x + p1.x) / 2, cy = sp * cxp + cp * cyp + Double(p0.y + p1.y) / 2
        func ang(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let th1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dth = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dth > 0 { dth -= 2 * .pi } else if sweep && dth < 0 { dth += 2 * .pi }
        let segs = max(1, Int(ceil(abs(dth) / (.pi / 2) - 1e-9)))
        let delta = dth / Double(segs)
        let t = 4.0 / 3.0 * tan(delta / 4)
        var a = th1
        for _ in 0..<segs {
            let ca = cos(a), sa = sin(a), cb = cos(a + delta), sb = sin(a + delta)
            func map(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cp * rx * x - sp * ry * y + cx, y: sp * rx * x + cp * ry * y + cy) }
            // unit-circle control points, then stretched, rotated and moved
            let c1 = map(ca - t * sa, sa + t * ca), c2 = map(cb + t * sb, sb - t * cb), e = map(cb, sb)
            path.addCurve(to: e, control1: c1, control2: c2)
            a += delta
        }
    }
}
