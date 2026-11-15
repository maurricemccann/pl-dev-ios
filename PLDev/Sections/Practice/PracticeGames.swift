import SwiftUI

// One Teacher (S348·9a3e): Games, the free-play half of the course. His rulings 11-15: a list, not a grid; 2D Apple-native, not 3D;
// the background is the glyph field; a score, no timer; the three Academy drills sit under Games; a game not rebuilt yet stays hidden.
// The first ones, built together ("All concurrently"): The Daily Seed (Long Game and Law 3 Live merged), What Persists, Transmission.
// The glyph game was dropped (his ruling 11-15). Each game has its drilled spec: Plans/SPEC - GAMES, FIRST THREE (S348).md.
// Content comes only from canon (the course file, his affirmations, the Doctrine deck). Nothing is sent anywhere.

struct CourseItem: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let kind: String
    let text: String
    let name: String?
}

enum GameID: String, CaseIterable, Identifiable {
    case daily, persists, transmission
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "The Daily Seed"
        case .persists: return "What Persists"
        case .transmission: return "Transmission"
        }
    }
    var line: String {
        switch self {
        case .daily: return "One of your seeds each day. Hold it, mark the day. The record only grows."
        case .persists: return "Read a line, hide it when you are ready, rebuild it from memory."
        case .transmission: return "Take one intention through the First, Second and Third Truth."
        }
    }
    var symbol: String {
        switch self {
        case .daily: return "calendar"
        case .persists: return "brain.head.profile"
        case .transmission: return "arrow.triangle.turn.up.right.diamond"
        }
    }
}

/// Best scores and the daily record, on the phone. Scores only ever rise; the daily record only ever adds.
enum GameScores {
    private static var store: UserDefaults { .standard }   // computed: a stored static UserDefaults fails Swift 6's concurrency check
    static func best(_ g: GameID) -> Int { store.integer(forKey: "game.best." + g.rawValue) }
    static func offer(_ g: GameID, _ score: Int) { if score > best(g) { store.set(score, forKey: "game.best." + g.rawValue) } }
    static var dailyDays: Set<String> {
        get { Set(store.stringArray(forKey: "game.daily.days") ?? []) }
        set { store.set(Array(newValue), forKey: "game.daily.days") }
    }
    /// The phone's own calendar day (local midnight), never UTC.
    static func today(_ d: Date = .now) -> String { let f = DateFormatter(); f.calendar = .current; f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
}

struct GamesScreen: View {
    let model: AppModel
    @State private var state = CourseModel()
    @State private var playing: GameID?
    @State private var playingArcade: ArcadeID?
    @State private var unlocked: Set<String> = []

    var body: some View {
        VStack(spacing: 12) {
            if let m = state.message { Text(m).candleHint().frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(GameID.allCases) { g in
                Button { playing = g } label: { row(g) }.buttonStyle(.plain)
            }
            NavigationLink { AcademyDrillsView().osScreen() } label: {
                rowBody(title: "The three drills", line: "The Purge, the Sequence and the Rewrite, from the Academy.", symbol: "checklist", score: nil)
            }
            .buttonStyle(.plain)
            Text("The arcade").font(.system(size: 11)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            ForEach(ArcadeID.allCases) { g in
                let open = unlocked.contains(g.rawValue)
                Button { if open { playingArcade = g } } label: {
                    rowBody(title: g.title, line: open ? g.line : "Unlocks from a game card in a pack.", symbol: open ? g.symbol : "lock",
                            score: open && ArcadeScores.best(g) > 0 ? "best \(ArcadeScores.best(g))" : nil)
                        .opacity(open ? 1 : 0.6)
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "" : "Locked until a pack deals its card")
            }
        }
        .padding(12)
        .background { GlyphField(strength: 0.14).clipShape(RoundedRectangle(cornerRadius: Candle.radius, style: .continuous)) }
        .task {
            await state.load(model: model)
            if let c = await PracticeCards.load(model: model) { unlocked = Set(c.games ?? []) }
        }
        .fullScreenCover(item: $playingArcade) { g in
            GameShell(title: g.title) { playingArcade = nil } content: { arcadeGame(g, seeds: state.course.map(Self.seeds) ?? [], units: state.course?.units ?? []) }
        }
        .fullScreenCover(item: $playing) { g in
            GameShell(title: g.title) { playing = nil } content: {
                if let course = state.course { game(g, course) }
                else { Text(state.message ?? "Loading the course…").candleHint() }
            }
        }
    }

    @ViewBuilder private func game(_ g: GameID, _ course: Course) -> some View {
        switch g {
        case .daily: DailySeedGame(seeds: Self.seeds(course))
        case .persists: WhatPersistsGame(lines: Self.truths + Self.seeds(course) + Self.affirmations())
        case .transmission: TransmissionGame()
        }
    }

    private func row(_ g: GameID) -> some View {
        let best = g == .daily ? GameScores.dailyDays.count : GameScores.best(g)
        return rowBody(title: g.title, line: g.line, symbol: g.symbol, score: best > 0 ? (g == .daily ? "\(best) days" : "best \(best)") : nil)
    }

    private func rowBody(title: String, line: String, symbol: String, score: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Candle.gold).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).candleH2()
                Text(line).font(.system(size: 13)).foregroundStyle(Candle.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let score { Text(score).font(.system(size: 12).monospacedDigit()).foregroundStyle(Candle.goldHi) }
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.4))
        }
        .frame(minHeight: 44)
        .candleCard(padding: 14)
        .contentShape(Rectangle())
    }

    static let truths = ["Prepared for luxury", "You are in control of your reality", "What persists in the mind becomes your reality"]
    static func seeds(_ c: Course) -> [String] {
        c.units.first { $0.n == 6 }?.items?.filter { $0.kind == "seed" }.map(\.text).filter { $0.split(separator: " ").count <= 14 } ?? []
    }
    /// His affirmations (the lines his voice reads in the practice), as the app already holds them; his ruling 11-15 adds them here.
    static func affirmations() -> [String] {
        PracticeDeck.cached().map(\.text).filter { $0.split(separator: " ").count <= 14 }
    }
}

