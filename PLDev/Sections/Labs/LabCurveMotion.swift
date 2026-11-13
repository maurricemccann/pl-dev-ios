import SwiftUI
import UIKit
import simd

// The curve in motion (living-curves-art/index.html), native: six live pieces on one dark page.
// 01 Cloth art and 03 Red cloth: p5 brush strokes (Canvas, Catmull-Rom like p5's curveVertex).
// 02 3D curve engine and 04 Matrix code spine: three.js tubes, projected by a small camera into a Canvas (the geometry is rebuilt
//    every frame on the web too; a tube here is round-capped strokes whose width follows depth, with the page's outline, halo and glow).
// 05 Matrix TV: p5 rain on a bitmap that keeps its trails. 06 Ascension lite: the organisms, portals and palettes, with p5's own noise.

// MARK: - Page

struct LabCurveMotionView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var live: Set<Int> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VStack(spacing: 18) {
                    Text("Psyched Luxuries · Living Archive").gEyebrow(9).foregroundStyle(PLG.gold.opacity(0.5))
                    Text("The Curve in Motion").font(.system(size: 40, design: .serif).italic()).foregroundStyle(Color(hex: 0xf5eed8)).multilineTextAlignment(.center)
                    Text("Seven years rendered in real time").gEyebrow(11).foregroundStyle(PLG.gold.opacity(0.4)).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 44).frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)

                section(1, "01 — Cloth Art", height: 460) { p in CMClothCanvas(red: false, paused: p) }
                section(2, "02 — 3D Curve Engine", height: 520, label: "Psyched Luxuries — 3D Curve Engine") { p in CMTubeCanvas(matrix: false, paused: p) }
                section(3, "03 — Red Cloth", height: 460) { p in CMClothCanvas(red: true, paused: p) }
                section(4, "04 — Matrix Code Spine", height: 520, label: "Matrix Code Spine — Flipped Origin", labelTint: Color(red: 0, green: 1, blue: 70 / 255).opacity(0.22)) { p in CMTubeCanvas(matrix: true, paused: p) }
                section(5, "05 — Matrix TV", height: 260) { p in CMMatrixTV(paused: p) }
                section(6, "06 — Ascension Lite", height: 520) { p in CMAscensionCanvas(paused: p) }

                VStack(spacing: 14) {
                    Text("Est. April 2019 · Decide → Persist → Obtain").gEyebrow(9).foregroundStyle(PLG.gold.opacity(0.3)).multilineTextAlignment(.center)
                }
                .padding(.vertical, 48).frame(maxWidth: .infinity)
                .overlay(alignment: .top) { Rectangle().fill(PLG.gold.opacity(0.15)).frame(height: 0.5) }
            }
        }
        .background(Color(hex: 0x0a0a0a))
        .scrollIndicators(.hidden)
        .accessibilityLabel("The curve in motion. Six live pieces.")
    }

    /// A numbered label and a glass card holding one piece; the piece runs only while it is on screen.
    private func section<C: View>(_ n: Int, _ title: String, height: CGFloat, label: String? = nil, labelTint: Color = PLG.gold.opacity(0.25),
                                  @ViewBuilder _ piece: @escaping (Bool) -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).gEyebrow(9).foregroundStyle(PLG.gold.opacity(0.3)).padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
            piece(!live.contains(n))
                .frame(height: height)
                .overlay(alignment: .bottom) {
                    if let label { Text(label).gEyebrow(9).foregroundStyle(labelTint).multilineTextAlignment(.center).padding(.bottom, 26).allowsHitTesting(false) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1) }
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                .padding(.horizontal, 16).padding(.bottom, 32)
                .onScrollVisibilityChange(threshold: 0.05) { v in if v { live.insert(n) } else { live.remove(n) } }
        }
    }
}

private func cmRGB(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 255) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a / 255) }

