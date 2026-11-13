import SwiftUI

// Composer's logic, ported from pl-composer (lib/types.ts, lib/graph.ts, lib/emit.ts), line for line, so the phone writes the same
// spec the web board and the desktop app write. Nothing here computes pixels: the graph carries intent, the renderer evaluates.

// MARK: sockets

enum ComposerSocket: String, CaseIterable, Sendable {
    case media = "Media", curve = "Curve", audio = "Audio", value = "Value", model = "Model", path = "Path", shot = "Shot", spec = "Spec"
    /// lib/types.ts SOCKET_COLOR (pl-os palette tokens, not new hues).
    var color: Color {
        switch self {
        case .media: return Color(hex: 0xc9a84c); case .curve: return Color(hex: 0x9b72cf); case .audio: return Color(hex: 0x2d8a6e)
        case .value: return Color(hex: 0x5f93a3); case .model: return Color(hex: 0xb07d2a); case .path: return Color(hex: 0x8c6a3e)
        case .shot: return Color(hex: 0xc0392b); case .spec: return Color(hex: 0x1a1510)
        }
    }
    var carries: String {
        switch self {
        case .media: return "File-backed pixels"; case .curve: return "A curves-library element"; case .audio: return "A track"
        case .value: return "A number, constant or time-varying"; case .model: return "Geometry: a .blend, .glb, .fbx"
        case .path: return "A tracer job: his pen path over his art"; case .shot: return "What a card resolves to"; case .spec: return "Terminal"
        }
    }
    var why: String {
        switch self {
        case .media: return "Stills and video. Baked."
        case .curve: return "Parametric, not baked. It can be driven. That is why it is not Media."
        case .audio: return "The only source that produces motion from nothing."
        case .value: return "An envelope, a slider and an LFO are all Value. Envelope is a flavour, not a type."
        case .model: return "Not pixels yet. Render it to get Media; that stage is never implicit."
        case .path: return "Not pixels yet. A look (chalk, velvet, bead...) renders it; the drawing order is his, never redrawn."
        case .shot: return "Exactly one per card."
        case .spec: return "The markdown."
        }
    }
}

// MARK: assets (read only)

struct ComposerAsset: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String          // media | audio | curve | model | path (the CLI's vocabulary)
    let name: String
    let catalog: String
    let path: String
    let ext: String
    let bytes: Int
    let width: Int?
    let height: Int?
    let duration: Double?
    let tags: [String]

    enum CodingKeys: String, CodingKey { case id, kind, name, catalog, path, ext, bytes, width, height, duration, tags }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(String.self, forKey: .kind); name = try c.decode(String.self, forKey: .name)
        catalog = (try? c.decode(String.self, forKey: .catalog)) ?? ""; path = (try? c.decode(String.self, forKey: .path)) ?? ""
        ext = (try? c.decode(String.self, forKey: .ext)) ?? ""; bytes = (try? c.decode(Int.self, forKey: .bytes)) ?? 0
        width = try? c.decode(Int.self, forKey: .width); height = try? c.decode(Int.self, forKey: .height)
        duration = try? c.decode(Double.self, forKey: .duration); tags = (try? c.decode([String].self, forKey: .tags)) ?? []
    }
    /// Which socket an asset plugs into (assetSocket).
    var socket: ComposerSocket {
        switch kind { case "curve": return .curve; case "audio": return .audio; case "model": return .model; case "path": return .path; default: return .media }
    }
}

struct ComposerRoot: Decodable, Hashable, Sendable {
    let catalog: String
    let present: Bool
    let count: Int
    let reason: String?
}

struct ComposerManifest: Decodable, Sendable {
    let generated: String
    let probed: Bool
    let roots: [ComposerRoot]
    let total: Int
    let assets: [ComposerAsset]
    enum K: String, CodingKey { case generated, probed, roots, counts, assets }
    enum CK: String, CodingKey { case total }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        generated = (try? c.decode(String.self, forKey: .generated)) ?? ""; probed = (try? c.decode(Bool.self, forKey: .probed)) ?? false
        roots = (try? c.decode([ComposerRoot].self, forKey: .roots)) ?? []
        assets = try c.decode([ComposerAsset].self, forKey: .assets)
        total = (try? c.nestedContainer(keyedBy: CK.self, forKey: .counts).decode(Int.self, forKey: .total)) ?? assets.count
    }
}

// MARK: values (a graph node's args are a bag of numbers, words, ranges and one bind map)

