import Accelerate
import CoreGraphics
import CoreText
import Foundation
import UIKit

// The native half of the Canvas 2D bridge (his order 11-13: his piece code runs unchanged in JavaScriptCore).
// `prelude.js` records every canvas call as numbers; `CanvasSurface.run` replays them on a Core Graphics bitmap.
// Everything here runs on the one JavaScript queue (`PieceRuntime.queue`), so nothing is locked.
//
// Pixels: premultiplied RGBA, 8 bit, row 0 on top, user space y-down like the browser (a flip is the base transform).

/// Every surface, decoded image and font the running pieces can name. One per runtime.
final class CanvasWorld: @unchecked Sendable {
    var surfaces: [Int: CanvasSurface] = [:]
    var images: [Int: CGImage] = [:]
    var bytesSinceCollect = 0
    var liveBytes = 0
    func surface(_ id: Int) -> CanvasSurface? { surfaces[id] }
}

struct GradientDef {
    var kind: Int   // 0 linear, 1 radial
    var x0: CGFloat, y0: CGFloat, r0: CGFloat, x1: CGFloat, y1: CGFloat, r1: CGFloat
    var stops: [(CGFloat, CGColor)] = []
    var cached: CGGradient?
}

struct PatternDef {
    var tile: CGImage        // already flipped top to bottom, so it draws upright in y-down user space
    var w: Int
    var h: Int
    var repeatMode: Int      // 0 none, 1 both, 2 x, 3 y
    var xf: CGAffineTransform = .identity
}

enum PaintStyle {
    case color(CGColor)
    case gradient(Int)
    case pattern(Int)
}

/// The canvas state the browser keeps and Core Graphics does not (or keeps in a way that is awkward to share).
struct DrawState {
    var fill: PaintStyle = .color(CSSColor.black)
    var stroke: PaintStyle = .color(CSSColor.black)
    var fontSpec = "10px sans-serif"
    var font: CTFont = FontResolver.font(for: "10px sans-serif")
    var align = 0
    var baseline = 0
    var spacing: CGFloat = 0
    var blur: CGFloat = 0
    var smoothing = true
    var lineWidth: CGFloat = 1
    var cap = 0
    var join = 0
    var miter: CGFloat = 10
    var dash: [CGFloat] = []
    var dashPhase: CGFloat = 0
    var shadowColor: CGColor = CSSColor.clear
    var shadowBlur: CGFloat = 0
    var shadowOX: CGFloat = 0
    var shadowOY: CGFloat = 0
    var alpha: CGFloat = 1
    var blend: CGBlendMode = .normal
}

final class CanvasSurface: @unchecked Sendable {
    let id: Int
    private(set) var w: Int
    private(set) var h: Int
    private(set) var data: UnsafeMutableRawPointer
    private(set) var gc: CGContext
    unowned let world: CanvasWorld

    private var st = DrawState()
    private var stack: [DrawState] = []
    private var m: CGAffineTransform = .identity
    private var path = CGMutablePath()
    private var pathM: CGAffineTransform = .identity
    private var gradients: [Int: GradientDef] = [:]
    private var patterns: [Int: PatternDef] = [:]
    private var temp: CanvasSurface?   // the scratch layer a blur is drawn into

    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static var baseInfo: UInt32 { CGImageAlphaInfo.premultipliedLast.rawValue }

    init(id: Int, w: Int, h: Int, world: CanvasWorld) {
        self.id = id
        self.world = world
        let (ww, hh) = (max(1, w), max(1, h))
        self.w = ww
        self.h = hh
        let buf = calloc(ww * hh, 4)!
        data = buf
        gc = Self.makeContext(buf, ww, hh)
        world.liveBytes += ww * hh * 4
        world.bytesSinceCollect += ww * hh * 4
    }

    deinit {
        world.liveBytes -= w * h * 4
        free(data)
    }

