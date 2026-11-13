import MetalKit
import SwiftUI

// Living Curves, the ribbon lab (app/lab, components/lab/RibbonCurves.tsx, lib/curve-ribbons/engine.ts).
// His twelve comps (public SVGs on the gallery) become gold ribbons: every filled shape is split into two sides, resampled by arc
// length, and drawn as a strip whose middle is the bright spine. The fragment shader reveals them along their length, breathes,
// and a glint runs down each one. A bloom pass lifts the spine, as the page's UnrealBloomPass did.

// MARK: - SVG to ribbons (pure, runs off the main thread)

enum LabRibbonBuilder {
    struct Built { let verts: [Float]; let aspect: Double; let count: Int }

    /// Fills the study sheets use for guides; the engine skips them.
    static let studyFills: Set<String> = ["#00ffff", "#00fefe", "#e28c0d", "#e2840d", "#9e2a2b", "#a31621", "#ff3b00", "#ff3a00", "#000000"]

    private struct Shape { let d: String; let fill: String; let m: CGAffineTransform }

    private final class Reader: NSObject, XMLParserDelegate {
        struct Frame { var fill: String?; var hidden: Bool; var m: CGAffineTransform; var isDefs: Bool }
        var stack: [Frame] = [Frame(fill: nil, hidden: false, m: .identity, isDefs: false)]
        var shapes: [Shape] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            var f = stack.last ?? Frame(fill: nil, hidden: false, m: .identity, isDefs: false)
            let style = Reader.style(a["style"])
            if style["display"] == "none" || a["display"] == "none" { f.hidden = true }
            if name == "defs" || name == "clipPath" || name == "mask" || name == "symbol" { f.isDefs = true }
            if let fill = style["fill"] ?? a["fill"] { f.fill = fill.lowercased().trimmingCharacters(in: .whitespaces) }
            if let t = a["transform"] { f.m = LabRibbonBuilder.transform(t).concatenating(f.m) }
            if name == "path", !f.hidden, !f.isDefs, let d = a["d"] { shapes.append(Shape(d: d, fill: f.fill ?? "#000000", m: f.m)) }
            stack.append(f)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if stack.count > 1 { stack.removeLast() } }

