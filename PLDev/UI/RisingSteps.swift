import SwiftUI
import UserNotifications

// What each answer gets (his "just do the whole build", 11-26; the vault's Rising Scale spec). The screen is keyed on what he
// tapped and aims one step up: control from Heavy, cooling from Hot, loosening from Low, and so on. His call: no helpline button.

struct RisingStep {
    /// OKLCH hue, chroma and ground lightness; `turn` is how far the accent's hue sits from the ground's. nil hue = the date's own.
    let hue: Double?, chroma: Double, light: Double, turn: Double
    let radius: Double, space: Double, tile: String
    let calm: Bool
    /// nil = the date's wallpaper.
    let wall: String?
    let title: String, face: String, side: CGFloat
    let lines: [String]
    /// The rest of the look by band (his list 11-26 4:00 PM): panel and tile shape, type, text and tile size, the curves' tiling,
    /// motion pace (slower is cooler and calmer), Home's tiles that raise the scale first, and Hawkins's label.
    var card = PLThemePreset.Card.frosted, look = "glass", titleFace = "v1", textFace = "jost"
    var textScale = 1.0, columns = 3, repeatSize = 300.0, curves = 0.5, pace = 1.0
    var lifts: [String] = []
    var hawkins = ""
    /// The accent's chroma (Duet job 71, section 1: chroma carries energy, so it rises up the bands); nil = the ground's.
    var pop: Double? = nil
    /// Duet job 71's exact colours (section 1 table), OKLCH L C H: ground, surface, text, muted, accent. Every pair clears 4.5:1.
    var oklch: [[Double]] = []

    static func of(_ b: Band) -> RisingStep {
        switch b {
        case .heavy: heavy
        case .hot: hot
        case .low: low
        case .stuck: stuck
        case .steady: steady
        case .rising: rising
        case .lit: lit
        }
    }

