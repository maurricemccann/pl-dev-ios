import CoreGraphics
import Foundation
import UIKit

enum SelShape: String, CaseIterable, Sendable { case auto, free, rect, ellipse }
enum SelOp: String, CaseIterable, Sendable { case replace, add, remove }

/// The selection: a white mask the size of the picture, alpha = how much is selected. `sharp` is what was drawn; `soft` is the same
/// after Feather, and is what limits strokes, fills, clears and transforms. Selecting is undoable (the mask is kept as runs).
@MainActor final class NativeSelection {
    let w: Int, h: Int
    let sharp: PixelBuffer
    private var softBuf: PixelBuffer?
    var has = false
    var feather = 0
    var tolerance = 32
    var shape: SelShape = .rect
    var op: SelOp = .replace
    private var clipCache: CGImage?
    private(set) var version = 0

    struct Snap { let has: Bool; let feather: Int; let w: Int; let h: Int; let runs: [UInt32] }

    init?(w: Int, h: Int) {
        guard let s = PixelBuffer(w: w, h: h) else { return nil }
        self.w = w; self.h = h; sharp = s
    }

    /// What limits drawing: the feathered mask when there is feather, else the sharp one.
    var mask: PixelBuffer { softBuf ?? sharp }

    private func changed() { clipCache = nil; version += 1 }

