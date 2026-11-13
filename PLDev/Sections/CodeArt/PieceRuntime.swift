import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
@preconcurrency import JavaScriptCore

// The code art runtime (his order 11-13: no web view). His piece bundles run unchanged in JavaScriptCore on one serial
// queue; the Canvas 2D calls they make arrive as a number stream (prelude.js) and are replayed on Core Graphics bitmaps
// (CanvasSurface.swift); `shaderPiece` fragments run as Metal passes (PieceShader.swift); audio comes from VJAudio.swift.
// Bundles are the gallery's public design assets (his ruling 11-13), fetched at run time and kept on the phone for offline.

struct PieceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sub: String
    let tags: [String]
    let comp: String?
    let warm: Int
    let live: Bool
    let set: String
    let ground: String
    let ink: String
    let body: String
    let hi: String
}

final class PieceRuntime: @unchecked Sendable {
    static let shared = PieceRuntime()
    typealias Fetcher = @Sendable (String) async -> (status: Int, data: Data)

    /// Every piece file, in the order the gallery loads them (lib/piece-bundles.json). Each one guards against double evaluation.
    static let bundleFiles = ["pieces.js", "pieces-w1.js", "pieces-ai.js", "pieces-h2.js", "pieces-pl-ribbon.js", "pieces-s305b.js"]

    let queue = DispatchQueue(label: "pldev.codeart.js", qos: .userInteractive)
    let world = CanvasWorld()
    private(set) var pieces: [PieceInfo] = []
    private var byID: [String: PieceInfo] = [:]
    private var context: JSContext?
    private var fetcher: Fetcher?
    private var booting: Task<Bool, Never>?
    private var fnDraw: JSValue?
    private var fnDrawXf: JSValue?
    private var fnWarm: JSValue?
    private var fnPump: JSValue?
    private var fnAudio: JSValue?
    private(set) var lastError: String?

    private init() {}

    var isReady: Bool { context != nil }
    func info(_ id: String) -> PieceInfo? { byID[id] }

    // MARK: boot

    /// Loads the bundles (disk copy first, refreshed in the background), builds the context, lists the pieces. Safe to call from every view.
    func boot(fetch: @escaping Fetcher) async -> Bool {
        if let t = booting { return await t.value }
        fetcher = fetch
        let t = Task<Bool, Never> { [self] in await self.bootOnce(fetch) }
        booting = t
        let ok = await t.value
        if !ok { booting = nil }   // a failed boot (no network, nothing saved) may try again
        return ok
    }

