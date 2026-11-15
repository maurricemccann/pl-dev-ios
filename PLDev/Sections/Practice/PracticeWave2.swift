import SwiftUI

// Games, wave 2 (S348·9a3e, spec vault Plans/SPEC - GAMES, WAVE 2 (S348).md): The Signal, Three Laws Room, Watch This Moment, rebuilt
// native from the beta. His drill 11-15: The Signal catches canon and lets noise pass (no lenses); Identity Install and The Void dropped;
// Archive Restoration folded into Restore the Archive; Origin Well held until the archive has real dates.

// MARK: - The Signal

struct SignalGame: View {
    let seeds: [String]
    struct Word: Identifiable { let id: Int; let text: String; let canon: Bool; let x: CGFloat; let born: Double }
    @State private var words: [Word] = []
    @State private var gone: Set<Int> = []
    @State private var score = 0
    @State private var caught = 0
    @State private var start = Date()
    @State private var done = false
    private let count = 30, gap = 1.4, fall = 6.0

    static let noise = ["excited", "honored", "blessed", "amazing", "unique", "limited", "exclusive", "maybe", "hopefully", "someday",
                        "eventually", "trying", "wish", "might", "could", "deal", "hurry", "viral", "hack", "guaranteed"]
    static let stop: Set<String> = ["about", "after", "again", "their", "there", "these", "those", "which", "while", "where", "other", "every", "being", "would", "should"]

    var body: some View {
        VStack(spacing: 12) {
            if done {
                Text("\(score)").font(.system(size: 44, weight: .semibold).monospacedDigit()).foregroundStyle(Candle.goldHi)
                Text("\(caught) of the house's words caught").candleHint()
                Button("Again") { begin() }.buttonStyle(CandleButton())
            } else {
                HStack { Text("Catch the house's words. Let the noise pass.").candleHint(); Spacer(); Text("\(score)").font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Candle.goldHi) }
                GeometryReader { geo in
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSince(start)
                        ZStack(alignment: .topLeading) {
                            ForEach(words.filter { !gone.contains($0.id) && t >= $0.born && t < $0.born + fall }) { w in
                                let y = CGFloat((t - w.born) / fall) * (geo.size.height + 40) - 20
                                Button { tap(w) } label: {
                                    Text(w.text).font(.system(size: 17, weight: .medium)).foregroundStyle(Candle.ink)
                                        .padding(.horizontal, 12).frame(minHeight: 44).background(Capsule().strokeBorder(Candle.hairline))
                                }
                                .buttonStyle(.plain)
                                .position(x: w.x * geo.size.width, y: y)
                            }
                        }
                        .onChange(of: Int(t)) { _, s in if Double(s) > Double(count) * gap + fall { finish() } }
                    }
                }
                .clipped()
            }
        }
        .padding(20)
        .onAppear { begin() }
    }

    private func begin() {
        let canon = Array(Set((seeds + GamesScreen.truths).flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }.map(String.init)
            .filter { $0.count >= 5 && !Self.stop.contains($0) })).shuffled()
        var pool: [(String, Bool)] = Array(canon.prefix(18)).map { ($0, true) } + Array(Self.noise.shuffled().prefix(count - min(18, canon.count))).map { ($0, false) }
        pool.shuffle()
        words = pool.enumerated().map { Word(id: $0.offset, text: $0.element.0, canon: $0.element.1, x: CGFloat.random(in: 0.18...0.82), born: Double($0.offset) * gap) }
        gone = []; score = 0; caught = 0; done = false; start = .now
    }

    private func tap(_ w: Word) {
        gone.insert(w.id)
        if w.canon { score += 10; caught += 1; PracticeSound.play(.right) } else { score -= 5; PracticeSound.play(.wrong) }
    }

    private func finish() {
        guard !done else { return }
        done = true; ArcadeScores.offer(.signal, max(0, score))
    }
}

// MARK: - Three Laws Room

struct ThreeLawsRoom: View {
    let units: [CourseUnit]
    @State private var room = 0
    @State private var shown = 0