/// p5's curveVertex: a Catmull-Rom spline through every vertex, the first and last only steering. Needs four points, like p5.
private func cmSpline(_ v: [CGPoint]) -> Path? {
    guard v.count >= 4 else { return nil }
    var p = Path()
    p.move(to: v[1])
    for i in 1..<(v.count - 2) {
        let p0 = v[i - 1], p1 = v[i], p2 = v[i + 1], p3 = v[i + 2]
        p.addCurve(to: p2,
                   control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                   control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
    }
    return p
}

// MARK: - 01 and 03: cloth

private final class CMCloth: @unchecked Sendable {
    struct Pt { var x: Double; var y: Double; var gap: Bool }
    final class Stroke {
        var pts: [Pt] = []
        let dir: Int
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var speed: Double, phase: Double, thickness: Double
        var gapPre = 0, gapPost = 0
        init(dir: Int, speed: Double, phase: Double, thickness: Double) { self.dir = dir; self.speed = speed; self.phase = phase; self.thickness = thickness }
    }

    let red: Bool
    var rng = HeroRNG(a: UInt32.random(in: 1...UInt32.max))
    var size: CGSize = .zero
    var strokes: [Stroke] = []
    var frame = 0
    private var off: Double { red ? 400 : 200 }
    private var maxPts: Int { red ? 900 : 300 }
    private var bound: Double { red ? 600 : 300 }

    init(red: Bool) { self.red = red }

    private func rand(_ a: Double, _ b: Double) -> Double { a + rng.next() * (b - a) }

    func ensure(_ s: CGSize) {
        if s.width < 20 || s.height < 20 || (abs(s.width - size.width) < 1 && abs(s.height - size.height) < 1 && !strokes.isEmpty) { return }
        size = s
        strokes = (0..<4).map { d -> Stroke in
            let st = Stroke(dir: d, speed: rand(2.0, 3.5), phase: rand(0, 1000), thickness: red ? rand(55, 95) : rand(40, 70))
            place(st, fresh: true)
            return st
        }
    }

    private func place(_ s: Stroke, fresh: Bool) {
        let w = Double(size.width), h = Double(size.height)
        switch s.dir {
        case 0: s.x = -off; s.y = rand(h * 0.2, h * 0.8); if fresh { s.vx = s.speed; s.vy = rand(-0.4, 0.4) }
        case 1: s.x = w + off; s.y = rand(h * 0.2, h * 0.8); if fresh { s.vx = -s.speed; s.vy = rand(-0.4, 0.4) }
        case 2: s.x = -off; s.y = -off; if fresh { s.vx = s.speed; s.vy = s.speed * 0.8 }
        default: s.x = -off; s.y = h + off; if fresh { s.vx = s.speed; s.vy = -s.speed * 0.8 }
        }
    }

    func tick() {
        frame += 1
        let f = Double(frame)
        let w = Double(size.width), h = Double(size.height)
        for s in strokes {
            for o in strokes where o !== s {                      // checkIntersections: a gap where two cross
                guard let last = o.pts.last else { continue }
                let dx = s.x - last.x, dy = s.y - last.y
                if dx * dx + dy * dy < 900 { s.gapPre = 6; s.gapPost = 16 }
            }
            let drift = sin(f * 0.01 + s.phase) * 1.2, pulse = sin(f * 0.02 + s.phase) * 1.8
            s.x += s.vx; s.y += s.vy + drift + pulse
            var gap = false
            if s.gapPre > 0 { gap = true; s.gapPre -= 1 } else if s.gapPost > 0 { gap = true; s.gapPost -= 1 }
            s.pts.append(Pt(x: s.x, y: s.y, gap: gap))
            if s.pts.count > maxPts { s.pts.removeFirst() }
            if s.x < -bound || s.x > w + bound || s.y < -bound || s.y > h + bound { s.pts = []; s.phase = rand(0, 1000); place(s, fresh: false) }
        }
    }

    func draw(_ gc: inout GraphicsContext) {
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red ? .black : cmRGB(253, 247, 242)))
        for s in strokes where s.pts.count >= 3 {
            let line = StrokeStyle(lineWidth: 1, lineCap: red ? .square : .round, lineJoin: red ? .miter : .round)
            var vs: [CGPoint] = []
            var t = 0.5
            for i in 1..<s.pts.count {
                let pt = s.pts[i], prev = s.pts[i - 1]
                if pt.gap { continue }
                let dx = pt.x - prev.x, dy = pt.y - prev.y
                let mag = max(sqrt(dx * dx + dy * dy), 1e-9)
                t = (-dy / mag + 1) * 0.5          // p5 keeps the stroke colour of the last vertex for the whole shape
                vs.append(CGPoint(x: pt.x, y: pt.y))
            }
            guard let path = cmSpline(vs) else { continue }
            var st = line
            st.lineWidth = s.thickness + (red ? 20 : 10)
            gc.stroke(path, with: .color(.black), style: st)
            st.lineWidth = s.thickness
            let c = red ? mix((180, 20, 20), (255, 60, 60), t) : mix((199, 90, 27), (164, 106, 63), t)   // burnt to bronze, or the two reds
            gc.stroke(path, with: .color(c), style: st)
            if red {
                var rs: [CGPoint] = []
                for i in 2..<s.pts.count {
                    let pt = s.pts[i], prev = s.pts[i - 1]
                    if pt.gap { continue }
                    let dx = pt.x - prev.x, dy = pt.y - prev.y
                    let mag = max(sqrt(dx * dx + dy * dy), 1e-9)
                    let nx = -dy / mag, ny = dx / mag
                    let off = s.thickness * 0.15 + sin(Double(i) * 0.1 + s.phase) * (s.thickness * 0.05)
                    rs.append(CGPoint(x: pt.x + nx * off, y: pt.y + ny * off))
                }
                if let rp = cmSpline(rs) {
                    st.lineWidth = s.thickness * 0.25
                    gc.stroke(rp, with: .color(cmRGB(255, 150, 150, 180)), style: st)
                }
            }
        }
    }

    private func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        cmRGB(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
}

private struct CMClothCanvas: View {
    let red: Bool
    let paused: Bool
    @State private var sim: CMCloth
    @State private var clock = LabFrameClock()
    init(red: Bool, paused: Bool) { self.red = red; self.paused = paused; _sim = State(initialValue: CMCloth(red: red)) }

