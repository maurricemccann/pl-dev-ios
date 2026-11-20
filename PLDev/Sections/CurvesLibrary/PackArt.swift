import SwiftUI
import UIKit

// The Pack's 2D art, ported call for call from the test page (pl-curves-gallery public/pack/index.html, S348/S349): his curve tile
// in the tier's own finish, the modifiers, the art window and plate, the slab label, and the reveal (his heart unravels into
// veins grown on shortest paths over a jittered lattice, then the face opens from the centre). The page drew these with canvas
// calls chosen to exist in Core Graphics; here they are those Core Graphics calls. Same numbers, same order, same SETTINGS.

// MARK: settings (exactly the page's DEFAULTS; "Copy settings" hands back this JSON)

struct PackSettings: Codable, Equatable, Sendable {
    struct Pattern: Codable, Equatable, Sendable { var size = 1.1 }
    struct Sheen: Codable, Equatable, Sendable { var shiny = 0.10, matte = 0.78, goldMatte = 0.55, clearcoat = 0.6, light = 1.15, iridescence = 0.45, sway = 1.0 }
    struct Colour: Codable, Equatable, Sendable {
        var obsidian = "#070708", champagne = "#E3C78F", heart = "#F2D9A0", silver = "#BEC2C8", ground = "#10152b", curves = "#E3C78F"
        var prismRainbow = 0.20, prismCurveRainbow = 0.48, prismSaturation = 0.55, prismBands = 2.4
    }
    struct Background: Codable, Equatable, Sendable { var rest = 0.22, during = 0.06, slab = 0.18, speed = 1.0 }
    struct Timing: Codable, Equatable, Sendable { var tearAuto = 0.62, emerge = 0.15, pull = 0.16, `catch` = 0.06, clear = 0.58, poise = 0.25, reveal = 1.0, clean = 0.55, slab = 0.95, deal = 0.7 }
    struct Reveal: Codable, Equatable, Sendable {
        var curves = 15.0, rim = 3.0, channel = 24.0, heartUnravel = 1.0, cell = 26.0, jitter = 0.35, wander = 2.0, smooth = 4.0
        var swell = 0.2, hand = 0.8, grow = 0.36, stagger = 0.1, openAt = 0.14
    }
    struct Tear: Codable, Equatable, Sendable { var coil = 2.2, lip = 1.5 }   // millimetres
    struct Modifier: Codable, Equatable, Sendable { var chance = 25.0, blend = 0.75, scale = 1.0, soft = 0.18 }
    struct Odds: Codable, Equatable, Sendable { var obsidian = 72.0, champagne = 20.0, prism = 8.0, pity = 15.0, champagneAfter = 5.0 }
    var pattern = Pattern(), sheen = Sheen(), colour = Colour(), background = Background(), timing = Timing()
    var reveal = Reveal(), tear = Tear(), modifier = Modifier(), odds = Odds()

    static let storeKey = "pldev.pack.settings"

    /// The page's merge: only keys the defaults have, only values of the same kind; anything else is ignored, never an error.
    static func merged(_ over: [String: Any]) throws -> PackSettings {
        guard var base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PackSettings())) as? [String: Any] else { return PackSettings() }
        merge(&base, over)
        return try JSONDecoder().decode(PackSettings.self, from: JSONSerialization.data(withJSONObject: base))
    }
    private static func merge(_ base: inout [String: Any], _ over: [String: Any]) {
        for (k, v) in over {
            guard let b = base[k] else { continue }
            if var bd = b as? [String: Any] { if let od = v as? [String: Any] { merge(&bd, od); base[k] = bd } }
            else if b is String, let s = v as? String { base[k] = s }
            else if let n = v as? NSNumber, !(b is String), CFGetTypeID(n) != CFBooleanGetTypeID() { base[k] = n }
        }
    }
    static func load() -> PackSettings {
        guard let s = UserDefaults.standard.string(forKey: storeKey), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let m = try? merged(o) else { return PackSettings() }
        return m
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(String(decoding: d, as: UTF8.self), forKey: Self.storeKey) } }
    var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

// MARK: tiers and the house palettes

enum PackTier {
    /// His rulings 11-16: OBSIDIAN = PLG, CHAMPAGNE = any video card (it plays when opened), PRISM = archive work. File keys: common / legendary / exclusive.
    static func name(_ t: String) -> String { t == "legendary" ? "CHAMPAGNE" : t == "exclusive" ? "PRISM" : "OBSIDIAN" }
    static func pips(_ t: String) -> Int { t == "legendary" ? 2 : t == "exclusive" ? 3 : 1 }
    static let order = ["exclusive", "legendary", "common"]
    /// Design Kit palettes.json: ground, key.
    static let house: [(name: String, ground: String, key: String)] = [
        ("obsidian-gold", "#0e0c08", "#c9a84c"), ("void-ember", "#0a0807", "#d4550a"), ("totem-blue-gold", "#0f1d3a", "#c9a84c"),
        ("deep-indigo", "#080810", "#6a7fd4"), ("night-silver", "#0c0c0e", "#b0b8c8"), ("bone-oxblood", "#f0ece4", "#7c1f1f"),
        ("cream-indigo", "#f5f1e6", "#33307e"), ("linen-forest", "#edeae0", "#1a3d1e"), ("ivory-copper", "#f2ede2", "#8b4a1a"),
        ("warm-smoke", "#e8e2d6", "#7c1f1f"), ("oxblood-ground", "#5e1414", "#c9a84c"), ("forest-ground", "#14301a", "#c9a84c"),
        ("pearl-gold", "#f4f1ea", "#b88a2e")]
    static let modifiers = ["BRUSHED", "ETCHED", "FROST", "MOLTEN"]
}

// MARK: small helpers (the page's ease, lerp, rng, hex, mix, hsl, value noise)

