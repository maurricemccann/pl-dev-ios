import SwiftUI

// Living Curves (`app/catalogue/living-curves/page.tsx`) and its source (`…/source/page.tsx`). The seven sketches are ported
// line for line from `components/art/sketches.ts` (clothEngine, flowField, kinematicBeziers, slimeMold, matrixRain); The Spiral
// is the Labs' own phyllotaxis view, the same sketch at the same colours. They run at p5's 60 frames a second on the Labs'
// clock (`LabFrameClock`, `LabBitmapSketch`). The source page reads the live page's code blocks, so it is always the code
// that runs on the site.

struct LivingCurvesView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    SiteDisplay(parts: [("The law of\n", false), ("all becoming.", true)], size: 48)
                    Text("The mark that governs the archive \u{2014} rendered in code the same way it was drawn in the studio. Not illustration. The doctrine itself, still running.").siteBody(16)
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 48)

                sketch("I", "The Cloth", "Four strokes. No force \u{2014} yielding at every intersection. The way all real things move.", dark: false) { ClothSketch(blood: false) }
                sketch("II", "The Cloth, in Blood", "The same law, raised in oxblood. Longer memory. A wet edge of light along every curve that survived.", dark: false) { ClothSketch(blood: true) }
                sketch("III", "The Transmission", "The third truth, made legible. Every falling character a thought that persisted long enough to become real.", dark: false, height: 300) { MatrixSketch() }

                VStack(spacing: 8) {
                    SiteRule().padding(.bottom, 32)
                    Text("New Work \u{2014} 2026").siteLabel()
                    Text("Four new systems. Same doctrine.").font(SiteFont.display(20, italic: true)).foregroundStyle(Bone.inkSoft(scheme))
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 40)

                sketch("IV", "The Field", "One thousand marks. Each following the unseen force at its position. The field does not announce itself \u{2014} it just bends everything inside it.", dark: true) { FieldSketch() }
                sketch("V", "The Spiral", "One thousand eight hundred points. Each rotated by 137.5\u{00B0} from the last \u{2014} the golden angle. The same ratio that governs seeds, shells, and petals. The law inside the math.", dark: true) { LabPhyllotaxisView() }
                sketch("VI", "The Chain", "Five chains. Nine links each. The root moves and every link follows \u{2014} the same way a mark follows the hand, the hand follows the mind, the mind follows the law.", dark: false) { ChainSketch() }
                sketch("VII", "The Mind", "Every piece, every law, every glyph \u{2014} linked. God nodes and the communities that orbit them. The archive is not a list. It is a single connected mind, mapped.", dark: true) { MindSketch() }

                SiteBand {
                    VStack(spacing: 22) {
                        Text("The Principle").siteTag(11, Bone.gold)
                        Text("The curve is not the detour. It is the route.").plHand(34).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                        Text("Every garment carries the curve \u{2014} the glyph, the principle encoded in fabric. Wearing it is not decoration. It is a declaration about the shape of all real becoming.")
                            .siteBody(14).multilineTextAlignment(.center)
                        NavigationLink { SiteShopList() } label: { Text("The Collection") }.buttonStyle(SitePill(gold: true))
                        NavigationLink { ArchiveView(model: .shared) } label: { Text("The Archive") }.buttonStyle(SiteGhost())
                        NavigationLink { LivingCurvesSourceView() } label: { SiteDoorLabel(title: "See the code \u{2192}", gold: true) }.buttonStyle(.plain)
                        SiteWatch()
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
        }
        .siteScreen()
        .plScreenTitle("Living Curves")
    }

    private func sketch<S: View>(_ n: String, _ title: String, _ copy: String, dark: Bool, height: CGFloat = 520, @ViewBuilder _ art: () -> S) -> some View {
        let ink = dark ? Color(hex: 0xf1ece1) : Bone.ink(scheme)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(n).plHand(36).foregroundStyle(Bone.gold)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(SiteFont.display(28)).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
                    Text(copy).font(SiteFont.body(14)).foregroundStyle(dark ? Color(hex: 0x9b937f) : Bone.inkSoft(scheme)).lineSpacing(4)
                }
            }
            NavigationLink { LivingCurvesSourceView() } label: { SiteDoorLabel(title: "See the code \u{2192}", gold: dark) }.buttonStyle(.plain)
            art().frame(height: height).clipped()
        }
        .padding(.horizontal, 24).padding(.vertical, 32)
        .background(dark ? Color(hex: 0x0e0c08) : Color.clear)
    }
}