    var body: some View {
        TimelineView(.animation(paused: paused)) { tl in
            Canvas { gc, size in
                sim.ensure(size)
                for _ in 0..<clock.due(tl.date) { sim.tick() }
                sim.draw(&gc)
            }
        }
        .drawingGroup()
        .accessibilityLabel(red ? "Red cloth: brush strokes crossing on black" : "Cloth art: brush strokes crossing on cream")
    }
}

// MARK: - 02 and 04: the tube scenes

private final class CMTubes: @unchecked Sendable {
    struct Cur {
        var pts: [SIMD3<Float>]
        var base: [SIMD3<Float>]
        var behavior: Int          // 0 swirl, 1 pulse, 2 tilt (engine) / weave (matrix), 3 drift
        var nextSwitch: Double
        var seed: Float
        var color: SIMD3<Double>   // 0...255
        var glyphs: [Glyph]
    }
    struct Glyph { var t: Float; var speed: Float; var offset: Float; var ch: Int }

    let matrix: Bool
    var rng = HeroRNG(a: UInt32.random(in: 1...UInt32.max))
    var curves: [Cur] = []
    var started: Date?
    var time = 0.0
    static let chars = Array("01{}[]()<>/\\=+*;:!%$#@&|.,-?_0123456789abcdef")
    static let sizes: [CGFloat] = [6, 9, 13, 18, 25]

    init(matrix: Bool) {
        self.matrix = matrix
        let cols: [SIMD3<Double>] = matrix ? [[0, 255, 70], [15, 175, 75], [0, 194, 138]] : [[201, 168, 76], [44, 109, 229], [229, 122, 44]]
        for i in 0..<3 {
            var pts: [SIMD3<Float>]
            var seed: Float = 0
            if matrix {
                seed = Float(i) * 1.37 + Float(rng.next()) * 2
                pts = (0..<9).map { k -> SIMD3<Float> in
                    let z = 7 - Float(k) / 8 * 13
                    let x = sin(Float(k) * 0.9 + seed) * (0.6 + cos(seed * 0.7) * 0.4) + Float(rng.next()) * 0.2 - 0.1
                    let y = cos(Float(k) * 0.6 - seed * 0.5) * (0.6 + sin(seed * 0.5) * 0.3) + Float(rng.next()) * 0.15 - 0.075
                    return [x, y, z]
                }
            } else {
                pts = [[-2.0, 0.0, -6], [-0.8, 0.8, -3], [0.2, 0.3, -1], [1.0, -0.4, 1], [0.4, 0.0, 3], [-0.3, 0.5, 5], [0.0, 0.0, 7]]
            }
            var glyphs: [Glyph] = []
            if matrix {
                let steps = 46, rings = 6          // the page lays 140 x 8; this keeps the same rings on a phone's budget
                for s in 0..<steps { for r in 0..<rings {
                    glyphs.append(Glyph(t: Float(s) / Float(steps - 1), speed: -(0.0006 + Float(s % 7) * 0.00005), offset: Float(r) / Float(rings) * 2 * .pi, ch: (s * rings + r) % Self.chars.count))
                } }
            }
            curves.append(Cur(pts: pts, base: pts, behavior: 0, nextSwitch: 2 + rng.next() * 3, seed: seed, color: cols[i], glyphs: glyphs))
        }
    }

    func tick(_ t: Double) {
        time = t
        for ci in curves.indices {
            if t > curves[ci].nextSwitch { curves[ci].behavior = Int(rng.next() * 4) % 4; curves[ci].nextSwitch = t + 2 + rng.next() * 3 }
            let c = curves[ci]
            let n = c.pts.count
            let tf = Float(t)
            for i in 0..<n {
                let u = Float(i) / Float(n - 1), base: Float = (i == 0 || i == n - 1) ? 0 : 1
                var dx: Float = 0, dy: Float = 0, dz: Float = 0
                let s = c.seed
                if matrix {
                    switch c.behavior {
                    case 0: dx = sin(tf * 0.9 + u * 5 + s) * 0.55 * base; dz = cos(tf * 0.9 + u * 5 + s) * 0.55 * base
                    case 1: let p = sin(tf * 1.6 + u * 3.5 + s) * 0.45 * base; dx = p * 0.35; dy = p * 0.65
                    case 2: dx = sin(tf * 0.6 + u * 6 + s * 0.7) * 0.35 * base; dy = cos(tf * 0.7 + u * 4 + s * 0.9) * 0.35 * base; dz = sin(tf * 0.5 + u * 3 + s * 0.5) * 0.25 * base
                    default: dx = sin(tf * 0.28 + u * 2.2 + s) * 0.28 * base; dz = sin(tf * 0.28 + u * 3.1 + s * 1.1) * 0.28 * base
                    }
                    dx += (c.base[i].x - c.pts[i].x) * 0.02
                } else {
                    switch c.behavior {
                    case 0: dx = sin(tf * 0.8 + u * 4) * 0.6 * base; dz = cos(tf * 0.8 + u * 4) * 0.6 * base
                    case 1: let p = sin(tf * 1.4 + u * 3) * 0.5 * base; dx = p * 0.4; dy = p * 0.6
                    case 2: dy = sin(tf * 0.9 + u * 5) * 0.7 * base
                    default: dx = sin(tf * 0.3 + u * 2) * 0.4 * base; dz = sin(tf * 0.3 + u * 3) * 0.4 * base
                    }
                    dx += (c.base[i].x - c.pts[i].x) * 0.015
                }
                curves[ci].pts[i] += SIMD3<Float>(dx, dy, dz) * 0.02
            }
            for g in curves[ci].glyphs.indices where matrix {
                var tt = curves[ci].glyphs[g].t + curves[ci].glyphs[g].speed
                if tt < 0 { tt += 1 }; if tt > 1 { tt -= 1 }
                curves[ci].glyphs[g].t = tt
            }
        }
    }