enum PackMath {
    static func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
    static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }
    static func rgb(_ h: String) -> (Double, Double, Double) {
        let s = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard s.count >= 6, let v = UInt32(s.prefix(6), radix: 16) else { return (0, 0, 0) }
        return (Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255))
    }
    static func ui(_ h: String) -> UIColor { let (r, g, b) = rgb(h); return UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
    static func mix(_ a: String, _ b: String, _ u: Double) -> UIColor {
        let x = rgb(a), y = rgb(b)
        return UIColor(red: (x.0 + (y.0 - x.0) * u).rounded() / 255, green: (x.1 + (y.1 - x.1) * u).rounded() / 255, blue: (x.2 + (y.2 - x.2) * u).rounded() / 255, alpha: 1)
    }
    static func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = { (v: CGFloat) in Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", k(r), k(g), k(b))
    }
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        func f(_ n: Double) -> Double { let k = (n + h * 12).truncatingRemainder(dividingBy: 12), a = s * min(l, 1 - l); return (255 * (l - a * max(-1, min(k - 3, 9 - k, 1)))).rounded() }
        return (f(0), f(8), f(4))
    }
    /// The material colour: red = foil that shimmers, green = roughness, blue = metallic.
    static func mr(_ foil: Double, _ rough: Double, _ metal: Double) -> UIColor { UIColor(red: foil, green: (rough * 255).rounded() / 255, blue: metal, alpha: 1) }
}

/// The page's seeded generator (mulberry32), bit for bit.
struct PackRNG {
    private var a: UInt32
    init(_ seed: Int) { a = UInt32(truncatingIfNeeded: seed) }
    mutating func callAsFunction() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// Smooth value noise on an integer lattice, seeded (the page's noise2), and its fbm.
struct PackNoise {
    let seed: UInt32
    init(_ seed: Int) { self.seed = UInt32(truncatingIfNeeded: seed) }
    private func h(_ x: Int, _ y: Int) -> Double {
        var n = UInt32(truncatingIfNeeded: x) &* 374_761_393 &+ UInt32(truncatingIfNeeded: y) &* 668_265_263 &+ seed &* 2_147_483_647
        n = (n ^ (n >> 13)) &* 1_274_126_177
        return Double(n ^ (n >> 16)) / 4_294_967_296
    }
    func callAsFunction(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y)), fx = x - Double(xi), fy = y - Double(yi), u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }
    func fbm(_ x: Double, _ y: Double, _ oct: Int = 4) -> Double {
        var s = 0.0, a = 0.5, f = 1.0, t = 0.0
        for _ in 0..<oct { s += a * self(x * f, y * f); t += a; a *= 0.5; f *= 2.03 }
        return s / t
    }
}

// MARK: the curve hero (pl-headless GoldCurves.tsx): curves that each clear a channel, butt ends

struct PackCurve {
    var sx, sy, ex, ey, ph, sp, w, op: Double
    var c1: (Double, Double), c2: (Double, Double)
    var a: [Double], f: [Double]

    static func make(_ rand: inout PackRNG, _ W: Double, _ H: Double, _ scale: Double) -> [PackCurve] {
        func R(_ a: Double, _ b: Double) -> Double { a + rand() * (b - a) }
        let m = 140 * scale
        var out: [PackCurve] = []
        for i in 0..<15 {
            let r = rand(), d = r < 0.45 ? 0 : r < 0.7 ? 1 : r < 0.85 ? 2 : 3
            let e: [Double]
            switch d {
            case 0: e = [R(-m * 2, -m), R(-H * 0.2, H * 1.2), R(W + m, W + m * 2), R(-H * 0.2, H * 1.2)]
            case 1: e = [R(-W * 0.2, W * 1.2), R(-m * 2, -m), R(-W * 0.2, W * 1.2), R(H + m, H + m * 2)]
            case 2: e = [R(-m * 2, -m), R(-H * 0.1, H * 0.6), R(-W * 0.1, W * 1.1), R(H + m, H + m * 2)]
            default: e = [R(-W * 0.1, W * 1.1), R(-m * 2, -m), R(W + m, W + m * 2), R(-H * 0.1, H * 1.1)]
            }
            let ph = R(0, 6.28), sp = R(0.15, 0.5)
            let w = (i < 5 ? R(5, 12) : i < 10 ? R(2, 4.5) : R(0.4, 1.5)) * 1.6 * scale / 0.45
            let op = (i < 5 ? R(0.28, 0.55) : i < 10 ? R(0.13, 0.28) : R(0.05, 0.15)) * 1.8
            let c1 = (R(W * 0.05, W * 0.95), R(H * 0.05, H * 0.95)), c2 = (R(W * 0.05, W * 0.95), R(H * 0.05, H * 0.95))
            let a = (0..<4).map { _ in R(80, 320) * scale }, f = (0..<4).map { _ in R(0.3, 1.9) }
            out.append(PackCurve(sx: e[0], sy: e[1], ex: e[2], ey: e[3], ph: ph, sp: sp, w: w, op: op, c1: c1, c2: c2, a: a, f: f))
        }
        return out
    }

    /// n points along the curve at time t, as x, y pairs.
    func points(_ t: Double, _ n: Int) -> [Double] {
        let s = sp * t * 0.048, p = ph
        let c1x = c1.0 + sin(s * f[0] + p) * a[0], c1y = c1.1 + cos(s * f[1] + p * 1.4) * a[1]
        let c2x = c2.0 + sin(s * f[2] + p * 0.6) * a[2], c2y = c2.1 + cos(s * f[3] + p * 1.8) * a[3]
        var pts = [Double](repeating: 0, count: n * 2)
        for k in 0..<n {
            let u = Double(k) / Double(n - 1), v = 1 - u, a = v * v * v, b = 3 * v * v * u, d = 3 * v * u * u, e = u * u * u
            pts[k * 2] = a * sx + b * c1x + d * c2x + e * ex; pts[k * 2 + 1] = a * sy + b * c1y + d * c2y + e * ey
        }
        return pts
    }
}

// MARK: a canvas: a bitmap with the page's top-left coordinates, so every drawing call reads as it did on the web

@MainActor final class PackCanvas {
    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let ctx: CGContext
    let w: CGFloat, h: CGFloat
    var rect: CGRect { CGRect(x: 0, y: 0, width: w, height: h) }