    // Buddy's lines are working drafts for him to rewrite; the feed's `buddy` block (keys heavy ... lit) replaces them over the air.
    private static let heavy = RisingStep(hue: 50, chroma: 0.024, light: 0.17, turn: -2, radius: 1.5, space: 1.2, tile: "circle", calm: true,
        wall: "code|rise-lamp", title: "One small thing", face: "calm", side: 112,
        lines: ["Heavy is allowed. One small thing, then rest."],
        card: .solid, look: "flat", titleFace: "bundle:Literata-Regular", textFace: "bundle:Literata-Regular",
        textScale: 1.12, columns: 2, repeatSize: 420, curves: 0.2, pace: 1.6,
        lifts: ["gate", "practice", "companion", "paint"], hawkins: "Grief, 75", pop: 0.05,
        oklch: [[0.17, 0.012, 50], [0.22, 0.016, 50], [0.86, 0.012, 60], [0.68, 0.012, 60], [0.62, 0.050, 48]])
    private static let hot = RisingStep(hue: 45, chroma: 0.020, light: 0.18, turn: 190, radius: 1.5, space: 1.2, tile: "circle", calm: true,
        wall: "code|rise-water", title: "Cool it first", face: "calm", side: 112,
        lines: ["Anger means something matters. Cool it first, then decide."],
        card: .solid, look: "flat", titleFace: "bundle:Literata-Regular", textFace: "bundle:Literata-Regular",
        textScale: 1.08, columns: 2, repeatSize: 400, curves: 0.2, pace: 1.6,
        lifts: ["gate", "practice", "paint", "companion"], hawkins: "Anger, 150", pop: 0.035,
        oklch: [[0.18, 0.010, 45], [0.23, 0.008, 60], [0.87, 0.008, 240], [0.69, 0.008, 240], [0.64, 0.035, 235]])
    private static let low = RisingStep(hue: 235, chroma: 0.040, light: 0.19, turn: -25, radius: 1.5, space: 1.1, tile: "squircle", calm: true,
        wall: "code|rise-path", title: "Let it loosen", face: "calm", side: 144,
        lines: ["Worry is a forecast, not a fact. Walk ten minutes, then look again."],
        titleFace: "v1", textFace: "bundle:Literata-Regular",
        textScale: 1.05, repeatSize: 360, curves: 0.35, pace: 1.3,
        lifts: ["practice", "gate", "paint", "companion", "library"], hawkins: "Fear, 100", pop: 0.05,
        oklch: [[0.19, 0.020, 235], [0.24, 0.025, 225], [0.88, 0.015, 220], [0.70, 0.015, 220], [0.68, 0.050, 210]])
    private static let stuck = RisingStep(hue: 195, chroma: 0.044, light: 0.20, turn: -25, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: "code|rise-table", title: "One step", face: "happy", side: 144,
        lines: ["Stuck asks for one small move. Pick the first step and stop there.",
                "Boredom is a quiet doorway. Picture one room of the life you want, down to the light."],
        card: .outline, look: "flat",
        lifts: ["paint", "practice", "composer", "school", "capture"], hawkins: "Neutrality, 250", pop: 0.06,
        oklch: [[0.20, 0.022, 195], [0.25, 0.028, 185], [0.89, 0.015, 180], [0.71, 0.015, 180], [0.71, 0.060, 170]])
    private static let steady = RisingStep(hue: 155, chroma: 0.050, light: 0.21, turn: -65, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: "code|rise-window", title: "Add a little", face: "happy", side: 144,
        lines: ["Steady is a good base. Add one thing that moves the work forward.",
                "Hope is a real step up. Write one line about the version of you who has plenty."],
        titleFace: "bundle:AvenirNext-Bold", textFace: "bundle:AvenirNext-Regular", pace: 0.9,
        lifts: ["paint", "practice", "capture", "composer", "shop", "school"], hawkins: "Willingness, 310", pop: 0.08,
        oklch: [[0.21, 0.025, 155], [0.26, 0.032, 150], [0.90, 0.020, 110], [0.72, 0.020, 110], [0.76, 0.080, 90]])
    private static let rising = RisingStep(hue: 80, chroma: 0.060, light: 0.23, turn: 2, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: "curves", title: "Make something", face: "excited", side: 144,
        lines: ["This is the practice working. Put it into one thing you make tonight.",
                "Luxury living is a way of standing in the world. You are standing in it now."],
        card: .clear, titleFace: "bundle:Futura-Bold", textFace: "bundle:Futura-Medium", repeatSize: 240, curves: 0.7, pace: 0.8,
        lifts: ["paint", "capture", "composer", "shop", "curate", "congregation"], hawkins: "Love, 500", pop: 0.11,
        oklch: [[0.23, 0.030, 80], [0.29, 0.040, 80], [0.92, 0.030, 85], [0.74, 0.030, 85], [0.80, 0.110, 82]])
    private static let lit = RisingStep(hue: 60, chroma: 0.090, light: 0.25, turn: 20, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: nil, title: "Keep this", face: "excited", side: 144,
        lines: ["Remember this. Leave yourself a note for a harder night.",
                "Good nights add up. Keep this one as a marker for the next."],
        card: .clear, look: "aurora", titleFace: "bundle:Futura-Bold", textFace: "bundle:Futura-Medium",
        textScale: 0.97, repeatSize: 200, curves: 0.85, pace: 0.75,
        lifts: ["paint", "capture", "shop", "curate", "congregation", "composer"], hawkins: "Joy, 540", pop: 0.14,
        oklch: [[0.25, 0.045, 60], [0.32, 0.060, 65], [0.94, 0.035, 85], [0.76, 0.035, 85], [0.84, 0.140, 80]])
}

