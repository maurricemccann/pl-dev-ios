import SwiftUI

// Buddy in lessons (S348·9a3e). His drawn faces (his McCann pack: grin, clench; bundled with his yes 11-15), played by THE rig: the
// Blender FaceRig built this session (vault Generation Techniques/Blender/Buddy Face Rig, source pl-r1-buddy/tools/rig), exported to
// rig-default.json (bundled as buddy-rig.json: 43 numbers, 82 moves), the same file the R1 plays. This is the R1's RigTrack + ArtRig
// + ArtFace, ported: each frame starts at zero, adds breathing and the current move as differences from rest, and moves and scales his
// pieces from those numbers; nothing is redrawn. His ruling 11-15: "The phone plays the same 64 moves" (the export now holds 82).
// When Buddy reacts is Gemini's table (vault Plans/RESEARCH - BUDDY IN LESSONS (GEMINI, S348).md). The grin's mouth is his rubber band
// (crowned 11-15): his six drawn stages, closed to open, with HyperFrames in-betweens, 51 frames (buddy-grin-open-00..50, his drawings at
// 0/10/20/30/40/50; source vault Generation Techniques/Blender/Buddy Face Rig/mouth-hyperframes). The rig's mouth_open picks the frame.

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
            // his note 11-15 "eye movements are too slow": his eyes and pupils run 1.7x the move's clock (holding their last value)
            let fe = (k.hasPrefix("eye") || k.hasPrefix("pupil")) ? min(f * 1.7, Double(a.count - 1)) : f
            let i = min(Int(fe), a.count - 1), j = min(i + 1, a.count - 1)
            let v = a[i] + (a[j] - a[i]) * (fe - Double(i))
            out[k, default: 0] += v - (rest[k] ?? 0)
        }
        return true
    }
}

/// What Buddy is doing: which face, and the move he is playing (nil = breathing only).
@MainActor @Observable final class BuddyModel {
    enum Moment { case open, reading, right, wrong, streak, finish, gold, returned, pack }
    var move: String?
    var moveAt = Date()
    let born = Date()
    /// Where his finger last touched (global points) and when: Buddy's pupils follow it in lessons (his ask 11-15, "as you're doing
    /// them he's watching your moves"), then ease back to the rig's own look about 2 s after the last touch.
    @ObservationIgnored var lookAt: CGPoint?
    @ObservationIgnored var lookAtTime = Date.distantPast
    func look(_ p: CGPoint) { lookAt = p; lookAtTime = .now }
    private var lastReaction = Date.distantPast

    /// Gemini's table, played as rig moves: one reaction per event, a 3 s rest for the small ones.
    func react(_ m: Moment) {
        // the clench face is gone (his ruling 11-15, crossed out, "Everywhere"): every moment is a move on his grin
        let mv: String = {
            switch m {
            case .open: return "happy"
            case .reading: return "thinking"
            case .right: return "nod_yes"
            case .wrong: return "hmm"
            case .streak: return "laugh"
            case .finish: return "proud"
            case .gold: return "starstruck"
            case .returned: return "wake_stretch"
            case .pack: return "surprised"
            }
        }()
        let big: Bool = { switch m { case .finish, .gold, .pack, .returned, .streak: return true; default: return false } }()
        guard big || Date().timeIntervalSince(lastReaction) > 3 else { return }
        lastReaction = .now
        move = mv; moveAt = .now
        if m == .wrong { frownAt = .now }
        // ChatGPT's expression set (frames: 0 grin, 1 laugh, 2 big laugh, 3 smirk, 4 flat, 5 frown, 6 sad with tears, 7 angry, 8 shout,
        // 9 nervous, 10 sweat, 11 kiss, 12 sparkle, 13 sharp grin, 14 uneasy, 15 yawn); shown 2.4 s, then his mouth returns
        let e: Int? = {
            switch m {
            case .open: return 0
            case .reading: return 3
            case .right: return 12
            case .wrong: return 6
            case .streak: return 2
            case .finish: return 1
            case .gold: return 12
            case .returned: return 15
            case .pack: return 8
            }
        }()
        expression = e; expressionAt = .now
    }

    /// The frown (his ruling 11-15): on a wrong answer his mouth closes and turns upside down, holds, and turns back.
    /// 0 = his smile, 1 = fully flipped; a quarter second each way, held two seconds.
    @ObservationIgnored var frownAt = Date.distantPast
    @ObservationIgnored var expression: Int?
    @ObservationIgnored var expressionAt = Date.distantPast
    func expression(_ now: Date) -> Int? { now.timeIntervalSince(expressionAt) < 2.4 ? expression : nil }