    init(_ w: Int, _ h: Int, scale: Int = 1) {
        self.w = CGFloat(w); self.h = CGFloat(h)
        guard let c = CGContext(data: nil, width: w * scale, height: h * scale, bitsPerComponent: 8, bytesPerRow: 0, space: Self.space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("a \(w)x\(h) bitmap could not be made") }
        ctx = c
        ctx.translateBy(x: 0, y: CGFloat(h * scale)); ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        ctx.interpolationQuality = .high
    }
    var image: CGImage? { ctx.makeImage() }
    func reset() { ctx.setBlendMode(.normal); ctx.setAlpha(1) }
    func clear() { ctx.clear(rect) }
    func fill(_ c: UIColor, _ r: CGRect? = nil) { ctx.setFillColor(c.cgColor); ctx.fill(r ?? rect) }
    /// An image drawn upright in r (the bitmap's own space runs bottom-up).
    func draw(_ img: CGImage?, _ r: CGRect) {
        guard let img else { return }
        ctx.saveGState(); ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size)); ctx.restoreGState()
    }
    func draw(_ c: PackCanvas) { draw(c.image, rect) }
    func stroke(_ c: UIColor, _ width: CGFloat, _ r: CGRect) { ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(width); ctx.stroke(r) }
    func text(_ s: String, _ size: CGFloat, _ c: UIColor, _ x: CGFloat, _ y: CGFloat, right: Bool = false) {
        let f = UIFont(name: PLFace.label, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
        UIGraphicsPushContext(ctx); a.draw(at: CGPoint(x: right ? x - a.size().width : x, y: y)); UIGraphicsPopContext()
    }
    /// The page's coverInto: the image cropped to fill r, never stretched.
    func cover(_ img: CGImage, _ r: CGRect) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        guard iw > 0, ih > 0 else { return }
        let s = max(r.width / iw, r.height / ih), sw = r.width / s, sh = r.height / s
        draw(img.cropping(to: CGRect(x: (iw - sw) / 2, y: (ih - sh) / 2, width: sw, height: sh).integral), r)
    }
    /// The page's tinted(): the mask's alpha, filled with a colour (or a gradient), at w x h.
    static func tinted(_ mask: CGImage?, _ w: CGFloat, _ h: CGFloat, fill: (CGContext, CGRect) -> Void) -> CGImage? {
        let c = PackCanvas(Int(w.rounded(.up)), Int(h.rounded(.up)))
        c.draw(mask, CGRect(x: 0, y: 0, width: w, height: h))
        c.ctx.setBlendMode(.sourceIn); fill(c.ctx, CGRect(x: 0, y: 0, width: w, height: h))
        return c.image
    }
    static func tinted(_ mask: CGImage?, _ col: UIColor, _ w: CGFloat = PackArt.RW, _ h: CGFloat = PackArt.RH) -> CGImage? {
        tinted(mask, w, h) { ctx, r in ctx.setFillColor(col.cgColor); ctx.fill(r) }
    }
}

// MARK: the art engine (front, back, label, reveal)

struct PackVein { var x, y, nx, ny, p: [Double]; var n: Int; var kH: Int; var d: Double }

struct PackReveal {
    var curves: [PackCurve]
    var anchors: [(Double, Double)]
    var veins: [PackVein?]
    var heartFill: UIColor, ink: UIColor, rim: UIColor
    var blob: [(Double, Double)]
    var u = 0.0, still = false
}

@MainActor final class PackArt {
    static let RW: CGFloat = 630, RH: CGFloat = 880
    static let window = CGRect(x: 28, y: 28, width: 574, height: 738)
    static let HD = 2

    var set = PackSettings()
    var mod: (name: String, seed: Int)?
    private let tile: CGImage, heart: CGImage, money: CGImage

    let front = PackCanvas(630, 880, scale: HD), frontMR = PackCanvas(630, 880, scale: HD)
    let back = PackCanvas(630, 880), backMR = PackCanvas(630, 880)
    let label = PackCanvas(720, 180, scale: HD)
    let reveal = PackCanvas(630, 880), rim = PackCanvas(315, 440)
    private let layer = PackCanvas(630, 880), heartTint = PackCanvas(630, 880)
    private(set) var rev: PackReveal?
    private var heartOn: [(Double, Double)]?
    private var modCache: (key: String, img: CGImage?) = ("", nil)

    init(tile: CGImage, heart: CGImage, money: CGImage) { self.tile = tile; self.heart = heart; self.money = money }

    private var RW: CGFloat { Self.RW }
    private var RH: CGFloat { Self.RH }

    // ---------- the tier finish ----------

    private func tileMask() -> CGImage? {
        let s = max(24, (set.pattern.size * Double(RW)).rounded())
        let c = PackCanvas(Int(RW), Int(RH))
        var y = 0.0
        while y < Double(RH) { var x = 0.0; while x < Double(RW) { c.draw(tile, CGRect(x: x, y: y, width: s, height: s)); x += s }; y += s }
        return c.image
    }