enum GVal: Codable, Hashable, Sendable {
    case num(Double), str(String), arr([GVal]), obj([String: GVal])

    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .num(n) }
        else if let b = try? c.decode(Bool.self) { self = .str(b ? "true" : "false") }
        else if let s = try? c.decode(String.self) { self = .str(s) }
        else if let a = try? c.decode([GVal].self) { self = .arr(a) }
        else if let o = try? c.decode([String: GVal].self) { self = .obj(o) }
        else { self = .str("") }
    }
    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self { case .num(let n): try c.encode(n); case .str(let s): try c.encode(s); case .arr(let a): try c.encode(a); case .obj(let o): try c.encode(o) }
    }

    var number: Double? { if case .num(let n) = self { return n }; if case .str(let s) = self { return Double(s) }; return nil }
    var string: String? { if case .str(let s) = self { return s }; if case .num(let n) = self { return Self.js(n) }; return nil }
    var range: [Double]? { if case .arr(let a) = self { return a.compactMap(\.number) }; return nil }

    /// JavaScript's String(number): 1 not 1.0, 0.3 not 0.30000000000000004.
    static func js(_ n: Double) -> String {
        if n.isFinite, n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
        return "\(n)"
    }
    /// emit.ts val(): arrays print numbers to two places, objects as { k: v }.
    var spec: String {
        switch self {
        case .num(let n): return Self.js(n)
        case .str(let s): return s
        case .arr(let a): return "[" + a.map { v -> String in if case .num(let n) = v { return String(format: "%.2f", n) }; return v.spec }.joined(separator: ", ") + "]"
        case .obj(let o): return "{ " + o.keys.sorted().map { "\($0): \(o[$0]!.spec)" }.joined(separator: ", ") + " }"
        }
    }
}

// MARK: the piece

/// How a shot enters (five words, not ffmpeg's fifty).
struct ComposerTransition: Identifiable, Sendable { let word: String; let why: String; var id: String { word } }
let composerTransitions: [ComposerTransition] = [
    ComposerTransition(word: "cut", why: "Nothing. The next shot is simply there."), ComposerTransition(word: "dissolve", why: "One picture becomes the other."),
    ComposerTransition(word: "black", why: "Out through black, then in. The longest pause."), ComposerTransition(word: "wipe", why: "The next shot pushes up over this one."),
    ComposerTransition(word: "slide", why: "Both move together, upward.")]
let composerTransitionSeconds = 0.4
let composerResolutions = ["1080x1920", "1080x1350", "1080x1080", "1920x1080"]

struct ComposerOp: Codable, Hashable, Sendable {
    var op: String
    var out: String?
    var args: [String: GVal]
}

struct ComposerShot: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var duration: Double
    var transition: String?
    var sourceIds: [String]
    var nodes: [ComposerOp]?
}

/// The same JSON the web board and the desktop app keep (`the-practice-v1.piece.json`), so a piece moves between all three.
struct ComposerPiece: Codable, Hashable, Sendable {
    var piece: String = "untitled-piece"
    var target: String = "remotion → openmontage"
    var fps: Int = 30
    var resolution: String = "1080x1920"
    var transition: String?
    var shots: [ComposerShot] = []
    var duration: Double { shots.reduce(0) { $0 + $1.duration } }
}

// MARK: the node catalog (lib/graph.ts KINDS)

enum NodeKind: String, CaseIterable, Codable, Sendable {
    case source, blender_render, envelope_extract, remap, constant, layer, matte, tracer_render, bed, file_to_curate, shot
}

struct PortSpec: Sendable { let id: String; let label: String; let accepts: [ComposerSocket]; var multi = false }
struct ParamSpec: Sendable {
    enum Kind: Sendable { case number, select, range }
    let key: String; let label: String; let kind: Kind
    var options: [String] = []; var min: Double? = nil; var max: Double? = nil; var step: Double? = nil
}
struct KindSpec: Sendable {
    let label: String; let why: String; let inputs: [PortSpec]; let output: ComposerSocket?; let params: [ParamSpec]; let rank: Int
}

private let mediaish: [ComposerSocket] = [.media, .curve]
private let looks = ["chalk", "paint", "velvet", "tension", "sand", "ripple", "loom", "flute", "caustic", "foil", "extrude", "vinyl", "shards", "rake", "frost", "patina", "blender-chalk", "blender-desk", "blender-carve", "blender-silk", "bead"]