/// The grounds for the lower five answers, drawn in code in the palette's own colours.
struct RiseGround: View {
    let name: String, key: Color, accent: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [key.opacity(0.16), accent.opacity(0.1)], startPoint: .top, endPoint: .bottom)
            scene
        }
    }

    @ViewBuilder private var scene: some View {
        switch name {
        case "rise-lamp": glow(key.opacity(0.4), 0.5, 0.92, 420)
        case "rise-water": ZStack { glow(accent.opacity(0.22), 0.5, 0.45, 380); drawn { c, s in water(&c, s) } }
        case "rise-path": drawn { c, s in path(&c, s) }
        case "rise-table": drawn { c, s in table(&c, s) }
        default: ZStack { glow(accent.opacity(0.2), 0.85, 0.1, 380); drawn { c, s in window(&c, s) } }
        }
    }

    private func glow(_ c: Color, _ x: Double, _ y: Double, _ r: CGFloat) -> some View {
        RadialGradient(colors: [c, .clear], center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: r)
    }
    private func drawn(_ f: @escaping (inout GraphicsContext, CGSize) -> Void) -> some View {
        Canvas { c, s in f(&c, s) }.drawingGroup()
    }
    private func line(_ c: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// A wide horizon and a few still lines of water.
    private func water(_ c: inout GraphicsContext, _ s: CGSize) {
        let top = s.height * 0.52
        line(&c, CGPoint(x: 0, y: top), CGPoint(x: s.width, y: top), accent.opacity(0.45), 1.5)
        for i in 1...9 {
            let y = top + CGFloat(i * i) * s.height * 0.0055
            let inset = s.width * (0.05 + 0.04 * CGFloat((i * 5) % 7))
            line(&c, CGPoint(x: inset, y: y), CGPoint(x: s.width - inset * 0.6, y: y), accent.opacity(0.18), 2)
        }
    }

    /// A path leading forward, with trunks beside it.
    private func path(_ c: inout GraphicsContext, _ s: CGSize) {
        let far = CGPoint(x: s.width * 0.55, y: s.height * 0.42)
        line(&c, CGPoint(x: s.width * 0.08, y: s.height), far, key.opacity(0.4), 3)
        line(&c, CGPoint(x: s.width * 0.96, y: s.height), far, key.opacity(0.4), 3)
        let trunks: [(CGFloat, CGFloat)] = [(0.1, 0.34), (0.24, 0.22), (0.8, 0.25), (0.93, 0.38)]
        for (x, h) in trunks {
            let foot = s.height * (0.42 + h * 0.8)
            line(&c, CGPoint(x: s.width * x, y: foot), CGPoint(x: s.width * x, y: foot - s.height * h), accent.opacity(0.2), h * 22)
        }
    }

    /// A clean worktable with three sticks of chalk on it.
    private func table(_ c: inout GraphicsContext, _ s: CGSize) {
        let y = s.height * 0.72
        line(&c, CGPoint(x: 0, y: y), CGPoint(x: s.width, y: y), key.opacity(0.4), 3)
        let chalk: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 30, 0.2), (0.45, 52, 0.15), (0.64, 26, 0.18)]
        for (x, dy, len) in chalk {
            line(&c, CGPoint(x: s.width * x, y: y + dy), CGPoint(x: s.width * (x + len), y: y + dy - 8), accent.opacity(0.3), 11)
        }
    }

    /// Light through a window, falling across the screen.
    private func window(_ c: inout GraphicsContext, _ s: CGSize) {
        for i in 0..<3 {
            let x = s.width * (0.38 + 0.24 * CGFloat(i))
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + s.width * 0.15, y: 0))
            p.addLine(to: CGPoint(x: x - s.width * 0.45, y: s.height)); p.addLine(to: CGPoint(x: x - s.width * 0.66, y: s.height))
            p.closeSubpath()
            c.fill(p, with: .color(accent.opacity(0.08)))
        }
    }
}

/// The one thing to do for this answer, then the second options (his rulings 11-26 afternoon). Finishing one leaves a tick
/// (the research: control comes first) and records which move it was, so "what lifts you" can count it against the re-ask.
struct RisingAction: View {
    let band: Band
    @State private var rising = RisingScale.shared
    @State private var breathing = false
    @State private var box = false
    @State private var timerUntil: Date?
    @State private var timerName = ""
    @State private var writing = false
    @State private var open: String?
    @State private var value: String?
    @State private var kind = ""
    @State private var song = UserDefaults.standard.string(forKey: "pldev.rising.song") ?? ""
    @State private var songDraft = ""
    @State private var board = false
    @Environment(\.openURL) private var openURL