    // MARK: camera

    struct Cam {
        var pos: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, fwd: SIMD3<Float>, focal: Float, cx: Float, cy: Float
        func project(_ p: SIMD3<Float>) -> (pt: CGPoint, depth: Float) {
            let v = p - pos
            let z = max(0.25, simd_dot(v, fwd))
            return (CGPoint(x: CGFloat(cx + simd_dot(v, right) / z * focal), y: CGFloat(cy - simd_dot(v, up) / z * focal)), z)
        }
    }

    func camera(_ size: CGSize) -> Cam {
        let t = Float(time)
        let pos: SIMD3<Float> = matrix ? [sin(t * 0.16) * 0.8, 1.6 + sin(t * 0.2) * 0.28, 8 + sin(t * 0.07) * 0.25] : [sin(t * 0.18) * 0.7, 1.6 + sin(t * 0.22) * 0.25, 8]
        let fwd = simd_normalize(SIMD3<Float>(0, 0.4, 0) - pos)
        let right = simd_normalize(simd_cross(fwd, [0, 1, 0]))
        let up = simd_cross(right, fwd)
        // the page is wide; on a phone the same vertical field of view keeps the whole curve in frame
        let focal = Float(size.height) / 2 / tan(Float(48 * Double.pi / 180) / 2) * 0.82
        return Cam(pos: pos, right: right, up: up, fwd: fwd, focal: focal, cx: Float(size.width) / 2, cy: Float(size.height) / 2)
    }

    // MARK: draw

    func draw(_ gc: inout GraphicsContext, _ size: CGSize) {
        let bg = matrix ? cmRGB(15, 20, 22) : cmRGB(10, 10, 10)
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
        let cam = camera(size)
        let fogK: Float = 0.035
        func fog(_ d: Float) -> Double { let q = d * fogK; return Double(exp(-q * q)) }   // FogExp2

        // glyph faces, resolved once a frame at five sizes
        var faces: [[GraphicsContext.ResolvedText]] = []
        if matrix {
            faces = Self.sizes.map { sz in
                Self.chars.map { ch in gc.resolve(Text(String(ch)).font(.system(size: sz, design: .monospaced)).foregroundStyle(cmRGB(0, 255, 70))) }
            }
        }

        // far curve first
        let order = curves.indices.sorted { a, b in
            cam.project(LabTube.point(curves[a].pts, 0.5)).depth > cam.project(LabTube.point(curves[b].pts, 0.5)).depth
        }
        for ci in order {
            let c = curves[ci]
            let seg = 56
            let samples = (0...seg).map { LabTube.point(c.pts, Float($0) / Float(seg)) }
            let proj = samples.map { cam.project($0) }
            let radius: Float = matrix ? 0.32 : 0.28
            let col = c.color
            let haloCol = matrix ? col : SIMD3<Double>(201, 168, 76)
            let haloA = matrix ? 0.10 : 0.12, glowA = matrix ? 0.06 : 0.05
            for s in 0..<seg {
                let a = proj[s], b = proj[s + 1]
                let d = (a.depth + b.depth) / 2
                let px = CGFloat(cam.focal / d)
                let f = fog(d)
                var p = Path(); p.move(to: a.pt); p.addLine(to: b.pt)
                func pass(_ r: Float, _ rgb: SIMD3<Double>, _ alpha: Double) {
                    gc.stroke(p, with: .color(cmRGB(rgb.x, rgb.y, rgb.z, 255 * alpha * f)), style: StrokeStyle(lineWidth: max(0.6, CGFloat(r) * 2 * px), lineCap: .round))
                }
                pass(matrix ? 0.52 : 0.46, haloCol, haloA)
                pass(matrix ? 0.44 : 0.40, col, glowA)
                pass(matrix ? 0.36 : 0.34, [0, 0, 0], 1)
                pass(radius, col * 0.55 + SIMD3<Double>(repeating: 8), 1)     // the lit body: emissive 0.18 on a dark metal
                // the key light along the upper edge
                var hp = Path(); let o = CGPoint(x: -px * CGFloat(radius) * 0.32, y: -px * CGFloat(radius) * 0.38)
                hp.move(to: CGPoint(x: a.pt.x + o.x, y: a.pt.y + o.y)); hp.addLine(to: CGPoint(x: b.pt.x + o.x, y: b.pt.y + o.y))
                gc.stroke(hp, with: .color(cmRGB(min(255, col.x + 90), min(255, col.y + 90), min(255, col.z + 90), 255 * 0.55 * f)),
                          style: StrokeStyle(lineWidth: max(0.5, CGFloat(radius) * 0.7 * px), lineCap: .round))
            }
            guard matrix else { continue }

            // frames along the tube (parallel transport), then the code that wraps and slides along it
            var prevN = SIMD3<Float>(0, 0, 1)
            var normals: [SIMD3<Float>] = [], binormals: [SIMD3<Float>] = []
            for s in 0...seg {
                let ahead = samples[min(seg, s + 1)], behind = samples[max(0, s - 1)]
                let tan = simd_normalize(ahead - behind)
                var n = prevN - simd_dot(prevN, tan) * tan
                if simd_length(n) < 1e-4 { n = abs(tan.x) < 0.9 ? simd_cross(tan, [1, 0, 0]) : simd_cross(tan, [0, 1, 0]) }
                n = simd_normalize(n); prevN = n
                normals.append(n); binormals.append(simd_cross(tan, n))
            }
            for g in c.glyphs {
                let pos = LabTube.point(c.pts, g.t)
                let idx = min(seg, max(0, Int(g.t * Float(seg))))
                let radial = (normals[idx] * cos(g.offset) + binormals[idx] * sin(g.offset)) * 0.48
                let at = pos + radial
                let facing = simd_dot(simd_normalize(radial), simd_normalize(cam.pos - at))
                if facing < 0.05 { continue }                               // the tube hides the far side
                let pr = cam.project(at)
                guard pr.pt.x > -20, pr.pt.x < size.width + 20, pr.pt.y > -20, pr.pt.y < size.height + 20 else { continue }
                let h = 0.22 * cam.focal / pr.depth
                let k = h < 7 ? 0 : h < 11 ? 1 : h < 16 ? 2 : h < 22 ? 3 : 4
                gc.opacity = Double(min(1, facing * 1.6)) * 0.95 * fog(pr.depth)
                gc.draw(faces[k][g.ch], at: pr.pt, anchor: .center)
            }
            gc.opacity = 1
        }

        if matrix {   // the faint scan lines over the whole piece
            var lines = Path()
            var y: CGFloat = 0
            while y < size.height { lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y)); y += 3 }
            gc.stroke(lines, with: .color(.black.opacity(0.06)), lineWidth: 1)
        }
    }
}