    /// Limits everything drawn next to the selection (a stroke, a fill, an erase). The context is a layer's y-down one; call inside
    /// save/restore. Does nothing when nothing is selected.
    func clip(_ c: CGContext) {
        guard has else { return }
        if clipCache == nil {
            let n = w * h, p = mask.ptr
            var a = Data(count: n)
            a.withUnsafeMutableBytes { o in for i in 0..<n { o[i] = p[i * 4 + 3] } }
            if let prov = CGDataProvider(data: a as CFData) {
                // an image mask paints where its sample is 0; the decode array turns that round, so 255 (selected) paints
                clipCache = CGImage(maskWidth: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, provider: prov, decode: [1, 0], shouldInterpolate: false)
            }
        }
        guard let m = clipCache else { return }
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)   // the picture is upright, the layer context is y-down
        c.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: m)
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)   // and back (flipping twice is the identity)
    }

    // MARK: shapes

    /// Adds, removes or replaces with a shape. `fill` draws the shape in the context it is given (the context is y-down, white is set).
    func combine(_ fill: (CGContext) -> Void) {
        if op == .remove && !has { return }
        let c = sharp.ctx
        c.saveGState()
        if op == .replace || !has { c.clear(CGRect(x: 0, y: 0, width: w, height: h)) }
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        c.setBlendMode(op == .remove && has ? .destinationOut : .normal)
        fill(c)
        c.restoreGState()
        has = true
        refreshSoft()
    }

    func rect(_ r: CGRect) { combine { $0.fill(r) } }
    func ellipse(_ r: CGRect) { combine { $0.fillEllipse(in: r) } }
    func polygon(_ pts: [CGPoint]) {
        guard pts.count >= 3 else { return }
        combine { c in c.addLines(between: pts); c.closePath(); c.fillPath() }
    }

    func clear() {
        sharp.ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        softBuf = nil; has = false; changed()
    }

    func invert() {
        let n = w * h
        let p = sharp.ptr
        for i in 0..<n {
            let a = 255 - p[i * 4 + 3]
            p[i * 4] = a; p[i * 4 + 1] = a; p[i * 4 + 2] = a; p[i * 4 + 3] = a
        }
        has = true
        refreshSoft()
    }

    /// Automatic: the area of one colour around a tap (a flood fill within a colour distance on the layer's pixels).
    func auto(from layer: PixelBuffer, x: Int, y: Int) {
        guard x >= 0, y >= 0, x < w, y < h, layer.w == w, layer.h == h else { return }
        if op == .remove && !has { return }
        let d = layer.ptr, t = tolerance
        let i0 = (y * w + x) * 4
        let r0 = Int(d[i0]), g0 = Int(d[i0 + 1]), b0 = Int(d[i0 + 2]), a0 = Int(d[i0 + 3])
        var seen = [UInt8](repeating: 0, count: w * h)
        var stack = [Int32](); stack.reserveCapacity(4096)
        stack.append(Int32(y * w + x)); seen[y * w + x] = 1
        while let p32 = stack.popLast() {
            let p = Int(p32), xx = p % w, yy = p / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = xx + dx, ny = yy + dy
                if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                let q = ny * w + nx
                if seen[q] != 0 { continue }
                seen[q] = 1
                let k = q * 4
                if abs(Int(d[k]) - r0) <= t && abs(Int(d[k + 1]) - g0) <= t && abs(Int(d[k + 2]) - b0) <= t && abs(Int(d[k + 3]) - a0) <= t { stack.append(Int32(q)) }
            }
        }
        // seen==1 marks both visited-and-inside and visited-and-rejected; walk again to keep only the inside ones
        let s = sharp.ptr
        let replace = op == .replace || !has
        for i in 0..<(w * h) {
            var inside = false
            if seen[i] != 0 { let k = i * 4; inside = abs(Int(d[k]) - r0) <= t && abs(Int(d[k + 1]) - g0) <= t && abs(Int(d[k + 2]) - b0) <= t && abs(Int(d[k + 3]) - a0) <= t }
            let cur = replace ? 0 : s[i * 4 + 3]
            var v = cur
            if op == .remove && has { if inside { v = 0 } } else { if inside { v = 255 } }
            s[i * 4] = v; s[i * 4 + 1] = v; s[i * 4 + 2] = v; s[i * 4 + 3] = v
        }
        has = true
        refreshSoft()
    }

    // MARK: feather

    func setFeather(_ f: Int) { feather = f; refreshSoft() }

    /// A box blur three times over the alpha plane approximates a Gaussian; the radius is the laptop's feather in pixels.
    func refreshSoft() {
        changed()
        guard has, feather > 0 else { softBuf = nil; return }
        let n = w * h
        var a = [UInt8](repeating: 0, count: n)
        let s = sharp.ptr
        for i in 0..<n { a[i] = s[i * 4 + 3] }
        var tmp = [UInt8](repeating: 0, count: n)
        let r = max(1, Int((Double(feather) * 0.58).rounded()))
        for _ in 0..<3 {
            Self.boxH(a, &tmp, w, h, r)
            Self.boxV(tmp, &a, w, h, r)
        }
        if softBuf == nil { softBuf = PixelBuffer(w: w, h: h) }
        guard let o = softBuf?.ptr else { return }
        for i in 0..<n { let v = a[i]; o[i * 4] = v; o[i * 4 + 1] = v; o[i * 4 + 2] = v; o[i * 4 + 3] = v }
    }

    private static func boxH(_ src: [UInt8], _ dst: inout [UInt8], _ w: Int, _ h: Int, _ r: Int) {
        let win = 2 * r + 1
        for y in 0..<h {
            let row = y * w
            var sum = 0
            for x in -r...r { sum += Int(src[row + min(w - 1, max(0, x))]) }
            for x in 0..<w {
                dst[row + x] = UInt8(sum / win)
                sum += Int(src[row + min(w - 1, x + r + 1)]) - Int(src[row + max(0, x - r)])
            }
        }
    }
    private static func boxV(_ src: [UInt8], _ dst: inout [UInt8], _ w: Int, _ h: Int, _ r: Int) {
        let win = 2 * r + 1
        for x in 0..<w {
            var sum = 0
            for y in -r...r { sum += Int(src[min(h - 1, max(0, y)) * w + x]) }
            for y in 0..<h {
                dst[y * w + x] = UInt8(sum / win)
                sum += Int(src[min(h - 1, y + r + 1) * w + x]) - Int(src[max(0, y - r) * w + x])
            }
        }
    }

    // MARK: history

    func snapshot() -> Snap {
        var runs: [UInt32] = []
        let s = sharp.ptr, n = w * h
        guard has, n > 0 else { return Snap(has: has, feather: feather, w: w, h: h, runs: []) }
        var v = s[3], k: UInt32 = 1
        for i in 1..<n {
            let x = s[i * 4 + 3]
            if x == v && k < 65535 { k += 1 } else { runs.append(UInt32(v)); runs.append(k); v = x; k = 1 }
        }
        runs.append(UInt32(v)); runs.append(k)
        return Snap(has: true, feather: feather, w: w, h: h, runs: runs)
    }

    func restore(_ snap: Snap) {
        guard snap.w == w, snap.h == h else { return }
        let s = sharp.ptr
        if !snap.has { clear(); return }
        var p = 0, i = 0
        while i + 1 < snap.runs.count {
            let v = UInt8(snap.runs[i]), k = Int(snap.runs[i + 1])
            for _ in 0..<k where p < w * h { s[p * 4] = v; s[p * 4 + 1] = v; s[p * 4 + 2] = v; s[p * 4 + 3] = v; p += 1 }
            i += 2
        }
        feather = snap.feather; has = true
        refreshSoft()
    }

    // MARK: on screen

    /// The unselected area under a diagonal stripe, at most 1,100 pixels on the long side (it is laid over the picture at full size).
    func overlayImage() -> CGImage? {
        guard has else { return nil }
        let k = min(1, 1100 / Double(max(w, h)))
        let ow = max(1, Int(Double(w) * k)), oh = max(1, Int(Double(h) * k))
        guard let c = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.setFillColor(CGColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 0.32)); c.fill(CGRect(x: 0, y: 0, width: ow, height: oh))
        c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.4)); c.setLineWidth(2)
        var x = -oh; while x < ow + oh { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x + oh, y: oh)); x += 14 }
        c.strokePath()
        c.setBlendMode(.destinationOut)
        if let img = mask.image() { c.draw(img, in: CGRect(x: 0, y: 0, width: ow, height: oh)) }
        return c.makeImage()
    }
}
