import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The drawing assists and the three odd tools: symmetry, tile mode, guides and assisted drawing, tangent lock, QuickShape, smudge,
/// wet mix, the eyedropper and ColorDrop. Each is a port of the same-named function in the laptop's `app.js`.
extension NativeCanvasModel {
    static func num(_ v: Any) -> Double { (v as? Double) ?? Double(v as? Int ?? 0) }

    // MARK: symmetry and tile

    private func symPoints(_ x: Double, _ y: Double, _ d: NativeDoc) -> [(Double, Double)] {
        let W = Double(d.w), H = Double(d.h), cx = W / 2, cy = H / 2
        switch sym {
        case .off: return [(x, y)]
        case .v: return [(x, y), (W - x, y)]
        case .h: return [(x, y), (x, H - y)]
        case .quad: return [(x, y), (W - x, y), (x, H - y), (W - x, H - y)]
        case .radial:
            let dx = x - cx, dy = y - cy
            var o: [(Double, Double)] = []
            for (a, b) in [(dx, dy), (-dx, dy)] {
                for k in 0..<4 {
                    let c = [1.0, 0, -1, 0][k], s = [0.0, 1, 0, -1][k]
                    o.append((cx + a * c - b * s, cy + a * s + b * c))
                }
            }
            return o
        }
    }

    /// The dab and its copies: across the symmetry guide, and again on the far side of the picture when tile mode is on.
    func copies(of dab: Dab, brush B: Brush, size: Double, in d: NativeDoc) -> [Dab] {
        if sym == .off && tile == .off { return [dab] }
        let W = Double(d.w), H = Double(d.h)
        let a0 = symPoints(dab.x, dab.y, d)
        let b0 = dab.tw.map { symPoints(dab.x + $0.dx, dab.y + $0.dy, d) }
        let pad0 = B.radius(size: size, pressure: dab.p, f: dab.f) * 1.5 + 4
        var out: [Dab] = []
        for (i, q) in a0.enumerated() {
            var d1 = dab
            d1.x = q.0; d1.y = q.1
            if let tw = dab.tw, let b0 { d1.tw = Twin(dx: b0[i].0 - q.0, dy: b0[i].1 - q.1, f: tw.f) }
            out.append(d1)
            if tile == .off { continue }
            for dx in [-W, 0, W] {
                for dy in (tile == .both ? [-H, 0, H] : [0.0]) {
                    if dx == 0 && dy == 0 { continue }
                    let nx = q.0 + dx, ny = q.1 + dy
                    if nx < -pad0 - 30 || ny < -pad0 - 30 || nx > W + pad0 + 30 || ny > H + pad0 + 30 { continue }
                    var d2 = d1
                    d2.x = nx; d2.y = ny
                    out.append(d2)
                }
            }
        }
        return out
    }

    // MARK: guides and assisted drawing

    func assistActive(layer i: Int) -> Bool {
        if let d = doc, d.layers.indices.contains(i), let a = d.layers[i].meta["assist"] as? Bool { return a }
        return assist
    }

    func guideVPs() -> [CGPoint] {
        guard let d = doc, guide.points > 0 else { return [] }
        if let v = vps[guide.rawValue], v.count == guide.points { return v }
        let W = CGFloat(d.w), H = CGFloat(d.h)
        let v: [CGPoint]
        switch guide {
        case .persp: v = [CGPoint(x: W / 2, y: H / 2)]
        case .persp2: v = [CGPoint(x: -W * 0.3, y: H / 2), CGPoint(x: W * 1.3, y: H / 2)]
        default: v = [CGPoint(x: -W * 0.3, y: H / 2), CGPoint(x: W * 1.3, y: H / 2), CGPoint(x: W / 2, y: -H * 1.4)]
        }
        vps[guide.rawValue] = v
        return v
    }