// MARK: - I and II: the cloth engine

@MainActor private final class Cloth {
    struct Opts { let bg: (Double, Double, Double); let a: (Double, Double, Double); let b: (Double, Double, Double); let thick: (Double, Double); let trail: Int; let travel: Double; let spawn: Double; let hl: (Double, Double, Double, Double)? }
    struct Pt { var x: Double; var y: Double; var gap: Bool }
    final class Stroke {
        var pts: [Pt] = []; let dir: Int; var speed: Double; var phase: Double; var thick: Double
        var gapPre = 0, gapPost = 0, x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        init(dir: Int, o: Opts) { self.dir = dir; speed = .random(in: 2..<3.5); phase = .random(in: 0..<1000); thick = .random(in: o.thick.0..<o.thick.1) }
    }
    static let cloth = Opts(bg: (253, 247, 242), a: (199, 90, 27), b: (164, 106, 63), thick: (40, 70), trail: 300, travel: 300, spawn: 200, hl: nil)
    static let blood = Opts(bg: (0, 0, 0), a: (180, 20, 20), b: (255, 60, 60), thick: (55, 95), trail: 900, travel: 600, spawn: 400, hl: (255, 150, 150, 180))

    let o: Opts
    var strokes: [Stroke] = []
    var size: CGSize = .zero
    var frame = 0
    init(_ o: Opts) { self.o = o }

    func spawn(_ s: Stroke) {
        let w = Double(size.width), h = Double(size.height), S = o.spawn
        switch s.dir {
        case 0: s.x = -S; s.y = .random(in: h * 0.2..<h * 0.8); s.vx = s.speed; s.vy = .random(in: -0.4..<0.4)
        case 1: s.x = w + S; s.y = .random(in: h * 0.2..<h * 0.8); s.vx = -s.speed; s.vy = .random(in: -0.4..<0.4)
        case 2: s.x = -S; s.y = -S; s.vx = s.speed; s.vy = s.speed * 0.8
        default: s.x = -S; s.y = h + S; s.vx = s.speed; s.vy = -s.speed * 0.8
        }
    }

    func ensure(_ s: CGSize) {
        guard s.width > 10, strokes.isEmpty || s != size else { return }
        size = s
        strokes = (0..<4).map { Stroke(dir: $0, o: o) }
        strokes.forEach(spawn)
    }

    func tick() {
        frame += 1
        let w = Double(size.width), h = Double(size.height)
        for s in strokes {
            for other in strokes where other !== s {   // checkIntersections
                guard let last = other.pts.last else { continue }
                let dx = s.x - last.x, dy = s.y - last.y
                if dx * dx + dy * dy < 900 { s.gapPre = 6; s.gapPost = 16 }
            }
            let drift = sin(Double(frame) * 0.01 + s.phase) * 1.2, pulse = sin(Double(frame) * 0.02 + s.phase) * 1.8
            s.x += s.vx; s.y += s.vy + drift + pulse
            var gap = false
            if s.gapPre > 0 { gap = true; s.gapPre -= 1 } else if s.gapPost > 0 { gap = true; s.gapPost -= 1 }
            s.pts.append(Pt(x: s.x, y: s.y, gap: gap))
            if s.pts.count > o.trail { s.pts.removeFirst() }
            if s.x < -o.travel || s.x > w + o.travel || s.y < -o.travel || s.y > h + o.travel { s.pts = []; s.phase = .random(in: 0..<1000); spawn(s) }
        }
    }

    private func rgb(_ c: (Double, Double, Double), _ a: Double = 255) -> Color { Color(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255).opacity(a / 255) }

