import MetalKit
import SwiftUI

// The scroll studies and the type lab: The study (a door and the Three Truths), Home study (2,000 curves drawn as you scroll),
// Hand (type, rendered in his hands), Components (the house's reusable pieces, each live).
// Sources: app/lab/study, app/lab/home, public/hand.html, app/components/page.tsx, components/ElectricBorder.tsx.

private let obsidian = Color(hex: 0x0e0c08)
private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t) }

/// Scroll progress 0...1 of a ScrollView, read natively.
private struct ProgressKey: Equatable { var p: Double }

// MARK: - The study: a door opens as you scroll, and the Three Truths arrive

struct LabStudyView: View {
    @State private var prog = 0.0
    private let goldDim = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255).opacity(0.58)

    private struct Panel { let pos: Int; let enter, hold, exit, leave: Double; let lines: [String]; let size: Int }   // pos: 0 left, 1 right, 2 center; size 0 sm, 1 lg, 2 xl
    private let panels: [Panel] = [
        Panel(pos: 0, enter: 0.27, hold: 0.34, exit: 0.50, leave: 0.56, lines: ["Prepared for luxury."], size: 1),
        Panel(pos: 1, enter: 0.31, hold: 0.38, exit: 0.52, leave: 0.58, lines: ["The preparation", "was the mechanism."], size: 0),
        Panel(pos: 0, enter: 0.50, hold: 0.57, exit: 0.70, leave: 0.76, lines: ["You are in control", "of your reality."], size: 0),
        Panel(pos: 1, enter: 0.54, hold: 0.61, exit: 0.72, leave: 0.78, lines: ["Thought rearranges you.", "You rearrange your circumstances."], size: 0),
        Panel(pos: 2, enter: 0.72, hold: 0.79, exit: 0.88, leave: 0.93, lines: ["What persists in the mind", "becomes your reality."], size: 1),
        Panel(pos: 2, enter: 0.91, hold: 0.95, exit: 0.99, leave: 1.0, lines: ["Watch this."], size: 2),
    ]
    private func alpha(_ p: Double, _ e: Double, _ h: Double, _ x: Double, _ l: Double) -> Double { p < e ? 0 : p < h ? smoothstep(e, h, p) : p < x ? 1 : 1 - smoothstep(x, l, p) }

    var body: some View {
        let doorAngle = smoothstep(0.10, 0.32, prog) * 80
        let doorLayer = 1 - smoothstep(0.30, 0.44, prog)
        let whisper = 1 - smoothstep(0.07, 0.20, prog)
        let glow = smoothstep(0.20, 0.44, prog)
        let sliver = clamp01(1 - doorAngle / 15)
        ZStack {
            obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 201 / 255, green: 130 / 255, blue: 40 / 255).opacity(0.11), Color(red: 160 / 255, green: 80 / 255, blue: 20 / 255).opacity(0.05), .clear],
                           center: UnitPoint(x: 0.5, y: 0.52), startRadius: 0, endRadius: 520)
                .opacity(glow).ignoresSafeArea().allowsHitTesting(false)
            GeometryReader { geo in
                let dw = min(max(160, geo.size.width * 0.5), 260), dh = min(max(280, geo.size.height * 0.62), 500)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().strokeBorder(PLG.gold.opacity(0.28), lineWidth: 1).frame(width: 40, height: 40)
                            .overlay { Circle().strokeBorder(PLG.gold.opacity(0.5), lineWidth: 1).frame(width: 21, height: 21) }
                            .opacity(0.7).offset(y: -(dh / 2) - 34)
                        ZStack {
                            Rectangle().fill(RadialGradient(colors: [Color(red: 220 / 255, green: 120 / 255, blue: 40 / 255).opacity(0.5), Color(red: 200 / 255, green: 90 / 255, blue: 20 / 255).opacity(0.22), .clear],
                                                             center: UnitPoint(x: 0.12, y: 0.5), startRadius: 0, endRadius: dh * 0.55)).opacity(sliver)
                            doorLeaf(dw, dh).rotation3DEffect(.degrees(-doorAngle), axis: (0, 1, 0), anchor: .leading, anchorZ: 0, perspective: 0.4)
                        }
                        .frame(width: dw, height: dh)
                        .overlay { Rectangle().strokeBorder(PLG.gold.opacity(0.25), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.5), radius: 30).shadow(color: PLG.gold.opacity(0.06), radius: 15)
                        Text("The door is open.").font(.system(size: 11, design: .serif)).labCaps().tracking(2.4).foregroundStyle(goldDim).opacity(whisper).offset(y: dh / 2 + 24)
                    }
                    .opacity(doorLayer)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            ForEach(panels.indices, id: \.self) { i in
                let pn = panels[i]
                let a = alpha(prog, pn.enter, pn.hold, pn.exit, pn.leave)
                if a >= 0.005 {
                    HStack {
                        if pn.pos != 0 { Spacer(minLength: 0) }
                        VStack(alignment: pn.pos == 2 ? .center : pn.pos == 0 ? .leading : .trailing, spacing: 5) {
                            ForEach(pn.lines, id: \.self) { line in
                                Text(line).plHand(pn.size == 2 ? 54 : pn.size == 1 ? 30 : 19, relativeTo: pn.size == 2 ? .largeTitle : .title2)
                                    .foregroundStyle(pn.size == 2 ? Color(hex: 0xd4b86a) : PLG.gold.opacity(0.82))
                                    .multilineTextAlignment(pn.pos == 2 ? .center : pn.pos == 0 ? .leading : .trailing)
                            }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 24)
                        .background(RoundedRectangle(cornerRadius: 2).fill(PLG.gold.opacity(0.035)).overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(PLG.gold.opacity(0.09), lineWidth: 1) })
                        .background(.ultraThinMaterial.opacity(0.4))
                        if pn.pos != 1 { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 22).opacity(a).allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                }
            }
            // The scroll: 450 screens tall, invisible; it only carries the progress.
            GeometryReader { geo in
                ScrollView(showsIndicators: false) { Color.clear.frame(height: geo.size.height * 4.5) }
                    .onScrollGeometryChange(for: Double.self) { g in Double(g.contentOffset.y / max(1, g.contentSize.height - g.containerSize.height)) } action: { _, v in
                        withAnimation(.linear(duration: 0.12)) { prog = clamp01(v) }
                    }
            }
        }
    }

    private func doorLeaf(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: Color(hex: 0x2e1505), location: 0), .init(color: Color(hex: 0x3d2009), location: 0.28), .init(color: Color(hex: 0x4a2c12), location: 0.5),
                                   .init(color: Color(hex: 0x3a1d08), location: 0.72), .init(color: Color(hex: 0x2c1304), location: 1)], startPoint: UnitPoint(x: 0.4, y: 0), endPoint: UnitPoint(x: 0.6, y: 1))
            // boards
            Canvas { gc, size in
                var x: CGFloat = 0
                while x < size.width {
                    gc.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.14)))
                    gc.fill(Path(CGRect(x: x + 6, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.09)))
                    x += 16
                }
            }
            Circle().fill(RadialGradient(colors: [PLG.gold, Color(hex: 0x6b4d18)], center: UnitPoint(x: 0.32, y: 0.32), startRadius: 0, endRadius: 8)).frame(width: 11, height: 11)
                .shadow(color: PLG.gold.opacity(0.35), radius: 3).position(x: w * 0.91, y: h / 2)
            ForEach([0.22, 0.74], id: \.self) { f in
                RoundedRectangle(cornerRadius: 1).fill(goldDim).frame(width: 7, height: 15).position(x: w * 0.03 + 3, y: h * f)
            }
        }
        .frame(width: w, height: h)
        .overlay(alignment: .trailing) { LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .leading, endPoint: .trailing).frame(width: 18) }
    }
}

