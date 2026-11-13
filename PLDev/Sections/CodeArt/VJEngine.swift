import AVFoundation
import CoreGraphics
import Foundation
import Metal
import QuartzCore

// The VJ instrument's engine (the twin of the gallery's VJEngine.tsx and vj/VJEffects.ts): two decks of pieces drawn by the runtime,
// a Metal compositor (A under B, four blend modes, then the effect chain), audio-driven modulation, a beat grid, a step
// sequencer, auto-advance, SNAP and REC. Everything here runs on the runtime's one queue.

struct VJParams: Codable, Equatable, Sendable {
    static let fxIDs = ["zoom", "kaleido", "mirror", "pixelate", "glitch", "rgbshift", "strobe", "invert"]
    static let modParams = ["speed", "zoom", "tilt", "warm", "blend"]
    static let modSources = ["bass", "mid", "high", "beat", "lfo"]
    static let blendNames = ["Normal", "Add", "Screen", "Multiply"]

    var pieceA = ""
    var pieceB = ""
    var layerBOn = false
    var speed = 1.0, zoom = 1.0, tilt = 0.0, warm = 0.0, blend = 1.0
    var react = [1.0, 1.0, 1.0]            // bass, mid, high
    var layerBlend = 2, opacityB = 0.75
    var fx = [Double](repeating: 0, count: 8)
    var mod = [[Double]](repeating: [Double](repeating: 0, count: 5), count: 5)
    var bpm = 0.0
    var auto = false, autoEvery = 8
    var seqOn = false
    var seq = [String](repeating: "", count: 8)
    var slots = [String](repeating: "", count: 6)
    var includeArchive = false
}

/// The parameters the screen changes and the engine reads each frame.
final class VJShared: @unchecked Sendable {
    private let lock = NSLock()
    private var p = VJParams()
    func get() -> VJParams { lock.lock(); defer { lock.unlock() }; return p }
    func set(_ v: VJParams) { lock.lock(); p = v; lock.unlock() }
}

enum VJEvent: Sendable {
    case levels(bass: Double, mid: Double, high: Double, beat: Bool, playing: Bool)
    case piece(deck: Int, id: String, name: String)
    case seqStep(Int)
    case problem(String)
}

struct FXU {
    var opacityB: Float = 0
    var time: Float = 0
    var bass: Float = 0
    var blend: Int32 = 0
    var zoom: Float = 0, kaleido: Float = 0, mirror: Float = 0, pixelate: Float = 0, glitch: Float = 0, rgbshift: Float = 0, strobe: Float = 0, invert: Float = 0
    var hasB: Float = 0
    var pad0: Float = 0, pad1: Float = 0, pad2: Float = 0
}

// MARK: - the compositor

