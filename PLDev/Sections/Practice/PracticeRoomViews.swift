import PhotosUI
import SwiftUI

// Desires with their WOOP and flow, habits, notes, wins, the weekly review and the record.

// MARK: - Desires

struct DesiresView: View {
    let model: AppModel
    @State private var desires: [PracticeDesire] = []
    @State private var text = ""
    @State private var priority = "medium"
    @State private var result: String?
    @State private var loaded = false
    @State private var failure: String?

    private var open: [PracticeDesire] { desires.filter { $0.completed_at == nil } }
    private var done: [PracticeDesire] { desires.filter { $0.completed_at != nil } }

    var body: some View {
        List {
            Section {
                TextField("A desire, written as already true", text: $text, axis: .vertical).lineLimit(1...5)
                Picker("Urgency", selection: $priority) { Text("High").tag("high"); Text("Medium").tag("medium"); Text("Low").tag("low") }
                Button("Add it") { Task { await add() } }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                ResultLine(text: result)
            }
            if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            if loaded && failure == nil && desires.isEmpty { ContentUnavailableView("No desires yet", systemImage: "sparkles", description: Text("Write what you are preparing for. It shows here, open first.")) }
            if !open.isEmpty {
                Section { ForEach(open) { row($0) } } header: { Text("Open · \(open.count)") } footer: { Text("Swipe left to mark one done. Touch and hold for more.") }
            }
            if !done.isEmpty { Section("Done · \(done.count)") { ForEach(done) { row($0) } } }
        }
        .navigationTitle("Desires").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.commit, trigger: desires.count)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ d: PracticeDesire) -> some View {
        NavigationLink { DesireDetail(model: model, desire: d) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: d.completed_at == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(d.completed_at == nil ? Color.secondary : Color.green).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.text).strikethrough(d.completed_at != nil).lineLimit(4)
                    Text([d.priority?.capitalized, d.date].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) { Button(d.completed_at == nil ? "Done" : "Reopen") { Task { await toggle(d) } }.tint(d.completed_at == nil ? .green : .gray) }
        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = d.text } }
    }

    private func load() async {
        do { desires = try await Practice.get("scripts", [PracticeDesire].self, model: model); failure = nil }
        catch { failure = "Could not load the desires. Pull to try again." }
        loaded = true
    }

    private func add() async {
        do { try await Practice.post("scripts", ["text": text.trimmingCharacters(in: .whitespacesAndNewlines), "priority": priority], model: model)
            text = ""; result = "Added."; await load() } catch { result = error.localizedDescription }
    }

    private func toggle(_ d: PracticeDesire) async {
        guard let i = desires.firstIndex(where: { $0.id == d.id }) else { return }
        let before = desires[i]
        desires[i].completed_at = before.completed_at == nil ? ISO8601DateFormatter().string(from: .now) : nil
        do { try await Practice.post("scripts/\(d.id)/toggle", model: model); await load() }
        catch { if let j = desires.firstIndex(where: { $0.id == d.id }) { desires[j] = before }; result = error.localizedDescription }
    }
}

/// One desire: its WOOP (wish, outcome, obstacle, plan) and its flow (trigger, two behaviours, outcome).
struct DesireDetail: View {
    let model: AppModel
    let desire: PracticeDesire
    @State private var outcome = ""
    @State private var obstacle = ""
    @State private var ifText = ""
    @State private var thenText = ""
    @State private var trigger = ""
    @State private var b1 = ""
    @State private var b2 = ""
    @State private var flowOutcome = ""
    @State private var result: String?
    @State private var saved = 0

