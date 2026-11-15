import SwiftUI

// The arcade (S348·9a3e, spec vault Plans/SPEC - ARCADE GAMES (S348).md): the six beta arcade games rebuilt native and 2D, each
// unlocked by a game card from a pack ("A reward you unlock"), then always in Games. Mechanics follow the beta code (C:\dev\PL Beta
// Games), with its bugs fixed; his rulings 11-15: his 5 drawn glyphs replace the invented marks, the runner drops INTERFERENCE,
// Archive Circles is dropped (Preparation is that game). Scores live on the phone and only rise.

enum ArcadeID: String, CaseIterable, Identifiable {
    case preparation, theReturn = "the-return", practice = "the-practice", compound, restore = "restore-the-archive", resonance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .preparation: return "Preparation"
        case .theReturn: return "The Return"
        case .practice: return "The Practice"
        case .compound: return "Compound"
        case .restore: return "Restore the Archive"
        case .resonance: return "Resonance"
        }
    }
    var line: String {
        switch self {
        case .preparation: return "Tap the instant the circle flares. Five rounds."
        case .theReturn: return "Watch your glyphs light, then return the sequence."
        case .practice: return "One tap to jump. Days of practice are the score."
        case .compound: return "Merge the stages from Day 1 to Year 7."
        case .restore: return "Slide the pieces until the archive work is whole."
        case .resonance: return "Swap your glyphs, match three, reach 500."
        }
    }
    var symbol: String {
        switch self {
        case .preparation: return "circle.dotted.circle"
        case .theReturn: return "arrow.triangle.2.circlepath"
        case .practice: return "figure.run"
        case .compound: return "square.grid.3x3.fill"
        case .restore: return "square.grid.4x3.fill"
        case .resonance: return "sparkles"
        }
    }
}

enum ArcadeScores {
    private static var store: UserDefaults { .standard }
    static func best(_ g: ArcadeID) -> Int { store.integer(forKey: "arcade.best." + g.rawValue) }
    static func offer(_ g: ArcadeID, _ s: Int) { if s > best(g) { store.set(s, forKey: "arcade.best." + g.rawValue) } }
}

/// One of his drawn glyphs, filled, fitted to its frame.
struct ArcadeGlyph: View {
    let index: Int
    var colour: Color = Candle.ink
    var body: some View {
        GeometryReader { geo in
            let g = PracticeMapArt.glyphs[index % PracticeMapArt.glyphs.count]
            PracticeMapGeometry.glyph(g, side: min(geo.size.width, geo.size.height) * 0.8, centre: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                .fill(colour, style: FillStyle(eoFill: true))
        }
        .accessibilityLabel(PracticeMapArt.glyphs[index % PracticeMapArt.glyphs.count].name)
    }
}

@ViewBuilder func arcadeGame(_ g: ArcadeID, seeds: [String]) -> some View {
    switch g {
    case .preparation: PreparationGame(principles: seeds)
    case .theReturn: ReturnGame()
    case .practice: RunnerGame(endLines: seeds)
    case .compound: CompoundGame()
    case .restore: RestoreGame()
    case .resonance: ResonanceGame()
    }
}

// MARK: - Preparation (Truth 1)

struct PreparationGame: View {
    let principles: [String]
    enum Phase { case idle, armed, flash, result, done }
    @State private var phase = Phase.idle
    @State private var round = 0
    @State private var scores: [Int] = []
    @State private var flashAt: Date?
    @State private var label = ""
    @State private var principle: String?
    @State private var token = 0
    private let rounds = 5

