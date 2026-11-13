import CoreGraphics
import Foundation
import UIKit

/// The nine blend modes Core Animation does not have (the laptop's `blend.js`): Linear Burn, Darker Colour, Lighter Colour, Vivid Light,
/// Linear Light, Pin Light, Hard Mix, Subtract, Divide. Per pixel, in the W3C compositing formula with straight-alpha blend functions.
/// `apply` returns the backdrop with the source blended in; both are premultiplied RGBA the size of the picture.
enum NativeBlendCPU {
    private static func burn(_ b: Double, _ s: Double) -> Double { s <= 0 ? (b >= 1 ? 1 : 0) : 1 - min(1, (1 - b) / s) }
    private static func dodge(_ b: Double, _ s: Double) -> Double { s >= 1 ? 1 : min(1, b / (1 - s)) }
    private static func fn(_ mode: String) -> ((Double, Double) -> Double)? {
        switch mode {
        case "x-linear-burn": return { b, s in max(0, b + s - 1) }
        case "x-vivid-light": return { b, s in s <= 0.5 ? burn(b, 2 * s) : dodge(b, 2 * (s - 0.5)) }
        case "x-linear-light": return { b, s in min(1, max(0, b + 2 * s - 1)) }
        case "x-pin-light": return { b, s in s < 0.5 ? min(b, 2 * s) : max(b, 2 * (s - 0.5)) }
        case "x-hard-mix": return { b, s in b + s >= 1 ? 1 : 0 }
        case "x-subtract": return { b, s in max(0, b - s) }
        case "x-divide": return { b, s in s <= 0 ? 1 : min(1, b / s) }
        default: return nil
        }
    }

    /// Blends `src` into `dst` in place over the pixels both buffers hold (same size), at the layer's opacity.
    @MainActor static func apply(mode: String, into dst: PixelBuffer, from src: UnsafePointer<UInt8>, opacity: Double) {
        let n = dst.w * dst.h, B = dst.ptr, f = fn(mode), dark = mode == "x-darker-color"
        func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.3 * r + 0.59 * g + 0.11 * b }
        for p in 0..<n {
            let i = p * 4
            let sa = Double(src[i + 3]) / 255 * opacity
            if sa <= 0 { continue }
            let ab = Double(B[i + 3]) / 255
            // un-premultiply to straight colour
            let sR = src[i + 3] == 0 ? 0 : Double(src[i]) / Double(src[i + 3]), sG = src[i + 3] == 0 ? 0 : Double(src[i + 1]) / Double(src[i + 3]), sB = src[i + 3] == 0 ? 0 : Double(src[i + 2]) / Double(src[i + 3])
            let cR = B[i + 3] == 0 ? 0 : Double(B[i]) / Double(B[i + 3]), cG = B[i + 3] == 0 ? 0 : Double(B[i + 1]) / Double(B[i + 3]), cB = B[i + 3] == 0 ? 0 : Double(B[i + 2]) / Double(B[i + 3])
            let ao = sa + ab * (1 - sa)
            var br: Double, bg: Double, bb: Double
            if let f { br = f(cR, sR); bg = f(cG, sG); bb = f(cB, sB) }
            else {
                let lb = lum(cR, cG, cB), ls = lum(sR, sG, sB)
                let takeB = dark ? lb < ls : lb > ls
                br = takeB ? cR : sR; bg = takeB ? cG : sG; bb = takeB ? cB : sB
            }
            let kb = ab, ks = 1 - ab   // where the backdrop is empty the source shows as it is; where it is solid, the blend shows
            let rr = (sa * (ks * sR + kb * br) + (1 - sa) * ab * cR) / ao
            let rg = (sa * (ks * sG + kb * bg) + (1 - sa) * ab * cG) / ao
            let rb = (sa * (ks * sB + kb * bb) + (1 - sa) * ab * cB) / ao
            // back to premultiplied
            B[i] = UInt8(max(0, min(255, (rr * ao * 255).rounded())))
            B[i + 1] = UInt8(max(0, min(255, (rg * ao * 255).rounded())))
            B[i + 2] = UInt8(max(0, min(255, (rb * ao * 255).rounded())))
            B[i + 3] = UInt8(max(0, min(255, (ao * 255).rounded())))
        }
    }
}

