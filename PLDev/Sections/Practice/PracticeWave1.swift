import SwiftUI

// Games, wave 1 (S348·9a3e, spec vault Plans/SPEC - GAMES, WAVE 1 (S348).md): The Seeds (with The Signal Descrambled as its second
// mode), The Curve, Reality Architect and Oracle Paths, rebuilt native from the beta (C:\dev\PL Beta Games) with its bugs fixed. His
// drill 11-15: a gentle clock for The Seeds (bonus only), Reality Architect on visible on-device rules, the Lexicon and Tarot dropped.

// MARK: - The Seeds (+ Descrambled)

struct SeedsGame: View {
    let seeds: [String]
    enum Mode { case memory, cold }
    @State private var mode: Mode?
    @State private var deck: [String] = []
    @State private var round = 0
    @State private var words: [String] = []
    @State private var chips: [SeedChip] = []
    @State private var placed = 0
    @State private var misses = 0
    @State private var shown = false
    @State private var started = Date()
    @State private var total = 0
    @State private var flash: Int?
    @State private var lastRound: Int?
    private let rounds = 5, clock = 45.0

    var body: some View {
        VStack(spacing: 18) {
            if seeds.count < 2 { Text("Your seeds are still loading. Open the Path once, then come back.").candleHint() }
            else if mode == nil { pick }
            else if round >= min(rounds, deck.count) { end }
            else { play }
        }
        .padding(20)
    }

    private var pick: some View {
        VStack(spacing: 14) {
            Text("Rebuild your seed phrases word by word. A clock adds points for speed; running out never fails a round.").candleHint().multilineTextAlignment(.center)
            Button("From memory: see it, then rebuild") { begin(.memory) }.buttonStyle(CandleButton())
            Button("Descrambled: rebuild it cold") { begin(.cold) }.buttonStyle(CandleButton())
            if ArcadeScores.best(.seeds) > 0 { Text("Best \(ArcadeScores.best(.seeds))").candleHint() }
        }
    }

    private var play: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let left = max(0, Int(clock - tl.date.timeIntervalSince(started)))
            VStack(spacing: 16) {
                HStack {
                    Text("Phrase \(round + 1) of \(min(rounds, deck.count))").candleHint()
                    Spacer()
                    Text(left > 0 ? "+\(left * 2)" : "no bonus").font(Font.pl(size: 13).monospacedDigit()).foregroundStyle(Candle.goldHi)
                }
                if shown {
                    Text(words.joined(separator: " ")).candleH2().multilineTextAlignment(.center)
                    Button("I have it") { withAnimation { shown = false }; started = .now }.buttonStyle(CandleButton())
                } else {
                    Text(words.prefix(placed).joined(separator: " ") + (placed < words.count ? " …" : ""))
                        .font(Font.pl(size: 20, weight: .medium)).foregroundStyle(Candle.ink).multilineTextAlignment(.center).frame(minHeight: 60)
                    SeedChips(chips: chips, flash: flash) { tap($0, left: left) }
                    if let lastRound { Text("Last phrase: \(lastRound)").candleHint() }
                }
            }
        }
    }

    private var end: some View {
        VStack(spacing: 14) {
            Text("\(total)").font(Font.pl(size: 44, weight: .semibold).monospacedDigit()).foregroundStyle(Candle.goldHi)
            Text("points from five phrases").candleHint()
            Button("Again") { mode = nil }.buttonStyle(CandleButton())
        }
        .onAppear { ArcadeScores.offer(.seeds, total) }
    }

    private func begin(_ m: Mode) {
        mode = m; deck = seeds.shuffled(); round = 0; total = 0; lastRound = nil; load()
    }

    private func load() {
        guard round < deck.count else { return }
        words = deck[round].split(separator: " ").map(String.init)
        chips = words.enumerated().map { SeedChip(id: $0.offset, word: $0.element) }.shuffled()
        placed = 0; misses = 0; shown = mode == .memory; started = .now
    }

    private func tap(_ id: Int, left: Int) {
        guard let c = chips.first(where: { $0.id == id }) else { return }
        // a chip is right when its word is the next word (repeated words are interchangeable)
        if c.word == words[placed] {
            chips.removeAll { $0.id == id }; placed += 1
            if placed == words.count {
                let s = max(0, 100 - 15 * misses) + left * 2
                total += s; lastRound = s; round += 1; load()
            }
        } else {
            misses += 1; flash = id
            Task { try? await Task.sleep(for: .milliseconds(350)); if flash == id { flash = nil } }
        }
    }
}