        static func style(_ s: String?) -> [String: String] {
            var out: [String: String] = [:]
            for part in (s ?? "").split(separator: ";") {
                let kv = part.split(separator: ":", maxSplits: 1)
                if kv.count == 2 { out[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces) }
            }
            return out
        }
    }

    /// SVG `transform=` (matrix, translate, scale, rotate), later items applied first.
    static func transform(_ s: String) -> CGAffineTransform {
        var m = CGAffineTransform.identity
        guard let re = try? NSRegularExpression(pattern: #"(\w+)\s*\(([^)]*)\)"#) else { return m }
        let ns = s as NSString
        for r in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: r.range(at: 1))
            let nums = ns.substring(with: r.range(at: 2)).split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.map { CGFloat($0) }
            var t = CGAffineTransform.identity
            switch name {
            case "matrix" where nums.count == 6: t = CGAffineTransform(a: nums[0], b: nums[1], c: nums[2], d: nums[3], tx: nums[4], ty: nums[5])
            case "translate" where nums.count >= 1: t = CGAffineTransform(translationX: nums[0], y: nums.count > 1 ? nums[1] : 0)
            case "scale" where nums.count >= 1: t = CGAffineTransform(scaleX: nums[0], y: nums.count > 1 ? nums[1] : nums[0])
            case "rotate" where nums.count >= 1:
                let a = nums[0] * .pi / 180
                if nums.count >= 3 { t = CGAffineTransform(translationX: nums[1], y: nums[2]).rotated(by: a).translatedBy(x: -nums[1], y: -nums[2]) }
                else { t = CGAffineTransform(rotationAngle: a) }
            default: break
            }
            m = t.concatenating(m)
        }
        return m
    }

    /// A path as closed polylines, curves flattened.
    static func polylines(_ path: CGPath, _ m: CGAffineTransform) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var cur: [CGPoint] = []
        var last = CGPoint.zero
        func flush() { if cur.count > 1 { out.append(cur) }; cur = [] }
        path.applyWithBlock { el in
            let e = el.pointee
            let p = e.points
            switch e.type {
            case .moveToPoint: flush(); last = p[0]; cur = [last]
            case .addLineToPoint: cur.append(p[0]); last = p[0]
            case .addQuadCurveToPoint:
                let c = p[0], q = p[1]
                for i in 1...6 { let t = CGFloat(i) / 6, u = 1 - t; cur.append(CGPoint(x: u * u * last.x + 2 * u * t * c.x + t * t * q.x, y: u * u * last.y + 2 * u * t * c.y + t * t * q.y)) }
                last = q
            case .addCurveToPoint:
                let c1 = p[0], c2 = p[1], q = p[2]
                for i in 1...8 {
                    let t = CGFloat(i) / 8, u = 1 - t
                    let x = u * u * u * last.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * q.x
                    let y = u * u * u * last.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * q.y
                    cur.append(CGPoint(x: x, y: y))
                }
                last = q
            case .closeSubpath: flush()
            @unknown default: break
            }
        }
        flush()
        return out.map { $0.map { $0.applying(m) } }
    }

    static func area(_ pts: [CGPoint]) -> Double {
        var a = 0.0
        for i in 0..<pts.count { let p = pts[i], q = pts[(i + 1) % pts.count]; a += Double(p.x * q.y - q.x * p.y) }
        return a / 2
    }

    static func build(svg: Data, targetHeight: Double = 6) -> Built? {
        let reader = Reader()
        let xml = XMLParser(data: svg)
        xml.delegate = reader
        guard xml.parse() || !reader.shapes.isEmpty else { return nil }

        var kept: [[CGPoint]] = []
        for s in reader.shapes {
            if s.fill == "none" || studyFills.contains(s.fill) { continue }
            guard let path = SVGPath.parse(s.d) else { continue }
            let lines = polylines(path, s.m)
            guard !lines.isEmpty else { continue }
            // the outer contours share the winding of the largest one; the opposite winding is a hole, which the ribbon engine ignores
            let areas = lines.map(area)
            guard let big = areas.max(by: { abs($0) < abs($1) }) else { continue }
            for (i, l) in lines.enumerated() where (areas[i] > 0) == (big > 0) && abs(areas[i]) > 1e-9 {
                var c = l
                if let f = c.first, let z = c.last, abs(f.x - z.x) < 1e-7, abs(f.y - z.y) < 1e-7 { c.removeLast() }
                if c.count >= 3 { kept.append(c) }
            }
        }
        guard !kept.isEmpty else { return nil }

        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for c in kept { for p in c { minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x)); minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y)) } }
        let w = maxX - minX, h = maxY - minY
        guard w > 0, h > 0 else { return nil }
        let scale = targetHeight / h
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let tx = { (x: CGFloat) -> Float in Float((Double(x) - cx) * scale) }
        let ty = { (y: CGFloat) -> Float in Float(-(Double(y) - cy) * scale) }

        var verts: [Float] = []
        var ribbons = 0
        for c in kept { if appendRibbon(c, tx, ty, &verts) { ribbons += 1 } }
        guard ribbons > 0 else { return nil }
        return Built(verts: verts, aspect: w / h, count: ribbons)
    }

    private static func appendRibbon(_ contour: [CGPoint], _ tx: (CGFloat) -> Float, _ ty: (CGFloat) -> Float, _ out: inout [Float]) -> Bool {
        let n = contour.count
        if n < 6 { return false }
        let iHi = n / 2
        if iHi <= 0 || iHi >= n { return false }
        func walk(_ from: Int, _ to: Int) -> [CGPoint] {
            var r: [CGPoint] = []
            var i = from
            for _ in 0...n { r.append(contour[i]); if i == to { break }; i = (i + 1) % n }
            return r
        }
        let sideA = walk(0, iHi)
        let sideB = Array(walk(iHi, 0).reversed())
        if sideA.count < 2 || sideB.count < 2 { return false }

        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        func resample(_ pts: [CGPoint], _ S: Int) -> [CGPoint]? {
            var seg: [CGFloat] = []
            var total: CGFloat = 0
            for i in 1..<pts.count { let d = dist(pts[i], pts[i - 1]); seg.append(d); total += d }
            if total < 1e-6 { return nil }
            var res: [CGPoint] = []
            var acc: CGFloat = 0
            var i = 0
            for s in 0..<S {
                let target = CGFloat(s) / CGFloat(S - 1) * total
                while i < seg.count && acc + seg[i] < target { acc += seg[i]; i += 1 }
                if i >= seg.count { res.append(pts[pts.count - 1]); continue }
                let f = seg[i] > 1e-9 ? (target - acc) / seg[i] : 0
                res.append(CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * f, y: pts[i].y + (pts[i + 1].y - pts[i].y) * f))
            }
            return res
        }
        var axLen: CGFloat = 0
        for i in 1..<sideA.count { axLen += dist(sideA[i], sideA[i - 1]) }
        let S = max(8, min(220, Int((axLen / 2.2).rounded())))
        guard let A = resample(sideA, S), let B = resample(sideB, S) else { return false }
        let mid = (0..<S).map { CGPoint(x: (A[$0].x + B[$0].x) / 2, y: (A[$0].y + B[$0].y) / 2) }
        var clLen: CGFloat = 0
        for s in 1..<S { clLen += dist(mid[s], mid[s - 1]) }
        let widths = (0..<S).map { dist(A[$0], B[$0]) }.sorted()
        let medW = widths[widths.count >> 1]
        if clLen < 1e-3 || medW > clLen * 0.55 { return false }

        func push(_ p: CGPoint, _ edge: Float, _ arc: Float) { out.append(tx(p.x)); out.append(ty(p.y)); out.append(edge); out.append(arc) }
        for s in 0..<(S - 1) {
            let a0 = Float(s) / Float(S - 1), a1 = Float(s + 1) / Float(S - 1)
            let L0 = A[s], C0 = mid[s], R0 = B[s], L1 = A[s + 1], C1 = mid[s + 1], R1 = B[s + 1]
            push(L0, 0, a0); push(C0, 1, a0); push(L1, 0, a1)
            push(L1, 0, a1); push(C0, 1, a0); push(C1, 1, a1)
            push(C0, 1, a0); push(R0, 0, a0); push(C1, 1, a1)
            push(C1, 1, a1); push(R0, 0, a0); push(R1, 0, a1)
        }
        return true
    }
}

