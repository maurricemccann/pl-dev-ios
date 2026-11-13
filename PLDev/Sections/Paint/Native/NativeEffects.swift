import CoreGraphics
import CoreImage
import Foundation
import UIKit

/// The brush effects that need the whole stroke: the channel (the keyline clearance around a band), satellites, wick, Echo Pen and
/// weave. Each is a port of the same-named function in `app.js`. They work on the stroke buffer and the layer inside the stroke's box.
@MainActor enum NativeEffects {
    nonisolated(unsafe) static let ci = CIContext(options: [.useSoftwareRenderer: false])

    static func blur(_ img: CGImage, radius: Double) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        let c = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: max(0.1, radius / 2)).cropped(to: rect)
        return ci.createCGImage(c, from: rect)
    }

    /// Draws an upright image with its top-left corner at (x, y) of a y-down buffer.
    static func put(_ img: CGImage, into b: PixelBuffer, x: Double, y: Double, alpha: Double = 1, blend: CGBlendMode = .normal) {
        b.ctx.saveGState()
        b.ctx.setAlpha(CGFloat(alpha)); b.ctx.setBlendMode(blend)
        b.ctx.translateBy(x: x, y: y + Double(img.height)); b.ctx.scaleBy(x: 1, y: -1)
        b.ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        b.ctx.restoreGState()
    }

    /// The part of a buffer inside a box, as an upright image (a view over the same memory, not a copy).
    static func crop(_ b: PixelBuffer, _ box: CGRect) -> CGImage? { b.image()?.cropping(to: box) }

    static func clampBox(_ r: CGRect, _ w: Int, _ h: Int, pad: Double = 2) -> CGRect {
        let x0 = max(0, floor(r.minX - pad)), y0 = max(0, floor(r.minY - pad)), x1 = min(Double(w), ceil(r.maxX + pad)), y1 = min(Double(h), ceil(r.maxY + pad))
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    // MARK: channel

    struct Ring { let outer: Bool; let rad: Double; let fill: String; let colour: String; let mask: PixelBuffer; let box: CGRect }

    /// The grown shape of the stroke for every channel, measured now (before the paper grain touches the stroke), each in its own buffer.
    static func rings(_ B: Brush, size: Double, wet: PixelBuffer, side1: PixelBuffer?, side2: PixelBuffer?, dirty: CGRect, fallback: String, docW: Int, docH: Int) -> [Ring] {
        let box = clampBox(dirty, docW, docH)
        guard box.width >= 1, box.height >= 1 else { return [] }
        var specs: [(Bool, Double, String, String)] = []   // outermost first
        let c1 = B.n("channel"), c2 = B.n("channel2")
        if c2 > 0 { specs.append((true, (c1 + c2) * size, B.t("channel2Fill"), B.t("channel2Color").isEmpty ? fallback : B.t("channel2Color"))) }
        specs.append((false, c1 * size, B.t("channelFill"), B.t("channelColor").isEmpty ? fallback : B.t("channelColor")))
        var out: [Ring] = []
        for (outer, rad, fill, colour) in specs {
            guard let m = PixelBuffer(w: Int(box.width), h: Int(box.height)) else { continue }
            if B.t("channelEnds") != "all", let side = outer ? side2 : side1, let img = crop(side, box) {
                put(img, into: m, x: 0, y: 0)
            } else if let img = crop(wet, box) {
                for k in [1.0, 0.5] { for i in 0..<16 {
                    let a = Double(i) / 16 * .pi * 2
                    put(img, into: m, x: cos(a) * rad * k, y: sin(a) * rad * k)
                } }
            }
            if let me = m.image() { put(me, into: m, x: 0, y: 0) }   // once more over itself so soft edges clear fully
            out.append(Ring(outer: outer, rad: rad, fill: fill, colour: colour, mask: m, box: box))
        }
        return out
    }

    /// Cuts every channel out of what is beneath, then fills it (clear, a flat colour, a glow or a soft shadow).
    static func applyRings(_ rings: [Ring], to layer: PixelBuffer, wet: PixelBuffer, selection: NativeSelection?) {
        for r in rings {
            if let sel = selection, sel.has, let si = crop(sel.mask, r.box) { put(si, into: r.mask, x: 0, y: 0, blend: .destinationIn) }
            guard let mi = r.mask.image() else { continue }
            put(mi, into: layer, x: Double(r.box.minX), y: Double(r.box.minY), blend: .destinationOut)
            let mode = r.fill
            if mode.isEmpty || mode == "clear" { continue }
            guard let t = PixelBuffer(w: r.mask.w, h: r.mask.h) else { continue }
            if mode == "shadow", let wi = crop(wet, r.box) { put(wi, into: t, x: 0, y: 0) } else { put(mi, into: t, x: 0, y: 0) }
            t.ctx.saveGState(); t.ctx.setBlendMode(.sourceIn)
            t.ctx.setFillColor(mode == "shadow" ? CGColor(gray: 0, alpha: 1) : (Hex.color(r.colour) ?? CGColor(gray: 0, alpha: 1)))
            t.ctx.fill(CGRect(x: 0, y: 0, width: t.w, height: t.h)); t.ctx.restoreGState()
            guard let ti = t.image() else { continue }
            let x = Double(r.box.minX), y = Double(r.box.minY)
            if mode == "colour" { put(ti, into: layer, x: x, y: y) }
            else if mode == "glow" {
                if let b = blur(ti, radius: max(2, r.rad * 0.7)) { put(b, into: layer, x: x, y: y) }
                put(ti, into: layer, x: x, y: y, alpha: 0.9)
            } else if let b = blur(ti, radius: max(2, r.rad * 0.45)) { put(b, into: layer, x: x + r.rad * 0.3, y: y + r.rad * 0.4, alpha: 0.5) }
        }
    }

    // MARK: satellites

    /// Small marks near the contour of the stroke, a few, never in the same place twice (the stroke decides where).
    static func satellites(_ B: Brush, pts: [[Any]], size: Double, color: String, wet: PixelBuffer, selection: NativeSelection?) -> CGRect? {
        guard pts.count >= 4 else { return nil }
        var s = 1.0
        for q in pts.prefix(6) { s = ((s * 31 + ((NativeCanvasModel.num(q[0]) * 7 + NativeCanvasModel.num(q[1]) * 13).rounded())).truncatingRemainder(dividingBy: 2147483647)) }
        func rnd() -> Double { s = (s * 16807).truncatingRemainder(dividingBy: 2147483647); return s / 2147483647 }
        let n = Int(B.n("satellites").rounded())
        var SB = B
        for k in ["twin", "channel", "taperStart", "taperEnd", "tremor", "swell"] { SB = SB.setting(k, 0.0) }
        SB = SB.setting("lines", 1.0)
        var box: CGRect?
        for _ in 0..<n {
            let k = 1 + Int(floor(rnd() * Double(pts.count - 2)))
            let a = pts[k - 1], b2 = pts[k + 1]
            let dir = atan2(NativeCanvasModel.num(b2[1]) - NativeCanvasModel.num(a[1]), NativeCanvasModel.num(b2[0]) - NativeCanvasModel.num(a[0]))
            let side: Double = rnd() < 0.5 ? -1 : 1
            let off = size * (0.85 + rnd() * 1.1), sz = size * (0.14 + rnd() * 0.16)
            let x = NativeCanvasModel.num(pts[k][0]) + cos(dir + .pi / 2) * off * side, y = NativeCanvasModel.num(pts[k][1]) + sin(dir + .pi / 2) * off * side
            wet.ctx.saveGState()
            selection?.clip(wet.ctx)
            NativeStamp.draw(wet.ctx, SB, color: color, size: sz, Dab(x: x, y: y, p: 1, f: 1, ang: dir, am: 1, tw: nil, dir: dir, span: 0, edge: false))
            wet.ctx.restoreGState()
            let rr = sz * 1.5 + 4
            let r = CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)
            box = box.map { $0.union(r) } ?? r
        }
        return box
    }

    // MARK: wick

    /// Marker: the edge spreads into the paper, more where the paper is rough.
    static func wick(_ w: PixelBuffer, _ B: Brush, size: Double, box: CGRect) {
        let bx = clampBox(box, w.w, w.h, pad: 0)
        guard bx.width >= 2, bx.height >= 2, let img = crop(w, bx), let t = PixelBuffer(w: Int(bx.width), h: Int(bx.height)),
              let soft = blur(img, radius: max(1, B.n("wick") * size * 0.14)) else { return }
        put(soft, into: t, x: 0, y: 0)
        if let tile = NativeStamp.grainTile("noise", depth: 0.55) {
            t.ctx.saveGState(); t.ctx.setBlendMode(.destinationOut)
            t.ctx.draw(tile, in: CGRect(x: 0, y: 0, width: 192, height: 192), byTiling: true)
            t.ctx.restoreGState()
        }
        if let ti = t.image() { put(ti, into: w, x: Double(bx.minX), y: Double(bx.minY), alpha: 0.6 * B.n("wick") + 0.2, blend: .destinationOver) }
    }

    // MARK: Echo Pen (distance field)

    /// Distance in pixels from every pixel of a mask to the nearest pixel outside it (chamfer 3-4); the picture's border counts as outside.
    static func edt(_ alpha: [UInt8], _ w: Int, _ h: Int, thr: UInt8) -> [Float] {
        let INF: Float = 1e8
        var d = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { d[i] = alpha[i] >= thr ? INF : 0 }
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            if d[i] == 0 { continue }
            var v = d[i]
            v = min(v, (x > 0 ? d[i - 1] : 0) + 3, (y > 0 ? d[i - w] : 0) + 3, (x > 0 && y > 0 ? d[i - w - 1] : 0) + 4, (x < w - 1 && y > 0 ? d[i - w + 1] : 0) + 4)
            d[i] = v
        } }
        for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            if d[i] == 0 { continue }
            var v = d[i]
            v = min(v, (x < w - 1 ? d[i + 1] : 0) + 3, (y < h - 1 ? d[i + w] : 0) + 3, (x < w - 1 && y < h - 1 ? d[i + w + 1] : 0) + 4, (x > 0 && y < h - 1 ? d[i + w - 1] : 0) + 4)
            d[i] = v
        } }
        for i in 0..<(w * h) { d[i] /= 3 }
        return d
    }

    /// Concentric lines: the first starts `first` px inside the edge, then every `step`, each `lw` thick, `count` of them.
    static func echoAlpha(_ dist: [Float], _ first: Double, _ step: Double, _ lw: Double, _ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: dist.count)
        for i in 0..<dist.count {
            let dv = Double(dist[i])
            if dv <= 0 { continue }
            let k = Int(((dv - first - lw / 2) / step).rounded())
            if k < 0 || k >= count { continue }
            let c = first + lw / 2 + Double(k) * step
            out[i] = UInt8(max(0, min(255, (lw / 2 + 0.5 - abs(dv - c)) * 255)))
        }
        return out
    }

    /// Thin clear lines inside the stroke's own band, concentric, collapsing to its centre line.
    static func echoInside(_ w: PixelBuffer, _ B: Brush, size: Double, box: CGRect) {
        let bx = clampBox(box, w.w, w.h, pad: 0)
        let bw = Int(bx.width), bh = Int(bx.height)
        guard bw >= 4, bh >= 4 else { return }
        var alpha = [UInt8](repeating: 0, count: bw * bh)
        for y in 0..<bh { for x in 0..<bw { alpha[y * bw + x] = w.ptr[((Int(bx.minY) + y) * w.w + Int(bx.minX) + x) * 4 + 3] } }
        let dist = edt(alpha, bw, bh, thr: 90)
        let gw = max(1.2, B.n("echoGap") * size), st = max(gw + 1.5, B.n("echoStep") * size)
        let a = echoAlpha(dist, st - gw / 2, st, gw, Int(B.n("echo").rounded()))
        guard let g = PixelBuffer(w: bw, h: bh) else { return }
        for i in 0..<(bw * bh) { let v = a[i]; g.ptr[i * 4] = v; g.ptr[i * 4 + 1] = v; g.ptr[i * 4 + 2] = v; g.ptr[i * 4 + 3] = v }
        if let gi = g.image() { put(gi, into: w, x: Double(bx.minX), y: Double(bx.minY), blend: .destinationOut) }
    }
}