extension NodeKind {
    var spec: KindSpec {
        switch self {
        case .source: return KindSpec(label: "Source", why: "A row of the library. The board reads the manifest and never writes it.", inputs: [], output: nil, params: [], rank: 0)
        case .blender_render: return KindSpec(label: "Blender Render", why: "Geometry is not pixels yet. This is the stage that makes it Media, and it is never implicit.",
                                              inputs: [PortSpec(id: "model", label: "model", accepts: [.model])], output: .media, params: [], rank: 0)
        case .envelope_extract: return KindSpec(label: "Envelope Extract", why: "Audio is the only source that produces motion from nothing. This is how it drives something.",
                                                inputs: [PortSpec(id: "audio", label: "audio", accepts: [.audio])], output: .value,
                                                params: [ParamSpec(key: "band", label: "band", kind: .select, options: ["low", "mid", "high", "full"]),
                                                         ParamSpec(key: "smooth", label: "smooth", kind: .number, min: 0, max: 1, step: 0.05),
                                                         ParamSpec(key: "gain", label: "gain", kind: .number, min: 0, max: 8, step: 0.1)], rank: 1)
        case .remap: return KindSpec(label: "Remap", why: "Rescales a Value into the range a parameter actually wants.",
                                     inputs: [PortSpec(id: "value", label: "value", accepts: [.value])], output: .value,
                                     params: [ParamSpec(key: "in", label: "in", kind: .range), ParamSpec(key: "out", label: "out", kind: .range),
                                              ParamSpec(key: "ease", label: "ease", kind: .select, options: ["linear", "ease-in", "ease-out", "ease-in-out"])], rank: 2)
        case .constant: return KindSpec(label: "Constant", why: "A number with no source. A slider, an LFO and an envelope are all Value.", inputs: [], output: .value,
                                        params: [ParamSpec(key: "value", label: "value", kind: .number, step: 0.1)], rank: 1)
        case .layer: return KindSpec(label: "Layer", why: "Composites one source over another. Bind a Value to drive a parameter over time.",
                                     inputs: [PortSpec(id: "base", label: "base", accepts: mediaish), PortSpec(id: "overlay", label: "overlay", accepts: mediaish),
                                              PortSpec(id: "opacity", label: "opacity", accepts: [.value]), PortSpec(id: "width", label: "width", accepts: [.value])],
                                     output: .shot,
                                     params: [ParamSpec(key: "blend", label: "blend", kind: .select, options: ["screen", "add", "lighten", "normal", "overlay", "multiply"]),
                                              ParamSpec(key: "opacity", label: "opacity", kind: .number, min: 0, max: 1, step: 0.05)], rank: 3)
        case .matte: return KindSpec(label: "Matte", why: "The base seen only inside the shape's marks. Not a blend: a window cut into one picture in the shape of another.",
                                     inputs: [PortSpec(id: "base", label: "base", accepts: mediaish), PortSpec(id: "shape", label: "shape", accepts: mediaish)], output: .shot,
                                     params: [ParamSpec(key: "threshold", label: "threshold", kind: .number, min: 0, max: 255, step: 1),
                                              ParamSpec(key: "feather", label: "feather", kind: .number, min: 0, max: 40, step: 1),
                                              ParamSpec(key: "ground", label: "ground", kind: .select, options: ["auto", "cream", "obsidian"])], rank: 3)
        case .tracer_render: return KindSpec(label: "Tracer Render", why: "His pen path drawn by one of the house looks. The path is his; the look is the material. Never redrawn.",
                                             inputs: [PortSpec(id: "path", label: "path", accepts: [.path])], output: .media,
                                             params: [ParamSpec(key: "look", label: "look", kind: .select, options: looks),
                                                      ParamSpec(key: "seed", label: "seed", kind: .number, min: 1, max: 9999, step: 1)], rank: 0)
        case .bed: return KindSpec(label: "Bed", why: "A music bed under the clip: the track ends with the drawing, then rings out. Every mix is word-checked.",
                                   inputs: [PortSpec(id: "media", label: "media", accepts: [.media]), PortSpec(id: "track", label: "track", accepts: [.audio])], output: .media,
                                   params: [ParamSpec(key: "tail", label: "tail", kind: .number, min: 2, max: 12, step: 0.5)], rank: 1)
        case .file_to_curate: return KindSpec(label: "File to /curate", why: "The card. The clip goes to /curate unmarked with these words and tags; he rules there.",
                                              inputs: [PortSpec(id: "media", label: "media", accepts: [.media])], output: nil,
                                              params: [ParamSpec(key: "kind", label: "kind", kind: .select, options: ["generation technique, music", "traced, music", "cinematic"]),
                                                       ParamSpec(key: "medium", label: "medium", kind: .select, options: ["chalk", "paint", "ink", "wet paint", "enamel bead", "gold wire", "gold thread", "light", "oxidation", "melt"]),
                                                       ParamSpec(key: "material", label: "material", kind: .select, options: ["slate", "paper", "canvas", "black", "kraft", "oxblood velvet", "black lacquer", "sand", "pool water", "indigo cloth", "reeded glass", "foil", "vinyl", "broken glass", "pressed board", "frosted glass", "copper", "lacquered board"]),
                                                       ParamSpec(key: "technique", label: "technique", kind: .select, options: looks)], rank: 4)
        case .shot: return KindSpec(label: "Shot", why: "What this card resolves to. Exactly one per card, and a graph can never contain another.",
                                    inputs: [PortSpec(id: "layers", label: "layers", accepts: [.shot], multi: true)], output: nil, params: [], rank: 4)
        }
    }
    /// The order of the Add node menu (GraphCanvas).
    static let addable: [NodeKind] = [.tracer_render, .bed, .file_to_curate, .blender_render, .envelope_extract, .remap, .constant, .layer, .matte]
}

