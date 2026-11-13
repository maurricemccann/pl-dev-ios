import SwiftUI
import TipKit

// Conversation, the Desire List (with each desire's flow and WOOP) and the Habits stack: the middle of the web's Today page.

// MARK: - Conversation: one ongoing thread

struct ConversationCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var thread: [PracticeMessage] = []
    @State private var text = ""
    @State private var sending = false
    @State private var failure: String?

    var body: some View {
        PCard(title: "Conversation", id: "conversation") {
            if !thread.isEmpty || sending {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(thread) { m in PracticeBubble(text: m.text, mine: m.role != "assistant").id(m.id) }
                            if sending { HStack { ProgressView().tint(Candle.gold); Spacer() }.id("typing") }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 240)
                    .onChange(of: thread.count) { _, _ in withAnimation { proxy.scrollTo(thread.last?.id, anchor: .bottom) } }
                    .onChange(of: sending) { _, now in if now { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
                    .task(id: thread.count) { proxy.scrollTo(thread.last?.id, anchor: .bottom) }
                }
            }
            PField(prompt: "Talk to it\u{2026}", text: $text, lines: 2)
            HStack { Button(sending ? "\u{2026}" : "Send") { Task { await send() } }.buttonStyle(CandleButton()).disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Spacer(minLength: 0) }
            CandleResult(text: failure)
        }
        .task(id: state.reload) { await load() }
    }

    private func load() async {
        do { thread = try await Practice.get("messages", [PracticeMessage].self, model: model); failure = nil }
        catch { failure = PracticeWords.loadFailed("the thread") }
    }

    private func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""; sending = true; failure = nil; defer { sending = false }
        thread.append(PracticeMessage(id: "local-\(UUID().uuidString)", role: "user", text: t, created_at: nil))
        do { try await Practice.post("conversation", ["text": t], model: model); await load(); state.tick += 1 }
        catch { failure = error.localizedDescription; text = t; thread.removeLast() }
    }
}

// MARK: - Desire List: priority, a check to complete, "map it" for the flow and the WOOP

struct DesireListCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var desires: [PracticeDesire] = []
    @State private var text = ""
    @State private var priority = "medium"
    @State private var result: String?
    @State private var failed = false
    @State private var mapped: String?

    var body: some View {
        PCard(title: "Desire List", id: "desires") {
            PField(prompt: "Write the desired outcome as if it\u{2019}s already true.", text: $text, lines: 3)
            PSelect(options: [("high", "high"), ("medium", "medium"), ("low", "low")], value: $priority, fill: false)
            HStack { Button("Save entry") { Task { await add() } }.buttonStyle(CandleButton()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Spacer(minLength: 0) }
            CandleResult(text: result)
            if failed && desires.isEmpty { Text(PracticeWords.loadFailed("the desires")).candleHint() }
            VStack(spacing: 0) {
                ForEach(desires) { d in
                    CandleRule()
                    item(d)
                }
            }
        }
        .task(id: state.reload) { await load() }
    }

    private func item(_ d: PracticeDesire) -> some View {
        let done = d.completed_at != nil
        let edge: Color = d.priority == "high" ? Candle.goldHi : d.priority == "low" ? Candle.pillLine : .clear
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { Task { await toggle(d) } } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square").font(.system(size: 20)).foregroundStyle(Candle.gold)
                        .frame(width: 36, height: 36).contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain).accessibilityLabel(done ? "Reopen" : "Mark done")
                Text("\(d.date ?? "") \u{00B7} \(d.text)").font(.system(size: 13.6)).strikethrough(done).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                Button(mapped == d.id ? "close" : "map it") { withAnimation(.snappy) { mapped = mapped == d.id ? nil : d.id } }
                    .buttonStyle(CandleGhost()).font(.system(size: 12))
            }
            if mapped == d.id { DesireMap(model: model, desire: d).padding(.leading, 24) }
        }
        .padding(.leading, 8).padding(.vertical, 4)
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 2) }
        .opacity(done ? 0.5 : 0.85)
        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = d.text } }
    }

    private func load() async {
        do { desires = try await Practice.get("scripts", [PracticeDesire].self, model: model); failed = false }
        catch { failed = true }
    }

    private func add() async {
        do {
            try await Practice.post("scripts", ["text": text.trimmingCharacters(in: .whitespacesAndNewlines), "priority": priority], model: model)
            text = ""; result = nil; state.desiresRev += 1; state.tick += 1; await load()
        } catch { result = error.localizedDescription }
    }

    private func toggle(_ d: PracticeDesire) async {
        guard let i = desires.firstIndex(where: { $0.id == d.id }) else { return }
        let before = desires[i]
        desires[i].completed_at = before.completed_at == nil ? ISO8601DateFormatter().string(from: .now) : nil
        do { try await Practice.post("scripts/\(d.id)/toggle", model: model); state.desiresRev += 1; state.tick += 1; await load() }
        catch { if let j = desires.firstIndex(where: { $0.id == d.id }) { desires[j] = before }; result = error.localizedDescription }
    }
}