    private func guideDirections(from sx: Double, _ sy: Double) -> [Double] {
        switch guide {
        case .off: return []
        case .grid: return [0, .pi / 2]
        case .iso: return [.pi / 2, .pi / 6, -.pi / 6]
        default:
            var dirs = guideVPs().map { atan2(Double($0.y) - sy, Double($0.x) - sx) }
            if guide == .persp { dirs += [0, .pi / 2] } else if guide == .persp2 { dirs.append(.pi / 2) }
            return dirs
        }
    }

    /// Assisted drawing: the stroke locks to the nearest guide direction once it has moved a little.
    func assistPoint(_ s: inout Live, _ x: Double, _ y: Double) -> (Double, Double) {
        guard let start = s.start else { s.start = CGPoint(x: x, y: y); return (x, y) }
        let sx = Double(start.x), sy = Double(start.y), dx = x - sx, dy = y - sy
        if s.dir == nil {
            if hypot(dx, dy) < 10 { return (sx, sy) }
            let allowed = guideDirections(from: sx, sy)
            guard !allowed.isEmpty else { return (x, y) }
            let a = atan2(dy, dx)
            var best = allowed[0], bd = 9.0
            for g in allowed { let dd = abs(sin(a - g)); if dd < bd { bd = dd; best = g } }   // a direction and its opposite count as one
            s.dir = (cos(best), sin(best))
        }
        guard let dir = s.dir else { return (x, y) }
        let t = dx * dir.0 + dy * dir.1
        return (sx + dir.0 * t, sy + dir.1 * t)
    }

    // MARK: tangent lock

    /// An earlier stroke's end that this stroke starts just beyond and in line with: the start slides onto it, fading over the first widths.
    func tangentAdjust(_ s: inout Live, _ x0: Double, _ y0: Double) -> (Double, Double) {
        guard let d = doc else { return (x0, y0) }
        if !s.tangentChecked {
            s.tangentChecked = true
            let R = s.size * 4 + 24, gap = max(6, s.size * 0.45)
            var best: (d: Double, tx: Double, ty: Double)?
            for r in d.log {
                if (r["dead"] as? Bool) == true || (r["onMask"] as? Bool) == true || (r["tool"] as? String) != "paint" { continue }
                guard (r["layer"] as? Int) == s.layer + 1, let pts = r["pts"] as? [[Any]], pts.count >= 6 else { continue }
                let n = pts.count
                for (e, q) in [(pts[n - 1], pts[n - 6]), (pts[0], pts[5])] {
                    let ex = Self.num(e[0]), ey = Self.num(e[1]), qx = Self.num(q[0]), qy = Self.num(q[1])
                    let h = atan2(ey - qy, ex - qx), vx = x0 - ex, vy = y0 - ey, dd = hypot(vx, vy)
                    if dd > R || dd < 1 { continue }
                    var da = atan2(vy, vx) - h
                    da = atan2(sin(da), cos(da))
                    if abs(da) > 0.9 { continue }
                    if best == nil || dd < best!.d { best = (dd, ex + cos(h) * gap, ey + sin(h) * gap) }
                }
            }
            if let b = best { s.tangentOffset = (b.tx - x0, b.ty - y0) }
            s.tangentPrev = CGPoint(x: x0, y: y0)
        }
        guard let off = s.tangentOffset, let prev = s.tangentPrev else { return (x0, y0) }
        s.tangentDist += hypot(x0 - Double(prev.x), y0 - Double(prev.y))
        s.tangentPrev = CGPoint(x: x0, y: y0)
        let k = max(0, 1 - s.tangentDist / (s.size * 3))
        return (x0 + off.0 * k, y0 + off.1 * k)
    }