    var body: some View {
        VStack(spacing: 18) {
            Text(phase == .done ? "Preparation Index" : "Round \(min(round + 1, rounds)) of \(rounds)").candleHint()
            TimelineView(.animation) { tl in
                let pulse = 46 + 6 * sin(tl.date.timeIntervalSinceReferenceDate * .pi / 2)
                let lit = phase == .flash && (flashAt.map { tl.date.timeIntervalSince($0) < 0.11 } ?? false)
                ZStack {
                    Circle().fill(Candle.gold.opacity(0.06)).frame(width: pulse * 3.2)
                    Circle().fill(lit ? Candle.goldHi : Candle.gold.opacity(0.25)).frame(width: (pulse + (lit ? 10 : 0)) * 2)
                }
                .frame(maxWidth: .infinity).frame(height: 260)
            }
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            .accessibilityLabel("The circle. Tap the instant it flares.")
            .accessibilityAddTraits(.isButton)
            if phase == .done {
                let index = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
                Text("\(index) / 100").plHand(34, relativeTo: .largeTitle).foregroundStyle(Candle.goldHi)
                Text("Best \(ArcadeScores.best(.preparation))").candleHint()
                Button("Again") { start() }.buttonStyle(CandleButton())
            } else if phase == .idle {
                Text("Do not anticipate. Tap the instant it flares.").candleHint()
                Button("Begin") { start() }.buttonStyle(CandleButton())
            } else {
                Text(label).font(.system(size: 17, weight: .medium)).foregroundStyle(Candle.ink).frame(minHeight: 24)
                if let principle, phase == .result { Text(principle).font(.system(size: 14, design: .serif).italic()).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center) }
            }
        }
        .sensoryFeedback(PLHaptic.success, trigger: scores.count)
    }

    private func start() { round = 0; scores = []; arm() }

    private func arm() {
        phase = .armed; label = "Wait for it."; principle = nil; token += 1
        let t = token, delay = Double.random(in: 4...14)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard t == token, phase == .armed else { return }
            phase = .flash; flashAt = .now
            try? await Task.sleep(for: .seconds(1.5))
            if t == token, phase == .flash { record(nil) }   // no tap in 1.5 s: a miss
        }
    }

    private func tap() {
        switch phase {
        case .armed: token += 1; label = "Too early. It had not flared."; scores.append(0); next()
        case .flash: record(flashAt.map { Date().timeIntervalSince($0) * 1000 })
        default: break
        }
    }

    private func record(_ ms: Double?) {
        token += 1
        let s = ms.map { max(0, Int((100 - $0 / 180 * 100).rounded())) } ?? 0
        scores.append(s)
        if let ms { label = (ms <= 30 ? "You are ready." : (s >= 90 ? "Perfect" : s >= 70 ? "Sharp" : s >= 40 ? "Close" : "Late")) + "  \(Int(ms)) ms" }
        else { label = "Missed." }
        next()
    }

    private func next() {
        phase = .result
        principle = principles.isEmpty ? nil : principles[(round + scores.count) % principles.count]
        round += 1
        let t = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard t == token else { return }
            if round >= rounds { phase = .done; ArcadeScores.offer(.preparation, scores.reduce(0, +) / max(1, scores.count)) } else { arm() }
        }
    }
}

// MARK: - The Return (his glyphs, Simon)

struct ReturnGame: View {
    @State private var sequence: [Int] = []
    @State private var input = 0
    @State private var lit: Int?
    @State private var wrong: Int?
    @State private var playing = false
    @State private var status = "Watch, then return the sequence."
    private let n = PracticeMapArt.glyphs.count

    var body: some View {
        VStack(spacing: 18) {
            Text("Length \(sequence.count) · best \(ArcadeScores.best(.theReturn))").candleHint()
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) * 0.36, c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    ForEach(0..<n, id: \.self) { i in
                        let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        Button { press(i) } label: {
                            ArcadeGlyph(index: i, colour: lit == i ? Color.black : Candle.ink)
                                .padding(14)
                                .frame(width: 88, height: 88)
                                .background(wrong == i ? Color.red.opacity(0.6) : (lit == i ? Candle.goldHi : Candle.card), in: Circle())
                                .overlay { Circle().strokeBorder(Candle.hairline, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .disabled(playing || sequence.isEmpty)
                        .position(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    }
                }
            }
            .frame(height: 330)
            Text(status).font(.system(size: 15)).foregroundStyle(Candle.ink).multilineTextAlignment(.center)
            if sequence.isEmpty { Button("Begin") { grow() }.buttonStyle(CandleButton()) }
        }
        .sensoryFeedback(PLHaptic.select, trigger: lit ?? -1)
    }

    private func grow() {
        sequence.append(Int.random(in: 0..<n)); input = 0
        playing = true; status = "Watch."
        let seq = sequence
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            for i in seq { lit = i; try? await Task.sleep(for: .seconds(0.5)); lit = nil; try? await Task.sleep(for: .seconds(0.3)) }
            playing = false; status = "Return it."
        }
    }