    /// Fades a mask out in an ellipse around the heart mark: the back's heart sits in clear space.
    private func heartClear(_ img: CGImage?) -> CGImage? {
        let c = PackCanvas(Int(RW), Int(RH)); c.draw(img, c.rect)
        let g = CGGradient(colorsSpace: PackCanvas.space, colors: [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])
        c.ctx.saveGState(); c.ctx.setBlendMode(.destinationOut)
        c.ctx.translateBy(x: RW / 2, y: RH * 0.5); c.ctx.scaleBy(x: RW * 0.56, y: RH * 0.30)
        c.ctx.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: 6.2832, clockwise: false); c.ctx.clip()
        if let g { c.ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0.55, endCenter: .zero, endRadius: 1, options: [.drawsBeforeStartLocation]) }
        c.ctx.restoreGState()
        return c.image
    }

    /// A diagonal sweep of hues, pulled toward the gold.
    private func holo(_ phase: Double, _ amount: Double) -> (CGContext, CGRect) -> Void {
        let C = set.colour, n = 14, k = PackMath.rgb(C.champagne)
        let cols = (0...n).map { i -> CGColor in
            let (r, g, b) = PackMath.hsl((phase + Double(i) / Double(n) * C.prismBands).truncatingRemainder(dividingBy: 1), C.prismSaturation, 0.62)
            let m = { (kv: Double, v: Double) in (kv + (v - kv) * amount).rounded() / 255 }
            return UIColor(red: m(k.0, r), green: m(k.1, g), blue: m(k.2, b), alpha: 1).cgColor
        }
        let locs = (0...n).map { CGFloat($0) / CGFloat(n) }
        let rw = RW, rh = RH
        return { ctx, r in
            guard let g = CGGradient(colorsSpace: PackCanvas.space, colors: cols as CFArray, locations: locs) else { return }
            ctx.saveGState(); ctx.clip(to: r)
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: rw * 0.9, y: rh * 0.6), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    // ---------- MODIFIERS (S349): a second material blended into the finish through a procedural mask ----------

    private func modColour(_ name: String, _ t: String) -> UIColor {
        let C = set.colour
        switch name {
        case "BRUSHED": return t == "common" ? PackMath.mix(C.silver, C.obsidian, 0.55) : t == "legendary" ? PackMath.mix(C.champagne, "#ffffff", 0.3) : PackMath.ui("#F2E6C8")
        case "ETCHED": return t == "common" ? PackMath.mix(C.silver, C.obsidian, 0.78) : PackMath.mix(t == "legendary" ? C.champagne : "#F2D48A", "#000000", 0.16)
        case "FROST": return t == "common" ? PackMath.ui("#2c3037") : t == "legendary" ? PackMath.mix(C.champagne, "#ffffff", 0.18) : PackMath.ui("#E4E4EC")
        default: return PackMath.ui("#F6E39A")
        }
    }
    private func modMR(_ name: String) -> UIColor {
        switch name {
        case "BRUSHED": return PackMath.mr(0, 0.26, 1)
        case "ETCHED": return PackMath.mr(0, 0.93, 0)
        case "FROST": return UIColor(red: 0, green: (0.86 * 255).rounded() / 255, blue: (0.15 * 255).rounded() / 255, alpha: 1)
        default: return PackMath.mr(1, 0.15, 1)
        }
    }

    /// Alpha = where the modifier's material shows (value noise per pixel, at half size, then smoothed up).
    private func modMask(_ name: String, _ seed: Int) -> CGImage? {
        let M = set.modifier, key = "\(name)|\(seed)|\(M.scale)|\(M.soft)"
        if modCache.key == key { return modCache.img }
        let w = Int(RW) >> 1, h = Int(RH) >> 1, n = PackNoise(seed), g = PackNoise(seed + 7)
        let k = 5 / (Double(w) * M.scale), lo = 0.5 - M.soft, hi = 0.5 + M.soft
        func step(_ v: Double) -> Double { let t = PackMath.clamp((v - lo) / (hi - lo), 0, 1); return t * t * (3 - 2 * t) }
        guard let sc = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: PackCanvas.space,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let px = sc.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for y in 0..<h {
            for x in 0..<w {
                let u = Double(x) * k, v = Double(y) * k
                let a: Double
                switch name {
                case "BRUSHED": a = PackMath.clamp(0.15 + (n.fbm(u * 0.08, v * 38, 3) - 0.5) * 2.4, 0, 1) * 0.75
                case "ETCHED":
                    let e = n.fbm(2.2 * u + 0.6 * g.fbm(u, v, 2), 2.2 * v, 4), t = PackMath.clamp((e - 0.5) / (0.02 + M.soft * 0.15) + 0.5, 0, 1)
                    a = t * t * (3 - 2 * t)
                case "FROST": a = step(n.fbm(u * 0.7, v * 0.7, 3) + 0.18) * (0.55 + 0.45 * n(Double(x) * 1.7, Double(y) * 1.7))
                default:
                    let q = n.fbm(u + 1.5 * g.fbm(u, v, 3), v + 1.5 * g.fbm(u + 5.2, v + 1.3, 3), 4)
                    let ridge = 1 - abs(sin(q * 22)), t = PackMath.clamp((ridge - (0.8 - M.soft * 0.4)) / (0.1 + M.soft * 0.2), 0, 1)
                    a = t * t * (3 - 2 * t)
                }
                let b = UInt8((a * 255).rounded()), i = (y * w + x) * 4
                px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = b
            }
        }
        let c = PackCanvas(Int(RW), Int(RH)); c.draw(sc.makeImage(), c.rect)
        modCache = (key, c.image)
        return modCache.img
    }

    func rollModifier(_ r: inout PackRNG) -> String? {
        r() * 100 < set.modifier.chance ? PackTier.modifiers[min(3, Int(r() * 4))] : nil
    }

    private func finish(_ tier: String, back isBack: Bool) {
        let col = isBack ? back : front, mr = isBack ? backMR : frontMR, S = set.sheen, C = set.colour
        var mask = tileMask()
        if isBack { mask = heartClear(mask) }
        col.reset(); mr.reset()
        switch tier {
        case "common":
            col.fill(PackMath.ui(C.obsidian))
            mr.fill(PackMath.mr(0, S.matte, 0)); mr.draw(PackCanvas.tinted(mask, PackMath.mr(0, S.shiny, 0)), mr.rect)
        case "legendary":
            col.fill(PackMath.mix(C.champagne, "#000000", 0.10)); col.draw(PackCanvas.tinted(mask, PackMath.ui(C.champagne)), col.rect)
            mr.fill(PackMath.mr(0, S.goldMatte, 1)); mr.draw(PackCanvas.tinted(mask, PackMath.mr(0, S.shiny, 1)), mr.rect)
        default:
            holo(0, C.prismRainbow)(col.ctx, col.rect); col.draw(PackCanvas.tinted(mask, RW, RH, fill: holo(0.45, C.prismCurveRainbow)), col.rect)
            mr.fill(PackMath.mr(1, 0.34, 1)); mr.draw(PackCanvas.tinted(mask, PackMath.mr(1, S.shiny, 1)), mr.rect)
        }
        guard let mod else { return }
        let m0 = modMask(mod.name, mod.seed), m = isBack ? heartClear(PackCanvas.tinted(m0, .black)) : m0   // on the back the modifier leaves the heart its clear space too
        for c in [col, mr] {
            c.ctx.saveGState()
            if !isBack {   // the art plate keeps its own finish
                let W = Self.window
                c.ctx.addRect(c.rect); c.ctx.addRect(CGRect(x: W.minX - 12, y: RH - 114, width: W.width + 24, height: 100)); c.ctx.clip(using: .evenOdd)
            }
            c.ctx.setAlpha(set.modifier.blend)
        }
        col.draw(PackCanvas.tinted(m, modColour(mod.name, tier)), col.rect)
        mr.draw(PackCanvas.tinted(m, modMR(mod.name)), mr.rect)
        col.ctx.restoreGState(); mr.ctx.restoreGState()
    }

    func composeFront(tier: String, piece: String, art: CGImage?) {
        finish(tier, back: false)
        let C = set.colour, W = Self.window, plateY = RH - 114
        let inkC = tier == "common" ? PackMath.ui(C.silver) : tier == "legendary" ? PackMath.ui(C.obsidian) : PackMath.ui("#E6E6EB")
        let inkM = tier == "common" ? PackMath.mr(0, 0.22, 1) : tier == "legendary" ? PackMath.mr(0, 0.5, 0) : PackMath.mr(1, 0.2, 1)
        if tier == "exclusive" {   // the obsidian plate
            front.fill(PackMath.ui(C.obsidian), CGRect(x: W.minX, y: plateY + 6, width: W.width, height: 114 - 34))
            frontMR.fill(PackMath.mr(0, 0.55, 0), CGRect(x: W.minX, y: plateY + 6, width: W.width, height: 114 - 34))
        }
        let key = W.insetBy(dx: -8, dy: -8)
        front.stroke(inkC, 3, key); frontMR.stroke(inkM, 3, key)   // the keyline
        if let art { front.cover(art, W) }
        frontMR.fill(PackMath.mr(0, 0.6, 0), W)   // the art: printed, not foil
        if tier != "common" { front.stroke(PackMath.ui(C.obsidian), 3, W.insetBy(dx: -1.5, dy: -1.5)); frontMR.stroke(PackMath.mr(0, 0.5, 0), 3, W.insetBy(dx: -1.5, dy: -1.5)) }
        for (c, ink) in [(front, inkC), (frontMR, inkM)] {
            c.text("PSYCHED LUXURIES", 25, ink, W.minX + 4, plateY + 20)
            c.text(piece, 19, ink, W.minX + 4, plateY + 52)
            c.text(PackTier.name(tier), 25, ink, W.maxX - 4, plateY + 20, right: true)
        }
        let ph: CGFloat = 38, pw = ph * CGFloat(money.width) / CGFloat(max(1, money.height))
        var px = W.maxX - 4
        for _ in 0..<PackTier.pips(tier) {
            px -= pw
            front.draw(PackCanvas.tinted(money, inkC, pw, ph), CGRect(x: px, y: plateY + 50, width: pw, height: ph))
            frontMR.draw(PackCanvas.tinted(money, inkM, pw, ph), CGRect(x: px, y: plateY + 50, width: pw, height: ph))
            px -= 7
        }
    }

    func composeBack(tier: String) { finish(tier, back: true) }

    func composeLabel(tier: String, piece: String) {
        let g = PackMath.ui(set.colour.champagne), c = label
        c.reset(); c.fill(PackMath.ui("#060607"))
        c.stroke(g, 2, CGRect(x: 7, y: 7, width: 706, height: 166))
        c.text("PSYCHED LUXURIES", 32, g, 30, 26); c.text(piece, 22, g, 30, 75)
        let d = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.text(String(format: "%02d %02d %d", d.month ?? 0, d.day ?? 0, d.year ?? 0), 22, g, 30, 111)
        c.text(PackTier.name(tier), 32, g, 690, 26, right: true)
        if let mod { c.text(mod.name, 22, g, 690, 146, right: true) }
        let ph: CGFloat = 55, pw = ph * CGFloat(money.width) / CGFloat(max(1, money.height))
        var px: CGFloat = 690
        for _ in 0..<PackTier.pips(tier) { px -= pw; c.draw(PackCanvas.tinted(money, g, pw, ph), CGRect(x: px, y: 85, width: pw, height: ph)); px -= 10 }
        c.ctx.setAlpha(0.55)   // the heart seal, a quiet stamp
        c.draw(PackCanvas.tinted(heart, PackMath.mix(set.colour.champagne, "#000000", 0.45), 150, 210), CGRect(x: 300, y: -18, width: 150, height: 210))
        c.ctx.setAlpha(1)
    }

    // ---------- the veins (his ask 11-17, "How to Grow Tendrils Over Any Object"): its node tree in 2D ----------

    private static let veinMargin = 72.0, veinNoise = 240.0, offCard = 3.0, repel = 3.0, ds = 8.0

    @MainActor private final class Lattice {
        let NC, NR, N: Int
        var X, Y: [Double]
        var adj, eid: [Int]
        var Wt: [Double]
        let cell, rh, m: Double
        var blk: [Bool]
        lazy var dist = [Double](repeating: 0, count: N)
        lazy var prev = [Int](repeating: -1, count: N)
        lazy var pe = [Int](repeating: -1, count: N)
        lazy var done = [Bool](repeating: false, count: N)
        lazy var hk = [Double](repeating: 0, count: N * 6 + 1)
        lazy var hv = [Int](repeating: 0, count: N * 6 + 1)

        init(seed: Int, R: PackSettings.Reveal, RW: Double, RH: Double) {
            let cell = PackMath.clamp(R.cell, 18, 48), J = PackMath.clamp(R.jitter, 0, 0.45) * cell, wander = PackMath.clamp(R.wander, 0, 8)
            let m = PackArt.veinMargin + cell, rh = cell * 0.866
            NC = Int(ceil((RW + 2 * m) / cell)) + 1; NR = Int(ceil((RH + 2 * m) / rh)) + 1; N = NC * NR
            self.cell = cell; self.rh = rh; self.m = m
            var r = PackRNG(seed + 1); let nz = PackNoise(seed + 3)
            X = [Double](repeating: 0, count: N); Y = X
            adj = [Int](repeating: -1, count: N * 6); eid = adj
            Wt = [Double](repeating: .infinity, count: N * 3)
            blk = [Bool](repeating: false, count: N)
            for i in 0..<N {
                let row = i / NC, col = i - row * NC
                X[i] = -m + (Double(col) + Double(row & 1) * 0.5) * cell + (r() * 2 - 1) * J
                Y[i] = -m + Double(row) * rh + (r() * 2 - 1) * J * 0.866   // y jitter scaled to the row height so rows never swap
            }
            func link(_ p: Int, _ q: Int, _ e: Int) { var s = p * 6; while adj[s] >= 0 { s += 1 }; adj[s] = q; eid[s] = e }
            for i in 0..<N {
                let row = i / NC, col = i - row * NC, odd = row & 1, down = row + 1 < NR
                let nb = [col + 1 < NC ? i + 1 : -1, down && col - 1 + odd >= 0 ? i + NC - 1 + odd : -1, down && col + odd < NC ? i + NC + odd : -1]   // right, down-left, down-right
                for d in 0..<3 {
                    let j = nb[d]; if j < 0 { continue }
                    let dx = X[j] - X[i], dy = Y[j] - Y[i], mx = (X[i] + X[j]) / 2, my = (Y[i] + Y[j]) / 2
                    let off = mx < 0 || mx > RW || my < 0 || my > RH, e = i * 3 + d
                    Wt[e] = (dx * dx + dy * dy).squareRoot() * (1 + wander * nz.fbm(mx / PackArt.veinNoise, my / PackArt.veinNoise, 3)) * (off ? PackArt.offCard : 1)
                    link(i, j, e); link(j, i, e)
                }
            }
        }

        func nodeAt(_ x: Double, _ y: Double) -> Int {
            let row = Int(PackMath.clamp(((y + m) / rh).rounded(), 0, Double(NR - 1)))
            return row * NC + Int(PackMath.clamp(((x + m) / cell - Double(row & 1) * 0.5).rounded(), 0, Double(NC - 1)))
        }
        /// A curve end moved onto the lattice's outer ring on the side it leaves by most, squeezed along that edge.
        func edgeNode(_ x: Double, _ y: Double, _ RW: Double, _ RH: Double) -> Int {
            func sq(_ v: Double, _ S: Double) -> Double { S * (0.05 + 0.9 * PackMath.clamp((v + 0.2 * S) / (1.4 * S), 0, 1)) }
            let o = [-x, x - RW, -y, y - RH], side = o.firstIndex(of: o.max() ?? 0) ?? 0
            let cx = side < 2 ? x : sq(x, RW), cy = side < 2 ? sq(y, RH) : y
            var row = Int(PackMath.clamp(((cy + m) / rh).rounded(), 0, Double(NR - 1)))
            var col = Int(PackMath.clamp(((cx + m) / cell - Double(row & 1) * 0.5).rounded(), 0, Double(NC - 1)))
            if side == 0 { col = 0 } else if side == 1 { col = NC - 1 } else if side == 2 { row = 0 } else { row = NR - 1 }
            return row * NC + col
        }
        /// Dijkstra from src until t settles, skipping blocked nodes; nil when t cannot be reached.
        func route(_ src: Int, _ t: Int, blocked: Bool) -> (nodes: [Int], edges: [Int])? {
            for i in 0..<N { dist[i] = .infinity; prev[i] = -1; pe[i] = -1; done[i] = false }
            var hn = 0
            func push(_ k: Double, _ v: Int) {
                var i = hn; hn += 1
                while i > 0 { let p = (i - 1) >> 1; if hk[p] <= k { break }; hk[i] = hk[p]; hv[i] = hv[p]; i = p }
                hk[i] = k; hv[i] = v
            }
            func pop() -> Int {
                let v = hv[0]; hn -= 1; let k = hk[hn], x = hv[hn]; var i = 0
                while true {
                    var c = 2 * i + 1; if c >= hn { break }
                    if c + 1 < hn && hk[c + 1] < hk[c] { c += 1 }
                    if hk[c] >= k { break }
                    hk[i] = hk[c]; hv[i] = hv[c]; i = c
                }
                hk[i] = k; hv[i] = x
                return v
            }
            dist[src] = 0; push(0, src)
            while hn > 0 {
                let u = pop(); if done[u] { continue }; done[u] = true; if u == t { break }
                for s in (u * 6)..<(u * 6 + 6) {
                    let v = adj[s]; if v < 0 || done[v] || (blocked && blk[v]) { continue }
                    let d = dist[u] + Wt[eid[s]]
                    if d < dist[v] { dist[v] = d; prev[v] = u; pe[v] = eid[s]; push(d, v) }
                }
            }
            guard done[t] else { return nil }
            var nodes = [t], edges: [Int] = [], v = t
            while v != src { edges.append(pe[v]); nodes.append(prev[v]); v = prev[v] }
            return (nodes.reversed(), edges)
        }
    }

    /// His hero cubic bent through (ax, ay): both control points move by one vector, so its off-card ends never move.
    private func heroThrough(_ c: PackCurve, _ ax: Double, _ ay: Double) -> (P: [Double], S: [Double], k0: Int) {
        var P = c.points(40, 64), k0 = 6, best = Double.infinity
        for k in 6...57 { let e = pow(P[k * 2] - ax, 2) + pow(P[k * 2 + 1] - ay, 2); if e < best { best = e; k0 = k } }
        let u = Double(k0) / 63, w = 3 * u * (1 - u), dx = (ax - P[k0 * 2]) / w, dy = (ay - P[k0 * 2 + 1]) / w
        for k in 1..<63 { let v = Double(k) / 63, s = 3 * v * (1 - v); P[k * 2] += dx * s; P[k * 2 + 1] += dy * s }
        var S = [Double](repeating: 0, count: 64)
        for k in 1..<64 { S[k] = S[k - 1] + hypot(P[k * 2] - P[k * 2 - 2], P[k * 2 + 1] - P[k * 2 - 1]) }
        return (P, S, k0)
    }

    private func shape(_ L: Lattice, _ nodes: [Int], _ j: Int, _ keep: Int, _ hand: Double, _ H: (P: [Double], S: [Double], k0: Int), _ sw: Double, _ ks: Int, _ d: Double) -> PackVein? {
        var px: [Double] = [], py: [Double] = []
        for (k, v) in nodes.enumerated() where k == 0 || k == nodes.count - 1 || k == j || k % keep == 0 { px.append(L.X[v]); py.append(L.Y[v]) }
        for _ in 0..<3 {   // Chaikin x3: a B-spline through the path, ends kept (the NURBS step)
            var qx = [px[0]], qy = [py[0]]
            for k in 0..<(px.count - 1) {
                qx.append(0.75 * px[k] + 0.25 * px[k + 1]); qx.append(0.25 * px[k] + 0.75 * px[k + 1])
                qy.append(0.75 * py[k] + 0.25 * py[k + 1]); qy.append(0.25 * py[k] + 0.75 * py[k + 1])
            }
            qx.append(px[px.count - 1]); qy.append(py[py.count - 1]); px = qx; py = qy
        }
        var x = [px[0]], y = [py[0]], acc = 0.0   // resample every ds units of arc
        for k in 0..<(px.count - 1) {
            let dx = px[k + 1] - px[k], dy = py[k + 1] - py[k], len = (dx * dx + dy * dy).squareRoot()
            var t = Self.ds - acc
            while t <= len { x.append(px[k] + dx * t / len); y.append(py[k] + dy * t / len); t += Self.ds }
            acc = len - (t - Self.ds)
        }
        x.append(px[px.count - 1]); y.append(py[py.count - 1])
        let n = x.count
        guard n >= 3 else { return nil }
        let hx = L.X[nodes[j]], hy = L.Y[nodes[j]]
        var kH = 1, best = Double.infinity
        for k in 1..<(n - 1) { let e = pow(x[k] - hx, 2) + pow(y[k] - hy, 2); if e < best { best = e; kH = k } }
        if hand > 0 {   // pull toward his sweep: each half maps by arc share, so both ends and the heart point line up
            let P = H.P, S = H.S, k0 = H.k0
            var q = 1
            for k in 0..<n {
                let s = k <= kH ? (Double(k) / Double(kH)) * S[k0] : S[k0] + (Double(k - kH) / Double(max(1, n - 1 - kH))) * (S[63] - S[k0])
                while q < 63 && S[q] < s { q += 1 }
                let f = PackMath.clamp((s - S[q - 1]) / max(1e-6, S[q] - S[q - 1]), 0, 1)
                x[k] += (PackMath.lerp(P[q * 2 - 2], P[q * 2], f) - x[k]) * hand
                y[k] += (PackMath.lerp(P[q * 2 - 1], P[q * 2 + 1], f) - y[k]) * hand
            }
        }
        var nx = [Double](repeating: 0, count: n), ny = nx, p = nx
        for k in 0..<n {
            let a = max(0, k - 1), b = min(n - 1, k + 1), tx = x[b] - x[a], ty = y[b] - y[a], l = (tx * tx + ty * ty).squareRoot()
            let ll = l > 0 ? l : 1
            nx[k] = -ty / ll; ny[k] = tx / ll
            p[k] = 1 - sw + sw * cos(2 * .pi * Double(ks) * Double(k) / Double(n - 1))   // Set Curve Radius: whole swells, so both ends are full
        }
        return PackVein(x: x, y: y, nx: nx, ny: ny, p: p, n: n, kH: kH, d: d)
    }

    private func buildVeins(_ seed: Int, _ curves: [PackCurve], _ sprouts: [(Double, Double)], _ count: Int) -> [PackVein?] {
        let R = set.reveal, L = Lattice(seed: seed, R: R, RW: Double(RW), RH: Double(RH))
        var rand = PackRNG(seed + 2)
        let keep = Int(PackMath.clamp(R.smooth.rounded(), 1, 5)), hand = PackMath.clamp(R.hand, 0, 1), sw = PackMath.clamp(R.swell, 0, 0.25)
        var out: [PackVein?] = []
        for i in 0..<min(count, curves.count, sprouts.count) {
            let c = curves[i], (ax, ay) = sprouts[i], h = L.nodeAt(ax, ay), ks = 1 + Int(rand() * 3), d = rand() * PackMath.clamp(R.stagger, 0, 0.3)
            let A = L.route(h, L.edgeNode(c.sx, c.sy, Double(RW), Double(RH)), blocked: false)
            if let A { for k in 0..<L.N { L.blk[k] = false }; for v in A.nodes { L.blk[v] = true } }   // the second half never touches the first
            guard let A, let B = L.route(h, L.edgeNode(c.ex, c.ey, Double(RW), Double(RH)), blocked: true) else {
                AppModel.shared.debug.note("pack", "vein \(i) found no path"); out.append(nil); continue
            }
            for e in A.edges { L.Wt[e] *= 1 + Self.repel }
            for e in B.edges { L.Wt[e] *= 1 + Self.repel }   // later veins cross this one, not run along it
            out.append(shape(L, Array(A.nodes.reversed()) + Array(B.nodes.dropFirst()), A.nodes.count - 1, keep, hand, heroThrough(c, ax, ay), sw, ks, d))
        }
        return out
    }

    /// Samples a..b (fractional) as one filled band; both ends are straight cuts across the line (butt), never a cap or a point.
    private func ribbon(_ ctx: CGContext, _ v: PackVein, _ a: Double, _ b: Double, _ W: Double, _ extra: Double) {
        let path = CGMutablePath(); var first = true
        func go(_ f: Double, _ s: Double) {
            let k = min(v.n - 2, Int(f)), t = f - Double(k), h = W * PackMath.lerp(v.p[k], v.p[k + 1], t) / 2 + extra
            let X = PackMath.lerp(v.x[k], v.x[k + 1], t) + s * PackMath.lerp(v.nx[k], v.nx[k + 1], t) * h
            let Y = PackMath.lerp(v.y[k], v.y[k + 1], t) + s * PackMath.lerp(v.ny[k], v.ny[k + 1], t) * h
            if first { path.move(to: CGPoint(x: X, y: Y)); first = false } else { path.addLine(to: CGPoint(x: X, y: Y)) }
        }
        go(a, 1); var k = Int(ceil(a)); while Double(k) <= b { go(Double(k), 1); k += 1 }; go(b, 1)
        go(b, -1); k = Int(floor(b)); while Double(k) >= a { go(Double(k), -1); k -= 1 }; go(a, -1)
        path.closeSubpath(); ctx.addPath(path); ctx.fillPath()
    }

    // ---------- the reveal on the card back: the heart unravels into veins, the opening runs centre out ----------

    /// The heart's own points (where a curve may be born) never change, so they are read from the image once.
    private func heartPoints() -> [(Double, Double)] {
        if let heartOn { return heartOn }
        let W = Int(RW), H = Int(RH)
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: PackCanvas.space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            c.draw(heart, in: CGRect(x: 0, y: 0, width: W, height: H))   // the bitmap's first row is the image's top row
        }
        var on: [(Double, Double)] = []
        for y in stride(from: 0, to: H, by: 3) { for x in stride(from: 0, to: W, by: 3) where px[(y * W + x) * 4 + 3] > 128 { on.append((Double(x), Double(y))) } }
        heartOn = on
        return on
    }

    func newReveal(seed: Int, tier: String) {
        var rand = PackRNG(seed)
        let curves = PackCurve.make(&rand, Double(RW), Double(RH), 0.45), C = set.colour
        // His ruling 11-17: the heart mark is always filled, no outline. His gold on Obsidian, obsidian on Champagne and Prism.
        let heartFill = tier == "common" ? PackMath.ui(C.heart) : PackMath.ui(C.obsidian)
        heartTint.reset(); heartTint.clear(); heartTint.draw(heart, heartTint.rect)
        heartTint.ctx.setBlendMode(.sourceIn); heartTint.fill(heartFill); heartTint.reset()
        let on = heartPoints()
        var taken: [(Double, Double)] = []
        let anchors: [(Double, Double)] = curves.map { c in
            _ = rand()   // the stream keeps its old length, so the blob below is unchanged
            let P = c.points(40, 64)
            var best = Double.infinity, bx = on.first?.0 ?? Double(RW) / 2, by = on.first?.1 ?? Double(RH) / 2
            for (ox, oy) in on where !taken.contains(where: { pow($0.0 - ox, 2) + pow($0.1 - oy, 2) < 900 }) {   // each curve is born where the heart's line comes nearest it; no two within 30 units
                for k in stride(from: 8, through: 55, by: 3) { let e = pow(P[k * 2] - ox, 2) + pow(P[k * 2 + 1] - oy, 2); if e < best { best = e; bx = ox; by = oy } }
            }
            taken.append((bx, by)); return (bx, by)
        }
        let R = set.reveal
        let sprouts = R.heartUnravel >= 0.5 ? anchors : curves.map { c in let p = c.points(40, 64); return (PackMath.clamp(p[64], 40, Double(RW) - 40), PackMath.clamp(p[65], 40, Double(RH) - 40)) }
        let veins = buildVeins(seed, curves, sprouts, min(15, Int(R.curves.rounded())))
        let blob = (0..<6).map { _ in (rand() * 6.28, 0.5 + rand()) }
        let rimHex = tier == "common" ? "#A6B0BA" : tier == "legendary" ? "#FFF0CD" : "#FFD678"
        rev = PackReveal(curves: curves, anchors: anchors, veins: veins, heartFill: heartFill, ink: tier == "common" ? PackMath.ui(C.champagne) : PackMath.ui(C.obsidian),
                         rim: PackMath.ui(rimHex), blob: blob)
    }

    private func blobPath(_ ctx: CGContext, _ open: Double, _ sx: Double, _ sy: Double) {
        guard let rev else { return }
        let Rm = hypot(Double(RW), Double(RH)) * 0.62
        for k in 0...72 {
            let th = Double(k) / 72 * .pi * 2
            var n = 0.0
            for (i, b) in rev.blob.enumerated() { n += sin(th * Double(i + 2) * b.1 + b.0) / Double(i + 2) }
            let r = open * Rm * (0.86 + 0.16 * n)
            let p = CGPoint(x: (Double(RW) / 2 + cos(th) * r * 0.74) * sx, y: (Double(RH) / 2 + sin(th) * r) * sy)
            if k == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.closePath()
    }

    /// u: 0 = the intact back with its heart, 1 = the clean face. Draws into `reveal` (colour) and `rim` (the glowing edge).
    func drawReveal(_ u: Double) {
        guard var rv = rev else { return }
        let ctx = reveal, L = layer, R = set.reveal, tau = u
        rim.reset(); rim.clear(); ctx.reset()
        if u >= 1 { ctx.draw(front); return }
        ctx.draw(back)
        let born = PackMath.ease(tau / 0.30), unravel = R.heartUnravel >= 0.5, grow = max(0.05, R.grow)
        if u < rv.u { rv.still = false }   // played again, or shown at rest: draw afresh
        rv.u = u
        if !rv.still {
            L.reset(); L.clear()
            if tau < 0.30 || !unravel {
                L.ctx.setAlpha(unravel ? 1 : 1 - PackMath.ease((tau - 0.14) / 0.3)); L.draw(heartTint); L.ctx.setAlpha(1)
                if unravel && born > 0 {
                    L.ctx.setBlendMode(.destinationOut); L.ctx.setFillColor(UIColor.black.cgColor)
                    for (ax, ay) in rv.anchors { L.ctx.fillEllipse(in: CGRect(x: ax - 150 * born, y: ay - 150 * born, width: 300 * born, height: 300 * born)) }
                    L.reset()
                }
            }
            var grown = true
            for i in stride(from: rv.veins.count - 1, through: 0, by: -1) {   // Trim Curve: each vein grows out of the heart toward both edges; vein 0 lands on top
                guard let v = rv.veins[i] else { continue }
                let g = PackMath.ease((tau - v.d) / grow)
                if g < 1 { grown = false }
                if g <= 0 { continue }
                let a = Double(v.kH) * (1 - g), b = Double(v.kH) + Double(v.n - 1 - v.kH) * g
                if b - a < 0.5 { continue }
                let c = rv.curves[i], W = max(1, 6 + (c.w - 6) * born)
                L.ctx.setBlendMode(.destinationOut); L.ctx.setAlpha(born); L.ctx.setFillColor(UIColor.black.cgColor); ribbon(L.ctx, v, a, b, W, R.channel * born / 2)
                L.ctx.setBlendMode(.normal); L.ctx.setAlpha(min(1, 1 + (c.op - 1) * born)); L.ctx.setFillColor((born < 0.5 ? rv.heartFill : rv.ink).cgColor); ribbon(L.ctx, v, a, b, W, 0)
            }
            L.reset()
            rv.still = grown && tau >= (unravel ? 0.30 : 0.44)   // the layer is final: later frames only copy it
        }
        rev = rv
        ctx.draw(L)
        let openAt = PackMath.clamp(R.openAt, 0, 0.7), open = PackMath.ease((tau - openAt) / (0.94 - openAt))
        if open > 0 {
            ctx.ctx.saveGState(); blobPath(ctx.ctx, open * 1.25, 1, 1); ctx.ctx.clip(); ctx.draw(front); ctx.ctx.restoreGState()
            if open < 0.98 && R.rim > 0 {
                ctx.ctx.setStrokeColor(rv.rim.cgColor); ctx.ctx.setLineWidth(R.rim); blobPath(ctx.ctx, open * 1.25, 1, 1); ctx.ctx.strokePath()
                rim.ctx.setStrokeColor(rv.rim.cgColor); rim.ctx.setLineWidth(max(1, R.rim * 0.66)); blobPath(rim.ctx, open * 1.25, 0.5, 0.5); rim.ctx.strokePath()
            }
        }
    }
}