final class VJCompositor: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let fxPSO: MTLRenderPipelineState
    private let presentPSO: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private weak var layer: CAMetalLayer?
    private var texA: MTLTexture?, texB: MTLTexture?, out: MTLTexture?, hold: MTLTexture?
    private(set) var w = 0, h = 0

    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 pos [[position]]; float2 uv; };
    struct FXU { float opacityB; float time; float bass; int blend; float zoom; float kaleido; float mirror; float pixelate; float glitch; float rgbshift; float strobe; float invert; float hasB; float p0; float p1; float p2; };
    vertex VOut vj_vs(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(p.x, 1.0 - p.y); return o;
    }
    constant sampler smp(filter::linear, address::clamp_to_edge);
    static float hashf(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    static float3 blendModes(float3 a, float3 b, int mode) {
        if (mode == 1) return a + b;
        if (mode == 2) return 1.0 - (1.0 - a) * (1.0 - b);
        if (mode == 3) return a * b;
        return b;
    }
    static float3 compAt(float2 uv, texture2d<float> A, texture2d<float> B, constant FXU &u) {
        float3 a = A.sample(smp, uv).rgb;
        float3 b = B.sample(smp, uv).rgb;
        float3 over = blendModes(a, b, u.blend);
        return mix(a, over, clamp(u.opacityB, 0.0, 1.0));
    }
    fragment float4 vj_fx(VOut in [[stage_in]], texture2d<float> A [[texture(0)]], texture2d<float> B [[texture(1)]], constant FXU &u [[buffer(0)]]) {
        float2 c = float2(0.5);
        float2 uv = in.uv;
        if (u.zoom > 0.001) { float z = 1.0 - u.zoom * 0.55 * (0.6 + u.bass * 0.9); uv = (uv - c) * z + c; }
        if (u.kaleido > 0.001) {
            float2 p = uv - c; float r = length(p); float ang = atan2(p.y, p.x);
            float seg = mix(2.0, 8.0, u.kaleido); float sa = 3.14159265 / seg;
            float x = ang + sa; float y = 2.0 * sa;
            ang = abs((x - y * floor(x / y)) - sa);
            uv = c + float2(cos(ang), sin(ang)) * r;
        }
        if (u.mirror > 0.001) { uv.x = mix(uv.x, abs(uv.x - 0.5) + 0.5, u.mirror); }
        if (u.pixelate > 0.001) { float n = mix(512.0, 18.0, u.pixelate); uv = (floor(uv * n) + 0.5) / n; }
        if (u.glitch > 0.001) {
            float row = floor(uv.y * 48.0); float t = floor(u.time * 12.0); float n = hashf(float2(row, t));
            if (n > 1.0 - u.glitch * 0.6) uv.x += (hashf(float2(row, t + 1.0)) - 0.5) * u.glitch * 0.28;
        }
        float3 col;
        float rs = u.rgbshift + u.glitch * 0.4;
        if (rs > 0.001) {
            float2 o = float2(rs * 0.018 * (0.5 + u.bass), 0.0);
            col.r = compAt(clamp(uv + o, 0.0, 1.0), A, B, u).r;
            col.g = compAt(uv, A, B, u).g;
            col.b = compAt(clamp(uv - o, 0.0, 1.0), A, B, u).b;
        } else { col = compAt(uv, A, B, u); }
        if (u.strobe > 0.001) { float s = step(0.5, fract(u.time * mix(2.0, 16.0, u.strobe))); col = mix(col, col * s, u.strobe); }
        if (u.invert > 0.001) { col = mix(col, 1.0 - col, u.invert); }
        return float4(col, 1.0);
    }
    fragment float4 vj_present(VOut in [[stage_in]], texture2d<float> O [[texture(0)]], texture2d<float> H [[texture(1)]], constant float2 &u [[buffer(0)]]) {
        float3 col = mix(O.sample(smp, in.uv).rgb, H.sample(smp, in.uv).rgb, u.x) * u.y;
        return float4(col, 1.0);
    }
    """

    init?(layer: CAMetalLayer) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.layer = layer
        do {
            let lib = try device.makeLibrary(source: Self.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "vj_vs")
            d.fragmentFunction = lib.makeFunction(name: "vj_fx")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            fxPSO = try device.makeRenderPipelineState(descriptor: d)
            d.fragmentFunction = lib.makeFunction(name: "vj_present")
            presentPSO = try device.makeRenderPipelineState(descriptor: d)
        } catch { DebugBridge.note("vj compositor: \(error.localizedDescription)"); return nil }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        guard let s = device.makeSamplerState(descriptor: sd) else { return nil }
        sampler = s
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
    }

    private func tex(_ fmt: MTLPixelFormat, _ w: Int, _ h: Int, _ usage: MTLTextureUsage) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: false)
        d.usage = usage
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }

    func ensure(_ nw: Int, _ nh: Int) {
        if nw == w && nh == h && texA != nil { return }
        w = nw; h = nh
        texA = tex(.rgba8Unorm, nw, nh, .shaderRead)
        texB = tex(.rgba8Unorm, nw, nh, .shaderRead)
        out = tex(.bgra8Unorm, nw, nh, [.renderTarget, .shaderRead])
        hold = tex(.bgra8Unorm, nw, nh, [.shaderRead])
    }

    /// One frame: A (and B) into the effect chain, then to the screen. `holdAlpha` is the outgoing piece's dissolve; `capture` returns the frame as BGRA.
    func render(a: CanvasSurface?, b: CanvasSurface?, fx: FXU, holdAlpha: Float, brightness: Float, copyHold: Bool, capture: Bool) -> Data? {
        guard let texA, let texB, let out, let hold, let a, a.w == w, a.h == h else { return nil }
        texA.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: a.data, bytesPerRow: w * 4)
        var u = fx
        if let b, b.w == w, b.h == h { texB.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: b.data, bytesPerRow: w * 4); u.hasB = 1 } else { u.opacityB = 0; u.hasB = 0 }
        guard let cb = queue.makeCommandBuffer() else { return nil }
        if copyHold, let blit = cb.makeBlitCommandEncoder() {
            blit.copy(from: out, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1), to: hold, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }
        let p1 = MTLRenderPassDescriptor()
        p1.colorAttachments[0].texture = out
        p1.colorAttachments[0].loadAction = .dontCare
        p1.colorAttachments[0].storeAction = .store
        if let e = cb.makeRenderCommandEncoder(descriptor: p1) {
            e.setRenderPipelineState(fxPSO)
            e.setFragmentTexture(texA, index: 0)
            e.setFragmentTexture(texB, index: 1)
            e.setFragmentSamplerState(sampler, index: 0)
            e.setFragmentBytes(&u, length: MemoryLayout<FXU>.stride, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
        if let layer, let drawable = layer.nextDrawable() {
            let p2 = MTLRenderPassDescriptor()
            p2.colorAttachments[0].texture = drawable.texture
            p2.colorAttachments[0].loadAction = .dontCare
            p2.colorAttachments[0].storeAction = .store
            if let e = cb.makeRenderCommandEncoder(descriptor: p2) {
                var pu = SIMD2<Float>(holdAlpha, brightness)
                e.setRenderPipelineState(presentPSO)
                e.setFragmentTexture(out, index: 0)
                e.setFragmentTexture(hold, index: 1)
                e.setFragmentBytes(&pu, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                e.endEncoding()
            }
            cb.present(drawable)
        }
        cb.commit()
        guard capture else { return nil }
        cb.waitUntilCompleted()
        var bytes = Data(count: w * h * 4)
        bytes.withUnsafeMutableBytes { out.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
        return bytes
    }
}

// MARK: - recording

/// REC: the composited frames to an H.264 file, video only.
final class VJRecorder: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var started = false
    private var t0 = 0.0
    let url: URL
    private(set) var frames = 0

    init?(w: Int, h: Int) {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("pl-live-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)
        guard let wr = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                                       AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]]
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        inp.expectsMediaDataInRealTime = true
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        guard wr.canAdd(inp) else { return nil }
        wr.add(inp)
        writer = wr; input = inp; adaptor = ad
        if !wr.startWriting() { return nil }
    }

    func append(_ bgra: Data, w: Int, h: Int, now: Double) {
        if !started { writer.startSession(atSourceTime: .zero); started = true; t0 = now }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let stride = CVPixelBufferGetBytesPerRow(pb)
            bgra.withUnsafeBytes { src in
                for row in 0..<h { memcpy(base + row * stride, src.baseAddress! + row * w * 4, min(stride, w * 4)) }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        if adaptor.append(pb, withPresentationTime: CMTime(seconds: max(0, now - t0), preferredTimescale: 600)) { frames += 1 }
    }

    func finish() async -> URL? {
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}

// MARK: - the engine

final class VJEngine: @unchecked Sendable {
    private let rt = PieceRuntime.shared
    let shared = VJShared()
    private var comp: VJCompositor?
    private var pxW = 0, pxH = 0
    private var dpr = 2.0
    private var decks: [PieceInstance?] = [nil, nil]
    private var pending: [PieceInstance?] = [nil, nil]
    private var loading: [String] = ["", ""]
    private var frameAcc = [0.0, 0.0]
    private var prevBeat = false
    private var lastA = ""
    private var lastB = ""
    private var beatCount = 0
    private var seqPlayhead = 0
    private var holdStart = 0.0
    private var wantHold = false
    private var tickBusy = false
    private var t0 = CACurrentMediaTime()
    private var uiTick = 0
    private var snapWaiters: [@Sendable (Data?, Int, Int) -> Void] = []
    private var recorder: VJRecorder?
    private(set) var order: [String] = []
    var onEvent: (@Sendable (VJEvent) -> Void)?

    // MARK: setup (call on the main actor; each hops to the queue)

    func attach(layer: CAMetalLayer) {
        rt.queue.async { [self] in
            comp = VJCompositor(layer: layer)
            if comp == nil { onEvent?(.problem("The effects could not start on this device.")) }
        }
    }

    func setSize(pxW nw: Int, pxH nh: Int, dpr nd: Double) {
        rt.queue.async { [self] in
            guard nw > 1, nh > 1, nw != pxW || nh != pxH else { return }
            pxW = nw; pxH = nh; dpr = nd
            comp?.ensure(nw, nh)
            for i in 0..<2 { if let d = decks[i] { rt.resize(d, pxW: nw, pxH: nh, dpr: nd) } }
        }
    }

    func setOrder(_ ids: [String]) { rt.queue.async { [self] in order = ids } }

    func load(deck: Int, id: String) {
        guard deck == 0 || deck == 1, !id.isEmpty else { return }
        rt.queue.async { [self] in
            if decks[deck]?.info.id == id && pending[deck] == nil { return }
            if loading[deck] == id { return }
            let (w, h, d) = (pxW, pxH, dpr)
            guard w > 1 else { return }
            loading[deck] = id
            Task.detached { [self] in
                if let inst = await rt.makeInstance(id, pxW: w, pxH: h, dpr: d) {
                    rt.queue.async { [self] in pending[deck] = inst; loading[deck] = "" }
                } else { rt.queue.async { [self] in loading[deck] = ""; onEvent?(.problem("That piece would not start.")) } }
            }
        }
    }

    func clear(deck: Int) { rt.queue.async { [self] in decks[deck] = nil; pending[deck] = nil } }

    /// One frame at display rate; skipped while the last is still drawing.
    func kick() {
        rt.queue.async { [self] in
            if tickBusy { return }
            tickBusy = true
            tick()
            tickBusy = false
        }
    }

    func snap(_ done: @escaping @Sendable (Data?, Int, Int) -> Void) { rt.queue.async { [self] in snapWaiters.append(done) } }

    func startRecording() {
        rt.queue.async { [self] in
            guard recorder == nil, pxW > 1 else { return }
            recorder = VJRecorder(w: pxW, h: pxH)
            if recorder == nil { onEvent?(.problem("Recording could not start.")) }
        }
    }

    func stopRecording(_ done: @escaping @Sendable (URL?) -> Void) {
        rt.queue.async { [self] in
            guard let r = recorder else { done(nil); return }
            recorder = nil
            Task.detached { done(await r.finish()) }
        }
    }

    var isRecording: Bool { recorder != nil }

    // MARK: the frame

    private func tick() {
        let p = shared.get()
        let nowMs = CACurrentMediaTime() * 1000
        VJAudio.shared.setTapTempo(p.bpm)
        let audio = VJAudio.shared.read(now: nowMs)
        let source = VJAudio.shared.source
        let playing = VJAudio.shared.isPlaying && source != .off
        rt.pushAudio(audio)
        rt.pump()

        // a deck whose new piece is ready: warm it in slices, then swap it in with a dissolve
        for i in 0..<2 {
            if let inst = pending[i] {
                if inst.warmLeft > 0 { _ = rt.warm(inst, frames: 6) }
                if inst.warmLeft <= 0 {
                    decks[i] = inst
                    pending[i] = nil
                    frameAcc[i] = Double(inst.info.warm)
                    if i == 0 { wantHold = true; holdStart = nowMs }
                    onEvent?(.piece(deck: i, id: inst.info.id, name: inst.info.name))
                }
            }
        }
        // a piece the screen asked for (the knob changed), or a first piece when nothing is loaded yet
        if p.pieceA != lastA { lastA = p.pieceA; if !p.pieceA.isEmpty { load(deck: 0, id: p.pieceA) } }
        else if decks[0] == nil, pending[0] == nil, loading[0].isEmpty { let id = p.pieceA.isEmpty ? (order.first ?? "") : p.pieceA; if !id.isEmpty { load(deck: 0, id: id) } }
        if p.layerBOn {
            if p.pieceB != lastB { lastB = p.pieceB; if !p.pieceB.isEmpty { load(deck: 1, id: p.pieceB) } }
            else if decks[1] == nil, pending[1] == nil, loading[1].isEmpty, !p.pieceB.isEmpty { load(deck: 1, id: p.pieceB) }
        } else { if decks[1] != nil { decks[1] = nil }; pending[1] = nil; lastB = "" }

        // the beat grid: the sequencer takes the beat, else auto-advance
        let edge = audio.beat && !prevBeat
        prevBeat = audio.beat
        if edge {
            if p.seqOn {
                seqPlayhead = (seqPlayhead + 1) % p.seq.count
                let id = p.seq[seqPlayhead]
                if !id.isEmpty { load(deck: 0, id: id) }
                onEvent?(.seqStep(seqPlayhead))
            } else if p.auto, !order.isEmpty {
                beatCount += 1
                if beatCount >= p.autoEvery {
                    beatCount = 0
                    let cur = decks[0]?.info.id ?? ""
                    let i = order.firstIndex(of: cur) ?? -1
                    load(deck: 0, id: order[(i + 1) % order.count])
                }
            }
        }

        // modulation: bands, beat and a tempo-synced LFO routed to any knob, additive on its base
        let lfoBpm = p.bpm > 0 ? p.bpm : 120
        let phase = ((nowMs / 1000) * (lfoBpm / 60) / 4).truncatingRemainder(dividingBy: 1)
        let lfo = phase < 0.5 ? phase * 2 : 2 - phase * 2
        let srcs = [audio.bass, audio.mid, audio.high, audio.beat ? 1.0 : 0.0, lfo]
        func modOf(_ k: Int) -> Double { zip(p.mod[k], srcs).reduce(0) { $0 + $1.0 * $1.1 } }
        func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }
        let effSpeed = p.speed + modOf(0) * 2
        let effZoom = clamp(p.zoom + modOf(1) * 2, 0.3, 3.5)
        let effAngle = p.tilt + modOf(2) * 180
        let effWarm = p.warm + modOf(3)
        let effBlend = clamp(p.blend + modOf(4) * 0.9, 0.1, 1)
        let speed = (playing ? 0.4 + audio.bass * 2.6 * p.react[0] + audio.mid * 0.4 * p.react[1] + audio.high * 0.25 * p.react[2] : 1.0) * effSpeed
        let breathe = (playing && audio.bass > 0.01) ? 1 + audio.bass * 0.13 * p.react[0] + (audio.beat ? 0.06 : 0) : 1
        let audioWarm = playing && audio.mid > 0.10 ? min(audio.mid * 0.18 * p.react[1], 0.30) : 0
        let totalWarm = audioWarm + effWarm * 0.35

        for i in 0..<2 {
            guard let d = decks[i] else { continue }
            frameAcc[i] += speed
            rt.drawTransformed(d, frame: Int(frameAcc[i]), zoom: effZoom * breathe, angle: effAngle, alpha: i == 0 ? effBlend : 1, warm: i == 0 ? totalWarm : 0, beat: i == 0 && audio.beat)
        }
        rt.collectIfHeavy()

        // composite
        guard let comp, pxW > 1, let a = decks[0].flatMap({ rt.world.surface($0.canvasID) }) else { return }
        let b = decks[1].flatMap { rt.world.surface($0.canvasID) }
        var fx = FXU()
        fx.opacityB = Float(p.opacityB)
        fx.time = Float(nowMs / 1000)
        fx.bass = Float(audio.bass)
        fx.blend = Int32(p.layerBlend)
        fx.zoom = Float(p.fx[0]); fx.kaleido = Float(p.fx[1]); fx.mirror = Float(p.fx[2]); fx.pixelate = Float(p.fx[3])
        fx.glitch = Float(p.fx[4]); fx.rgbshift = Float(p.fx[5]); fx.strobe = Float(p.fx[6]); fx.invert = Float(p.fx[7])
        // the dissolve: the outgoing frame fades over 0.9 s (the browser's momentum-carry)
        var holdAlpha: Float = 0
        var copyHold = false
        if wantHold { copyHold = true; wantHold = false }
        else if holdStart > 0 { let t = (nowMs - holdStart) / 900; if t < 1 { holdAlpha = Float(1 - t) } else { holdStart = 0 } }
        if copyHold { holdAlpha = 1 }
        let brightness = Float(playing ? 1 + audio.bass * 0.30 * p.react[0] : 1)
        let capture = !snapWaiters.isEmpty || recorder != nil
        if let frame = comp.render(a: a, b: p.layerBOn ? b : nil, fx: fx, holdAlpha: holdAlpha, brightness: brightness, copyHold: copyHold, capture: capture) {
            if let r = recorder { r.append(frame, w: pxW, h: pxH, now: nowMs / 1000) }
            if !snapWaiters.isEmpty {
                let waiters = snapWaiters
                snapWaiters.removeAll()
                let (w, h) = (pxW, pxH)
                for s in waiters { s(frame, w, h) }
            }
        }
        uiTick += 1
        if uiTick % 4 == 0 { onEvent?(.levels(bass: audio.bass, mid: audio.mid, high: audio.high, beat: audio.beat, playing: playing)) }
    }
}
