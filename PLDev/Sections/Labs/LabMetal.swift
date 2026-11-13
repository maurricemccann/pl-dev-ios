import MetalKit
import SwiftUI

// The GPU labs. Each web page ran a WebGL fragment shader (or a ping-pong of two textures); here the same maths runs in Metal.
// One full-screen triangle, the fragment shader does the work, and a scene object keeps the textures between frames.
// Texture space is top-left origin everywhere (the pages' v_uv was bottom-left, so the display shaders flip y once).

// MARK: - The device

@MainActor enum LabGPU {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    static let queue: MTLCommandQueue? = device?.makeCommandQueue()
    private static var libs: [String: MTLLibrary] = [:]
    private static var psos: [String: MTLRenderPipelineState] = [:]
    nonisolated(unsafe) static var lastError: String?

    /// Shared opening of every shader here: the triangle, and three samplers.
    static let preamble = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 pos [[position]]; float2 uv; };
    vertex VOut vs_main(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(p.x, 1.0 - p.y); return o;
    }
    constexpr sampler sN(filter::nearest, address::repeat);
    constexpr sampler sNC(filter::nearest, address::clamp_to_edge);
    constexpr sampler sL(filter::linear, address::clamp_to_edge);
    static inline float h_rand(float2 uv) { return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453); }
    static inline float h_noise(float2 uv) {
        float2 i = floor(uv); float2 f = fract(uv);
        float a = h_rand(i); float b = h_rand(i + float2(1.0, 0.0)); float c = h_rand(i + float2(0.0, 1.0)); float d = h_rand(i + float2(1.0, 1.0));
        float2 u2 = f * f * (3.0 - 2.0 * f);
        return mix(a, b, u2.x) + (c - a) * u2.y * (1.0 - u2.x) + (d - b) * u2.x * u2.y;
    }
    """

    static func library(_ key: String, _ body: String) -> MTLLibrary? {
        if let l = libs[key] { return l }
        guard let device else { return nil }
        do {
            let o = MTLCompileOptions()
            o.mathMode = .safe   // the hashes lean on sin() of large numbers
            let l = try device.makeLibrary(source: preamble + "\n" + body, options: o)
            libs[key] = l
            return l
        } catch {
            lastError = "\(key): \(error.localizedDescription)"
            return nil
        }
    }

    static func pipeline(_ lib: MTLLibrary, _ fragment: String, format: MTLPixelFormat, blend: Bool = false, key: String, vertex: String = "vs_main") -> MTLRenderPipelineState? {
        let k = "\(key)/\(fragment)/\(format.rawValue)/\(blend)/\(vertex)"
        if let p = psos[k] { return p }
        guard let device, let v = lib.makeFunction(name: vertex), let f = lib.makeFunction(name: fragment) else { lastError = "\(key): no function \(fragment)"; return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = v; d.fragmentFunction = f
        d.colorAttachments[0].pixelFormat = format
        if blend {
            let c = d.colorAttachments[0]!
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do { let p = try device.makeRenderPipelineState(descriptor: d); psos[k] = p; return p }
        catch { lastError = "\(key): \(error.localizedDescription)"; return nil }
    }

    static func texture(_ w: Int, _ h: Int, _ format: MTLPixelFormat) -> MTLTexture? {
        guard let device else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }

    /// The page ground, for a lab that has nothing to draw yet.
    static func clear(_ cb: MTLCommandBuffer, _ target: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    /// One full-screen pass into `target` (or cleared first). `params` arrive as `constant float *U` at buffer 0.
    static func run(_ cb: MTLCommandBuffer, _ pso: MTLRenderPipelineState, target: MTLTexture, textures: [MTLTexture?] = [], params: [Float] = [0], clear: MTLClearColor? = nil) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        if let clear { pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].clearColor = clear } else { pass.colorAttachments[0].loadAction = .dontCare }
        pass.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        e.setRenderPipelineState(pso)
        var p = params
        e.setFragmentBytes(&p, length: MemoryLayout<Float>.stride * p.count, index: 0)
        for (i, t) in textures.enumerated() { if let t { e.setFragmentTexture(t, index: i) } }
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
    }
}

/// Two textures that trade places each pass.
@MainActor final class LabPingPong {
    var read: MTLTexture
    var write: MTLTexture
    init?(_ w: Int, _ h: Int, _ f: MTLPixelFormat) {
        guard let a = LabGPU.texture(w, h, f), let b = LabGPU.texture(w, h, f) else { return nil }
        read = a; write = b
    }
    func swap() { let t = read; read = write; write = t }
}

// MARK: - The host

@MainActor protocol LabMetalScene: AnyObject {
    /// Encode this frame into the drawable (or do nothing). The host presents and commits.
    func frame(_ view: MTKView, _ cb: MTLCommandBuffer, _ target: MTLTexture)
    /// A finger, in 0...1 of the view, y from the top; nil when it lifts.
    func touch(_ p: CGPoint?, size: CGSize)
    /// A scene that only needs to be drawn once (Reduce Motion) pauses the view.
    var paused: Bool { get }
}
extension LabMetalScene {
    func touch(_ p: CGPoint?, size: CGSize) {}
    var paused: Bool { false }
}

struct LabMetalView: View {
    let scene: LabMetalScene
    var body: some View {
        GeometryReader { geo in
            LabMetalRep(scene: scene)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in scene.touch(CGPoint(x: v.location.x / max(1, geo.size.width), y: v.location.y / max(1, geo.size.height)), size: geo.size) }
                    .onEnded { _ in scene.touch(nil, size: geo.size) })
        }
        .background(Color.black)
    }
}

private struct LabMetalRep: UIViewRepresentable {
    let scene: LabMetalScene
    func makeCoordinator() -> Coord { Coord(scene) }
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: LabGPU.device)
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = true
        v.preferredFramesPerSecond = 60
        v.isOpaque = true
        v.backgroundColor = .black
        v.delegate = context.coordinator
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        return v
    }
    func updateUIView(_ v: MTKView, context: Context) {}

    @MainActor final class Coord: NSObject, MTKViewDelegate {
        let scene: LabMetalScene
        init(_ s: LabMetalScene) { scene = s }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable, let cb = LabGPU.queue?.makeCommandBuffer() else { return }
            scene.frame(view, cb, drawable.texture)
            cb.present(drawable)
            cb.commit()
            if scene.paused { view.isPaused = true }
        }
    }
}

/// When the GPU is missing or a shader would not compile, the lab says so in one line over the ground (never a blank screen).
struct LabGPUMissing: View {
    var body: some View {
        ContentUnavailableView("This one needs the GPU", systemImage: "cpu", description: Text(LabGPU.lastError ?? "Metal is not available on this device."))
            .foregroundStyle(PLG.gold)
    }
}

func labReduceMotion() -> Bool { UIAccessibility.isReduceMotionEnabled }

// MARK: - Single-pass fragment labs (Warp, Glitch, the Engine)

@MainActor final class LabFragmentScene: LabMetalScene {
    let lib: MTLLibrary
    let fragment: String
    let key: String
    let still: Double?
    let start = CACurrentMediaTime()
    init?(key: String, source: String, fragment: String, still: Double? = nil) {
        guard let l = LabGPU.library(key, source) else { return nil }
        lib = l; self.fragment = fragment; self.key = key; self.still = still
    }
    var paused: Bool { still != nil }
    func frame(_ view: MTKView, _ cb: MTLCommandBuffer, _ target: MTLTexture) {
        guard let pso = LabGPU.pipeline(lib, fragment, format: target.pixelFormat, key: key) else { return }
        let t = Float(still ?? (CACurrentMediaTime() - start))
        LabGPU.run(cb, pso, target: target, params: [t, Float(target.width), Float(target.height)])
    }
}

private let warpSource = """
static inline float3 hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
fragment float4 fs_warp(VOut in [[stage_in]], constant float *U [[buffer(0)]]) {
    float t = U[0];
    float2 v_uv = float2(in.uv.x, 1.0 - in.uv.y);
    float2 uv = v_uv;
    uv += 0.018 * sin(t * 0.4 + v_uv.yx * 5.0);
    uv += 0.010 * sin(t * 0.7 + v_uv * 12.0 + 1.3);
    uv += 0.006 * sin(t * 1.1 + v_uv.yx * 20.0 + 2.7);
    float hue = 0.1194 + 0.018 * sin(t * 0.25 + uv.x * 4.0 + uv.y * 2.0);
    float sat = 0.62 + 0.10 * sin(t * 0.4 + uv.y * 6.0);
    float val = 0.30 + 0.45 * (uv.y + 0.2 * sin(t * 0.3 + uv.x * 8.0));
    val = clamp(val, 0.0, 1.0);
    float vig = 1.0 - 0.5 * pow(length(v_uv - 0.5) * 1.6, 2.0);
    val *= vig;
    return float4(hsvToRgb(float3(hue, sat, val)), 1.0);
}
"""

private let glitchSource = """
static inline float3 baseImage(float2 uv, float t) {
    float n = h_noise(uv * 3.0 + t * 0.1);
    float wave = sin(uv.y * 12.0 + t * 0.5 + n * 4.0) * 0.5 + 0.5;
    float3 gold = float3(0.788, 0.659, 0.298);
    float3 voidc = float3(0.039, 0.039, 0.039);
    return mix(voidc, gold, wave * 0.6);
}
fragment float4 fs_glitch(VOut in [[stage_in]], constant float *U [[buffer(0)]]) {
    float t = U[0];
    float2 v_uv = float2(in.uv.x, 1.0 - in.uv.y);
    float band = floor(v_uv.y * 40.0);
    float bandNoise = h_rand(float2(band, floor(t * 8.0)));
    float glitchStrength = step(0.92, bandNoise);
    float blockOffset = (h_rand(float2(band * 13.7, t * 3.0)) - 0.5) * 0.08 * glitchStrength;
    float aberration = h_noise(float2(v_uv.y * 20.0, t * 2.0)) * 0.006 * (0.5 + glitchStrength);
    float2 uvR = float2(v_uv.x + blockOffset + aberration, v_uv.y);
    float2 uvG = float2(v_uv.x + blockOffset, v_uv.y);
    float2 uvB = float2(v_uv.x + blockOffset - aberration, v_uv.y);
    float r = baseImage(uvR, t).r;
    float g = baseImage(uvG, t).g;
    float b = baseImage(uvB, t).b;
    float flashBand = floor(v_uv.y * 80.0);
    float flash = step(0.995, h_rand(float2(flashBand, floor(t * 15.0))));
    float3 col = float3(r, g, b);
    col = mix(col, float3(0.788, 0.659, 0.298), flash * 0.7);
    return float4(col, 1.0);
}
"""

private let engineSource = """
static inline float3 hsl2rgb(float h, float s, float l) {
    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    float h6 = fract(h) * 6.0;
    float x = c * (1.0 - abs(fmod(h6, 2.0) - 1.0));
    float m = l - c * 0.5;
    float3 rgb = float3(0.0);
    if (h6 < 1.0) { rgb = float3(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = float3(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = float3(0.0, c, x); }
    else if (h6 < 4.0) { rgb = float3(0.0, x, c); }
    else if (h6 < 5.0) { rgb = float3(x, 0.0, c); }
    else { rgb = float3(c, 0.0, x); }
    return rgb + m;
}
fragment float4 fs_engine(VOut in [[stage_in]], constant float *U [[buffer(0)]]) {
    float t = U[0];
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float hue = 0.10 + 0.04 * sin(t * 0.3 + uv.x * 3.14159);
    float sat = 0.85 + 0.1 * sin(t * 0.5 + uv.y * 6.28318);
    float lit = 0.35 + 0.25 * uv.y + 0.05 * sin(t * 0.7 + uv.x * 6.28318);
    return float4(hsl2rgb(hue, sat, lit), 1.0);
}
"""

struct LabWarpView: View {
    @State private var scene = LabFragmentScene(key: "warp", source: warpSource, fragment: "fs_warp", still: labReduceMotion() ? 6.0 : nil)
    var body: some View { if let scene { LabMetalView(scene: scene) } else { LabGPUMissing() } }
}

struct LabGlitchView: View {
    @State private var scene = LabFragmentScene(key: "glitch", source: glitchSource, fragment: "fs_glitch", still: labReduceMotion() ? 0 : nil)
    var body: some View { if let scene { LabMetalView(scene: scene) } else { LabGPUMissing() } }
}

/// The Engine: the web page probed WebGPU and drew a WGSL gradient. Here it is Metal: the same gradient, and the lines the
/// page printed (adapter, limits, features) read off this phone's own GPU.
struct LabMetalProbeView: View {
    @State private var scene = LabFragmentScene(key: "engine", source: engineSource, fragment: "fs_engine")
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let scene { LabMetalView(scene: scene) } else { LabGPUMissing() }
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Self.lines(), id: \.0) { l in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(l.0 + ":").foregroundStyle(PLG.gold.opacity(0.55))
                        Text(l.1).foregroundStyle(PLG.gold).multilineTextAlignment(.trailing)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(.top, 56).padding(.trailing, 18)
            .shadow(color: .black.opacity(0.85), radius: 4)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }

    static func lines() -> [(String, String)] {
        guard let d = LabGPU.device else { return [("device", "Metal is not available")] }
        var fams: [String] = []
        let all: [(MTLGPUFamily, String)] = [(.apple4, "apple4"), (.apple5, "apple5"), (.apple6, "apple6"), (.apple7, "apple7"), (.apple8, "apple8"), (.apple9, "apple9"), (.metal3, "metal3"), (.metal4, "metal4")]
        for (f, n) in all where d.supportsFamily(f) { fams.append(n) }
        let mb = { (b: UInt64) in ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }
        return [
            ("description", d.name),
            ("architecture", d.architecture.name),
            ("families", fams.joined(separator: " ")),
            ("maxBufferLength", mb(UInt64(d.maxBufferLength))),
            ("recommendedWorkingSet", mb(d.recommendedMaxWorkingSetSize)),
            ("maxThreadsPerThreadgroup", "\(d.maxThreadsPerThreadgroup.width) x \(d.maxThreadsPerThreadgroup.height) x \(d.maxThreadsPerThreadgroup.depth)"),
            ("unifiedMemory", d.hasUnifiedMemory ? "yes" : "no"),
            ("rendering", "Metal fragment shader, live on the GPU"),
        ]
    }
}

// MARK: - Reaction diffusion (Gray-Scott, the Seed)

private let reactionSource = """
fragment float4 fs_rd_update(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> st [[texture(0)]]) {
    float2 res = float2(U[0], U[1]); float F = U[2]; float K = U[3];
    float2 px = 1.0 / res;
    float2 uv = in.uv;
    float4 c = st.sample(sNC, uv);
    float u = c.r; float v = c.g;
    float4 n = st.sample(sNC, uv + float2(0.0, px.y));
    float4 s = st.sample(sNC, uv - float2(0.0, px.y));
    float4 e = st.sample(sNC, uv + float2(px.x, 0.0));
    float4 w = st.sample(sNC, uv - float2(px.x, 0.0));
    float lapU = n.r + s.r + e.r + w.r - 4.0 * u;
    float lapV = n.g + s.g + e.g + w.g - 4.0 * v;
    float uvv = u * v * v;
    float du = 0.2100 * lapU - uvv + F * (1.0 - u);
    float dv = 0.1050 * lapV + uvv - (F + K) * v;
    return float4(clamp(u + du, 0.0, 1.0), clamp(v + dv, 0.0, 1.0), 0.0, 1.0);
}
fragment float4 fs_rd_show(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> st [[texture(0)]]) {
    float u = st.sample(sNC, in.uv).r;
    float3 obsidian = float3(0.039, 0.039, 0.039);
    float3 gold = float3(0.788, 0.659, 0.298);
    float3 col = mix(gold, obsidian, smoothstep(0.2, 0.7, u));
    return float4(col, 1.0);
}
"""

@MainActor final class LabReactionScene: LabMetalScene {
    static let sim = 512
    let lib: MTLLibrary
    let state: LabPingPong
    let reduce = labReduceMotion()
    var settled = false
    init?() {
        guard let l = LabGPU.library("reaction", reactionSource), let s = LabPingPong(Self.sim, Self.sim, .rgba32Float) else { return nil }
        lib = l; state = s
        let n = Self.sim
        var data = [Float](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) { data[i * 4] = 1; data[i * 4 + 3] = 1 }
        for _ in 0..<5 {
            let cx = 80 + Int.random(in: 0..<(n - 160)), cy = 80 + Int.random(in: 0..<(n - 160))
            for dy in -10..<10 { for dx in -10..<10 { let k = ((cy + dy) * n + (cx + dx)) * 4; data[k] = 0; data[k + 1] = 1 } }
        }
        data.withUnsafeBytes { s.read.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: n * 16) }
    }
    var paused: Bool { settled }
    func frame(_ view: MTKView, _ cb: MTLCommandBuffer, _ target: MTLTexture) {
        guard let up = LabGPU.pipeline(lib, "fs_rd_update", format: .rgba32Float, key: "reaction"),
              let show = LabGPU.pipeline(lib, "fs_rd_show", format: target.pixelFormat, key: "reaction") else { return }
        let n = Float(Self.sim)
        let steps = reduce ? 2500 : 8
        for _ in 0..<steps {
            LabGPU.run(cb, up, target: state.write, textures: [state.read], params: [n, n, 0.037, 0.060])
            state.swap()
        }
        LabGPU.run(cb, show, target: target, textures: [state.read])
        if reduce { settled = true }
    }
}

struct LabReactionView: View {
    @State private var scene = LabReactionScene()
    var body: some View { if let scene { LabMetalView(scene: scene) } else { LabGPUMissing() } }
}

// MARK: - Life (the Company): Conway on a torus, the rule driven by the envelope

private let lifeSource = """
static inline float cellAt(texture2d<float> st, float2 uv) { return step(0.5, st.sample(sN, uv).r); }
fragment float4 fs_life_update(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> st [[texture(0)]]) {
    float2 res = float2(U[0], U[1]); float sLo = U[2]; float sHi = U[3]; float b6 = U[4];
    float3 spark = float3(U[5], U[6], U[7]); float seed = U[8];
    float2 px = 1.0 / res;
    float2 uv = in.uv;
    float n = 0.0;
    n += cellAt(st, uv + float2(-px.x, -px.y));
    n += cellAt(st, uv + float2(0.0, -px.y));
    n += cellAt(st, uv + float2(px.x, -px.y));
    n += cellAt(st, uv + float2(-px.x, 0.0));
    n += cellAt(st, uv + float2(px.x, 0.0));
    n += cellAt(st, uv + float2(-px.x, px.y));
    n += cellAt(st, uv + float2(0.0, px.y));
    n += cellAt(st, uv + float2(px.x, px.y));
    float4 c = st.sample(sN, uv);
    float me = step(0.5, c.r);
    float survives = step(sLo - 0.5, n) * step(n, sHi + 0.5);
    float born = step(2.5, n) * step(n, 3.5);
    born = max(born, b6 * step(5.5, n) * step(n, 6.5));
    float next = mix(born, survives, me);
    float2 d = uv - spark.xy;
    float inSpark = step(dot(d, d), spark.z * spark.z) * step(0.0001, spark.z);
    next = mix(next, step(0.62, h_rand(uv * res + seed)), inSpark);
    float age = next > 0.5 ? min(1.0, c.g + 0.14) : c.g * 0.72;
    return float4(next, age, 0.0, 1.0);
}
fragment float4 fs_life_show(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> st [[texture(0)]]) {
    float e = U[0];
    float4 s = st.sample(sN, in.uv);
    float live = step(0.5, s.r);
    float3 obsidian = float3(0.039, 0.039, 0.039);
    float3 gold = float3(0.788, 0.659, 0.298);
    float3 hi = float3(0.906, 0.812, 0.522);
    float3 col = mix(obsidian, gold * 0.28, s.g);
    col = mix(col, mix(gold, hi, e), live);
    return float4(col, 1.0);
}
"""

@MainActor @Observable final class LabLifeScene: LabMetalScene {
    static let sim = 256
    let lib: MTLLibrary
    let state: LabPingPong
    let start = CACurrentMediaTime()
    @ObservationIgnored var acc = 0.0
    let reduce = labReduceMotion()
    @ObservationIgnored var settled = false
    var rule = "B3 / S23"
    var source = "lfo"   // lfo, deck, mic

    init?() {
        guard let l = LabGPU.library("life", lifeSource), let s = LabPingPong(Self.sim, Self.sim, .rgba8Unorm) else { return nil }
        lib = l; state = s
        let n = Self.sim
        var data = [UInt8](repeating: 0, count: n * n * 4)
        var seed: UInt32 = 0x5EED11FE
        func rnd() -> Double {   // mulberry32: the page's seed, so it opens the same way
            seed = seed &+ 0x6D2B79F5
            var t = (seed ^ (seed >> 15)) &* (1 | seed)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
        for i in 0..<(n * n) {
            let y = Double(i / n)
            let d = 0.05 + 0.16 * (0.5 + 0.5 * sin(y * 0.055))
            data[i * 4] = rnd() < d ? 255 : 0
            data[i * 4 + 3] = 255
        }
        let glider = [(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)]
        for _ in 0..<6 {
            let cx = Int(rnd() * Double(n - 8)) + 2, cy = Int(rnd() * Double(n - 8)) + 2
            for (dx, dy) in glider { data[((cy + dy) * n + (cx + dx)) * 4] = 255 }
        }
        data.withUnsafeBytes { s.read.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: n * 4) }
    }

    /// The envelope: the deck or mic when VJAudio has a source, else an 11 s sweep that never idles at full Maze.
    func envelope() -> (e: Double, beat: Bool, from: String) {
        if VJAudio.shared.source != .off {
            let b = VJAudio.shared.read()
            let from: String
            if case .mic = VJAudio.shared.source { from = "mic" } else { from = "deck" }
            return (min(1, b.bass * 0.7 + b.mid * 0.3), b.beat, from)
        }
        let t = CACurrentMediaTime() - start
        return ((0.5 - 0.5 * cos(t * 0.57)) * 0.65, false, "lfo")
    }

    var paused: Bool { settled }
    func frame(_ view: MTKView, _ cb: MTLCommandBuffer, _ target: MTLTexture) {
        guard let up = LabGPU.pipeline(lib, "fs_life_update", format: .rgba8Unorm, key: "life"),
              let show = LabGPU.pipeline(lib, "fs_life_show", format: target.pixelFormat, key: "life") else { return }
        let n = Float(Self.sim)
        func gen(_ sLo: Float, _ sHi: Float, _ b6: Float, _ spark: (Float, Float, Float)) {
            LabGPU.run(cb, up, target: state.write, textures: [state.read], params: [n, n, sLo, sHi, b6, spark.0, spark.1, spark.2, Float.random(in: 0..<1000)])
            state.swap()
        }
        if reduce {
            for _ in 0..<120 { gen(2, 3, 0, (0, 0, 0)) }
            LabGPU.run(cb, show, target: target, textures: [state.read], params: [0.1])
            settled = true
            if rule != "B3 / S2–3" { rule = "B3 / S2–3" }
            return
        }
        let (e, beat, from) = envelope()
        let sLo: Float = e > 0.55 ? 1 : 2
        let sHi = Float(3 + Int(min(e, 0.999) * 3))
        let b6: Float = beat ? 1 : 0
        let spark: (Float, Float, Float) = beat ? (Float.random(in: 0..<1), Float.random(in: 0..<1), 0.05) : (0, 0, 0)
        acc = min(acc + 0.10 + e * 0.85, 4)
        var steps = 0
        while acc >= 1 && steps < 4 { acc -= 1; gen(sLo, sHi, b6, steps == 0 ? spark : (0, 0, 0)); steps += 1 }
        LabGPU.run(cb, show, target: target, textures: [state.read], params: [Float(e)])
        let r = "B\(b6 > 0 ? "36" : "3") / S\(Int(sLo))–\(Int(sHi))"
        if r != rule { rule = r }
        if from != source { source = from }
    }
}

struct LabLifeView: View {
    @State private var scene = LabLifeScene()
    @State private var micLine: String?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let scene {
                LabMetalView(scene: scene)
                LinearGradient(colors: [.clear, Color(hex: 0x0a0a0a).opacity(0.88)], startPoint: .init(x: 0.5, y: 0.66), endPoint: .bottom).allowsHitTesting(false)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(scene.rule).font(.system(size: 11, design: .serif)).labCaps().tracking(2).foregroundStyle(PLG.gold.opacity(0.72)).contentTransition(.numericText())
                    if scene.source != "mic" {
                        LabPill(title: scene.source == "deck" ? "deck" : "listen", symbol: "mic") { Task { await listen() } }
                    }
                    if let micLine { Text(micLine).font(.caption2).foregroundStyle(PLG.gold.opacity(0.7)).multilineTextAlignment(.trailing).frame(maxWidth: 220, alignment: .trailing) }
                }
                .padding(12)
                .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x0e0c08).opacity(0.82)).overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(PLG.gold.opacity(0.28), lineWidth: 0.8) } }
                .padding(.top, 54).padding(.trailing, 14)
            } else { LabGPUMissing() }
        }
        .onDisappear { if VJAudio.shared.source == .mic { VJAudio.shared.stop() } }
    }

    private func listen() async {
        do { try await VJAudio.shared.startMic(); micLine = nil }
        catch { micLine = (error as? LocalizedError)?.errorDescription ?? "The mic did not start. The sweep keeps the piece running." }
    }
}

// MARK: - Fluid (the stirred field): gold ink on bone, advected and projected on the GPU

private let fluidSource = """
fragment float4 fs_advect_vel(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> vel [[texture(0)]]) {
    float2 texel = float2(U[0], U[1]); float dt = U[2]; float dis = U[3];
    float2 v = vel.sample(sL, in.uv).xy;
    float2 coord = in.uv - dt * v * texel;
    float2 adv = vel.sample(sL, coord).xy;
    return float4(adv * dis, 0.0, 1.0);
}
fragment float4 fs_advect_dye(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> vel [[texture(0)]], texture2d<float> dye [[texture(1)]]) {
    float2 texel = float2(U[0], U[1]); float dt = U[2]; float dis = U[3];
    float2 v = vel.sample(sL, in.uv).xy;
    float2 coord = in.uv - dt * v * texel;
    float d = dye.sample(sL, coord).r;
    return float4(d * dis, 0.0, 0.0, 1.0);
}
fragment float4 fs_divergence(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> vel [[texture(0)]]) {
    float2 texel = float2(U[0], U[1]);
    float l = vel.sample(sL, in.uv - float2(texel.x, 0.0)).x;
    float r = vel.sample(sL, in.uv + float2(texel.x, 0.0)).x;
    float b = vel.sample(sL, in.uv - float2(0.0, texel.y)).y;
    float t = vel.sample(sL, in.uv + float2(0.0, texel.y)).y;
    return float4(0.5 * (r - l + t - b), 0.0, 0.0, 1.0);
}
fragment float4 fs_pressure(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> pr [[texture(0)]], texture2d<float> dv [[texture(1)]]) {
    float2 texel = float2(U[0], U[1]);
    float l = pr.sample(sL, in.uv - float2(texel.x, 0.0)).x;
    float r = pr.sample(sL, in.uv + float2(texel.x, 0.0)).x;
    float b = pr.sample(sL, in.uv - float2(0.0, texel.y)).x;
    float t = pr.sample(sL, in.uv + float2(0.0, texel.y)).x;
    float d = dv.sample(sL, in.uv).x;
    return float4((l + r + b + t - d) * 0.25, 0.0, 0.0, 1.0);
}
fragment float4 fs_gradient(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> pr [[texture(0)]], texture2d<float> vel [[texture(1)]]) {
    float2 texel = float2(U[0], U[1]);
    float l = pr.sample(sL, in.uv - float2(texel.x, 0.0)).x;
    float r = pr.sample(sL, in.uv + float2(texel.x, 0.0)).x;
    float b = pr.sample(sL, in.uv - float2(0.0, texel.y)).x;
    float t = pr.sample(sL, in.uv + float2(0.0, texel.y)).x;
    float2 v = vel.sample(sL, in.uv).xy;
    v -= 0.5 * float2(r - l, t - b);
    return float4(v, 0.0, 1.0);
}
fragment float4 fs_splat(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> tg [[texture(0)]]) {
    float2 pt = float2(U[0], U[1]); float3 value = float3(U[2], U[3], U[4]); float radius = U[5]; float aspect = U[6];
    float2 p = in.uv - pt;
    p.x *= aspect;
    float f = exp(-dot(p, p) / radius);
    float3 base = tg.sample(sL, in.uv).xyz;
    return float4(base + f * value, 1.0);
}
fragment float4 fs_fluid_show(VOut in [[stage_in]], constant float *U [[buffer(0)]], texture2d<float> dye [[texture(0)]]) {
    float intensity = U[0];
    float d = dye.sample(sL, in.uv).r;
    d = smoothstep(0.02, 0.85, d);
    float a = d * 0.42 * intensity;
    float3 gold = float3(0.788, 0.659, 0.298);
    float3 col = gold * (0.82 + 0.18 * d);
    float3 bone = float3(0.945, 0.925, 0.882);
    return float4(col * a + bone * (1.0 - a), 1.0);
}
"""

@MainActor final class LabFluidScene: LabMetalScene {
    static let sim = 256
    let lib: MTLLibrary
    let vel: LabPingPong, dye: LabPingPong, pressure: LabPingPong
    let divergence: MTLTexture
    var pointer: (x: Float, y: Float, dx: Float, dy: Float)?
    var last: (x: Float, y: Float)?
    var aT = Float.random(in: 0..<1000)
    var aspect: Float = 0.46
    let reduce = labReduceMotion()
    var seeded = false

    init?() {
        guard let l = LabGPU.library("fluid", fluidSource), let v = LabPingPong(Self.sim, Self.sim, .rgba16Float), let d = LabPingPong(Self.sim, Self.sim, .rgba16Float),
              let p = LabPingPong(Self.sim, Self.sim, .rgba16Float), let dv = LabGPU.texture(Self.sim, Self.sim, .rgba16Float) else { return nil }
        lib = l; vel = v; dye = d; pressure = p; divergence = dv
    }

    var paused: Bool { reduce && seeded }

    func touch(_ p: CGPoint?, size: CGSize) {
        aspect = Float(size.width / max(1, size.height))
        guard let p else { last = nil; pointer = nil; return }
        let x = Float(p.x), y = Float(p.y)
        if let l = last { pointer = (x, y, x - l.x, y - l.y) }
        last = (x, y)
    }

    func frame(_ view: MTKView, _ cb: MTLCommandBuffer, _ target: MTLTexture) {
        let k = "fluid", f = MTLPixelFormat.rgba16Float
        guard let pAV = LabGPU.pipeline(lib, "fs_advect_vel", format: f, key: k), let pAD = LabGPU.pipeline(lib, "fs_advect_dye", format: f, key: k),
              let pDiv = LabGPU.pipeline(lib, "fs_divergence", format: f, key: k), let pPr = LabGPU.pipeline(lib, "fs_pressure", format: f, key: k),
              let pGr = LabGPU.pipeline(lib, "fs_gradient", format: f, key: k), let pSp = LabGPU.pipeline(lib, "fs_splat", format: f, key: k),
              let pShow = LabGPU.pipeline(lib, "fs_fluid_show", format: target.pixelFormat, key: k) else { return }
        let texel = 1 / Float(Self.sim)

        func splat(_ t: LabPingPong, _ x: Float, _ y: Float, _ vx: Float, _ vy: Float, _ vz: Float, _ radius: Float) {
            LabGPU.run(cb, pSp, target: t.write, textures: [t.read], params: [x, y, vx, vy, vz, radius, aspect])
            t.swap()
        }
        func ambient(_ strength: Float) {
            aT += 0.006
            let ax = 0.5 + 0.32 * sin(aT * 0.7) * cos(aT * 0.31)
            let ay = 0.5 + 0.28 * cos(aT * 0.53) * sin(aT * 0.23)
            splat(vel, ax, ay, cos(aT * 1.3) * 0.0009, sin(aT * 1.1) * 0.0009, 0, 0.0009)
            splat(dye, ax, ay, strength, 0, 0, 0.0012)
        }
        func step() {
            LabGPU.run(cb, pAV, target: vel.write, textures: [vel.read], params: [texel, texel, 1.0, 0.985]); vel.swap()
            LabGPU.run(cb, pDiv, target: divergence, textures: [vel.read], params: [texel, texel])
            for _ in 0..<14 { LabGPU.run(cb, pPr, target: pressure.write, textures: [pressure.read, divergence], params: [texel, texel]); pressure.swap() }
            LabGPU.run(cb, pGr, target: vel.write, textures: [pressure.read, vel.read], params: [texel, texel]); vel.swap()
            LabGPU.run(cb, pAD, target: dye.write, textures: [vel.read, dye.read], params: [texel, texel, 1.0, 0.992]); dye.swap()
        }

        if reduce {
            if !seeded { for _ in 0..<18 { ambient(0.05) }; for _ in 0..<24 { step() }; seeded = true }
        } else {
            if Bool.random() { ambient(0.025) }
            if let p = pointer {
                let speed = hypot(p.dx, p.dy)
                splat(vel, p.x, p.y, p.dx * 18, p.dy * 18, 0, 0.0016)
                splat(dye, p.x, p.y, min(0.22, 0.05 + speed * 9), 0, 0, 0.0016)
                pointer = nil
            }
            step()
        }
        LabGPU.run(cb, pShow, target: target, textures: [dye.read], params: [1])
    }
}

struct LabFluidView: View {
    @State private var scene = LabFluidScene()
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0xf1ece1).ignoresSafeArea()
            if let scene { LabMetalView(scene: scene) } else { LabGPUMissing() }
            VStack(alignment: .leading, spacing: 0) {
                Text("The Mirror · M1 — the stirred field").font(.system(size: 11, design: .serif)).labCaps().tracking(2.4).opacity(0.55)
                Text("What persists in the mind becomes your reality.").plHand(34, relativeTo: .largeTitle).lineSpacing(2).padding(.top, 10)
                Text("Move across the page. The cursor stirs a still pool of gold ink — the field remembers the path of the hand, then settles, then breathes. It is meant to be felt at the edge of attention, never to announce itself.")
                    .font(.system(size: 16, design: .serif)).lineSpacing(6).opacity(0.86).padding(.top, 14)
                Text("Prepared for luxury. You are in control of your reality. Drag slowly to draw a thin gold thread; move fast to open a wider, softer bloom that closes again on its own.")
                    .font(.system(size: 16, design: .serif)).lineSpacing(6).opacity(0.86).padding(.top, 14)
                HStack(spacing: 10) { Text("Restraint"); Text("·"); Text("Breath"); Text("·"); Text("Gold on bone") }
                    .font(.system(size: 13, design: .serif)).opacity(0.6).padding(.top, 24)
            }
            .foregroundStyle(Color(hex: 0x161310))
            .padding(.horizontal, 24).padding(.top, 70)
            .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
    }
}
