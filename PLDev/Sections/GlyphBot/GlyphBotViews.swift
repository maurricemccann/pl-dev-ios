import SwiftUI
import TipKit

// MARK: - Ask: the Oracle, offline-first (the web room's twin)

/// Reveals text a couple of characters at a time, as the web room does. Instant when Reduce Motion is on.
struct TypewriterText: View {
    let text: String
    let animate: Bool
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(animate && !reduceMotion ? String(text.prefix(shown)) : text)
            .plReading().textSelection(.enabled)
            .task(id: text) {
                guard animate, !reduceMotion else { return }
                shown = 0
                while shown < text.count, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(15))
                    shown = min(text.count, shown + 2)
                }
            }
    }
}

struct AskTab: View {
    let model: AppModel
    @Bindable var state: GlyphBotModel
    private let store = GlyphBotStore.shared
    private let net = GlyphBotNet.shared
    private let voice = GlyphBotVoice.shared
    @State private var text = ""
    @State private var loading = false
    @State private var typingID: String?
    @State private var sourcesFor: GlyphTurn?
    @State private var note: String?
    @State private var sent = 0

    private var thread: [GlyphTurn] { Array(store.turns.prefix(30).reversed()) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    status
                    TipView(AnswerHoldTip())
                    if thread.isEmpty { ContentUnavailableView("Nothing asked yet", systemImage: "bubbles.and.sparkles", description: Text("Ask. GlyphBot answers from the practice, and from memory when you are offline.")) }
                    ForEach(thread) { t in
                        PracticeBubble(text: t.question, mine: true).id("\(t.id)-q")
                        if !t.answer.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    TypewriterText(text: t.answer, animate: typingID == t.id)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: PLRadius.row + 4, style: .continuous))
                                    Text(GlyphBot.viaWords(t.via)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 40)
                            }
                            .id(t.id)
                            .contextMenu {
                                if !t.passages.isEmpty { Button("Sources", systemImage: "doc.text.magnifyingglass") { sourcesFor = t } }
                                if GlyphBot.interviewReady(model) { Button("Hear it", systemImage: "speaker.wave.2") { Task { note = await voice.speak(t.answer, model: model) } } }
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = t.answer }
                            }
                        }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).id("typing") }
                    if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap)
            }
            .onChange(of: store.turns.first?.answer) { _, _ in withAnimation { proxy.scrollTo(thread.last.map { "\($0.id)" }, anchor: .bottom) } }
            .onChange(of: loading) { _, now in if now { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(net.online ? "Ask the practice" : "Offline: answering from memory", text: $text, axis: .vertical).lineLimit(1...4)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(loading || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Ask")
            }
            .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap).background(.bar)
        }
        .sensoryFeedback(PLHaptic.select, trigger: sent)
        .sheet(item: $sourcesFor) { t in SourcesSheet(turn: t) }
        .onDisappear { voice.stop() }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Image(systemName: net.online ? "circle.fill" : "circle.dotted").font(.caption2).foregroundStyle(net.online ? Color.green : PLTone.house)
            Text(net.online ? "Online" : "Offline: answering from memory").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if store.unsynced.count > 0 {
                Button("\(store.unsynced.count) to sync") { Task { await store.flush(model: model); state.publish() } }.font(.caption).buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The question is kept the instant it is asked, so an offline turn still persists; the answer fills in after.
    private func ask() async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        text = ""; loading = true; note = nil; defer { loading = false }
        var turn = GlyphTurn(id: UUID().uuidString, question: q, answer: "", via: "", passages: [], askedAt: ISO8601DateFormatter().string(from: .now), synced: false)
        store.save(turn); sent += 1
        if net.online, let r = try? await GlyphBot.ask(q, model: model), !r.answer.isEmpty {
            turn.answer = r.answer; turn.via = r.via; turn.passages = r.passages
        } else {
            let hit = store.cached(for: q)
            turn.answer = hit?.answer ?? GlyphDoctrine.pick(q)
            let why = net.online ? "the Oracle did not answer" : "offline"   // online but refused is not "offline"
            turn.via = hit == nil ? "doctrine · \(why)" : "cached · \(why)"
        }
        store.save(turn); typingID = turn.id
        await store.flush(model: model); state.publish()
    }
}

struct SourcesSheet: View {
    let turn: GlyphTurn
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(turn.passages, id: \.self) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.source.isEmpty ? "A passage" : p.source.replacingOccurrences(of: "-", with: " ").capitalized).font(.headline)
                    Text(p.text).font(.callout).foregroundStyle(.secondary).lineLimit(8)
                }
            }
            .overlay { if turn.passages.isEmpty { ContentUnavailableView("No sources", systemImage: "doc.text", description: Text("This answer came from memory or the bundled doctrine.")) } }
            .navigationTitle("Sources").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

// MARK: - Sit: the interviewer

