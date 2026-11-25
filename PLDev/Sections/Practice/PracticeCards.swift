import SwiftUI

// The Today screen, card for card in the web app's order (`pl-manifestation-practice/public/index.html`): streak, Scratchpad,
// Wins & Noticed, Morning, Lesson, Reframe, Affirmations, Conversation, Desire List, Habits, Meditation, Vision board, Evening.
// Same calls, same words. Where the web had a workaround (an `<audio>` element, a `<select>`, a `<details>`), the phone has the real thing.

/// A chat bubble as the practice draws it (`.convo-user` / `.convo-assistant`): his words on gold with dark text; the coach's on the
/// card with the field hairline, in a serif italic gold-hi. Shared with GlyphBot.
struct PracticeBubble: View {
    let text: String
    let mine: Bool
    var caption: String?

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(text).textSelection(.enabled)
                    .font(mine ? .system(size: 14) : .system(size: 14, design: .serif).italic())
                    .foregroundStyle(mine ? Candle.bg : Candle.goldHi).lineSpacing(3)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(mine ? Candle.gold : Candle.card, in: RoundedRectangle(cornerRadius: 8 * PLStyle.radius, style: .continuous))
                    .overlay { if !mine { RoundedRectangle(cornerRadius: 8 * PLStyle.radius, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) } }
                if let caption { Text(caption).font(Font.pl(.caption2)).foregroundStyle(Candle.ink.opacity(0.5)) }
            }
            if !mine { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : "Coach"): \(text)")
    }
}

/// What a failed read says in a card, and what an offline write says.
enum PracticeWords {
    static let offlineSaved = "Saved on this iPhone. It sends when you are online."
    static func loadFailed(_ what: String) -> String { "Could not load \(what). Pull to try again." }
}

// MARK: - The streak (soft: days this month and in all, nothing to break)

struct StreakCard: View {
    let state: PracticeModel
    var body: some View {
        let n = state.streak?.practisedThisMonth ?? 0
        let total = state.streak?.practisedTotal ?? 0
        let goal = [7, 30, 100, 365, 1000].first { $0 > total } ?? total   // the next round number; the arc only grows (his ruling 11-24)
        VStack(spacing: 8) {
            // the arc tells the same story as the centre: the total, toward its next round number
            PLRing(value: Double(total) / Double(max(goal, 1)), center: "\(total)", label: "days practised", tint: Candle.goldHi,
                   text: Candle.goldHi, dim: Candle.ink.opacity(0.6), size: 96)
            if n > 0 {
                Text("\(n) this month")
                    .font(Font.pl(size: 12.8)).foregroundStyle(Candle.ink.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .accessibilityElement(children: .combine)
        .id("streak")
    }
}

// MARK: - Scratchpad: the notes stack and fade, nothing ever disappears

struct ScratchpadCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var notes: [PracticeNote] = []
    @State private var text = ""
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        PCard(title: "Scratchpad", id: "scratchpad") {
            PField(prompt: "Quick note\u{2026}", text: $text, lines: 2)
            HStack { Button("Add") { Task { await add() } }.buttonStyle(CandleButton()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Spacer(minLength: 0) }
            CandleResult(text: result)
            if failed && notes.isEmpty { Text(PracticeWords.loadFailed("your notes")).candleHint() }
            if !notes.isEmpty {
                VStack(spacing: -6) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { i, n in
                        let depth = min(i, 4)
                        Text(n.text).font(Font.pl(size: 13.6)).foregroundStyle(Candle.ink).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Candle.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 8 * PLStyle.radius, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 8 * PLStyle.radius, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
                            .opacity([1, 0.8, 0.6, 0.4, 0.25][depth]).scaleEffect([1, 0.98, 0.96, 0.94, 0.92][depth])
                            .zIndex(Double(notes.count - i))
                            .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = n.text } }
                    }
                }
                .padding(.top, 6).padding(.bottom, 6)
            }
        }
        .task(id: state.reload) { await load() }
    }

    private func load() async {
        if let l = try? await Practice.get("notes", [PracticeNote].self, model: model) { notes = l; failed = false } else { failed = true }
    }

    private func add() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let sent = try await Practice.postQueued("notes", ["text": t], model: model)
            text = ""; result = sent ? nil : PracticeWords.offlineSaved; state.tick += 1
            if sent { await load() }
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Wins & Noticed