func composerDefaultArgs(_ k: NodeKind) -> [String: GVal] {
    switch k {
    case .envelope_extract: return ["band": .str("low"), "smooth": .num(0.3), "gain": .num(1)]
    case .remap: return ["in": .arr([.num(0), .num(1)]), "out": .arr([.num(0.35), .num(1)]), "ease": .str("linear")]
    case .constant: return ["value": .num(1)]
    case .layer: return ["blend": .str("screen"), "opacity": .num(1)]
    case .matte: return ["ground": .str("auto")]
    case .blender_render: return ["fps": .str("@piece.fps"), "resolution": .str("@piece.resolution")]
    case .tracer_render: return ["look": .str("velvet"), "seed": .num(342)]
    case .bed: return ["tail": .num(6)]
    case .file_to_curate: return ["kind": .str("generation technique, music"), "medium": .str("paint"), "material": .str("slate"), "technique": .str("velvet")]
    default: return [:]
    }
}

// MARK: canvas shapes

struct GNode: Identifiable, Hashable, Sendable {
    var id: String
    var position: CGPoint
    var kind: NodeKind
    var assetId: String?
    var out: String?
    var args: [String: GVal]
}
struct GEdge: Identifiable, Hashable, Sendable {
    var id: String
    var source: String
    var target: String
    var port: String        // the target's input id; the source side is always "out"
}

enum ComposerGraph {
    // layout constants, shared with the node view so the sockets sit exactly where the maths says
    static let nodeWidth: CGFloat = 186, head: CGFloat = 26, row: CGFloat = 21
    static func height(_ k: NodeKind) -> CGFloat { head + row * CGFloat(k.spec.inputs.count + 1) + 6 }
    static func inputPoint(_ n: GNode, _ port: String) -> CGPoint {
        let i = n.kind.spec.inputs.firstIndex { $0.id == port } ?? 0
        return CGPoint(x: n.position.x, y: n.position.y + head + row * CGFloat(i) + row / 2)
    }
    static func outputPoint(_ n: GNode) -> CGPoint {
        CGPoint(x: n.position.x + nodeWidth, y: n.position.y + head + row * CGFloat(n.kind.spec.inputs.count) + row / 2)
    }

    static func outputType(_ n: GNode, _ byId: [String: ComposerAsset]) -> ComposerSocket? {
        if n.kind == .source { return n.assetId.flatMap { byId[$0] }?.socket }
        return n.kind.spec.output
    }

    private static func refOf(_ n: GNode) -> String { n.kind == .source ? (n.assetId ?? n.id) : (n.out ?? n.id) }

    /// Strict typed connect: the type must fit the port, a single port holds one wire, and no cycles.
    static func canConnect(source: String, target: String, port: String, nodes: [GNode], edges: [GEdge], byId: [String: ComposerAsset]) -> (ok: Bool, reason: String?) {
        guard let src = nodes.first(where: { $0.id == source }), let tgt = nodes.first(where: { $0.id == target }) else { return (false, "unknown node") }
        if src.id == tgt.id { return (false, "a node cannot feed itself") }
        guard let p = tgt.kind.spec.inputs.first(where: { $0.id == port }) else { return (false, "no such input") }
        guard let t = outputType(src, byId) else { return (false, "this source is not in the current manifest") }
        if !p.accepts.contains(t) { return (false, "\(p.label) takes \(p.accepts.map(\.rawValue).joined(separator: " or ")), not \(t.rawValue)") }
        if !p.multi, edges.contains(where: { $0.target == tgt.id && $0.port == p.id }) { return (false, "\(p.label) already has a connection") }
        if reaches(from: tgt.id, to: src.id, edges) { return (false, "that would make a cycle") }
        return (true, nil)
    }

    private static func reaches(from: String, to: String, _ edges: [GEdge]) -> Bool {
        var seen = Set<String>(), stack = [from]
        while let cur = stack.popLast() {
            if cur == to { return true }
            if !seen.insert(cur).inserted { continue }
            for e in edges where e.source == cur { stack.append(e.target) }
        }
        return false
    }

