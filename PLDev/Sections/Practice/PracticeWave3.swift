import SwiftUI

// Games, wave 3 (S348·9a3e, spec vault Plans/SPEC - GAMES, WAVE 3 (S348).md): Curve Field and Apostle Layer. His drill 11-15 dropped
// the Atlas, Sanctuary Preview, both Congregation games and Fifty Seeds.

// MARK: - Curve Field

struct CurveFieldGame: View {
    let seeds: [String]
    struct Hidden { let at: CGPoint; let text: String }
    @State private var rig = FieldRig()
    @State private var hidden: [Hidden] = []
    @State private var found: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text(found.count == 3 ? "All three found. Watch this." : "Move through his curves. Three of your seeds are hidden in the field.").candleHint()
            GeometryReader { geo in
                TimelineView(.animation(paused: reduceMotion)) { tl in
                    Canvas { ctx, size in
                        rig.reduce = reduceMotion
                        rig.setup(size)
                        rig.advance(tl.date)
                        for i in rig.ropes.indices {
                            ctx.stroke(rig.path(i), with: .color(i % 2 == 0 ? Candle.gold : Candle.goldHi.opacity(0.7)), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                        }
                        for k in found.sorted() where k < hidden.count {
                            ctx.draw(Text(hidden[k].text).font(.system(size: 14, design: .serif)).foregroundStyle(Candle.ink), at: hidden[k].at)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        rig.mx = v.location.x; rig.my = v.location.y
                        for (k, h) in hidden.enumerated() where !found.contains(k) && hypot(h.at.x - v.location.x, h.at.y - v.location.y) < 50 {
                            found.insert(k); PracticeSound.play(.right)
                            if found.count == 3 { ArcadeScores.offer(.field, ArcadeScores.best(.field) + 1) }
                        }
                    }
                    .onEnded { _ in rig.mx = -1e9; rig.my = -1e9 })
                .onAppear { hide(in: geo.size) }
            }
            .candleCard(padding: 0)
            if found.count == 3 { Button("Hide three more") { found = []; hide(in: nil) }.buttonStyle(CandleButton()) }
        }
        .padding(16)
    }

    @State private var area = CGSize(width: 340, height: 600)
    private func hide(in size: CGSize?) {
        if let size { area = size }
        let lines = seeds.filter { $0.split(separator: " ").count <= 6 }.shuffled()
        let pick = Array((lines.isEmpty ? GamesScreen.truths : lines).prefix(3))
        hidden = pick.map { Hidden(at: CGPoint(x: CGFloat.random(in: 0.2...0.8) * area.width, y: CGFloat.random(in: 0.15...0.85) * area.height), text: $0) }
    }
}

// MARK: - Apostle Layer

struct ApostleLayer: View {
    @State private var draft: String?
    @State private var working = false
    @State private var kept: [String] = UserDefaults.standard.stringArray(forKey: "apostle.kept") ?? []
    @State private var note: String?

    private var played: [ArcadeID] { ArcadeID.allCases.filter { $0 != .apostle && ArcadeScores.best($0) > 0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("A reflection on what you have played. Proposed on this iPhone, kept only if you accept it, and never part of the canon.").candleHint()
                if played.count < 3 {
                    Text("Opens after three different games have a score. \(played.count) so far.").candleH2()
                } else {
                    Text("Played: " + played.map(\.title).joined(separator: ", ")).candleHint()
                    if let draft {
                        Text(draft).font(.system(size: 19, design: .serif)).foregroundStyle(Candle.ink).candleCard()
                        HStack {
                            Button("Keep it") { kept.insert(draft, at: 0); UserDefaults.standard.set(kept, forKey: "apostle.kept"); self.draft = nil; ArcadeScores.offer(.apostle, kept.count) }.buttonStyle(CandleButton())
                            Button("Let it go") { self.draft = nil }.buttonStyle(CandleButton())
                        }
                    } else {
                        Button(working ? "Reading…" : "Propose a reflection") { Task { await propose() } }.buttonStyle(CandleButton()).disabled(working)
                    }
                    if let note { Text(note).candleHint() }
                }
                if !kept.isEmpty {
                    Text("Kept").candleH2().padding(.top, 8)
                    ForEach(kept, id: \.self) { Text($0).font(.system(size: 15, design: .serif)).foregroundStyle(Candle.ink.opacity(0.85)) }
                }
            }
            .padding(20)
        }
    }

    private func propose() async {
        working = true; defer { working = false }
        let facts = played.map { "\($0.title): best \(ArcadeScores.best($0)), \($0.line)" }
        if let s = await PLIntelligence.apostle(facts: facts) { draft = s; note = nil }
        else { note = PLIntelligence.isReady ? "No reflection came back. Try again." : PLIntelligence.statusLine }
    }
}