    /// Which of his mouths Buddy wears: "grin" (his rubber-band grin) or "red" (his red-lip mouth, his GIF 11-15, "A second Buddy
    /// mouth"). Kept on the phone; holding Buddy swaps it.
    var mouthStyle: String = UserDefaults.standard.string(forKey: "buddy.mouth") ?? "grin"
    func swapMouth() { mouthStyle = mouthStyle == "grin" ? "red" : "grin"; UserDefaults.standard.set(mouthStyle, forKey: "buddy.mouth") }
    func frown(_ now: Date) -> Double {
        let t = now.timeIntervalSince(frownAt)
        guard t >= 0, t < 2.6 else { return 0 }
        let up = min(1, t / 0.25), down = min(1, max(0, (2.6 - t) / 0.35))
        let x = min(up, down)
        return x * x * (3 - 2 * x)
    }

    @ObservationIgnored private var deck: [String] = []

    /// A tap on Buddy in the title bar plays his next move: every rig move once, in a shuffled order, then a fresh shuffle
    /// (the house's "random = shuffled deck"). His ask 11-15: Buddy lives top-right so he can be seen tested.
    func playNext() {
        if deck.isEmpty { deck = (BuddyRig.shared?.moves.keys.filter { $0 != "breathing" } ?? []).shuffled() }
        guard let mv = deck.popLast() else { return }
        move = mv; moveAt = .now
    }

    /// The rig's numbers now: breathing plus the current move. When a one-shot move ends Buddy returns to the grin at rest.
    func numbers(_ now: Date) -> [String: Double] {
        var out: [String: Double] = [:]
        guard let rig = BuddyRig.shared else { return out }
        rig.add("breathing", ms: now.timeIntervalSince(born) * 1000, into: &out)
        if let mv = move, !rig.add(mv, ms: now.timeIntervalSince(moveAt) * 1000, into: &out) {
            Task { @MainActor in if self.move == mv { self.move = nil } }
        }
        return out
    }

    @ObservationIgnored private var mouthLevel = 0.0
    @ObservationIgnored private var mouthAt = Date.distantPast

    /// Which of his 51 mouth frames shows (0 = his closed drawing, 50 = his full grin). At rest, thinking and asleep the rig's mouth_open
    /// drives it (talking opens and closes through his stages); any other move is the full grin. The level travels at most one section
    /// (10 frames) per third of a second, so a change of move opens or closes through his drawings instead of jumping.
    func mouthFrame(_ n: [String: Double], now: Date) -> Int {
        if frown(now) > 0 { mouthLevel = 0; mouthAt = now; return 0 }   // a frown is his closed mouth, turned over
        let open = min(1, max(0, (BuddyRig.shared?.rest["mouth_open"] ?? 0) + (n["mouth_open"] ?? 0)))
        let target: Double = {
            switch move {
            case nil, "thinking", "hmm", "sleepy", "fall_asleep", "tired", "talking": return open
            default: return max(open, 1)
            }
        }()
        let step = min(0.1, max(0, now.timeIntervalSince(mouthAt))) * 0.6   // 0.2 of the range (10 of his frames) per 1/3 s
        mouthAt = now
        // lip sync (his ruling 11-15): while one of his recorded lines plays, the mouth follows the loudness of his own voice
        if let v = PracticeClips.shared.voiceLevel { mouthLevel = v; return Int((v * 50).rounded()) }
        mouthLevel = move == "talking" ? target : mouthLevel + max(-step, min(step, target - mouthLevel))   // speech follows the rig frame by frame
        return Int((mouthLevel * 50).rounded())
    }
}

struct BuddyFaceArt {
    struct Box: Decodable { let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat }
    struct Layout: Decodable { let w: CGFloat; let h: CGFloat; let parts: [String: Box] }
    let layout: Layout
    let pieces: [String: BuddyGlass]
    let mouthFrames: [BuddyGlass]   // his grin, closed to open: his own animation (his GIF 11-15, replaced the 51 in-betweens)
    let redFrames: [BuddyGlass]     // his red-lip mouth, closed to open, 12 frames (his GIF's opening half)
    let redFrown: [BuddyGlass]      // his red mouth from smile to frown, 16 frames (his second GIF, 11-15)
    let expressions: [BuddyGlass]   // ChatGPT's 16 2D expressions (his ruling 11-15)
    let lessonMouth: [BuddyGlass]   // ChatGPT's 16 glossy 3D mouth frames, worn in lessons (his ruling 11-15)

