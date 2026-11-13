import SwiftUI

// Trained hero: the painting-grammar generator (lib/hero-grammar.ts, app/lab/trained-hero/page.tsx), whole.
// Random by default, reproducible by seed. Three weight tiers, thin echoes first, an over/under channel punched at every crossing,
// and the painting's vocabulary: hooks and knots, hard V kinks, S-curves, ghost dashes. The page's inner-tongue panel (the sliders and
// the JSON pl-os writes) is the second half of this screen. The generator is that file's own maths.

enum HeroType: String, CaseIterable, Codable { case chord, arc, sweep, hook, kink, scurve, dash }

struct HeroCfg: Codable, Equatable {
    var count: Double
    var mix: [String: Double]
    var hookLoop: Double, kinkSharp: Double, share0: Double, share1: Double
    var widthK: [Double], op: [Double]
    var gap: Double, drift: Double
    var polarity: String
    var pools: Double, poolScale: Double, glow: Double, stars: Double
    var fieldColor: String, lineColor: String

    static let today = HeroCfg(count: 15, mix: ["chord": 0, "arc": 11, "sweep": 4, "hook": 0, "kink": 0, "scurve": 0, "dash": 0], hookLoop: 60, kinkSharp: 0.6,
                               share0: 5.0 / 15, share1: 5.0 / 15, widthK: [1, 1, 1], op: [0.415, 0.205, 0.1], gap: 9, drift: 1, polarity: "lines",
                               pools: 8, poolScale: 0.5, glow: 0.9, stars: 0.5, fieldColor: "#e6d9a8", lineColor: "#c9a84c")
    static var painting: HeroCfg {
        var c = today
        c.count = 22; c.mix = ["chord": 3, "arc": 3, "sweep": 2, "hook": 3, "kink": 4, "scurve": 2, "dash": 6]
        c.hookLoop = 55; c.kinkSharp = 0.85; c.share0 = 0.4; c.share1 = 0.35; c.op = [0.66, 0.36, 0.18]
        return c
    }
}

struct HeroStroke {
    var type: HeroType
    var layer: Int
    var segs: [[Double]]      // x0 y0 c1x c1y c2x c2y x1 y1
    var width: Double, opacity: Double, phase: Double, amp: Double
}

struct HeroRNG {
    var a: UInt32
    mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

enum HeroGrammar {
    static func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Double] {
        [x0, y0, x0 + (x1 - x0) / 3, y0 + (y1 - y0) / 3, x0 + 2 * (x1 - x0) / 3, y0 + 2 * (y1 - y0) / 3, x1, y1]
    }