struct SeedChip: Identifiable { let id: Int; let word: String }

/// Word chips that wrap across lines; a wrong tap flashes and does not take.
struct SeedChips: View {
    let chips: [SeedChip]
    let flash: Int?
    let tap: (Int) -> Void
    var body: some View {
        SeedWrap(spacing: 8) {
                ForEach(chips) { c in
                    Button { tap(c.id) } label: {
                        Text(c.word).font(Font.pl(size: 16)).foregroundStyle(flash == c.id ? Color.red.opacity(0.9) : Candle.ink)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().strokeBorder(flash == c.id ? Color.red.opacity(0.7) : Candle.gold.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
        }
    }
}

/// Lays children left to right, wrapping to a new line when the row is full.
struct SeedWrap: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + z.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

// MARK: - The Curve

struct CurveGame: View {
    enum Phase { case watch, draw, scored, done }
    @State private var phase = Phase.watch
    @State private var deck: [Int] = Array(PracticeMapArt.strokes.indices).shuffled()
    @State private var round = 0
    @State private var drawn: [CGPoint] = []
    @State private var drawStart = Date()
    @State private var scores: [Int] = []
    private let rounds = 5

    var body: some View {
        VStack(spacing: 14) {
            Text(phase == .done ? "Alignment, five strokes" : "Stroke \(round + 1) of \(rounds)").candleHint()
            if phase == .done {
                Text("\(scores.reduce(0, +) / max(1, scores.count))").font(Font.pl(size: 44, weight: .semibold).monospacedDigit()).foregroundStyle(Candle.goldHi)
                Button("Again") { deck = Array(PracticeMapArt.strokes.indices).shuffled(); round = 0; scores = []; phase = .watch; drawStart = .now }.buttonStyle(CandleButton())
            } else {
                GeometryReader { geo in
                    let target = PracticeMapGeometry.stroke(PracticeMapArt.strokes[deck[round % deck.count]], in: geo.size)
                    TimelineView(.animation) { tl in
                        Canvas { ctx, _ in
                            if phase == .watch {
                                let f = min(1, tl.date.timeIntervalSince(drawStart) / 2.2)
                                ctx.stroke(target.trimmedPath(from: 0, to: f), with: .color(Candle.gold), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            }
                            if phase == .scored { ctx.stroke(target, with: .color(Candle.gold.opacity(0.5)), style: StrokeStyle(lineWidth: 14, lineCap: .round)) }
                            var p = Path(); if let f = drawn.first { p.move(to: f); drawn.dropFirst().forEach { p.addLine(to: $0) } }
                            ctx.stroke(p, with: .color(Candle.ink), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        guard phase == .draw else { return }
                        drawn.append(v.location)
                    }.onEnded { _ in
                        guard phase == .draw, drawn.count > 4 else { return }
                        scores.append(Self.align(target, drawn, size: geo.size)); phase = .scored
                    })
                }
                .frame(height: 380)
                .candleCard(padding: 0)
                switch phase {
                case .watch: Button("Hide it, I'll draw it") { drawn = []; phase = .draw }.buttonStyle(CandleButton())
                case .draw: Text("Redraw his stroke from memory, one line.").candleHint()
                case .scored:
                    Text("\(scores.last ?? 0)").font(Font.pl(size: 28, weight: .semibold).monospacedDigit()).foregroundStyle(Candle.goldHi)
                    Button(round + 1 < rounds ? "Next stroke" : "Finish") {
                        round += 1; drawn = []
                        if round >= rounds { phase = .done; ArcadeScores.offer(.curve, scores.reduce(0, +) / max(1, scores.count)) } else { phase = .watch; drawStart = .now }
                    }.buttonStyle(CandleButton())
                case .done: EmptyView()
                }
            }
        }
        .padding(20)
        .onAppear { drawStart = .now }
    }

    /// 100 when the drawn line lies on his stroke: both sampled at 48 points along their length, the mean of each drawn point's
    /// distance to his stroke and each of his points' distance to the drawing (so half a stroke does not score full), against 1/8 of the box.
    static func align(_ target: Path, _ drawn: [CGPoint], size: CGSize) -> Int {
        let ts = (0..<48).map { PracticeMapGeometry.point(on: target, at: CGFloat($0) / 47) }
        let ds = drawn
        func near(_ p: CGPoint, _ set: [CGPoint]) -> CGFloat { set.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? 999 }
        let a = ds.map { near($0, ts) }.reduce(0, +) / CGFloat(max(1, ds.count))
        let b = ts.map { near($0, ds) }.reduce(0, +) / CGFloat(ts.count)
        let tol = max(size.width, size.height) / 8
        return max(0, min(100, Int((1 - (a + b) / 2 / tol) * 100)))
    }
}

// MARK: - Reality Architect

struct ArchitectGame: View {
    static let pillars: [(name: String, line: String, hint: String)] = [
        ("Self", "Who you are becoming. Your identity, your practice, your state of being.", "I am becoming..."),
        ("Wealth", "What you are drawing toward you. Resources, abundance, material reality.", "Money flows to me because..."),
        ("World", "What you are contributing. Your reach, your impact, how your reality serves others.", "My presence changes...")]
    @State private var text = ["", "", ""]
    @State private var sealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("State what you are building. Precise, present tense commands score; hedges cost. Every rule is shown.").candleHint()
                ForEach(0..<3, id: \.self) { i in
                    let r = Self.score(text[i])
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.pillars[i].name).candleH2()
                        Text(Self.pillars[i].line).candleHint()
                        TextField(Self.pillars[i].hint, text: $text[i], axis: .vertical).lineLimit(2...5).disabled(sealed)
                            .padding(12).background(RoundedRectangle(cornerRadius: 12 * PLStyle.radius).strokeBorder(Candle.hairline))
                        ProgressView(value: Double(r.score), total: 100).tint(r.score >= 80 ? Candle.goldHi : Candle.gold)
                        Text("Clarity \(r.score)").font(Font.pl(size: 12).monospacedDigit()).foregroundStyle(Candle.goldHi)
                        ForEach(r.notes, id: \.self) { Text($0).font(Font.pl(size: 13)).foregroundStyle(Candle.ink.opacity(0.8)) }
                    }
                    .candleCard()
                }
                let all = text.map { Self.score($0).score }
                if sealed {
                    Text("Sealed. Clarity \(all.reduce(0, +) / 3).").candleH2()
                    Button("Start a new blueprint") { text = ["", "", ""]; sealed = false }.buttonStyle(CandleButton())
                } else {
                    Button("Seal the blueprint") { sealed = true; ArcadeScores.offer(.architect, all.reduce(0, +) / 3) }
                        .buttonStyle(CandleButton()).disabled(all.contains { $0 < 55 })
                    if all.contains(where: { $0 < 55 }) { Text("Each pillar seals at clarity 55.").candleHint() }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    static let hedges = ["maybe", "try", "hope", "want", "wish", "might", "could", "would like", "someday", "eventually"]
    static let strong = ["am", "is", "are", "have", "create", "build", "attract", "generate", "lead", "command", "hold", "own", "shape", "become", "draw", "move", "know", "see", "stand", "walk"]
    static let banned = ["excited", "honored", "blessed", "check out", "amazing", "unique", "limited", "exclusive", "manifest"]

    /// The beta's clarity rules, on whole words (the beta matched "try" inside "country"). Returns the score and a line per rule hit.
    static func score(_ raw: String) -> (score: Int, notes: [String]) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 5 { return (0, ["Begin stating your intention."]) }
        let lower = t.lowercased()
        let words = lower.components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted).filter { !$0.isEmpty }
        if words.count < 4 { return (15, ["Too brief. Go deeper."]) }
        let joined = " " + words.joined(separator: " ") + " "
        func has(_ w: String) -> Bool { joined.contains(" " + w + " ") }
        var s = 30, notes: [String] = []
        for h in hedges where has(h) { s -= 12; notes.append("\"\(h)\" hedges the command. Remove it.") }
        for b in banned where has(b) || (b == "manifest" && words.contains { $0.hasPrefix("manifest") }) { s -= 12; notes.append("\"\(b)\" is not the house's language.") }
        if words.contains(where: { $0.hasSuffix("'m") }) || has("am") || has("is") || has("are") || has("have") || has("do") || has("does") { s += 20; notes.append("Present tense. Good.") }
        else { notes.append("Say it in the present tense.") }
        let verbs = strong.filter { has($0) }.count
        s += min(verbs * 8, 20); if verbs > 0 { notes.append("\(verbs) strong \(verbs == 1 ? "verb" : "verbs").") }
        if words.count >= 8 { s += 10 }
        if words.count >= 14 { s += 5 }
        if t.contains("?") { s -= 20; notes.append("Remove the question. State the command.") }
        return (max(5, min(100, s)), notes)
    }
}

// MARK: - Oracle Paths

struct OraclePathsGame: View {
    // the beta's five-deep story, carried over word for word (his founder history); one fix: the stale piece count reads "The archive"
    static let paths: [String: (text: String, choices: [(String, String)])] = [
        "root": ("The practice began on April 29th, 2019. A piece of chalk. A curve remembered from childhood. What called you here?", [("I came to understand the practice.", "practice"), ("I came to understand the archive.", "archive"), ("I came to understand the self.", "self")]),
        "practice": ("Seven years. No days off. The practice is not a habit — it is the structure of the self. What do you carry when you practice?", [("Intention — I know what I am building.", "practice_intention"), ("Doubt — I practice despite it.", "practice_doubt"), ("Rhythm — The body knows the way.", "practice_rhythm")]),
        "archive": ("The archive, catalogued. 90% governed by the Curve. The archive is not a record — it is a proof. What does a seven-year proof mean?", [("It means the practice is real.", "archive_real"), ("It means the self persists.", "archive_persist"), ("It means the world will remember.", "archive_world")]),
        "self": ("Before the practice: living day to day, no direction, no sense of what came next. After: a catalog, a brand, a philosophy. What changed?", [("The decision to produce regardless.", "self_produce"), ("The belief that the curve matters.", "self_curve"), ("The refusal to let reality be set by others.", "self_refuse")]),
        "practice_intention": ("Intention is a coordinate. Precision creates miracles. The Oracle reads: you build with clarity. What will you build?", [("A world that answers my frequency.", "terminus_law2"), ("A body of work that outlasts me.", "terminus_archive")]),
        "practice_doubt": ("Despite the conditions. The curve was drawn in spite. The Oracle reads: you know the practice is the answer to doubt, not its opposite.", [("The practice is how I persist.", "terminus_law3"), ("Doubt is just interference.", "terminus_practice")]),
        "practice_rhythm": ("The body holds the pattern when the mind forgets. The lineage — chalk, ink, marker, paint — each a rhythm returned to.", [("The hand knows what the mind denies.", "terminus_curve"), ("I will return to the practice today.", "terminus_return")]),
        "archive_real": ("Proof that this exists. That was the mission from the beginning. The Oracle has read the archive. It confirms: this is real.", [("Then I prepare for what comes next.", "terminus_law1"), ("Then I tell everyone.", "terminus_signal")]),
        "archive_persist": ("What persists in the mind becomes reality. The archive persists. He persists. The curve persists. What do you persist with?", [("The belief that my work matters.", "terminus_law3"), ("The practice, one more day.", "terminus_practice")]),
        "archive_world": ("The minute I picked up that chalk I knew my curves would cover the world. The Oracle confirms: the archive is moving.", [("Prepared for luxury.", "terminus_law1"), ("In control of this reality.", "terminus_law2")]),
        "self_produce": ("Produce uncontrollably. Expand in spite. The Oracle recognizes this pattern — it is the engine of the entire catalog.", [("I will produce again today.", "terminus_practice"), ("The production IS the philosophy.", "terminus_curve")]),
        "self_curve": ("Three curves that look like a rose. The first tag. Still true today. The Oracle says: the curve was the signal from the beginning.", [("Follow the signal.", "terminus_signal"), ("The curve will cover everything.", "terminus_curve")]),
        "self_refuse": ("You are in control of your reality. Not the conditions. Not the doubters. Not the default settings. The Oracle agrees.", [("Replace the default settings.", "terminus_law2"), ("What persists in my mind is mine.", "terminus_law3")]),
        "terminus_law1": ("Prepared for luxury. The Oracle closes. The first truth is yours.", []),
        "terminus_law2": ("You are in control of your reality. The Oracle closes. The second truth is yours.", []),
        "terminus_law3": ("What persists in the mind becomes your reality. The Oracle closes. The third truth is yours.", []),
        "terminus_archive": ("The archive will outlast the conditions. The practice guarantees it. The Oracle has read the signal.", []),
        "terminus_curve": ("The Curve is the governing law. Not preference — law. The Oracle confirms what the hand already knew.", []),
        "terminus_practice": ("Return to the practice. That is the answer the Oracle always gives. Go make something.", []),
        "terminus_signal": ("The signal is broadcasting. The Oracle closes. Your frequency is the transmission. Watch this.", []),
        "terminus_return": ("Begin again. That is all the Oracle knows. The practice is the return. The return is the practice.", []),
    ]
    @State private var at = "root"
    @State private var trail: [String] = []

    var body: some View {
        let node = Self.paths[at] ?? Self.paths["root"]!
        VStack(alignment: .leading, spacing: 18) {
            Text("Step \(min(trail.count + 1, 5))").candleHint()
            Text(node.text).font(Font.pl(size: 20, design: .serif)).foregroundStyle(Candle.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if node.choices.isEmpty {
                Text("Watch this.").font(Font.pl(size: 16, design: .serif).italic()).foregroundStyle(Candle.goldHi)
                if !trail.isEmpty { Text("Your path: " + trail.joined(separator: " · ")).candleHint() }
                Button("Ask again") { at = "root"; trail = [] }.buttonStyle(CandleButton())
            } else {
                ForEach(node.choices.indices, id: \.self) { k in
                    let c = node.choices[k]
                    Button { trail.append(c.0); at = c.1; if Self.paths[c.1]?.choices.isEmpty ?? true { OracleRecord.save(trail, ending: c.1) } } label: {
                        Text(c.0).font(Font.pl(size: 16)).foregroundStyle(Candle.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).candleCard(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .animation(.easeInOut(duration: 0.25), value: at)
    }
}

/// The endings he has reached, kept on the phone (the path he took is kept, per the spec).
enum OracleRecord {
    static func save(_ trail: [String], ending: String) {
        var all = UserDefaults.standard.stringArray(forKey: "oracle.endings") ?? []
        if !all.contains(ending) { all.append(ending) }
        UserDefaults.standard.set(all, forKey: "oracle.endings")
        UserDefaults.standard.set(trail, forKey: "oracle.lastPath")
        ArcadeScores.offer(.oracle, all.count)
    }
}