struct WinsCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var logs: [PracticeLog] = []
    @State private var summary: PracticeLogSummary?
    @State private var text = ""
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        PCard(title: "Wins & Noticed", hint: "a win = proof you can \u{00B7} noticed = the filter is working", id: "wins") {
            PField(prompt: "What happened?", text: $text, lines: 2)
            HStack(spacing: 6) {
                Button("Log a win") { Task { await add("win") } }.buttonStyle(CandleButton())
                Button("I noticed\u{2026}") { Task { await add("noticed") } }.buttonStyle(CandleGhost())
                Spacer(minLength: 0)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            CandleResult(text: result)
            if failed && logs.isEmpty { Text(PracticeWords.loadFailed("the log")).candleHint() }
            // S350, his pick 11-21 ("Show the log growing"): the whole log's size and the first line ever kept
            if let s = summary, s.total > 0 {
                Text("\(s.total) kept" + (s.first.map { " \u{00B7} first: \u{201C}\($0.text)\u{201D}" } ?? "")).candleHint().lineLimit(2)
            }
            VStack(spacing: 0) {
                ForEach(logs) { l in
                    CandleRule()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        KindPill(kind: l.kind)
                        Text(l.text).font(Font.pl(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .task(id: state.reload) { await load() }
    }

    private func load() async {
        if let l = try? await Practice.get("logs", [PracticeLog].self, model: model) { logs = l; failed = false } else { failed = true }
        summary = try? await Practice.get("logs/summary", PracticeLogSummary.self, model: model)   // older server: no line, never a wrong count
    }

    private func add(_ kind: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let sent = try await Practice.postQueued("logs", ["kind": kind, "text": t], model: model)
            text = ""; result = sent ? nil : PracticeWords.offlineSaved; state.tick += 1
            if sent { await load() }
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Morning and evening (the only two that count toward the streak)

struct CheckinCard: View {
    let model: AppModel
    let state: PracticeModel
    let evening: Bool
    nonisolated private static var moods: [String] { ThemeFeed.list(ThemeFeed.feed?.practice?.moods) ?? ["calm", "hopeful", "doubtful", "anxious", "grounded"] }   // config over the air (S353·7b1e)
    @State private var mood = "calm"
    @State private var story = ""
    @State private var gratitude = ""
    @State private var shifted = ""
    @State private var note = ""
    @State private var result: String?
    @State private var busy = false
    @State private var failedOnce = false
    @State private var cards: PracticeCollection?
    @State private var fresh: PracticeEarned?
    @State private var showCards = false
    @State private var question: String?

    private var done: Bool { evening ? state.eveningDone : state.morningDone }
    private var label: String {
        if busy { return "\u{2026}" }
        if failedOnce { return "Save failed \u{2014} try again" }
        return evening ? (done ? "Closed \u{2713}" : "Close the day") : (done ? "Logged \u{2713}" : "Log it")
    }

    var body: some View {
        PCard(title: evening ? "Evening \u{2014} gratitude" : "Morning \u{2014} what\u{2019}s persisting", id: evening ? "evening" : "morning") {
            if evening {
                PField(prompt: "What was real today?", text: $gratitude, lines: 3)
                PField(prompt: "Did today\u{2019}s story shift?", text: $shifted, lines: 3)
                if let q = question { Text("Sit with this: " + q).candleHint() }
            } else {
                PSelect(options: Self.moods.map { ($0, $0) }, value: $mood)
                PField(prompt: "What story is running right now?", text: $story, lines: 3)
            }
            HStack { Button(label) { Task { await save() } }.buttonStyle(CandleButton()).disabled(busy); Spacer(minLength: 0) }
            CandleResult(text: result)
            CoachNote(text: note)
            if evening, let cards, cards.count > 0 {
                Button("\(cards.count) cards earned \u{00b7} show") { fresh = nil; showCards = true }.buttonStyle(.plain).font(Font.pl(.footnote))
            }
        }
        .task(id: state.today?.date ?? "") {
            prefill()
            guard evening else { return }
            cards = await PracticeCards.load(model: model)
            // the evening Doctrine question (GET /api/evening-questions), a shuffled deck; the card stands without it
            if question == nil, let q = try? await Practice.get("evening-questions", PracticeItems<String>.self, model: model).items,
               let k = PracticeDeck.next(of: q.indices.map(String.init), deck: "practice.evening.deck"), let i = Int(k) { question = q[i] }
        }
        .sheet(isPresented: $showCards) { if let cards { EarnedCardSheet(model: model, fresh: fresh, collection: cards) } }
    }

    /// A completed check-in shows as completed, not as a blank form (S144's "did it even save").
    private func prefill() {
        guard let d = state.today else { return }
        if let m = d.mood, Self.moods.contains(m) { mood = m }
        if story.isEmpty { story = d.story ?? "" }
        if gratitude.isEmpty { gratitude = d.gratitude ?? "" }
        if shifted.isEmpty { shifted = d.story_shifted ?? "" }
    }

    private func save() async {
        busy = true; failedOnce = false; defer { busy = false }
        do {
            let sent = evening ? try await Practice.postQueued("checkin/evening", ["gratitude": gratitude, "storyShifted": shifted], model: model)
                               : try await Practice.postQueued("checkin/morning", ["mood": mood, "story": story], model: model)
            state.tick += 1
            guard sent else { result = PracticeWords.offlineSaved; return }
            result = nil
            await state.loadToday(model: model)
            if evening, let c = await PracticeCards.load(model: model) {
                cards = c
                if let top = c.cards.first, PracticeCards.isFresh(top) { fresh = top; showCards = true }
            }
            await PracticeNotice.reschedule(model: model)
            note = "\u{2026}"
            let body: [String: Any] = evening ? ["gratitude": gratitude, "shifted": shifted] : ["mood": mood, "story": story]
            struct Coach: Decodable { let note: String? }
            if let d = try? await Practice.post("coach", body, model: model), let c = try? JSONDecoder().decode(Coach.self, from: d) { note = c.note ?? "" } else { note = "" }
        } catch { failedOnce = true; result = error.localizedDescription }
    }
}

// MARK: - Which Truth? (the web's #truth-card, his ruling 11-15: the Academy's scenarios, one source, GET /api/truths)

struct PracticeTruth: Decodable { let scenario: String; let answer: Int; let why: String }
struct PracticeItems<T: Decodable>: Decodable { let items: [T] }

struct TruthCard: View {
    let model: AppModel
    @State private var all: [PracticeTruth] = []
    @State private var current: PracticeTruth?
    @State private var picked: Int?
    @State private var failed = false
    private static let names = ["1 \u{00b7} Prepared", "2 \u{00b7} In control", "3 \u{00b7} Persists"]

    var body: some View {
        PCard(title: "Which Truth?", id: "truth") {
            if let t = current {
                Text(t.scenario).font(Font.pl(size: 14)).foregroundStyle(Candle.ink).frame(maxWidth: .infinity, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { picks(t) }
                    VStack(alignment: .leading, spacing: 6) { picks(t) }
                }
                if let p = picked {
                    Text((p == t.answer ? "Yes. " : "The \(["", "First", "Second", "Third"][min(max(t.answer, 0), 3)]) Truth. ") + t.why).candleHint()
                    HStack { Button("Another") { deal() }.buttonStyle(CandleGhost()); Spacer(minLength: 0) }
                }
            } else {
                Text(failed ? "The scenarios are out of reach right now." : "Loading\u{2026}").candleHint()
            }
        }
        .task { await load() }
    }

    @ViewBuilder private func picks(_ t: PracticeTruth) -> some View {
        ForEach(1...3, id: \.self) { n in
            // after a pick the right one carries a check and a wrong pick a cross, so the answer is never colour alone
            let mark = picked == nil ? "" : (n == t.answer ? " \u{2713}" : (n == picked ? " \u{2717}" : ""))
            Button(Self.names[n - 1] + mark) { picked = n }
                .buttonStyle(CandleGhost()).disabled(picked != nil)
                .opacity(picked != nil && n != t.answer && n != picked ? 0.5 : 1)
        }
    }

    private func load() async {
        guard all.isEmpty else { return }
        if let l = try? await Practice.get("truths", PracticeItems<PracticeTruth>.self, model: model), !l.items.isEmpty { all = l.items; deal() } else { failed = true }
    }

    private func deal() {
        picked = nil
        guard let k = PracticeDeck.next(of: all.indices.map(String.init), deck: "practice.truth.deck"), let i = Int(k) else { return }
        current = all[i]
    }
}

// MARK: - Lesson (calendar-advanced, never gated)

struct LessonCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var answer = ""
    @State private var result: String?

    var body: some View {
        if let l = state.lesson {
            PCard(title: l.lesson.title, id: "lesson") {
                Text(l.lesson.lesson).font(Font.pl(size: 16)).foregroundStyle(Candle.ink).lineSpacing(5).textSelection(.enabled)
                PField(prompt: l.lesson.applicationPrompt, text: $answer, lines: 3)
                if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack { Button("Keep it as a note") { Task { await keep(l) } }.buttonStyle(CandleGhost()); Spacer(minLength: 0) }
                }
                CandleResult(text: result)
            }
        } else {
            PCard(title: "Lesson", id: "lesson") { Text(state.loaded ? PracticeWords.loadFailed("today\u{2019}s lesson") : "Loading today\u{2019}s lesson\u{2026}").candleHint() }
        }
    }

    private func keep(_ l: PracticeLesson) async {
        do {
            try await Practice.post("notes", ["text": "\(l.lesson.title)\n\(answer.trimmingCharacters(in: .whitespacesAndNewlines))"], model: model)
            answer = ""; result = "Kept in your notes."; state.reload += 1
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Reframe

struct ReframeCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var belief = ""
    @State private var reframe = ""
    @State private var suggesting = false
    @State private var busy = false
    @State private var result: String?
    @State private var saved: [PracticeReframe] = []
    @State private var failed = false

    var body: some View {
        PCard(title: "Reframe", hint: "name the limiting belief \u{2014} replace it with one that\u{2019}s true and useful", id: "reframe") {
            PField(prompt: "The belief that\u{2019}s in the way\u{2026}", text: $belief, lines: 2)
            HStack { Button(busy ? "\u{2026}" : "Reframe it") { Task { await make() } }.buttonStyle(CandleButton()).disabled(busy || belief.trimmingCharacters(in: .whitespaces).isEmpty); Spacer(minLength: 0) }
            if suggesting {
                PField(prompt: "Edit before saving", text: $reframe, lines: 2, serif: true)
                HStack { Button("Keep this one") { Task { await keep() } }.buttonStyle(CandleButton()).disabled(reframe.trimmingCharacters(in: .whitespaces).isEmpty); Spacer(minLength: 0) }
            }
            CandleResult(text: result)
            if failed && saved.isEmpty { Text(PracticeWords.loadFailed("your reframes")).candleHint() }
            VStack(spacing: 0) {
                ForEach(saved) { r in
                    CandleRule()
                    (Text(r.belief).font(Font.pl(size: 13)).strikethrough().foregroundStyle(Candle.ink.opacity(0.5))
                     + Text("  \u{2192}  ").foregroundStyle(Candle.gold)
                     + Text(r.reframe).font(Font.pl(size: 13, design: .serif).italic()).foregroundStyle(Candle.goldHi))
                        .lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        .contextMenu { Button("Copy the reframe", systemImage: "doc.on.doc") { UIPasteboard.general.string = r.reframe } }
                }
            }
        }
        .task(id: state.reload) { await load() }
    }

    private func load() async { if let l = try? await Practice.get("reframes", [PracticeReframe].self, model: model) { saved = l; failed = false } else { failed = true } }

    private func make() async {
        busy = true; defer { busy = false }
        struct R: Decodable { let reframe: String? }
        do {
            let d = try await Practice.post("reframe", ["belief": belief], model: model)
            let r = (try? JSONDecoder().decode(R.self, from: d))?.reframe ?? ""
            if r.isEmpty { result = "No reframe came back. Try again, or write your own." } else { reframe = r; suggesting = true; result = nil }
        } catch { result = error.localizedDescription }
    }

    private func keep() async {
        do {
            try await Practice.post("reframes", ["belief": belief, "reframe": reframe], model: model)
            belief = ""; reframe = ""; suggesting = false; result = nil; state.tick += 1; await load()
        } catch { result = error.localizedDescription }
    }
}