    private static func makeContext(_ data: UnsafeMutableRawPointer, _ w: Int, _ h: Int) -> CGContext {
        let c = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: baseInfo)!
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: 1, y: -1)
        c.setAllowsAntialiasing(true)
        c.setShouldAntialias(true)
        c.interpolationQuality = .high
        c.setLineCap(.butt)
        c.setLineJoin(.miter)
        return c
    }

    /// A new size clears the canvas and resets its state, as in the browser.
    func resize(_ nw: Int, _ nh: Int) {
        let (ww, hh) = (max(1, nw), max(1, nh))
        world.liveBytes += ww * hh * 4 - w * h * 4
        world.bytesSinceCollect += ww * hh * 4
        free(data)
        w = ww
        h = hh
        let buf = calloc(ww * hh, 4)!
        data = buf
        gc = Self.makeContext(buf, ww, hh)
        st = DrawState()
        stack.removeAll()
        m = .identity
        path = CGMutablePath()
        pathM = .identity
        gradients.removeAll()
        patterns.removeAll()
        temp = nil
    }

    func snapshot() -> CGImage? { gc.makeImage() }

    // MARK: pixels

    /// Unpremultiplied RGBA, as `getImageData` returns it.
    func read(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, into out: UnsafeMutablePointer<UInt8>) {
        let src = data.assumingMemoryBound(to: UInt8.self)
        for row in 0..<rh {
            let sy = y + row
            for col in 0..<rw {
                let sx = x + col
                let o = (row * rw + col) * 4
                if sx < 0 || sy < 0 || sx >= w || sy >= h { out[o] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 0; continue }
                let s = (sy * w + sx) * 4
                let a = Int(src[s + 3])
                if a == 255 || a == 0 { out[o] = src[s]; out[o + 1] = src[s + 1]; out[o + 2] = src[s + 2]; out[o + 3] = src[s + 3] }
                else {
                    out[o] = UInt8(min(255, (Int(src[s]) * 255 + a / 2) / a))
                    out[o + 1] = UInt8(min(255, (Int(src[s + 1]) * 255 + a / 2) / a))
                    out[o + 2] = UInt8(min(255, (Int(src[s + 2]) * 255 + a / 2) / a))
                    out[o + 3] = UInt8(a)
                }
            }
        }
    }

    /// `putImageData`: written straight into the bitmap (no blending), premultiplied on the way in.
    func write(_ px: UnsafePointer<UInt8>, iw: Int, ih: Int, dx: Int, dy: Int, sx: Int, sy: Int, sw: Int, sh: Int) {
        let dst = data.assumingMemoryBound(to: UInt8.self)
        for row in 0..<max(0, sh) {
            let srow = sy + row
            let drow = dy + sy + row
            if srow < 0 || srow >= ih || drow < 0 || drow >= h { continue }
            for col in 0..<max(0, sw) {
                let scol = sx + col
                let dcol = dx + sx + col
                if scol < 0 || scol >= iw || dcol < 0 || dcol >= w { continue }
                let s = (srow * iw + scol) * 4
                let d = (drow * w + dcol) * 4
                let a = Int(px[s + 3])
                if a == 255 { dst[d] = px[s]; dst[d + 1] = px[s + 1]; dst[d + 2] = px[s + 2]; dst[d + 3] = 255 }
                else {
                    dst[d] = UInt8((Int(px[s]) * a + 127) / 255)
                    dst[d + 1] = UInt8((Int(px[s + 1]) * a + 127) / 255)
                    dst[d + 2] = UInt8((Int(px[s + 2]) * a + 127) / 255)
                    dst[d + 3] = UInt8(a)
                }
            }
        }
    }

    // MARK: replay

    /// Operand counts per opcode (prelude.js `OP`); 46 (dash) is variable.
    private static let argc: [Int] = {
        var a = [Int](repeating: -1, count: 64)
        let t: [(Int, Int)] = [(1, 0), (2, 0), (3, 2), (4, 2), (5, 1), (6, 6), (7, 6), (8, 0), (9, 2), (10, 2), (11, 6), (12, 4), (13, 6), (14, 5), (15, 8), (16, 4), (17, 0), (18, 1), (19, 0), (20, 1),
                               (21, 4), (22, 4), (23, 4), (24, 1), (25, 1), (26, 1), (27, 1), (28, 1), (29, 1), (30, 1), (31, 1), (32, 1), (33, 1), (34, 1), (35, 1), (36, 1), (37, 1), (38, 1), (39, 1), (40, 1),
                               (41, 1), (42, 1), (43, 4), (44, 4), (45, 10), (47, 1), (48, 1), (49, 8), (50, 3), (51, 4), (52, 2), (53, 1), (54, 2), (55, 1), (56, 1), (57, 7)]
        for (c, n) in t { a[c] = n }
        return a
    }()

    func run(_ nums: UnsafePointer<Double>, count: Int, strs: [String]) {
        var i = 0
        while i < count {
            let code = Int(nums[i])
            i += 1
            var n = (code >= 0 && code < Self.argc.count) ? Self.argc[code] : -1
            if code == 46 { if i >= count { return }; n = 1 + min(8, max(0, Int(nums[i]))) }
            if n < 0 { return }   // a stream we cannot read: stop rather than guess
            if i + n > count { return }
            var finite = true
            for k in 0..<n where !nums[i + k].isFinite { finite = false; break }
            if finite {
                op(code, nums + i, strs)
            }
            i += n
        }
    }

    @inline(__always) private func str(_ nums: UnsafePointer<Double>, _ k: Int, _ strs: [String]) -> String {
        let ix = Int(nums[k])
        return ix >= 0 && ix < strs.count ? strs[ix] : ""
    }

    private func pt(_ nums: UnsafePointer<Double>, _ k: Int) -> CGPoint { CGPoint(x: nums[k], y: nums[k + 1]) }

    /// The matrix that maps what has been added to the current path into the path's own space, when the canvas matrix has moved on.
    private var pathXf: CGAffineTransform {
        m == pathM ? .identity : (pathM.isInvertible ? m.concatenating(pathM.inverted()) : .identity)
    }

    private func op(_ code: Int, _ a: UnsafePointer<Double>, _ strs: [String]) {
        switch code {
        case 1: save()
        case 2: restore()
        case 3: gc.translateBy(x: a[0], y: a[1]); m = m.translatedBy(x: a[0], y: a[1])
        case 4: gc.scaleBy(x: a[0], y: a[1]); m = m.scaledBy(x: a[0], y: a[1])
        case 5: gc.rotate(by: a[0]); m = m.rotated(by: a[0])
        case 6:
            let t = CGAffineTransform(a: a[0], b: a[1], c: a[2], d: a[3], tx: a[4], ty: a[5])
            gc.concatenate(t); m = t.concatenating(m)
        case 7:
            let t = CGAffineTransform(a: a[0], b: a[1], c: a[2], d: a[3], tx: a[4], ty: a[5])
            let cur = gc.ctm
            if cur.isInvertible { gc.concatenate(cur.inverted()) }
            gc.translateBy(x: 0, y: CGFloat(h)); gc.scaleBy(x: 1, y: -1)
            gc.concatenate(t); m = t
        case 8: path = CGMutablePath(); pathM = m
        case 9: path.move(to: pt(a, 0), transform: pathXf)
        case 10:
            if path.isEmpty { path.move(to: pt(a, 0), transform: pathXf) } else { path.addLine(to: pt(a, 0), transform: pathXf) }
        case 11:
            if path.isEmpty { path.move(to: pt(a, 0), transform: pathXf) }
            path.addCurve(to: pt(a, 4), control1: pt(a, 0), control2: pt(a, 2), transform: pathXf)
        case 12:
            if path.isEmpty { path.move(to: pt(a, 0), transform: pathXf) }
            path.addQuadCurve(to: pt(a, 2), control: pt(a, 0), transform: pathXf)
        case 13:
            let r = a[2]
            if r < 0 { return }
            var end = a[4]
            let start = a[3]
            let tau = Double.pi * 2
            if abs(end - start) >= tau { end = start + (end >= start ? tau : -tau) }
            path.addArc(center: pt(a, 0), radius: r, startAngle: start, endAngle: end, clockwise: a[5] != 0, transform: pathXf)
        case 14:
            if path.isEmpty { path.move(to: pt(a, 0), transform: pathXf) }
            if a[4] <= 0 { path.addLine(to: pt(a, 0), transform: pathXf) }
            else { path.addArc(tangent1End: pt(a, 0), tangent2End: pt(a, 2), radius: a[4], transform: pathXf) }
        case 15:
            let start = a[5]
            var end = a[6]
            let tau = Double.pi * 2
            if abs(end - start) >= tau { end = start + (end >= start ? tau : -tau) }
            if a[2] < 0 || a[3] < 0 { return }
            let t = CGAffineTransform(translationX: a[0], y: a[1]).rotated(by: a[4]).scaledBy(x: max(a[2], 1e-6), y: max(a[3], 1e-6))
            path.addArc(center: .zero, radius: 1, startAngle: start, endAngle: end, clockwise: a[7] != 0, transform: t.concatenating(pathXf))
        case 16: path.addRect(CGRect(x: a[0], y: a[1], width: a[2], height: a[3]), transform: pathXf)
        case 17: path.closeSubpath()
        case 18: fillCurrent(rule: a[0] != 0 ? .evenOdd : .winding)
        case 19: strokeCurrent()
        case 20: gc.addPath(pathForDraw()); gc.clip(using: a[0] != 0 ? .evenOdd : .winding)
        case 21: filtered { fillPath(CGPath(rect: CGRect(x: a[0], y: a[1], width: a[2], height: a[3]), transform: nil), rule: .winding) }
        case 22: filtered { strokePath(CGPath(rect: CGRect(x: a[0], y: a[1], width: a[2], height: a[3]), transform: nil)) }
        case 23: gc.clear(CGRect(x: a[0], y: a[1], width: a[2], height: a[3]))
        case 24: if let c = CSSColor.parse(str(a, 0, strs)) { st.fill = .color(c) }
        case 25: if let c = CSSColor.parse(str(a, 0, strs)) { st.stroke = .color(c) }
        case 26: st.fill = .gradient(Int(a[0]))
        case 27: st.stroke = .gradient(Int(a[0]))
        case 28: st.fill = .pattern(Int(a[0]))
        case 29: st.stroke = .pattern(Int(a[0]))
        case 30: st.lineWidth = a[0]
        case 31: st.cap = Int(a[0])
        case 32: st.join = Int(a[0])
        case 33: st.miter = a[0]
        case 34: st.alpha = max(0, min(1, a[0])); gc.setAlpha(st.alpha)
        case 35: st.blend = CSSBlend.mode(str(a, 0, strs)); gc.setBlendMode(st.blend)
        case 36: if let c = CSSColor.parse(str(a, 0, strs)) { st.shadowColor = c; applyShadow() }
        case 37: st.shadowBlur = max(0, a[0]); applyShadow()
        case 38: st.shadowOX = a[0]; applyShadow()
        case 39: st.shadowOY = a[0]; applyShadow()
        case 40: st.fontSpec = str(a, 0, strs); st.font = FontResolver.font(for: st.fontSpec)
        case 41: st.align = Int(a[0])
        case 42: st.baseline = Int(a[0])
        case 43: filtered { drawText(str(a, 0, strs), a[1], a[2], a[3], stroke: false) }
        case 44: filtered { drawText(str(a, 0, strs), a[1], a[2], a[3], stroke: true) }
        case 45: filtered { drawImage(kind: Int(a[0]), id: Int(a[1]), sx: a[2], sy: a[3], sw: a[4], sh: a[5], dx: a[6], dy: a[7], dw: a[8], dh: a[9]) }
        case 46:
            let k = min(8, max(0, Int(a[0])))
            st.dash = (0..<k).map { CGFloat(a[1 + $0]) }
            if st.dash.contains(where: { $0 < 0 }) || st.dash.reduce(0, +) <= 0 { st.dash = [] }
        case 47: st.dashPhase = a[0]
        case 48: st.smoothing = a[0] != 0; gc.interpolationQuality = st.smoothing ? .high : .none
        case 49:
            var g = GradientDef(kind: Int(a[1]), x0: a[2], y0: a[3], r0: a[4], x1: a[5], y1: a[6], r1: a[7])
            g.stops = []
            gradients[Int(a[0])] = g
            if gradients.count > 4096 { for k in gradients.keys.sorted().prefix(1024) { gradients[k] = nil } }
        case 50:
            if var g = gradients[Int(a[0])], let c = CSSColor.parse(str(a, 2, strs)) {
                g.stops.append((max(0, min(1, a[1])), c)); g.cached = nil
                gradients[Int(a[0])] = g
            }
        case 51:
            let kind = Int(a[1]), sid = Int(a[2])
            let img: CGImage? = kind == 0 ? world.surface(sid)?.snapshot() : world.images[sid]
            if let img, let tile = Self.flipped(img) {
                patterns[Int(a[0])] = PatternDef(tile: tile, w: img.width, h: img.height, repeatMode: Int(a[3]))
                if patterns.count > 256 { for k in patterns.keys.sorted().prefix(64) { patterns[k] = nil } }
            }
        case 52: if let p = SVGPath.cached(str(a, 0, strs)) { filtered { fillPath(p, rule: a[1] != 0 ? .evenOdd : .winding) } }
        case 53: if let p = SVGPath.cached(str(a, 0, strs)) { filtered { strokePath(p) } }
        case 54: if let p = SVGPath.cached(str(a, 0, strs)) { gc.addPath(p); gc.clip(using: a[1] != 0 ? .evenOdd : .winding) }
        case 55: st.blur = CSSFilter.blur(str(a, 0, strs))
        case 56: st.spacing = a[0]
        case 57: if var p = patterns[Int(a[0])] { p.xf = CGAffineTransform(a: a[1], b: a[2], c: a[3], d: a[4], tx: a[5], ty: a[6]); patterns[Int(a[0])] = p }
        default: break
        }
    }

    // MARK: state

    private func save() {
        gc.saveGState()
        stack.append(st)
        savedM.append(m)
    }

    private var savedM: [CGAffineTransform] = []

    private func restore() {
        guard let s = stack.popLast() else { return }
        gc.restoreGState()
        st = s
        if let sm = savedM.popLast() { m = sm }
    }

    private func applyShadow() {
        let alpha = st.shadowColor.alpha
        if alpha > 0 && (st.shadowBlur > 0 || st.shadowOX != 0 || st.shadowOY != 0) {
            gc.setShadow(offset: CGSize(width: st.shadowOX, height: -st.shadowOY), blur: st.shadowBlur, color: st.shadowColor)
        } else {
            gc.setShadow(offset: .zero, blur: 0, color: nil)
        }
    }

    private func applyStroke() {
        gc.setLineWidth(st.lineWidth)
        gc.setLineCap(st.cap == 1 ? .round : st.cap == 2 ? .square : .butt)
        gc.setLineJoin(st.join == 1 ? .round : st.join == 2 ? .bevel : .miter)
        gc.setMiterLimit(st.miter)
        if st.dash.isEmpty { gc.setLineDash(phase: 0, lengths: []) } else { gc.setLineDash(phase: st.dashPhase, lengths: st.dash) }
    }

    // MARK: drawing

    private func pathForDraw() -> CGPath {
        if m == pathM { return path }
        guard m.isInvertible else { return CGMutablePath() }
        var t = pathM.concatenating(m.inverted())
        return path.copy(using: &t) ?? path
    }

    private func fillCurrent(rule: CGPathFillRule) { let p = pathForDraw(); filtered { fillPath(p, rule: rule) } }
    private func strokeCurrent() { let p = pathForDraw(); filtered { strokePath(p) } }

    private func fillPath(_ p: CGPath, rule: CGPathFillRule) {
        switch st.fill {
        case .color(let c):
            gc.setFillColor(c)
            gc.addPath(p)
            gc.fillPath(using: rule)
        case .gradient(let id):
            gc.saveGState(); gc.addPath(p); gc.clip(using: rule); drawGradient(id); gc.restoreGState()
        case .pattern(let id):
            gc.saveGState(); gc.addPath(p); gc.clip(using: rule); drawPattern(id); gc.restoreGState()
        }
    }

    private func strokePath(_ p: CGPath) {
        applyStroke()
        switch st.stroke {
        case .color(let c):
            gc.setStrokeColor(c)
            gc.addPath(p)
            gc.strokePath()
        case .gradient(let id):
            gc.saveGState(); gc.addPath(p); gc.replacePathWithStrokedPath(); gc.clip(); drawGradient(id); gc.restoreGState()
        case .pattern(let id):
            gc.saveGState(); gc.addPath(p); gc.replacePathWithStrokedPath(); gc.clip(); drawPattern(id); gc.restoreGState()
        }
    }

    private func drawGradient(_ id: Int) {
        guard var g = gradients[id], !g.stops.isEmpty else { return }
        if g.cached == nil {
            var stops = g.stops.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }.map(\.element)
            if stops.count == 1 { stops.append(stops[0]) }
            g.cached = CGGradient(colorsSpace: Self.space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))
            gradients[id] = g
        }
        guard let grad = g.cached else { return }
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        if g.kind == 0 {
            if g.x0 == g.x1 && g.y0 == g.y1 { return }
            gc.drawLinearGradient(grad, start: CGPoint(x: g.x0, y: g.y0), end: CGPoint(x: g.x1, y: g.y1), options: opts)
        } else {
            gc.drawRadialGradient(grad, startCenter: CGPoint(x: g.x0, y: g.y0), startRadius: max(0, g.r0), endCenter: CGPoint(x: g.x1, y: g.y1), endRadius: max(0, g.r1), options: opts)
        }
    }

    /// Tiles the pattern over the current clip, in the pattern's own space.
    private func drawPattern(_ id: Int) {
        guard let p = patterns[id], p.w > 0, p.h > 0, p.xf.isInvertible else { return }
        let bb = gc.boundingBoxOfClipPath
        if bb.isNull || bb.isInfinite || bb.isEmpty { return }
        gc.saveGState()
        gc.concatenate(p.xf)
        let r = bb.applying(p.xf.inverted())
        let tw = CGFloat(p.w), th = CGFloat(p.h)
        var x0 = Int(floor(r.minX / tw)), x1 = Int(ceil(r.maxX / tw)), y0 = Int(floor(r.minY / th)), y1 = Int(ceil(r.maxY / th))
        if p.repeatMode == 0 || p.repeatMode == 3 { x0 = 0; x1 = 1 }
        if p.repeatMode == 0 || p.repeatMode == 2 { y0 = 0; y1 = 1 }
        if (x1 - x0) * (y1 - y0) <= 40000 {
            for ty in y0..<max(y0, y1) {
                for tx in x0..<max(x0, x1) {
                    gc.draw(p.tile, in: CGRect(x: CGFloat(tx) * tw, y: CGFloat(ty) * th, width: tw, height: th))
                }
            }
        }
        gc.restoreGState()
    }

    private static func flipped(_ img: CGImage) -> CGImage? {
        guard let c = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: baseInfo) else { return nil }
        c.translateBy(x: 0, y: CGFloat(img.height))
        c.scaleBy(x: 1, y: -1)
        c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))   // mirrored top to bottom: a y-down draw turns it upright
        return c.makeImage()
    }

    private func drawImage(kind: Int, id: Int, sx: CGFloat, sy: CGFloat, sw: CGFloat, sh: CGFloat, dx: CGFloat, dy: CGFloat, dw: CGFloat, dh: CGFloat) {
        guard dw != 0, dh != 0, sw > 0, sh > 0 else { return }
        let src: CGImage?
        if kind == 0 { src = world.surface(id)?.snapshot() } else { src = world.images[id] }
        guard let img = src else { return }
        var crop = CGRect(x: sx, y: sy, width: sw, height: sh).integral
        crop = crop.intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        if crop.isNull || crop.isEmpty { return }
        guard let part = (crop.width == CGFloat(img.width) && crop.height == CGFloat(img.height)) ? img : img.cropping(to: crop) else { return }
        // keep the destination proportion of a clipped source edge
        var rect = CGRect(x: dx, y: dy, width: dw, height: dh)
        if crop.width != sw || crop.height != sh {
            let kx = dw / sw, ky = dh / sh
            rect = CGRect(x: dx + (crop.minX - sx) * kx, y: dy + (crop.minY - sy) * ky, width: crop.width * kx, height: crop.height * ky)
        }
        gc.saveGState()
        gc.interpolationQuality = st.smoothing ? .high : .none
        gc.translateBy(x: rect.minX, y: rect.maxY)
        gc.scaleBy(x: 1, y: -1)
        gc.draw(part, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        gc.restoreGState()
    }

    // MARK: text

    private func drawText(_ text: String, _ x: CGFloat, _ y: CGFloat, _ maxW: CGFloat, stroke: Bool) {
        if text.isEmpty { return }
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): st.font,
                                                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        if st.spacing != 0 { attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = st.spacing }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &asc, &desc, &lead))
        var px = x
        switch st.align { case 1: px -= width / 2; case 2: px -= width; default: break }
        var py = y
        switch st.baseline { case 1: py += asc; case 2: py += asc * 0.8; case 3: py += (asc - desc) / 2; case 4, 5: py -= desc; default: break }
        gc.saveGState()
        if maxW > 0 && width > maxW {
            gc.translateBy(x: x, y: 0); gc.scaleBy(x: maxW / width, y: 1); gc.translateBy(x: -x, y: 0)
        }
        gc.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        gc.textPosition = CGPoint(x: px, y: py)
        let style = stroke ? st.stroke : st.fill
        switch style {
        case .color(let c):
            if stroke { applyStroke(); gc.setStrokeColor(c); gc.setTextDrawingMode(.stroke) } else { gc.setFillColor(c); gc.setTextDrawingMode(.fill) }
            CTLineDraw(line, gc)
        case .gradient(let id):
            gc.setTextDrawingMode(.clip); CTLineDraw(line, gc); drawGradient(id)
        case .pattern(let id):
            gc.setTextDrawingMode(.clip); CTLineDraw(line, gc); drawPattern(id)
        }
        gc.restoreGState()
    }

    static func measure(font spec: String, text: String, spacing: CGFloat) -> Double {
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): FontResolver.font(for: spec)]
        if spacing != 0 { attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = spacing }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    // MARK: the blur filter

    /// Runs a draw; when `filter: blur(Npx)` is set, the draw goes to a scratch layer, which is blurred and composited.
    private func filtered(_ draw: () -> Void) {
        guard st.blur > 0.25 else { draw(); return }
        let t: CanvasSurface
        if let tt = temp, tt.w == w, tt.h == h { t = tt } else { t = CanvasSurface(id: -1, w: w, h: h, world: world); temp = t }
        memset(t.data, 0, w * h * 4)
        // draw into the scratch layer with the same matrix and the same styles, but plain compositing
        let main = gc
        let cur = t.gc.ctm
        if cur.isInvertible { t.gc.concatenate(cur.inverted()) }
        t.gc.concatenate(main.ctm)
        t.gc.setAlpha(1); t.gc.setBlendMode(.normal); t.gc.setShadow(offset: .zero, blur: 0, color: nil)
        t.gc.interpolationQuality = st.smoothing ? .high : .none
        gc = t.gc
        draw()
        gc = main
        t.blurInPlace(sigma: Double(st.blur))
        guard let img = t.gc.makeImage() else { return }
        main.saveGState()
        let ctm = main.ctm
        if ctm.isInvertible { main.concatenate(ctm.inverted()) }
        main.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))   // raw y-up space: the picture lands upright
        main.restoreGState()
    }

    /// Three box passes approximate a Gaussian of the given sigma.
    func blurInPlace(sigma: Double) {
        let k = max(1, Int(sigma.rounded()))
        let size = UInt32(k * 2 + 1)
        var buf = vImage_Buffer(data: data, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
        let tmp = calloc(w * h, 4)!
        defer { free(tmp) }
        var out = vImage_Buffer(data: tmp, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
        for _ in 0..<3 {
            vImageBoxConvolve_ARGB8888(&buf, &out, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend))
            memcpy(data, tmp, w * h * 4)
        }
    }
}