    static func generate(_ cfg: HeroCfg, _ w: Double, _ h: Double, seed: Int) -> [HeroStroke] {
        var R = HeroRNG(a: UInt32(truncatingIfNeeded: seed))
        func rand(_ a: Double, _ b: Double) -> Double { a + R.next() * (b - a) }
        let total = HeroType.allCases.reduce(0.0) { $0 + (cfg.mix[$1.rawValue] ?? 0) }
        let tot = total == 0 ? 1 : total
        func pick() -> HeroType {
            var r = R.next() * tot
            for t in HeroType.allCases { r -= cfg.mix[t.rawValue] ?? 0; if r <= 0 { return t } }
            return .arc
        }
        func edge() -> (Double, Double) {
            let m = 140.0, s = Int(floor(R.next() * 4))
            switch s {
            case 0: return (rand(-2 * m, -m), rand(0, h))
            case 1: return (rand(w + m, w + 2 * m), rand(0, h))
            case 2: return (rand(0, w), rand(-2 * m, -m))
            default: return (rand(0, w), rand(h + m, h + 2 * m))
            }
        }
        var out: [HeroStroke] = []
        func layerOf() -> Int { let r = R.next(); return r < cfg.share0 ? 0 : r < cfg.share0 + cfg.share1 ? 1 : 2 }
        func widthFor(_ l: Int) -> Double { (l == 0 ? rand(5, 12) : l == 1 ? rand(2, 4.5) : rand(0.4, 1.5)) * cfg.widthK[l] }
        func push(_ type: HeroType, _ layer: Int, _ segs: [[Double]], _ width: Double? = nil) {
            let wd = width ?? widthFor(layer)
            let op = cfg.op[layer] * rand(0.8, 1.2)
            out.append(HeroStroke(type: type, layer: layer, segs: segs, width: wd, opacity: op, phase: rand(0, 6.28), amp: rand(15, 40)))
        }
        let n = max(0, Int(cfg.count.rounded()))
        for _ in 0..<n {
            let type = pick()
            let layer = type == .dash ? (R.next() < 0.5 ? 1 : 2) : layerOf()
            let (sx, sy) = edge(), (ex, ey) = edge()
            switch type {
            case .arc:
                push(type, layer, [[sx, sy, rand(w * 0.05, w * 0.95), rand(h * 0.05, h * 0.95), rand(w * 0.05, w * 0.95), rand(h * 0.05, h * 0.95), ex, ey]])
            case .chord, .sweep:
                let k = type == .sweep ? 0.08 : 0.03
                let mx = (sx + ex) / 2, my = (sy + ey) / 2, nx = -(ey - sy), ny = ex - sx
                let nl = hypot(nx, ny) == 0 ? 1 : hypot(nx, ny)
                let o = rand(-1, 1) * k * hypot(ex - sx, ey - sy)
                push(type, layer, [[sx, sy, mx + (nx / nl) * o - (mx - sx) * 0.5, my + (ny / nl) * o - (my - sy) * 0.5, mx + (nx / nl) * o + (ex - mx) * 0.5, my + (ny / nl) * o + (ey - my) * 0.5, ex, ey]])
            case .scurve:
                let dx = ex - sx, dy = ey - sy, nl = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy), nx = -dy / nl, ny = dx / nl, a = rand(0.15, 0.35) * nl
                push(type, layer, [[sx, sy, sx + dx * 0.33 + nx * a, sy + dy * 0.33 + ny * a, sx + dx * 0.66 - nx * a, sy + dy * 0.66 - ny * a, ex, ey]])
            case .kink:
                var verts: [(Double, Double)] = [(sx, sy)]
                let pts = 2 + Int(floor(R.next() * 2))
                let base = atan2(ey - sy, ex - sx), len = hypot(ex - sx, ey - sy)
                var cx = sx, cy = sy, ang = base
                for _ in 0..<pts {
                    let step = (len / Double(pts + 1)) * rand(0.7, 1.3)
                    cx += cos(ang) * step; cy += sin(ang) * step; verts.append((cx, cy))
                    ang = base + (R.next() < 0.5 ? -1 : 1) * rand(0.35, 1.2) * (0.4 + cfg.kinkSharp * 1.6)
                }
                verts.append((ex, ey))
                var segs: [[Double]] = []
                for k in 0..<(verts.count - 1) { segs.append(line(verts[k].0, verts[k].1, verts[k + 1].0, verts[k + 1].1)) }
                push(type, layer, segs, widthFor(layer))
            case .hook:
                let dx = ex - sx, dy = ey - sy, nl = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy), ux = dx / nl, uy = dy / nl, nx = -uy, ny = ux
                let t = rand(0.3, 0.7), px = sx + dx * t, py = sy + dy * t, r = cfg.hookLoop * rand(0.7, 1.3), sgn: Double = R.next() < 0.5 ? -1 : 1, kk = 0.5523 * r
                let ax = px - ux * r, ay = py - uy * r
                let cxm = px + nx * r * sgn, cym = py + ny * r * sgn
                let segs: [[Double]] = [
                    [sx, sy, sx + (ax - sx) / 3, sy + (ay - sy) / 3, sx + 2 * (ax - sx) / 3, sy + 2 * (ay - sy) / 3, ax, ay],
                    [ax, ay, ax + ux * kk, ay + uy * kk, cxm - ux * kk * 0.2, cym - uy * kk * 0.2, cxm, cym],
                    [cxm, cym, cxm + ux * kk, cym + uy * kk, px + ux * r + nx * kk * sgn * 0.3, py + uy * r + ny * kk * sgn * 0.3, px + ux * r, py + uy * r],
                    [px + ux * r, py + uy * r, px + ux * r * 1.6, py + uy * r * 1.6, ex - (ex - px) * 0.3, ey - (ey - py) * 0.3, ex, ey],
                ]
                push(type, layer, segs)
            case .dash:
                let base = out.filter { $0.type != .dash }
                var x = rand(0, w), y = rand(0, h), ang = rand(0, .pi)
                if !base.isEmpty {
                    let host = base[Int(floor(R.next() * Double(base.count)))]
                    let sg = host.segs[Int(floor(R.next() * Double(host.segs.count)))]
                    x = sg[0] * 0.5 + sg[6] * 0.5; y = sg[1] * 0.5 + sg[7] * 0.5; ang = atan2(sg[7] - sg[1], sg[6] - sg[0])
                    let off = rand(12, 26) * (R.next() < 0.5 ? -1 : 1)
                    x += -sin(ang) * off; y += cos(ang) * off
                }
                let l = rand(30, 90)
                push(type, layer, [line(x - cos(ang) * l / 2, y - sin(ang) * l / 2, x + cos(ang) * l / 2, y + sin(ang) * l / 2)], widthFor(layer) * 0.8)
            }
        }
        // thin echoes first, heavy last: draw order is depth
        return out.enumerated().sorted { ($0.element.layer, -$0.offset) > ($1.element.layer, -$1.offset) }.map(\.element)
    }

    static func at(_ s: HeroStroke, _ i: Int, _ t: Double, _ drift: Double) -> [Double] {
        let g = s.segs[i]
        if drift == 0 || s.type == .kink || s.type == .dash { return g }
        let k = sin(t * 0.0012 * drift + s.phase) * s.amp, m = cos(t * 0.0009 * drift + s.phase * 1.3) * s.amp
        return [g[0], g[1], g[2] + k, g[3] + m, g[4] - m, g[5] + k, g[6], g[7]]
    }

    static func polyline(_ s: HeroStroke, steps: Int = 24) -> [(Double, Double)] {
        var pts: [(Double, Double)] = []
        for g in s.segs { for k in 0...steps {
            let u = Double(k) / Double(steps), v = 1 - u
            pts.append((v * v * v * g[0] + 3 * v * v * u * g[2] + 3 * v * u * u * g[4] + u * u * u * g[6], v * v * v * g[1] + 3 * v * v * u * g[3] + 3 * v * u * u * g[5] + u * u * u * g[7]))
        } }
        return pts
    }

    static func crossing(_ a: HeroStroke, _ b: HeroStroke) -> (x: Double, y: Double, tx: Double, ty: Double)? {
        let A = polyline(a, steps: 12), B = polyline(b, steps: 12)
        for i in 0..<(A.count - 1) { for j in 0..<(B.count - 1) {
            let p = A[i], q = A[i + 1], r = B[j], s = B[j + 1]
            let d = (q.0 - p.0) * (s.1 - r.1) - (q.1 - p.1) * (s.0 - r.0)
            if abs(d) < 1e-6 { continue }
            let u = ((r.0 - p.0) * (s.1 - r.1) - (r.1 - p.1) * (s.0 - r.0)) / d
            let v = ((r.0 - p.0) * (q.1 - p.1) - (r.1 - p.1) * (q.0 - p.0)) / d
            if u > 0 && u < 1 && v > 0 && v < 1 {
                let L = hypot(q.0 - p.0, q.1 - p.1) == 0 ? 1 : hypot(q.0 - p.0, q.1 - p.1)
                return (p.0 + u * (q.0 - p.0), p.1 + u * (q.1 - p.1), (q.0 - p.0) / L, (q.1 - p.1) / L)
            }
        } }
        return nil
    }
}

