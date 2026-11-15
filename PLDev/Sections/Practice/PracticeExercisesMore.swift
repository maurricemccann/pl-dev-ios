import SwiftUI

// One Teacher (S348·9a3e): the exercise kinds that were named in the course file but waited for their views ("complete the game,
// make sure nothing is missing", his ask 11-15). Each is a snippet of a drill or game, fed only from the course file.
// - rewrite: the Academy's Rewrite drill, graded by its examiner (pl-academy /api/drill/rewrite, crown or crucify).
// - say-it: speak the line; recognised on the phone (CaptureDictation, on-device when the phone supports it); nothing is recorded.
// - draw-it: trace one of his drawn glyphs over a faint guide; scored by how much of the mark the trace covers.

/// Words only, lower case, for comparing what was said with what is written.
private func words(_ s: String) -> [String] {
    s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}

// MARK: - rewrite

struct RewriteExercise: View {
    let original: String
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var critique: String?
    @State private var model: String?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original).font(.system(size: 17, design: .serif).italic()).foregroundStyle(Candle.ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            if !locked {
                PField(prompt: "Your rewrite. Declarative. Spare.", text: $text, lines: 4)
                Button(busy ? "The examiner is reading…" : "Face the examiner") { Task { await grade() } }
                    .buttonStyle(CandleButton()).disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let failure {
                    Text(failure).candleHint()
                    Button("Continue without a grade") { answer(true) }.buttonStyle(CandleGhost())
                }
            }
            if let critique { Text(critique).font(.system(size: 14, design: .serif).italic()).foregroundStyle(Candle.goldHi).fixedSize(horizontal: false, vertical: true) }
            if let model {
                Text("The examiner's rewrite").font(.system(size: 11)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                Text(model).font(.system(size: 15)).foregroundStyle(Candle.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func grade() async {
        busy = true; failure = nil; defer { busy = false }
        do {
            let j = try await Academy.post("api/drill/rewrite", ["original": original, "rewrite": text.trimmingCharacters(in: .whitespacesAndNewlines)])
            if let e = j["error"] as? String { failure = "The examiner could not be reached (\(e))."; return }
            critique = j["critique"] as? String
            model = j["model"] as? String
            answer((j["verdict"] as? String) == "crown")
        } catch {
            failure = "The examiner could not be reached. Check the connection, or continue without a grade."
        }
    }
}

// MARK: - say it

/// Holds what was heard; the dictation callbacks reach it weakly (the Jarvis screen's pattern), never the view.
@MainActor @Observable final class SayItModel {
    var heard = ""
    var listening = false
    var note: String?
    let dictation = CaptureDictation()

    func start() async {
        heard = ""; note = nil
        let problem = await dictation.start(onText: { [weak self] t in Task { @MainActor in self?.heard = t } },
                                            onEnd: { [weak self] in Task { @MainActor in self?.listening = false } })
        if let problem { note = problem } else { listening = true }
    }
    func stop() { dictation.stop(); listening = false }
}

struct SayItExercise: View {
    let target: String
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var say = SayItModel()
    private var heard: String { say.heard }
    private var listening: Bool { say.listening }
    private var note: String? { say.note }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target).font(.system(size: 20)).foregroundStyle(Candle.goldHi).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Text(heard.isEmpty ? (listening ? "Listening…" : "Tap the microphone and say it.") : heard)
                .font(.system(size: 15)).foregroundStyle(heard.isEmpty ? Candle.ink.opacity(0.5) : Candle.ink)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading).padding(12)
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
            if let note { Text(note).candleHint() }
            if !locked {
                HStack(spacing: 10) {
                    Button { Task { await toggle() } } label: {
                        Label(listening ? "Stop" : "Say it", systemImage: listening ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(CandleButton())
                    if !heard.isEmpty && !listening { Button("Check") { check() }.buttonStyle(CandleGhost()) }
                }
            }
        }
        .onDisappear { if listening { say.stop() } }
    }

    private func toggle() async {
        if listening { say.stop(); check(); return }
        await say.start()
    }

    /// Right when at least 85 % of the line's words were heard, in any order: speech recognition drops small words.
    private func check() {
        let want = words(target), got = Set(words(heard))
        guard !want.isEmpty, !heard.isEmpty else { return }
        let hit = want.filter { got.contains($0) }.count
        answer(Double(hit) / Double(want.count) >= 0.85)
    }
}

// MARK: - draw it

struct DrawItExercise: View {
    let glyphName: String
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var score: Double?

    static func art(_ name: String) -> (slug: String, name: String, aspect: CGFloat, outlines: [[CGPoint]])? {
        PracticeMapArt.glyphs.first { $0.name == name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(glyphName).candleH2()
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.8, c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    if let g = Self.art(glyphName) {
                        PracticeMapGeometry.glyph(g, side: side, centre: c).fill(Candle.ink.opacity(0.14), style: FillStyle(eoFill: true))
                    }
                    Canvas { ctx, _ in
                        for s in strokes + [current] where s.count > 1 {
                            var p = Path(); p.move(to: s[0]); for q in s.dropFirst() { p.addLine(to: q) }
                            ctx.stroke(p, with: .color(Candle.gold), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in if !locked { current.append(v.location) } }
                    .onEnded { _ in if !current.isEmpty { strokes.append(current); current = [] } })
                .onAppear { side_ = side; centre_ = c }
                .onChange(of: geo.size) { _, s in side_ = min(s.width, s.height) * 0.8; centre_ = CGPoint(x: s.width / 2, y: s.height / 2) }
            }
            .frame(height: 300)
            .background(Candle.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
            if let score { Text("You covered \(Int(score * 100)) % of the mark.").candleHint() }
            if !locked {
                HStack(spacing: 10) {
                    Button("Check") { check() }.buttonStyle(CandleButton()).disabled(strokes.isEmpty)
                    Button("Clear") { strokes = []; current = []; score = nil }.buttonStyle(CandleGhost())
                }
            }
        }
    }

    @State private var side_: CGFloat = 0
    @State private var centre_: CGPoint = .zero

    /// The share of the glyph's outline points that have a traced point within 16 pt. Right at 60 % or more.
    private func check() {
        guard let g = Self.art(glyphName), side_ > 0 else { return }
        let w = g.aspect >= 1 ? side_ : side_ * g.aspect, h = g.aspect >= 1 ? side_ / g.aspect : side_
        let targets = g.outlines.flatMap { $0 }.enumerated().filter { $0.offset % 3 == 0 }.map { e in
            CGPoint(x: centre_.x - w / 2 + e.element.x * w, y: centre_.y - h / 2 + e.element.y * h)
        }
        let drawn = strokes.flatMap { $0 }
        guard !targets.isEmpty, !drawn.isEmpty else { return }
        let covered = targets.filter { t in drawn.contains { hypot($0.x - t.x, $0.y - t.y) < 16 } }.count
        let s = Double(covered) / Double(targets.count)
        score = s
        answer(s >= 0.6)
    }
}