    // MARK: QuickShape

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }
    private func douglasPeucker(_ pts: [CGPoint], _ tol: Double) -> [CGPoint] {
        if pts.count < 3 { return pts }
        let a = pts[0], b = pts[pts.count - 1]
        let L = max(1e-9, dist(a, b))
        var md = -1.0, mi = 0
        for i in 1..<(pts.count - 1) {
            let d = abs(Double((b.x - a.x) * (a.y - pts[i].y) - (a.x - pts[i].x) * (b.y - a.y))) / L
            if d > md { md = d; mi = i }
        }
        if md <= tol { return [a, b] }
        return Array(douglasPeucker(Array(pts[0...mi]), tol).dropLast()) + douglasPeucker(Array(pts[mi...]), tol)
    }

    /// The clean path for a stroke that is nearly a line, a triangle, a four-sided shape or an ellipse; nil for a free stroke.
    func shapeFit(_ pts: [CGPoint]) -> (kind: String, path: [CGPoint])? {
        let n = pts.count
        guard n >= 6 else { return nil }
        var len = 0.0
        for i in 1..<n { len += dist(pts[i - 1], pts[i]) }
        let first = pts[0], last = pts[n - 1], gap = dist(first, last)
        guard len >= 30 else { return nil }
        if gap > 0.3 * len {   // open
            let chord = max(gap, 1e-9)
            var dev = 0.0
            for p in pts { dev = max(dev, abs(Double((last.x - first.x) * (first.y - p.y) - (first.x - p.x) * (last.y - first.y))) / chord) }
            if dev < 0.07 * chord { return ("line", [first, last]) }
            let poly = douglasPeucker(pts, 0.05 * len)
            return poly.count <= 4 ? ("poly", poly) : nil
        }
        var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for p in pts { x0 = min(x0, Double(p.x)); y0 = min(y0, Double(p.y)); x1 = max(x1, Double(p.x)); y1 = max(y1, Double(p.y)) }
        let tol = 0.07 * max(x1 - x0, y1 - y0)
        var ib = 0, bd = -1.0
        for (i, p) in pts.enumerated() { let d = dist(p, first); if d > bd { bd = d; ib = i } }   // a closed path has no chord: cut at the point farthest from the start
        var ring = Array(douglasPeucker(Array(pts[0...ib]), tol).dropLast()) + Array(douglasPeucker(Array(pts[ib...]) + [first], tol).dropLast())
        var again = true
        while again && ring.count > 3 {   // a vertex that hardly turns is not a corner
            again = false
            for i in 0..<ring.count {
                let a = ring[(i + ring.count - 1) % ring.count], b = ring[i], c = ring[(i + 1) % ring.count]
                let ux = Double(b.x - a.x), uy = Double(b.y - a.y), vx = Double(c.x - b.x), vy = Double(c.y - b.y)
                let lu = max(1e-9, hypot(ux, uy)), lv = max(1e-9, hypot(vx, vy))
                if (ux * vx + uy * vy) / (lu * lv) > 0.9 { ring.remove(at: i); again = true; break }
            }
        }
        let corners = ring.count
        if corners == 3 || corners == 4 { return (corners == 3 ? "triangle" : "quad", ring + [ring[0]]) }
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, rx = (x1 - x0) / 2, ry = (y1 - y0) / 2
        var out: [CGPoint] = []
        for i in 0...72 { let a = Double(i) / 72 * .pi * 2; out.append(CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry)) }
        return ("ellipse", out)
    }

    func snapShape() {
        guard var s = live, !s.snapped, s.tool != .smudge, let d = doc else { return }
        let pts = s.pts.map { CGPoint(x: Self.num($0[0]), y: Self.num($0[1])) }
        guard let fit = shapeFit(pts) else { return }
        s.shape = fit
        relay(&s, path: fit.path, d)
        live = s
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        say("Shape held. Touch with a second finger to make it exact.")
    }

    /// Lays the stroke down again along a clean path.
    private func relay(_ s: inout Live, path: [CGPoint], _ d: NativeDoc) {
        if s.tool == .paint, !s.onMask { if let w = wet, let box = s.dirty?.integral { w.clear(box) } }
        else { for (k, data) in s.before { s.target.setTile(tx: k.tx, ty: k.ty, data) } }
        s.dirty = nil
        var st = NativeStroker(s.brush, size: s.size)
        st.global = stabAll
        s.stroker = st; s.raw = []
        let p = s.pAvg ?? 1
        s.pAvg = nil
        for (i, q) in path.enumerated() {
            let dabs = s.stroker.add(x: Double(q.x), y: Double(q.y), p: p, t: Double(i) * 8)
            lay(dabs, &s, on: d)
        }
        s.pts = path.map { [(Double($0.x) * 10).rounded() / 10, (Double($0.y) * 10).rounded() / 10, (p * 100).rounded() / 100, 0] }
        s.snapped = true
        refreshLive(s)
    }

    /// A second finger on a held shape: a line locks to 15 degree steps, an ellipse becomes a circle, a four-sided shape a square, a triangle an equilateral one.
    func perfectShape() {
        guard var s = live, s.snapped, let sh = s.shape, !s.perfect, let d = doc else { return }
        let step = Double.pi / 12
        func snap(_ a: Double) -> Double { (a / step).rounded() * step }
        let P = sh.path
        var out: [CGPoint]?
        switch sh.kind {
        case "line":
            let a = P[0], b = P[1], L = dist(a, b), ang = snap(atan2(Double(b.y - a.y), Double(b.x - a.x)))
            out = [a, CGPoint(x: Double(a.x) + cos(ang) * L, y: Double(a.y) + sin(ang) * L)]
        case "ellipse":
            var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
            for p in P { x0 = min(x0, Double(p.x)); y0 = min(y0, Double(p.y)); x1 = max(x1, Double(p.x)); y1 = max(y1, Double(p.y)) }
            let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, r = ((x1 - x0) + (y1 - y0)) / 4
            out = P.indices.map { i in let a = Double(i) / Double(P.count - 1) * .pi * 2; return CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r) }
        case "quad", "triangle":
            let k = Array(P.dropLast()), n = Double(k.count)
            let cx = k.reduce(0.0) { $0 + Double($1.x) } / n, cy = k.reduce(0.0) { $0 + Double($1.y) } / n
            let R = k.reduce(0.0) { $0 + hypot(Double($1.x) - cx, Double($1.y) - cy) } / n
            var area = 0.0
            for i in 0..<k.count { let a = k[i], b = k[(i + 1) % k.count]; area += Double(a.x * b.y - b.x * a.y) }
            let sg = area >= 0 ? 1.0 : -1.0
            if k.count == 4 {
                let e = snap(atan2(Double(k[1].y - k[0].y), Double(k[1].x - k[0].x))), h = R / 2.0.squareRoot()
                let u = (cos(e), sin(e)), nn = (cos(e + sg * .pi / 2), sin(e + sg * .pi / 2))
                func at(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: cx + u.0 * h * a + nn.0 * h * b, y: cy + u.1 * h * a + nn.1 * h * b) }
                var o = [at(-1, -1), at(1, -1), at(1, 1), at(-1, 1)]; o.append(o[0]); out = o
            } else {
                let a0 = snap(atan2(Double(k[0].y) - cy, Double(k[0].x) - cx))
                var o = (0..<3).map { i in CGPoint(x: cx + cos(a0 + sg * Double(i) * .pi * 2 / 3) * R, y: cy + sin(a0 + sg * Double(i) * .pi * 2 / 3) * R) }
                o.append(o[0]); out = o
            }
        default: break
        }
        guard let path = out else { return }
        s.perfect = true; s.shape = (sh.kind, path)
        s.snapped = false
        relay(&s, path: path, d)
        live = s
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    var shapeHeld: Bool { live?.snapped == true && live?.perfect == false }

    // MARK: smudge

    private static var smudgeMasks: [Int: CGImage] = [:]
    private static func radialMask(_ D: Int) -> CGImage? {
        if let m = smudgeMasks[D] { return m }
        guard let c = CGContext(data: nil, width: D, height: D, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0.85), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 0.55, 1]) else { return nil }
        let m = CGPoint(x: Double(D) / 2, y: Double(D) / 2)
        c.drawRadialGradient(g, startCenter: m, startRadius: 0, endCenter: m, endRadius: Double(D) / 2, options: [])
        let img = c.makeImage()
        if let img { smudgeMasks[D] = img }
        return img
    }

    /// One smudge dab: the paint under the finger is picked up through a soft round mask, then laid down along the way.
    func smudgeDab(_ dab: Dab, _ s: inout Live, _ d: NativeDoc) {
        let px = s.target
        let r = max(2, s.size / 2 * (0.5 + 0.5 * dab.p)), D = Int(min(512, ceil(r * 2)))
        let sx = Int((dab.x - Double(D) / 2).rounded()), sy = Int((dab.y - Double(D) / 2).rounded())
        let rect = CGRect(x: sx, y: sy, width: D, height: D)
        let box = rect.insetBy(dx: -2, dy: -2)
        s.dirty = s.dirty.map { $0.union(box) } ?? box
        for k in px.tiles(in: box) where s.before[k] == nil { s.before[k] = px.tilePixels(tx: k.tx, ty: k.ty) }
        let inside = rect.intersection(CGRect(x: 0, y: 0, width: px.w, height: px.h))
        guard !inside.isNull, inside.width >= 1, inside.height >= 1, let layerImg = px.image(), let part = layerImg.cropping(to: inside),
              let pick = PixelBuffer(w: D, h: D) else { return }
        let ox = Double(inside.minX) - Double(sx), oy = Double(inside.minY) - Double(sy)
        pick.ctx.saveGState()
        pick.ctx.translateBy(x: ox, y: oy + Double(part.height)); pick.ctx.scaleBy(x: 1, y: -1)
        pick.ctx.draw(part, in: CGRect(x: 0, y: 0, width: part.width, height: part.height))
        pick.ctx.restoreGState()
        if let m = Self.radialMask(D) {
            pick.ctx.saveGState(); pick.ctx.setBlendMode(.destinationIn)
            pick.ctx.translateBy(x: 0, y: Double(D)); pick.ctx.scaleBy(x: 1, y: -1)
            pick.ctx.draw(m, in: CGRect(x: 0, y: 0, width: D, height: D))
            pick.ctx.restoreGState()
        }
        guard let carry = s.carry, carry.w == D else { s.carry = pick; return }
        let k = max(0, min(1, s.op * (0.4 + 0.6 * dab.p)))
        if let ci = carry.image() {
            px.ctx.saveGState()
            selection?.clip(px.ctx)
            px.ctx.setAlpha(CGFloat(k))
            px.ctx.translateBy(x: Double(sx), y: Double(sy) + Double(D)); px.ctx.scaleBy(x: 1, y: -1)
            px.ctx.draw(ci, in: CGRect(x: 0, y: 0, width: D, height: D))
            px.ctx.restoreGState()
        }
        if let pi = pick.image() {
            carry.ctx.saveGState()
            carry.ctx.setAlpha(CGFloat(1 - 0.8 * s.op))
            carry.ctx.translateBy(x: 0, y: Double(D)); carry.ctx.scaleBy(x: 1, y: -1)
            carry.ctx.draw(pi, in: CGRect(x: 0, y: 0, width: D, height: D))
            carry.ctx.restoreGState()
        }
    }

    // MARK: wet mix

    /// Wet mix: the paint on the brush picks up the colour of the layer under the dab, and drifts back to the brush's own colour.
    func wetColour(_ st: inout WetState, at x: Double, y: Double, radius r: Double, _ B: Brush, base: String, layer: PixelBuffer) -> String {
        func c255(_ hex: String) -> [Double] { Hex.rgb(hex).map { [$0.0 * 255, $0.1 * 255, $0.2 * 255] } ?? [0, 0, 0] }
        if st.rgb == nil { st.rgb = c255(base); st.base = st.rgb ?? [0, 0, 0] }
        var cur = st.rgb ?? [0, 0, 0]
        let n = max(2, min(20, Int((r * 0.8).rounded()))), sx = max(0, Int((x - Double(n) / 2).rounded())), sy = max(0, Int((y - Double(n) / 2).rounded()))
        let ex = min(layer.w, sx + n), ey = min(layer.h, sy + n), per = B.n("spacing") / 0.1
        if ex > sx && ey > sy {
            var R = 0.0, G = 0.0, Bl = 0.0, A = 0.0
            for yy in sy..<ey { for xx in sx..<ex {
                let i = (yy * layer.w + xx) * 4
                R += Double(layer.ptr[i]) * 255; G += Double(layer.ptr[i + 1]) * 255; Bl += Double(layer.ptr[i + 2]) * 255; A += Double(layer.ptr[i + 3])
            } }
            if A > 0 {
                let k = max(0, min(1, B.n("wet") * 0.5 * (A / (Double((ex - sx) * (ey - sy)) * 255)) * per))
                let avg = [R / A, G / A, Bl / A]
                for c in 0..<3 { cur[c] += (avg[c] - cur[c]) * k }
            }
        }
        let back = max(0, min(1, (1 - B.n("wetPull")) * 0.06 * per))
        for c in 0..<3 { cur[c] += (st.base[c] - cur[c]) * back }
        st.rgb = cur
        let q = cur.map { max(0, min(255, ($0 / 6).rounded() * 6)) / 255 }   // steps of six, so the sprite cache stays small
        return Hex.string(r: q[0], g: q[1], b: q[2])
    }

    // MARK: eyedropper and ColorDrop

    func pick(at p: CGPoint) {
        guard let d = doc else { return }
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < d.w, y < d.h, let rgb = d.sample(x: x, y: y) else { return }
        color = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        pushRecent(Hex.string(r: rgb.0, g: rgb.1, b: rgb.2))
        stage?.updateOverlay(probe: p, hex: Hex.string(r: rgb.0, g: rgb.1, b: rgb.2))
    }

    /// ColorDrop: flood-fill the area under the tap with the colour; the threshold decides how far "the same colour" reaches.
    func fillDrop(at p: CGPoint) {
        guard live == nil, let d = doc else { return }
        let L = d.layers[d.active]
        guard d.isShown(L) else { say("This layer is hidden."); return }
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < d.w, y < d.h else { return }
        let refLayer = d.layers.enumerated().first { $0.element.meta["ref"] as? Bool == true && $0.offset != d.active }?.element
        let t = Int((fillThreshold * 2.55 * 0.9).rounded())
        let m = NativeFlood.mask(refLayer?.pixels ?? L.pixels, x: x, y: y, tolerance: t)
        guard m.count == d.w * d.h else { return }
        // grown by a pixel so antialiased edges are covered
        var minX = d.w, minY = d.h, maxX = -1, maxY = -1
        for yy in 0..<d.h { for xx in 0..<d.w where m[yy * d.w + xx] != 0 { minX = min(minX, xx); maxX = max(maxX, xx); minY = min(minY, yy); maxY = max(maxY, yy) } }
        guard maxX >= 0 else { return }
        let box = CGRect(x: max(0, minX - 3), y: max(0, minY - 3), width: min(d.w, maxX + 4) - max(0, minX - 3), height: min(d.h, maxY + 4) - max(0, minY - 3))
        let px = L.pixels
        var before: [TileKey: Data] = [:]
        for k in px.tiles(in: box) { before[k] = px.tilePixels(tx: k.tx, ty: k.ty) }
        let c = UIColor(color).rgb
        let sel = selection?.has == true ? selection?.mask : nil
        for yy in Int(box.minY)..<Int(box.maxY) { for xx in Int(box.minX)..<Int(box.maxX) {
            var inside = m[yy * d.w + xx] != 0
            if !inside {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = xx + dx, ny = yy + dy
                    if nx >= 0, ny >= 0, nx < d.w, ny < d.h, m[ny * d.w + nx] != 0 { inside = true; break }
                }
            }
            if !inside { continue }
            let i = (yy * d.w + xx) * 4
            var w = 1.0
            if let sel { w = Double(sel.ptr[i + 3]) / 255; if w <= 0 { continue } }
            let oldA = Double(px.ptr[i + 3]) / 255
            if L.alphaLock && oldA == 0 { continue }
            let a = L.alphaLock ? oldA : 1.0
            let tr = c.0 * 255 * a, tg = c.1 * 255 * a, tb = c.2 * 255 * a
            px.ptr[i] = UInt8(max(0, min(255, Double(px.ptr[i]) * (1 - w) + tr * w)))
            px.ptr[i + 1] = UInt8(max(0, min(255, Double(px.ptr[i + 1]) * (1 - w) + tg * w)))
            px.ptr[i + 2] = UInt8(max(0, min(255, Double(px.ptr[i + 2]) * (1 - w) + tb * w)))
            px.ptr[i + 3] = UInt8(max(0, min(255, Double(px.ptr[i + 3]) * (1 - w) + a * 255 * w)))
        } }
        L.meta["raw"] = true
        let tiles = before.keys.sorted { ($0.ty, $0.tx) < ($1.ty, $1.tx) }.map { k in (k, before[k]!, px.tilePixels(tx: k.tx, ty: k.ty)) }
        pushTiles(px, tiles, label: "Fill", layer: d.active)
        stage?.refresh(active: d.active, wetOpacity: 0)
        pushRecent(UIColor(color).hex)
        syncFlags()
    }

    // MARK: guides in the file

    func writeGuide(into d: NativeDoc) {
        d.guide["g"] = guide.rawValue
        d.guide["size"] = Int(guideSize)
        d.guide["tile"] = tile.rawValue
        d.guide["paper"] = paper
        if vps.isEmpty { d.guide["vps"] = NSNull() }
        else { d.guide["vps"] = Dictionary(uniqueKeysWithValues: vps.map { ($0.key, $0.value.map { [Double($0.x), Double($0.y)] }) }) }
    }
}

