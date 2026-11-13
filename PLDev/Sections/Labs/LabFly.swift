import Compression
import SwiftUI

// THE FLY (public/fly/*, js/pl-curve.js, js/pl-sim.worker.js, js/data.js, js/presets.js).
// A curve drawn by a real fruit fly's brain: the FlyWire v783 connectome (138,639 neurons, 2,700,513 connections) run as a leaky
// integrate-and-fire network after Shiu et al., and the path walked by what is firing, rendered with the house's over/under channel.
// The wiring is measurement; the mapping to the line is a choice (as the page says). Code MIT (fly-brain-bench), data CC-BY 4.0
// (FlyWire, Dorkenwald et al.; Schlegel et al.). Everything below is that page's own maths in Swift; nothing is a web view.

// MARK: - The packed data

enum FlyData {
    struct Meta: Decodable {
        struct Dicts: Decodable { let super_class: [String]; let cell_class: [String]; let cell_type: [String]; let nt: [String]?; let side: [String] }
        let n_neurons: Int; let n_edges: Int; let dicts: Dicts
    }
    struct Channel: Decodable { let all: [Int]?; let left: [Int]?; let right: [Int]?; let types: [String]?; let found: [String]?; let desc: String? }
    struct Channels: Decodable { let channels: [String: Channel] }

    /// A gzip file as bytes: the 10-byte header (and its optional fields) off, the deflate body inflated.
    static func gunzip(_ d: Data) -> Data? {
        let b = [UInt8](d)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flg = b[3]
        var p = 10
        if flg & 4 != 0 { guard p + 2 <= b.count else { return nil }; p += 2 + Int(b[p]) + Int(b[p + 1]) << 8 }
        if flg & 8 != 0 { while p < b.count, b[p] != 0 { p += 1 }; p += 1 }
        if flg & 16 != 0 { while p < b.count, b[p] != 0 { p += 1 }; p += 1 }
        if flg & 2 != 0 { p += 2 }
        guard p < b.count - 8 else { return nil }
        let body = Data(b[p..<(b.count - 8)])
        return try? (body as NSData).decompressed(using: .zlib) as Data
    }

    struct Reader {
        let b: [UInt8]
        var p = 0
        init(_ d: Data) { b = [UInt8](d) }
        mutating func next() -> Int {
            var r = 0, s = 0
            while p < b.count { let x = Int(b[p]); p += 1; r |= (x & 0x7f) << s; s += 7; if x & 0x80 == 0 { break } }
            return r
        }
    }

    struct Wiring { var indptr: [Int32]; var indices: [Int32]; var weights: [Float] }

    /// conn.bin: varint row_counts[N], varint dest_delta[E], varint weight[E]; the sign of each row's weights is its neuron's sign bit.
    static func decodeConnectome(_ bytes: Data, n: Int, e: Int, sign: Data) -> Wiring? {
        var rd = Reader(bytes)
        var counts = [Int](repeating: 0, count: n)
        for i in 0..<n { counts[i] = rd.next() }
        var indptr = [Int32](repeating: 0, count: n + 1)
        for i in 0..<n { indptr[i + 1] = indptr[i] + Int32(counts[i]) }
        guard Int(indptr[n]) == e else { return nil }
        var indices = [Int32](repeating: 0, count: e)
        for k in 0..<e { indices[k] = Int32(truncatingIfNeeded: rd.next()) }
        for i in 0..<n { let a = Int(indptr[i]), z = Int(indptr[i + 1]); if z - a > 1 { for k in (a + 1)..<z { indices[k] &+= indices[k - 1] } } }
        let signBytes = [UInt8](sign)
        var weights = [Float](repeating: 0, count: e)
        for i in 0..<n {
            let exc = (signBytes[i >> 3] >> UInt8(7 - (i & 7))) & 1
            let s: Float = exc == 1 ? 0.275 : -0.275
            for k in Int(indptr[i])..<Int(indptr[i + 1]) { weights[k] = Float(rd.next()) * s }
        }
        return Wiring(indptr: indptr, indices: indices, weights: weights)
    }