private struct CMTubeCanvas: View {
    let matrix: Bool
    let paused: Bool
    @State private var sim: CMTubes
    @State private var clock = LabFrameClock()
    @State private var t0 = Date()
    init(matrix: Bool, paused: Bool) { self.matrix = matrix; self.paused = paused; _sim = State(initialValue: CMTubes(matrix: matrix)) }

    var body: some View {
        TimelineView(.animation(paused: paused)) { tl in
            Canvas { gc, size in
                for _ in 0..<clock.due(tl.date) { sim.tick(tl.date.timeIntervalSince(t0)) }
                if clock.frame == 0 { sim.tick(0) }
                sim.draw(&gc, size)
            }
        }
        .background(matrix ? Color(hex: 0x0f1416) : Color(hex: 0x0a0a0a))
        .accessibilityLabel(matrix ? "Matrix code spine: three green tubes wrapped in sliding code" : "3D curve engine: three tubes that swirl, pulse, tilt and drift")
    }
}

// MARK: - 05: Matrix TV

private final class CMRain: @unchecked Sendable {
    struct Stream { var x: Double; var y: Double; var speed: Double }
    var streams: [Stream] = []
    var rng = HeroRNG(a: UInt32.random(in: 1...UInt32.max))
    static let chars = Array("01{}[]<>/=+*;:!%$#@")
    static let lines = ["PERSISTENT", "THOUGHTS", "MANIFEST", "REALITY"]
    let rain = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    let big = UIFont.monospacedSystemFont(ofSize: 20, weight: .regular)

    func rand(_ a: Double, _ b: Double) -> Double { a + rng.next() * (b - a) }
    func reseed(_ s: CGSize) {
        streams = (0..<Int(s.width / 16)).map { Stream(x: Double($0) * 16, y: rand(-1500, 0), speed: rand(2, 6)) }
    }

    /// Text at a p5 baseline, in the bitmap's y-down space.
    private func text(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
        UIGraphicsPushContext(c)
        (s as NSString).draw(at: CGPoint(x: x, y: y - font.ascender), withAttributes: [.font: font, .foregroundColor: color])
        UIGraphicsPopContext()
    }