/// Flood fill over a layer's pixels: every touching pixel within a colour distance of the one tapped. 255 where it reaches.
enum NativeFlood {
    @MainActor static func mask(_ layer: PixelBuffer, x: Int, y: Int, tolerance t: Int) -> [UInt8] {
        let w = layer.w, h = layer.h, d = layer.ptr
        var out = [UInt8](repeating: 0, count: w * h)
        guard x >= 0, y >= 0, x < w, y < h else { return out }
        let i0 = (y * w + x) * 4
        let r0 = Int(d[i0]), g0 = Int(d[i0 + 1]), b0 = Int(d[i0 + 2]), a0 = Int(d[i0 + 3])
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int32] = [Int32(y * w + x)]
        seen[y * w + x] = true
        out[y * w + x] = 255
        while let p32 = stack.popLast() {
            let p = Int(p32), xx = p % w, yy = p / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = xx + dx, ny = yy + dy
                if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                let q = ny * w + nx
                if seen[q] { continue }
                seen[q] = true
                let k = q * 4
                if abs(Int(d[k]) - r0) <= t && abs(Int(d[k + 1]) - g0) <= t && abs(Int(d[k + 2]) - b0) <= t && abs(Int(d[k + 3]) - a0) <= t { out[q] = 255; stack.append(Int32(q)) }
            }
        }
        return out
    }
}

extension NativeDoc {
    /// The colour of one pixel of the picture as it shows (blends, masks, groups and clips included, the PSD-only blends as Normal).
    func sample(x: Int, y: Int) -> (Double, Double, Double)? {
        guard let c = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.setFillColor(Hex.color(bgVis ? bg : "#ffffff") ?? CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = CGRect(x: -Double(x), y: Double(y + 1 - h), width: Double(w), height: Double(h))
        for i in 0..<layers.count where isShown(layers[i]) {
            guard let img = effectiveImage(of: i) else { continue }
            c.saveGState()
            c.setAlpha(CGFloat(shownOpacity(layers[i])))
            c.setBlendMode(NativeBlend.mode(layers[i].meta["blend"] as? String).cg ?? .normal)
            c.draw(img, in: r)
            c.restoreGState()
        }
        guard let p = c.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let a = Double(p[3]) / 255
        if a <= 0 { return (1, 1, 1) }
        return (Double(p[0]) / 255 / a, Double(p[1]) / 255 / a, Double(p[2]) / 255 / a)
    }
}