    private static var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("codeart", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func bootOnce(_ fetch: @escaping Fetcher) async -> Bool {
        var sources: [(String, String)] = []
        for file in Self.bundleFiles {
            let local = Self.cacheDir.appendingPathComponent(file)
            var text: String?
            if let d = try? Data(contentsOf: local), let s = String(data: d, encoding: .utf8), !s.isEmpty { text = s }
            let modified = try? local.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let age = modified.map { Date().timeIntervalSince($0) } ?? .infinity
            if text == nil {
                let (st, d) = await fetch("scripts/" + file)
                if st == 200, let s = String(data: d, encoding: .utf8), !s.isEmpty { text = s; try? d.write(to: local) }
            } else if age > 86400 {
                Task.detached { let (st, d) = await fetch("scripts/" + file); if st == 200, !d.isEmpty { try? d.write(to: local) } }   // for the next launch
            }
            if let text { sources.append((file, text)) }
        }
        guard sources.contains(where: { $0.0 == "pieces.js" }) else { lastError = "The pieces are not on the phone yet and the gallery did not answer."; return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async { cont.resume(returning: self.build(sources)) }
        }
    }

    private func build(_ sources: [(String, String)]) -> Bool {
        guard let ctx = JSContext() else { lastError = "JavaScript could not start."; return false }
        ctx.name = "pldev-codeart"
        ctx.exceptionHandler = { _, e in DebugBridge.note("js: \(e?.toString() ?? "?") line \(e?.objectForKeyedSubscript("line")?.toInt32() ?? 0)") }
        installNative(ctx)
        ctx.evaluateScript(CanvasPrelude.source, withSourceURL: URL(string: "pldev:///prelude.js"))
        if ctx.objectForKeyedSubscript("__listPieces").isUndefined { lastError = "The runtime did not start."; return false }
        for (file, text) in sources {
            ctx.evaluateScript(text, withSourceURL: URL(string: "pldev:///scripts/\(file)"))
        }
        guard let json = ctx.objectForKeyedSubscript("__listPieces").call(withArguments: [])?.toString(),
              let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { lastError = "The pieces did not load."; return false }
        var out: [PieceInfo] = []
        for o in arr {
            guard let id = o["id"] as? String else { continue }
            let pal = o["pal"] as? [String: Any]
            let comp: String? = (o["comp"] as? String) ?? (o["comp"] as? NSNumber).map { String(format: "%02d", $0.intValue) }
            out.append(PieceInfo(id: id, name: (o["name"] as? String) ?? id, sub: (o["sub"] as? String) ?? "", tags: (o["tags"] as? [String]) ?? [], comp: comp,
                                 warm: (o["warm"] as? NSNumber)?.intValue ?? 60, live: (o["live"] as? Bool) ?? false, set: (o["set"] as? String) ?? "curve-archive",
                                 ground: (pal?["g"] as? String) ?? "#0e0c08", ink: (pal?["ink"] as? String) ?? "#e8dfce", body: (pal?["body"] as? String) ?? "#c9a84c", hi: (pal?["hi"] as? String) ?? "#7a5c1e"))
        }
        pieces = out
        byID = Dictionary(out.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        fnDraw = ctx.objectForKeyedSubscript("__draw")
        fnDrawXf = ctx.objectForKeyedSubscript("__drawXf")
        fnWarm = ctx.objectForKeyedSubscript("__warm")
        fnPump = ctx.objectForKeyedSubscript("__pump")
        fnAudio = ctx.objectForKeyedSubscript("__setAudio")
        context = ctx
        return !out.isEmpty
    }

    // MARK: instances

    /// A piece ready to draw: its comp loaded, `make` run. `pxW`/`pxH` are bitmap pixels, `dpr` the pixels per point.
    func makeInstance(_ id: String, pxW: Int, pxH: Int, dpr: Double) async -> PieceInstance? {
        await withCheckedContinuation { (cont: CheckedContinuation<PieceInstance?, Never>) in
            queue.async {
                guard let ctx = self.context, let info = self.byID[id] else { cont.resume(returning: nil); return }
                let once = Once()
                if let comp = info.comp {
                    let cb: @convention(block) (JSValue) -> Void = { _ in self.queue.async { self.create(id, pxW, pxH, dpr, info, once, cont) } }
                    ctx.objectForKeyedSubscript("__loadComp").call(withArguments: [comp, unsafeBitCast(cb, to: AnyObject.self)])
                    self.queue.asyncAfter(deadline: .now() + 8) { self.create(id, pxW, pxH, dpr, info, once, cont) }   // a comp that never answers must not hold the piece forever
                } else { self.create(id, pxW, pxH, dpr, info, once, cont) }
            }
        }
    }

    private final class Once: @unchecked Sendable { var done = false }

    private func create(_ id: String, _ pxW: Int, _ pxH: Int, _ dpr: Double, _ info: PieceInfo, _ once: Once, _ cont: CheckedContinuation<PieceInstance?, Never>) {
        if once.done { return }
        once.done = true
        guard let ctx = context,
              let out = ctx.objectForKeyedSubscript("__newInstance").call(withArguments: [id, pxW, pxH, dpr])?.toString(),
              let o = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any],
              let handle = (o["handle"] as? NSNumber)?.intValue, let canvas = (o["canvas"] as? NSNumber)?.intValue else { cont.resume(returning: nil); return }
        cont.resume(returning: PieceInstance(runtime: self, handle: handle, canvasID: canvas, info: info, w: (o["w"] as? NSNumber)?.doubleValue ?? Double(pxW) / dpr,
                                             h: (o["h"] as? NSNumber)?.doubleValue ?? Double(pxH) / dpr, warmLeft: (o["warm"] as? NSNumber)?.intValue ?? info.warm))
    }

    // queue-only below

    func pushAudio(_ b: VJAudio.Bands) { fnAudio?.call(withArguments: [b.bass, b.mid, b.high, b.beat]) }
    func pump() { fnPump?.call(withArguments: []) }

    /// Runs one slice of the warm-up frames; returns how many are left.
    func warm(_ inst: PieceInstance, frames: Int) -> Int {
        let left = fnWarm?.call(withArguments: [inst.handle, frames])?.toInt32() ?? 0
        inst.warmLeft = Int(left)
        return Int(left)
    }

    /// One frame of a piece. Returns the picture, or nil when the piece's surface is gone.
    func draw(_ inst: PieceInstance) -> CGImage? {
        fnDraw?.call(withArguments: [inst.handle, -1])
        return world.surface(inst.canvasID)?.snapshot()
    }

    /// One frame through a transform (a VJ deck: zoom and tilt around the centre, and an alpha), as VJEngine draws it.
    func drawTransformed(_ inst: PieceInstance, frame: Int, zoom: Double, angle: Double, alpha: Double, warm: Double, beat: Bool) {
        fnDrawXf?.call(withArguments: [inst.handle, frame, zoom, angle, alpha, warm, beat])
    }

    func resize(_ inst: PieceInstance, pxW: Int, pxH: Int, dpr: Double) {
        context?.objectForKeyedSubscript("__resizeInstance").call(withArguments: [inst.handle, pxW, pxH, dpr])
        inst.w = Double(pxW) / dpr
        inst.h = Double(pxH) / dpr
        inst.warmLeft = inst.info.warm
    }

    func free(handle: Int, canvasID: Int) {
        queue.async { [self] in
            context?.objectForKeyedSubscript("__freeInstance").call(withArguments: [handle])
            world.surfaces[canvasID] = nil
        }
    }

    /// Native memory is invisible to JavaScript's collector, so a heavy piece's canvases would pile up until it ran. Nudge it.
    func collectIfHeavy() {
        if world.bytesSinceCollect > 160_000_000, let c = context {
            JSGarbageCollect(c.jsGlobalContextRef)
            world.bytesSinceCollect = 0
        }
    }

    // MARK: Forge

    /// Runs source that registers a piece (the same wrapper ForgePreview uses); returns the new piece's id or the error.
    func run(source: String) async -> (id: String?, error: String?) {
        await withCheckedContinuation { (cont: CheckedContinuation<(id: String?, error: String?), Never>) in
            queue.async {
                guard let ctx = self.context, let out = ctx.objectForKeyedSubscript("__forgeRun").call(withArguments: [source])?.toString(),
                      let o = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] else { cont.resume(returning: (nil, "The runtime is not ready.")); return }
                if let e = o["error"] as? String { cont.resume(returning: (nil, e)); return }
                guard let id = o["id"] as? String else { cont.resume(returning: (nil, "The code did not register a piece.")); return }
                // add it to the list the rooms read
                if let json = ctx.objectForKeyedSubscript("__listPieces").call(withArguments: [])?.toString(),
                   let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]], let row = arr.first(where: { ($0["id"] as? String) == id }) {
                    let pal = row["pal"] as? [String: Any]
                    let info = PieceInfo(id: id, name: (row["name"] as? String) ?? id, sub: (row["sub"] as? String) ?? "", tags: (row["tags"] as? [String]) ?? [], comp: nil, warm: (row["warm"] as? NSNumber)?.intValue ?? 60, live: false, set: "forge",
                                         ground: (pal?["g"] as? String) ?? "#0e0c08", ink: (pal?["ink"] as? String) ?? "#e8dfce", body: (pal?["body"] as? String) ?? "#c9a84c", hi: (pal?["hi"] as? String) ?? "#7a5c1e")
                    self.byID[id] = info
                    if !self.pieces.contains(where: { $0.id == id }) { self.pieces.append(info) }
                }
                cont.resume(returning: (id, nil))
            }
        }
    }

    // MARK: the native object the prelude calls

    private func bytes(_ v: JSValue) -> (UnsafeMutableRawPointer, Int)? {
        guard let ctx = JSContext.current() else { return nil }
        let refOpt: JSGlobalContextRef? = ctx.jsGlobalContextRef
        guard let ref = refOpt, let obj = JSValueToObject(ref, v.jsValueRef, nil) else { return nil }
        let len = JSObjectGetTypedArrayByteLength(ref, obj, nil)
        guard len > 0, let p = JSObjectGetTypedArrayBytesPtr(ref, obj, nil) else { return nil }
        return (p, len)
    }

    private func callback(_ name: String, _ args: [Any]) {
        queue.async { [self] in context?.objectForKeyedSubscript(name).call(withArguments: args) }
    }

    private func installNative(_ ctx: JSContext) {
        let n = JSValue(newObjectIn: ctx)!
        func put(_ name: String, _ block: AnyObject) { n.setObject(block, forKeyedSubscript: name as NSString) }

        let now: @convention(block) () -> Double = { CACurrentMediaTime() * 1000 }
        put("now", unsafeBitCast(now, to: AnyObject.self))

        let log: @convention(block) (Int, String) -> Void = { level, msg in if level >= 1 { DebugBridge.note(msg) } }
        put("log", unsafeBitCast(log, to: AnyObject.self))

        let canvasResize: @convention(block) (Int, Int, Int) -> Void = { [unowned self] id, w, h in
            if let s = world.surfaces[id] { s.resize(w, h) } else { world.surfaces[id] = CanvasSurface(id: id, w: w, h: h, world: world) }
        }
        put("canvasResize", unsafeBitCast(canvasResize, to: AnyObject.self))

        let canvasFree: @convention(block) (Int) -> Void = { [unowned self] id in world.surfaces[id] = nil }
        put("canvasFree", unsafeBitCast(canvasFree, to: AnyObject.self))

        let flush: @convention(block) (Int, JSValue, Int, JSValue) -> Void = { [unowned self] id, nums, count, strs in
            guard let s = world.surfaces[id], let (p, len) = bytes(nums) else { return }
            let strings = (strs.toArray() as? [String]) ?? []
            s.run(p.assumingMemoryBound(to: Double.self), count: min(count, len / 8), strs: strings)
        }
        put("flush", unsafeBitCast(flush, to: AnyObject.self))

        let getImageData: @convention(block) (Int, Int, Int, Int, Int, JSValue) -> Void = { [unowned self] id, x, y, w, h, out in
            guard let s = world.surfaces[id], let (p, len) = bytes(out), len >= w * h * 4 else { return }
            s.read(x, y, w, h, into: p.assumingMemoryBound(to: UInt8.self))
        }
        put("getImageData", unsafeBitCast(getImageData, to: AnyObject.self))

        let putImageData: @convention(block) (Int, JSValue, Int, Int, Int, Int, Int, Int, Int, Int) -> Void = { [unowned self] id, px, iw, ih, dx, dy, sx, sy, sw, sh in
            guard let s = world.surfaces[id], let (p, len) = bytes(px), len >= iw * ih * 4 else { return }
            s.write(UnsafePointer(p.assumingMemoryBound(to: UInt8.self)), iw: iw, ih: ih, dx: dx, dy: dy, sx: sx, sy: sy, sw: sw, sh: sh)
        }
        put("putImageData", unsafeBitCast(putImageData, to: AnyObject.self))

        let measureText: @convention(block) (String, String, Double) -> Double = { font, text, spacing in
            CanvasSurface.measure(font: font, text: text, spacing: CGFloat(spacing))
        }
        put("measureText", unsafeBitCast(measureText, to: AnyObject.self))

        let hasFont: @convention(block) (String) -> Bool = { FontResolver.hasFont($0) }
        put("hasFont", unsafeBitCast(hasFont, to: AnyObject.self))

        let pointIn: @convention(block) (String, Double, Double, Int, Int, Double) -> Bool = { d, x, y, rule, stroke, lw in
            SVGPath.contains(d, x: x, y: y, evenOdd: rule != 0, stroke: stroke != 0, lineWidth: lw)
        }
        put("pointIn", unsafeBitCast(pointIn, to: AnyObject.self))

        let imageLoad: @convention(block) (Int, String) -> Void = { [unowned self] id, url in
            guard let fetcher else { callback("__imgDone", [id, false, 0, 0]); return }
            Task.detached { [self] in
                let (st, data) = await fetcher(url)
                var decoded: CGImage?
                if st == 200, let src = CGImageSourceCreateWithData(data as CFData, nil) { decoded = CGImageSourceCreateImageAtIndex(src, 0, nil) }
                let img = decoded
                queue.async { [self] in
                    if let img { world.images[id] = img; context?.objectForKeyedSubscript("__imgDone").call(withArguments: [id, true, img.width, img.height]) }
                    else { context?.objectForKeyedSubscript("__imgDone").call(withArguments: [id, false, 0, 0]) }
                }
            }
        }
        put("imageLoad", unsafeBitCast(imageLoad, to: AnyObject.self))

        let fetchBlock: @convention(block) (Int, String, String, String) -> Void = { [unowned self] id, url, _, _ in
            guard let fetcher else { callback("__fetchDone", [id, 0, ""]); return }
            Task.detached { [self] in
                let (st, data) = await fetcher(url)
                let text = String(data: data, encoding: .utf8) ?? ""
                callback("__fetchDone", [id, st, text])
            }
        }
        put("fetch", unsafeBitCast(fetchBlock, to: AnyObject.self))

        let glDraw: @convention(block) (Int, String, JSValue, Int, Int) -> Void = { [unowned self] id, frag, uniforms, w, h in
            guard let s = world.surfaces[id], let (p, len) = bytes(uniforms), len >= 16 * 8 else { return }
            let u = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Double.self), count: 16))
            ShaderRenderer.shared.render(frag: frag, uniforms: u, w: w, h: h, into: s)
        }
        put("glDraw", unsafeBitCast(glDraw, to: AnyObject.self))

        ctx.setObject(n, forKeyedSubscript: "__N" as NSString)
    }
}