// MARK: - the small parsers

enum CSSBlend {
    static func mode(_ s: String) -> CGBlendMode {
        switch s {
        case "source-over": return .normal
        case "lighter": return .plusLighter
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "darken": return .darken
        case "lighten": return .lighten
        case "color-dodge": return .colorDodge
        case "color-burn": return .colorBurn
        case "hard-light": return .hardLight
        case "soft-light": return .softLight
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        case "source-in": return .sourceIn
        case "source-out": return .sourceOut
        case "source-atop": return .sourceAtop
        case "destination-over": return .destinationOver
        case "destination-in": return .destinationIn
        case "destination-out": return .destinationOut
        case "destination-atop": return .destinationAtop
        case "xor": return .xor
        case "copy": return .copy
        default: return .normal
        }
    }
}

enum CSSFilter {
    /// `blur(3px)` gives 3. Anything else (none, brightness, ...) gives 0: the draw is left plain.
    static func blur(_ s: String) -> CGFloat {
        guard let open = s.range(of: "blur("), let close = s.range(of: ")", range: open.upperBound..<s.endIndex) else { return 0 }
        let inner = s[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")
        return CGFloat(Double(inner) ?? 0)
    }
}

enum CSSColor {
    nonisolated(unsafe) private static var cache: [String: CGColor] = [:]
    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let black = CGColor(colorSpace: space, components: [0, 0, 0, 1])!
    static let clear = CGColor(colorSpace: space, components: [0, 0, 0, 0])!