    private func press(_ i: Int) {
        guard !playing, input < sequence.count else { return }
        if i == sequence[input] {
            lit = i
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.25)); if lit == i { lit = nil } }
            input += 1
            if input == sequence.count {
                ArcadeScores.offer(.theReturn, sequence.count)
                status = sequence.count >= 10 ? "Watch this." : "Held. One longer."
                Task { @MainActor in try? await Task.sleep(for: .seconds(0.8)); grow() }
            }
        } else {
            wrong = i; status = "The practice is return. Begin again."
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.2)); wrong = nil; sequence = []; input = 0; status = "Watch, then return the sequence." }
        }
    }
}

// MARK: - The Practice (runner)

@MainActor @Observable final class RunnerModel {
    struct Obstacle { var x: Double; let h: Double; let label: String }
    var y = 0.0
    var vy = 0.0
    var days = 0.0
    var speed = 180.0
    var spawnIn = 1.5
    var obstacles: [Obstacle] = []
    var running = false
    var over = false
    var last: Date?
    let words = ["DOUBT", "DISTRACTION", "FEAR", "NOISE", "RESISTANCE", "DELAY"]

    func reset() { y = 0; vy = 0; days = 0; spawnIn = 1.5; obstacles = []; over = false; running = true; last = nil }
    func jump() { if y == 0 { vy = 840 } }

    /// The beta's per-frame values at 60 fps, as per-second ones: jump 14 px/frame, gravity 0.6 px/frame², speed 3 + days*0.008 px/frame,
    /// days 0.04 a frame, a spawn every max(45, 90 - days*0.3) frames.
    func step(_ now: Date, width: Double) {
        defer { last = now }
        guard running, !over, let last else { return }
        let dt = min(0.05, now.timeIntervalSince(last))
        vy -= 2160 * dt; y = max(0, y + vy * dt); if y == 0 { vy = 0 }
        days += 2.4 * dt
        speed = (3 + days * 0.008) * 60
        for i in obstacles.indices { obstacles[i].x -= speed * dt }
        obstacles.removeAll { $0.x < -40 }
        spawnIn -= dt
        if spawnIn <= 0 {
            obstacles.append(Obstacle(x: width + 20, h: Double.random(in: 20...40), label: words.randomElement() ?? "DOUBT"))
            spawnIn = max(45, 90 - days * 0.3) / 60
        }
        let fx = width * 0.2
        for o in obstacles where abs(o.x - fx) < 4 + 8 && y < o.h { over = true; running = false }
    }
}

struct RunnerGame: View {
    let endLines: [String]
    @State private var m = RunnerModel()

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation(paused: !m.running)) { tl in
                Canvas { ctx, size in
                    m.step(tl.date, width: size.width)
                    let ground = size.height * 0.75, fx = size.width * 0.2
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: ground)); p.addLine(to: CGPoint(x: size.width, y: ground)) }, with: .color(Candle.gold.opacity(0.3)), lineWidth: 1)
                    let feet = ground - m.y
                    var fig = Path()
                    fig.addEllipse(in: CGRect(x: fx - 6, y: feet - 40, width: 12, height: 12))
                    fig.move(to: CGPoint(x: fx, y: feet - 28)); fig.addLine(to: CGPoint(x: fx, y: feet - 12))
                    fig.move(to: CGPoint(x: fx, y: feet - 12)); fig.addLine(to: CGPoint(x: fx - 6, y: feet))
                    fig.move(to: CGPoint(x: fx, y: feet - 12)); fig.addLine(to: CGPoint(x: fx + 6, y: feet))
                    fig.move(to: CGPoint(x: fx - 8, y: feet - 22)); fig.addLine(to: CGPoint(x: fx + 8, y: feet - 22))
                    ctx.stroke(fig, with: .color(Candle.gold), lineWidth: 2)
                    for o in m.obstacles {
                        ctx.fill(Path(CGRect(x: o.x - 4, y: ground - o.h, width: 8, height: o.h)), with: .color(Color(red: 160 / 255, green: 60 / 255, blue: 60 / 255).opacity(0.75)))
                        ctx.draw(Text(o.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Candle.ink.opacity(0.7)), at: CGPoint(x: o.x, y: ground - o.h - 10))
                    }
                    ctx.draw(Text("\(Int(m.days)) days").font(.system(size: 14).monospacedDigit()).foregroundStyle(Candle.goldHi), at: CGPoint(x: size.width - 50, y: 20))
                }
            }
            .frame(height: 300)
            .background(Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if m.running { m.jump() } }
            .accessibilityLabel("The run. Tap to jump.")
            if m.over {
                Text("\(Int(m.days)) days of practice.").plHand(28, relativeTo: .title).foregroundStyle(Candle.goldHi)
                Text(endLines.randomElement() ?? "Despite the conditions.").font(.system(size: 14, design: .serif).italic()).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
                Text("Best \(ArcadeScores.best(.practice)) days").candleHint()
                Button("Run again") { m.reset() }.buttonStyle(CandleButton())
            } else if !m.running {
                Text("Daily. Without exception. Jump doubt, distraction, fear.").candleHint()
                Button("Begin") { m.reset() }.buttonStyle(CandleButton())
            }
        }
        .onChange(of: m.over) { _, over in if over { ArcadeScores.offer(.practice, Int(m.days)) } }
    }
}