    init(band: Band) { self.band = band }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rising.current?.did == true {
                Label("Done. That counts.", systemImage: "checkmark.circle.fill").frame(minHeight: 44)
                // end on the best moment (peak-end, Duet job 71): the night's high point, never what was missed
                if let best = rising.bestTonight { Text("Tonight's best moment so far: " + best + ".").plFont(.footnote) }
                // calm is a full target at Heavy and Steady (job 71); elsewhere calm first, then one step up, never a jump
                if band == .heavy || band == .steady {
                    Text("Calm counts as a step up on its own.").plFont(.footnote).foregroundStyle(.secondary)
                } else if let up = Band(rawValue: band.rawValue + 1) {
                    Text("When it settles, aim one step up: " + RisingStep.of(up).title.lowercased() + ".").plFont(.footnote).foregroundStyle(.secondary)
                }
                // once cooled, decide now what to do about it later
                if band == .hot {
                    if writing { RisingPlan(fields: ["If it comes up again", "Then I will"]) { writing = false } }
                    else { button("Decide what you'll do about it later", "arrow.turn.down.right") { writing = true } }
                }
            } else {
                // the wake check-in starts with light
                if rising.firstOfShift { button("Light first: 2 minutes outside or at a bright window", "sun.max") { finish("Light first") } }
                offer
            }
        }
        .sensoryFeedback(.success, trigger: rising.current?.did ?? false)
    }

    @ViewBuilder private var offer: some View {
        switch band {
        case .heavy:
            if breathing { BreathRing(rounds: 3, done: { finish("Breathe with me") }, stop: { breathing = false }) } else {
                button("Breathe with me", "wind") { breathing = true }
                button("Water", "drop") { finish("Water") }
                practice("Listen", "ear", RisingAction.stayThenReplace, "Listened, then replaced")
                songButton
                button("Step into light", "sun.max") { finish("Step into light") }
            }
        case .hot:
            if breathing {
                BreathRing(rounds: box ? 4 : 12, box: box, inS: box ? 0 : 3, outS: box ? 0 : 7, done: { finish(box ? "Box breathing, 4 by 4" : "Cool down, 2 minutes") }, stop: { breathing = false })
            } else if timerUntil != nil {
                timer
            } else {
                button("Cool down, 2 minutes", "wind") { box = false; breathing = true }
                button("Box breathing, 4 by 4", "square") { box = true; breathing = true }
                button("Timeout, 10 minutes", "timer") { startTimer("Timeout, 10 minutes", "Come back when you're ready.") }
                button("Cold water on your hands", "drop") { finish("Cold water on your hands") }
                practice("Notice the thought", "text.bubble", RisingAction.defuse, "Noticed it")
                practice("Call it excitement", "bolt", RisingAction.excited, "Called it")
            }
        case .low:
            if breathing { BreathRing(rounds: 12, inS: 4, outS: 6, done: { finish("Breathe slow, 2 minutes") }, stop: { breathing = false }) }
            else if timerUntil != nil { timer } else {
                button("Breathe slow, 2 minutes", "wind") { breathing = true }
                button("Walk 10 minutes, past trees", "figure.walk") { startTimer("Walk 10 minutes, past trees", "Look again.") }
                practice("Listen", "ear", RisingAction.stayThenReplace, "Listened, then replaced")
                practice("Can I wonder", "sparkles", "Ask: can I wonder how it would feel if this went right? Wonder only. No need to believe it yet.", "Wondered")
                if let past = RisingAction.kindLines.last { Text("A line you wrote to yourself: " + past).plFont(.footnote).foregroundStyle(.secondary) }
                values
                practice("Talk to yourself as you", "person.wave.2", RisingAction.selfTalk, "Said it")
                practice("Call it excitement", "bolt", RisingAction.excited, "Called it")
            }
        case .stuck:
            if writing { RisingPlan(fields: ["The first step is"]) { finish("Do the first step") } } else {
                button("Do the first step", "arrow.right.circle") { writing = true }
                practice("Can I wonder", "sparkles", "Ask: can I wonder how it would feel if this went right? Wonder only. No need to believe it yet.", "Wondered")
                button("Make something with no goal", "scribble") { finish("Make something with no goal") }
                practice("Notice the thought", "text.bubble", RisingAction.defuse, "Noticed it")
                practice("Talk to yourself as you", "person.wave.2", RisingAction.selfTalk, "Said it")
            }
        case .steady:
            if writing { RisingPlan(fields: ["I want", "The best of it", "In the way", "If that happens, I will"]) { finish("Plan one move") } }
            else {
                button("Plan one move", "map") { writing = true }
                button("Brisk walk with music", "figure.walk") { finish("Brisk walk with music") }
                nightScene
                practice("Savour 20 seconds", "sparkles", RisingAction.savour, "Savoured")
                if rising.aweDue { practice("Awe minute", "sun.horizon", RisingAction.awe, "Saw it") }
            }
        case .rising:
            button("Made it and showed one person", "paintbrush") { finish("Made it and showed one person") }
            TextField("A note for your low self", text: $rising.note, axis: .vertical).textFieldStyle(.roundedBorder)
            nightScene
            practice("Savour 20 seconds", "sparkles", RisingAction.savour, "Savoured")
            if rising.aweDue { practice("Awe minute", "sun.horizon", RisingAction.awe, "Saw it") }
        case .lit:
            TextField("A note for a heavy night", text: $rising.note, axis: .vertical).textFieldStyle(.roundedBorder)
            button("Keep it", "bookmark") { finish("Keep it") }
            button("Vision board", "square.grid.2x2") { board = true }
                .sheet(isPresented: $board) { RisingVisionBoard { board = false; finish("Vision board") } }
            nightScene
            practice("Savour 20 seconds", "sparkles", RisingAction.savour, "Savoured")
        }
    }

    /// Stay with the feeling first, then replace it (his sources disagreed; his ruling 11-26: both, in that order).
    // Duet job 71, sections 3, 7 and 8: the quick methods that hold up, in our words.
    static let savour = "Name one good moment tonight. Replay it for 20 seconds: where you were, what you saw, what you felt. A small thing counts."
    static let awe = "Look up at the sky, or at something vast, old or intricate, for one minute. Find one thing you had not seen before."
    static let defuse = "Say the thought as: I'm having the thought that... Say it once more, slower. It is a thought, not an order."
    static let selfTalk = "Write one line to yourself as you, not I: You can handle this because..."
    static let excited = "Nerves before something big? Say it out loud: I feel excited. Not calm, excited. The energy is the same."
    static let stayThenReplace = "One minute. Where is it in your body? What is it trying to tell you? Only listen. Then breathe in one feeling you would rather have, and let it take the space."

    /// One of his notebook practices: the button opens a short instruction and its own "done".
    @ViewBuilder private func practice(_ title: String, _ symbol: String, _ text: String, _ done: String) -> some View {
        if open == title {
            Text(text).plFont(.callout)
            button(done, "checkmark") { finish(title) }
        } else {
            button(title, symbol) { open = title }
        }
    }

    /// Tonight's coin flip: a plain, ordinary night or a bright one, each with one obstacle and a move. The re-ask scores each.
    @ViewBuilder private var nightScene: some View {
        let calm = rising.nightCalm
        let name = calm ? "Night scene, ordinary" : "Night scene, bright"
        if open == name {
            Text((calm ? "Picture tonight going plain and fine: you at the table, the work getting done, nothing special."
                       : "Picture tonight at its best: the piece coming out right.")
                 + " Then feel it as if it already happened, in your chest. Hold the picture and the feeling together for three breaths.").plFont(.callout)
            RisingPlan(fields: ["One thing that could get in the way", "My move if it does"]) { finish(name) }
        } else {
            button("Night scene", "moon.stars") { open = name }
        }
    }

    /// What matters tonight, then one kind line to himself.
    @ViewBuilder private var values: some View {
        if open == "Values" {
            Text("What matters tonight?").plFont(.callout)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["Family", "The work", "Health", "Freedom", "People"], id: \.self) { v in
                        Button(v) { value = v }.buttonStyle(.bordered).tint(value == v ? PLTone.accent : .secondary).frame(minHeight: 44)
                    }
                }
            }
            if let value { Text("One small thing for " + value.lowercased() + " tonight.").plFont(.footnote) }
            TextField("One kind line to yourself, as to a friend", text: $kind, axis: .vertical).textFieldStyle(.roundedBorder)
            button("Said it", "heart") { RisingAction.keep(kind: kind, value: value); finish("Values and a kind line") }
        } else {
            button("Values and a kind line", "heart") { open = "Values" }
        }
    }

    /// His kind lines, kept on the phone with the value he picked, so a later Low tap can show him one.
    static var kindLines: [String] { UserDefaults.standard.stringArray(forKey: "pldev.rising.kindLines") ?? [] }
    static func keep(kind: String, value: String?) {
        let line = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        UserDefaults.standard.set(Array((kindLines + [(value.map { $0 + ": " } ?? "") + line]).suffix(30)), forKey: "pldev.rising.kindLines")
    }

    /// A song picked ahead, for a heavy night.
    @ViewBuilder private var songButton: some View {
        if song.isEmpty {
            TextField("A song for a heavy night (pick it ahead)", text: $songDraft).textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit {
                    song = songDraft.trimmingCharacters(in: .whitespaces)
                    UserDefaults.standard.set(song, forKey: "pldev.rising.song")
                }
        } else {
            button("Play your song: " + song, "music.note") {
                let term = song.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let web = URL(string: "https://music.apple.com/search?term=" + term)
                if let app = URL(string: "music://music.apple.com/search?term=" + term) {
                    openURL(app) { opened in if !opened, let web { openURL(web) } }
                } else if let web { openURL(web) }
                finish("Your song")
            }
            .contextMenu { Button("Change the song") { song = ""; songDraft = ""; UserDefaults.standard.removeObject(forKey: "pldev.rising.song") } }
        }
    }

    @ViewBuilder private var timer: some View {
        if let timerUntil {
            Text(timerInterval: Date()...max(timerUntil, Date()), countsDown: true).monospacedDigit().plFont(.callout, emphasized: true)
            button(timerName.hasPrefix("Timeout") ? "I'm back" : "I walked", "checkmark") { stopTimer(); finish(timerName) }
        }
    }

    /// The move that has lifted him most shows at once; the rest fade in. Nothing changes place.
    private func button(_ title: String, _ symbol: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
            .buttonStyle(.bordered)
            .modifier(RisingLate(late: rising.lifts.first.map { !$0.move.hasPrefix(title) } ?? false))
    }

    private func finish(_ move: String) { breathing = false; writing = false; timerUntil = nil; open = nil; rising.markDone(move) }

    private func startTimer(_ name: String, _ body: String) {
        timerName = name
        timerUntil = Date().addingTimeInterval(600)
        guard !rising.asleep(at: Date().addingTimeInterval(600)) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ten minutes."
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rising-walk", content: content,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
    }
    private func stopTimer() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rising-walk"]) }
}

