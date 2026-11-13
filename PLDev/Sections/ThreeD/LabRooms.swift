import SwiftUI
import RealityKit
import UIKit

// MARK: - The heart coin (his heart1 model, gold, spinning, breathing)

struct HeartRoom: View {
    @State private var holder = Entity()
    @State private var missing = false

    var body: some View {
        OrbitStage(distance: 3.4, height: 0.0, autoSpin: true) { pivot in
            guard let e = await ThreeDModels.load("heart1") else { missing = true; return }
            ThreeDModels.paint(e, ThreeDModels.goldMaterial(rough: 0.28))
            e.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])   // his GLB's up is -Z
            let f = ThreeDModels.fitted(e, longest: 1.6)
            f.position.y = -0.8
            holder = f
            pivot.addChild(f)
        }
        .overlay { if missing { ContentUnavailableView("Model not found", systemImage: "heart.slash", description: Text("The heart is not in this build.")) } }
        .task {
            var t: Float = 0
            while !Task.isCancelled {   // the web's breathing pulse: scale 1 +/- 3 %
                t += 0.016
                holder.scale = SIMD3<Float>(repeating: 1 + sin(t * 1.2) * 0.03)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .navigationTitle("Heart").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - The wordmark: PSYCHED over LUXURIES in his hand, gold, with the thin line between

struct WordmarkRoom: View {
    var body: some View {
        OrbitStage(distance: 6.0, height: 0.0, autoSpin: true) { pivot in
            let name = HouseKit.shared.titleFont
            let font = name.flatMap { UIFont(name: $0, size: 0.5) } ?? UIFont.systemFont(ofSize: 0.5, weight: .semibold)
            for (text, y) in [("PSYCHED", Float(0.55)), ("LUXURIES", Float(-0.7))] {
                let mesh = MeshResource.generateText(text, extrusionDepth: 0.06, font: font, containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
                let e = ModelEntity(mesh: mesh, materials: [ThreeDModels.goldMaterial(rough: 0.3)])
                let b = e.visualBounds(relativeTo: nil)
                e.position = [-b.center.x, y - b.center.y, 0]
                pivot.addChild(e)
            }
            let line = ModelEntity(mesh: .generateBox(size: [3.2, 0.012, 0.012]), materials: [SimpleMaterial(color: ThreeDHouse.gold, roughness: 0.4, isMetallic: true)])
            pivot.addChild(line)
        }
        .navigationTitle("Wordmark").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Living Curves: his twelve curve compositions as gold ribbons

/// Reads the SVG path data of a curve composition and builds its ribbons the way the web engine does: each filled shape is split
/// into two sides, both resampled to the same count, and the ribbon is the strip between them with a spine down the middle.
enum RibbonBuilder {
    static let studyFills: Set<String> = ["#00ffff", "#00fefe", "#e28c0d", "#e2840d", "#9e2a2b", "#a31621", "#ff3b00", "#ff3a00", "#000000"]

    /// Closed contours (as point lists) from an SVG's filled paths.
    static func contours(svg: String) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var rest = svg[...]
        while let r = rest.range(of: "<path") {
            rest = rest[r.upperBound...]
            guard let end = rest.range(of: "/>") else { break }
            let tag = String(rest[..<end.lowerBound])
            rest = rest[end.upperBound...]
            guard let d = attr("d", in: tag) else { continue }
            let fill = (fillColour(tag) ?? "").lowercased()
            if fill == "none" || studyFills.contains(fill) { continue }
            for c in parse(d) where c.count >= 6 { out.append(c) }
        }
        return out
    }

    private static func attr(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: " \(name)=\"") ?? tag.range(of: "\n\(name)=\"") ?? tag.range(of: "\t\(name)=\"") else { return nil }
        let after = tag[r.upperBound...]
        guard let q = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<q])
    }

    private static func fillColour(_ tag: String) -> String? {
        if let f = attr("fill", in: tag) { return f }
        guard let s = attr("style", in: tag), let r = s.range(of: "fill:") else { return nil }
        let after = s[r.upperBound...]
        return String(after.prefix { $0 != ";" }).trimmingCharacters(in: .whitespaces)
    }

    /// M m L l H h V v C c S s Q q Z z, each curve sampled in 24 steps. Arcs do not occur in his compositions.
    static func parse(_ d: String) -> [[CGPoint]] {
        var tokens: [String] = []
        var cur = ""
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" { if !cur.isEmpty { tokens.append(cur); cur = "" }; tokens.append(String(ch)) }
            else if ch == "," || ch == " " || ch == "\n" || ch == "\t" { if !cur.isEmpty { tokens.append(cur); cur = "" } }
            else if ch == "-" && !cur.isEmpty && cur.last != "e" && cur.last != "E" { tokens.append(cur); cur = "-" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var subs: [[CGPoint]] = []
        var pts: [CGPoint] = []
        var p = CGPoint.zero, start = CGPoint.zero, lastC = CGPoint.zero
        var i = 0
        var cmd = "M"
        func num() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }
        func isCmd(_ s: String) -> Bool { s.count == 1 && s.first!.isLetter && s != "e" }
        func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ e: CGPoint) {
            for k in 1...24 {
                let t = CGFloat(k) / 24, u = 1 - t
                pts.append(CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*e.x, y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*e.y))
            }
        }
        while i < tokens.count {
            if isCmd(tokens[i]) { cmd = tokens[i]; i += 1 }
            let rel = cmd.first!.isLowercase
            switch cmd.uppercased() {
            case "M":
                if pts.count > 1 { subs.append(pts) }
                let x = num(), y = num(); p = rel ? CGPoint(x: p.x + x, y: p.y + y) : CGPoint(x: x, y: y); start = p; pts = [p]
                cmd = rel ? "l" : "L"
            case "L": let x = num(), y = num(); p = rel ? CGPoint(x: p.x + x, y: p.y + y) : CGPoint(x: x, y: y); pts.append(p)
            case "H": let x = num(); p.x = rel ? p.x + x : x; pts.append(p)
            case "V": let y = num(); p.y = rel ? p.y + y : y; pts.append(p)
            case "C":
                let x1 = num(), y1 = num(), x2 = num(), y2 = num(), x = num(), y = num()
                let b = rel ? CGPoint(x: p.x + x1, y: p.y + y1) : CGPoint(x: x1, y: y1)
                let c = rel ? CGPoint(x: p.x + x2, y: p.y + y2) : CGPoint(x: x2, y: y2)
                let e = rel ? CGPoint(x: p.x + x, y: p.y + y) : CGPoint(x: x, y: y)
                cubic(p, b, c, e); lastC = c; p = e
            case "S":
                let x2 = num(), y2 = num(), x = num(), y = num()
                let b = CGPoint(x: 2 * p.x - lastC.x, y: 2 * p.y - lastC.y)
                let c = rel ? CGPoint(x: p.x + x2, y: p.y + y2) : CGPoint(x: x2, y: y2)
                let e = rel ? CGPoint(x: p.x + x, y: p.y + y) : CGPoint(x: x, y: y)
                cubic(p, b, c, e); lastC = c; p = e
            case "Q":
                let x1 = num(), y1 = num(), x = num(), y = num()
                let q = rel ? CGPoint(x: p.x + x1, y: p.y + y1) : CGPoint(x: x1, y: y1)
                let e = rel ? CGPoint(x: p.x + x, y: p.y + y) : CGPoint(x: x, y: y)
                cubic(p, CGPoint(x: p.x + 2 * (q.x - p.x) / 3, y: p.y + 2 * (q.y - p.y) / 3), CGPoint(x: e.x + 2 * (q.x - e.x) / 3, y: e.y + 2 * (q.y - e.y) / 3), e); p = e
            case "Z": p = start; if pts.count > 1 { subs.append(pts) }; pts = []
            default: i += 1
            }
        }
        if pts.count > 1 { subs.append(pts) }
        // close and drop a repeated first point
        return subs.map { s in var s = s; if let a = s.first, let b = s.last, abs(a.x - b.x) < 1e-7, abs(a.y - b.y) < 1e-7 { s.removeLast() }; return s }
    }

    /// The ribbon meshes (one per shape) scaled to `height` metres tall and centred. u = distance from the edge (0 edge, 1 spine), v = arc 0...1.
    static func meshes(svg: String, height: Float) -> (meshes: [MeshResource], aspect: Float) {
        let cs = contours(svg: svg)
        guard !cs.isEmpty else { return ([], 1) }
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for c in cs { for p in c { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) } }
        let h = maxY - minY, w = maxX - minX
        guard h > 0 else { return ([], 1) }
        let sc = CGFloat(height) / h, cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        var out: [MeshResource] = []
        for c in cs {
            guard let m = ribbon(c, tx: { Float(($0 - cx) * sc) }, ty: { Float(-($0 - cy) * sc) }) else { continue }
            out.append(m)
        }
        return (out, Float(w / h))
    }

    private static func ribbon(_ contour: [CGPoint], tx: (CGFloat) -> Float, ty: (CGFloat) -> Float) -> MeshResource? {
        let n = contour.count
        guard n >= 6 else { return nil }
        let iHi = n / 2
        func walk(_ from: Int, _ to: Int) -> [CGPoint] {
            var o: [CGPoint] = []; var i = from
            for _ in 0...n { o.append(contour[i]); if i == to { break }; i = (i + 1) % n }
            return o
        }
        let a = walk(0, iHi)
        let b = Array(walk(iHi, 0).reversed())
        guard a.count >= 2, b.count >= 2 else { return nil }
        func dist(_ p: CGPoint, _ q: CGPoint) -> CGFloat { hypot(p.x - q.x, p.y - q.y) }
        func resample(_ pts: [CGPoint], _ S: Int) -> [CGPoint]? {
            var seg: [CGFloat] = []; var total: CGFloat = 0
            for i in 1..<pts.count { let d = dist(pts[i], pts[i - 1]); seg.append(d); total += d }
            guard total > 1e-6 else { return nil }
            var res: [CGPoint] = []
            for s in 0..<S {
                let target = CGFloat(s) / CGFloat(S - 1) * total
                var acc: CGFloat = 0; var i = 0
                while i < seg.count && acc + seg[i] < target { acc += seg[i]; i += 1 }
                if i >= seg.count { res.append(pts[pts.count - 1]); continue }
                let f = seg[i] > 1e-9 ? (target - acc) / seg[i] : 0
                res.append(CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * f, y: pts[i].y + (pts[i + 1].y - pts[i].y) * f))
            }
            return res
        }
        var axLen: CGFloat = 0
        for i in 1..<a.count { axLen += dist(a[i], a[i - 1]) }
        let S = max(8, min(220, Int((axLen / 2.2).rounded())))
        guard let A = resample(a, S), let B = resample(b, S) else { return nil }
        let mid = (0..<S).map { CGPoint(x: (A[$0].x + B[$0].x) / 2, y: (A[$0].y + B[$0].y) / 2) }
        var clLen: CGFloat = 0
        for s in 1..<S { clLen += dist(mid[s], mid[s - 1]) }
        let widths = (0..<S).map { dist(A[$0], B[$0]) }.sorted()
        guard clLen > 1e-3, widths[widths.count >> 1] <= clLen * 0.55 else { return nil }

        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        func vert(_ p: CGPoint, _ edge: Float, _ arc: Float) -> UInt32 {
            pos.append([tx(p.x), ty(p.y), 0]); uv.append([edge, arc]); return UInt32(pos.count - 1)
        }
        // three bands per step (left, spine, right), as the web builds them, two triangles each
        for s in 0..<(S - 1) {
            let a0 = Float(s) / Float(S - 1), a1 = Float(s + 1) / Float(S - 1)
            let l0 = vert(A[s], 0, a0), c0 = vert(mid[s], 1, a0), r0 = vert(B[s], 0, a0)
            let l1 = vert(A[s + 1], 0, a1), c1 = vert(mid[s + 1], 1, a1), r1 = vert(B[s + 1], 0, a1)
            idx += [l0, c0, l1, l1, c0, c1, c0, r0, c1, c1, r0, r1]
        }
        var d = MeshDescriptor()
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    /// The web shader's colour, baked: deep gold at the edge up to a pale core on the spine, a rim of gold, a soft glint along the arc.
    static func gradient() -> TextureResource? {
        let w = 32, h = 256
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let gold: (Float, Float, Float) = (0.788, 0.659, 0.298)
        for y in 0..<h {
            let arc = Float(y) / Float(h - 1)
            let glint = 0.5 + 0.5 * sin(arc * 7)
            for x in 0..<w {
                let spine = Float(x) / Float(w - 1)
                let k = pow(spine, 1.35)
                let core = (gold.0 + (1 - gold.0) * 0.9, gold.1 + (0.97 - gold.1) * 0.9, gold.2 + (0.88 - gold.2) * 0.9)
                var c = (gold.0 * 0.3 + (core.0 - gold.0 * 0.3) * k, gold.1 * 0.3 + (core.1 - gold.1 * 0.3) * k, gold.2 * 0.3 + (core.2 - gold.2 * 0.3) * k)
                let rim = smooth(0, 0.1, spine) * (1 - smooth(0.1, 0.42, spine))
                c = (c.0 + gold.0 * rim * 0.85, c.1 + gold.1 * rim * 0.85, c.2 + gold.2 * rim * 0.85)
                let lum = 0.8 + 0.2 + 0.14 * glint * spine
                let o = (y * w + x) * 4
                px[o] = UInt8(max(0, min(255, c.0 * lum * 255))); px[o + 1] = UInt8(max(0, min(255, c.1 * lum * 255))); px[o + 2] = UInt8(max(0, min(255, c.2 * lum * 255)))
            }
        }
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
}