// MARK: - Compound (2048, stages of the practice)

struct CompoundGame: View {
    static let stages: [Int: String] = [2: "Day 1", 4: "Week 1", 8: "Month 1", 16: "Month 3", 32: "Month 6", 64: "Year 1", 128: "Year 2",
                                        256: "Year 3", 512: "Year 4", 1024: "Year 5", 2048: "Year 7"]
    @State private var board = [Int](repeating: 0, count: 16)
    @State private var score = 0
    @State private var state = "play"   // play, won, over

    var body: some View {
        VStack(spacing: 14) {
            Text("Score \(score) · best \(ArcadeScores.best(.compound))").candleHint()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<16, id: \.self) { i in
                    let v = board[i]
                    Text(v == 0 ? "" : (Self.stages[v] ?? "\(v)"))
                        .font(.system(size: 13, weight: .semibold)).minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(v >= 64 ? Color.black : Candle.ink)
                        .frame(maxWidth: .infinity).frame(height: 72)
                        .background(v == 0 ? Candle.field : Candle.gold.opacity(min(1, 0.15 + log2(Double(max(v, 2))) * 0.08)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(8)
            .background(Candle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .highPriorityGesture(DragGesture(minimumDistance: 20).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                move(abs(dx) > abs(dy) ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0))
            })
            .accessibilityLabel("The board. Swipe to merge.")
            if state == "won" { Text("Year 7. The practice compounds.").plHand(24, relativeTo: .title2).foregroundStyle(Candle.goldHi) }
            if state == "over" { Text("No moves left. \(score) points.").font(.system(size: 15)).foregroundStyle(Candle.ink) }
            if state != "play" { Button("Again") { start() }.buttonStyle(CandleButton()) }
            Text("Swipe up, down, left or right.").candleHint()
        }
        .onAppear { if board.allSatisfy({ $0 == 0 }) { start() } }
        .sensoryFeedback(PLHaptic.select, trigger: score)
    }

    private func start() { board = Array(repeating: 0, count: 16); score = 0; state = "play"; add(); add() }
    private func add() {
        let empty = board.indices.filter { board[$0] == 0 }
        if let i = empty.randomElement() { board[i] = Double.random(in: 0..<1) < 0.9 ? 2 : 4 }
    }

    /// dir: 0 up, 1 right, 2 down, 3 left.
    private func move(_ dir: Int) {
        guard state == "play" else { return }
        var b = board, gained = 0
        for line in 0..<4 {
            let idx: [Int] = (0..<4).map { k in
                switch dir {
                case 0: return k * 4 + line
                case 2: return (3 - k) * 4 + line
                case 3: return line * 4 + k
                default: return line * 4 + (3 - k)
                }
            }
            var vals = idx.map { b[$0] }.filter { $0 != 0 }, out: [Int] = []
            var k = 0
            while k < vals.count {
                if k + 1 < vals.count && vals[k] == vals[k + 1] { out.append(vals[k] * 2); gained += vals[k] * 2; k += 2 } else { out.append(vals[k]); k += 1 }
            }
            vals = out + Array(repeating: 0, count: 4 - out.count)
            for (j, i) in idx.enumerated() { b[i] = vals[j] }
        }
        guard b != board else { return }
        withAnimation(.snappy(duration: 0.15)) { board = b; score += gained }
        add()
        ArcadeScores.offer(.compound, score)
        if board.contains(2048) { state = "won" } else if !canMove() { state = "over" }
    }

    private func canMove() -> Bool {
        if board.contains(0) { return true }
        for r in 0..<4 { for c in 0..<4 {
            let v = board[r * 4 + c]
            if c < 3 && board[r * 4 + c + 1] == v { return true }
            if r < 3 && board[(r + 1) * 4 + c] == v { return true }
        } }
        return false
    }
}

// MARK: - Restore the Archive (sliding puzzle of a real piece)

struct RestoreGame: View {
    private static let words = ["CURVE", "MARK", "GLYPH", "VOID", "GOLD", "PRACTICE", "PATTERN", "FIGURE", "SIGNAL", "ARCHIVE", "PERSIST", "CONTROL", "PREPARE", "RETURN", "DESCENT"]
    struct Piece: Decodable { let cr: String?; let title: String?; let thumb: String?; let url: String? }
    struct Manifest: Decodable { let pieces: [Piece] }
    @State private var board = Array(0..<16)
    @State private var moves = 0
    @State private var image: UIImage?
    @State private var piece: Piece?
    @State private var hint = false
    @State private var loading = true