    func step(_ c: CGContext, _ size: CGSize, _ frame: Int) {
        let W = size.width, H = size.height
        c.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 30 / 255)); c.fill(CGRect(origin: .zero, size: size))
        let green = UIColor(red: 80 / 255, green: 120 / 255, blue: 80 / 255, alpha: 90 / 255)
        for i in streams.indices {
            let ch = String(Self.chars[Int(rng.next() * Double(Self.chars.count)) % Self.chars.count])
            text(c, ch, CGFloat(streams[i].x), CGFloat(streams[i].y), rain, green)
            streams[i].y += streams[i].speed
            if streams[i].y > Double(H) + 20 { streams[i].y = rand(-300, 0); streams[i].speed = rand(2, 6) }
        }
        // the four gold lines, breathing
        let cw = ("A" as NSString).size(withAttributes: [.font: big]).width
        let baseY = H * 0.35
        for (i, str) in Self.lines.enumerated() {
            let y = baseY + CGFloat(i) * 28 + CGFloat(sin(Double(frame) * 0.01 + Double(i)) * 3)
            let x = (W - cw * CGFloat(str.count)) / 2
            for (j, ch) in str.enumerated() {
                text(c, String(ch), x + CGFloat(j) * cw, y, big, UIColor(red: 1, green: 240 / 255, blue: 200 / 255, alpha: 180 / 255))
                text(c, String(ch), x + CGFloat(j) * cw + 1, y + 1, big, UIColor(red: 201 / 255, green: 168 / 255, blue: 76 / 255, alpha: 1))
            }
        }
        var scan = Path()
        var sy: CGFloat = 0
        while sy < H { scan.move(to: CGPoint(x: 0, y: sy)); scan.addLine(to: CGPoint(x: W, y: sy)); sy += 3 }
        c.setStrokeColor(CGColor(srgbRed: 201 / 255, green: 168 / 255, blue: 76 / 255, alpha: 40 / 255)); c.setLineWidth(1)
        c.addPath(scan.cgPath); c.strokePath()
    }
}

private struct CMMatrixTV: View {
    let paused: Bool
    @State private var rain = CMRain()
    var body: some View {
        LabBitmapSketch(ground: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), step: { c, size, frame in rain.step(c, size, frame) }, reseed: { rain.reseed($0) })
            .accessibilityLabel("Matrix TV: code rain with four gold words, persistent thoughts manifest reality")
    }
}

// MARK: - 06: Ascension lite

/// p5's noise(): value noise with cosine blending, four octaves at half amplitude.
private struct CMNoise {
    private var table: [Double]
    init(seed: UInt32) {
        var r = HeroRNG(a: seed)
        table = (0..<4096).map { _ in r.next() }
    }
    func noise(_ x0: Double, _ y0: Double, _ z0: Double) -> Double {
        let x = abs(x0), y = abs(y0), z = abs(z0)
        var xi = Int(x), yi = Int(y), zi = Int(z)
        var xf = x - Double(xi), yf = y - Double(yi), zf = z - Double(zi)
        func sc(_ i: Double) -> Double { 0.5 * (1 - cos(i * .pi)) }
        var r = 0.0, ampl = 0.5
        for _ in 0..<4 {
            var of = xi + (yi << 4) + (zi << 8)
            let rxf = sc(xf), ryf = sc(yf)
            var n1 = table[of & 4095]
            n1 += rxf * (table[(of + 1) & 4095] - n1)
            var n2 = table[(of + 16) & 4095]
            n2 += rxf * (table[(of + 17) & 4095] - n2)
            n1 += ryf * (n2 - n1)
            of += 256
            n2 = table[of & 4095]
            n2 += rxf * (table[(of + 1) & 4095] - n2)
            let n3a = table[(of + 16) & 4095]
            let n3 = n3a + rxf * (table[(of + 17) & 4095] - n3a)
            n2 += ryf * (n3 - n2)
            n1 += sc(zf) * (n2 - n1)
            r += n1 * ampl; ampl *= 0.5
            xi <<= 1; xf *= 2; yi <<= 1; yf *= 2; zi <<= 1; zf *= 2
            if xf >= 1 { xi += 1; xf -= 1 }
            if yf >= 1 { yi += 1; yf -= 1 }
            if zf >= 1 { zi += 1; zf -= 1 }
        }
        return r
    }
}

private final class CMAscension: @unchecked Sendable {
    typealias RGB = SIMD3<Double>
    struct Pal { var bg: RGB, cd: RGB, cl: RGB, w: RGB, s: RGB, a: RGB }
    static let palettes: [Pal] = [
        Pal(bg: [3, 0, 10], cd: [140, 10, 25], cl: [255, 80, 110], w: [255, 210, 190], s: [255, 230, 180], a: [255, 220, 160]),
        Pal(bg: [4, 2, 10], cd: [180, 90, 10], cl: [255, 200, 80], w: [255, 240, 210], s: [255, 255, 200], a: [255, 255, 200]),
        Pal(bg: [0, 4, 12], cd: [10, 60, 140], cl: [90, 180, 255], w: [210, 230, 255], s: [220, 250, 255], a: [220, 240, 255]),
        Pal(bg: [0, 0, 0], cd: [180, 40, 20], cl: [255, 120, 80], w: [255, 220, 200], s: [255, 230, 210], a: [255, 230, 210]),
    ]
    static let maxPoints = 420, basePop = 16, noiseScale = 0.001, pulseSpeed = 0.015
    static let reproInterval = 200.0, reproChance = 0.25, collapseInterval = 1800, collapseDuration = 260.0