extension NativeCanvasModel {
    /// Called for every dab of a brush with a channel that clears only at its sides: the same dab slid sideways both ways, in black.
    func sideStamp(_ dab: Dab, _ B: Brush, size: Double, doc d: NativeDoc) {
        if chan1 == nil { chan1 = PixelBuffer(w: d.w, h: d.h) }
        if B.n("channel2") > 0, chan2 == nil { chan2 = PixelBuffer(w: d.w, h: d.h) }
        let HB = haloBrush ?? B.setting("flow", 1.0).setting("grain", "none").setting("pressOp", 0.0)
        haloBrush = HB
        let rad = B.n("channel") * size, nx = cos(dab.dir + .pi / 2) * rad, ny = sin(dab.dir + .pi / 2) * rad, asym = B.n("channelAsym")
        func stamp(_ buf: PixelBuffer?, _ k: Double, _ scale: Double) {
            guard let buf else { return }
            var d2 = dab; d2.am = 1
            let kk = k * (k < 0 ? 1 + asym : 1 - asym) * scale
            d2.x = dab.x + nx * kk; d2.y = dab.y + ny * kk
            NativeStamp.drawWithTwin(buf.ctx, HB, color: "#000000", color2: "#000000", size: size, d2)
        }
        for k in [-1.0, -0.5, 0.5, 1.0] { stamp(chan1, k, 1) }
        stamp(chan1, 0, 1)
        if B.n("channel2") > 0 {
            let k2 = (B.n("channel") + B.n("channel2")) / B.n("channel")
            for k in [-1.0, -0.5, 0.5, 1.0] { stamp(chan2, k, k2) }
            stamp(chan2, 0, k2)
        }
    }

