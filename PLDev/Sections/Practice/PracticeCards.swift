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
                    .background(mine ? Candle.gold : Candle.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { if !mine { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) } }
                if let caption { Text(caption).font(.caption2).foregroundStyle(Candle.ink.opacity(0.5)) }
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
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 38, weight: .light)).foregroundStyle(Candle.goldHi).monospacedDigit().contentTransition(.numericText())
            Text("\(n == 1 ? "day" : "days") practised this month \u{00B7} \(state.streak?.practisedTotal ?? 0) in all")
                .font(.system(size: 12.8)).foregroundStyle(Candle.ink.opacity(0.6))
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
                        Text(n.text).font(.system(size: 13.6)).foregroundStyle(Candle.ink).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Candle.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
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
            VStack(spacing: 0) {
                ForEach(logs) { l in
                    CandleRule()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        KindPill(kind: l.kind)
                        Text(l.text).font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading)
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
    private static let moods = ["calm", "hopeful", "doubtful", "anxious", "grounded"]
    @State private var mood = "calm"
    @State private var story = ""
    @State private var gratitude = ""
    @State private var shifted = ""
    @State private var note = ""
    @State private var result: String?
    @State private var busy = false
    @State private var failedOnce = false

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
            } else {
                PSelect(options: Self.moods.map { ($0, $0) }, value: $mood)
                PField(prompt: "What story is running right now?", text: $story, lines: 3)
            }
            HStack { Button(label) { Task { await save() } }.buttonStyle(CandleButton()).disabled(busy); Spacer(minLength: 0) }
            CandleResult(text: result)
            CoachNote(text: note)
        }
        .task(id: state.today?.date ?? "") { prefill() }
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
            await PracticeNotice.reschedule(model: model)
            note = "\u{2026}"
            let body: [String: Any] = evening ? ["gratitude": gratitude, "shifted": shifted] : ["mood": mood, "story": story]
            struct Coach: Decodable { let note: String? }
            if let d = try? await Practice.post("coach", body, model: model), let c = try? JSONDecoder().decode(Coach.self, from: d) { note = c.note ?? "" } else { note = "" }
        } catch { failedOnce = true; result = error.localizedDescription }
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
                Text(l.lesson.lesson).font(.system(size: 16)).foregroundStyle(Candle.ink).lineSpacing(5).textSelection(.enabled)
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
                    (Text(r.belief).font(.system(size: 13)).strikethrough().foregroundStyle(Candle.ink.opacity(0.5))
                     + Text("  \u{2192}  ").foregroundStyle(Candle.gold)
                     + Text(r.reframe).font(.system(size: 13, design: .serif).italic()).foregroundStyle(Candle.goldHi))
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