    /// labels.bin: five uint16 arrays of N: super class, cell class, cell type, neurotransmitter, side.
    static func decodeLabels(_ d: Data, n: Int) -> [[UInt16]] {
        let u: [UInt16] = d.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self).prefix(n * 5)) }
        return (0..<5).map { Array(u[($0 * n)..<(($0 + 1) * n)]) }
    }

    /// pos.u16.bin: three uint16 per neuron, scaled to the span and centred on the cloud's own bounding box.
    static func decodePositions(_ d: Data, n: Int, span: Double) -> [Float] {
        let u: [UInt16] = d.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self).prefix(n * 3)) }
        var pos = [Float](repeating: 0, count: n * 3)
        var mn: [Float] = [1e9, 1e9, 1e9], mx: [Float] = [-1e9, -1e9, -1e9]
        for i in 0..<n { for k in 0..<3 {
            let v = Float(Double(u[i * 3 + k]) / 65535 * span); pos[i * 3 + k] = v
            mn[k] = min(mn[k], v); mx[k] = max(mx[k], v)
        } }
        for i in 0..<n { for k in 0..<3 { pos[i * 3 + k] -= (mn[k] + mx[k]) / 2 } }
        return pos
    }
}

// MARK: - The stimuli (presets.js)

struct FlyPreset: Identifiable {
    let id: String, name: String, tag: String, why: String
    var cellType: [String] = [], cellClass: [String] = [], prefix: [String] = []
    static let all: [FlyPreset] = [
        FlyPreset(id: "sugar", name: "Sugar on the proboscis", tag: "taste", why: "Labellar bristle taste neurons. Stimulating these is the published benchmark for this model — in the paper it drives the motor neurons that extend the proboscis to feed.", cellType: ["LB3"]),
        FlyPreset(id: "food", name: "Smell of food", tag: "smell", why: "Olfactory receptor neurons tuned to apple cider vinegar and other fermenting fruit. The classic \"there is food nearby\" channel.", cellType: ["ORN_DM1", "ORN_DM2"]),
        FlyPreset(id: "pheromone", name: "Pheromone (cVA)", tag: "smell", why: "The DA1 glomerulus carries cis-vaccenyl acetate, the courtship pheromone. This is the most studied labelled line in the fly.", cellType: ["ORN_DA1"]),
        FlyPreset(id: "loom", name: "Something coming at you", tag: "vision", why: "Looming detectors: they fire when a dark object expands in the visual field. Watch the responding list for DNp01 — the giant fibre, the single neuron that triggers the escape jump.", cellType: ["LPLC2"]),
        FlyPreset(id: "song", name: "Courtship song", tag: "hearing", why: "Johnston's organ, subgroup B: the antennal hearing neurons tuned to the low-frequency wingbeat song a courting male produces.", prefix: ["JO-B"]),
        FlyPreset(id: "colour", name: "Colour photoreceptors", tag: "vision", why: "The two inner photoreceptors of every ommatidium, carrying UV/blue and blue/green. Firing these lights up the whole optic lobe.", cellType: ["R7", "R8"]),
        FlyPreset(id: "humid", name: "Humidity", tag: "body", why: "Hygrosensory neurons in the antenna. Flies dehydrate fast at their size, so moisture gets its own dedicated sensory channel.", cellClass: ["hygrosensory"]),
        FlyPreset(id: "heat", name: "Temperature", tag: "body", why: "Thermosensory neurons of the arista. A handful of cells carries the whole hot/cold sense.", cellClass: ["thermosensory"]),
        FlyPreset(id: "touch", name: "Touch on the eye", tag: "body", why: "Bristle mechanosensory neurons between the ommatidia. This is what a speck of dust landing on the eye feels like, and it triggers grooming.", cellType: ["BM_InOm"]),
        FlyPreset(id: "bitter", name: "Bitter taste", tag: "taste", why: "Other labellar bristle classes, including the ones carrying aversive taste. Compare the response with sugar — different neurons, different downstream target.", prefix: ["LB1", "LB2"]),
    ]
}

// MARK: - The engine: a leaky integrate-and-fire network on its own thread (pl-sim.worker.js)

/// Parameters after Shiu et al. (2024); integration is the closed-form solution, so results do not depend on the step.
/// Spike-frequency adaptation (2 mV per spike, 200 ms) is the page's own fix for runaway firing.
final class FlyEngine: @unchecked Sendable {
    struct Post: Sendable {
        var counts: [Double] = []
        var cx = 0.0, cy = 0.0, spread = 0.0, nSpk = 0
        var nActive = 0, totalSpikes = 0
    }

    private let V0: Float = -52, VTH: Float = -45, TMBR: Float = 20, TAU: Float = 5
    private let DT: Float = 0.1
    private let WADP: Float = 2.0, W_POI: Float = 0.275 * 250, P_POI: Double = 150 * 0.1 / 1000
    private let EPS_V: Float = 0.02, EPS_G: Float = 0.02
    private let EA = Float(exp(-0.1 / 200.0)), EV = Float(exp(-0.1 / 20.0)), EG = Float(exp(-0.1 / 5.0))   // DT 0.1, TMBR 20, TAU 5
    private let KC: Float = (5.0 / (5.0 - 20.0)) * (Float(exp(-0.1 / 5.0)) - Float(exp(-0.1 / 20.0)))
    private let RFC_STEPS: Int16 = 22   // round(2.2 / 0.1)
    private let DLY_STEPS = 18          // round(1.8 / 0.1)

