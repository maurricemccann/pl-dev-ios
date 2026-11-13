import Foundation
import Metal

// The shader pieces (`shaderPiece({frag})`: goldfog, plasma, tunnel, oil, prism, and any a Forge run adds).
// The piece file hands over a GLSL fragment; `GLSLtoMSL` turns it into a Metal fragment shader with the same uniforms
// (u_time, u_res, u_bass, u_mid, u_high, u_beat, u_gold, u_ink, u_bg), the pass renders into a texture, and the pixels
// land in the piece's canvas, which the piece then draws with `drawImage` exactly as it does in the browser.

enum GLSLtoMSL {
    /// Limits of this translator (the frag is the five house shaders and what Forge writes in the same dialect):
    /// the uniforms are locals of `main`, so a helper function that reads `u_*` directly will not compile and the piece shows its ground.
    static func translate(_ frag: String) -> String? {
        var src = frag
        src = src.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
        src = src.replacingOccurrences(of: #"//[^\n]*"#, with: " ", options: .regularExpression)
        src = src.replacingOccurrences(of: #"precision\s+\w+\s+\w+\s*;"#, with: "", options: .regularExpression)
        src = src.replacingOccurrences(of: #"uniform\s+[^;]*;"#, with: "", options: .regularExpression)
        for (from, to) in [("vec2", "float2"), ("vec3", "float3"), ("vec4", "float4"), ("mat2", "float2x2"), ("mat3", "float3x3"), ("mat4", "float4x4"), ("ivec2", "int2"), ("bvec2", "bool2")] {
            src = src.replacingOccurrences(of: "\\b\(from)\\b", with: to, options: .regularExpression)
        }
        // split out `void main() { ... }` by brace matching
        guard let mainRange = src.range(of: #"void\s+main\s*\(\s*(void)?\s*\)\s*\{"#, options: .regularExpression) else { return nil }
        let helpers = String(src[src.startIndex..<mainRange.lowerBound])
        var depth = 1
        var idx = mainRange.upperBound
        var bodyEnd: String.Index?
        while idx < src.endIndex {
            let ch = src[idx]
            if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1; if depth == 0 { bodyEnd = idx; break } }
            idx = src.index(after: idx)
        }
        guard let bodyEnd else { return nil }
        let body = String(src[mainRange.upperBound..<bodyEnd])
        return """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; };
        vertex VOut vs_main(uint vid [[vertex_id]]) {
            float2 p = float2(float((vid << 1) & 2), float(vid & 2));
            VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); return o;
        }
        static inline float mod(float x, float y) { return x - y * floor(x / y); }
        static inline float2 mod(float2 x, float y) { return x - y * floor(x / y); }
        static inline float3 mod(float3 x, float y) { return x - y * floor(x / y); }
        static inline float2 mod(float2 x, float2 y) { return x - y * floor(x / y); }
        static inline float3 mod(float3 x, float3 y) { return x - y * floor(x / y); }
        static inline float atan(float y, float x) { return atan2(y, x); }
        static inline float inversesqrt(float x) { return rsqrt(x); }
        \(helpers)
        fragment float4 fs_main(VOut in [[stage_in]], constant float *U [[buffer(0)]]) {
            float u_time = U[0]; float2 u_res = float2(U[1], U[2]);
            float u_bass = U[3]; float u_mid = U[4]; float u_high = U[5]; float u_beat = U[6];
            float3 u_gold = float3(U[7], U[8], U[9]); float3 u_ink = float3(U[10], U[11], U[12]); float3 u_bg = float3(U[13], U[14], U[15]);
            float4 gl_FragCoord = float4(in.pos.x, u_res.y - in.pos.y, in.pos.z, 1.0);
            float4 gl_FragColor = float4(0.0, 0.0, 0.0, 1.0);
            \(body)
            return gl_FragColor;
        }
        """
    }
}

final class ShaderRenderer: @unchecked Sendable {
    static let shared = ShaderRenderer()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var failed: Set<String> = []
    private var target: MTLTexture?

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
    }

    /// Renders `frag` at w x h into the surface's pixels. On any failure the surface is filled with the piece's ground colour (u[13...15]).
    func render(frag: String, uniforms u: [Double], w: Int, h: Int, into surface: CanvasSurface) {
        guard w > 1, h > 1, w == surface.w, h == surface.h, u.count >= 16 else { return }
        guard let device, let queue, let pso = pipeline(frag, device), let tex = texture(device, w, h) else { fillGround(surface, u); return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { fillGround(surface, u); return }
        var f = u.prefix(16).map { Float($0) }
        enc.setRenderPipelineState(pso)
        enc.setFragmentBytes(&f, length: MemoryLayout<Float>.stride * 16, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if cb.status != .completed { fillGround(surface, u); return }
        tex.getBytes(surface.data, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    }

    private func texture(_ device: MTLDevice, _ w: Int, _ h: Int) -> MTLTexture? {
        if let t = target, t.width == w, t.height == h { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        target = device.makeTexture(descriptor: d)
        return target
    }

    private func pipeline(_ frag: String, _ device: MTLDevice) -> MTLRenderPipelineState? {
        if let p = pipelines[frag] { return p }
        if failed.contains(frag) { return nil }
        guard let msl = GLSLtoMSL.translate(frag) else { failed.insert(frag); DebugBridge.note("shader: no main() in the fragment"); return nil }
        do {
            let opts = MTLCompileOptions()
            opts.mathMode = .safe   // the hash functions lean on sin() of large numbers; fast math would change the picture
            let lib = try device.makeLibrary(source: msl, options: opts)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "vs_main")
            d.fragmentFunction = lib.makeFunction(name: "fs_main")
            d.colorAttachments[0].pixelFormat = .rgba8Unorm
            let p = try device.makeRenderPipelineState(descriptor: d)
            pipelines[frag] = p
            return p
        } catch {
            failed.insert(frag)
            DebugBridge.note("shader: \(error.localizedDescription)")
            return nil
        }
    }

    private func fillGround(_ s: CanvasSurface, _ u: [Double]) {
        let r = UInt8(max(0, min(255, u[13] * 255))), g = UInt8(max(0, min(255, u[14] * 255))), b = UInt8(max(0, min(255, u[15] * 255)))
        let p = s.data.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(s.w * s.h) { p[i * 4] = r; p[i * 4 + 1] = g; p[i * 4 + 2] = b; p[i * 4 + 3] = 255 }
    }
}

/// Runtime notes (a failed shader compile, a script error) kept for the room's own debug line. Never shown as a sheet.
enum DebugBridge {
    nonisolated(unsafe) private(set) static var lines: [String] = []
    static func note(_ s: String) {
        lines.append(s)
        if lines.count > 60 { lines.removeFirst(lines.count - 60) }
    }
}