// MARK: - The scene

private let ribbonSource = """
struct RibOut { float4 pos [[position]]; float edge; float arc; };
vertex RibOut vs_ribbon(uint vid [[vertex_id]], constant float4 *V [[buffer(1)]], constant float *U [[buffer(0)]]) {
    float4 v = V[vid];
    RibOut o;
    o.pos = float4(v.x * U[0], v.y * U[1], 0.0, 1.0);
    o.edge = v.z; o.arc = v.w;
    return o;
}
fragment float4 fs_ribbon(RibOut in [[stage_in]], constant float *U [[buffer(0)]]) {
    float reveal = U[2]; float t = U[3]; float breathe = U[4];
    float3 uGold = float3(U[5], U[6], U[7]);
    float lead = 1.0 - smoothstep(reveal - 0.12, reveal, in.arc);
    if (lead <= 0.001) { discard_fragment(); }
    float spine = clamp(in.edge, 0.0, 1.0);
    float3 core = mix(uGold, float3(1.0, 0.97, 0.88), 0.9);
    float3 deep = uGold * 0.30;
    float3 col = mix(deep, core, pow(spine, 1.35));
    float rim = smoothstep(0.0, 0.10, spine) * (1.0 - smoothstep(0.10, 0.42, spine));
    col += uGold * rim * 0.85;
    float glint = 0.5 + 0.5 * sin(in.arc * 7.0 - t * 1.2);
    float lum = 0.80 + 0.20 * breathe + 0.14 * glint * spine;
    float tip = smoothstep(reveal - 0.12, reveal - 0.01, in.arc) * lead;
    col += core * tip * 0.7;
    return float4(col * lum, 1.0);
}
fragment float4 fs_bright_h(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float2 px = float2(U[0], 0.0);
    float3 acc = float3(0.0);
    float wts[5] = {0.2270, 0.1946, 0.1216, 0.0541, 0.0162};
    for (int i = -4; i <= 4; i++) {
        float3 c = src.sample(sL, in.uv + px * float(i) * 2.0).rgb;
        float l = dot(c, float3(0.299, 0.587, 0.114));
        c *= smoothstep(0.6, 0.75, l);
        acc += c * wts[abs(i)];
    }
    return float4(acc, 1.0);
}
fragment float4 fs_blur(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> src [[texture(0)]]) {
    float2 px = float2(U[0], U[1]);
    float3 acc = float3(0.0);
    float wts[5] = {0.2270, 0.1946, 0.1216, 0.0541, 0.0162};
    for (int i = -4; i <= 4; i++) { acc += src.sample(sL, in.uv + px * float(i) * 2.0).rgb * wts[abs(i)]; }
    return float4(acc, 1.0);
}
fragment float4 fs_comp(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> scn [[texture(0)]], texture2d<float> bloom [[texture(1)]]) {
    float3 a = scn.sample(sL, in.uv).rgb;
    float3 b = bloom.sample(sL, in.uv).rgb;
    return float4(a + b * U[0], 1.0);
}
"""