    /// canvas to the emitter's contract: Kahn with the catalog's rank breaking ties; layers tie-break on their wiring order into the Shot.
    static func toOps(_ nodes: [GNode], _ edges: [GEdge]) -> [ComposerOp] {
        let byNode = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func inputRef(_ id: String, _ port: String) -> String? {
            guard let e = edges.first(where: { $0.target == id && $0.port == port }), let up = byNode[e.source] else { return nil }
            return refOf(up)
        }
        var layerOrder: [String: Int] = [:]
        if let terminal = nodes.first(where: { $0.kind == .shot }) {
            for (i, e) in edges.filter({ $0.target == terminal.id }).enumerated() { layerOrder[e.source] = i }
        }
        let idx = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        func tiebreak(_ n: GNode, _ i: Int) -> Int { (n.kind == .layer || n.kind == .matte) ? (layerOrder[n.id] ?? 1_000_000) : i }

        var indeg = Dictionary(nodes.map { ($0.id, 0) }, uniquingKeysWith: { a, _ in a })
        for e in edges where indeg[e.target] != nil { indeg[e.target]! += 1 }
        var ready = nodes.filter { indeg[$0.id] == 0 }
        var order: [GNode] = []
        while !ready.isEmpty {
            let keyed = ready.enumerated().sorted { a, b in
                let ra = a.element.kind.spec.rank - b.element.kind.spec.rank
                if ra != 0 { return ra < 0 }
                let ta = tiebreak(a.element, idx[a.element.id] ?? 0), tb = tiebreak(b.element, idx[b.element.id] ?? 0)
                return ta != tb ? ta < tb : a.offset < b.offset
            }
            ready = keyed.map(\.element)
            let n = ready.removeFirst()
            order.append(n)
            for e in edges where e.source == n.id {
                let d = (indeg[e.target] ?? 1) - 1
                indeg[e.target] = d
                if d == 0, let t = byNode[e.target] { ready.append(t) }
            }
        }

        var out: [ComposerOp] = []
        for n in order {
            let args = n.args
            switch n.kind {
            case .source, .shot: continue
            case .blender_render:
                guard let s = inputRef(n.id, "model") else { continue }
                out.append(ComposerOp(op: "blender_render", out: n.out, args: args.merging(["source": .str(s)]) { a, _ in a }))
            case .tracer_render:
                guard let s = inputRef(n.id, "path") else { continue }
                out.append(ComposerOp(op: "tracer_render", out: n.out, args: args.merging(["source": .str(s)]) { a, _ in a }))
            case .bed:
                guard let s = inputRef(n.id, "media"), let t = inputRef(n.id, "track") else { continue }
                out.append(ComposerOp(op: "bed", out: n.out, args: args.merging(["source": .str(s), "track": .str(t)]) { a, _ in a }))
            case .file_to_curate:
                guard let s = inputRef(n.id, "media") else { continue }
                out.append(ComposerOp(op: "file_to_curate", out: nil, args: args.merging(["source": .str(s)]) { a, _ in a }))
            case .envelope_extract:
                guard let s = inputRef(n.id, "audio") else { continue }
                out.append(ComposerOp(op: "envelope_extract", out: n.out, args: args.merging(["source": .str(s)]) { a, _ in a }))
            case .remap:
                guard let s = inputRef(n.id, "value") else { continue }
                out.append(ComposerOp(op: "remap", out: n.out, args: args.merging(["source": .str(s)]) { a, _ in a }))
            case .constant:
                out.append(ComposerOp(op: "constant", out: n.out, args: args))
            case .matte:
                guard let base = inputRef(n.id, "base"), let shape = inputRef(n.id, "shape") else { continue }   // a matte needs both halves
                var a: [String: GVal] = ["base": .str(base), "shape": .str(shape)]
                for k in ["threshold", "feather"] { if let v = args[k], v.string != "" { a[k] = v } }
                if let g = args["ground"], g.string != "auto", g.string != "" { a["ground"] = g }
                out.append(ComposerOp(op: "matte", out: nil, args: a))
            case .layer:
                guard let base = inputRef(n.id, "base") else { continue }   // a layer with no base is not a layer yet
                var a = args
                a["base"] = .str(base)
                if let o = inputRef(n.id, "overlay") { a["overlay"] = .str(o) }
                var bind: [String: GVal] = [:]
                for k in ["opacity", "width"] { if let r = inputRef(n.id, k) { bind[k] = .str(r) } }
                if !bind.isEmpty { a["bind"] = .obj(bind) }
                out.append(ComposerOp(op: "layer", out: nil, args: a))
            }
        }
        return out
    }

