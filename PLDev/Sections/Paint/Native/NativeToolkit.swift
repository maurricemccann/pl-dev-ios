import Foundation

/// A brush, as the laptop's toolkit describes it: numbers and words keyed by the toolkit's own parameter names, over the toolkit defaults.
/// `NativeToolkit.json` is a copy of the packs, defaults, schema, papers, gestures and Quick menu out of `C:\dev\pl-toolkit`, and his colours
/// out of the Design Kit (the laptop's `src/toolkit.js` and `src/kit.js`); regenerate it when the toolkit changes.
struct Brush: @unchecked Sendable, Identifiable {
    let id: String
    let name: String
    let pack: String
    let note: String?
    let tip: String?
    var updated: Double
    private var num: [String: Double]
    private var txt: [String: String]

    func n(_ k: String) -> Double { num[k] ?? 0 }
    func t(_ k: String) -> String { txt[k] ?? "" }

    init(_ d: [String: Any], defaults: [String: Any], pack: String) {
        var num: [String: Double] = [:], txt: [String: String] = [:]
        for (k, v) in defaults.merging(d, uniquingKeysWith: { _, b in b }) {
            if let x = v as? Double { num[k] = x } else if let x = v as? Int { num[k] = Double(x) } else if let x = v as? String { txt[k] = x }
            else if let x = v as? Bool { num[k] = x ? 1 : 0 }
        }
        self.num = num; self.txt = txt
        id = d["id"] as? String ?? "brush"; name = d["name"] as? String ?? "Brush"; self.pack = pack
        note = d["note"] as? String; tip = d["tip"] as? String
        updated = (d["u"] as? Double) ?? Double(d["u"] as? Int ?? 0)
    }

    /// The plain brush the smudge and the first run use when the toolkit file is missing.
    static func plain(defaults: [String: Any]) -> Brush { Brush(["id": "round", "name": "Round"], defaults: defaults, pack: "Basics") }

    var shape: String { t("shape") }
    var usesTilt: Bool { n("tiltSize") > 0 || n("tiltAngle") > 0 }
    /// The ends need the whole stroke length, so the stroke is laid down once more on release (the laptop's `finishStroke`).
    var needsLength: Bool { n("taperEnd") > 0 || n("flareEnd") > 0 || (!t("capEnd").isEmpty && t("capEnd") != "flat") }
    var needsTwinColour: Bool { n("twin") > 0 || n("lines") > 1 && t("gapFill") == "colour" }

    func radius(size: Double, pressure p: Double, f: Double = 1) -> Double {
        max(0.6, size / 2 * (1 - n("pressSize") + n("pressSize") * pow(max(0, min(1, p)), n("pressCurve"))) * f)
    }

    // MARK: editing (Brush Studio)

    func setting(_ k: String, _ v: Double) -> Brush { var b = self; b.num[k] = v; b.updated = Date().timeIntervalSince1970 * 1000; return b }
    func setting(_ k: String, _ v: String) -> Brush { var b = self; b.txt[k] = v; b.updated = Date().timeIntervalSince1970 * 1000; return b }
    func renamed(_ id: String, _ name: String, pack: String) -> Brush {
        var d = dictionary(); d["id"] = id; d["name"] = name
        return Brush(d, defaults: NativeToolkit.defaults, pack: pack)
    }
    /// Every parameter that differs from the toolkit default, as the laptop's `mine.json` keeps a brush.
    func dictionary() -> [String: Any] {
        var o: [String: Any] = ["id": id, "name": name, "u": updated]
        let d = NativeToolkit.defaults
        for (k, v) in num { if let x = d[k] as? Double ?? (d[k] as? Int).map(Double.init), x == v { continue }; o[k] = v }
        for (k, v) in txt { if let x = d[k] as? String, x == v { continue }; o[k] = v }
        if let note { o["note"] = note }
        if let tip { o["tip"] = tip }
        return o
    }
}

enum NativeToolkit {
    struct Pack: Identifiable { let name: String; let brushes: [Brush]; var id: String { name } }
    struct Canvas { let name: String; let w: Int; let h: Int }
    struct Paper: Identifiable { let id: String; let name: String; let ground: String?; let texture: String; let edge: String }
    struct Gesture: Identifiable { let id: String; let name: String; let def: String }
    struct Profile { var name: String; var slots: [String] }
    struct Param { let key: String; let def: Double; let min: Double; let max: Double; let step: Double }
    struct Choice { let key: String; let def: String; let options: [String] }
    struct Palette: Identifiable { let name: String; let colors: [String]; let house: Bool; var id: String { name } }