// MARK: - Home study: 2,000 curves, drawn as you scroll

struct LabHomeStudyView: View {
    private struct Curve { var x0, y0, c1x, c1y, c2x, c2y, x1, y1, alpha, width: Double }
    private static let total = 2000
    @State private var prog = 0.0
    @State private var bitmap = LabBitmap()
    @State private var state = Draw()
    @Environment(\.displayScale) private var displayScale
    private final class Draw { var drawn = 0; var curves: [Curve] = [] }

    private let beats: [(at: Double, lines: [String], size: Int)] = [
        (0.01, ["April 2019.", "One mark."], 0), (0.22, ["365 decisions.", "All made before the result", "was visible."], 0),
        (0.44, ["Prepared for luxury."], 1), (0.63, ["The preparation", "was the mechanism."], 0),
        (0.82, ["2,000 pieces.", "The archive is the argument."], 0), (0.96, ["Watch this."], 2),
    ]

    private static func build() -> [Curve] {
        var R = HeroRNG(a: 0x20190401)
        var out: [Curve] = []
        let law = -Double.pi * 0.14
        for i in 0..<total {
            let t = Double(i) / Double(total), order = pow(t, 2.4)
            let raw = (R.next() - 0.5) * .pi * 2
            let angle = raw + (law - raw) * order * 0.72
            let margin = 0.06 + 0.08 * order
            let x0 = margin + R.next() * (1 - 2 * margin), y0 = margin + R.next() * (1 - 2 * margin)
            let len = 0.38 + R.next() * 0.44
            let x1 = clamp01(x0 + cos(angle) * len), y1 = clamp01(y0 + sin(angle) * len)
            let px = -sin(angle), py = cos(angle)
            let sign: Double = R.next() > 0.5 ? 1 : -1
            let chaos = 1 - order * 0.65
            let bulge = sign * (0.06 + R.next() * 0.3 * chaos)
            let alpha = 0.055 + 0.17 * t + R.next() * 0.07
            let width = 0.35 + 1.2 * (t + R.next() * 0.3) * 0.8 + 0.25 * R.next()
            out.append(Curve(x0: x0, y0: y0, c1x: x0 + cos(angle) * len * 0.3 + px * bulge, c1y: y0 + sin(angle) * len * 0.3 + py * bulge,
                             c2x: x1 - cos(angle) * len * 0.3 + px * bulge * 0.55, c2y: y1 - sin(angle) * len * 0.3 + py * bulge * 0.55, x1: x1, y1: y1, alpha: alpha, width: width))
        }
        return out
    }