    func draw(_ g: inout GraphicsContext) {
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(rgb(o.bg)))
        for s in strokes where s.pts.count >= 3 {
            // p5 strokes a shape in the colour last set before endShape: the last drawn segment's direction picks the blend
            var kept: [CGPoint] = []
            var t = 0.5
            for i in 1..<s.pts.count where !s.pts[i].gap {
                let p = s.pts[i], q = s.pts[i - 1]
                let dx = p.x - q.x, dy = p.y - q.y, mag = max(1e-9, (dx * dx + dy * dy).squareRoot())
                t = (-dy / mag + 1) * 0.5
                kept.append(CGPoint(x: p.x, y: p.y))
            }
            guard kept.count > 1 else { continue }
            let path = LabKinematicView.spline(kept)
            g.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: s.thick + (o.hl == nil ? 10 : 20), lineCap: .square))
            let col = (o.a.0 + (o.b.0 - o.a.0) * t, o.a.1 + (o.b.1 - o.a.1) * t, o.a.2 + (o.b.2 - o.a.2) * t)
            g.stroke(path, with: .color(rgb(col)), style: StrokeStyle(lineWidth: s.thick, lineCap: .square))
            if let hl = o.hl {
                var refl: [CGPoint] = []
                for i in 2..<s.pts.count where !s.pts[i].gap {
                    let p = s.pts[i], q = s.pts[i - 1]
                    let dx = p.x - q.x, dy = p.y - q.y, mag = max(1e-9, (dx * dx + dy * dy).squareRoot())
                    let nx = -dy / mag, ny = dx / mag
                    let off = s.thick * 0.15 + sin(Double(i) * 0.1 + s.phase) * (s.thick * 0.05)
                    refl.append(CGPoint(x: p.x + nx * off, y: p.y + ny * off))
                }
                if refl.count > 1 { g.stroke(LabKinematicView.spline(refl), with: .color(rgb((hl.0, hl.1, hl.2), hl.3)), style: StrokeStyle(lineWidth: s.thick * 0.25, lineCap: .square)) }
            }
        }
    }
}

private struct ClothSketch: View {
    let blood: Bool
    @State private var sim: Cloth
    @State private var clock = LabFrameClock()
    @Environment(\.accessibilityReduceMotion) private var reduce
    init(blood: Bool) { self.blood = blood; _sim = State(initialValue: Cloth(blood ? Cloth.blood : Cloth.cloth)) }
    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            Canvas { g, size in
                sim.ensure(size)
                let n = reduce ? (sim.frame == 0 ? 120 : 0) : clock.due(tl.date)
                for _ in 0..<n { sim.tick() }
                sim.draw(&g)
            }
        }
        .drawingGroup(opaque: true)
        .accessibilityLabel(blood ? "The Cloth in Blood: oxblood strokes crossing on black" : "The Cloth: burnt and bronze strokes crossing on cream")
    }
}

// MARK: - III: the transmission (code rain, the gold phrase, scanlines)

private struct MatrixSketch: View {
    private final class Box { var streams: [(x: Double, y: Double, speed: Double)] = [] }
    @State private var box = Box()
    private static let chars = Array("01{}[]<>/=+*;:!%$#@")
    private static let lines = ["PREPARED", "FOR", "LUXURY", "\u{00B7}"]

    var body: some View {
        LabBitmapSketch(ground: CGColor(gray: 0, alpha: 1), step: { c, size, frame in
            let W = Double(size.width), H = Double(size.height)
            c.setFillColor(CGColor(gray: 0, alpha: 30 / 255)); c.fill(CGRect(origin: .zero, size: size))
            UIGraphicsPushContext(c)
            let small = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), big = UIFont.monospacedSystemFont(ofSize: 20, weight: .regular)
            let rain: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: UIColor(red: 80 / 255, green: 120 / 255, blue: 80 / 255, alpha: 90 / 255)]
            for i in box.streams.indices {
                let s = box.streams[i]
                NSString(string: String(Self.chars.randomElement()!)).draw(at: CGPoint(x: s.x, y: s.y - 16), withAttributes: rain)
                box.streams[i].y += s.speed
                if box.streams[i].y > H + 20 { box.streams[i].y = .random(in: -300..<0); box.streams[i].speed = .random(in: 2..<6) }
            }
            let cw = ("A" as NSString).size(withAttributes: [.font: big]).width
            for (i, str) in Self.lines.enumerated() {
                let y = H * 0.35 + Double(i) * 28 + sin(Double(frame) * 0.01 + Double(i)) * 3 - 20
                let x = (W - cw * Double(str.count)) / 2
                for (j, ch) in str.enumerated() {
                    let s = NSString(string: String(ch))
                    s.draw(at: CGPoint(x: x + Double(j) * cw, y: y), withAttributes: [.font: big, .foregroundColor: UIColor(red: 1, green: 240 / 255, blue: 200 / 255, alpha: 180 / 255)])
                    s.draw(at: CGPoint(x: x + Double(j) * cw + 1, y: y + 1), withAttributes: [.font: big, .foregroundColor: UIColor(red: 201 / 255, green: 168 / 255, blue: 76 / 255, alpha: 1)])
                }
            }
            UIGraphicsPopContext()
            c.setStrokeColor(CGColor(srgbRed: 201 / 255, green: 168 / 255, blue: 76 / 255, alpha: 40 / 255)); c.setLineWidth(1)
            var y = 0.0
            while y < H { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: W, y: y)); y += 3 }
            c.strokePath()
        }, reseed: { size in
            box.streams = (0..<Int(size.width / 16)).map { (x: Double($0) * 16, y: .random(in: -1500..<0), speed: .random(in: 2..<6)) }
        })
        .accessibilityLabel("The Transmission: code falling behind the words Prepared for Luxury")
    }
}