/// One running piece: a handle into the JavaScript side and the surface it draws on.
final class PieceInstance: @unchecked Sendable {
    let runtime: PieceRuntime
    let handle: Int
    let canvasID: Int
    let info: PieceInfo
    var w: Double
    var h: Double
    var warmLeft: Int

    init(runtime: PieceRuntime, handle: Int, canvasID: Int, info: PieceInfo, w: Double, h: Double, warmLeft: Int) {
        self.runtime = runtime
        self.handle = handle
        self.canvasID = canvasID
        self.info = info
        self.w = w
        self.h = h
        self.warmLeft = warmLeft
    }

    deinit { runtime.free(handle: handle, canvasID: canvasID) }
}

/// The gallery as the runtime's network: relative paths go through the app's own HTTP client (offline copies and all), absolute
/// addresses (a piece's public data feed) straight out.
enum CodeArtNet {
    @MainActor static func fetcher(for model: AppModel) -> PieceRuntime.Fetcher {
        let http = model.http
        return { url in
            if url.hasPrefix("http://") || url.hasPrefix("https://") {
                guard let u = URL(string: url) else { return (0, Data()) }
                var req = URLRequest(url: u)
                req.timeoutInterval = 12
                guard let (d, r) = try? await URLSession.shared.data(for: req), let h = r as? HTTPURLResponse else { return (0, Data()) }
                return (h.statusCode, d)
            }
            guard let http else { return (0, Data()) }
            var path = url
            if path.hasPrefix("/") { path.removeFirst() }
            var query: [String: String] = [:]
            if let q = path.firstIndex(of: "?") {
                for pair in path[path.index(after: q)...].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    if let k = kv.first { query[k] = kv.count > 1 ? (kv[1].removingPercentEncoding ?? kv[1]) : "" }
                }
                path = String(path[..<q])
            }
            do { return (200, try await http.send(RequestPlan(origin: "gallery", path: path, query: query), timeout: 40)) }
            catch { return (404, Data()) }
        }
    }
}