    /// A graph to the canvas: used to reopen a saved graph and to seed a shot from deriveGraph, one operation written once.
    static func fromOps(_ graph: [ComposerOp], sourceIds: [String]) -> (nodes: [GNode], edges: [GEdge]) {
        var nodes: [GNode] = [], edges: [GEdge] = []
        var producer: [String: String] = [:]
        var seq = 0
        func nid(_ k: String) -> String { seq += 1; return "\(k)_\(seq)" }
        for aid in sourceIds {
            let id = nid("src")
            nodes.append(GNode(id: id, position: .zero, kind: .source, assetId: aid, out: nil, args: [:]))
            producer[aid] = id
        }
        func link(_ ref: GVal?, _ target: String, _ port: String) {
            guard let r = ref?.string, let p = producer[r] else { return }
            edges.append(GEdge(id: "e\(edges.count)", source: p, target: target, port: port))
        }
        let terminalId = nid("shot")
        var layerIds: [String] = []
        for g in graph {
            var rest = g.args
            let id = nid(g.op)
            func drop(_ keys: String...) { for k in keys { rest.removeValue(forKey: k) } }
            switch g.op {
            case "blender_render": drop("source"); nodes.append(GNode(id: id, position: .zero, kind: .blender_render, out: g.out, args: rest)); link(g.args["source"], id, "model")
            case "tracer_render": drop("source"); nodes.append(GNode(id: id, position: .zero, kind: .tracer_render, out: g.out, args: rest)); link(g.args["source"], id, "path")
            case "bed": drop("source", "track"); nodes.append(GNode(id: id, position: .zero, kind: .bed, out: g.out, args: rest)); link(g.args["source"], id, "media"); link(g.args["track"], id, "track")
            case "file_to_curate": drop("source"); nodes.append(GNode(id: id, position: .zero, kind: .file_to_curate, out: nil, args: rest)); link(g.args["source"], id, "media")
            case "envelope_extract": drop("source"); nodes.append(GNode(id: id, position: .zero, kind: .envelope_extract, out: g.out, args: rest)); link(g.args["source"], id, "audio")
            case "remap": drop("source"); nodes.append(GNode(id: id, position: .zero, kind: .remap, out: g.out, args: rest)); link(g.args["source"], id, "value")
            case "constant": nodes.append(GNode(id: id, position: .zero, kind: .constant, out: g.out, args: rest))
            case "matte":
                drop("base", "shape"); if rest["ground"] == nil { rest["ground"] = .str("auto") }
                nodes.append(GNode(id: id, position: .zero, kind: .matte, out: nil, args: rest)); link(g.args["base"], id, "base"); link(g.args["shape"], id, "shape"); layerIds.append(id)
            case "layer":
                drop("base", "overlay", "bind")
                nodes.append(GNode(id: id, position: .zero, kind: .layer, out: nil, args: rest)); link(g.args["base"], id, "base"); link(g.args["overlay"], id, "overlay")
                if case .obj(let bind)? = g.args["bind"] { for k in ["opacity", "width"] { link(bind[k], id, k) } }
                layerIds.append(id)
            default: break
            }
            if let o = g.out { producer[o] = id }
        }
        nodes.append(GNode(id: terminalId, position: .zero, kind: .shot, out: nil, args: [:]))
        for l in layerIds { edges.append(GEdge(id: "e\(edges.count)", source: l, target: terminalId, port: "layers")) }
        layout(&nodes, edges)
        return (nodes, edges)
    }

    /// Columns by dependency depth, rows by arrival (not a dagre dependency: the graph is a handful of nodes deep).
    static func layout(_ nodes: inout [GNode], _ edges: [GEdge]) {
        var depth: [String: Int] = [:]
        func compute(_ id: String, _ seen: inout Set<String>) -> Int {
            if let d = depth[id] { return d }
            if seen.contains(id) { return 0 }
            seen.insert(id)
            let ups = edges.filter { $0.target == id }.map(\.source)
            let d = ups.isEmpty ? 0 : 1 + (ups.map { compute($0, &seen) }.max() ?? 0)
            depth[id] = d
            return d
        }
        for n in nodes { var seen = Set<String>(); _ = compute(n.id, &seen) }
        var rows: [Int: Int] = [:]
        for i in nodes.indices {
            let d = depth[nodes[i].id] ?? 0, r = rows[d] ?? 0
            rows[d] = r + 1
            nodes[i].position = CGPoint(x: 24 + CGFloat(d) * 232, y: 24 + CGFloat(r) * 132)
        }
    }

    /// The canvas for a shot: its saved graph if it has one, the real default wiring if not.
    static func canvasFor(_ shot: ComposerShot, byId: [String: ComposerAsset]) -> (nodes: [GNode], edges: [GEdge]) {
        let g = (shot.nodes?.isEmpty == false) ? shot.nodes! : deriveGraph(shot, byId: byId)
        return fromOps(g, sourceIds: shot.sourceIds)
    }

