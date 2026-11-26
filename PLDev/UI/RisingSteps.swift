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
    private static let heavy = RisingStep(hue: 65, chroma: 0.045, light: 0.23, turn: 12, radius: 1.5, space: 1.2, tile: "circle", calm: true,
        wall: "code|rise-lamp", title: "One small thing", face: "calm", side: 112,
        lines: ["Heavy is allowed. One small thing, then rest."])
    private static let hot = RisingStep(hue: 240, chroma: 0.03, light: 0.21, turn: -15, radius: 1.5, space: 1.2, tile: "circle", calm: true,
        wall: "code|rise-water", title: "Cool it first", face: "calm", side: 112,
        lines: ["Anger means something matters. Cool it first, then decide."])
    private static let low = RisingStep(hue: 220, chroma: 0.05, light: 0.21, turn: -25, radius: 1.5, space: 1.1, tile: "squircle", calm: true,
        wall: "code|rise-path", title: "Let it loosen", face: "calm", side: 144,
        lines: ["Worry is a forecast, not a fact. Walk ten minutes, then look again."])
    private static let stuck = RisingStep(hue: 170, chroma: 0.065, light: 0.20, turn: -25, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: "code|rise-table", title: "One step", face: "happy", side: 144,
        lines: ["Stuck asks for one small move. Pick the first step and stop there.",
                "Boredom is a quiet doorway. Picture one room of the life you want, down to the light."])
    private static let steady = RisingStep(hue: 140, chroma: 0.08, light: 0.22, turn: -55, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: "code|rise-window", title: "Add a little", face: "happy", side: 144,
        lines: ["Steady is a good base. Add one thing that moves the work forward.",
                "Hope is a real step up. Write one line about the version of you who has plenty."])
    private static let rising = RisingStep(hue: 80, chroma: 0.11, light: 0.22, turn: 12, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: "curves", title: "Make something", face: "excited", side: 144,
        lines: ["This is the practice working. Put it into one thing you make tonight.",
                "Luxury living is a way of standing in the world. You are standing in it now."])
    private static let lit = RisingStep(hue: nil, chroma: 0.13, light: 0.19, turn: 40, radius: 1, space: 1, tile: "squircle", calm: false,
        wall: nil, title: "Keep this", face: "excited", side: 144,
        lines: ["Remember this. Leave yourself a note for a harder night.",
                "Good nights add up. Keep this one as a marker for the next."])
}

/// The grounds for the lower five answers, drawn in code in the palette's own colours.
struct RiseGround: View {
    let name: String, key: Color, accent: Color

    var body: some View {
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

/// The one thing to do for this answer. Finishing it leaves a tick (the research: control comes first).
struct RisingAction: View {
    let band: Band
    @State private var rising = RisingScale.shared
    @State private var breathing = false
    @State private var walkUntil: Date?
    @State private var writing = false

    init(band: Band) { self.band = band }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rising.current?.did == true {
                Label("Done. That counts.", systemImage: "checkmark.circle.fill").frame(minHeight: 44)
            } else {
                offer
            }
        }
        .sensoryFeedback(.success, trigger: rising.current?.did ?? false)
    }

    @ViewBuilder private var offer: some View {
        switch band {
        case .heavy:
            if breathing { BreathRing(rounds: 3, done: finish, stop: { breathing = false }) } else {
                button("Breathe with me", "wind") { breathing = true }
                button("Water", "drop") { finish() }
            }
        case .hot:
            if breathing { BreathRing(rounds: 13, done: finish, stop: { breathing = false }) } else { button("Cool down, 2 minutes", "wind") { breathing = true } }
        case .low: walk
        case .stuck:
            if writing { RisingPlan(fields: ["The first step is"]) { finish() } } else { button("Do the first step", "arrow.right.circle") { writing = true } }
        case .steady:
            if writing { RisingPlan(fields: ["I want", "The best of it", "In the way", "If that happens, I will"]) { finish() } }
            else { button("Plan one move", "map") { writing = true } }
        case .rising:
            button("Made it and showed one person", "paintbrush") { finish() }
            TextField("A note for your low self", text: $rising.note, axis: .vertical).textFieldStyle(.roundedBorder)
        case .lit:
            TextField("A note for a heavy night", text: $rising.note, axis: .vertical).textFieldStyle(.roundedBorder)
            button("Keep it", "bookmark") { finish() }
        }
    }

    @ViewBuilder private var walk: some View {
        if let walkUntil {
            Text(timerInterval: Date()...max(walkUntil, Date()), countsDown: true).monospacedDigit().plFont(.callout, emphasized: true)
            button("I walked", "checkmark") { stopWalk(); finish() }
        } else {
            button("Walk 10 minutes", "figure.walk") { startWalk() }
        }
    }

    private func button(_ title: String, _ symbol: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
            .buttonStyle(.bordered)
    }

    private func finish() { breathing = false; writing = false; walkUntil = nil; rising.markDone() }

    private func startWalk() {
        walkUntil = Date().addingTimeInterval(600)
        let content = UNMutableNotificationContent()
        content.title = "Ten minutes."
        content.body = "Look again."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rising-walk", content: content,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
    }
    private func stopWalk() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rising-walk"]) }
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

/// Two breaths in, one long breath out (2 s, 1 s, 6 s), with a tap as each breath out starts.
private struct BreathRing: View {
    let rounds: Int
    let done: () -> Void, stop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var word = "In"
    @State private var size: CGFloat = 0.5
    @State private var out = 0

    init(rounds: Int, done: @escaping () -> Void, stop: @escaping () -> Void) { self.rounds = rounds; self.done = done; self.stop = stop }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(PLTone.accent, lineWidth: 3)
                    .scaleEffect(reduce ? 1 : size)
                    .opacity(reduce ? Double(size) : 1)
                Text(word).plFont(.callout, emphasized: true)
            }
            .frame(width: 150, height: 150)
            Button("Stop", action: stop).frame(minWidth: 44, minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: out)
        .task {
            for _ in 0..<rounds {
                if !(await step("In", 0.85, 2)) { return }
                if !(await step("More", 1, 1)) { return }
                out += 1
                if !(await step("Out", 0.45, 6)) { return }
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