    var body: some View {
        Form {
            Section("The wish") { Text(desire.text).plReading().textSelection(.enabled) }
            Section {
                TextField("Outcome: the best result", text: $outcome, axis: .vertical)
                TextField("Obstacle: what in you stands in the way", text: $obstacle, axis: .vertical)
                TextField("If (the obstacle shows up)", text: $ifText, axis: .vertical)
                TextField("Then I will", text: $thenText, axis: .vertical)
                Button("Save the plan") { Task { await saveWoop() } }
            } header: { Text("WOOP") } footer: { Text("Mental contrasting with an if-then plan: the bridge from the wish to a day's action.") }
            Section {
                TextField("Trigger", text: $trigger, axis: .vertical)
                TextField("Behaviour one", text: $b1, axis: .vertical)
                TextField("Behaviour two", text: $b2, axis: .vertical)
                TextField("Outcome", text: $flowOutcome, axis: .vertical)
                Button("Save the flow") { Task { await saveFlow() } }
            } header: { Text("The flow") }
            Section { ResultLine(text: result) }
        }
        .navigationTitle("Desire").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.success, trigger: saved)
        .task { await load() }
    }

    private func load() async {
        if let w = try? await Practice.getOrNil("woop/\(desire.id)", PracticeWoop.self, model: model) {
            outcome = w.outcome ?? ""; obstacle = w.obstacle ?? ""; ifText = w.if_text ?? ""; thenText = w.then_text ?? ""
        }
        if let d = try? await Practice.getOrNil("diagrams/\(desire.id)", PracticeDiagram.self, model: model) {
            trigger = d.trigger_text ?? ""; b1 = d.behavior1 ?? ""; b2 = d.behavior2 ?? ""; flowOutcome = d.outcome ?? ""
        }
    }

    private func saveWoop() async {
        do { try await Practice.post("woop/\(desire.id)", ["outcome": outcome, "obstacle": obstacle, "if_text": ifText, "then_text": thenText], model: model); result = "Plan saved."; saved += 1 }
        catch { result = error.localizedDescription }
    }

    private func saveFlow() async {
        do { try await Practice.post("diagrams/\(desire.id)", ["trigger": trigger, "behavior1": b1, "behavior2": b2, "outcome": flowOutcome], model: model); result = "Flow saved."; saved += 1 }
        catch { result = error.localizedDescription }
    }
}

// MARK: - Habits

struct HabitsView: View {
    let model: AppModel
    @State private var habits: [PracticeHabit] = []
    @State private var cue = ""
    @State private var response = ""
    @State private var reward = ""
    @State private var result: String?
    @State private var archive: PracticeHabit?
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                TextField("After… (the cue)", text: $cue)
                TextField("I will… (one tiny action)", text: $response)
                TextField("Then… (the reward)", text: $reward)
                Button("Add the habit") { Task { await add() } }.disabled(response.trimmingCharacters(in: .whitespaces).isEmpty)
                ResultLine(text: result)
            } header: { Text("A tiny habit") } footer: { Text("Cue, action, reward. One tick a day.") }
            if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            if loaded && failure == nil && habits.isEmpty { ContentUnavailableView("No habits yet", systemImage: "checklist", description: Text("Add one above. Its week of dots fills as you tick it.")) }
            if !habits.isEmpty {
                Section {
                    ForEach(habits) { h in
                        HabitRow(habit: h)
                            .swipeActions(edge: .trailing) {
                                Button(h.tickedToday ? "Undo" : "Done") { Task { await tick(h) } }.tint(h.tickedToday ? .gray : .green)
                            }
                            .swipeActions(edge: .leading) { Button("Archive") { archive = h }.tint(PLTone.accent) }
                    }
                } header: { Text("This week") } footer: { Text("Swipe left to tick, right to archive.") }
            }
        }
        .navigationTitle("Habits").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Archive this habit?", isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } }), titleVisibility: .visible, presenting: archive) { h in
            Button("Archive \"\(h.response)\"", role: .destructive) { Task { await doArchive(h) } }
        } message: { _ in Text("It leaves the list. Its ticks stay on the record.") }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { let l = try await Practice.get("habits", [PracticeHabit].self, model: model); habits = l; PracticeSection.state.habits = l; PracticeSection.state.publish(); failure = nil }
        catch { failure = "Could not load the habits. Pull to try again." }
        loaded = true
    }

    private func tick(_ h: PracticeHabit) async {
        await PracticeSection.state.tickHabit(h, model: model)
        habits = PracticeSection.state.habits
        if let m = PracticeSection.state.message { result = m; PracticeSection.state.message = nil }
    }

    private func add() async {
        do { try await Practice.post("habits", ["cue": cue, "response": response.trimmingCharacters(in: .whitespaces), "reward": reward], model: model)
            cue = ""; response = ""; reward = ""; result = "Added."; await load() } catch { result = error.localizedDescription }
    }

    private func doArchive(_ h: PracticeHabit) async {
        do { try await Practice.post("habits/\(h.id)", model: model, method: "DELETE"); result = "Archived."; await load() } catch { result = error.localizedDescription }
    }
}