    private let n: Int
    private let indptr: [Int32], indices: [Int32], weights: [Float]
    private var v: [Float], g: [Float], adp: [Float]
    private var rfc: [Int16], inActive: [UInt8], isStim: [UInt8]
    private var active: [Int32], nActive = 0
    private var ring: [[Int32]]
    private var stim: [Int32] = []
    private var step = 0
    private var totalSpikes = 0
    private var pos: [Float]
    private var bucketOf: [Int32: [Int]] = [:]
    private var tracked: [UInt8]
    private var counts: [Double] = []
    private var sx = 0.0, sy = 0.0, sz = 0.0, sxx = 0.0, syy = 0.0, nSpk = 0

    // shared with the main thread
    private let lock = NSLock()
    private var running = false, quit = false
    private var pendingStim: [Int32]?, pendingReset = false
    private var mailbox: Post?

    init(n: Int, wiring: FlyData.Wiring, pos: [Float], lists: [[Int32]]) {
        self.n = n; indptr = wiring.indptr; indices = wiring.indices; weights = wiring.weights; self.pos = pos
        v = [Float](repeating: -52, count: n); g = [Float](repeating: 0, count: n); adp = [Float](repeating: 0, count: n)
        rfc = [Int16](repeating: 0, count: n); inActive = [UInt8](repeating: 0, count: n); isStim = [UInt8](repeating: 0, count: n)
        active = [Int32](repeating: 0, count: n)
        ring = (0..<18).map { _ in [] }
        tracked = [UInt8](repeating: 0, count: n)
        counts = [Double](repeating: 0, count: lists.count)
        for (b, list) in lists.enumerated() { for i in list { tracked[Int(i)] = 1; bucketOf[i, default: []].append(b) } }
    }

    func start() { Thread.detachNewThread { [self] in loop() } }
    func setRunning(_ on: Bool) { lock.lock(); running = on; lock.unlock() }
    func stimulate(_ idx: [Int32]) { lock.lock(); pendingStim = idx; lock.unlock() }
    func reset() { lock.lock(); pendingReset = true; lock.unlock() }
    func stop() { lock.lock(); quit = true; lock.unlock() }
    func take() -> Post? { lock.lock(); defer { lock.unlock() }; let m = mailbox; mailbox = nil; return m }

    private func resetState() {
        for i in 0..<n { v[i] = V0; g[i] = 0; rfc[i] = 0; inActive[i] = 0; adp[i] = 0 }
        nActive = 0; step = 0; totalSpikes = 0
        for s in 0..<ring.count { ring[s].removeAll(keepingCapacity: true) }
        for i in stim { touch(Int(i)) }
    }
    @inline(__always) private func touch(_ i: Int) { if inActive[i] == 0 { inActive[i] = 1; active[nActive] = Int32(i); nActive += 1 } }

    private func advance(_ out: inout [Int32]) {
        let slot = step % DLY_STEPS
        // 1. deliver spikes emitted TDLY ago
        for src in ring[slot] {
            let a = Int(indptr[Int(src)]), b = Int(indptr[Int(src) + 1])
            var e = a
            while e < b { let j = Int(indices[e]); g[j] += weights[e]; touch(j); e += 1 }
        }
        ring[slot].removeAll(keepingCapacity: true)
        // 2. Poisson drive on the stimulated set
        for i in stim where Double.random(in: 0..<1) < P_POI { v[Int(i)] += W_POI; touch(Int(i)) }
        // 3. integrate and threshold, active set only
        var w = 0
        for k in 0..<nActive {
            let i = Int(active[k])
            if rfc[i] > 0 { rfc[i] -= 1; active[w] = Int32(i); w += 1; continue }
            let gi = g[i], vi = v[i]
            let an = adp[i] * EA
            let vn = V0 + (vi - V0) * EV + KC * gi - an
            let gn = gi * EG
            adp[i] = an
            if vn > VTH {
                v[i] = V0; g[i] = 0
                if isStim[i] == 0 { adp[i] = an + WADP; rfc[i] = RFC_STEPS }
                totalSpikes += 1
                ring[(step + DLY_STEPS - 1) % DLY_STEPS].append(Int32(i))
                out.append(Int32(i))
                active[w] = Int32(i); w += 1
            } else {
                v[i] = vn; g[i] = gn
                let dv = vn - V0
                if dv < EPS_V && dv > -EPS_V && gn < EPS_G && gn > -EPS_G && an < EPS_G && isStim[i] == 0 {
                    inActive[i] = 0; v[i] = V0; g[i] = 0; adp[i] = 0
                } else { active[w] = Int32(i); w += 1 }
            }
        }
        nActive = w
        step += 1
    }