    var body: some View {
        let truths = GamesScreen.truths
        let unit = units.first { $0.n == room + 1 }
        let lines = (unit?.items ?? []).map(\.text).filter { $0.split(separator: " ").count <= 30 }
        VStack(alignment: .leading, spacing: 16) {
            Text("Room \(room + 1) of 3").candleHint()
            Text(truths[room]).font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(Candle.goldHi)
            if let u = unit { Text(u.about).font(.system(size: 15)).foregroundStyle(Candle.ink.opacity(0.85)) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.prefix(shown).enumerated()), id: \.offset) { _, l in
                        Text(l).font(.system(size: 17, design: .serif)).foregroundStyle(Candle.ink).transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if shown < min(lines.count, 6) {
                Button("Walk on") { withAnimation(.easeOut(duration: 0.4)) { shown += 1 } }.buttonStyle(CandleButton())
            } else if room < 2 {
                Button("The next room") { withAnimation { room += 1; shown = 0 } }.buttonStyle(CandleButton())
            } else {
                Text("Watch this.").font(.system(size: 18, design: .serif).italic()).foregroundStyle(Candle.goldHi)
                Button("Walk through again") { withAnimation { room = 0; shown = 0 } }.buttonStyle(CandleButton())
                    .onAppear { ArcadeScores.offer(.room, 1) }
            }
        }
        .padding(20)
    }
}

// MARK: - Watch This Moment

struct WatchThisMoment: View {
    struct Piece: Decodable { let cr: String?; let title: String?; let thumb: String? }
    struct Manifest: Decodable { let pieces: [Piece] }
    struct Mark { var p: CGPoint; let t: Date }
    @State private var marks: [Mark] = []
    @State private var length: CGFloat = 0
    @State private var deck: [Piece] = []
    @State private var reveal: Piece?
    @State private var note: String?

    var body: some View {
        ZStack {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    if marks.isEmpty && reveal == nil {
                        ctx.draw(Text("Draw the Curve.").font(.system(size: 13)).foregroundStyle(Candle.ink.opacity(0.5)), at: CGPoint(x: size.width / 2, y: size.height / 2))
                    }
                    for k in marks.indices.dropFirst() {
                        let age = tl.date.timeIntervalSince(marks[k].t), a = max(0, 1 - age / 3)
                        guard a > 0 else { continue }
                        var p = Path(); p.move(to: marks[k - 1].p); p.addLine(to: marks[k].p)
                        ctx.stroke(p, with: .color(Candle.gold.opacity(a)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                if let l = marks.last { length += hypot(v.location.x - l.p.x, v.location.y - l.p.y) }
                marks.append(Mark(p: v.location, t: .now)); if marks.count > 600 { marks.removeFirst(100) }
            }.onEnded { _ in
                if length > 900 { Task { await show() } }
            })
            if let r = reveal {
                VStack(spacing: 12) {
                    Text("Watch this.").font(.system(size: 22, design: .serif).italic()).foregroundStyle(Candle.goldHi)
                    if let s = r.thumb, let u = URL(string: s) {
                        AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 320)
                    }
                    Text(r.title ?? "From the archive").candleH2()
                    if let cr = r.cr { Text(cr).candleHint() }
                    Button("Draw again") { reveal = nil; marks = []; length = 0 }.buttonStyle(CandleButton())
                }
                .padding(20).candleCard()
                .padding(20)
            }
            if let note { VStack { Spacer(); Text(note).candleHint().padding() } }
        }
    }

    private func show() async {
        length = 0
        if deck.isEmpty {
            guard let url = URL(string: "https://assets.psychedluxuries.com/manifest.json"),
                  let (d, _) = try? await URLSession.shared.data(from: url), let m = try? JSONDecoder().decode(Manifest.self, from: d) else {
                note = "Could not reach the archive, so no piece this time. Watch this."; return
            }
            deck = m.pieces.filter { $0.thumb != nil }.shuffled()
        }
        note = nil
        reveal = deck.popLast()
        ArcadeScores.offer(.moment, ArcadeScores.best(.moment) + 1)
    }
}