/// Full screen with a close button, the practice's ground and the glyph field faintly behind.
struct GameShell<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            CandleGround()
            GlyphField(strength: 0.07).ignoresSafeArea().blendMode(.screen)
            VStack(spacing: 16) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Candle.ink).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close the game")
                    Text(title).plHand(22, relativeTo: .title2).foregroundStyle(Candle.goldHi)
                    Spacer()
                }
                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 40) }
            }
            .padding(20).frame(maxWidth: 640)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - The Daily Seed (Long Game + Law 3 Live)

struct DailySeedGame: View {
    let seeds: [String]
    @State private var days = GameScores.dailyDays
    private var today: String { GameScores.today() }
    /// Today's seed: the same all day, a different one tomorrow, every seed before any repeats.
    private var seed: String? {
        guard !seeds.isEmpty else { return nil }
        let day = Int((Calendar.current.startOfDay(for: .now).timeIntervalSince1970 / 86400).rounded())
        return seeds[((day % seeds.count) + seeds.count) % seeds.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let seed {
                Text("Today's seed").font(.system(size: 12)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                Text(seed).font(.system(size: 22)).foregroundStyle(Candle.goldHi).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No seeds yet: star seed phrases in Curate and they arrive here.").candleHint()
            }
            if days.contains(today) {
                Text("Held today. \(days.count) \(days.count == 1 ? "day" : "days") in all.").font(.system(size: 15, weight: .medium)).foregroundStyle(Candle.ink)
            } else {
                Button("I held it today") { days.insert(today); GameScores.dailyDays = days }.buttonStyle(CandleButton()).disabled(seed == nil)
            }
            grid
            Text("A missed day stays empty; nothing is ever taken away.").candleHint()
        }
        .sensoryFeedback(PLHaptic.success, trigger: days.count)
    }

    /// The last 52 weeks, a square per day, gold where he held the seed.
    private var grid: some View {
        let cal = Calendar.current, start = cal.date(byAdding: .day, value: -363, to: cal.startOfDay(for: .now)) ?? .now
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 26)
        return LazyVGrid(columns: cols, spacing: 2) {
            ForEach(0..<364, id: \.self) { i in
                let d = cal.date(byAdding: .day, value: i, to: start) ?? .now
                RoundedRectangle(cornerRadius: 2).fill(days.contains(GameScores.today(d)) ? Candle.gold : Candle.pillLine.opacity(0.6)).aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityLabel("\(days.count) days held in the last year")
    }
}

// MARK: - What Persists

struct WhatPersistsGame: View {
    let lines: [String]
    @State private var round = 0
    @State private var right = 0
    @State private var result: Bool?
    @State private var deck: [String] = []
    private let rounds = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if deck.isEmpty {
                Text("No lines to hold yet.").candleHint()
            } else if round < min(rounds, deck.count) {
                Text("Round \(round + 1) of \(min(rounds, deck.count)) · \(right) right").font(.system(size: 12).monospacedDigit()).foregroundStyle(Candle.ink.opacity(0.6))
                let line = deck[round]
                TileExercise(shownFirst: line, target: line.split(separator: " ").map(String.init), separator: " ", locked: result != nil) { ok in
                    result = ok; if ok { right += 1 }
                }
                .id(round)
                if let result {
                    Text(result ? "Held." : "Not this time:").font(.system(size: 15, weight: .medium)).foregroundStyle(result ? Candle.goldHi : Candle.ink)
                    if !result { Text(line).font(.system(size: 15)).foregroundStyle(Candle.ink) }
                    Button("Next") { self.result = nil; round += 1; if round >= min(rounds, deck.count) { GameScores.offer(.persists, right) } }.buttonStyle(CandleButton())
                }
            } else {
                Text("\(right) of \(min(rounds, deck.count)) held.").plHand(26, relativeTo: .title).foregroundStyle(Candle.goldHi)
                Text("Best: \(GameScores.best(.persists))").candleHint()
                Button("Play again") { start() }.buttonStyle(CandleButton())
            }
        }
        .onAppear { if deck.isEmpty { start() } }
        .sensoryFeedback(PLHaptic.success, trigger: right)
    }

