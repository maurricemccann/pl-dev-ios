import SwiftUI

// The Trends screen, as the web draws it: Weekly review, Rehearsals, Story history.

struct TrendsScreen: View {
    let model: AppModel
    @Bindable var state: PracticeModel
    var body: some View {
        VStack(spacing: 16) {
            ReviewCard(model: model, state: state)
            RehearsalsCard(model: model, state: state)
            StoryHistoryCard(model: model, state: state)
            VisionPreviewCard(state: state)
        }
    }
}

// MARK: - Weekly review: due when no review was sealed in the last seven days

struct ReviewCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var reviews: [PracticeReview] = []
    @State private var worked = ""
    @State private var adjust = ""
    @State private var celebrate = ""
    @State private var summary = ""
    @State private var reading = false
    @State private var result: String?
    @State private var sealed = 0

    private var latest: PracticeReview? { reviews.first }
    private var due: Bool {
        guard let l = latest, let d = Date.pl(l.date) else { return true }
        return Date().timeIntervalSince(d) > 7 * 86400
    }

    var body: some View {
        PCard(title: "Weekly review", id: "review") {
            if due {
                Text("seven days on the record \u{2014} close the loop").font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5))
                PField(prompt: "What worked this week?", text: $worked, lines: 2)
                PField(prompt: "What gets adjusted?", text: $adjust, lines: 2)
                PField(prompt: "What gets celebrated \u{2014} effort counts.", text: $celebrate, lines: 2)
                HStack(spacing: 6) {
                    Button(reading ? "\u{2026}" : "Read my week") { Task { await read() } }.buttonStyle(CandleGhost()).disabled(reading)
                    Spacer(minLength: 0)
                }
                CoachNote(text: summary)
                HStack { Button("Seal the week") { Task { await seal() } }.buttonStyle(CandleButton()); Spacer(minLength: 0) }
                CandleResult(text: result)
            }
            if let l = latest {
                VStack(alignment: .leading, spacing: 0) {
                    Text("last sealed \(l.date)").font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5)).padding(.bottom, 4)
                    if let s = l.ai_summary, !s.isEmpty { CoachNote(text: s) }
                    line("worked", l.worked); line("adjust", l.adjust); line("celebrate", l.celebrate)
                }
            }
        }
        .sensoryFeedback(PLHaptic.success, trigger: sealed)
        .task(id: state.reload) { await load() }
    }

    private func line(_ k: String, _ v: String?) -> some View {
        VStack(spacing: 0) {
            CandleRule()
            (Text("\(k):").foregroundStyle(Candle.goldHi).fontWeight(.medium) + Text(" \(v.flatMap { $0.isEmpty ? nil : $0 } ?? "\u{2014}")"))
                .font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
        .padding(.top, 6)
    }

    private func load() async { if let l = try? await Practice.get("reviews", [PracticeReview].self, model: model) { reviews = l } }

    private func read() async {
        reading = true; defer { reading = false }
        struct S: Decodable { let summary: String? }
        do {
            let d = try await Practice.post("review-summary", model: model)
            let s = (try? JSONDecoder().decode(S.self, from: d))?.summary ?? ""
            summary = s.isEmpty ? "The record is thin this week \u{2014} the read comes from what\u{2019}s logged." : s
        } catch { result = error.localizedDescription }
    }

    private func seal() async {
        do {
            try await Practice.post("reviews", ["worked": worked, "adjust": adjust, "celebrate": celebrate, "ai_summary": summary], model: model)
            sealed += 1; worked = ""; adjust = ""; celebrate = ""; summary = ""; result = nil
            await load(); await state.loadToday(model: model)
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Rehearsals this week

struct RehearsalsCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var sessions: [PracticeSessionRow] = []
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        let week = sessions.filter { s in Date.pl(s.created_at).map { Date().timeIntervalSince($0) < 7 * 86400 } ?? false }
        PCard(title: "Rehearsals", id: "rehearsals") {
            if week.isEmpty {
                QuietLine(text: failed ? PracticeWords.loadFailed("the rehearsals") : loaded ? "No rehearsals yet." : "\u{2026}")
            } else {
                let avg = Double(week.map(\.intensity).reduce(0, +)) / Double(week.count)
                (Text("\(week.count)").fontWeight(.semibold) + Text(" rehearsal\(week.count == 1 ? "" : "s") this week \u{00B7} avg intensity ") + Text(String(format: "%.1f", avg)).fontWeight(.semibold) + Text("/5"))
                    .font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.85))
                VStack(spacing: 0) {
                    ForEach(week.prefix(5)) { s in
                        CandleRule()
                        Text("\(s.date ?? "") \u{00B7} \(s.intensity)/5 \u{00B7} \(String((s.desire_text ?? "").prefix(60)))")
                            .font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                }
            }
        }
        .task(id: state.reload) {
            if let s = try? await Practice.get("sessions", [PracticeSessionRow].self, model: model) { sessions = s; failed = false } else { failed = true }
            loaded = true
        }
    }
}

// MARK: - Story history

struct StoryHistoryCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var trends: [PracticeTrend] = []
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        PCard(title: "Story history", id: "story") {
            if trends.isEmpty { QuietLine(text: failed ? PracticeWords.loadFailed("the record") : loaded ? "Nothing logged yet." : "\u{2026}") }
            VStack(spacing: 0) {
                ForEach(trends) { t in
                    CandleRule()
                    (Text(t.date).fontWeight(.semibold).foregroundStyle(Candle.goldHi)
                     + Text(" \u{2014} \(t.story.flatMap { $0.isEmpty ? nil : $0 } ?? "(no morning entry)")")
                     + Text(t.story_shifted.flatMap { $0.isEmpty ? nil : " \u{2192} shifted: \($0)" } ?? ""))
                        .font(.system(size: 13.6)).foregroundStyle(Candle.ink.opacity(0.85)).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).textSelection(.enabled)
                }
            }
        }
        .task(id: state.reload) {
            if let t = try? await Practice.get("trends", [PracticeTrend].self, model: model) { trends = t; failed = false } else { failed = true }
            loaded = true
        }
    }
}