    private var solved: Bool { board == Array(0..<16) }

    var body: some View {
        VStack(spacing: 14) {
            Text(solved && moves > 0 ? "Archive restored in \(moves) moves." : "\(moves) moves").candleHint()
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height), cell = side / 4
                ZStack(alignment: .topLeading) {
                    ForEach(0..<16, id: \.self) { pos in
                        let v = board[pos]
                        if v != 15 || solved {
                            tile(v, cell: cell)
                                .frame(width: cell - 3, height: cell - 3)
                                .offset(x: CGFloat(pos % 4) * cell, y: CGFloat(pos / 4) * cell)
                                .onTapGesture { slide(pos) }
                        }
                    }
                    if hint, let image { Image(uiImage: image).resizable().frame(width: side, height: side).opacity(0.9) }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            if solved && moves > 0, let piece { Text([piece.title, piece.cr].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 15, weight: .medium)).foregroundStyle(Candle.goldHi) }
            HStack(spacing: 10) {
                if image != nil { Button(hint ? "Hide the work" : "Show the work") { hint.toggle() }.buttonStyle(CandleGhost()) }
                Button("New piece") { Task { await load() } }.buttonStyle(CandleGhost())
            }
            if loading { ProgressView().tint(Candle.gold) }
        }
        .task { await load() }
        .sensoryFeedback(PLHaptic.select, trigger: moves)
    }