    final class Portal {
        var x: Double, y: Double, r: Double, ir: Double, f: Double, ph: Double, cr: Double
        init(_ w: Double, _ h: Double, _ g: CMAscension) {
            let rad = g.rand(80, 150)
            x = g.rand(w * 0.2, w * 0.8); y = g.rand(h * 0.2, h * 0.8); r = rad
            ir = rad * g.rand(2, 3); f = g.rand(0.4, 0.9); ph = g.rand(0, 1000); cr = rad
        }
    }
    final class Organism {
        var s: Int
        var pts: [(x: Double, y: Double, gap: Bool)] = []
        var ph: Double, seed: Double
        var life = 0, lr = 0.0, alive = true
        var e = 1.0, cf = 1.0
        var bt = 0.0, na = 0.0, sp = 0.0, tw = 0.0, rt = 0.0, ri = 0.0, rc = 0.0
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var gp = 0, gq = 0
        init(_ s: Int, parent: Bool, _ g: CMAscension) {
            self.s = s; ph = g.rand(0, 1000); seed = g.rand(0, 10000)
            func mut(_ v: Double, _ a: Double = 0.1) -> Double { parent ? v * g.rand(1 - a, 1 + a) : v }
            switch s {
            case 0: bt = mut(g.rand(60, 110)); na = mut(40); sp = mut(g.rand(1.4, 2.2)); tw = mut(0.55, 0.15); rt = 0.7
            case 1: bt = mut(g.rand(10, 22)); na = mut(80); sp = mut(g.rand(2.2, 3.4)); tw = mut(0.9, 0.2); rt = 0.6
            default: bt = mut(g.rand(8, 16)); na = mut(120); sp = mut(g.rand(2.4, 3.6)); tw = mut(1.2, 0.25); rt = 0.5
            }
            ri = CMAscension.reproInterval * g.rand(0.8, 1.2)
            rc = CMAscension.reproChance * g.rand(0.8, 1.2)
            spawn(g)
        }
        func spawn(_ g: CMAscension) {
            let w = Double(g.size.width), h = Double(g.size.height)
            switch Int(g.rand(0, 4)) {
            case 0: x = -w * 0.2; y = g.rand(h * 0.15, h * 0.85); vx = sp; vy = g.rand(-0.4, 0.4)
            case 1: x = w + w * 0.2; y = g.rand(h * 0.15, h * 0.85); vx = -sp; vy = g.rand(-0.4, 0.4)
            case 2: x = -w * 0.2; y = -h * 0.2; vx = sp; vy = sp * g.rand(0.6, 1)
            default: x = -w * 0.2; y = h + h * 0.2; vx = sp; vy = -sp * g.rand(0.6, 1)
            }
            gp = 0; gq = 0
        }
    }

    var rng = HeroRNG(a: UInt32.random(in: 1...UInt32.max))
    var noise = CMNoise(seed: UInt32.random(in: 1...UInt32.max))
    var size: CGSize = .zero
    var frame = 0
    var organisms: [Organism] = []
    var portals: [Portal] = []
    var curPal = 0, nextPal = 1, palT = 0.0
    var collapseActive = false, collapseStart = 0

    func rand(_ a: Double, _ b: Double) -> Double { a + rng.next() * (b - a) }
    func newOrganism(_ s: Int? = nil, parent: Bool = false) -> Organism { Organism(s ?? Int(rand(0, 3)), parent: parent, self) }

    func ensure(_ s: CGSize) {
        if s.width < 20 || s.height < 20 || (abs(s.width - size.width) < 1 && abs(s.height - size.height) < 1 && !organisms.isEmpty) { return }
        size = s
        noise = CMNoise(seed: UInt32.random(in: 1...UInt32.max))
        portals = [Portal(Double(s.width), Double(s.height), self), Portal(Double(s.width), Double(s.height), self)]
        organisms = (0..<Self.basePop).map { Organism($0 % 3, parent: false, self) }
        frame = 0; collapseActive = false; palT = 0
    }

    private func blended() -> Pal {
        let a = Self.palettes[curPal], b = Self.palettes[nextPal]
        func l(_ x: RGB, _ y: RGB, _ t: Double = palT) -> RGB { x + (y - x) * t }
        return Pal(bg: l(a.bg, b.bg, palT * 0.5), cd: l(a.cd, b.cd), cl: l(a.cl, b.cl), w: l(a.w, b.w), s: l(a.s, b.s), a: l(a.a, b.a))
    }