    private static let named: [String: (CGFloat, CGFloat, CGFloat)] = [
        "white": (255, 255, 255), "black": (0, 0, 0), "red": (255, 0, 0), "green": (0, 128, 0), "blue": (0, 0, 255), "yellow": (255, 255, 0), "orange": (255, 165, 0),
        "gray": (128, 128, 128), "grey": (128, 128, 128), "gold": (255, 215, 0), "cyan": (0, 255, 255), "magenta": (255, 0, 255), "purple": (128, 0, 128), "pink": (255, 192, 203),
        "silver": (192, 192, 192), "brown": (165, 42, 42), "navy": (0, 0, 128), "teal": (0, 128, 128), "maroon": (128, 0, 0), "lime": (0, 255, 0), "ivory": (255, 255, 240), "tomato": (255, 99, 71),
        "crimson": (220, 20, 60), "coral": (255, 127, 80), "indigo": (75, 0, 130), "violet": (238, 130, 238), "beige": (245, 245, 220), "khaki": (240, 230, 140),
    ]

    /// nil when the string is not a colour (the canvas then keeps its previous style).
    static func parse(_ raw: String) -> CGColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let c = cache[s] { return c }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if s == "transparent" { a = 0 }
        else if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            let full: String
            switch hex.count {
            case 3, 4: full = hex.map { "\($0)\($0)" }.joined()
            case 6, 8: full = hex
            default: return nil
            }
            guard let v = UInt64(full, radix: 16) else { return nil }
            if full.count == 6 { r = CGFloat((v >> 16) & 255); g = CGFloat((v >> 8) & 255); b = CGFloat(v & 255) }
            else { r = CGFloat((v >> 24) & 255); g = CGFloat((v >> 16) & 255); b = CGFloat((v >> 8) & 255); a = CGFloat(v & 255) / 255 }
        } else if s.hasPrefix("rgb") || s.hasPrefix("hsl") {
            guard let o = s.firstIndex(of: "("), let c = s.lastIndex(of: ")"), o < c else { return nil }
            let parts = s[s.index(after: o)..<c].split(whereSeparator: { " ,/".contains($0) }).map(String.init)
            guard parts.count >= 3 else { return nil }
            func num(_ p: String, _ scale: CGFloat) -> CGFloat? {
                if p.hasSuffix("%") { return Double(p.dropLast()).map { CGFloat($0) / 100 * scale } }
                return Double(p.replacingOccurrences(of: "deg", with: "")).map { CGFloat($0) }
            }
            if s.hasPrefix("rgb") {
                guard let rr = num(parts[0], 255), let gg = num(parts[1], 255), let bb = num(parts[2], 255) else { return nil }
                r = rr; g = gg; b = bb
            } else {
                guard let hh = num(parts[0], 360), let ss = num(parts[1], 1), let ll = num(parts[2], 1) else { return nil }
                let h6 = (hh.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
                let sat = max(0, min(1, parts[1].hasSuffix("%") ? ss : ss / 100)), lig = max(0, min(1, parts[2].hasSuffix("%") ? ll : ll / 100))
                let cc = (1 - abs(2 * lig - 1)) * sat, x = cc * (1 - abs(h6.truncatingRemainder(dividingBy: 2) - 1)), mm = lig - cc / 2
                let (r1, g1, b1): (CGFloat, CGFloat, CGFloat)
                switch Int(h6) { case 0: (r1, g1, b1) = (cc, x, 0); case 1: (r1, g1, b1) = (x, cc, 0); case 2: (r1, g1, b1) = (0, cc, x); case 3: (r1, g1, b1) = (0, x, cc); case 4: (r1, g1, b1) = (x, 0, cc); default: (r1, g1, b1) = (cc, 0, x) }
                r = (r1 + mm) * 255; g = (g1 + mm) * 255; b = (b1 + mm) * 255
            }
            if parts.count >= 4, let aa = num(parts[3], 1) { a = parts[3].hasSuffix("%") ? aa : aa }
        } else if let n = named[s] { (r, g, b) = n }
        else { return nil }
        let col = CGColor(colorSpace: space, components: [max(0, min(255, r)) / 255, max(0, min(255, g)) / 255, max(0, min(255, b)) / 255, max(0, min(1, a))])
        if let col { if cache.count > 4000 { cache.removeAll() }; cache[s] = col }
        return col
    }
}

