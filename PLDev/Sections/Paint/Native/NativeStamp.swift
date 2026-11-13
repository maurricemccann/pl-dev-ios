import CoreGraphics
import Foundation
import UIKit

/// The stamp half of the laptop's brush engine (`brush.js`: `sprite`, `drawStamp`, `stampWithTwin`, `drawFill`, `grainTile`, `applyGrain`,
/// `jitterColour` from `app.js`) on Core Graphics. A sprite is a 128 pixel picture of one dab, kept per shape, hardness, flow, light and colour.
/// Differences from the browser, stated: the soft edge of a square or diamond is a Core Graphics shadow, not a canvas blur, so its feather
/// is close and not identical; "moving" and "along" grain are not drawn yet (texturised grain is).
@MainActor enum NativeStamp {
    private static var sprites: [String: CGImage] = [:]
    private static var grains: [String: CGImage] = [:]
    private static var tips: [String: CGImage] = [:]
    private static let N = 128

    private static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }

    // MARK: colour

    private static func rgb255(_ hex: String) -> [Double] { Hex.rgb(hex).map { [$0.0 * 255, $0.1 * 255, $0.2 * 255] } ?? [0, 0, 0] }
    private static func mix(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { zip(a, b).map { ($0 + ($1 - $0) * t).rounded() } }
    private static func cg(_ c: [Double], _ a: Double) -> CGColor { CGColor(red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255, alpha: a) }
    private static func hueShift(_ c: [Double], _ deg: Double) -> [Double] {
        let r = c[0] / 255, g = c[1] / 255, b = c[2] / 255, mx = max(r, g, b), mn = min(r, g, b), d = mx - mn, l = (mx + mn) / 2
        var h = 0.0
        if d != 0 { h = mx == r ? ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4 }
        h = (h * 60 + deg + 360).truncatingRemainder(dividingBy: 360)
        let s = d != 0 ? d / (1 - abs(2 * l - 1)) : 0
        func k(_ n: Double) -> Double { let q = (n + h / 30).truncatingRemainder(dividingBy: 12); return l - s * min(l, 1 - l) * max(-1, min(q - 3, 9 - q, 1)) }
        return [k(0) * 255, k(8) * 255, k(4) * 255].map { $0.rounded() }
    }

    /// Colour dynamics: each dab a little different in hue, saturation and lightness, the same every time for the same place.
    static func jitterColour(_ hex: String, hue: Double, sat: Double, bri: Double, x: Double, y: Double) -> String {
        func rn(_ k: Double) -> Double { let v = sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453; return (v - floor(v)) * 2 - 1 }
        let c = rgb255(hex), r = c[0] / 255, g = c[1] / 255, b = c[2] / 255, mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var l = (mx + mn) / 2, hh = 0.0, s = d != 0 ? d / (1 - abs(2 * l - 1)) : 0
        if d != 0 { hh = mx == r ? ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4 }
        hh = (hh * 60 + hue * 60 * rn(1) + 360).truncatingRemainder(dividingBy: 360)
        s = max(0, min(1, s * (1 + sat * 0.6 * rn(2)))); l = max(0.05, min(0.95, l + bri * 0.25 * rn(3)))
        func q(_ n2: Double) -> Double { let k = (n2 + hh / 30).truncatingRemainder(dividingBy: 12); return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1)) }
        let v = [q(0), q(8), q(4)].map { max(0, min(255, ((($0 * 255) / 6).rounded()) * 6)) / 255 }
        return Hex.string(r: v[0], g: v[1], b: v[2])
    }

    // MARK: sprites

    private static func spriteContext() -> CGContext? {
        guard let c = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(N)); c.scaleBy(x: 1, y: -1)   // y-down, like the browser canvas the shapes were written for
        return c
    }

    private static func tipImage(_ url: String) -> CGImage? {
        if let t = tips[url] { return t }
        guard let img = NativeDoc.image(fromDataURL: url), let c = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.draw(img, in: CGRect(x: 0, y: 0, width: N, height: N))
        let out = c.makeImage(); if let out { tips[url] = out }; return out
    }

    static func sprite(_ B: Brush, color: String) -> CGImage? {
        let shape = B.shape, a = B.n("flow"), hard = B.n("hard"), light = B.t("light")
        let key = "\(shape)|\(String(format: "%.2f", hard))|\(String(format: "%.2f", a))|\(light)|\(color)" + (shape == "tip" ? "|\((B.tip ?? "").count)\((B.tip ?? "").suffix(16))" : "")
        if let s = sprites[key] { return s }
        guard let g = spriteContext() else { return nil }
        let n = CGFloat(N), col = rgb255(color), fill = cg(col, a)
        let space = CGColorSpaceCreateDeviceRGB()
        func radial() {
            let z = cg(col, 0), h = CGFloat(max(0.01, min(0.995, hard)))
            if let gr = CGGradient(colorsSpace: space, colors: [fill, fill, z] as CFArray, locations: [0, h, 1]) {
                g.drawRadialGradient(gr, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: n / 2, options: [])
            }
        }
        /// A shape with a soft edge: drawn off to the side with a shadow that lands on the sprite, blurred by (1 - hard).
        func soft(_ blur: Double, _ path: CGPath) {
            g.saveGState()
            if blur > 0.5 {
                g.setShadow(offset: CGSize(width: n * 2, height: 0), blur: CGFloat(blur), color: fill)
                g.translateBy(x: -n * 2, y: 0)
            }
            g.setFillColor(fill); g.addPath(path); g.fillPath()
            g.restoreGState()
        }
        switch shape {
        case "tip":
            if let url = B.tip, let tip = tipImage(url) {
                g.setFillColor(fill); g.fill(CGRect(x: 0, y: 0, width: n, height: n))
                g.setBlendMode(.destinationIn)
                g.saveGState(); g.translateBy(x: 0, y: n); g.scaleBy(x: 1, y: -1); g.draw(tip, in: CGRect(x: 0, y: 0, width: n, height: n)); g.restoreGState()
            } else {   // not decoded or missing: a round soft dab
                if let gr = CGGradient(colorsSpace: space, colors: [fill, cg(col, 0)] as CFArray, locations: [0, 1]) {
                    g.drawRadialGradient(gr, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: n / 2, options: [])
                }
            }
        case "tube":   // a glossy cylinder seen from the side: light top edge, the colour, a dark core, a hue-shifted rim
            let top = light != "bottom", white = [255.0, 255, 255]
            let ramp: [(Double, [Double])] = [(0, mix(col, white, 0.62)), (0.17, mix(col, white, 0.3)), (0.4, col), (0.66, mix(col, [4, 6, 24], 0.82)), (0.88, mix(hueShift(col, 70), [60, 20, 120], 0.35))]
            var stops: [(Double, CGColor)] = ramp.map { (top ? $0.0 : 1 - $0.0, cg($0.1, a)) }
            stops.append((top ? 1 : 0, cg(hueShift(col, 70), 0)))
            stops.sort { $0.0 < $1.0 }
            if let gr = CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { CGFloat($0.0) }) {
                g.saveGState(); g.clip(to: CGRect(x: n * 0.2, y: n * 0.04, width: n * 0.6, height: n * 0.92))
                g.drawLinearGradient(gr, start: CGPoint(x: 0, y: n * 0.04), end: CGPoint(x: 0, y: n * 0.96), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                g.restoreGState()
            }
        case "square":
            soft((1 - hard) * Double(N) * 0.1, CGPath(rect: CGRect(x: n * 0.14, y: n * 0.14, width: n * 0.72, height: n * 0.72), transform: nil))
        case "diamond":
            let p = CGMutablePath()
            p.move(to: CGPoint(x: n / 2, y: n * 0.06)); p.addLine(to: CGPoint(x: n * 0.94, y: n / 2)); p.addLine(to: CGPoint(x: n / 2, y: n * 0.94)); p.addLine(to: CGPoint(x: n * 0.06, y: n / 2)); p.closeSubpath()
            soft((1 - hard) * Double(N) * 0.08, p)
        case "bristle":
            var s = 12345.0
            func r() -> Double { s = (s * 16807).truncatingRemainder(dividingBy: 2147483647); return s / 2147483647 }
            g.setFillColor(fill)
            for _ in 0..<22 {
                let ang = r() * .pi * 2, d = r().squareRoot() * Double(N) * 0.4, rad = Double(N) * (0.05 + r() * 0.05)
                g.fillEllipse(in: CGRect(x: Double(N) / 2 + cos(ang) * d - rad, y: Double(N) / 2 + sin(ang) * d - rad, width: rad * 2, height: rad * 2))
            }
        default: radial()
        }
        if sprites.count > 700 { sprites.removeAll() }
        guard let img = g.makeImage() else { return nil }
        if shape != "tip" || (B.tip.map { tipImage($0) != nil } ?? false) { sprites[key] = img }
        return img
    }

    // MARK: stamping

    /// One dab on a context: rotated by the angle, squashed by the brush's roundness, at the pen's opacity.
    static func draw(_ ctx: CGContext, _ B: Brush, color: String, size: Double, _ d: Dab, skipGrain: Bool = true, offset: (Double, Double) = (0, 0), f: Double? = nil) {
        let r = B.radius(size: size, pressure: d.p, f: f ?? d.f)
        guard let sp = sprite(B, color: color) else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(clamp(d.am, 0, 1)))
        ctx.translateBy(x: d.x + offset.0, y: d.y + offset.1)
        ctx.rotate(by: CGFloat(d.ang)); ctx.scaleBy(x: 1, y: CGFloat(B.n("round") == 0 ? 1 : B.n("round")))
        ctx.scaleBy(x: 1, y: -1)   // sprites are upright pictures; this canvas is y-down
        ctx.draw(sp, in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    /// The companion band first, so the main band lies over it where they touch (`twinMode: over` puts it on top).
    static func drawWithTwin(_ ctx: CGContext, _ B: Brush, color: String, color2: String, size: Double, _ d: Dab) {
        let over = B.t("twinMode") == "over"
        if let tw = d.tw, !over { draw(ctx, B, color: color2, size: size, d, offset: (tw.dx, tw.dy), f: tw.f) }
        draw(ctx, B, color: color, size: size, d)
        if let tw = d.tw, over { draw(ctx, B, color: color2, size: size, d, offset: (tw.dx, tw.dy), f: tw.f) }
    }

    /// The filled middle of a band: a flat bar across the stroke, as wide as the distance between the lines' centres.
    static func drawFill(_ ctx: CGContext, _ B: Brush, color: String, size: Double, _ d: Dab) {
        let len = max(2, B.n("spacing") * size * 1.6)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(clamp(d.am, 0, 1)))
        ctx.translateBy(x: d.x, y: d.y); ctx.rotate(by: CGFloat(d.ang))
        ctx.setFillColor(Hex.color(color) ?? CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: -len / 2, y: -d.span / 2, width: len, height: d.span))
        ctx.restoreGState()
    }

    // MARK: grain

    /// A tile whose alpha is how much of the stamp the grain takes away. Seeded, so it is the same tile every time (the laptop's recipe).
    static func grainTile(_ kind: String, depth: Double) -> CGImage? {
        let key = kind + "|" + String(format: "%.2f", depth)
        if let t = grains[key] { return t }
        let T = 192
        var s = 4242.0
        func r() -> Double { s = (s * 16807).truncatingRemainder(dividingBy: 2147483647); return s / 2147483647 }
        let coarse = (0..<576).map { _ in r() }
        func val(_ x: Double, _ y: Double) -> Double {
            let gx = x / 8, gy = y / 8, x0 = Int(floor(gx)) % 24, y0 = Int(floor(gy)) % 24, fx = gx - floor(gx), fy = gy - floor(gy), x1 = (x0 + 1) % 24, y1 = (y0 + 1) % 24
            let a = coarse[y0 * 24 + x0], b = coarse[y0 * 24 + x1], c2 = coarse[y1 * 24 + x0], d = coarse[y1 * 24 + x1]
            return (a * (1 - fx) + b * fx) * (1 - fy) + (c2 * (1 - fx) + d * fx) * fy
        }
        let big = (0..<576).map { _ in r() }, mid = (0..<64).map { _ in r() }, mid2 = (0..<256).map { _ in r() }
        func lump(_ x0: Double, _ y0: Double, _ cell: Int, _ arr: [Double]) -> Double {
            let n = T / cell, x = ((x0.truncatingRemainder(dividingBy: Double(T))) + Double(T)).truncatingRemainder(dividingBy: Double(T)), y = ((y0.truncatingRemainder(dividingBy: Double(T))) + Double(T)).truncatingRemainder(dividingBy: Double(T))
            let gx = x / Double(cell), gy = y / Double(cell), xi = Int(floor(gx)) % n, yi = Int(floor(gy)) % n, fx = gx - floor(gx), fy = gy - floor(gy), x1 = (xi + 1) % n, y1 = (yi + 1) % n
            func sm(_ t: Double) -> Double { t * t * (3 - 2 * t) }
            let a = arr[yi * n + xi], b = arr[yi * n + x1], c2 = arr[y1 * n + xi], d = arr[y1 * n + x1], u = sm(fx), v = sm(fy)
            return (a * (1 - u) + b * u) * (1 - v) + (c2 * (1 - u) + d * u) * v
        }
        var alpha = [UInt8](repeating: 0, count: T * T)
        var relief = kind == "relief" ? [Double](repeating: 0, count: T * T) : []
        for y in 0..<T { for x in 0..<T {
            var h = 0.0
            let fx = Double(x), fy = Double(y)
            switch kind {
            case "noise": h = r()
            case "paper": h = clamp((val(fx, fy) * 0.6 + r() * 0.5 - 0.35) * 2.2, 0, 1)
            case "relief":
                let wv = (lump(fx, fy, 24, mid) - 0.5) * 36, wu = (lump(fy, fx, 24, mid) - 0.5) * 36
                relief[y * T + x] = lump(fx + wv, fy + wu, 24, mid) * 0.42 + lump(fx + wu, fy + wv, 12, mid2) * 0.34 + lump(fx, fy, 8, big) * 0.2 + r() * 0.1
                continue
            case "canvas": h = (sin(fx * 0.9) * sin(fy * 0.9) + 1) / 2 > 0.5 ? 0.9 : 0.15
            case "dots": let cx = Double(x % 12) - 6, cy = Double(y % 12) - 6; h = hypot(cx, cy) < 3.4 ? 0 : 1
            default: break
            }
            alpha[y * T + x] = UInt8((clamp(h * depth, 0, 1) * 255).rounded())
        } }
        if kind == "relief" {   // soften the lumps, then keep the ones above the line: irregular blobs, not squares
            for y in 0..<T { for x in 0..<T {
                var a = 0.0
                for dy in -1...1 { for dx in -1...1 { a += relief[((y + dy + T) % T) * T + ((x + dx + T) % T)] } }
                alpha[y * T + x] = UInt8((clamp((a / 9 - 0.43) * 3.8, 0, 1) * clamp(depth, 0, 1) * 255).rounded())
            } }
        }
        var px = [UInt8](repeating: 0, count: T * T * 4)
        for i in 0..<(T * T) { px[i * 4 + 3] = alpha[i] }   // black with this alpha: premultiplied, so the colour channels stay 0
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let img = CGImage(width: T, height: T, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: T * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        if grains.count > 40 { grains.removeAll() }
        grains[key] = img
        return img
    }

    /// Texturised grain: one pass over the whole stroke, fixed to the paper, so overlapping dabs cannot fill the tooth back in.
    static func applyGrain(_ ctx: CGContext, _ B: Brush, in rect: CGRect) {
        let kind = B.t("grain")
        guard kind != "none", !kind.isEmpty, B.t("grainMode") == "texturised", let tile = grainTile(kind, depth: B.n("grainDepth")) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setBlendMode(.destinationOut)
        let gs = CGFloat(B.n("grainScale") == 0 ? 1 : B.n("grainScale"))
        ctx.scaleBy(x: gs, y: gs)
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: 192, height: 192), byTiling: true)
        ctx.restoreGState()
    }
}
