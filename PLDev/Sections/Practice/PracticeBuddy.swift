import SwiftUI

// Buddy in lessons (S348·9a3e). His drawn faces (his McCann pack: grin, clench; bundled with his yes 11-15), played by THE rig: the
// Blender FaceRig built this session (vault Generation Techniques/Blender/Buddy Face Rig, source pl-r1-buddy/tools/rig), exported to
// rig-default.json (bundled as buddy-rig.json: 43 numbers, 82 moves), the same file the R1 plays. This is the R1's RigTrack + ArtRig
// + ArtFace, ported: each frame starts at zero, adds breathing and the current move as differences from rest, and moves and scales his
// pieces from those numbers; nothing is redrawn. His ruling 11-15: "The phone plays the same 64 moves" (the export now holds 82).
// When Buddy reacts is Gemini's table (vault Plans/RESEARCH - BUDDY IN LESSONS (GEMINI, S348).md). His two new grin mouths (11-15):
// the open grin without the outer outline, and his closed mouth for rest, thinking and sleep.

/// The rig file: rest values and moves, sampled by elapsed time (RigTrack.java).
final class BuddyRig: @unchecked Sendable {
    struct Move { let ms: Double; let loop: Bool; let v: [String: [Double]] }
    let fps: Double
    let rest: [String: Double]
    let moves: [String: Move]

    static let shared: BuddyRig? = {
        guard let u = Bundle.main.url(forResource: "buddy-rig", withExtension: "json"), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let fps = (o["fps"] as? NSNumber)?.doubleValue, let rest = o["rest"] as? [String: NSNumber], let mv = o["moves"] as? [String: [String: Any]] else { return nil }
        var moves: [String: Move] = [:]
        for (name, m) in mv {
            let vv = (m["v"] as? [String: [NSNumber]] ?? [:]).mapValues { $0.map(\.doubleValue) }
            moves[name] = Move(ms: (m["ms"] as? NSNumber)?.doubleValue ?? 1000, loop: (m["loop"] as? Bool) ?? false, v: vv)
        }
        return BuddyRig(fps: fps, rest: rest.mapValues(\.doubleValue), moves: moves)
    }()

    init(fps: Double, rest: [String: Double], moves: [String: Move]) { self.fps = fps; self.rest = rest; self.moves = moves }

    /// Adds (value - rest) of every number the move animates at `ms` into `out`; false once a one-shot move has ended.
    @discardableResult func add(_ move: String, ms: Double, into out: inout [String: Double]) -> Bool {
        guard let m = moves[move], ms >= 0 else { return false }
        var t = ms
        if t >= m.ms { guard m.loop else { return false }; t = t.truncatingRemainder(dividingBy: m.ms) }
        let f = t * fps / 1000
        for (k, a) in m.v where !a.isEmpty {
            let i = min(Int(f), a.count - 1), j = min(i + 1, a.count - 1)
            let v = a[i] + (a[j] - a[i]) * (f - Double(i))
            out[k, default: 0] += v - (rest[k] ?? 0)
        }
        return true
    }
}

/// What Buddy is doing: which face, and the move he is playing (nil = breathing only).
@MainActor @Observable final class BuddyModel {
    enum Moment { case open, reading, right, wrong, streak, finish, gold, returned, pack }
    var face = "grin"
    var move: String?
    var moveAt = Date()
    let born = Date()
    private var lastReaction = Date.distantPast

    /// Gemini's table, played as rig moves: one reaction per event, a 3 s rest for the small ones.
    func react(_ m: Moment) {
        let (f, mv): (String, String) = {
            switch m {
            case .open: return ("grin", "happy")
            case .reading: return ("grin", "thinking")
            case .right: return ("grin", "nod_yes")
            case .wrong: return ("clench", "hmm")
            case .streak: return ("grin", "laugh")
            case .finish: return ("grin", "proud")
            case .gold: return ("clench", "starstruck")
            case .returned: return ("grin", "wake_stretch")
            case .pack: return ("clench", "surprised")
            }
        }()
        let big: Bool = { switch m { case .finish, .gold, .pack, .returned, .streak: return true; default: return false } }()
        guard big || Date().timeIntervalSince(lastReaction) > 3 else { return }
        lastReaction = .now
        face = f; move = mv; moveAt = .now
    }

    /// The rig's numbers now: breathing plus the current move. When a one-shot move ends Buddy returns to the grin at rest.
    func numbers(_ now: Date) -> [String: Double] {
        var out: [String: Double] = [:]
        guard let rig = BuddyRig.shared else { return out }
        rig.add("breathing", ms: now.timeIntervalSince(born) * 1000, into: &out)
        if let mv = move, !rig.add(mv, ms: now.timeIntervalSince(moveAt) * 1000, into: &out) {
            Task { @MainActor in if self.move == mv { self.move = nil; self.face = "grin" } }
        }
        return out
    }

    /// His closed mouth at rest, while thinking and asleep; while talking it opens past a third of the way (grin only).
    func mouthClosed(_ n: [String: Double]) -> Bool {
        switch move {
        case nil, "thinking", "hmm", "sleepy", "fall_asleep", "tired": return true
        case "talking": return (n["mouth_open"] ?? 0) < 0.15
        default: return false
        }
    }
}

struct BuddyFaceArt {
    struct Box: Decodable { let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat }
    struct Layout: Decodable { let w: CGFloat; let h: CGFloat; let parts: [String: Box] }
    let name: String
    let layout: Layout
    let images: [String: UIImage]