    func clearSideBuffers(_ box: CGRect) { chan1?.clear(box); chan2?.clear(box) }
}

extension NativeCanvasModel {
    /// Weave: where this stroke crosses an earlier one, the first crossing goes over, the next under, the next over: the stroke is cut
    /// (with the channel's gap) around the line it passes under.
    func weaveCut(wet w: PixelBuffer, layer L: PixelBuffer, brush B: Brush, size: Double, pts: [[Any]], box: CGRect) {
        let bx = NativeEffects.clampBox(box, w.w, w.h, pad: 0)
        let rw = Int(bx.width), rh = Int(bx.height), rx = Int(bx.minX), ry = Int(bx.minY)
        guard rw >= 4, rh >= 4, !pts.isEmpty else { return }
        let rad = (B.n("channel") == 0 ? 0.15 : B.n("channel")) * size + 3
        func oldA(_ x: Int, _ y: Int) -> UInt8 { L.ptr[((ry + y) * L.w + rx + x) * 4 + 3] }
        func newA(_ x: Int, _ y: Int) -> UInt8 { w.ptr[((ry + y) * w.w + rx + x) * 4 + 3] }
        var lab = [Int32](repeating: 0, count: rw * rh)
        struct Comp { var x0: Int, y0: Int, x1: Int, y1: Int, cx: Double, cy: Double, at: Int }
        var comps: [Comp] = []
        for i in 0..<(rw * rh) {
            let ix = i % rw, iy = i / rw
            if lab[i] != 0 || oldA(ix, iy) < 40 || newA(ix, iy) < 40 { continue }
            let id = Int32(comps.count + 1)
            var st = [i]
            lab[i] = id
            var x0 = rw, y0 = rh, x1 = 0, y1 = 0, n = 0, sx = 0, sy = 0
            while let p = st.popLast() {
                let px = p % rw, py = p / rw
                n += 1; sx += px; sy += py
                x0 = min(x0, px); x1 = max(x1, px); y0 = min(y0, py); y1 = max(y1, py)
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = px + dx, ny = py + dy
                    if nx < 0 || ny < 0 || nx >= rw || ny >= rh { continue }
                    let q = ny * rw + nx
                    if lab[q] != 0 { continue }
                    if oldA(nx, ny) >= 40 && newA(nx, ny) >= 40 { lab[q] = id; st.append(q) }
                }
            }
            if n >= 30 { comps.append(Comp(x0: x0, y0: y0, x1: x1, y1: y1, cx: Double(sx) / Double(n) + Double(rx), cy: Double(sy) / Double(n) + Double(ry), at: 0)) }
        }
        guard !comps.isEmpty else { return }
        for k in comps.indices {
            var bi = 0, bd = 1e12
            for (i, q) in pts.enumerated() {
                let dx = Self.num(q[0]) - comps[k].cx, dy = Self.num(q[1]) - comps[k].cy
                let d = dx * dx + dy * dy
                if d < bd { bd = d; bi = i }
            }
            comps[k].at = bi
        }
        comps.sort { $0.at < $1.at }
        let r = Int(ceil(rad))
        for (n, k) in comps.enumerated() where n % 2 == 1 {   // the first crossing, the third...: over; the second, fourth...: under
            let wx0 = max(0, k.x0 - r - 2), wy0 = max(0, k.y0 - r - 2), wx1 = min(rw, k.x1 + r + 3), wy1 = min(rh, k.y1 + r + 3), ww = wx1 - wx0, wh = wy1 - wy0
            guard ww > 0, wh > 0 else { continue }
            var inv = [UInt8](repeating: 0, count: ww * wh)
            for yy in 0..<wh { for xx in 0..<ww { inv[yy * ww + xx] = oldA(wx0 + xx, wy0 + yy) >= 40 ? 0 : 255 } }   // the distance from the old stroke, found as the distance inside what is not it
            let dt = NativeEffects.edt(inv, ww, wh, thr: 128)
            for yy in 0..<wh { for xx in 0..<ww where Double(dt[yy * ww + xx]) <= rad {
                let i = ((ry + wy0 + yy) * w.w + rx + wx0 + xx) * 4
                w.ptr[i] = 0; w.ptr[i + 1] = 0; w.ptr[i + 2] = 0; w.ptr[i + 3] = 0
            } }
            let g = CGRect(x: Double(rx + wx0) - rad * 2, y: Double(ry + wy0) - rad * 2, width: Double(ww) + rad * 4, height: Double(wh) + rad * 4)
            clearSideBuffers(g)   // no clearance is cut into the earlier stroke where this one goes under it
        }
    }
}