@MainActor final class LabRibbonScene: LabMetalScene {
    let lib: MTLLibrary
    var vbuf: MTLBuffer?
    var vcount = 0
    var halfW: Float = 3.3, halfH: Float = 3.3
    var aspect = 1.0
    var reveal: Float = 0
    let start = CACurrentMediaTime()
    let reduce = labReduceMotion()
    var scene: MTLTexture?, b1: MTLTexture?, b2: MTLTexture?
    var viewAspect: Float = 0.46

    init?() {
        guard let l = LabGPU.library("ribbon", ribbonSource) else { return nil }
        lib = l
    }

    func load(_ built: LabRibbonBuilder.Built) {
        built.verts.withUnsafeBytes { vbuf = LabGPU.device?.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        vcount = built.verts.count / 4
        aspect = built.aspect
        reveal = reduce ? 1.3 : 0
    }

    var paused: Bool { false }

    private func fit() {
        let contentH: Float = 6, contentW = 6 * Float(aspect), pad: Float = 1.1
        if viewAspect > Float(aspect) { halfH = contentH / 2 * pad; halfW = halfH * viewAspect }
        else { halfW = contentW / 2 * pad; halfH = halfW / viewAspect }
    }

    func frame(_ view: MTKView, _ cb: MTLCommandBuffer, _ target: MTLTexture) {
        let w = target.width, h = target.height
        viewAspect = Float(w) / Float(max(1, h))
        fit()
        if scene == nil || scene!.width != w || scene!.height != h {
            scene = LabGPU.texture(w, h, .rgba16Float)
            b1 = LabGPU.texture(max(2, w / 4), max(2, h / 4), .rgba16Float)
            b2 = LabGPU.texture(max(2, w / 4), max(2, h / 4), .rgba16Float)
        }
        guard let scene, let b1, let b2, let vbuf, vcount > 0,
              let rib = LabGPU.pipeline(lib, "fs_ribbon", format: .rgba16Float, key: "ribbon", vertex: "vs_ribbon"),
              let bright = LabGPU.pipeline(lib, "fs_bright_h", format: .rgba16Float, key: "ribbon"),
              let blur = LabGPU.pipeline(lib, "fs_blur", format: .rgba16Float, key: "ribbon"),
              let comp = LabGPU.pipeline(lib, "fs_comp", format: target.pixelFormat, key: "ribbon") else {
            LabGPU.clear(cb, target)   // nothing loaded yet: the ground
            return
        }
        if reveal < 1.25 { reveal += 0.006 }
        let t = Float(CACurrentMediaTime() - start)
        let breathe = 0.5 + 0.5 * sin(t * 0.55)

        // the ribbons, painter's order, into the scene texture (gold in linear light, as the page's colour was)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = scene
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.003, green: 0.003, blue: 0.003, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        if let e = cb.makeRenderCommandEncoder(descriptor: pass) {
            e.setRenderPipelineState(rib)
            var u: [Float] = [1 / halfW, 1 / halfH, reveal, t, breathe, 0.584, 0.392, 0.072]
            e.setVertexBytes(&u, length: u.count * 4, index: 0)
            e.setVertexBuffer(vbuf, offset: 0, index: 1)
            e.setFragmentBytes(&u, length: u.count * 4, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vcount)
            e.endEncoding()
        }
        // bloom: bright pass + horizontal blur at a quarter size, then two vertical/horizontal blurs
        let qw = Float(b1.width), qh = Float(b1.height)
        LabGPU.run(cb, bright, target: b1, textures: [scene], params: [1 / qw])
        LabGPU.run(cb, blur, target: b2, textures: [b1], params: [0, 1 / qh])
        LabGPU.run(cb, blur, target: b1, textures: [b2], params: [1 / qw, 0])
        LabGPU.run(cb, blur, target: b2, textures: [b1], params: [0, 1 / qh])
        LabGPU.run(cb, comp, target: target, textures: [scene, b2], params: [0.9])
    }
}

struct LabRibbonView: View {
    let model: AppModel
    @State private var scene = LabRibbonScene()
    @State private var comp = 9
    @State private var failed = false
    @State private var cache: [Int: LabRibbonBuilder.Built] = [:]
    private let count = 12

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let scene { LabMetalView(scene: scene) } else { LabGPUMissing() }
            if failed {
                Text("This comp did not load. Pull back and try again.").font(.footnote).foregroundStyle(PLG.gold.opacity(0.7)).padding(.bottom, 80).frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                stepButton("‹", "Previous composition") { comp = (comp - 2 + count) % count + 1 }
                Text("\(String(format: "%02d", comp)) / 12").font(.system(size: 13, design: .serif)).labCaps().tracking(1.8).foregroundStyle(PLG.gold.opacity(0.7)).frame(minWidth: 56).monospacedDigit()
                stepButton("›", "Next composition") { comp = comp % count + 1 }
            }
            .padding(.trailing, 20).padding(.bottom, 26)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40 { comp = comp % count + 1 } else if v.translation.width > 40 { comp = (comp - 2 + count) % count + 1 }
        })
        .task(id: comp) { await load(comp) }
        .sensoryFeedback(PLHaptic.select, trigger: comp)
    }

    private func stepButton(_ s: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s).font(.system(size: 20)).foregroundStyle(PLG.gold.opacity(0.85)).frame(width: 44, height: 44)
                .background { Circle().fill(Color(hex: 0x0a0a0a).opacity(0.6)) }
                .overlay { Circle().strokeBorder(PLG.gold.opacity(0.35), lineWidth: 1) }
        }
        .accessibilityLabel(label)
    }

    private func load(_ n: Int) async {
        failed = false
        if let b = cache[n] { scene?.load(b); return }
        guard let http = model.http else { failed = true; return }
        do {
            let data = try await http.send(RequestPlan(origin: "gallery", path: "curves/curve-comp-\(String(format: "%02d", n)).svg"), timeout: 60)
            let built = await Task.detached(priority: .userInitiated) { LabRibbonBuilder.build(svg: data) }.value
            guard let built else { failed = true; return }
            cache[n] = built
            if n == comp { scene?.load(built) }
        } catch { failed = true }
    }
}