    nonisolated(unsafe) static let raw: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "NativeToolkit", withExtension: "json"), let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return o
    }()
    nonisolated(unsafe) static let defaults: [String: Any] = raw["defaults"] as? [String: Any] ?? [:]

    /// Loaded once from the bundle. A missing or damaged file leaves one plain round brush, never a crash.
    nonisolated(unsafe) static let loaded: (defaults: [String: Any], packs: [Pack], canvases: [Canvas]) = {
        guard let defaults = raw["defaults"] as? [String: Any] else {
            return ([:], [Pack(name: "Basics", brushes: [Brush.plain(defaults: [:])])], [])
        }
        let packs = (raw["packs"] as? [[String: Any]] ?? []).map { p -> Pack in
            let name = p["name"] as? String ?? "Pack"
            return Pack(name: name, brushes: (p["brushes"] as? [[String: Any]] ?? []).map { Brush($0, defaults: defaults, pack: name) })
        }
        let presets = ((raw["canvases"] as? [String: Any])?["presets"] as? [[Any]] ?? []).compactMap { r -> Canvas? in
            guard r.count == 3, let n = r[0] as? String, let w = r[1] as? Int, let h = r[2] as? Int else { return nil }
            return Canvas(name: n, w: w, h: h)
        }
        return (defaults, packs, presets)
    }()

    static var packs: [Pack] { loaded.packs }
    static var all: [Brush] { loaded.packs.flatMap(\.brushes) }
    static var round: Brush { all.first { $0.id == "round" } ?? all.first ?? Brush.plain(defaults: loaded.defaults) }
    static var canvases: [Canvas] { loaded.canvases }

    static var papers: [Paper] {
        (raw["papers"] as? [[String: Any]] ?? []).map { Paper(id: $0["id"] as? String ?? "plain", name: $0["name"] as? String ?? "Plain", ground: $0["ground"] as? String, texture: $0["texture"] as? String ?? "none", edge: $0["edge"] as? String ?? "straight") }
    }
    static var gestures: [Gesture] {
        (raw["gestures"] as? [[String: Any]] ?? []).map { Gesture(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", def: $0["default"] as? String ?? "None") }
    }
    static var quickProfiles: [Profile] {
        (raw["quickmenu"] as? [[String: Any]] ?? []).map { Profile(name: $0["name"] as? String ?? "Profile", slots: $0["slots"] as? [String] ?? []) }
    }
    static var palettes: [Palette] {
        (raw["kitPalettes"] as? [[String: Any]] ?? []).map { Palette(name: $0["name"] as? String ?? "", colors: $0["colors"] as? [String] ?? [], house: $0["house"] as? Bool ?? false) }
    }
    static var accent: String { raw["kitAccent"] as? String ?? "#c9a84c" }

    /// The parameter table (`schema.json`): numbers with a range, and choices.
    static var params: [Param] {
        let s = raw["schema"] as? [String: Any] ?? [:]
        return s.compactMap { k, v in
            guard let m = v as? [String: Any], m["options"] == nil, m["def"] is NSNumber, m["def"] as? String == nil else { return nil }
            let lo = (m["min"] as? NSNumber)?.doubleValue ?? 0, hi = (m["max"] as? NSNumber)?.doubleValue ?? 1
            return Param(key: k, def: (m["def"] as? NSNumber)?.doubleValue ?? 0, min: lo, max: hi, step: (m["step"] as? NSNumber)?.doubleValue ?? (hi - lo > 20 ? 1 : 0.01))
        }.sorted { $0.key < $1.key }
    }
    static var choices: [Choice] {
        let s = raw["schema"] as? [String: Any] ?? [:]
        return s.compactMap { k, v in
            guard let m = v as? [String: Any], let o = m["options"] as? [String] else { return nil }
            return Choice(key: k, def: m["def"] as? String ?? o.first ?? "", options: o)
        }.sorted { $0.key < $1.key }
    }

    /// What his own writing says a colour means (the laptop's `senseOf`): the family and its meaning, or nil.
    static func sense(of hex: String) -> String? {
        guard let rgb = Hex.rgb(hex) else { return nil }
        let r = rgb.0, g = rgb.1, b = rgb.2, mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        var h = 0.0
        if d > 0 { h = mx == r ? ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4; h *= 60 }
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        let fams = (raw["colourSense"] as? [String: Any])?["families"] as? [[String: Any]] ?? []
        func within(_ t: [String: Any], _ key: String, _ v: Double) -> Bool {
            guard let a = t[key] as? [Double], a.count == 2 else { return true }
            return a[0] <= a[1] ? (v >= a[0] && v <= a[1]) : (v >= a[0] || v <= a[1])
        }
        for f in fams {
            guard let t = f["test"] as? [String: Any] else { continue }
            if within(t, "h", h) && within(t, "s", s) && within(t, "l", l) {
                return "\(f["name"] as? String ?? ""): \(f["meaning"] as? String ?? "")"
            }
        }
        return nil
    }
}

/// His own brushes ("Mine"), saved on the phone as the laptop's `mine.json` and synced as `file/mine.json`.
@MainActor enum NativeMine {
    private static var url: URL { NativeStore.dir.appendingPathComponent("mine.json") }
    static var brushes: [Brush] = load()
    static func load() -> [Brush] {
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return (o["brushes"] as? [[String: Any]] ?? []).map { Brush($0, defaults: NativeToolkit.defaults, pack: "Mine") }
    }
    static func save() {
        let o: [String: Any] = ["v": 1, "brushes": brushes.map { $0.dictionary() }]
        if let d = try? JSONSerialization.data(withJSONObject: o) { try? d.write(to: url, options: .atomic) }
    }
    static func upsert(_ b: Brush) {
        let m = Brush(b.dictionary(), defaults: NativeToolkit.defaults, pack: "Mine")
        if let i = brushes.firstIndex(where: { $0.id == m.id }) { brushes[i] = m } else { brushes.append(m) }
        save()
    }
    static func remove(_ id: String) { brushes.removeAll { $0.id == id }; save() }
    /// Keeps the newer edit of every brush when the other side has it too.
    static func merge(remote: [[String: Any]]) -> Bool {
        var changed = false
        for r in remote {
            guard let id = r["id"] as? String else { continue }
            let ru = (r["u"] as? Double) ?? Double(r["u"] as? Int ?? 0)
            if let i = brushes.firstIndex(where: { $0.id == id }) {
                if ru > brushes[i].updated { brushes[i] = Brush(r, defaults: NativeToolkit.defaults, pack: "Mine"); changed = true }
            } else { brushes.append(Brush(r, defaults: NativeToolkit.defaults, pack: "Mine")); changed = true }
        }
        if changed { save() }
        return changed
    }

    static var all: [NativeToolkit.Pack] {
        var p = NativeToolkit.packs
        if !brushes.isEmpty { p.append(NativeToolkit.Pack(name: "Mine", brushes: brushes)) }
        return p
    }
}