    @ViewBuilder private func tile(_ v: Int, cell: CGFloat) -> some View {
        if let image, let cg = image.cgImage {
            let w = cg.width / 4, h = cg.height / 4
            if let part = cg.cropping(to: CGRect(x: (v % 4) * w, y: (v / 4) * h, width: w, height: h)) {
                Image(uiImage: UIImage(cgImage: part)).resizable().clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        } else {
            Text(Self.words[min(v, 14)]).font(.system(size: 11, weight: .semibold)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(Candle.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Candle.card, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private func slide(_ pos: Int) {
        guard !solved || moves == 0, let empty = board.firstIndex(of: 15) else { return }
        let (r, c, er, ec) = (pos / 4, pos % 4, empty / 4, empty % 4)
        guard abs(r - er) + abs(c - ec) == 1 else { return }
        withAnimation(.snappy(duration: 0.12)) { board.swapAt(pos, empty) }
        moves += 1
        if solved { ArcadeScores.offer(.restore, max(1, 1000 - moves)) }
    }

    /// 500 random legal moves from solved, so it is always solvable (the beta's method).
    private func scramble() {
        var b = Array(0..<16), e = 15
        for _ in 0..<500 {
            let r = e / 4, c = e % 4
            let next = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)].filter { $0.0 >= 0 && $0.0 < 4 && $0.1 >= 0 && $0.1 < 4 }.randomElement()!
            let n = next.0 * 4 + next.1
            b.swapAt(e, n); e = n
        }
        board = b == Array(0..<16) ? [1, 0] + Array(2..<16) : b
        moves = 0; hint = false
    }

    private func load() async {
        loading = true; defer { loading = false }
        scramble()
        image = nil
        guard let url = URL(string: "https://assets.psychedluxuries.com/manifest.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let m = try? JSONDecoder().decode(Manifest.self, from: data),
              let p = m.pieces.filter({ $0.thumb != nil || $0.url != nil }).randomElement(),
              let src = URL(string: p.thumb ?? p.url ?? ""),
              let (img, _) = try? await URLSession.shared.data(from: src),
              let ui = UIImage(data: img) else { return }   // offline: the word tiles stay
        // square-crop the work so the sixteen pieces are equal
        if let cg = ui.cgImage {
            let s = min(cg.width, cg.height)
            if let sq = cg.cropping(to: CGRect(x: (cg.width - s) / 2, y: (cg.height - s) / 2, width: s, height: s)) { image = UIImage(cgImage: sq) }
        }
        piece = p
    }
}

// MARK: - Resonance (match-3 of his glyphs)

struct ResonanceGame: View {
    private static let size = 7, kinds = 5, goal = 500
    @State private var grid: [Int] = []
    @State private var picked: Int?
    @State private var score = 0

    var body: some View {
        VStack(spacing: 14) {
            Text(score >= Self.goal ? "Resonance achieved. \(score)." : "\(score) of \(Self.goal) · best \(ArcadeScores.best(.resonance))").candleHint()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: Self.size), spacing: 4) {
                ForEach(grid.indices, id: \.self) { i in
                    Button { tap(i) } label: {
                        ArcadeGlyph(index: grid[i], colour: picked == i ? Color.black : Candle.ink)
                            .padding(5)
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .background(picked == i ? Candle.goldHi : Candle.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            if score >= Self.goal { Button("Again") { start() }.buttonStyle(CandleButton()) }
            Text("Tap a glyph, then a neighbour, to swap. Three in a line resonate.").candleHint()
        }
        .onAppear { if grid.isEmpty { start() } }
        .sensoryFeedback(PLHaptic.success, trigger: score)
    }

    private func start() {
        score = 0; picked = nil
        repeat { grid = (0..<(Self.size * Self.size)).map { _ in Int.random(in: 0..<Self.kinds) } } while !matches(grid).isEmpty || !hasMove(grid)
    }

    private func tap(_ i: Int) {
        guard score < Self.goal else { return }
        guard let p = picked else { picked = i; return }
        if p == i { picked = nil; return }
        let (r1, c1, r2, c2) = (p / Self.size, p % Self.size, i / Self.size, i % Self.size)
        guard abs(r1 - r2) + abs(c1 - c2) == 1 else { picked = i; return }
        var g = grid; g.swapAt(p, i)
        picked = nil
        guard !matches(g).isEmpty else { return }   // no match: the swap does not happen (the beta's rule)
        withAnimation(.snappy(duration: 0.18)) { grid = g }
        resolve()
    }

    /// Clear, fall, refill, until nothing matches; then reshuffle if no move is left (the beta could strand the player).
    private func resolve() {
        var g = grid, gained = 0
        while true {
            let m = matches(g)
            if m.isEmpty { break }
            gained += m.count * 10
            for i in m { g[i] = -1 }
            for c in 0..<Self.size {
                var col = (0..<Self.size).map { g[$0 * Self.size + c] }.filter { $0 >= 0 }
                while col.count < Self.size { col.insert(Int.random(in: 0..<Self.kinds), at: 0) }
                for r in 0..<Self.size { g[r * Self.size + c] = col[r] }
            }
        }
        while !hasMove(g) { g.shuffle(); if matches(g).isEmpty == false { continue } }
        withAnimation(.snappy(duration: 0.2)) { grid = g; score += gained }
        ArcadeScores.offer(.resonance, score)
    }

    private func matches(_ g: [Int]) -> Set<Int> {
        var out = Set<Int>(); let n = Self.size
        for r in 0..<n { for c in 0..<(n - 2) {
            let a = r * n + c
            if g[a] >= 0 && g[a] == g[a + 1] && g[a] == g[a + 2] { out.formUnion([a, a + 1, a + 2]) }
        } }
        for c in 0..<n { for r in 0..<(n - 2) {
            let a = r * n + c
            if g[a] >= 0 && g[a] == g[a + n] && g[a] == g[a + 2 * n] { out.formUnion([a, a + n, a + 2 * n]) }
        } }
        return out
    }

    private func hasMove(_ g: [Int]) -> Bool {
        let n = Self.size
        for i in g.indices {
            for j in [i + 1, i + n] where j < g.count && (j != i + 1 || i % n < n - 1) {
                var t = g; t.swapAt(i, j)
                if !matches(t).isEmpty { return true }
            }
        }
        return false
    }
}