/// `.diagram-panel`: the flow (trigger, I will, then, which leads to) and the WOOP (outcome, obstacle, if, then).
struct DesireMap: View {
    let model: AppModel
    let desire: PracticeDesire
    @State private var trigger = ""
    @State private var b1 = ""
    @State private var b2 = ""
    @State private var outcomeFlow = ""
    @State private var outcome = ""
    @State private var obstacle = ""
    @State private var ifText = ""
    @State private var thenText = ""
    @State private var savedFlow: [String] = []
    @State private var savedPlan: String?
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PField(prompt: "Trigger \u{2014} when this happens\u{2026}", text: $trigger, small: true)
            PField(prompt: "I will\u{2026}", text: $b1, small: true)
            PField(prompt: "Then\u{2026}", text: $b2, small: true)
            PField(prompt: "Which leads to\u{2026}", text: $outcomeFlow, small: true)
            HStack { Button("save flow") { Task { await saveFlow() } }.buttonStyle(CandleGhost()).font(.system(size: 12)); Spacer(minLength: 0) }
            if !savedFlow.isEmpty {
                WrapLayout(spacing: 4) {
                    ForEach(Array(savedFlow.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 4) {
                            if i > 0 { Text("\u{2192}").foregroundStyle(Candle.gold) }
                            Text(s).font(.system(size: 12.5)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Candle.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("WOOP \u{2014} contrast it, then plan it").font(.system(size: 10.9)).textCase(.uppercase).tracking(1.1).foregroundStyle(Candle.goldHi.opacity(0.7))
                PField(prompt: "Outcome \u{2014} the best real result of this\u{2026}", text: $outcome, small: true)
                PField(prompt: "Obstacle \u{2014} the inner thing most likely to stop me\u{2026}", text: $obstacle, small: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { PField(prompt: "If (the obstacle shows up as\u{2026})", text: $ifText, small: true); PField(prompt: "then I will\u{2026}", text: $thenText, small: true) }
                    VStack(spacing: 6) { PField(prompt: "If (the obstacle shows up as\u{2026})", text: $ifText, small: true); PField(prompt: "then I will\u{2026}", text: $thenText, small: true) }
                }
                HStack { Button("save WOOP") { Task { await saveWoop() } }.buttonStyle(CandleGhost()).font(.system(size: 12)); Spacer(minLength: 0) }
                if let savedPlan { Text(savedPlan).font(.system(size: 12.8, design: .serif).italic()).foregroundStyle(Candle.goldHi) }
            }
            .padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(Candle.fieldLine).frame(height: 1) }
            CandleResult(text: result)
        }
        .task { await load() }
    }

    private func flow() -> [String] { [trigger, b1, b2, outcomeFlow].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private func plan() -> String? { ifText.isEmpty || thenText.isEmpty ? nil : "If \(ifText) \u{2192} then \(thenText)" }

    private func load() async {
        if let d = try? await Practice.getOrNil("diagrams/\(desire.id)", PracticeDiagram.self, model: model) {
            trigger = d.trigger_text ?? ""; b1 = d.behavior1 ?? ""; b2 = d.behavior2 ?? ""; outcomeFlow = d.outcome ?? ""; savedFlow = flow()
        }
        if let w = try? await Practice.getOrNil("woop/\(desire.id)", PracticeWoop.self, model: model) {
            outcome = w.outcome ?? ""; obstacle = w.obstacle ?? ""; ifText = w.if_text ?? ""; thenText = w.then_text ?? ""; savedPlan = plan()
        }
    }

    private func saveFlow() async {
        do { try await Practice.post("diagrams/\(desire.id)", ["trigger": trigger, "behavior1": b1, "behavior2": b2, "outcome": outcomeFlow], model: model); savedFlow = flow(); result = "Flow saved." }
        catch { result = error.localizedDescription }
    }

    private func saveWoop() async {
        do { try await Practice.post("woop/\(desire.id)", ["outcome": outcome, "obstacle": obstacle, "if_text": ifText, "then_text": thenText], model: model); savedPlan = plan(); result = "WOOP saved." }
        catch { result = error.localizedDescription }
    }
}

// MARK: - Habits: the tiny stack (cue, response, reward), ticked the day it happens

struct HabitsCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var adding = false
    @State private var cue = ""
    @State private var response = ""
    @State private var reward = ""
    @State private var result: String?
    @State private var archive: PracticeHabit?

    var body: some View {
        PCard(title: "Habits \u{2014} the tiny stack", hint: "cue \u{2192} response \u{2192} reward \u{00B7} tick it the day it happens", id: "habits") {
            if !state.habits.isEmpty { TipView(HabitSwipeTip()) }
            if state.habits.isEmpty { QuietLine(text: state.loaded ? "No habits yet \u{2014} start with one tiny one." : "\u{2026}") }
            VStack(spacing: 0) {
                ForEach(Array(state.habits.enumerated()), id: \.element.id) { i, h in
                    if i > 0 { CandleRule() }
                    row(h)
                }
            }
            PDetails(summary: "+ new habit", open: $adding) {
                PField(prompt: "Cue \u{2014} after I\u{2026}", text: $cue, small: true)
                PField(prompt: "Response \u{2014} I will\u{2026} (the tiny version)", text: $response, small: true)
                PField(prompt: "Reward \u{2014} then I get\u{2026}", text: $reward, small: true)
                HStack { Button("Add it") { Task { await add() } }.buttonStyle(CandleButton()).disabled(response.trimmingCharacters(in: .whitespaces).isEmpty); Spacer(minLength: 0) }
            }
            CandleResult(text: result)
        }
        .confirmationDialog("Archive this habit?", isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } }), titleVisibility: .visible, presenting: archive) { h in
            Button("Archive \u{201C}\(h.response)\u{201D}", role: .destructive) { Task { await doArchive(h) } }
        } message: { _ in Text("It leaves the list. Its ticks stay on the record.") }
    }

    private func row(_ h: PracticeHabit) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { Task { await state.tickHabit(h, model: model); if let m = state.message { result = m; state.message = nil } } } label: {
                Image(systemName: h.tickedToday ? "checkmark.square.fill" : "square").font(.system(size: 20)).foregroundStyle(Candle.gold)
                    .frame(width: 36, height: 36).contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: h.tickedToday)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(h.response), \(h.tickedToday ? "done today, tap to undo" : "not done today, tap to tick")")
            VStack(alignment: .leading, spacing: 4) {
                (Text(h.cue.flatMap { $0.isEmpty ? nil : "\($0) \u{2192} " } ?? "").foregroundStyle(Candle.ink.opacity(0.55))
                 + Text(h.response)
                 + Text(h.reward.flatMap { $0.isEmpty ? nil : " \u{2192} \($0)" } ?? "").foregroundStyle(Candle.ink.opacity(0.55)))
                    .font(.system(size: 13.6))
                WeekDots(week: h.week)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
        }
        .padding(.vertical, 4)
        .contextMenu { Button("Archive", systemImage: "archivebox", role: .destructive) { archive = h } }
    }

    private func add() async {
        do {
            try await Practice.post("habits", ["cue": cue, "response": response.trimmingCharacters(in: .whitespaces), "reward": reward], model: model)
            cue = ""; response = ""; reward = ""; adding = false; result = nil; await state.loadToday(model: model)
        } catch { result = error.localizedDescription }
    }

    private func doArchive(_ h: PracticeHabit) async {
        do { try await Practice.post("habits/\(h.id)", model: model, method: "DELETE"); result = "Archived."; await state.loadToday(model: model) }
        catch { result = error.localizedDescription }
    }
}