// MARK: - IV: the field (p5's noise, ported)

/// p5.js `noise()`: four octaves of smoothed value noise over a 4096-entry table, falloff 0.5.
final class P5Noise {
    private var table: [Double] = (0..<4096).map { _ in Double.random(in: 0..<1) }
    private func fade(_ i: Double) -> Double { 0.5 * (1 - cos(i * .pi)) }

    func noise(_ x0: Double, _ y0: Double, _ z0: Double) -> Double {
        var x = abs(x0), y = abs(y0), z = abs(z0)
        var xi = Int(x), yi = Int(y), zi = Int(z)
        var xf = x - Double(xi), yf = y - Double(yi), zf = z - Double(zi)
        var r = 0.0, ampl = 0.5
        for _ in 0..<4 {
            var of = xi + (yi << 4) + (zi << 8)
            let rxf = fade(xf), ryf = fade(yf)
            var n1 = table[of & 4095]
            n1 += rxf * (table[(of + 1) & 4095] - n1)
            var n2 = table[(of + 16) & 4095]
            n2 += rxf * (table[(of + 17) & 4095] - n2)
            n1 += ryf * (n2 - n1)
            of += 256
            n2 = table[of & 4095]
            n2 += rxf * (table[(of + 1) & 4095] - n2)
            var n3 = table[(of + 16) & 4095]
            n3 += rxf * (table[(of + 17) & 4095] - n3)
            n2 += ryf * (n3 - n2)
            n1 += fade(zf) * (n2 - n1)
            r += n1 * ampl
            ampl *= 0.5
            xi <<= 1; xf *= 2; yi <<= 1; yf *= 2; zi <<= 1; zf *= 2
            if xf >= 1 { xi += 1; xf -= 1 }
            if yf >= 1 { yi += 1; yf -= 1 }
            if zf >= 1 { zi += 1; zf -= 1 }
        }
        x = 0; y = 0; z = 0
        return r
    }
}

struct FieldSketch: View {
    private final class Box { var pts: [(x: Double, y: Double, vx: Double, vy: Double, age: Double, maxAge: Double)] = []; let noise = P5Noise() }
    @State private var box = Box()

    var body: some View {
        LabBitmapSketch(ground: CGColor(srgbRed: 14 / 255, green: 12 / 255, blue: 8 / 255, alpha: 1), step: { c, size, frame in
            let W = Double(size.width), H = Double(size.height)
            c.setFillColor(CGColor(srgbRed: 14 / 255, green: 12 / 255, blue: 8 / 255, alpha: 14 / 255)); c.fill(CGRect(origin: .zero, size: size))
            c.setLineWidth(0.8)
            for i in box.pts.indices {
                var p = box.pts[i]
                let a = box.noise.noise(p.x * 0.0025, p.y * 0.0025, Double(frame) * 0.00038) * .pi * 2 * 3.8
                p.vx += (cos(a) * 2.3 - p.vx) * 0.07; p.vy += (sin(a) * 2.3 - p.vy) * 0.07
                let ox = p.x, oy = p.y
                p.x += p.vx; p.y += p.vy; p.age += 1
                let life = p.age.truncatingRemainder(dividingBy: p.maxAge) / p.maxAge
                let alpha = (sin(life * .pi) * 170 + 8).rounded()
                c.setStrokeColor(CGColor(srgbRed: 201 / 255, green: 168 / 255, blue: 76 / 255, alpha: alpha / 255))
                c.move(to: CGPoint(x: ox, y: oy)); c.addLine(to: CGPoint(x: p.x, y: p.y)); c.strokePath()
                if p.age > p.maxAge || p.x < -8 || p.x > W + 8 || p.y < -8 || p.y > H + 8 { p = Self.fresh(W, H, maxAge: p.maxAge) }
                box.pts[i] = p
            }
        }, reseed: { size in
            box.pts = (0..<1000).map { _ in Self.fresh(Double(size.width), Double(size.height), maxAge: 200) }
        })
        .accessibilityLabel("The Field: a thousand gold marks following an unseen flow on obsidian")
    }