/// `font` strings the pieces set ("48px PLHand, cursive", "italic 600 24px Georgia") to a real font.
enum FontResolver {
    /// His hand's PostScript name once HouseKit has registered it (set from the main actor; read on the runtime queue).
    nonisolated(unsafe) static var handName: String?
    nonisolated(unsafe) private static var cache: [String: CTFont] = [:]
    nonisolated(unsafe) private static var families: Set<String>?

    static func hasFont(_ name: String) -> Bool {
        if name == "PLHand" { return handName != nil }
        return UIFont(name: name, size: 12) != nil || familyNames.contains(name.lowercased())
    }

    private static var familyNames: Set<String> {
        if let f = families { return f }
        let f = Set(UIFont.familyNames.map { $0.lowercased() })
        families = f
        return f
    }

    static func font(for spec: String) -> CTFont {
        if let f = cache[spec] { return f }
        var size: CGFloat = 10
        var rest = spec
        if let r = spec.range(of: #"(\d+(?:\.\d+)?)(px|pt)"#, options: .regularExpression) {
            size = CGFloat(Double(spec[r].dropLast(2)) ?? 10)
            rest = String(spec[r.upperBound...])
        }
        let before = spec.lowercased()
        let bold = before.contains("bold") || before.contains("700") || before.contains("800") || before.contains("900") || before.contains("600")
        let italic = before.contains("italic") || before.contains("oblique")
        let families = rest.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }.filter { !$0.isEmpty }
        var base: UIFont?
        for fam in families {
            if fam == "PLHand" { if let n = handName, let f = UIFont(name: n, size: size) { base = f; break }; continue }
            switch fam.lowercased() {
            case "serif": base = withDesign(.serif, size, bold)
            case "sans-serif", "system-ui", "-apple-system": base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            case "monospace": base = UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
            case "cursive": base = UIFont(name: "SnellRoundhand", size: size) ?? withDesign(.serif, size, bold)
            case "fantasy": base = UIFont(name: "Papyrus", size: size)
            default:
                if let f = UIFont(name: fam, size: size) { base = f }
                else if familyNames.contains(fam.lowercased()),
                        let name = UIFont.familyNames.first(where: { $0.lowercased() == fam.lowercased() }),
                        let face = UIFont.fontNames(forFamilyName: name).first, let f = UIFont(name: face, size: size) { base = f }
            }
            if base != nil { break }
        }
        var ui = base ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold && base != nil { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let d = ui.fontDescriptor.withSymbolicTraits(traits.union(ui.fontDescriptor.symbolicTraits)) { ui = UIFont(descriptor: d, size: size) }
        let ct = CTFontCreateWithName(ui.fontName as CFString, size, nil)
        if cache.count > 300 { cache.removeAll() }
        cache[spec] = ct
        return ct
    }

    private static func withDesign(_ design: UIFontDescriptor.SystemDesign, _ size: CGFloat, _ bold: Bool) -> UIFont {
        let sys = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if let d = sys.fontDescriptor.withDesign(design) { return UIFont(descriptor: d, size: size) }
        return sys
    }
}