// MARK: - The surface

struct HeroSurface: View {
    let strokes: [HeroStroke]
    let cfg: HeroCfg
    let night: Bool
    let seed: Int
    var layerOnly = false
    var time: Double = 0     // milliseconds
    var drift: Double = 0

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        let n = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        return (Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
    }
    private static func color(_ hex: String, _ a: Double = 1) -> Color { let c = rgb(hex); return Color(red: c.0, green: c.1, blue: c.2, opacity: a) }

    var body: some View {
        Canvas { gc, size in
            let w = Double(size.width), h = Double(size.height)
            let fieldLit = night && cfg.polarity == "field"
            if !layerOnly {
                var R = HeroRNG(a: UInt32(truncatingIfNeeded: seed + 7919))
                if !night { gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color("#f1ece1"))) }
                else if !fieldLit {
                    gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color("#0d0c1a")))
                    for _ in 0..<Int((cfg.stars * 90).rounded()) { gc.fill(Path(CGRect(x: R.next() * w, y: R.next() * h, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.35))) }
                } else {
                    gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color("#050504")))
                    let f = Self.rgb(cfg.fieldColor)
                    var lit = gc
                    lit.blendMode = .plusLighter
                    lit.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: f.0, green: f.1, blue: f.2, opacity: 0.5 * cfg.glow), Color(red: f.0, green: f.1, blue: f.2, opacity: 0.36 * cfg.glow)]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
                    for _ in 0..<Int(cfg.pools.rounded()) {
                        let x = R.next() * w, y = R.next() * h, rad = (0.1 + R.next() * 0.25) * max(w, h) * cfg.poolScale * 2
                        lit.fill(Path(CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)),
                                 with: .radialGradient(Gradient(colors: [Color(red: f.0, green: f.1, blue: f.2, opacity: 0.6 * cfg.glow), Color(red: f.0, green: f.1, blue: f.2, opacity: 0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: rad))
                    }
                }
            }
            let dark = fieldLit
            let line = Self.rgb(dark ? "#0a0a0c" : cfg.lineColor)
            gc.drawLayer { layer in
                for s in strokes {
                    var p = Path()
                    for i in s.segs.indices {
                        let q = HeroGrammar.at(s, i, time, drift)
                        if i == 0 { p.move(to: CGPoint(x: q[0], y: q[1])) }
                        p.addCurve(to: CGPoint(x: q[6], y: q[7]), control1: CGPoint(x: q[2], y: q[3]), control2: CGPoint(x: q[4], y: q[5]))
                    }
                    layer.blendMode = .destinationOut
                    layer.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: s.width + (s.type == .dash ? cfg.gap : cfg.gap * 2), lineCap: .butt, lineJoin: .miter))
                    layer.blendMode = .normal
                    let ratio = cfg.op[s.layer] == 0 ? 1 : s.opacity / cfg.op[s.layer]
                    let a = dark ? min(0.97, [0.97, 0.62, 0.3][s.layer] * ratio) : s.opacity
                    layer.stroke(p, with: .color(Color(red: line.0, green: line.1, blue: line.2, opacity: a)), style: StrokeStyle(lineWidth: s.width, lineCap: .butt, lineJoin: .miter))
                }
            }
        }
    }
}