@MainActor @Observable final class SittingModel {
    enum Mode: String, CaseIterable, Identifiable {
        case interview, free
        var id: String { rawValue }
        var title: String { self == .interview ? "Interview" : "Free talk" }
    }
    struct Line: Identifiable { let id = UUID(); let mine: Bool; let text: String; let seat: String? }

    var mode: Mode = .interview
    var domain = ""                   // empty: GlyphBot chooses
    var settings = GlyphBot.Settings()
    var lines: [Line] = []
    var sid: Int?
    var started: Date?
    var answers = 0
    var busy = false
    var done = false
    var error: String?
    var draft = ""                    // his answer; it stays here when a send fails

    var active: Bool { started != nil }
    var savedSitting: Bool { UserDefaults.standard.integer(forKey: "glyphbot.sid") > 0 && !(UserDefaults.standard.string(forKey: "glyphbot.lastQ") ?? "").isEmpty }

    func begin(model: AppModel) async {
        lines = []; sid = nil; answers = 0; done = false; error = nil; draft = ""
        started = Date()
        SittingLive.start(mode: mode.title, started: started ?? .now)
        guard mode == .interview else { return }   // free talk: he speaks first
        await ask("[open]", visible: false, model: model)
    }

    func resume() {
        let d = UserDefaults.standard
        sid = d.integer(forKey: "glyphbot.sid"); started = Date(); answers = 0; done = false; error = nil; draft = ""
        mode = Mode(rawValue: d.string(forKey: "glyphbot.mode") ?? "") ?? .interview
        lines = [Line(mine: false, text: d.string(forKey: "glyphbot.lastQ") ?? "", seat: d.string(forKey: "glyphbot.lastSeat"))]
        SittingLive.start(mode: mode.title, started: started ?? .now)
    }

    /// The one call site of an answer. It runs only from the Send button.
    func send(model: AppModel) async {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        draft = ""
        await ask(t, visible: true, model: model)
    }

    private func ask(_ text: String, visible: Bool, model: AppModel) async {
        busy = true; error = nil; defer { busy = false }
        let mineLine = Line(mine: true, text: text, seat: nil)
        if visible { lines.append(mineLine) }
        do {
            let dom: String? = mode == .free ? (sid == nil ? "free" : nil) : (sid == nil && !domain.isEmpty ? domain : nil)
            let r = try await GlyphBot.turn(session: sid, text: text, domain: dom, settings: settings, model: model)
            sid = r.session_id ?? sid
            if visible { answers += 1 }
            done = r.done == true
            if let q = r.reply, !q.isEmpty {
                lines.append(Line(mine: false, text: q, seat: r.seat))
                let d = UserDefaults.standard
                d.set(sid ?? 0, forKey: "glyphbot.sid"); d.set(q, forKey: "glyphbot.lastQ"); d.set(r.seat ?? "", forKey: "glyphbot.lastSeat"); d.set(mode.rawValue, forKey: "glyphbot.mode")
            }
            await SittingLive.update(answers: answers, seat: GlyphBot.seatTitle(r.seat))
            if done { await end() }
        } catch {
            if visible { lines.removeAll { $0.id == mineLine.id }; draft = text }   // nothing lost: the answer is back in the box
            self.error = "Not sent. \(plainSentence(error)) Your answer is still in the box."
        }
    }

    func end() async {
        await SittingLive.stop()
        if done { UserDefaults.standard.removeObject(forKey: "glyphbot.sid") }
        started = nil
    }
}

struct SitTab: View {
    let model: AppModel
    @Bindable var state: GlyphBotModel
    @Bindable var sitting: SittingModel
    private let voice = GlyphBotVoice.shared
    @State private var note: String?

    var body: some View {
        Group {
            if !GlyphBot.interviewReady(model) {
                ContentUnavailableView("The interviewer needs its key", systemImage: "key", description: Text("Your config has no key named interview. Add it to the config file and load it again."))
            } else if sitting.active { thread } else { setup }
        }
        .sensoryFeedback(PLHaptic.select, trigger: sitting.lines.count)
        .onDisappear { voice.stop() }
    }