    var body: some View {
        let progress = prog
        return ZStack {
            obsidian.ignoresSafeArea()
            Canvas { gc, size in
                if state.curves.isEmpty { state.curves = Self.build() }
                let remade = bitmap.ensure(size, scale: displayScale, ground: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
                if remade { state.drawn = 0 }
                guard let c = bitmap.ctx else { return }
                let target = min(Self.total, Int(progress * Double(Self.total)))
                func stroke(_ k: Curve) {
                    c.setStrokeColor(CGColor(srgbRed: 201 / 255, green: 168 / 255, blue: 76 / 255, alpha: k.alpha)); c.setLineWidth(k.width)
                    c.move(to: CGPoint(x: k.x0 * size.width, y: k.y0 * size.height))
                    c.addCurve(to: CGPoint(x: k.x1 * size.width, y: k.y1 * size.height), control1: CGPoint(x: k.c1x * size.width, y: k.c1y * size.height), control2: CGPoint(x: k.c2x * size.width, y: k.c2y * size.height))
                    c.strokePath()
                }
                if target > state.drawn { for i in state.drawn..<target { stroke(state.curves[i]) }; state.drawn = target }
                else if target < state.drawn - 8 { c.clear(CGRect(origin: .zero, size: size)); for i in 0..<target { stroke(state.curves[i]) }; state.drawn = target }
                if let img = bitmap.image() { gc.draw(Image(decorative: img, scale: displayScale), in: CGRect(origin: .zero, size: size)) }
                // the first curve glows alone
                if state.drawn == 1 {
                    var g = gc; g.addFilter(.blur(radius: 5)); g.opacity = 0.45
                    let k = state.curves[0]
                    var p = Path(); p.move(to: CGPoint(x: k.x0 * size.width, y: k.y0 * size.height))
                    p.addCurve(to: CGPoint(x: k.x1 * size.width, y: k.y1 * size.height), control1: CGPoint(x: k.c1x * size.width, y: k.c1y * size.height), control2: CGPoint(x: k.c2x * size.width, y: k.c2y * size.height))
                    g.stroke(p, with: .color(PLG.gold), lineWidth: k.width)
                }
            }
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .top) {
                        Color.clear.frame(height: geo.size.height * 5)
                        ForEach(beats.indices, id: \.self) { i in
                            BeatView(lines: beats[i].lines, size: beats[i].size).frame(width: geo.size.width, height: geo.size.height)
                                .offset(y: beats[i].at * geo.size.height * 5)
                        }
                    }
                }
                .onScrollGeometryChange(for: Double.self) { g in Double(g.contentOffset.y / max(1, g.contentSize.height - g.containerSize.height)) } action: { _, v in prog = clamp01(v) }
            }
        }
    }

    /// One beat: rises into place and fades in when it is mostly on screen.
    private struct BeatView: View {
        let lines: [String]; let size: Int
        @State private var shown = false
        var body: some View {
            VStack(spacing: 6) {
                ForEach(lines, id: \.self) { l in
                    Text(l).plHand(size == 2 ? 50 : size == 1 ? 36 : 24, relativeTo: size == 2 ? .largeTitle : .title2)
                        .foregroundStyle(size == 2 ? Color(hex: 0xd4b86a) : PLG.gold.opacity(0.85)).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 30).frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 22)
            .onScrollVisibilityChange(threshold: 0.45) { v in withAnimation(.timingCurve(0.2, 0.1, 0.2, 1, duration: 1.4)) { shown = v } }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Hand: type, rendered in his hands

struct LabHandView: View {
    @State private var text = "Prepared for luxury."
    @State private var face = 0              // 0 his hand, 1 ledger
    @State private var seed = Double(Int.random(in: 0..<1_000_000_000))
    @State private var wobble = 4.0
    @State private var speed = 5.0
    @State private var shown = Int.max
    @State private var writer: Task<Void, Never>?
    @FocusState private var focus: Bool

    private func rnd(_ i: Int) -> Double { let x = sin(seed + Double(i) * 127.1) * 43758.5453; return x - floor(x) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hand, live").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.7).textCase(.uppercase).foregroundStyle(Color(hex: 0x8a8576)).padding(.top, 4)
                stage
                TextEditor(text: $text).focused($focus).scrollContentBackground(.hidden).font(.system(size: 16)).foregroundStyle(Color(hex: 0xefe9dc))
                    .frame(minHeight: 90).padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x12100b))).overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x2a2618), lineWidth: 1) }
                    .accessibilityLabel("Type here").onChange(of: text) { _, _ in shown = Int.max }
                LabWrap(spacing: 8) {
                    pill("My hand", face == 0) { face = 0 }
                    pill("Ledger", face == 1) { face = 1 }
                    pill("Write it", false) { write() }
                    pill("Re-roll", false) { seed = Double(Int.random(in: 0..<1_000_000_000)); shown = Int.max }
                }
                slider("Wobble", $wobble)
                slider("Speed", $speed)
                Text("Your original hand is the main face (capitals only). Ledger is the notebook hand cut from your pages. Ransom (the scrap-letter face) is left off: it froze the browser here, so it stays out.")
                    .font(.caption).foregroundStyle(Color(hex: 0x8a8576)).padding(.top, 6)
            }
            .padding(16).padding(.top, 40)
        }
        .background(Color(hex: 0x0e0c08))
        .scrollDismissesKeyboard(.interactively)
        .onAppear { write() }
        .onDisappear { writer?.cancel() }
    }

    private var stage: some View {
        let fontName = face == 0 ? PLFace.handV1 : PLFace.ledger
        let size: CGFloat = 40
        let w = wobble / 10
        let lines = text.isEmpty ? [" "] : text.components(separatedBy: "\n")
        var index = 0
        var built: [(Int, [[(Int, Character)]])] = []
        for (li, line) in lines.enumerated() {
            var words: [[(Int, Character)]] = [[]]
            for ch in line {
                if ch == " " { words.append([]) } else { words[words.count - 1].append((index, ch)) }
                index += 1
            }
            index += 1
            built.append((li, words))
        }
        return VStack(spacing: 4) {
            ForEach(built, id: \.0) { _, words in
                LabWrap(spacing: 0, centered: true) {
                    ForEach(words.indices, id: \.self) { wi in
                        HStack(spacing: 0) {
                            ForEach(words[wi], id: \.0) { i, ch in
                                Text(String(ch)).font(.custom(fontName, size: size))
                                    .foregroundStyle(Color(hex: 0xefe9dc))
                                    .scaleEffect(1 + (rnd(i + 19) - 0.5) * 0.1 * w)
                                    .rotationEffect(.degrees((rnd(i + 9) - 0.5) * 10 * w))
                                    .offset(y: CGFloat((rnd(i) - 0.5) * 0.16 * w) * size)
                                    .padding(.trailing, CGFloat((rnd(i + 29) - 0.5) * 0.06 * w) * size)
                                    .opacity(i < shown ? 1 : 0)
                            }
                        }
                        .padding(.trailing, wi < words.count - 1 ? size * 0.3 : 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260).padding(.horizontal, 18).padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x12100b)))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x2a2618), lineWidth: 1) }
        .accessibilityElement(children: .ignore).accessibilityLabel(text)
    }

    private func write() {
        writer?.cancel()
        let count = text.count
        guard !UIAccessibility.isReduceMotionEnabled else { shown = Int.max; return }
        shown = 0
        writer = Task {
            var k = 0
            while k <= count + 1, !Task.isCancelled {
                shown = k; k += 1
                try? await Task.sleep(for: .milliseconds(Int((11 - speed) * 28)))
            }
            shown = Int.max
        }
    }

    private func pill(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(0.7).textCase(.uppercase)
                .foregroundStyle(on ? Color(hex: 0x0e0c08) : Color(hex: 0x8a8576)).padding(.horizontal, 14).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? PLG.gold : .clear))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(on ? PLG.gold : Color(hex: 0x2a2618), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
    private func slider(_ t: String, _ v: Binding<Double>) -> some View {
        HStack { Text(t).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(hex: 0x8a8576)).frame(width: 64, alignment: .leading)
            Slider(value: v, in: t == "Wobble" ? 0...10 : 1...10, step: 1).tint(PLG.gold) }
    }
}

