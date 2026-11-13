import SwiftUI

// The Meditation card: the Coherence Bloom and the Prism on one eleven-second breath, and the two-minute rehearsal under them.
// Port of `public/app.js` (drawCoherenceBloom, the prism fragment shader, the rehearsal stages), clock for clock.

/// 5.5 s in and 5.5 s out: one cosine, so the turn is still, like a real breath. One clock drives the picture and the words.
enum Breath {
    static let ms = 11000.0
    static func phase(_ tMs: Double) -> (u: Double, envelope: Double) {
        let u = tMs.truncatingRemainder(dividingBy: ms) / ms
        return (u, 0.5 - 0.5 * cos(u * 2 * .pi))
    }
}

/// `drawCoherenceBloom`: eight teardrop petals at the golden angle, swelling on the inhale. Drawn in the web's 600 by 400 world.
struct CoherenceBloom: View {
    let tMs: Double
    private static let ink = Color(hex: 0xefe7d2), body = Color(hex: 0xc9a84c), hi = Color(hex: 0xf3e6b0)

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 600
            var c = ctx
            c.scaleBy(x: s, y: s)
            let w = 600.0, h = 400.0, cx = w / 2, cy = h / 2
            let env = Breath.phase(tMs).envelope
            let R = min(w, h) * (0.16 + 0.22 * env)
            let rot = tMs * 0.00007
            let golden = Double.pi * (3 - 5.0.squareRoot())
            for p in 0..<8 {
                let a0 = Double(p) * golden + rot
                let petalR = R * (0.75 + 0.25 * sin(Double(p) * 1.7))
                var path = Path()
                for i in 0...80 {
                    let u = Double(i) / 80
                    let ang = a0 + sin(u * .pi) * 0.55
                    let rr = petalR * sin(u * .pi)
                    let pt = CGPoint(x: cx + cos(ang) * rr, y: cy + sin(ang) * rr)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                let round = StrokeStyle(lineWidth: 5.8, lineCap: .round, lineJoin: .round)
                c.drawLayer { l in
                    l.addFilter(.shadow(color: Color(red: 20 / 255, green: 16 / 255, blue: 12 / 255).opacity(0.18), radius: 2.5, x: 1.5, y: 3))
                    l.stroke(path, with: .color(Self.ink), style: round)
                }
                c.stroke(path, with: .color(Self.body), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                c.stroke(path, with: .color(Self.hi), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            }
            let r = 3 + env * 2
            c.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(Self.hi))
        }
        .background(Candle.bg)
        .accessibilityElement().accessibilityLabel("Visual breathing guide: a golden bloom that swells on the inhale and settles on the exhale, one breath every eleven seconds")
    }
}

/// The Prism as the second visual: the gallery's liquid-glass fragment shader (`PracticePrism.metal`), slowed to breath tempo.
struct PrismView: View {
    let tMs: Double
    var body: some View {
        GeometryReader { g in
            Rectangle().fill(Candle.bg)
                .colorEffect(ShaderLibrary.practicePrism(.float2(g.size.width, g.size.height), .float(tMs / 6000), .float(Breath.phase(tMs).envelope)))
        }
        .accessibilityElement().accessibilityLabel("Visual breathing guide: a slow liquid glass that swells with the breath")
    }
}

struct MeditationCard: View {
    let model: AppModel
    let state: PracticeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = "bloom"
    @State private var start = Date()
    @State private var rehearsal = RehearsalFlow()

    var body: some View {
        PCard(title: "Meditation", id: "meditation") {
            HStack(spacing: 6) {
                CandleChip(title: "the coherence bloom", on: mode == "bloom") { mode = "bloom" }
                CandleChip(title: "the prism", on: mode == "prism") { mode = "prism" }
                Spacer(minLength: 0)
            }
            TimelineView(.animation(paused: reduceMotion)) { tl in
                let t = reduceMotion ? 2750 : tl.date.timeIntervalSince(start) * 1000
                VStack(spacing: 8) {
                    Group { if mode == "bloom" { CoherenceBloom(tMs: t) } else { PrismView(tMs: t) } }
                        .aspectRatio(3 / 2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(Breath.phase(t).u < 0.5 ? "breathe in..." : "breathe out...").font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.7))
                }
            }
            RehearsalSection(model: model, state: state, flow: $rehearsal)
        }
    }
}