// MARK: - The screen

struct LabHeroView: View {
    @State private var cfg = HeroCfg.today
    @State private var seed = 20260930
    @State private var night = false
    @State private var frozen = false
    @State private var width: Double = 390
    @State private var readout = ""
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let height: Double = 520

    private var strokes: [HeroStroke] { HeroGrammar.generate(cfg, width, height, seed: seed) }

    var body: some View {
        let st = strokes
        let counts = tally(st)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Curve Library · lab · Phase 1 of the trained hero").gEyebrow(10).foregroundStyle(PLG.dim(.dark))
                Text("Trained hero, both sides of the system").gTitle(26, relativeTo: .title).foregroundStyle(PLG.ink(.dark))
                Text("Top: the public render. Below it: the settings panel as it will sit in pl-os, and the JSON it will write. Still random, trained on the painting's shapes.")
                    .font(.footnote).foregroundStyle(PLG.dim(.dark))
                Text("Outer · what the world sees · \(night ? (cfg.polarity == "field" ? "nightOS, field lit" : "nightOS, lines lit") : "lightOS")").gEyebrow(10).foregroundStyle(PLG.dim(.dark))
                GeometryReader { geo in
                    TimelineView(.animation(paused: frozen || reduceMotion || cfg.drift == 0)) { tl in
                        HeroSurface(strokes: st, cfg: cfg, night: night, seed: seed, time: frozen || reduceMotion ? 0 : tl.date.timeIntervalSince(start) * 1000, drift: frozen || reduceMotion ? 0 : cfg.drift)
                    }
                    .onAppear { width = max(320, Double(geo.size.width)) }
                    .onChange(of: geo.size.width) { _, w in width = max(320, Double(w)) }
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4)).overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: 0x2a2a30), lineWidth: 1) }
                .accessibilityLabel("Hero curves preview")
                Text(readout.isEmpty ? "Press \"Run checks\" for the stroke counts, the crossing-gap probe and the seed repeat test." : readout)
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(PLG.dim(.dark)).textSelection(.enabled).frame(minHeight: 60, alignment: .topLeading)
                panel(counts)
                Text("The painting, for the eye · day · digital · night").gEyebrow(10).foregroundStyle(PLG.dim(.dark)).padding(.top, 8)
                ForEach([("Day", "painting-day.jpg"), ("Digital", "painting-digital.jpg"), ("Night", "painting-night.jpg")], id: \.1) { n, f in
                    VStack(alignment: .leading, spacing: 4) {
                        AsyncImage(url: URL(string: LibraryData.shared.base(AppModel.shared) + "/lab/trained-hero/" + f)) { $0.resizable().scaledToFit() } placeholder: { Color(hex: 0x1a1610).frame(height: 160) }
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(n).font(.caption).foregroundStyle(PLG.dim(.dark))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 80)
        }
        .background(Color(hex: 0x0d0d10))
        .environment(\.colorScheme, .dark)
    }

    private func tally(_ st: [HeroStroke]) -> (types: [HeroType: Int], layers: [Int]) {
        var t: [HeroType: Int] = [:], l = [0, 0, 0]
        for s in st { t[s.type, default: 0] += 1; l[s.layer] += 1 }
        return (t, l)
    }

    // The inner tongue: pl-os's panel, in the page's own light card.
    private let ink = Color(hex: 0x1a1510), dim = Color(hex: 0x6b5d48), surface = Color(hex: 0xfdf9f1), gold = Color(hex: 0xc9a84c)

    private func panel(_ counts: (types: [HeroType: Int], layers: [Int])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("The Hero Curves").font(.system(size: 17, design: .serif).italic()).foregroundStyle(gold)
                Spacer()
                Text("inner · pl-os").font(.system(size: 10, design: .monospaced)).foregroundStyle(dim)
            }
            Text("One config the whole site reads. It sits beside The Creator Signal; the switch below mirrors it so you can see both modes.").font(.system(size: 12.5)).foregroundStyle(dim)
            Toggle(isOn: $night) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(night ? "Sleep · nightOS" : "Awake · lightOS").font(.system(size: 13.5)).foregroundStyle(ink)
                    Text("preview of the Creator Signal").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(dim)
                }
            }.tint(gold)
            LabWrap(spacing: 6) {
                chip("Preset · today", false) { var c = HeroCfg.today; c.polarity = cfg.polarity; cfg = c }
                chip("Preset · painting", false) { var c = HeroCfg.painting; c.polarity = cfg.polarity; cfg = c }
                chip("nightOS · lines lit", cfg.polarity == "lines") { cfg.polarity = "lines" }
                chip("nightOS · field lit", cfg.polarity == "field") { cfg.polarity = "field" }
            }
            HStack(spacing: 8) {
                Text("Seed").font(.system(size: 12)).foregroundStyle(dim)
                TextField("seed", value: $seed, format: .number.grouping(.never)).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 120).font(.system(size: 12, design: .monospaced))
            }
            LabWrap(spacing: 6) {
                chip("New draw", false) { seed = Int.random(in: 0..<1_000_000_000) }
                chip(frozen ? "Frozen" : "Freeze", frozen) { frozen.toggle() }
                chip("Run checks", false) { runChecks(counts) }
            }
            ForEach(groups, id: \.0) { title, keys in
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 10, design: .monospaced)).tracking(0.8).textCase(.uppercase).foregroundStyle(dim)
                    ForEach(keys, id: \.self) { k in if let s = sliders.first(where: { $0.key == k }) { slider(s) } }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 160 / 255, green: 140 / 255, blue: 110 / 255).opacity(0.22), lineWidth: 1) }
            }
            HStack {
                Text("What pl-os writes · app_meta").font(.system(size: 10, design: .monospaced)).tracking(0.8).textCase(.uppercase).foregroundStyle(dim)
                Spacer()
                chip("Copy JSON", false) { UIPasteboard.general.string = json }
            }
            ScrollView { Text(json).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(dim).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(maxHeight: 180).padding(8).background(Color(hex: 0xfaf7f0)).clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 6).fill(surface))
        .environment(\.colorScheme, .light)
    }

    private func chip(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 11.5)).foregroundStyle(on ? .white : ink).padding(.horizontal, 12).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 3).fill(on ? gold : Color(hex: 0xf5efe2)))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(on ? gold : Color(red: 160 / 255, green: 140 / 255, blue: 110 / 255).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: sliders

    private struct Sl { let key: String; let label: String; let lo: Double; let hi: Double; let step: Double; let get: (HeroCfg) -> Double; let set: (inout HeroCfg, Double) -> Void }
    private var sliders: [Sl] {
        var s: [Sl] = [Sl(key: "count", label: "Strokes", lo: 4, hi: 40, step: 1, get: { $0.count }, set: { $0.count = $1 })]
        for t in HeroType.allCases { s.append(Sl(key: "mix-" + t.rawValue, label: "Mix · " + t.rawValue, lo: 0, hi: 12, step: 1, get: { $0.mix[t.rawValue] ?? 0 }, set: { $0.mix[t.rawValue] = $1 })) }
        s += [Sl(key: "hookLoop", label: "Hook loop radius", lo: 20, hi: 140, step: 1, get: { $0.hookLoop }, set: { $0.hookLoop = $1 }),
              Sl(key: "kinkSharp", label: "Kink sharpness", lo: 0, hi: 1, step: 0.05, get: { $0.kinkSharp }, set: { $0.kinkSharp = $1 }),
              Sl(key: "share0", label: "Ink 1 · heavy share", lo: 0, hi: 0.8, step: 0.05, get: { $0.share0 }, set: { $0.share0 = $1 }),
              Sl(key: "share1", label: "Ink 2 · mid share", lo: 0, hi: 0.8, step: 0.05, get: { $0.share1 }, set: { $0.share1 = $1 })]
        for l in 0..<3 {
            s.append(Sl(key: "wk\(l)", label: "Ink \(l + 1) · width ×", lo: 0.3, hi: 2.5, step: 0.05, get: { $0.widthK[l] }, set: { $0.widthK[l] = $1 }))
            s.append(Sl(key: "op\(l)", label: "Ink \(l + 1) · opacity", lo: 0.02, hi: 1, step: 0.01, get: { $0.op[l] }, set: { $0.op[l] = $1 }))
        }
        s += [Sl(key: "gap", label: "Over/under gap", lo: 0, hi: 24, step: 1, get: { $0.gap }, set: { $0.gap = $1 }),
              Sl(key: "drift", label: "Motion", lo: 0, hi: 3, step: 0.1, get: { $0.drift }, set: { $0.drift = $1 }),
              Sl(key: "pools", label: "Night field · pools", lo: 0, hi: 20, step: 1, get: { $0.pools }, set: { $0.pools = $1 }),
              Sl(key: "poolScale", label: "Night field · pool size", lo: 0.2, hi: 1.5, step: 0.05, get: { $0.poolScale }, set: { $0.poolScale = $1 }),
              Sl(key: "glow", label: "Night field · glow", lo: 0, hi: 1.5, step: 0.05, get: { $0.glow }, set: { $0.glow = $1 }),
              Sl(key: "stars", label: "Stars", lo: 0, hi: 1, step: 0.05, get: { $0.stars }, set: { $0.stars = $1 })]
        return s
    }
    private var groups: [(String, [String])] {
        [("Stroke mix", ["count"] + HeroType.allCases.map { "mix-" + $0.rawValue }), ("Shapes", ["hookLoop", "kinkSharp"]),
         ("Three inks", ["share0", "share1", "wk0", "op0", "wk1", "op1", "wk2", "op2"]), ("Weave and motion", ["gap", "drift"]), ("nightOS field", ["pools", "poolScale", "glow", "stars"])]
    }
    private func slider(_ s: Sl) -> some View {
        HStack(spacing: 8) {
            Text(s.label).font(.system(size: 12)).foregroundStyle(ink).frame(width: 120, alignment: .leading).lineLimit(2)
            Slider(value: Binding(get: { s.get(cfg) }, set: { v in var c = cfg; s.set(&c, v); cfg = c }), in: s.lo...s.hi, step: s.step).tint(gold)
            Text(String(format: s.step < 1 ? "%.2f" : "%.0f", s.get(cfg))).font(.system(size: 11, design: .monospaced)).foregroundStyle(dim).frame(width: 40, alignment: .trailing).monospacedDigit()
        }
    }

    private var json: String {
        struct Wrap: Encodable { let hero_curves_config: HeroCfg }
        // the page prints the config with seed: 'random-per-load' beside it
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(Wrap(hero_curves_config: cfg)), var s = String(data: d, encoding: .utf8) else { return "{}" }
        s = s.replacingOccurrences(of: "\"stars\" :", with: "\"seed\" : \"random-per-load\",\n    \"stars\" :")
        return s
    }

    // MARK: checks (AT2, AT3, AT4 of the page)

    @MainActor private func pixels(_ st: [HeroStroke], night: Bool, layerOnly: Bool, seed: Int) -> (data: [UInt8], w: Int, h: Int)? {
        let r = ImageRenderer(content: HeroSurface(strokes: st, cfg: cfg, night: night, seed: seed, layerOnly: layerOnly).frame(width: width, height: height))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (buf, w, h)
    }
    private func hash(_ d: [UInt8]) -> String {
        var h: UInt32 = 2166136261
        var i = 0
        while i + 3 < d.count { h ^= UInt32(d[i]) ^ (UInt32(d[i + 1]) << 1) ^ (UInt32(d[i + 2]) << 2) ^ (UInt32(d[i + 3]) << 3); h = h &* 16777619; i += 4 }
        return String(format: "%08x", h)
    }

    @MainActor private func runChecks(_ counts: (types: [HeroType: Int], layers: [Int])) {
        var lines: [String] = []
        let a = pixels(HeroGrammar.generate(cfg, width, height, seed: seed), night: night, layerOnly: false, seed: seed)
        let b = pixels(HeroGrammar.generate(cfg, width, height, seed: seed), night: night, layerOnly: false, seed: seed)
        let c = pixels(HeroGrammar.generate(cfg, width, height, seed: seed + 1), night: night, layerOnly: false, seed: seed + 1)
        if let a, let b, let c {
            let h1 = hash(a.data), h2 = hash(b.data), h3 = hash(c.data)
            lines.append("AT4 same seed \(seed): \(h1) / \(h2) -> \(h1 == h2 ? "IDENTICAL" : "DIFFERENT (fail)")")
            lines.append("AT4 seed \(seed + 1): \(h3) -> \(h3 != h1 ? "differs (pass)" : "same (fail)")")
        } else { lines.append("AT4 could not render the frames to compare.") }
        let sts = HeroGrammar.generate(cfg, width, height, seed: seed)
        var done = false
        if let layer = pixels(sts, night: false, layerOnly: true, seed: seed) {
            outer: for i in 0..<sts.count { for j in (i + 1)..<max(i + 1, sts.count) {
                if sts[i].type == .dash || sts[j].type == .dash { continue }
                guard let cr = HeroGrammar.crossing(sts[i], sts[j]), cr.x >= 20, cr.x <= width - 20, cr.y >= 20, cr.y <= height - 20 else { continue }
                let over = sts[j], under = sts[i]
                func probe(_ d: Double) -> Int {
                    let x = Int((cr.x + cr.tx * d).rounded()), y = Int((cr.y + cr.ty * d).rounded())
                    guard x >= 0, y >= 0, x < layer.w, y < layer.h else { return 0 }
                    return Int(layer.data[(y * layer.w + x) * 4 + 3])
                }
                let near = over.width / 2 + cfg.gap / 2, far = over.width / 2 + cfg.gap + 14
                lines.append("AT3 crossing (\(Int(cr.x)),\(Int(cr.y))) \(under.type.rawValue) under \(over.type.rawValue): alpha in channel \(probe(near)) / \(probe(-near)) (want 0), beyond it \(probe(far)) / \(probe(-far)) (want >0 if the under stroke continues)")
                done = true; break outer
            } }
        }
        if !done { lines.append("AT3 no crossing found for this seed, try another seed") }
        lines.append("AT2 counts: " + HeroType.allCases.map { "\($0.rawValue) \(counts.types[$0] ?? 0)" }.joined(separator: " · ") + " | ink1 \(counts.layers[0]) · ink2 \(counts.layers[1]) · ink3 \(counts.layers[2])")
        readout = lines.joined(separator: "\n")
    }
}

/// Items that wrap onto the next line, left aligned or centred.
struct LabWrap: Layout {
    var spacing: CGFloat = 6
    var centered = false

    private func rows(_ subviews: Subviews, _ maxW: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, sz)); x += sz.width + spacing
        }
        return rows
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 320
        let rs = rows(subviews, maxW)
        var h: CGFloat = 0, w: CGFloat = 0
        for r in rs {
            h += (r.map(\.1.height).max() ?? 0) + spacing
            w = max(w, r.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, r.count - 1)))
        }
        return CGSize(width: centered ? maxW : min(maxW, w), height: max(0, h - spacing))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in rows(subviews, bounds.width) {
            let rowW = r.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, r.count - 1))
            var x = bounds.minX + (centered ? (bounds.width - rowW) / 2 : 0)
            let rowH = r.map(\.1.height).max() ?? 0
            for (i, sz) in r { subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz)); x += sz.width + spacing }
            y += rowH + spacing
        }
    }
}