    /// A fresh `v_` / `m_` identifier. Names are for humans; uniqueness is for the renderer.
    static func nextOut(_ k: NodeKind, _ nodes: [GNode], assetId: String? = nil) -> String? {
        if [.layer, .matte, .source, .shot, .file_to_curate].contains(k) { return nil }
        let base: String
        switch k {
        case .blender_render: base = "m_\(assetId ?? "render")"
        case .tracer_render: base = "m_\(assetId ?? "trace")"
        case .bed: base = "m_bed"
        case .envelope_extract: base = "v_energy"
        case .remap: base = "v_remap"
        default: base = "v_const"
        }
        let taken = Set(nodes.compactMap(\.out))
        if !taken.contains(base) { return base }
        var i = 2
        while taken.contains("\(base)_\(i)") { i += 1 }
        return "\(base)_\(i)"
    }

    /// The default wiring from what is attached (the rules S262 proved): the first media is the base, the rest overlay with screen,
    /// a model is rendered first, and a track drives overlay opacity through its low band.
    static func deriveGraph(_ shot: ComposerShot, byId: [String: ComposerAsset]) -> [ComposerOp] {
        let assets = shot.sourceIds.compactMap { byId[$0] }
        var nodes: [ComposerOp] = []
        let models = assets.filter { $0.kind == "model" }, audio = assets.filter { $0.kind == "audio" }
        let media = assets.filter { $0.kind == "media" || $0.kind == "curve" } + models
        for m in models {
            nodes.append(ComposerOp(op: "blender_render", out: "m_\(m.id)", args: ["source": .str(m.id), "fps": .str("@piece.fps"), "resolution": .str("@piece.resolution")]))
        }
        var bind: [String: GVal]?
        if let a = audio.first {
            nodes.append(ComposerOp(op: "envelope_extract", out: "v_energy", args: ["source": .str(a.id), "band": .str("low"), "smooth": .num(0.3), "gain": .num(1)]))
            nodes.append(ComposerOp(op: "remap", out: "v_opacity", args: ["source": .str("v_energy"), "in": .arr([.num(0), .num(1)]), "out": .arr([.num(0.35), .num(1)]), "ease": .str("linear")]))
            bind = ["opacity": .str("v_opacity")]
        }
        if let base = media.first {
            let baseRef = base.kind == "model" ? "m_\(base.id)" : base.id
            for ov in media.dropFirst() {
                var a: [String: GVal] = ["base": .str(baseRef), "overlay": .str(ov.kind == "model" ? "m_\(ov.id)" : ov.id), "blend": .str("screen"), "opacity": .num(1)]
                if let b = bind { a["bind"] = .obj(b) }
                nodes.append(ComposerOp(op: "layer", out: nil, args: a))
            }
            if media.count == 1 {
                // a single source is still a layer (one base, no overlay) so every shot has the same shape; screen is the safe default
                var a: [String: GVal] = ["base": .str(baseRef), "blend": .str("screen"), "opacity": .num(1)]
                if let b = bind { a["bind"] = .obj(b) }
                nodes.append(ComposerOp(op: "layer", out: nil, args: a))
            }
        }
        return nodes
    }
}

// MARK: the spec (emit.ts)

enum ComposerSpec {
    private static func name(_ id: GVal?, _ byId: [String: ComposerAsset]) -> String {
        guard let s = id?.string, let a = byId[s] else { return "" }
        return "   # \(a.name)"
    }