// MARK: - The rehearsal: five senses over the breath, then how strongly it landed

struct RehearsalFlow {
    enum Phase { case setup, live, rate, done }
    var phase: Phase = .setup
    var started = Date()
    var elapsed = 0
    var chosen = ""
}

struct RehearsalSection: View {
    let model: AppModel
    let state: PracticeModel
    @Binding var flow: RehearsalFlow
    private static let stages = [
        "See it \u{2014} the room, the light, where you are when it\u{2019}s true.",
        "Hear it \u{2014} what\u{2019}s said around you, the sound of that day.",
        "Feel it \u{2014} the fabric, the weight, the temperature of it.",
        "The emotion of it done \u{2014} let it land in the chest.",
        "Hold the whole scene \u{2014} you inside it, present tense.",
    ]
    private static let stageSeconds = 24
    @State private var desires: [PracticeDesire] = []
    @State private var result: String?
    @State private var stageBeat = 0

    private var stage: Int { min(flow.elapsed / Self.stageSeconds, Self.stages.count - 1) }

    var body: some View {
        VStack(spacing: 8) {
            switch flow.phase {
            case .setup:
                HStack(spacing: 6) {
                    PSelect(options: desires.isEmpty ? [("", "write a desire first")] : desires.map { ($0.id, String($0.text.prefix(70))) }, value: $flow.chosen)
                    Button("Rehearse it \u{2014} 2 minutes") { begin() }.buttonStyle(CandleGhost()).fixedSize().disabled(flow.chosen.isEmpty)
                }
            case .live:
                Text(Self.stages[stage]).font(.system(size: 16, design: .serif).italic()).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
                    .lineSpacing(4).frame(maxWidth: .infinity, minHeight: 56).id(stage).transition(.opacity)
                Button("end early") { end() }.buttonStyle(CandleGhost())
            case .rate:
                Text("How vivid did it get \u{2014} how much did it land?").font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { n in Button("\(n)") { Task { await save(n) } }.buttonStyle(CandleButton()).frame(minWidth: 44) }
                }
            case .done:
                Text("Logged. The scene compounds.").font(.system(size: 15, design: .serif).italic()).foregroundStyle(Candle.goldHi).padding(.vertical, 10)
            }
            CandleResult(text: result)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: flow.phase == .live ? stage : -1)
        .sensoryFeedback(PLHaptic.open, trigger: stageBeat)
        .sensoryFeedback(PLHaptic.success, trigger: flow.phase == .done)
        .task(id: state.desiresRev) { await loadDesires() }
        .task(id: flow.phase == .live) {
            while flow.phase == .live, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard flow.phase == .live else { break }
                flow.elapsed = Int(Date().timeIntervalSince(flow.started))
                if stage != stageBeat { stageBeat = stage }
                await RehearsalLive.update(stage: stage, titles: Self.stages)
                if flow.elapsed >= Self.stageSeconds * Self.stages.count { end() }
            }
        }
        .onDisappear { if flow.phase == .live { end() } }
    }

    private func loadDesires() async {
        if let l = try? await Practice.get("scripts", [PracticeDesire].self, model: model) {
            desires = l.filter { $0.completed_at == nil }
            if !desires.contains(where: { $0.id == flow.chosen }) { flow.chosen = desires.first?.id ?? "" }
        }
    }

    private func begin() {
        flow.started = Date(); flow.elapsed = 0; stageBeat = 0; result = nil; flow.phase = .live
        RehearsalLive.start(desire: desires.first { $0.id == flow.chosen }?.text ?? "A rehearsal", started: flow.started, titles: Self.stages)
    }

    private func end() {
        Task { await RehearsalLive.stop() }
        flow.phase = .rate
    }

    private func save(_ n: Int) async {
        do {
            try await Practice.post("sessions", ["script_id": flow.chosen, "duration_s": max(Int(Date().timeIntervalSince(flow.started)), 1), "intensity": n], model: model)
            flow.phase = .done; state.tick += 1; state.reload += 1
            try? await Task.sleep(for: .seconds(4)); flow.phase = .setup
        } catch { result = error.localizedDescription }
    }
}