    /// The sketch's `reset`: a random spot, still, a random age within the old life, then a new life length.
    private static func fresh(_ w: Double, _ h: Double, maxAge: Double) -> (x: Double, y: Double, vx: Double, vy: Double, age: Double, maxAge: Double) {
        (x: .random(in: 0..<max(1, w)), y: .random(in: 0..<max(1, h)), vx: 0, vy: 0, age: .random(in: 0..<maxAge), maxAge: .random(in: 140..<380))
    }
}

// MARK: - VI: the chain, gold on bone

private struct ChainSketch: View {
    private struct Chain { var links: [CGPoint]; var rootX: Double; var rootY: Double; var phase: Double }
    private final class Box { var chains: [Chain] = []; var size: CGSize = .zero }
    @State private var box = Box()
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let len = 50.0

    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            Canvas { g, size in
                if box.size != size { reseed(size) }
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xf1ece1)))
                let t = tl.date.timeIntervalSince(start) * 60 * 0.013
                let gold = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255)
                for ci in box.chains.indices {
                    var ch = box.chains[ci]
                    ch.links[0].x = ch.rootX + sin(t * 0.72 + ch.phase) * 62 + sin(t * 1.31 + ch.phase * 1.4) * 26
                    ch.links[0].y = ch.rootY + cos(t * 0.55 + ch.phase) * 42 + cos(t * 1.13 + ch.phase * 0.9) * 18
                    for j in 1..<ch.links.count {
                        let p = ch.links[j - 1], c = ch.links[j]
                        let dx = Double(c.x - p.x), dy = Double(c.y - p.y), d = max(1e-4, (dx * dx + dy * dy).squareRoot())
                        ch.links[j] = CGPoint(x: Double(p.x) + dx / d * len, y: Double(p.y) + dy / d * len)
                    }
                    box.chains[ci] = ch
                    let curve = LabKinematicView.spline(ch.links)
                    g.stroke(curve, with: .color(Color(red: 21 / 255, green: 18 / 255, blue: 11 / 255).opacity(18 / 255)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    g.stroke(curve, with: .color(gold.opacity(210 / 255)), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    for (j, l) in ch.links.enumerated() {
                        let f = Double(j) / Double(ch.links.count - 1), d = 4.5 + (1.2 - 4.5) * f
                        g.fill(Path(ellipseIn: CGRect(x: l.x - d / 2, y: l.y - d / 2, width: d, height: d)), with: .color(gold.opacity((200 - f * 145).rounded() / 255)))
                    }
                }
            }
        }
        .drawingGroup(opaque: true)
        .accessibilityLabel("The Chain: five gold chains following their roots on bone")
    }

    private func reseed(_ size: CGSize) {
        box.size = size
        guard size.width > 20, size.height > 20 else { box.chains = []; return }
        box.chains = (0..<5).map { _ in
            let rx = Double.random(in: Double(size.width) * 0.18..<Double(size.width) * 0.82), ry = Double.random(in: Double(size.height) * 0.22..<Double(size.height) * 0.78)
            return Chain(links: (0..<9).map { CGPoint(x: rx, y: ry - Double($0) * len) }, rootX: rx, rootY: ry, phase: .random(in: 0..<(2 * .pi)))
        }
    }
}

// MARK: - VII: the mind (the archive as a force-settled knowledge graph)