    @MainActor static let grin = load()

    /// His grin pieces as written by `.claude/scripts/pl-buddy-glass.py --masks` (his originals kept in the vault rig folder).
    static func load() -> BuddyFaceArt? {
        guard let url = Bundle.main.url(forResource: "buddy-grin-face", withExtension: "json"),
              let data = try? Data(contentsOf: url), let layout = try? JSONDecoder().decode(Layout.self, from: data) else { return nil }
        let tints = (Bundle.main.url(forResource: "buddy-glass", withExtension: "json").flatMap { try? Data(contentsOf: $0) })
            .flatMap { try? JSONDecoder().decode([String: [Double]].self, from: $0) } ?? [:]
        func glass(_ name: String) -> BuddyGlass? {
            func img(_ s: String) -> UIImage? { Bundle.main.url(forResource: "\(name)-\(s)", withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) } }
            guard let lines = img("lines") else { return nil }
            let c = tints[name].flatMap { $0.count == 3 ? Color(red: $0[0], green: $0[1], blue: $0[2]) : nil }
            return BuddyGlass(lines: lines, clear: img("clear"), tint: c == nil ? nil : img("tint"), colour: c)
        }
        var pieces: [String: BuddyGlass] = [:]
        for p in layout.parts.keys { if let g = glass("buddy-grin-\(p)") { pieces[p] = g } }
        var frames: [BuddyGlass] = []   // as many as he drew, read until the next is missing
        while let f = glass(String(format: "buddy-grin-open-%02d", frames.count)) { frames.append(f) }
        let red = (0...11).compactMap { glass(String(format: "buddy-red-open-%02d", $0)) }
        let frown = (0...15).compactMap { glass(String(format: "buddy-red-frown-%02d", $0)) }
        // whole pictures, drawn as they are (no glass split): ChatGPT's sets carry tongues, tears and sparkles in their own colours
        func plain(_ base: String) -> [BuddyGlass] {
            let s = (0...15).compactMap { i in Bundle.main.url(forResource: String(format: "\(base)-%02d", i), withExtension: "png")
                .flatMap { UIImage(contentsOfFile: $0.path) }.map { BuddyGlass(lines: $0, clear: nil, tint: nil, colour: nil) } }
            return s.count == 16 ? s : []
        }
        return pieces["mouth"] == nil ? nil : BuddyFaceArt(layout: layout, pieces: pieces, mouthFrames: frames.count > 1 ? frames : [],
                                                          redFrames: red.count == 12 ? red : [], redFrown: frown.count == 16 ? frown : [],
                                                          expressions: plain("buddy-expr"), lessonMouth: plain("buddy-gl3d"))
    }
}

/// One piece of his, ready for Apple's glass: his lines, the areas that are clear glass, and the areas that are tinted glass.
struct BuddyGlass {
    let lines: UIImage
    let clear: UIImage?
    let tint: UIImage?
    let colour: Color?
}