/// The likely choice is there at once and the rest fade in over half a second (ephemeral adaptation: faster than a fixed menu
/// when the guess is right, and nothing moves when it is wrong).
struct RisingLate: ViewModifier {
    let late: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(late && !shown ? 0 : 1)
            .onAppear { if late { withAnimation(.easeIn(duration: 0.5)) { shown = true } } }
    }
}

/// A few short lines, then Done. Kept on the phone until the next one.
private struct RisingPlan: View {
    let fields: [String]
    let done: () -> Void
    @State private var text: [String: String] = UserDefaults.standard.dictionary(forKey: "pldev.rising.plan") as? [String: String] ?? [:]

    init(fields: [String], done: @escaping () -> Void) { self.fields = fields; self.done = done }

    var body: some View {
        ForEach(fields, id: \.self) { f in
            TextField(f, text: Binding(get: { text[f] ?? "" }, set: { text[f] = $0 }), axis: .vertical).textFieldStyle(.roundedBorder)
        }
        Button("Done") { UserDefaults.standard.set(text, forKey: "pldev.rising.plan"); done() }
            .buttonStyle(.borderedProminent).frame(minHeight: 44)
    }
}

/// Two breaths in, one long breath out (2 s, 1 s, 6 s), a box (4 s each side), or a slow pacer (inS in, outS out; about
/// 6 a minute with the longer breath out, Duet job 71), with a tap as each breath out starts. It grows 12% at most.
/// Lit's vision board (spec: "a vision board on Lit"): his chosen pieces from the Gate's count, full size, with the step under them.
private struct RisingVisionBoard: View {
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urls: [URL] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if urls.isEmpty {
                        Text("Pick pieces in the Gate's count and they show here.").plFont(.callout).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(urls, id: \.self) { u in
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                                .frame(height: 160).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .accessibilityLabel("Your chosen pieces")
                    Text("See it. Name the one thing in its way. Plan the step.").plFont(.callout)
                    RisingPlan(fields: ["The one thing in its way", "My step"]) { done() }
                }
                .padding(16)
            }
            .navigationTitle("Vision board").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            _ = GateStore.shared.load()
            urls = GateStore.shared.saved.count.compactMap { $0.isEmpty ? nil : URL(string: $0) }
        }
    }
}