    private func loop() {
        var lastPost = Date()
        var spikes: [Int32] = []
        while true {
            lock.lock()
            let isRunning = running, done = quit
            let ps = pendingStim, pr = pendingReset
            pendingStim = nil; pendingReset = false
            lock.unlock()
            if done { return }
            if let ps {
                for i in stim { isStim[Int(i)] = 0 }
                stim = ps
                for i in stim { isStim[Int(i)] = 1 }
                resetState()
                counts = [Double](repeating: 0, count: counts.count)
            } else if pr { resetState() }
            if !isRunning { Thread.sleep(forTimeInterval: 0.03); continue }
            for _ in 0..<8 {
                spikes.removeAll(keepingCapacity: true)
                advance(&spikes)
                for s in spikes {
                    let i = Int(s)
                    if tracked[i] == 1, let bs = bucketOf[s] { for b in bs { counts[b] += 1 } }
                    let x = Double(pos[i * 3]), y = Double(pos[i * 3 + 1]), z = Double(pos[i * 3 + 2])
                    sx += x; sy += y; sz += z; sxx += x * x; syy += y * y; nSpk += 1
                }
            }
            if Date().timeIntervalSince(lastPost) >= 0.033 {
                lastPost = Date()
                var p = Post(counts: counts, nActive: nActive, totalSpikes: totalSpikes)
                if nSpk > 0 {
                    let cx = sx / Double(nSpk), cy = sy / Double(nSpk)
                    p.cx = cx; p.cy = cy
                    p.spread = (max(0, sxx / Double(nSpk) - cx * cx) + max(0, syy / Double(nSpk) - cy * cy)).squareRoot()
                }
                p.nSpk = nSpk
                lock.lock()
                if var old = mailbox { for b in 0..<min(old.counts.count, p.counts.count) { old.counts[b] += p.counts[b] }; old.cx = p.cx; old.cy = p.cy; old.spread = p.spread; old.nSpk = p.nSpk; old.nActive = p.nActive; old.totalSpikes = p.totalSpikes; mailbox = old }
                else { mailbox = p }
                lock.unlock()
                for b in counts.indices { counts[b] = 0 }
                sx = 0; sy = 0; sz = 0; sxx = 0; syy = 0; nSpk = 0
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }
}

// MARK: - The model: boot, the readout, and the path the fly draws

@MainActor @Observable final class FlyModel {
    nonisolated static let channels: [(String, String)] = [
        ("walk", "how fast the line travels"), ("turn", "which way it bends — left/right imbalance is signed"), ("wing", "how wide the ribbon opens"),
        ("escape", "the giant fibre. One spike breaks the line"), ("stop", "the line stalls and the ink pools"), ("backward", "it retraces itself"),
        ("landing", "it falls"), ("proboscis", "it blooms at the head"),
    ]
    struct Pt { var x: Double; var y: Double; var w: Double; var o: Double }

    var bootMessage = "waking a fly"
    var bootProgress = 0.0
    var bootFailed = false
    var ready = false
    var running = false
    var stimName = "no stimulus"
    var why = "Choose a stimulus to wake the brain."
    var selected: String?
    var neurons = 0
    var edges = 0
    var totalSpikes = 0
    var nActiveNow = 0
    var channelHz: [String: Double] = [:]

    // drawing state, read by the canvas each frame (not observed)
    @ObservationIgnored var path: [Pt] = []
    @ObservationIgnored var breaks: [(x: Double, y: Double, a: Double)] = []
    @ObservationIgnored var size: CGSize = .zero
    @ObservationIgnored private var engine: FlyEngine?
    @ObservationIgnored private var labels: [[UInt16]] = []
    @ObservationIgnored private var dicts: FlyData.Meta.Dicts?
    @ObservationIgnored private var bucketNames: [String] = []
    @ObservationIgnored private var counts: [Double] = []
    @ObservationIgnored private var hz: [Double] = []
    @ObservationIgnored private var bucketN: [Double] = []
    @ObservationIgnored private var penX = 0.0
    @ObservationIgnored private var penY = 0.0
    @ObservationIgnored private var heading = -0.6
    @ObservationIgnored private var nSpk = 0
    @ObservationIgnored private var lastRead = Date()
    @ObservationIgnored private var lastBreak = -99.0
    @ObservationIgnored private var escapeArmed = true
    @ObservationIgnored private var t = 0.0
    @ObservationIgnored private var rates: [String: Double] = [:]
    @ObservationIgnored private var lastFrame: Date?

    func boot(model: AppModel) async {
        guard !ready, engine == nil else { return }
        guard let http = model.http else { bootMessage = "failed: this app is not set up"; bootFailed = true; return }
        func get(_ p: String, _ f: Double, _ msg: String) async throws -> Data {
            bootMessage = msg; bootProgress = f
            return try await http.send(RequestPlan(origin: "gallery", path: "fly/data/" + p), timeout: 180)
        }
        do {
            let metaGz = try await get("meta.json.gz", 0.02, "reading the index")
            guard let metaRaw = FlyData.gunzip(metaGz), let meta = try? JSONDecoder().decode(FlyData.Meta.self, from: metaRaw) else { throw FlyFail("the index would not open") }
            neurons = meta.n_neurons; edges = meta.n_edges; dicts = meta.dicts
            let span = (try? JSONSerialization.jsonObject(with: metaRaw) as? [String: Any])?["span"] as? Double ?? 814.848
            let n = meta.n_neurons

            let posRaw = try await get("pos.u16.bin.gz", 0.08, "reading where each neuron sits")
            let labRaw = try await get("labels.bin.gz", 0.14, "reading the annotations")
            let signRaw = try await get("sign.bin.gz", 0.18, "reading the annotations")
            let chanRaw = try await http.send(RequestPlan(origin: "gallery", path: "fly/data/channels.json"), timeout: 60)
            let connRaw = try await get("conn.bin.gz", 0.22, "reading 2.7 million connections")
            bootMessage = "rebuilding the wiring"; bootProgress = 0.86

            let dictsCopy = meta.dicts
            let built = await Task.detached(priority: .userInitiated) { () -> (FlyData.Wiring, [Float], [[UInt16]], FlyData.Channels, [[Int32]], [String])? in
                guard let pos = FlyData.gunzip(posRaw), let lab = FlyData.gunzip(labRaw), let sign = FlyData.gunzip(signRaw), let conn = FlyData.gunzip(connRaw),
                      let ch = try? JSONDecoder().decode(FlyData.Channels.self, from: chanRaw),
                      let wiring = FlyData.decodeConnectome(conn, n: n, e: meta.n_edges, sign: sign) else { return nil }
                let labels = FlyData.decodeLabels(lab, n: n)
                let (lists, names) = FlyModel.buckets(channels: ch, labels: labels, dicts: dictsCopy, n: n)
                return (wiring, FlyData.decodePositions(pos, n: n, span: span), labels, ch, lists, names)
            }.value
            guard let (wiring, pos, labels, _, lists, names) = built else { throw FlyFail("the wiring would not rebuild") }

            bootMessage = "waking it"; bootProgress = 0.95
            self.labels = labels; bucketNames = names
            counts = [Double](repeating: 0, count: names.count); hz = counts
            bucketN = lists.map { Double(max(1, $0.count)) }
            let e = FlyEngine(n: n, wiring: wiring, pos: pos, lists: lists)
            engine = e
            e.start()
            bootMessage = "ready"; bootProgress = 1
            ready = true
        } catch {
            bootMessage = "failed: \((error as? FlyFail)?.why ?? error.localizedDescription)"
            bootFailed = true
        }
    }
    struct FlyFail: Error { let why: String; init(_ w: String) { why = w } }

    /// The eight channels (turn split by hemisphere) and the anatomical regions the line is steered by.
    nonisolated static func buckets(channels ch: FlyData.Channels, labels: [[UInt16]], dicts: FlyData.Meta.Dicts, n: Int) -> ([[Int32]], [String]) {
        var defs: [(String, [Int32])] = []
        for (k, _) in channels {
            guard let c = ch.channels[k] else { continue }
            if k == "turn" { defs.append(("turnL", (c.left ?? []).map(Int32.init))); defs.append(("turnR", (c.right ?? []).map(Int32.init))) }
            defs.append((k, (c.all ?? []).map(Int32.init)))
        }
        let regions: [(String, [String], [String])] = [("optic", ["optic", "visual_projection"], []), ("mb", [], ["Kenyon_Cell"]), ("cx", [], ["CX"]),
                                                       ("sensory", ["sensory", "sensory_ascending"], []), ("descending", ["descending"], []), ("central", ["central"], [])]
        let left = dicts.side.firstIndex(of: "left") ?? -1, right = dicts.side.firstIndex(of: "right") ?? -1
        for (name, sc, cc) in regions {
            let wantSC = Set(sc.compactMap { dicts.super_class.firstIndex(of: $0) }), wantCC = Set(cc.compactMap { dicts.cell_class.firstIndex(of: $0) })
            var all: [Int32] = [], l: [Int32] = [], r: [Int32] = []
            for i in 0..<n where wantSC.contains(Int(labels[0][i])) || wantCC.contains(Int(labels[1][i])) {
                all.append(Int32(i))
                if Int(labels[4][i]) == left { l.append(Int32(i)) } else if Int(labels[4][i]) == right { r.append(Int32(i)) }
            }
            if all.isEmpty { continue }
            defs.append(("r:\(name)", all))
            if name == "cx" || name == "optic" { defs.append(("r:\(name):L", l)); defs.append(("r:\(name):R", r)) }
        }
        return (defs.map(\.1), defs.map(\.0))
    }

    func choose(_ p: FlyPreset) {
        guard let dicts, !labels.isEmpty else { return }
        let wantType = Set(p.cellType.compactMap { dicts.cell_type.firstIndex(of: $0) })
        let wantClass = Set(p.cellClass.compactMap { dicts.cell_class.firstIndex(of: $0) })
        var prefixIdx = Set<Int>()
        if !p.prefix.isEmpty { for (i, name) in dicts.cell_type.enumerated() where p.prefix.contains(where: { name.hasPrefix($0) }) { prefixIdx.insert(i) } }
        var idx: [Int32] = []
        for i in 0..<labels[2].count where wantType.contains(Int(labels[2][i])) || wantClass.contains(Int(labels[1][i])) || prefixIdx.contains(Int(labels[2][i])) { idx.append(Int32(i)) }
        selected = p.id
        if idx.isEmpty { why = "No neurons matched this preset in v783."; return }
        stimName = "\(p.name) · \(idx.count.formatted()) neurons"
        why = p.why
        engine?.stimulate(idx)
        for b in counts.indices { counts[b] = 0; hz[b] = 0 }
        if !running { toggle(true) }
    }

    func toggle(_ on: Bool) { running = on; engine?.setRunning(on) }
    func clear() { path = []; breaks = [] }
    func shutdown() { engine?.stop() }

    private func rate(_ name: String) -> Double { bucketNames.firstIndex(of: name).map { hz[$0] } ?? 0 }

    /// Everything the page's frame loop does: read the engine's mailbox, smooth the channel rates, step the pen.
    func tick() {
        let nowFrame = Date()
        let rawDt = lastFrame.map { nowFrame.timeIntervalSince($0) } ?? 0.016
        lastFrame = nowFrame
        guard let engine else { return }
        if let m = engine.take() {
            for b in 0..<min(counts.count, m.counts.count) { counts[b] += m.counts[b] }
            totalSpikes = m.totalSpikes; nActiveNow = m.nActive
            nSpk = m.nSpk
        }
        let now = Date()
        if now.timeIntervalSince(lastRead) > 0.1 {
            let dtSec = now.timeIntervalSince(lastRead); lastRead = now
            for b in counts.indices {
                let isRegion = bucketNames[b].hasPrefix("r:")
                let v = isRegion ? counts[b] / dtSec : counts[b] / bucketN[b] / dtSec
                hz[b] += (v - hz[b]) * 0.45
                counts[b] = 0
            }
            var r: [String: Double] = [:]
            for (k, _) in Self.channels { r[k] = rate(k) }
            r["turn"] = (rate("turnL") + rate("turnR")) / 2
            rates = r
            channelHz = r
        }
        guard running, size.width > 10, size.height > 10 else { return }
        let dt = min(0.05, rawDt)
        t += dt
        if path.isEmpty && penX == 0 { penX = size.width / 2; penY = size.height / 2 }
        let rOptic = rate("r:optic"), rMB = rate("r:mb"), rCXL = rate("r:cx:L"), rCXR = rate("r:cx:R")
        let rDesc = rate("r:descending"), rCentral = rate("r:central"), rSens = rate("r:sensory")
        let rOpL = rate("r:optic:L"), rOpR = rate("r:optic:R")
        let opImb = (rOpR - rOpL) / (rOpR + rOpL + 40)
        let cxImb = (rCXR - rCXL) / (rCXR + rCXL + 8)
        let imb = abs(cxImb) > 0.02 ? cxImb : opImb
        heading += imb * (1.4 + min(3.2, rMB / 60)) * dt * 26
        let stepLen = 20 + min(170, rDesc * 1.6 + rCentral / 22 + rOptic / 22)
        penX += cos(heading) * stepLen * dt; penY += sin(heading) * stepLen * dt
        let W = Double(size.width), H = Double(size.height), m = 30.0
        if penX < m || penX > W - m { heading = .pi - heading; penX = min(W - m, max(m, penX)) }
        if penY < m || penY > H - m { heading = -heading; penY = min(H - m, max(m, penY)) }
        let act = min(1, rOptic / 400 + rSens / 250)
        let weight: (w: Double, o: Double) = act > 0.5 ? (7.5, 0.9) : act > 0.22 ? (3.2, 0.55) : (1.0, 0.3)
        if nSpk > 0, path.last.map({ hypot(penX - $0.x, penY - $0.y) >= 2.2 }) ?? true {
            path.append(Pt(x: penX, y: penY, w: weight.w, o: weight.o))
            if path.count > 1400 { path.removeFirst() }
        }
        // the giant fibre breaks the line: one spike is takeoff
        let esc = rates["escape"] ?? 0
        if esc > 1.2 && escapeArmed && t - lastBreak > 1.6, let h = path.last { escapeArmed = false; lastBreak = t; breaks.append((h.x, h.y, 1)) }
        if esc < 0.5 { escapeArmed = true }
        for i in breaks.indices.reversed() { breaks[i].a -= dt * 1.2; if breaks[i].a <= 0 { breaks.remove(at: i) } }
    }
}

// MARK: - The screen

struct LabFlyView: View {
    let model: AppModel
    @State private var fly = FlyModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                stage.containerRelativeFrame(.vertical) { h, _ in h * 0.62 }
                panel
            }
        }
        .background(Color(hex: 0x0a0a0a))
        .scrollIndicators(.hidden)
        .task { await fly.boot(model: model) }
        .task { while !Task.isCancelled { fly.tick(); try? await Task.sleep(for: .milliseconds(16)) } }
        .onDisappear { fly.shutdown() }
        .sensoryFeedback(PLHaptic.select, trigger: fly.selected)
    }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation) { _ in
                Canvas { gc, size in
                    fly.size = size
                    gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0a0a0a)))
                    draw(&gc)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("THE FLY").font(.system(size: 19, weight: .semibold, design: .serif)).tracking(2.6).foregroundStyle(PLG.gold)
                Text("The fly draws; the house renders. The line is the path walked by the centre of mass of whatever is firing in a brain that died several years ago.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0x7a756a)).lineSpacing(3).frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.top, 14).padding(.leading, 20).allowsHitTesting(false)
            HStack(spacing: 22) {
                hud("neurons", fly.neurons == 0 ? "—" : fly.neurons.formatted())
                hud("connections", fly.edges == 0 ? "—" : fly.edges.formatted())
                hud("spikes", fly.totalSpikes.formatted())
                hud("active now", fly.nActiveNow.formatted())
            }
            .frame(maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 20).padding(.bottom, 14).allowsHitTesting(false)
            if !fly.ready { boot }
        }
    }

    private func hud(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Color(hex: 0x7a756a))
            Text(v).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0xe8e4d9)).contentTransition(.numericText())
        }
    }

    private var boot: some View {
        VStack(spacing: 14) {
            Text(fly.bootMessage).font(.system(size: 11, design: .monospaced)).tracking(1.1).foregroundStyle(fly.bootFailed ? Color(hex: 0xd9706f) : Color(hex: 0x7a756a))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x1a1813)).frame(width: 260, height: 2)
                Rectangle().fill(PLG.gold).frame(width: 260 * fly.bootProgress, height: 2).animation(.easeOut(duration: 0.25), value: fly.bootProgress)
            }
            if fly.bootFailed { LabPill(title: "Try again") { fly.bootFailed = false; Task { await fly.boot(model: model) } } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: 0x0a0a0a))
    }

    /// The house's render over the fly's path: runs of 14 points, each carving a channel out of everything laid down before it.
    private func draw(_ gc: inout GraphicsContext) {
        let P = fly.path
        if P.count >= 3 {
            gc.drawLayer { layer in
                let run = 14
                var start = 0
                while start < P.count - 2 {
                    let end = min(P.count - 1, start + run + 1)
                    if end - start >= 2 {
                        let mid = P[min(P.count - 1, start + ((end - start) >> 1))]
                        let age = Double(end) / Double(P.count)
                        let alpha = mid.o * min(1, age * 2.2)
                        if alpha > 0.01 {
                            var p = Path()
                            p.move(to: CGPoint(x: (P[start].x + P[start + 1].x) / 2, y: (P[start].y + P[start + 1].y) / 2))
                            for i in (start + 1)..<end {
                                let b = P[i], c = P[i + 1]
                                p.addQuadCurve(to: CGPoint(x: (b.x + c.x) / 2, y: (b.y + c.y) / 2), control: CGPoint(x: b.x, y: b.y))
                            }
                            layer.blendMode = .destinationOut
                            layer.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: mid.w + 4.4, lineCap: .round, lineJoin: .round))
                            layer.blendMode = .normal
                            layer.stroke(p, with: .color(PLG.gold.opacity(alpha)), style: StrokeStyle(lineWidth: mid.w, lineCap: .round, lineJoin: .round))
                        }
                    }
                    start += run
                }
            }
        }
        for b in fly.breaks {
            let r = (1 - b.a) * 220
            gc.stroke(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)), with: .color(PLG.gold.opacity(b.a * 0.45)), lineWidth: 1.4)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STIMULUS").font(.system(size: 12, weight: .semibold, design: .serif)).tracking(1.7).foregroundStyle(PLG.gold)
            Text("Pick a sense. Nothing here aims at the motor channels — the wiring gets there on its own.")
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(hex: 0x7a756a)).lineSpacing(4).padding(.top, 4).padding(.bottom, 16)
            HStack(spacing: 8) {
                flyButton(fly.running ? "pause" : "run", on: fly.running) { fly.toggle(!fly.running) }.disabled(!fly.ready)
                flyButton("clear", on: false) { fly.clear() }
            }
            .padding(.bottom, 14)
            VStack(spacing: 5) {
                ForEach(FlyPreset.all) { p in
                    Button { fly.choose(p) } label: {
                        HStack { Text(p.name); Spacer(); Text(p.tag.uppercased()).font(.system(size: 9.5)).tracking(0.9).opacity(0.7) }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(fly.selected == p.id ? Color(hex: 0x0a0a0a) : Color(hex: 0xe8e4d9))
                            .padding(.horizontal, 11).frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 3).fill(fly.selected == p.id ? PLG.gold : Color(hex: 0x111010)))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(fly.selected == p.id ? PLG.gold : Color(hex: 0x1e1c18), lineWidth: 1))
                    }
                    .buttonStyle(.plain).disabled(!fly.ready)
                }
            }
            Text(fly.why).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(hex: 0x7a756a)).lineSpacing(5)
                .padding(.leading, 10).padding(.top, 12).overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x1e1c18)).frame(width: 1) }
            Text("WHAT THE LINE IS DOING").font(.system(size: 12, weight: .semibold, design: .serif)).tracking(1.7).foregroundStyle(PLG.gold).padding(.top, 24)
            Text(fly.stimName).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(hex: 0x7a756a)).padding(.top, 4).padding(.bottom, 8)
            ForEach(FlyModel.channels, id: \.0) { k, what in
                let hz = fly.channelHz[k] ?? 0
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k).font(.system(size: 11, design: .monospaced)).foregroundStyle(hz > 4 ? PLG.gold : Color(hex: 0xe8e4d9))
                        Text(what).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Color(hex: 0x7a756a))
                    }
                    Spacer()
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x17150f)).frame(width: 62, height: 3)
                        Capsule().fill(PLG.gold).frame(width: 62 * min(1, hz * 7 / 100), height: 3)
                    }
                    Text(String(format: "%.0f", hz)).font(.system(size: 10, design: .monospaced)).foregroundStyle(hz > 4 ? PLG.gold : Color(hex: 0x7a756a)).frame(width: 30, alignment: .trailing).monospacedDigit()
                }
                .padding(.vertical, 6)
                Divider().overlay(Color(hex: 0x131210))
            }
            Text("The wiring is measurement. The mapping is a choice. Which descending neurons exist and what each one does is published biology. That turn should bend a curve rather than colour it is a decision made in this drawing. The fly is real; the drawing is ours.\n\nConnectome: FlyWire v783 — Dorkenwald et al.; Schlegel et al. — CC-BY 4.0. LIF model after Shiu et al. Simulation engine from fly-brain-bench (MIT).")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(hex: 0x5c584f)).lineSpacing(5).padding(.top, 26)
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x070706))
    }

    private func flyButton(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, design: .monospaced)).tracking(0.7).foregroundStyle(on ? Color(hex: 0x0a0a0a) : Color(hex: 0xe8e4d9))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 2).fill(on ? PLG.gold : Color(hex: 0x111010)))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(on ? PLG.gold : Color(hex: 0x1e1c18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