private final class MindGraph {
    struct Node { var x: Double; var y: Double; var vx = 0.0; var vy = 0.0; let r: Double; let hub: Bool; let col: (Double, Double, Double) }
    static let community: [(Double, Double, Double)] = [(232, 116, 59), (240, 168, 48), (154, 138, 58), (46, 111, 214), (77, 184, 232),
                                                        (43, 177, 168), (224, 57, 43), (123, 79, 192), (154, 163, 176), (58, 167, 87)]
    var nodes: [Node] = []
    var edges: [(Int, Int)] = []
    var size: CGSize = .zero

    func build(_ s: CGSize) {
        size = s; nodes = []; edges = []
        let w = Double(s.width), h = Double(s.height), cx = w / 2, cy = h / 2
        var hubs: [Int] = []
        for c in 0..<Self.community.count {
            let a = Double(c) / Double(Self.community.count) * 2 * .pi + .random(in: -0.2..<0.2)
            let rr = min(w, h) * (0.12 + .random(in: 0..<0.12))
            let god = c < 4
            nodes.append(Node(x: cx + cos(a) * rr + .random(in: -24..<24), y: cy + sin(a) * rr + .random(in: -24..<24), r: god ? .random(in: 9..<15) : .random(in: 5..<8), hub: true, col: Self.community[c]))
            hubs.append(nodes.count - 1)
        }
        for i in 0..<hubs.count { for j in (i + 1)..<hubs.count where Double.random(in: 0..<1) < 0.6 { edges.append((hubs[i], hubs[j])) } }
        for c in 0..<Self.community.count {
            let hub = nodes[hubs[c]]
            for k in 0..<Int.random(in: 12..<22) {
                let a = Double.random(in: 0..<(2 * .pi)), d = Double.random(in: 28..<95)
                let idx = nodes.count
                nodes.append(Node(x: hub.x + cos(a) * d, y: hub.y + sin(a) * d, r: .random(in: 2.2..<4.4), hub: false, col: Self.community[c]))
                edges.append((hubs[c], idx))
                if k > 0 && Double.random(in: 0..<1) < 0.35 { edges.append((idx, idx - 1)) }
                if Double.random(in: 0..<1) < 0.22 { edges.append((idx, hubs[Int.random(in: 0..<hubs.count)])) }
                if Double.random(in: 0..<1) < 0.10 { edges.append((idx, Int.random(in: 0..<nodes.count))) }
            }
        }
    }

    func step() {
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        for i in nodes.indices {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y
                let d2 = max(1, dx * dx + dy * dy), d = d2.squareRoot(), f = 380 / d2
                let fx = dx / d * f, fy = dy / d * f
                nodes[i].vx += fx; nodes[i].vy += fy; nodes[j].vx -= fx; nodes[j].vy -= fy
            }
            nodes[i].vx += (cx - nodes[i].x) * 0.0009; nodes[i].vy += (cy - nodes[i].y) * 0.0009
        }
        for (a, b) in edges {
            let dx = nodes[b].x - nodes[a].x, dy = nodes[b].y - nodes[a].y, d = max(1e-9, (dx * dx + dy * dy).squareRoot())
            let f = (d - (nodes[a].hub || nodes[b].hub ? 64 : 42)) * 0.008, fx = dx / d * f, fy = dy / d * f
            nodes[a].vx += fx; nodes[a].vy += fy; nodes[b].vx -= fx; nodes[b].vy -= fy
        }
        for i in nodes.indices { nodes[i].vx *= 0.86; nodes[i].vy *= 0.86; nodes[i].x += nodes[i].vx; nodes[i].y += nodes[i].vy }
    }

    func draw(_ g: inout GraphicsContext) {
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0e0c08)))
        var hubEdges = Path(), leafEdges = Path()
        for (a, b) in edges {
            let p = CGPoint(x: nodes[a].x, y: nodes[a].y), q = CGPoint(x: nodes[b].x, y: nodes[b].y)
            if nodes[a].hub || nodes[b].hub { hubEdges.move(to: p); hubEdges.addLine(to: q) } else { leafEdges.move(to: p); leafEdges.addLine(to: q) }
        }
        let grey = Color(red: 186 / 255, green: 188 / 255, blue: 198 / 255)
        g.stroke(leafEdges, with: .color(grey.opacity(26 / 255)), lineWidth: 0.7)
        g.stroke(hubEdges, with: .color(grey.opacity(46 / 255)), lineWidth: 0.7)
        for n in nodes {
            let col = Color(red: n.col.0 / 255, green: n.col.1 / 255, blue: n.col.2 / 255)
            if n.hub {
                let halo = n.r + 5
                g.fill(Path(ellipseIn: CGRect(x: n.x - halo, y: n.y - halo, width: halo * 2, height: halo * 2)), with: .color(col.opacity(55 / 255)))
                g.fill(Path(ellipseIn: CGRect(x: n.x - n.r, y: n.y - n.r, width: n.r * 2, height: n.r * 2)), with: .color(col))
            } else {
                g.fill(Path(ellipseIn: CGRect(x: n.x - n.r, y: n.y - n.r, width: n.r * 2, height: n.r * 2)), with: .color(col.opacity(225 / 255)))
            }
        }
    }
}