// MARK: - Components: the house's reusable pieces, live

/// A glass surface border that crawls with fractal noise: Canvas, no backdrop dependency (components/ElectricBorder.tsx).
struct LabElectricBorder: View {
    var radius: CGFloat = 14
    var color = Color(red: 201 / 255, green: 168 / 255, blue: 76 / 255).opacity(0.55)
    var width: CGFloat = 1.4
    var jitter: Double = 2.2
    var speed: Double = 0.0006
    var inset: CGFloat = 2
    @State private var seed = Double.random(in: 0..<1000)
    @State private var start = Date()

    private func hash(_ x: Double, _ y: Double) -> Double { let s = sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453123; return s - floor(s) }
    private func vnoise(_ x: Double, _ y: Double) -> Double {
        let x0 = floor(x), y0 = floor(y), fx = x - x0, fy = y - y0
        let a = hash(x0, y0), b = hash(x0 + 1, y0), c = hash(x0, y0 + 1), d = hash(x0 + 1, y0 + 1)
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }
    private func fractal(_ x: Double, _ y: Double) -> Double {
        var amp = 1.0, freq = 1.0, sum = 0.0, norm = 0.0
        for _ in 0..<3 { sum += amp * vnoise(x * freq, y * freq); norm += amp; amp *= 0.55; freq *= 2.1 }
        return sum / norm
    }
    /// Position, outward normal and a 0...1 run along the perimeter of a rounded rect, at arc length `s`.
    private func point(_ s: Double, _ w: Double, _ h: Double, _ r: Double) -> (x: Double, y: Double, ox: Double, oy: Double, n: Double) {
        let sx = w - 2 * r, sy = h - 2 * r, arc = .pi / 2 * r
        let segs = [sx, arc, sy, arc, sx, arc, sy, arc]
        let perim = 2 * sx + 2 * sy + 4 * arc
        var acc = 0.0
        for i in 0..<8 where s <= acc + segs[i] || i == 7 {
            let l = s - acc, a = arc > 0 ? l / arc * .pi / 2 : 0, n = s / perim
            switch i {
            case 0: return (r + l, 0, 0, -1, n)
            case 1: return (w - r + r * sin(a), r - r * cos(a), sin(a), -cos(a), n)
            case 2: return (w, r + l, 1, 0, n)
            case 3: return (w - r + r * cos(a), h - r + r * sin(a), cos(a), sin(a), n)
            case 4: return (w - r - l, h, 0, 1, n)
            case 5: return (r - r * sin(a), h - r + r * cos(a), -sin(a), cos(a), n)
            case 6: return (0, h - r - l, -1, 0, n)
            default: return (r - r * cos(a), r - r * sin(a), -cos(a), -sin(a), n)
            }
        }
        return (0, 0, 0, -1, 0)
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { gc, size in
                let t = tl.date.timeIntervalSince(start) * 1000
                let iw = max(0, Double(size.width - 2 * inset)), ih = max(0, Double(size.height - 2 * inset)), ir = max(0, Double(radius - inset))
                let perim = 2 * (iw - 2 * ir) + 2 * (ih - 2 * ir) + 4 * (.pi / 2) * ir
                var p = Path()
                for i in 0...96 {
                    let pt = point(Double(i) / 96 * perim, iw, ih, ir)
                    let n = fractal(pt.n * 3, t * speed) - 0.5
                    let x = pt.x + Double(inset) + pt.ox * n * jitter, y = pt.y + Double(inset) + pt.oy * n * jitter
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                p.closeSubpath()
                gc.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private let prismSource = """
static inline float p_hash(float2 p) { return fract(sin(dot(p, float2(41.3, 289.1))) * 43758.5453); }
static inline float p_noise(float2 p) {
    float2 i = floor(p); float2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    float a = p_hash(i); float b = p_hash(i + float2(1.0, 0.0)); float c = p_hash(i + float2(0.0, 1.0)); float d = p_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
static inline float p_fbm(float2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * p_noise(p); p = p * 2.03 + float2(1.7); a *= 0.5; } return v; }
static inline float p_caustic(float2 uv, float t) {
    float2 w = float2(p_fbm(uv * 2.2 + t * 0.3), p_fbm(uv * 2.2 - t * 0.25 + 4.1));
    return p_fbm(uv * 2.2 + w * 2.2 + t * 0.15);
}
fragment float4 fs_prism(VOut in [[stage_in]], constant float *U [[buffer(0)]]) {
    float2 res = float2(U[1], U[2]);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    uv.x *= res.x / res.y;
    float t = U[0] * 0.2;
    float3 bg = float3(0.051, 0.043, 0.027); float3 gold = float3(0.788, 0.659, 0.298); float3 ink = float3(0.102, 0.082, 0.063);
    float base = p_caustic(uv, t);
    float g = smoothstep(0.32, 0.68, base);
    float3 col = mix(bg, gold * 1.15, g);
    col = mix(col, ink, smoothstep(0.0, 0.18, base) * 0.55);
    float off = 0.006;
    float edge = p_caustic(uv + float2(off, 0.0), t) - p_caustic(uv - float2(off, 0.0), t);
    col += float3(1.0, 0.0, -1.0) * edge * 1.4;
    float d = abs(fract((uv.x + uv.y) * 0.55 - t * 0.3) - 0.5);
    float sweep = pow(max(0.0, 1.0 - d * 7.0), 3.0);
    col += float3(1.0) * sweep * 0.5;
    return float4(col, 1.0);
}
"""

struct LabComponentsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var prism = LabFragmentScene(key: "prism", source: prismSource, fragment: "fs_prism", still: labReduceMotion() ? 3 : nil)
    @State private var curvedName: String?
    private let model = AppModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("House Components").gTitle(28, relativeTo: .title).foregroundStyle(PLG.ink(scheme))
                Text("The reusable UI pieces from the repos, each one live. Linked from the Vault's UI Components shelf.").font(.footnote).foregroundStyle(PLG.dim(scheme)).padding(.top, 6).padding(.bottom, 30)
                section("ElectricBorder", "components/ElectricBorder.tsx · Canvas2D fractal-noise border · shipped S138, wired into 15 glass-card sites") {
                    Text("A living border — fractal noise crawling the perimeter. No backdrop-filter dependency, safe on iOS Safari.").font(.system(size: 16, design: .serif).italic())
                        .foregroundStyle(PLG.ink(scheme)).gCard(padding: 28, radius: 14).overlay { LabElectricBorder(radius: 14) }
                }
                section("Liquid Glass — The Prism", "public/scripts/pieces.js · shaderPiece 'prism' · GLSL fbm caustics + chromatic aberration · S138") {
                    Group { if let prism { LabMetalView(scene: prism) } else { LabGPUMissing() } }
                        .aspectRatio(2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    openPiece("open The Prism in the library", "prism")
                }
                section("Glass Card", "app/globals.css · .glass-card — the house glass surface (pl-os token language)") {
                    Text("The standard glass surface every panel in the inner tongue sits on.").font(.system(size: 16, design: .serif).italic()).foregroundStyle(PLG.ink(scheme)).gCard(padding: 28, radius: 14)
                }
                section("Countdown, Ten Down", "public/scripts/pieces-s305b.js · piece s5b-motion-count · the count is the preparation and the last word is the proof") {
                    openPiece("open Ten Down in the library", "s5b-motion-count")
                }
                section("Countdown, Five Down", "public/scripts/pieces-s305b.js · piece s5b-qm-count · each number turns over into the one that is left") {
                    openPiece("open Five Down in the library", "s5b-qm-count")
                }
                section("Type — the founder's hands", "public/fonts · MaurriceMccannPsychedHandwrit (PLHand) + Curvedabc — both founder-drawn") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Watch this.").font(.custom(PLFace.handV1, size: 34)).foregroundStyle(PLG.ink(scheme))
                        Text("PLHand — the handwriting").font(.system(size: 10, design: .monospaced)).foregroundStyle(PLG.dim(scheme))
                    }.gCard(padding: 28, radius: 14).padding(.bottom, 12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prepared for luxury").font(curvedName.map { Font.custom($0, size: 30) } ?? Font.system(size: 30, design: .serif).italic()).foregroundStyle(PLG.ink(scheme))
                        Text("Curvedabc — the curved letterforms").font(.system(size: 10, design: .monospaced)).foregroundStyle(PLG.dim(scheme))
                    }.gCard(padding: 28, radius: 14)
                }
            }
            .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 80)
        }
        .background { GalleryGround() }
        .task { curvedName = await LabFonts.curved(model: model) }
    }

    private func section<C: View>(_ title: String, _ source: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).gEyebrow(13).foregroundStyle(PLG.ink(scheme)).padding(.bottom, 4)
            Text(source).font(.system(size: 10, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).padding(.bottom, 14)
            content()
        }
        .padding(.bottom, 40)
    }

    private func openPiece(_ label: String, _ id: String) -> some View {
        NavigationLink { LabPieceFull(model: model, id: id) } label: {
            Text("\(label) →").font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.goldDim(scheme)).padding(.top, 10).frame(minHeight: 44, alignment: .leading)
        }
    }
}

/// One code piece full screen (the "open in the library" links), on the code-art runtime.
struct LabPieceFull: View {
    let model: AppModel
    let id: String
    var body: some View {
        LivePieceCard(model: model, pieceID: id, thumb: nil).ignoresSafeArea().navigationTitle(id).navigationBarTitleDisplayMode(.inline)
    }
}

/// His Curvedabc face: fetched once from the gallery (a public design asset) and registered for the process.
enum LabFonts {
    @MainActor static func curved(model: AppModel) async -> String? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LabFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Curvedabc-Regular.ttf")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "fonts/Curvedabc-Regular.ttf"), timeout: 40) else { return nil }
            try? d.write(to: url)
        }
        guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider), let name = font.postScriptName as String? else { return nil }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return name
    }
}