// MARK: - Notes (they stack, they never disappear)

struct NotesView: View {
    let model: AppModel
    @State private var notes: [PracticeNote] = []
    @State private var text = ""
    @State private var result: String?
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                TextField("A thought, kept", text: $text, axis: .vertical).lineLimit(1...6)
                Button("Keep it") { Task { await add() } }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                ResultLine(text: result)
            }
            if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            if loaded && failure == nil && notes.isEmpty { ContentUnavailableView("No notes yet", systemImage: "note.text", description: Text("Each note you keep stacks here, newest first.")) }
            Section {
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 3) { Text(n.text).plReading(); Ago(text: n.created_at).font(.caption2).foregroundStyle(.tertiary) }
                        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = n.text } }
                }
            }
        }
        .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.success, trigger: notes.count)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { notes = try await Practice.get("notes", [PracticeNote].self, model: model); failure = nil }
        catch { failure = "Could not load the notes. Pull to try again." }
        loaded = true
    }

    private func add() async {
        do {
            let sent = try await Practice.postQueued("notes", ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)], model: model)
            text = ""; result = sent ? "Kept." : "Saved on this iPhone. It sends when you are online."; if sent { await load() }
        }
        catch { result = error.localizedDescription }
    }
}

// MARK: - Wins and noticed

struct WinsView: View {
    let model: AppModel
    @State private var kind = "win"
    @State private var logs: [PracticeLog] = []
    @State private var text = ""
    @State private var result: String?
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Picker("Kind", selection: $kind) { Text("Wins").tag("win"); Text("Noticed").tag("noticed") }.pickerStyle(.segmented)
                TextField(kind == "win" ? "A win, small counts" : "An opportunity you noticed", text: $text, axis: .vertical).lineLimit(1...5)
                Button("Log it") { Task { await add() } }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                ResultLine(text: result)
            } footer: { Text(kind == "win" ? "Wins are proof of mastery." : "Noticed is what you now see because you hold it in mind.") }
            let shown = logs.filter { $0.kind == kind }
            if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            if loaded && failure == nil && shown.isEmpty { ContentUnavailableView(kind == "win" ? "No wins yet" : "Nothing noticed yet", systemImage: kind == "win" ? "trophy" : "eye", description: Text("What you log here is listed, newest first.")) }
            Section {
                ForEach(shown) { l in
                    VStack(alignment: .leading, spacing: 3) { Text(l.text); Ago(text: l.created_at).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
        .navigationTitle("Wins and noticed").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.success, trigger: logs.count)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { logs = try await Practice.get("logs", [PracticeLog].self, model: model); failure = nil }
        catch { failure = "Could not load the log. Pull to try again." }
        loaded = true
    }

    private func add() async {
        do {
            let sent = try await Practice.postQueued("logs", ["kind": kind, "text": text.trimmingCharacters(in: .whitespacesAndNewlines)], model: model)
            text = ""; result = sent ? "Logged." : "Saved on this iPhone. It sends when you are online."; if sent { await load() }
        }
        catch { result = error.localizedDescription }
    }
}

// MARK: - Weekly review

struct ReviewView: View {
    let model: AppModel
    @State private var reviews: [PracticeReview] = []
    @State private var reviewsFailed = false
    @State private var worked = ""
    @State private var adjust = ""
    @State private var celebrate = ""
    @State private var summary = ""
    @State private var reading = false
    @State private var result: String?
    @State private var sealed = 0

