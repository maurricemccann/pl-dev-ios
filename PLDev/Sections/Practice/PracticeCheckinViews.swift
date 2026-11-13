import SwiftUI

// The day's loop: the two check-ins, the lesson, the reframe, the talk with the coach. Same calls as the web app.

/// A chat bubble. His own words take his orange, the coach's sit on the system fill. Shared with GlyphBot.
struct PracticeBubble: View {
    let text: String
    let mine: Bool
    var caption: String?

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(text).plReading().textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? Wallpaper.line.opacity(0.22) : Color(uiColor: .secondarySystemFill),
                                in: RoundedRectangle(cornerRadius: PLRadius.row + 4, style: .continuous))
                if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
            }
            if !mine { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : "Coach"): \(text)")
    }
}

// MARK: - Morning and evening

struct CheckinView: View {
    let model: AppModel
    let evening: Bool
    private static let moods = ["calm", "hopeful", "doubtful", "anxious", "grounded"]
    @State private var mood = "calm"
    @State private var story = ""
    @State private var gratitude = ""
    @State private var shifted = ""
    @State private var note: String?
    @State private var result: String?
    @State private var busy = false
    @State private var saved = 0

    var body: some View {
        Form {
            if evening {
                Section("What was real today") {
                    TextField("Gratitude", text: $gratitude, axis: .vertical).lineLimit(2...6)
                }
                Section("Did today's story shift?") {
                    TextField("In your words", text: $shifted, axis: .vertical).lineLimit(2...6)
                }
            } else {
                Section("This morning") {
                    Picker("Mood", selection: $mood) { ForEach(Self.moods, id: \.self) { Text($0.capitalized).tag($0) } }
                }
                Section("The story running right now") {
                    TextField("What story is running?", text: $story, axis: .vertical).lineLimit(2...6)
                }
            }
            Section {
                Button { Task { await save() } } label: {
                    HStack { Text(evening ? "Close the day" : "Log it"); if busy { Spacer(); ProgressView() } }
                }
                .disabled(busy)
                ResultLine(text: result)
            }
            if let note {
                Section("The coach") { Text(note).plReading().textSelection(.enabled) }
            }
        }
        .navigationTitle(evening ? "Evening" : "Morning")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.success, trigger: saved)
        .task { await prefill() }
    }

    private func prefill() async {
        guard let day = try? await Practice.getOrNil("checkin/today", PracticeCheckin.self, model: model) else { return }
        if let m = day.mood, Self.moods.contains(m) { mood = m }
        story = day.story ?? story
        gratitude = day.gratitude ?? gratitude
        shifted = day.story_shifted ?? shifted
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            if evening {
                try await Practice.post("checkin/evening", ["gratitude": gratitude, "storyShifted": shifted], model: model)
            } else {
                try await Practice.post("checkin/morning", ["mood": mood, "story": story], model: model)
            }
            saved += 1; result = "Saved."
            await PracticeSection.state.loadToday(model: model)
            await PracticeNotice.reschedule(model: model)
            let body: [String: Any] = evening ? ["gratitude": gratitude, "shifted": shifted] : ["mood": mood, "story": story]
            struct Coach: Decodable { let note: String? }
            if let d = try? await Practice.post("coach", body, model: model), let c = try? JSONDecoder().decode(Coach.self, from: d), let n = c.note, !n.isEmpty { note = n }
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Lesson

struct LessonView: View {
    let model: AppModel
    @State private var answer = ""
    @State private var result: String?

    var body: some View {
        Loaded(load: { try await Practice.get("lesson", PracticeLesson.self, model: model) }) { l, _ in
            List {
                Section {
                    Text(l.lesson.lesson).plReading().textSelection(.enabled)
                } header: { Text("Day \(l.lesson.day + 1)") }
                Section {
                    Text(l.lesson.applicationPrompt).font(.callout).foregroundStyle(.secondary)
                    TextField("Your answer, any time, never blocking", text: $answer, axis: .vertical).lineLimit(2...8)
                    Button("Keep it as a note") { Task { await keep(l) } }
                        .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                    ResultLine(text: result)
                } header: { Text("Apply it") } footer: { Text("A kept answer goes to Notes, where nothing disappears.") }
            }
            .navigationTitle(l.lesson.title).navigationBarTitleDisplayMode(.inline)
        }
    }

    private func keep(_ l: PracticeLesson) async {
        do {
            try await Practice.post("notes", ["text": "\(l.lesson.title)\n\(answer.trimmingCharacters(in: .whitespacesAndNewlines))"], model: model)
            answer = ""; result = "Kept in Notes."
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Reframe

struct ReframeView: View {
    let model: AppModel
    @State private var belief = ""
    @State private var reframe = ""
    @State private var busy = false
    @State private var result: String?
    @State private var saved: [PracticeReframe] = []

    var body: some View {
        List {
            Section("The limiting belief") {
                TextField("What do you believe that holds you back?", text: $belief, axis: .vertical).lineLimit(2...6)
                Button { Task { await make() } } label: { HStack { Text("Reframe it"); if busy { Spacer(); ProgressView() } } }
                    .disabled(busy || belief.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !reframe.isEmpty || result != nil {
                Section {
                    TextField("The reframe", text: $reframe, axis: .vertical).lineLimit(2...6)
                    Button("Keep the pair") { Task { await keep() } }.disabled(reframe.trimmingCharacters(in: .whitespaces).isEmpty)
                    ResultLine(text: result)
                } header: { Text("The reframe") } footer: { Text("Edit it before you keep it. It should sound like you.") }
            }
            if !saved.isEmpty {
                Section("Kept") {
                    ForEach(saved) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.belief).font(.callout).foregroundStyle(.secondary)
                            Text(r.reframe).plReading()
                            Ago(text: r.created_at).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contextMenu { Button("Copy the reframe", systemImage: "doc.on.doc") { UIPasteboard.general.string = r.reframe } }
                    }
                }
            }
        }
        .navigationTitle("Reframe").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async { saved = (try? await Practice.get("reframes", [PracticeReframe].self, model: model)) ?? saved }

    private func make() async {
        busy = true; defer { busy = false }
        struct R: Decodable { let reframe: String? }
        do {
            let d = try await Practice.post("reframe", ["belief": belief], model: model)
            reframe = (try? JSONDecoder().decode(R.self, from: d))?.reframe ?? ""
            result = reframe.isEmpty ? "No reframe came back. Pull to try again, or write your own." : nil
        } catch { result = error.localizedDescription }
    }

    private func keep() async {
        do {
            try await Practice.post("reframes", ["belief": belief, "reframe": reframe], model: model)
            belief = ""; reframe = ""; result = "Kept."; await load()
        } catch { result = error.localizedDescription }
    }
}

// MARK: - Talk it through (the ongoing thread)

struct CoachView: View {
    let model: AppModel
    @State private var thread: [PracticeMessage] = []
    @State private var text = ""
    @State private var sending = false
    @State private var failure: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if thread.isEmpty && failure == nil { ContentUnavailableView("Nothing said yet", systemImage: "bubble.left.and.bubble.right", description: Text("Say what is on your mind. The thread stays, so it reads as one conversation.")) }
                    ForEach(thread) { m in PracticeBubble(text: m.text, mine: m.role != "assistant", caption: nil).id(m.id) }
                    if sending { ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).id("typing") }
                    if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap)
            }
            .onChange(of: thread.count) { _, _ in withAnimation { proxy.scrollTo(thread.last?.id, anchor: .bottom) } }
            .onChange(of: sending) { _, now in if now { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Say it", text: $text, axis: .vertical).lineLimit(1...5)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
            }
            .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap).background(.bar)
        }
        .navigationTitle("Talk it through").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.select, trigger: thread.count)
        .task { await load() }
    }

    private func load() async {
        do { thread = try await Practice.get("messages", [PracticeMessage].self, model: model); failure = nil }
        catch { failure = "Could not load the thread. \(plainSentence(error))" }
    }

    private func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""; sending = true; defer { sending = false }
        thread.append(PracticeMessage(id: "local-\(UUID().uuidString)", role: "user", text: t, created_at: nil))
        do { try await Practice.post("conversation", ["text": t], model: model); await load() }
        catch { failure = error.localizedDescription; text = t; thread.removeLast() }
    }
}