struct RibbonRoom: View {
    let model: AppModel
    @State private var comp = 9
    @State private var failed = false
    @State private var stage = Entity()
    @State private var aspect: Float = 1
    private let count = 12

    var body: some View {
        ZStack(alignment: .bottom) {
            OrbitStage(distance: 7.5, height: 0, autoSpin: false) { pivot in
                stage = Entity(); pivot.addChild(stage)
                await show(comp)
            }
            VStack(spacing: 6) {
                if failed { Label("Not loaded. Try another composition.", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary) }
                Picker("Composition", selection: $comp) { ForEach(1...count, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                    .pickerStyle(.menu).padding(.horizontal)
                    .onChange(of: comp) { _, n in Task { await show(n) } }
            }.padding(.vertical, 8).background(.bar)
        }
        .navigationTitle("Curves").navigationBarTitleDisplayMode(.inline)
    }

    private func show(_ n: Int) async {
        for c in stage.children { c.removeFromParent() }
        guard let http = model.http,
              let data = try? await http.send(RequestPlan(origin: "gallery", path: String(format: "curves/curve-comp-%02d.svg", n))),
              let svg = String(data: data, encoding: .utf8) else { failed = true; return }
        let built = RibbonBuilder.meshes(svg: svg, height: 6)
        failed = built.meshes.isEmpty
        var m = UnlitMaterial()
        if let t = RibbonBuilder.gradient() { m.color = .init(tint: .white, texture: .init(t)) } else { m = UnlitMaterial(color: ThreeDHouse.gold) }
        m.faceCulling = .none
        for (i, mesh) in built.meshes.enumerated() {
            let e = ModelEntity(mesh: mesh, materials: [m]); e.position.z = Float(i) * 0.002
            stage.addChild(e)
        }
    }
}