    var body: some View {
        List {
            Section {
                TextField("What worked this week?", text: $worked, axis: .vertical).lineLimit(2...5)
                TextField("What gets adjusted?", text: $adjust, axis: .vertical).lineLimit(2...5)
                TextField("What gets celebrated? Effort counts.", text: $celebrate, axis: .vertical).lineLimit(2...5)
            } header: { Text("This week") }
            Section {
                Button { Task { await read() } } label: { HStack { Text("Read my week"); if reading { Spacer(); ProgressView() } } }.disabled(reading)
                if !summary.isEmpty { Text(summary).plReading().textSelection(.enabled) }
            } footer: { Text("The read comes from what is actually on the record this week.") }
            Section {
                Button("Seal the week") { Task { await seal() } }
                ResultLine(text: result)
            }
            if reviewsFailed && reviews.isEmpty { Text("Your past reviews did not load. Pull to try again.").foregroundStyle(.secondary) }
            if !reviews.isEmpty {
                Section("Sealed") {
                    ForEach(reviews.filter(\.hasText)) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.date).font(.caption.bold())
                            if let c = r.celebrate, !c.isEmpty { Text("Celebrated: \(c)").font(.callout) }
                            if let w = r.worked, !w.isEmpty { Text("Worked: \(w)").font(.callout) }
                            if let a = r.adjust, !a.isEmpty { Text("Adjusted: \(a)").font(.callout) }
                            if let s = r.ai_summary, !s.isEmpty { Text(s).font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Weekly review").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.success, trigger: sealed)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async { if let l = try? await Practice.get("reviews", [PracticeReview].self, model: model) { reviews = l; reviewsFailed = false } else { reviewsFailed = true } }

    private func read() async {
        reading = true; defer { reading = false }
        struct S: Decodable { let summary: String? }
        do {
            let d = try await Practice.post("review-summary", model: model)
            summary = (try? JSONDecoder().decode(S.self, from: d))?.summary ?? ""
            if summary.isEmpty { result = "The record is thin this week. Write the three lines yourself." }
        } catch { result = error.localizedDescription }
    }

    private func seal() async {
        do {
            try await Practice.post("reviews", ["worked": worked, "adjust": adjust, "celebrate": celebrate, "ai_summary": summary], model: model)
            result = "Sealed."; sealed += 1; worked = ""; adjust = ""; celebrate = ""; summary = ""
            await load(); await PracticeSection.state.loadToday(model: model)
        } catch { result = error.localizedDescription }
    }
}

extension PracticeReview {
    /// An empty review row is only the due-date marker; it is not shown as a sealed week.
    var hasText: Bool { [worked, adjust, celebrate, ai_summary].contains { !($0 ?? "").isEmpty } }
}

// MARK: - The record: the story history and the rehearsals

struct TrendsView: View {
    let model: AppModel
    @State private var trends: [PracticeTrend] = []
    @State private var sessions: [PracticeSessionRow] = []
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        List {
            let week = sessions.filter { s in Date.pl(s.created_at).map { Date().timeIntervalSince($0) < 7 * 86400 } ?? false }
            Section {
                if week.isEmpty { Text("No rehearsals this week.").foregroundStyle(.secondary) }
                else {
                    LabeledContent("Rehearsals", value: "\(week.count)")
                    LabeledContent("Average intensity", value: String(format: "%.1f of 5", Double(week.map(\.intensity).reduce(0, +)) / Double(week.count)))
                    ForEach(week.prefix(5)) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.intensity) of 5 · \(s.desire_text.map { String($0.prefix(60)) } ?? "a rehearsal")").font(.callout)
                            Ago(text: s.created_at).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: { Text("Rehearsals · this week") }
            if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            if loaded && failure == nil && trends.isEmpty { ContentUnavailableView("No days on the record yet", systemImage: "chart.xyaxis.line", description: Text("Each check-in adds a day to the story history.")) }
            Section("Story history") {
                ForEach(trends) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(t.date).font(.caption.bold()); if let m = t.mood, !m.isEmpty { Text(m.capitalized).font(.caption).foregroundStyle(.secondary) } }
                        if let s = t.story, !s.isEmpty { Text(s).font(.callout) }
                        if let g = t.gratitude, !g.isEmpty { Text("Real: \(g)").font(.callout).foregroundStyle(.secondary) }
                        if let sh = t.story_shifted, !sh.isEmpty { Text("Shifted: \(sh)").font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("The record").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        async let t = try? Practice.get("trends", [PracticeTrend].self, model: model)
        async let s = try? Practice.get("sessions", [PracticeSessionRow].self, model: model)
        let (t1, s1) = await (t, s)
        if let t1 { trends = t1 }
        if let s1 { sessions = s1 }
        failure = (t1 == nil && s1 == nil) ? "Could not load the record. Pull to try again." : nil
        loaded = true
    }
}

// MARK: - Vision board

struct VisionView: View {
    let model: AppModel
    @State private var pins: [PracticePin] = []
    @State private var pinsFailed = false
    @State private var more: [PracticeBoardImages.Image] = []
    @State private var picking = false
    @State private var photo: PhotosPickerItem?
    @State private var result: String?
    @State private var uploading = false

    var body: some View {
        List {
            Section {
                if pinsFailed && pins.isEmpty { Text("Your board did not load. Pull to try again.").foregroundStyle(.secondary) }
                else if pins.isEmpty { Text("Nothing chosen yet. Tap a picture below to keep it.").foregroundStyle(.secondary) }
                else { grid(pins.map { ($0.url, $0.alt, true) }) }
            } header: { Text("Chosen") } footer: { Text("Tap a chosen picture to let it go. Chosen pictures stay.") }
            Section {
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) { Label(uploading ? "Adding…" : "Add your own", systemImage: "photo.badge.plus") }.disabled(uploading)
                    Spacer()
                    Button("From the catalogue") { picking = true }
                }
                ResultLine(text: result)
            }
            Section {
                grid(more.filter { m in !pins.contains { $0.url == m.url } }.map { ($0.url, $0.alt, false) })
            } header: { Text("More from the house") } footer: { Text("Twelve at random from his catalogue. Pull down for another twelve.") }
        }
        .navigationTitle("Vision board").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.select, trigger: pins.count)
        .sheet(isPresented: $picking) { PicturePicker { url in picking = false; Task { await toggle(url, "Catalogue") } } }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
        .task { await load(refreshMore: true) }
        .refreshable { await load(refreshMore: true) }
    }

    private func grid(_ items: [(String, String?, Bool)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.0) { url, alt, pinned in
                Button { Task { await toggle(url, alt ?? "") } } label: {
                    AsyncImage(url: Practice.imageURL(url, model: model)) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                        .frame(height: 96).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topTrailing) { if pinned { Image(systemName: "pin.fill").font(.caption).padding(5).foregroundStyle(.white).background(Wallpaper.line, in: Circle()).padding(4) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(alt ?? "Picture"), \(pinned ? "chosen" : "not chosen")")
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
    }

    private func load(refreshMore: Bool) async {
        if let p = try? await Practice.get("pins", [PracticePin].self, model: model) { pins = p; pinsFailed = false } else { pinsFailed = true }
        if refreshMore, let m = try? await Practice.get("vision-board", PracticeBoardImages.self, model: model, query: ["source": "house"]) { more = m.images }
    }

    private func toggle(_ url: String, _ alt: String) async {
        do { try await Practice.post("pins/toggle", ["url": url, "alt": alt], model: model); await load(refreshMore: false) }
        catch { result = error.localizedDescription }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true; defer { uploading = false; photo = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: raw), let jpeg = img.jpegData(compressionQuality: 0.82) else { result = "Not added. That picture would not load."; return }
        struct Up: Decodable { let url: String? }
        do {
            let d = try await Practice.upload("board-upload", jpeg, type: "image/jpeg", model: model)
            guard let u = (try? JSONDecoder().decode(Up.self, from: d))?.url else { result = "Not added. The practice did not take it."; return }
            try await Practice.post("pins/toggle", ["url": u, "alt": "Mine"], model: model)
            result = "Added."; await load(refreshMore: false)
        } catch { result = error.localizedDescription }
    }
}