/// His face, moved by the rig's numbers (ArtRig.eye + ArtFace's mouth and pupils), in the box it is given.
struct BuddyView: View {
    let model: BuddyModel
    var trail: [String: CGSize] = [:]   // per-piece lag on his rope (the ragdoll squish); empty everywhere else
    var pinned = false                  // on his rope: no whole-face drift, so the face never leaves the rope's tip (his note 11-15)
    var lesson = false                  // in a lesson he wears ChatGPT's glossy 3D mouth (his ruling 11-15)
    @State private var centre = CGPoint.zero   // his centre on screen (global), so his eyes know where the finger is
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion && model.move == nil)) { tl in   // a move asked for always plays; Reduce Motion only stills the idle breathing
            GeometryReader { geo in
                if let art = BuddyFaceArt.grin {
                    let n = watching(reduceMotion && model.move == nil ? [:] : model.numbers(tl.date), now: tl.date)
                    face(art, size: geo.size, n: n, now: tl.date)
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { centre = CGPoint(x: $0.midX, y: $0.midY) }
        .accessibilityLabel("Buddy" + (model.move.map { ", \($0.replacingOccurrences(of: "_", with: " "))" } ?? ""))
    }

    private static func cl(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }

    /// While a finger touched within the last 2 s, his pupils point at it (reaching further than a rig move, 0.18 of the eye),
    /// fading back to the rig's own pupils over the following half second.
    private func watching(_ n0: [String: Double], now: Date) -> [String: Double] {
        var n = n0; n["look_reach"] = 0.10
        guard let p = model.lookAt else { return n }
        let age = now.timeIntervalSince(model.lookAtTime)
        guard age < 2.5 else { return n }
        let w = age < 2 ? 1.0 : (2.5 - age) / 0.5
        let dx = Double(p.x - centre.x), dy = Double(p.y - centre.y), d = max(1, (dx * dx + dy * dy).squareRoot())
        let k = min(1, d / 90)   // reaches the eye's edge sooner (his note 11-15, too slow)
        n["pupil_x"] = (n0["pupil_x"] ?? 0) * (1 - w) + dx / d * k * w
        n["pupil_y"] = (n0["pupil_y"] ?? 0) * (1 - w) + dy / d * k * w
        n["look_reach"] = 0.10 + 0.16 * w
        return n
    }

    private func face(_ a: BuddyFaceArt, size: CGSize, n: [String: Double], now: Date) -> some View {
        let r: (String) -> CGFloat = { CGFloat(n[$0] ?? 0) }   // one number type throughout: mixed Double/CGFloat stalls the type checker
        let k = min(size.width / a.layout.w, size.height / a.layout.h) * 0.92
        let ox = (size.width - a.layout.w * k) / 2, oy = (size.height - a.layout.h * k) / 2
        func rect(_ p: String) -> CGRect? {
            guard let b = a.layout.parts[p] else { return nil }
            return CGRect(x: ox + b.x * k, y: oy + b.y * k, width: b.w * k, height: b.h * k)
        }
        let eyeW = (a.layout.parts["eyeL"]?.w ?? 200) * k
        let level = model.mouthFrame(n, now: now)   // 0 closed ... 50 his full grin (read once: it moves the mouth's state)
        let red = model.mouthStyle == "red" && !a.redFrames.isEmpty
        // the red mouth frowns through his own sixteen drawings (smile to frown and back); the grin turns over instead
        let frownNow = model.frown(now), redFrown = red && a.redFrown.count == 16 && frownNow > 0
        // in a lesson: ChatGPT's 3D mouth opens through its frames 0-4, a wrong answer shows its grimace (12);
        // elsewhere a moment shows its expression for 2.4 s; otherwise his own mouth
        let lessonM = lesson && !a.lessonMouth.isEmpty
        let expr = lessonM ? nil : model.expression(now).flatMap { a.expressions.isEmpty ? nil : a.expressions[$0] }
        let mf = lessonM ? a.lessonMouth[frownNow > 0 ? 12 : min(4, Int((Double(level) / 50 * 4).rounded()))]
            : expr ?? (redFrown ? a.redFrown[min(15, Int((frownNow * 15).rounded()))]
            : (red ? a.redFrames[min(11, Int((Double(level) / 50 * 11).rounded()))]
               : (a.mouthFrames.isEmpty ? nil : a.mouthFrames[min(a.mouthFrames.count - 1, Int((Double(level) / 50 * Double(a.mouthFrames.count - 1)).rounded()))])))
        // the whole face: a small drift, turn and stretch (the rig's face_* numbers)
        let fx = pinned ? 0 : r("face_x") * size.width * 0.12, fy = pinned ? 0 : r("face_y") * size.width * 0.12, frot = r("face_rot")
        let fsx = Self.cl(1 + r("face_sx"), 0.85, 1.08), fsy = Self.cl(1 + r("face_sy"), 0.85, 1.08)
        return ZStack(alignment: .topLeading) {
            ForEach(["L", "R"], id: \.self) { s in
                if let e = rect("eye" + s), let img = a.pieces["eye" + s] {
                    // ArtRig.eye: move by eye widths, the lids squash his eye between them (never a hard crop), a lid's slant leans it
                    let uc = Self.cl(r("eye\(s)_lidU_y"), 0, 0.9), lc = Self.cl(r("eye\(s)_lidL_y"), 0, 0.9), keep = max(0.2, 1 - uc - lc)
                    let lidShift = (uc * e.height + keep * e.height / 2) - e.height / 2
                    let dir: CGFloat = s == "L" ? 1 : -1
                    ZStack(alignment: .topLeading) {
                        BuddyGlassPiece(glass: img).frame(width: e.width, height: e.height)
                        if let p = rect("pupil" + s), let pi = a.pieces["pupil" + s] {
                            BuddyGlassPiece(glass: pi).frame(width: p.width, height: p.height)
                                .scaleEffect(max(0.5, 1 + r("pupil_size")))
                                .offset(x: p.minX - e.minX + e.width * Self.cl(r("pupil_x"), -1, 1) * r("look_reach"),
                                        y: p.minY - e.minY + e.height * Self.cl(r("pupil_y"), -1, 1) * r("look_reach"))
                        }
                    }
                    .frame(width: e.width, height: e.height, alignment: .topLeading)
                    .scaleEffect(x: Self.cl(1 + r("eye\(s)_sx"), 0.6, 1.08), y: Self.cl(1 + r("eye\(s)_sy"), 0.5, 1.08) * keep, anchor: .center)
                    .rotationEffect(.degrees(r("eye\(s)_rot") + Self.cl(r("eye\(s)_lidU_ang"), -35, 35) * dir * 0.4))
                    .offset(x: e.minX + r("eye\(s)_x") * e.width + (trail["eye" + s]?.width ?? 0), y: e.minY + r("eye\(s)_y") * e.width + lidShift + (trail["eye" + s]?.height ?? 0))
                }
            }
            if let m = rect("mouth"), let img = mf ?? a.pieces["mouth"] {
                // ArtFace's mouth: width stretches it (capped), the curve lifts it, the rig moves it by eye widths. His frames do the
                // opening; each frame is his full 1132x560 canvas with the open grin (988x559) at its top-left, so it is drawn at the
                // mouth box scaled by 1132/988 x 560/559, anchored top-left, and his full grin lands exactly on the old mouth piece.
                let msx = Self.cl(1 + r("mouth_w") * 0.5, 0.88, 1.08)
                let flip = (redFrown || lessonM || expr != nil) ? 1 : CGFloat(1 - 2 * frownNow)   // the grin's frown turns his smile over; the red mouth draws its own
                let msy: CGFloat = (mf == nil ? Self.cl(1 + r("mouth_open") * 0.15 + r("mouth_curve") * 0.05, 0.9, 1.08) : Self.cl(1 + r("mouth_curve") * 0.05, 0.9, 1.08)) * flip
                // his frames are drawn the mouth box's width at their own proportions, centred on the box's height (red 354x266,
                // his yellow grin cropped to one shared box for all its frames)
                let ar: CGFloat = img.lines.size.width > 0 ? img.lines.size.height / img.lines.size.width : m.height / m.width
                let fw: CGFloat = m.width
                let fh: CGFloat = mf == nil ? m.height : m.width * ar
                let fy: CGFloat = mf == nil ? 0 : (m.height - fh) / 2
                BuddyGlassPiece(glass: img).frame(width: fw, height: fh, alignment: .topLeading)
                    .scaleEffect(x: msx, y: msy, anchor: .center)   // centre, so the frown turns his mouth over in place
                    .offset(x: m.minX + r("mouth_x") * eyeW + (trail["mouth"]?.width ?? 0), y: m.minY + fy + r("mouth_y") * eyeW - r("mouth_curve") * 6 * k + (trail["mouth"]?.height ?? 0))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(x: fsx, y: fsy)
        .rotationEffect(.degrees(frot))
        .offset(x: fx, y: fy)
    }
}

/// One of his pieces: his whites as he drew them, his colours in Apple's Liquid Glass tinted his own colour (his rulings 11-15). Was: the clear areas (eye
/// whites, teeth) are clear glass, his colours are glass tinted with his own colour, both in the piece's exact shape (the glass is masked
/// by the layer's alpha); his lines are drawn on top, untouched.
struct BuddyGlassPiece: View {
    let glass: BuddyGlass

    var body: some View {
        ZStack {
            if let c = glass.clear {
                // his whites drawn as he drew them (his ruling 11-15, "Back to his drawing": clear glass let the rope show through his eyes)
                Image(uiImage: c).resizable().aspectRatio(contentMode: .fit)
            }
            if let t = glass.tint, let col = glass.colour {
                Color.clear.glassEffect(.clear.tint(col), in: .rect).mask(Image(uiImage: t).resizable().aspectRatio(contentMode: .fit))
            }
            Image(uiImage: glass.lines).resizable().aspectRatio(contentMode: .fit)
        }
    }
}