extension NativeDoc {
    var usesCustomBlend: Bool {
        layers.contains { ($0.meta["blend"] as? String ?? "").hasPrefix("x-") && isShown($0) }
            || groups.contains { ($0["blend"] as? String ?? "").hasPrefix("x-") }
    }

    func groupID(_ i: Int) -> Int { layers[i].meta["grp"] as? Int ?? 0 }
    func group(_ id: Int) -> [String: Any]? { groups.first { ($0["id"] as? Int) == id } }

    /// The whole picture with every blend mode honoured (the nine PSD ones per pixel) and groups composed as groups. This is the one
    /// compositor: the screen uses it when a layer carries a PSD-only blend, and the share sheet, the merges, Send and the PSD use it always.
    func compositeBuffer(includeBackground: Bool = true, only: Range<Int>? = nil) -> PixelBuffer? {
        guard let out = PixelBuffer(w: w, h: h) else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        if includeBackground, bgVis, let col = Hex.color(bg) { out.ctx.setFillColor(col); out.ctx.fill(full) }
        guard let tmp = PixelBuffer(w: w, h: h) else { return nil }
        let range = only ?? 0..<layers.count
        var i = range.lowerBound
        while i < range.upperBound {
            let gid = groupID(i)
            if gid == 0 {
                if layers[i].visible { blend(layer: i, onto: out, tmp: tmp, opacity: layers[i].opacity) }
                i += 1
            } else {
                var j = i
                while j < range.upperBound && groupID(j) == gid { j += 1 }
                let g = group(gid)
                if g?["vis"] as? Bool ?? true, let sub = PixelBuffer(w: w, h: h) {
                    for k in i..<j where layers[k].visible { blend(layer: k, onto: sub, tmp: tmp, opacity: layers[k].opacity) }
                    let go = (g?["op"] as? Double) ?? Double(g?["op"] as? Int ?? 1)
                    let mode = g?["blend"] as? String ?? "source-over"
                    if let img = sub.image() { place(img, mode: mode, onto: out, tmp: tmp, opacity: go) }
                }
                i = j
            }
        }
        return out
    }

    private func place(_ img: CGImage, mode: String, onto out: PixelBuffer, tmp: PixelBuffer, opacity: Double) {
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        if mode.hasPrefix("x-") {
            tmp.ctx.clear(full); tmp.drawUpright(img, in: full)
            NativeBlendCPU.apply(mode: mode, into: out, from: UnsafePointer(tmp.ptr), opacity: opacity)
        } else {
            out.drawUpright(img, in: full, alpha: CGFloat(opacity), blend: NativeBlend.mode(mode).cg ?? .normal)
        }
    }
    private func blend(layer i: Int, onto out: PixelBuffer, tmp: PixelBuffer, opacity: Double) {
        guard let img = effectiveImage(of: i) else { return }
        place(img, mode: layers[i].meta["blend"] as? String ?? "source-over", onto: out, tmp: tmp, opacity: opacity)
    }

    /// A layer's picture with its mask applied and, if it is clipped, cut to the layer below it.
    func effectiveImage(of i: Int) -> CGImage? {
        let l = layers[i]
        guard var img = l.pixels.image() else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        func through(_ m: CGImage) {
            guard let t = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            t.draw(img, in: full); t.setBlendMode(.destinationIn); t.draw(m, in: full)
            if let o = t.makeImage() { img = o }
        }
        if let mk = l.maskPx?.image() { through(mk) }
        if let b = clipBase(of: i), let base = layers[b].pixels.image() { through(base) }
        return img
    }
}