    @MainActor static let grin = load("grin")
    @MainActor static let clench = load("clench")

    static func load(_ name: String) -> BuddyFaceArt? {
        guard let url = Bundle.main.url(forResource: "buddy-\(name)-face", withExtension: "json"),
              let data = try? Data(contentsOf: url), let layout = try? JSONDecoder().decode(Layout.self, from: data) else { return nil }
        var imgs: [String: UIImage] = [:]
        for p in Array(layout.parts.keys) + ["mouthClosed"] {
            if let u = Bundle.main.url(forResource: "buddy-\(name)-\(p)", withExtension: "png"), let i = UIImage(contentsOfFile: u.path) { imgs[p] = i }
        }
        return imgs["mouth"] == nil ? nil : BuddyFaceArt(name: name, layout: layout, images: imgs)
    }
}

/// His face, moved by the rig's numbers (ArtRig.eye + ArtFace's mouth and pupils), in the box it is given.
struct BuddyView: View {
    let model: BuddyModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            GeometryReader { geo in
                if let art = model.face == "clench" ? BuddyFaceArt.clench : BuddyFaceArt.grin {
                    let n = reduceMotion ? [:] : model.numbers(tl.date)
                    face(art, size: geo.size, n: n)
                }
            }
        }
        .accessibilityLabel("Buddy" + (model.move.map { ", \($0.replacingOccurrences(of: "_", with: " "))" } ?? ""))
    }

    private static func cl(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }

    private func face(_ a: BuddyFaceArt, size: CGSize, n: [String: Double]) -> some View {
        let r: (String) -> CGFloat = { CGFloat(n[$0] ?? 0) }   // one number type throughout: mixed Double/CGFloat stalls the type checker
        let k = min(size.width / a.layout.w, size.height / a.layout.h) * 0.92
        let ox = (size.width - a.layout.w * k) / 2, oy = (size.height - a.layout.h * k) / 2
        func rect(_ p: String) -> CGRect? {
            guard let b = a.layout.parts[p] else { return nil }
            return CGRect(x: ox + b.x * k, y: oy + b.y * k, width: b.w * k, height: b.h * k)
        }
        let eyeW = (a.layout.parts["eyeL"]?.w ?? 200) * k
        let closed = model.mouthClosed(n) && a.images["mouthClosed"] != nil
        // the whole face: a small drift, turn and stretch (the rig's face_* numbers)
        let fx = r("face_x") * size.width * 0.12, fy = r("face_y") * size.width * 0.12, frot = r("face_rot")
        let fsx = Self.cl(1 + r("face_sx"), 0.85, 1.08), fsy = Self.cl(1 + r("face_sy"), 0.85, 1.08)
        return ZStack(alignment: .topLeading) {
            ForEach(["L", "R"], id: \.self) { s in
                if let e = rect("eye" + s), let img = a.images["eye" + s] {
                    // ArtRig.eye: move by eye widths, the lids squash his eye between them (never a hard crop), a lid's slant leans it
                    let uc = Self.cl(r("eye\(s)_lidU_y"), 0, 0.9), lc = Self.cl(r("eye\(s)_lidL_y"), 0, 0.9), keep = max(0.2, 1 - uc - lc)
                    let lidShift = (uc * e.height + keep * e.height / 2) - e.height / 2
                    let dir: CGFloat = s == "L" ? 1 : -1
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: img).resizable().frame(width: e.width, height: e.height)
                        if let p = rect("pupil" + s), let pi = a.images["pupil" + s] {
                            Image(uiImage: pi).resizable().frame(width: p.width, height: p.height)
                                .scaleEffect(max(0.5, 1 + r("pupil_size")))
                                .offset(x: p.minX - e.minX + e.width * Self.cl(r("pupil_x"), -1, 1) * 0.10,
                                        y: p.minY - e.minY + e.height * Self.cl(r("pupil_y"), -1, 1) * 0.10)
                        }
                    }
                    .frame(width: e.width, height: e.height, alignment: .topLeading)
                    .scaleEffect(x: Self.cl(1 + r("eye\(s)_sx"), 0.6, 1.08), y: Self.cl(1 + r("eye\(s)_sy"), 0.5, 1.08) * keep, anchor: .center)
                    .rotationEffect(.degrees(r("eye\(s)_rot") + Self.cl(r("eye\(s)_lidU_ang"), -35, 35) * dir * 0.4))
                    .offset(x: e.minX + r("eye\(s)_x") * e.width, y: e.minY + r("eye\(s)_y") * e.width + lidShift)
                }
            }
            if let m = rect("mouth"), let img = closed ? a.images["mouthClosed"] : a.images["mouth"] {
                // ArtFace's mouth: width and open stretch it (capped), the curve lifts it, the rig moves it by eye widths
                let msx = Self.cl(1 + r("mouth_w") * 0.5, 0.88, 1.08)
                let msy = Self.cl(1 + r("mouth_open") * 0.15 + r("mouth_curve") * 0.05, 0.9, 1.08)
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: m.width, height: m.height)
                    .scaleEffect(x: msx, y: msy, anchor: .bottom)
                    .offset(x: m.minX + r("mouth_x") * eyeW, y: m.minY + r("mouth_y") * eyeW - r("mouth_curve") * 6 * k)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(x: fsx, y: fsy)
        .rotationEffect(.degrees(frot))
        .offset(x: fx, y: fy)
    }
}