    static func lines(_ n: ComposerOp, _ byId: [String: ComposerAsset]) -> [String] {
        let a = n.args
        func v(_ k: String) -> String { a[k]?.spec ?? "undefined" }
        switch n.op {
        case "envelope_extract":
            return ["  - envelope_extract: \(v("source")) -> \(n.out ?? "undefined")\(name(a["source"], byId))"] + ["band", "smooth", "gain"].map { "      \($0): \(v($0))" }
        case "remap":
            return ["  - remap: \(v("source")) -> \(n.out ?? "undefined")", "      in: \(v("in"))", "      out: \(v("out"))", "      ease: \(v("ease"))"]
        case "constant":
            return ["  - constant: -> \(n.out ?? "undefined")", "      value: \(v("value"))"]
        case "blender_render":
            return ["  - blender_render: \(v("source")) -> \(n.out ?? "undefined")\(name(a["source"], byId))", "      fps: \(v("fps"))", "      resolution: \(v("resolution"))"]
        case "matte":
            var out = ["  - matte:", "      base: \(v("base"))\(name(a["base"], byId))", "      shape: \(v("shape"))\(name(a["shape"], byId))"]
            for k in ["invert", "threshold", "feather", "ground"] { if let x = a[k], x.string != "" { out.append("      \(k): \(x.spec)") } }
            return out
        case "tracer_render":
            var out = ["  - tracer_render: \(v("source")) -> \(n.out ?? "undefined")\(name(a["source"], byId))", "      look: \(v("look"))"]
            for k in ["seed", "fstop", "tool"] { if let x = a[k], x.string != "" { out.append("      \(k): \(x.spec)") } }
            return out
        case "bed":
            return ["  - bed: \(v("source")) + \(v("track")) -> \(n.out ?? "undefined")\(name(a["track"], byId))", "      tail: \(v("tail"))"]
        case "file_to_curate":
            var out = ["  - file_to_curate: \(v("source"))"]
            for k in ["kind", "medium", "material", "technique", "piece", "words"] { if let x = a[k], x.string != "" { out.append("      \(k): \(x.spec)") } }
            return out
        default:
            var out = ["  - layer:", "      base: \(v("base"))\(name(a["base"], byId))"]
            if a["overlay"] != nil { out.append("      overlay: \(v("overlay"))\(name(a["overlay"], byId))") }
            if a["bind"] != nil { out.append("      bind: \(v("bind"))") }
            out += ["      blend: \(v("blend"))", "      opacity: \(v("opacity"))"]
            return out
        }
    }

    static func stamp(_ d: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "America/Los_Angeles"); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d) + " PT"
    }

    /// The whole spec. Shot order in the file is shot order in the piece: that ordering is the contract, so nothing here sorts.
    static func emit(_ piece: ComposerPiece, assets: [ComposerAsset], now: Date = .now) -> String {
        let byId = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out = ["---", "spec_version: 1", "piece: \(piece.piece)", "created: \(stamp(now))", "target: \(piece.target)", "fps: \(piece.fps)", "resolution: \(piece.resolution)"]
        if let t = piece.transition, !t.isEmpty { out.append("transition: \(t)") }
        out += [String(format: "duration: %.1f", piece.duration), "---", ""]
        for (i, shot) in piece.shots.enumerated() {
            out.append("## Shot \(String(format: "%02d", i + 1)) — \(shot.title)")
            out.append(String(format: "duration: %.1f", shot.duration))
            if let t = shot.transition, !t.isEmpty, i > 0 { out.append("transition: \(t)") }   // shot 01 has nothing to come from
            let resolved = shot.sourceIds.compactMap { byId[$0] }
            if resolved.isEmpty { out.append("sources: []   # no sources attached — this shot renders black") }
            else { out.append("sources:"); for a in resolved { out.append("  - \(a.kind): \(a.id)   # \(a.name)\(a.ext)") } }
            let graph = (shot.nodes?.isEmpty == false) ? shot.nodes! : ComposerGraph.deriveGraph(shot, byId: byId)
            if !graph.isEmpty { out.append("graph:"); for n in graph { out += lines(n, byId) } }
            out.append("-> \(shot.id)")
            out.append("")
        }
        return out.joined(separator: "\n")
    }
}

// MARK: the render card (the board's POST body, page.tsx sendToRender)

enum ComposerCardError: Error { case needs(String) }

enum ComposerCard {
    /// A shot needs a Tracer Render and a File to /curate node, the render wired to a tracer job. Says plainly what is missing.
    static func body(piece: ComposerPiece, shot: ComposerShot, byId: [String: ComposerAsset]) throws -> [String: Any] {
        let nodes = (shot.nodes?.isEmpty == false) ? shot.nodes! : ComposerGraph.deriveGraph(shot, byId: byId)
        guard let tr = nodes.first(where: { $0.op == "tracer_render" }), let fc = nodes.first(where: { $0.op == "file_to_curate" })
        else { throw ComposerCardError.needs("This shot needs a Tracer Render node and a File to /curate node in its graph before it can be sent.") }
        guard let pathAsset = tr.args["source"]?.string.flatMap({ byId[$0] }) else { throw ComposerCardError.needs("The Tracer Render node is not wired to a path (a tracer job).") }
        let bd = nodes.first { $0.op == "bed" }
        let track = bd?.args["track"]?.string.flatMap { byId[$0] }
        var render: [String: Any] = ["look": tr.args["look"]?.string ?? "velvet", "path_dir": pathAsset.path]
        if let seed = tr.args["seed"]?.number, seed != 0 { render["seed"] = Int(seed) }
        var card: [String: String] = [:]
        for (k, v) in fc.args where k != "source" { card[k] = v.string ?? v.spec }
        return ["piece": piece.piece, "shot": shot.title.isEmpty ? shot.id : shot.title, "render": render,
                "bed": track.map { ["track": $0.path] } ?? NSNull(), "card": card]
    }
}
