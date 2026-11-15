import SwiftUI

// Buddy in lessons (S348·9a3e). His ruling: "Only my drawn ones" -> his McCann pack (the R1 Buddy's `packs/mccann`: the grin and
// the clench, his own eyes, pupils and mouths, bundled with his yes 11-15). Motion is the R1's `ArtFace.java` ported: only moves and
// scales of his pieces, never a redraw. When and how Buddy reacts is Gemini's table (his "Ask Gemini";
// vault Plans/RESEARCH - BUDDY IN LESSONS (GEMINI, S348).md): one reaction per event, a 3 s rest, scale never past 108 %.

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
        for p in layout.parts.keys {
            if let u = Bundle.main.url(forResource: "buddy-\(name)-\(p)", withExtension: "png"), let i = UIImage(contentsOfFile: u.path) { imgs[p] = i }
        }
        return imgs["mouth"] == nil ? nil : BuddyFaceArt(name: name, layout: layout, images: imgs)
    }
}

enum BuddyState: String { case idle, happy, laugh, talk, surprised, sleepy, think }

/// Who Buddy is right now. `react` follows Gemini's table; a reaction inside the rest is dropped, never queued.
@MainActor @Observable final class BuddyModel {
    enum Moment { case open, reading, right, wrong, streak, finish, gold, returned, pack }
    var face = "grin"
    var state = BuddyState.idle
    private var lastReaction = Date.distantPast
    private var token = 0

    func react(_ m: Moment) {
        let (f, s, secs): (String, BuddyState, Double) = {
            switch m {
            case .open: return ("grin", .happy, 1.2)
            case .reading: return ("grin", .think, 1.5)
            case .right: return ("grin", .happy, 1.0)
            case .wrong: return ("clench", .surprised, 0.8)
            case .streak: return ("grin", .laugh, 1.5)
            case .finish: return ("grin", .happy, 2.0)
            case .gold: return ("clench", .laugh, 2.5)
            case .returned: return ("grin", .sleepy, 2.0)
            case .pack: return ("clench", .surprised, 1.2)
            }
        }()
        // the big moments always play; the small ones respect a 3 s rest
        let big: Bool = { switch m { case .finish, .gold, .pack, .returned, .streak: return true; default: return false } }()
        guard big || Date().timeIntervalSince(lastReaction) > 3 else { return }
        lastReaction = .now; token += 1
        let t = token
        face = f; state = s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(secs))
            guard t == token else { return }
            face = "grin"; state = .idle
        }
    }
}

/// His face, drawn from his pieces. `size` is the box it fits in.
struct BuddyView: View {
    let model: BuddyModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            GeometryReader { geo in
                if let art = model.face == "clench" ? BuddyFaceArt.clench : BuddyFaceArt.grin {
                    face(art, size: geo.size, t: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityLabel("Buddy, \(model.state.rawValue)")
    }

    private func face(_ a: BuddyFaceArt, size: CGSize, t: Double) -> some View {
        let grin = a.images["pupilL"] != nil
        let k = min(size.width / a.layout.w, size.height / a.layout.h)
        let ox = (size.width - a.layout.w * k) / 2, oy = (size.height - a.layout.h * k) / 2
        // ArtFace's state table (eye sx/sy, mouth sx/sy, mouth dy, mouth rot, pupil x/y, pupil scale), capped at 1.08 (Gemini)
        var esx = 1.0, esy = 1.0, msx = 1.0, msy = 1.0, mdy = 0.0, mrot = 0.0, ppx = 0.0, ppy = 0.0, pps = 1.0
        let wave = sin(t * 2 * .pi / (grin ? 3.2 : 2.8))
        switch model.state {
        case .happy: if grin { ppy = -0.07; mrot = -3 } else { esy = 0.85; mdy = -8 }
        case .laugh:
            let hi = Int(t * 1000 / (grin ? 120 : 100)) % 2 == 0
            if grin { msx = 1.05; msy = hi ? 1.08 : 1.06; esy = 0.85 } else { mrot = hi ? 2 : -2; msy = hi ? 1.08 : 1; esy = 0.75 }
        case .talk:
            let u = abs(sin(t * .pi / (grin ? 0.135 : 0.12)))
            if grin { msy = 1 + 0.08 * u; msx = 1 + 0.03 * u } else { mdy = (u - 0.5) * 8; msy = 1.05; msx = 0.98 }
        case .surprised: esx = grin ? 1.08 : 1.05; esy = 1.08; msy = 1.08; msx = grin ? 0.9 : 1; pps = 0.85
        case .sleepy: esy = grin ? 0.6 : 0.65; ppy = 0.12; mdy = grin ? 8 : 0; msy = 0.9
        case .think: if grin { ppx = 0.13; ppy = -0.13; mrot = 4 } else { mrot = -3; msx = 0.95; msy = 0.95 }
        case .idle:
            if grin { mrot = sin(t * 2 * .pi / 4.5); ppx = sin(t * 0.7) * 0.08; ppy = cos(t * 0.5) * 0.06 } else { mdy = sin(t * 2 * .pi / 4) * 2 }
        }
        let eyeBreath = 1 + (grin ? 0.01 : 0.02) * wave, mouthBreath = 1 + 0.02 * wave
        let blink = grin && (Int(t * 10) % 47 == 0) ? 0.08 : 1.0   // a short blink every ~4.7 s: the grin's whites squash to a slit
        func rect(_ n: String) -> CGRect? {
            guard let b = a.layout.parts[n] else { return nil }
            return CGRect(x: ox + b.x * k, y: oy + b.y * k, width: b.w * k, height: b.h * k)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(["L", "R"], id: \.self) { side in
                if let e = rect("eye" + side), let img = a.images["eye" + side] {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: img).resizable().frame(width: e.width, height: e.height)
                        if let p = rect("pupil" + side), let pi = a.images["pupil" + side] {
                            Image(uiImage: pi).resizable().frame(width: p.width, height: p.height)
                                .scaleEffect(pps)
                                .offset(x: p.minX - e.minX + e.width * ppx, y: p.minY - e.minY + e.height * ppy)
                        }
                    }
                    .frame(width: e.width, height: e.height, alignment: .topLeading)
                    .scaleEffect(x: min(1.08, esx), y: min(1.08, esy * eyeBreath) * blink, anchor: .center)
                    .offset(x: e.minX, y: e.minY)
                }
            }
            if let m = rect("mouth"), let img = a.images["mouth"] {
                Image(uiImage: img).resizable().frame(width: m.width, height: m.height)
                    .scaleEffect(x: min(1.08, msx), y: min(1.08, msy * mouthBreath), anchor: .bottom)
                    .rotationEffect(.degrees(mrot), anchor: UnitPoint(x: 0.42, y: 0.5))
                    .offset(x: m.minX, y: m.minY + mdy * k * 2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