    private var setup: some View {
        Form {
            Section {
                Picker("Mode", selection: $sitting.mode) { ForEach(SittingModel.Mode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            } footer: {
                Text(sitting.mode == .interview ? "GlyphBot asks, one question at a time, and pulls on what you say. Everything you answer is saved word for word."
                                                : "You start. GlyphBot answers like someone who has read everything you ever said.")
            }
            if sitting.mode == .interview {
                Section("This sitting") {
                    Picker("Domain", selection: $sitting.domain) {
                        Text("Let GlyphBot choose").tag("")
                        ForEach(GlyphBot.domains, id: \.self) { Text(GlyphBot.domainTitle($0)).tag($0) }
                    }
                    Picker("Pressure", selection: $sitting.settings.boldness) { Text("Light").tag("light"); Text("Gentle").tag("gentle"); Text("Probing").tag("probing") }
                    Picker("Length", selection: $sitting.settings.targetMin) { Text("Open").tag(0); Text("10 minutes").tag(10); Text("20 minutes").tag(20); Text("30 minutes").tag(30) }
                    Toggle("Go deeper on rich answers", isOn: $sitting.settings.deep)
                }
            }
            Section {
                Button(sitting.mode == .interview ? "Begin the sitting" : "Start talking") { Task { await sitting.begin(model: model) } }
                if sitting.savedSitting { Button("Continue the last sitting") { sitting.resume() } }
            }
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if sitting.lines.isEmpty && !sitting.busy {
                        ContentUnavailableView("You start", systemImage: "text.bubble", description: Text("Say what is on your mind. Nothing is sent until you press send."))
                    }
                    ForEach(sitting.lines) { l in
                        if l.mine { PracticeBubble(text: l.text, mine: true).id(l.id) }
                        else {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.text).plReading().textSelection(.enabled)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: PLRadius.row + 4, style: .continuous))
                                    Label(GlyphBot.seatTitle(l.seat), systemImage: GlyphBot.seatSymbol(l.seat)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 40)
                            }
                            .id(l.id)
                            .contextMenu {
                                Button("Hear it", systemImage: "speaker.wave.2") { Task { note = await voice.speak(l.text, model: model) } }
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = l.text }
                            }
                        }
                    }
                    if sitting.busy { ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).id("typing") }
                    if let e = sitting.error { ResultLine(text: e) }
                    if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    if sitting.done { Text("The sitting is over. Everything you said is kept word for word.").font(.footnote).foregroundStyle(.secondary).padding(.top, 8) }
                }
                .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap)
            }
            .onChange(of: sitting.lines.count) { _, _ in withAnimation { proxy.scrollTo(sitting.lines.last?.id, anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Your answer", text: $sitting.draft, axis: .vertical).lineLimit(1...8)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Button { Task { await sitting.send(model: model) } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(sitting.busy || sitting.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Send")
                }
                Button(sitting.done ? "Finish" : "End the sitting") { Task { await sitting.end() } }.font(.footnote).buttonStyle(.borderless)
            }
            .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap).background(.bar)
        }
    }
}

// MARK: - Record: what the interviews have kept

struct GlyphRecordTab: View {
    let model: AppModel
    @Bindable var state: GlyphBotModel
    private let store = GlyphBotStore.shared

    var body: some View {
        List {
            if let m = state.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
            if let s = state.interview {
                Section {
                    PracticeKpis(items: [("bank questions asked", "\(s.bank?.asked ?? 0) of \(s.bank?.total ?? 0)"), ("answers on record", "\((s.coverage ?? [:]).values.reduce(0, +))")])
                    if let r = s.bank?.next_round { LabeledContent("Next round", value: r.capitalized) }
                }
                Section {
                    let cov = s.coverage ?? [:]
                    let top = max(cov.values.max() ?? 1, 1)
                    ForEach(GlyphBot.domains, id: \.self) { d in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(GlyphBot.domainTitle(d)); Spacer(); Text("\(cov[d] ?? 0)").monospacedDigit().foregroundStyle(.secondary) }
                            ProgressView(value: Double(cov[d] ?? 0), total: Double(top)).tint(Wallpaper.line)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: { Text("Coverage") } footer: { Text("Answers per domain. GlyphBot steers toward the thinnest.") }
                if let recent = s.recent, !recent.isEmpty {
                    Section("Recent answers") {
                        ForEach(recent) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                if let q = r.question { Text(q).font(.callout).foregroundStyle(.secondary) }
                                Text(r.answer).plReading().lineLimit(6)
                                HStack { if let d = r.domain { Text(GlyphBot.domainTitle(d)) }; Ago(text: r.at) }.font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else if !GlyphBot.interviewReady(model) {
                ContentUnavailableView("The record needs the interviewer key", systemImage: "key", description: Text("Your config has no key named interview. Add it to the config file and load it again."))
            } else if !OfflineState.shared.online {
                ContentUnavailableView("The record needs a connection the first time", systemImage: "wifi.slash", description: Text("Once it has loaded, it stays on this iPhone for offline use."))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
            Section {
                LabeledContent("Oracle questions on this phone", value: "\(store.turns.count)")
                LabeledContent("Waiting to sync", value: "\(store.unsynced.count)")
                if store.unsynced.count > 0 { Button("Sync now") { Task { await store.flush(model: model); state.publish() } } }
            } header: { Text("The Oracle") } footer: { Text("Every question is kept the moment you ask it, offline too, and syncs when the connection returns.") }
        }
        .refreshable { await state.loadState(model: model) }
        .task { await state.loadState(model: model) }
    }
}