    private func start() { deck = Array(lines.shuffled().prefix(rounds)); round = 0; right = 0; result = nil }
}

// MARK: - Transmission (one intention through the three Truths, in order)

struct TransmissionGame: View {
    /// His ruling 11-15: his Doctrine deck's question on each Truth ("Use your Doctrine ones"), and mine ("And yours").
    /// `doctrine` is word for word from pl-academy DECKS.doctrine; `ask` is about the intention he names.
    private static let stages: [(truth: String, ask: String, doctrine: String)] = [
        ("Prepared for luxury", "What would already be in place if this were arriving tomorrow? Name one thing to prepare.",
         "Take today's piece. Apply the First Truth to it: where in its composition does preparation show?"),
        ("You are in control of your reality", "What do you decide about it, as its author? Write it as a decision, not a hope.",
         "Write the Second Truth as a refusal — what does control of reality decline to negotiate?"),
        ("What persists in the mind becomes your reality", "What line will you keep in mind about it each day?",
         "Identify a subculture that already lives the Third Truth without naming it. What would they recognize in the work instantly?"),
    ]
    @AppStorage("game.transmission.done") private var done = 0
    @State private var intention = ""
    @State private var answers = ["", "", ""]
    @State private var doctrine = ["", "", ""]
    @State private var stage = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if stage < 0 {
                Text("Name one intention.").candleH2()
                PField(prompt: "What are you bringing in?", text: $intention, lines: 2)
                Button("Begin") { stage = 0 }.buttonStyle(CandleButton()).disabled(intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if stage < 3 {
                Text(["The First Truth", "The Second Truth", "The Third Truth"][stage]).font(.system(size: 12)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                Text(Self.stages[stage].truth).font(.system(size: 22)).foregroundStyle(Candle.goldHi)
                Text(Self.stages[stage].ask).font(.system(size: 15)).foregroundStyle(Candle.ink).fixedSize(horizontal: false, vertical: true)
                PField(prompt: "One line.", text: $answers[stage], lines: 3)
                Text("From the Doctrine deck").font(.system(size: 11)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold).padding(.top, 6)
                Text(Self.stages[stage].doctrine).font(.system(size: 15, design: .serif).italic()).foregroundStyle(Candle.goldHi).fixedSize(horizontal: false, vertical: true)
                PField(prompt: "One line (optional).", text: $doctrine[stage], lines: 3)
                Button(stage < 2 ? "Next Truth" : "Complete") { stage += 1; if stage == 3 { done += 1; GameScores.offer(.transmission, done) } }
                    .buttonStyle(CandleButton()).disabled(answers[stage].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text(intention).font(.system(size: 20, weight: .medium)).foregroundStyle(Candle.goldHi)
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.stages[i].truth).font(.system(size: 12)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                        Text(answers[i]).font(.system(size: 15)).foregroundStyle(Candle.ink)
                        if !doctrine[i].isEmpty { Text(doctrine[i]).font(.system(size: 14, design: .serif).italic()).foregroundStyle(Candle.goldHi) }
                    }
                    .candleCard(padding: 12)
                }
                Text("\(done) transmitted in all.").candleHint()
                Button("Another") { intention = ""; answers = ["", "", ""]; doctrine = ["", "", ""]; stage = -1 }.buttonStyle(CandleButton())
            }
        }
    }
}