private struct MindSketch: View {
    @State private var sim = MindGraph()
    @State private var clock = LabFrameClock()
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            Canvas { g, size in
                if sim.nodes.isEmpty, size.width > 20 { sim.build(size); if reduce { for _ in 0..<200 { sim.step() } } }
                sim.size = size   // a resize keeps the settled graph, as the site's does
                if !reduce { for _ in 0..<clock.due(tl.date) { sim.step() } }
                sim.draw(&g)
            }
        }
        .drawingGroup(opaque: true)
        .accessibilityLabel("The Mind: the archive drawn as a knowledge graph, communities orbiting their hubs")
    }
}

// MARK: - The source

/// `/catalogue/living-curves/source`: the exact functions, read from the live page's code blocks (the shared engine first).
struct LivingCurvesSourceView: View {
    @State private var blocks: [String] = []
    @State private var failed = false
    @Environment(\.colorScheme) private var scheme
    private static let labels = ["The Shared Engine", "I \u{00B7} The Cloth", "II \u{00B7} The Cloth, in Blood", "III \u{00B7} The Transmission", "IV \u{00B7} The Field",
                                 "V \u{00B7} The Spiral", "VI \u{00B7} The Chain", "VII \u{00B7} The Mind"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("The source.").font(SiteFont.display(52)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
                    Text("These are the exact functions that draw the work on the previous page. Unedited. Unabridged. The code is part of the archive.").siteBody(16)
                }
                if blocks.isEmpty {
                    if failed { EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the source", detail: "The site did not answer and the page has not been saved yet. Pull to try again.") }
                    else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { i, code in
                    VStack(alignment: .leading, spacing: 12) {
                        if i == 0 {
                            HStack(spacing: 14) { Text("0").plHand(26).foregroundStyle(Bone.gold); Text(Self.labels[0]).font(SiteFont.display(20, italic: true)).foregroundStyle(Bone.inkSoft(scheme)) }
                            Text("The cloth and blood cloth share one brushstroke engine. Parameters differ; the law is the same.").siteBody(14)
                        } else {
                            SiteRule()
                            Text(i < Self.labels.count ? Self.labels[i] : "").font(SiteFont.display(20)).foregroundStyle(Bone.ink(scheme)).padding(.top, 12)
                        }
                        ScrollView(.horizontal) {
                            Text(code).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.65)).lineSpacing(3)
                                .padding(24).fixedSize()
                        }
                        .background(Color(hex: 0x0e0c08))
                        .textSelection(.enabled)
                    }
                }
                SiteBand {
                    VStack(spacing: 22) {
                        Text("The code and the cloth are the same argument.").font(SiteFont.display(30, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                        NavigationLink { SiteReaderView(path: "the-three-truths", title: "The Three Truths") } label: { Text("The Three Truths") }.buttonStyle(SiteGhost())
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, -24)
            }
            .padding(.horizontal, 24).padding(.top, 24)
        }
        .siteScreen()
        .plScreenTitle("The Source")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let html = await SiteData.html("catalogue/living-curves/source") else { failed = true; return }
        let found = SiteData.matches("<code[^>]*>(.*?)</code>", in: html).map { Self.decode($0[0]) }.filter { !$0.isEmpty }
        if found.isEmpty { failed = true } else { blocks = found; failed = false }
    }

    /// Entities only: the code's own line breaks and indentation stay.
    static func decode(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<!-- -->", with: "")
        for (k, v) in ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&amp;": "&"] { t = t.replacingOccurrences(of: k, with: v) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