    private func step(_ o: Organism) -> Organism? {
        o.life += 1; o.lr += 1
        let ft = Double(frame) * Self.pulseSpeed + o.ph
        let n = noise.noise(o.x * Self.noiseScale, o.y * Self.noiseScale, o.seed + ft * 0.05)
        let angle = n * 2 * .pi * 3
        o.vx += cos(angle) * o.na * 0.008; o.vy += sin(angle) * o.na * 0.008
        o.vx *= o.rt; o.vy *= o.rt
        var gap = false
        if o.gp > 0 { gap = true; o.gp -= 1 } else if o.gq > 0 { gap = true; o.gq -= 1 }
        o.pts.append((o.x, o.y, gap))
        if o.pts.count > Self.maxPoints { o.pts.removeFirst() }
        o.x += o.vx; o.y += o.vy
        for pt in portals {                                          // the portals pull each organism toward their centre
            let fx = o.x - pt.x, fy = o.y - pt.y, d2 = fx * fx + fy * fy
            if d2 < pt.ir * pt.ir {
                let d = max(sqrt(d2), 1e-9)
                let sf = o.s == 0 ? 0.9 : o.s == 1 ? 1.1 : 1.3
                let st = (1 - d / pt.ir) * pt.f * sf
                o.x -= fx / d * st * o.cf; o.y -= fy / d * st * o.cf
            }
        }
        let w = Double(size.width), h = Double(size.height)
        if o.x < -w * 0.4 || o.x > w * 1.4 || o.y < -h * 0.4 || o.y > h * 1.4 { o.alive = false; return nil }
        if o.lr >= o.ri {
            o.lr = 0
            if rand(0, 1) < o.rc && organisms.count < 60 { return Organism(o.s, parent: true, self) }
        }
        return nil
    }

    /// One 60 fps step of the world (the part of p5's draw() that is not drawing).
    func advance() {
        frame += 1
        palT = min(palT + 0.0008, 1)
        if palT >= 1 { curPal = nextPal; nextPal = (nextPal + 1) % Self.palettes.count; palT = 0 }
        for p in portals { p.cr = p.r * (1 + 0.12 * sin(Double(frame) * 0.01 + p.ph)) }
        if !collapseActive && frame % Self.collapseInterval == 0 && frame > 0 { collapseActive = true; collapseStart = frame }
        if collapseActive && Double(frame - collapseStart) > Self.collapseDuration {
            collapseActive = false
            organisms = organisms.filter { $0.alive }
            while organisms.count < Self.basePop { organisms.append(newOrganism()) }
        }
        var born: [Organism] = []
        for o in organisms where o.alive { if let child = step(o) { born.append(child) } }
        organisms.append(contentsOf: born)
        organisms = organisms.filter { $0.alive }
        if organisms.count < Self.basePop { organisms.append(newOrganism()) }
    }

    func draw(_ gc: inout GraphicsContext) {
        let pal = blended()
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c(pal.bg)))
        for p in portals {
            for i in 0..<3 {
                let rr = p.cr * (1 + Double(i) * 0.35), a = 40 - Double(i) * 10
                gc.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(c(pal.a, a)), lineWidth: 1.5 + Double(i) * 0.7)
            }
        }
        let colFactor = collapseActive ? 1 - Double(frame - collapseStart) / Self.collapseDuration * 0.7 : 1
        for o in organisms where o.alive { render(o, pal, colFactor, &gc) }
    }

    private func c(_ v: RGB, _ a: Double = 255) -> Color { cmRGB(v.x, v.y, v.z, a) }

    private func render(_ o: Organism, _ pal: Pal, _ colFactor: Double, _ gc: inout GraphicsContext) {
        guard o.pts.count >= 3 else { return }
        let base = o.bt * o.e * colFactor
        var vs: [CGPoint] = [], t = 0.5
        for i in 1..<o.pts.count {
            let pt = o.pts[i], prev = o.pts[i - 1]
            if pt.gap { continue }
            let dx = pt.x - prev.x, dy = pt.y - prev.y
            t = (-dy / max(sqrt(dx * dx + dy * dy), 1e-9) + 1) * 0.5
            vs.append(CGPoint(x: pt.x, y: pt.y))
        }
        guard let path = cmSpline(vs) else { return }
        switch o.s {
        case 0:
            gc.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: base + 8, lineCap: .round, lineJoin: .round))
            gc.stroke(path, with: .color(c(pal.cd + (pal.cl - pal.cd) * t)), style: StrokeStyle(lineWidth: base, lineCap: .round, lineJoin: .round))
        case 1:
            gc.stroke(path, with: .color(c(pal.w, 160)), style: StrokeStyle(lineWidth: max(1, base * 0.45), lineCap: .round, lineJoin: .round))
        default:
            gc.stroke(path, with: .color(c(pal.s, 100)), style: StrokeStyle(lineWidth: max(0.5, base * 0.22), lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CMAscensionCanvas: View {
    let paused: Bool
    @State private var sim = CMAscension()
    @State private var clock = LabFrameClock()
    var body: some View {
        TimelineView(.animation(paused: paused)) { tl in
            Canvas { gc, size in
                sim.ensure(size)
                for _ in 0..<clock.due(tl.date) { sim.advance() }
                sim.draw(&gc)
            }
        }
        .drawingGroup()
        .accessibilityLabel("Ascension lite: cloth, wire and spore organisms drifting through two portals")
    }
}