private struct BreathRing: View {
    let rounds: Int
    let box: Bool   // 4 in, 4 hold, 4 out, 4 hold
    let inS: Double, outS: Double   // 0 = not the pacer
    let done: () -> Void, stop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var word = "In"
    @State private var size: CGFloat = 0.88
    @State private var out = 0

    init(rounds: Int, box: Bool = false, inS: Double = 0, outS: Double = 0, done: @escaping () -> Void, stop: @escaping () -> Void) {
        self.rounds = rounds; self.box = box; self.inS = inS; self.outS = outS; self.done = done; self.stop = stop
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(PLTone.accent, lineWidth: 3)
                    .scaleEffect(reduce ? 1 : size)
                    .opacity(reduce ? 0.75 + Double(size - 0.88) / 0.12 * 0.25 : 1)
                Text(word).plFont(.callout, emphasized: true)
            }
            .frame(width: 150, height: 150)
            Button("Stop", action: stop).frame(minWidth: 44, minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: out)
        .task {
            for _ in 0..<rounds {
                if box {
                    if !(await step("In", 1, 4)) { return }
                    if !(await step("Hold", 1, 4)) { return }
                    out += 1
                    if !(await step("Out", 0.88, 4)) { return }
                    if !(await step("Hold", 0.88, 4)) { return }
                } else if inS > 0 {
                    if !(await step("In", 1, inS)) { return }
                    out += 1
                    if !(await step("Out", 0.88, outS)) { return }
                } else {
                    if !(await step("In", 0.97, 2)) { return }
                    if !(await step("More", 1, 1)) { return }
                    out += 1
                    if !(await step("Out", 0.92, 6)) { return }
                }
            }
            done()
        }
    }

    /// False when the ring left the screen, so nothing is ticked for him.
    private func step(_ w: String, _ to: CGFloat, _ seconds: Double) async -> Bool {
        word = w
        AccessibilityNotification.Announcement(w).post()
        withAnimation(.easeInOut(duration: seconds)) { size = to }
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}
