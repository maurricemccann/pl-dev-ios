import Foundation

/// A brush, as the laptop's toolkit describes it: numbers and words keyed by the toolkit's own parameter names, over the toolkit defaults.
/// `NativeToolkit.json` is a copy of the packs and defaults out of `C:\dev\pl-toolkit` (the laptop's `src/toolkit.js`); regenerate it when the toolkit changes.
struct Brush: Sendable, Identifiable {
    let id: String
    let name: String
    let pack: String
    let note: String?
    let tip: String?
    private let num: [String: Double]
    private let txt: [String: String]

    func n(_ k: String) -> Double { num[k] ?? 0 }
    func t(_ k: String) -> String { txt[k] ?? "" }

    init(_ d: [String: Any], defaults: [String: Any], pack: String) {
        var num: [String: Double] = [:], txt: [String: String] = [:]
        for (k, v) in defaults.merging(d, uniquingKeysWith: { _, b in b }) {
            if let x = v as? Double { num[k] = x } else if let x = v as? Int { num[k] = Double(x) } else if let x = v as? String { txt[k] = x }
        }
        self.num = num; self.txt = txt
        id = d["id"] as? String ?? "brush"; name = d["name"] as? String ?? "Brush"; self.pack = pack
        note = d["note"] as? String; tip = d["tip"] as? String
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
}

enum NativeToolkit {
    struct Pack: Identifiable { let name: String; let brushes: [Brush]; var id: String { name } }
    struct Canvas { let name: String; let w: Int; let h: Int }

    /// Loaded once from the bundle. A missing or damaged file leaves one plain round brush, never a crash.
    nonisolated(unsafe) static let loaded: (defaults: [String: Any], packs: [Pack], canvases: [Canvas]) = {
        guard let url = Bundle.main.url(forResource: "NativeToolkit", withExtension: "json"), let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let defaults = o["defaults"] as? [String: Any] else {
            return ([:], [Pack(name: "Basics", brushes: [Brush.plain(defaults: [:])])], [])
        }
        let packs = (o["packs"] as? [[String: Any]] ?? []).map { p -> Pack in
            let name = p["name"] as? String ?? "Pack"
            return Pack(name: name, brushes: (p["brushes"] as? [[String: Any]] ?? []).map { Brush($0, defaults: defaults, pack: name) })
        }
        let presets = ((o["canvases"] as? [String: Any])?["presets"] as? [[Any]] ?? []).compactMap { r -> Canvas? in
            guard r.count == 3, let n = r[0] as? String, let w = r[1] as? Int, let h = r[2] as? Int else { return nil }
            return Canvas(name: n, w: w, h: h)
        }
        return (defaults, packs, presets)
    }()

    static var packs: [Pack] { loaded.packs }
    static var all: [Brush] { loaded.packs.flatMap(\.brushes) }
    static var round: Brush { all.first { $0.id == "round" } ?? all.first ?? Brush.plain(defaults: loaded.defaults) }
}
