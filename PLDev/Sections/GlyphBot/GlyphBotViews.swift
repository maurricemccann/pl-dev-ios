import SwiftUI
import TipKit

// MARK: - Ask: the Oracle, offline-first (the web room's twin)

/// Reveals text a couple of characters at a time, as the web room does. Instant when Reduce Motion is on.
struct TypewriterText: View {
    let text: String
    let animate: Bool
    var onDone: (() -> Void)? = nil
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
                if !Task.isCancelled { onDone?() }
            }
    }
}

struct AskTab: View {
    @Environment(\.colorScheme) private var scheme
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

    private var face: GlyphTurn? { thread.last { !$0.answer.isEmpty } }
    private var history: [GlyphTurn] { thread.filter { $0.id != face?.id } }

    var body: some View {
        VStack(spacing: 0) {
            stage
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        status
                        TipView(AnswerHoldTip())
                        ForEach(history) { t in
                            GlyphUserBubble(text: t.question).id("\(t.id)-q")
                            if !t.answer.isEmpty {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        GlyphBubble(mine: false) { Text(t.answer).font(SiteFont.body(15)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(4).textSelection(.enabled) }
                                        Text(GlyphBot.viaWords(t.via)).font(SiteFont.body(11, relativeTo: .caption)).foregroundStyle(Bone.inkFaint(scheme))
                                    }
                                    Spacer(minLength: 40)
                                }
                                .id(t.id)
                                .contextMenu { turnMenu(t) }
                            }
                        }
                        if let f = face { GlyphUserBubble(text: f.question).id("\(f.id)-q") }
                        if let note { Text(note).font(Font.pl(.footnote)).foregroundStyle(.secondary) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .onChange(of: store.turns.first?.answer) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: loading) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(net.online ? "Ask the practice" : "Offline: answering from memory", text: $text, axis: .vertical).lineLimit(1...4).siteField()
                Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(Font.pl(.largeTitle)).foregroundStyle(Bone.gold).frame(minWidth: 44, minHeight: 44) }
                    .disabled(loading || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Ask")
            }
            .padding(.horizontal, 20).padding(.vertical, 10).background(Bone.ground(scheme)).overlay(alignment: .top) { SiteRule() }
        }
        .background { SiteGround() }
        .sensoryFeedback(PLHaptic.select, trigger: sent)
        .sheet(item: $sourcesFor) { t in SourcesSheet(turn: t) }
        .onDisappear { voice.stop() }
    }

    /// The stage: GlyphGuy seated at the left, the latest answer in his bubble (the web room's top block).
    private var stage: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphStageFigure(speaking: typingID != nil)
                .frame(width: 112, height: 176)
            Group {
                if let f = face {
                    GlyphStageBubble(text: f.answer, sources: f.passages, loading: loading, typing: typingID == f.id, onDone: { typingID = nil })
                        .contextMenu { turnMenu(f) }
                } else {
                    GlyphStageBubble(text: "Ask. I answer from the practice.", sources: [], loading: loading, typing: false, onDone: nil)
                }
            }
            .padding(.top, 32)
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    @ViewBuilder private func turnMenu(_ t: GlyphTurn) -> some View {
        if !t.passages.isEmpty { Button("Sources", systemImage: "doc.text.magnifyingglass") { sourcesFor = t } }
        if GlyphBot.interviewReady(model) { Button("Hear it", systemImage: "speaker.wave.2") { Task { note = await voice.speak(t.answer, model: model) } } }
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = t.answer }
    }

    private var status: some View {
        HStack(spacing: 6) {
            if !net.online {   // online is already shown in the header; said once (11-13)
                Image(systemName: "circle.dotted").font(Font.pl(.caption2)).foregroundStyle(Bone.amber)
                Text("Offline: answering from memory").font(Font.pl(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            if store.unsynced.count > 0 {
                SiteAction(title: "\(store.unsynced.count) to sync") { Task { await store.flush(model: model); state.publish() } }
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
            let why = net.online ? "the Oracle did not answer" : "offline"   // online but refused is not "offline"
            if hit == nil, let local = await PLIntelligence.glyphAnswer(question: q, turns: store.turns) {   // apple lane: Apple Intelligence, from the record only
                turn.answer = local; turn.via = "on-device · \(why)"
            } else {
                turn.answer = hit?.answer ?? GlyphDoctrine.pick(q)
                turn.via = hit == nil ? "doctrine · \(why)" : "cached · \(why)"
            }
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
                    Text(p.source.isEmpty ? "A passage" : p.source.replacingOccurrences(of: "-", with: " ").capitalized).font(Font.pl(.headline))
                    Text(p.text).font(Font.pl(.callout)).foregroundStyle(.secondary).lineLimit(8)
                }
                .listRowBackground(PLRowGround())
            }
            .glyphList()
            .overlay { if turn.passages.isEmpty { ContentUnavailableView("No sources", systemImage: "doc.text", description: Text("This answer came from memory or the bundled doctrine.")) } }
            .navigationTitle("Sources").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

// MARK: - Sit: the interviewer

@MainActor @Observable final class SittingModel {
    enum Mode: String, CaseIterable, Identifiable {
        case interview, free, mastermind
        var id: String { rawValue }
        var title: String { switch self { case .interview: "Interview"; case .free: "Free talk"; case .mastermind: "Mastermind" } }
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

    /// A sitting saved on this phone that is still recent enough to continue (`SittingFreshness`), and when it was left.
    /// Stored, so the setup screen redraws the moment an old one is cleared.
    var savedSitting = false
    var savedAt: Date?

    var active: Bool { started != nil }

    init() { refreshSaved() }

    private static let savedKeys = ["glyphbot.sid", "glyphbot.lastQ", "glyphbot.lastSeat", "glyphbot.mode", "glyphbot.at"]

    /// Reads what is saved. The server opens a new sitting only when no session id is sent and closes one only at the monthly
    /// budget, so a saved id alone would resume the question he left a month ago (his 11-24). One that is not recent is cleared
    /// here, so the next sitting begins fresh and the newest queued questions come up.
    func refreshSaved() {
        let d = UserDefaults.standard
        let has = d.integer(forKey: "glyphbot.sid") > 0 && !(d.string(forKey: "glyphbot.lastQ") ?? "").isEmpty
        let at = (d.object(forKey: "glyphbot.at") as? Double).map { Date(timeIntervalSince1970: $0) }
        if has, !SittingFreshness.isFresh(savedAt: at) { clearSaved(); return }
        savedSitting = has; savedAt = has ? at : nil
    }

    private func clearSaved() {
        Self.savedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        savedSitting = false; savedAt = nil
    }

    func begin(model: AppModel) async {
        clearSaved()   // "Start a new sitting" means new: nothing of the last one is offered or sent
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
            let dom: String? = mode != .interview ? (sid == nil ? mode.rawValue : nil) : (sid == nil && !domain.isEmpty ? domain : nil)
            var engine = settings
            InterviewPrefs.apply(to: &engine)   // model, adventure, reply length and the bank, from Voice and answers
            let r = try await GlyphBot.turn(session: sid, text: text, domain: dom, settings: engine, model: model, context: mode == .mastermind ? GateStore.shared.summary : nil)
            sid = r.session_id ?? sid
            if visible { answers += 1 }
            done = r.done == true
            if let q = r.reply, !q.isEmpty {
                lines.append(Line(mine: false, text: q, seat: r.seat))
                let d = UserDefaults.standard
                d.set(sid ?? 0, forKey: "glyphbot.sid"); d.set(q, forKey: "glyphbot.lastQ"); d.set(r.seat ?? "", forKey: "glyphbot.lastSeat"); d.set(mode.rawValue, forKey: "glyphbot.mode")
                d.set(Date().timeIntervalSince1970, forKey: "glyphbot.at")   // when he left off: a sitting is continued only while this is recent
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
        if done { clearSaved() }
        started = nil
        refreshSaved()
    }
}

struct SitTab: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel
    @Bindable var state: GlyphBotModel
    @Bindable var sitting: SittingModel
    private let voice = GlyphBotVoice.shared
    @State private var note: String?
    @State private var talk = InterviewTalk()

    var body: some View {
        Group {
            if !GlyphBot.interviewReady(model) {
                SiteEmpty(title: "The interviewer needs its key", detail: "Your config has no key named interview. Add it to the config file and load it again.")
            } else if sitting.active { thread } else { setup }
        }
        .sensoryFeedback(PLHaptic.select, trigger: sitting.lines.count)
        .onAppear { sitting.refreshSaved() }
        .onDisappear { voice.stop(); talk.stopAll() }
        .onChange(of: sitting.lines.count) { _, _ in
            // Voice: each question the interviewer asks is spoken aloud in an Apple voice, then it listens (hands free) or waits for the held gold.
            guard talk.on, sitting.active, !sitting.done, let last = sitting.lines.last, !last.mine else { return }
            talk.speak(last.text) { heard in sitting.draft = heard; Task { await sitting.send(model: model) } }
        }
        .onChange(of: sitting.error) { _, e in if talk.on, let e { talk.idle(e) } }
        .onChange(of: sitting.active) { _, a in if !a { talk.stopAll() } }
    }

    private var modeIndex: Binding<Int> {
        Binding(get: { SittingModel.Mode.allCases.firstIndex(of: sitting.mode) ?? 0 }, set: { sitting.mode = SittingModel.Mode.allCases[$0] })
    }

    // MARK: setup: the page opens like the Congregation's, then the cards

    private var setup: some View {
        let s = state.interview
        let interview = sitting.mode == .interview
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SitePageHead(eyebrow: sitting.mode == .mastermind ? "The mastermind" : "The interview", lead: interview ? "GlyphBot asks," : "You start,",
                             accent: interview ? "you answer." : sitting.mode == .mastermind ? "two minds make a third." : "it answers.",
                             lede: interview ? "One question at a time. It pulls on what you say, and everything you answer is saved word for word."
                                 : sitting.mode == .mastermind ? "Bring what you are calling in. GlyphBot sharpens it, names what is in the way, and holds you to it. It sees your Gate."
                                 : "GlyphBot answers like someone who has read everything you ever said.")
                VStack(alignment: .leading, spacing: 16) {
                    GlyphUsageRow(model: model)
                    SiteSegment(titles: SittingModel.Mode.allCases.map(\.title), index: modeIndex)
                    if interview {
                        upNext
                        answered
                        if let b = s?.bank, (b.total ?? 0) > 0 { bankCard(b) }
                        doors
                        thisSitting
                    }
                    voiceCard
                    actions
                }
                .padding(.horizontal, 20).padding(.bottom, 28)
            }
        }
        .background { SiteGround() }
        .task { await state.loadState(model: model) }
        .refreshable { await state.loadState(model: model) }
    }

    /// The questions, before he sits down: the topics the interviewer draws from (the newest five unused) and the bank questions it may reword.
    private var upNext: some View {
        let s = state.interview
        return GlyphCard(title: "Up next", note: "The interviewer sees these, newest first, and rewords them to fit where the talk is.") {
            if let q = s?.queue, !q.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(q.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { SiteRule() }
                        questionLine(t.text, tag: nil)
                    }
                }
            } else if s == nil {
                if let m = state.message {
                    Text(m).siteBody(14)
                    SiteAction(title: "Try again") { Task { await state.loadState(model: model) } }
                } else { SitePulse() }
            } else if s?.queue == nil {
                Text("The queue shows here once the server has its update.").siteBody(14)
            } else {
                Text("Nothing is queued. It will choose from the bank.").siteBody(14)
            }
            if let b = s?.bank_next, !b.isEmpty {
                SiteRule()
                Text("From the bank").siteLabel(11)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(b.enumerated()), id: \.element.id) { i, q in
                        if i > 0 { SiteRule() }
                        questionLine(q.text, tag: q.round?.capitalized)
                    }
                }
            }
        }
    }

    private func questionLine(_ text: String, tag: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let tag { Text(tag).siteLabel(11) }
            Text(text).font(SiteFont.display(18)).foregroundStyle(Bone.ink(scheme)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// What he already answered, read only; the whole record is the Record tab.
    @ViewBuilder private var answered: some View {
        if let recent = state.interview?.recent, !recent.isEmpty {
            GlyphCard(title: "Already answered", note: "Read only. Every answer is kept word for word.") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recent.prefix(3).enumerated()), id: \.element.id) { i, r in
                        if i > 0 { SiteRule() }
                        VStack(alignment: .leading, spacing: 4) {
                            if let q = r.question { Text(q).font(SiteFont.body(13, relativeTo: .footnote)).foregroundStyle(Bone.inkFaint(scheme)).lineLimit(2) }
                            Text(r.answer).font(SiteFont.body(14)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(3).lineLimit(3)
                        }
                        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                SiteAction(title: "All answers") { state.tab = .record }
            }
        }
    }

    private func bankCard(_ b: GlyphBot.StateReply.Bank) -> some View {
        GlyphCard(title: "The 501") {
            HStack {
                Text("\(b.asked ?? 0) of \(b.total ?? 0) asked").font(SiteFont.body(14)).monospacedDigit().foregroundStyle(Bone.ink(scheme))
                Spacer()
                Text(b.next_round.map { "Next: \($0.capitalized)" } ?? "All asked").font(SiteFont.body(13, relativeTo: .footnote)).foregroundStyle(Bone.inkFaint(scheme))
            }
            ProgressView(value: Double(b.asked ?? 0), total: Double(max(1, b.total ?? 1))).tint(Bone.gold)
        }
        .accessibilityElement(children: .combine)
    }

    /// The page's doors: one tap sits you down on that domain, with how much it already holds.
    private var doors: some View {
        let cov = state.interview?.coverage ?? [:]
        return GlyphCard(title: "Doors") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(GlyphBot.domains.enumerated()), id: \.element) { i, d in
                    if i > 0 { SiteRule() }
                    Button { sitting.domain = d; Task { await sitting.begin(model: model) } } label: {
                        HStack {
                            Text(GlyphBot.domainTitle(d)).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
                            Spacer()
                            Text((cov[d] ?? 0) == 0 ? "Untouched" : "\(cov[d] ?? 0) answer\((cov[d] ?? 0) == 1 ? "" : "s")").font(SiteFont.body(13, relativeTo: .footnote)).foregroundStyle(Bone.inkFaint(scheme))
                            Image(systemName: "chevron.right").font(Font.pl(.caption2).weight(.bold)).foregroundStyle(Bone.inkFaint(scheme))
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var thisSitting: some View {
        GlyphCard(title: "This sitting") {
            GlyphRow(title: "Domain") {
                Picker("Domain", selection: $sitting.domain) {
                    Text("Let GlyphBot choose").tag("")
                    ForEach(GlyphBot.domains, id: \.self) { Text(GlyphBot.domainTitle($0)).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }
            SiteRule()
            GlyphRow(title: "Pressure") {
                Picker("Pressure", selection: $sitting.settings.boldness) { Text("Light").tag("light"); Text("Gentle").tag("gentle"); Text("Probing").tag("probing") }.labelsHidden().pickerStyle(.menu)
            }
            SiteRule()
            GlyphRow(title: "Length") {
                Picker("Length", selection: $sitting.settings.targetMin) { Text("Open").tag(0); Text("10 minutes").tag(10); Text("20 minutes").tag(20); Text("30 minutes").tag(30) }.labelsHidden().pickerStyle(.menu)
            }
            SiteRule()
            GlyphRow(title: "Go deeper on rich answers") { Toggle("Go deeper on rich answers", isOn: $sitting.settings.deep).labelsHidden() }
        }
    }

    private var voiceCard: some View {
        GlyphCard(title: "Voice", note: "It speaks each question in an Apple voice on this iPhone and hears you with Apple's on-device speech. Hands free or push to talk, the pause, the speed and the model are in Voice and answers.") {
            if talk.supported {
                GlyphRow(title: "Talk to it") { Toggle("Talk to it", isOn: Binding(get: { talk.on }, set: { talk.setOn($0) })).labelsHidden() }
            } else {
                Text("Voice answers need Speech Recognition and the microphone. Allow them for PL DEV in Settings.").siteBody(14)
            }
            SiteRule()
            NavigationLink { InterviewSettingsView(sitting: sitting) } label: {
                GlyphRow(title: "Voice and answers") { Image(systemName: "chevron.right").font(Font.pl(.caption2).weight(.bold)).foregroundStyle(Bone.inkFaint(scheme)) }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A saved sitting can be continued only while it is recent; a new sitting is always one tap.
    private var actions: some View {
        VStack(spacing: 12) {
            if sitting.savedSitting {
                Button("Continue the last sitting") { sitting.resume() }.buttonStyle(SitePill(gold: true))
                if let at = sitting.savedAt {
                    Text("Left off " + at.formatted(.relative(presentation: .named))).font(SiteFont.body(12, relativeTo: .caption)).foregroundStyle(Bone.inkFaint(scheme))
                }
                Button("Start a new sitting") { Task { await sitting.begin(model: model) } }.buttonStyle(SiteGhost())
            } else {
                Button("Start a new sitting") { Task { await sitting.begin(model: model) } }.buttonStyle(SitePill(gold: true))
            }
        }
        .padding(.top, 4)
    }

    // MARK: the sitting itself

    /// The page's orb: the gold button, what it hears, and a way back to typing.
    private var orbPanel: some View {
        VStack(spacing: 8) {
            Text(talk.heard.isEmpty ? " " : talk.heard).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme)).lineLimit(3).frame(maxWidth: .infinity, minHeight: 22)
            InterviewOrb(talk: talk)
            Text(talk.statusLine).font(SiteFont.body(11, relativeTo: .caption, weight: .medium)).textCase(.uppercase).tracking(2.4)
                .foregroundStyle(talk.note == nil ? Bone.inkFaint(scheme) : Color(hex: 0xe08a8a))
            HStack(spacing: 18) {
                Button("Type instead") { talk.setOn(false) }
                NavigationLink { InterviewSettingsView(sitting: sitting) } label: { Text("Voice settings") }
            }.font(Font.pl(.footnote))
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if sitting.lines.isEmpty && !sitting.busy {
                        SiteEmpty(title: "You start", detail: "Say what is on your mind. Nothing is sent until you press send.")
                    }
                    ForEach(sitting.lines) { l in
                        if l.mine { GlyphUserBubble(text: l.text).id(l.id) }
                        else {
                            // the question is the point of the screen: the latest one is set large, in the site's display face
                            let newest = l.id == sitting.lines.last?.id
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    GlyphBubble(mine: false) {
                                        Text(l.text).font(newest ? SiteFont.display(21) : SiteFont.body(15)).foregroundStyle(Bone.ink(scheme)).lineSpacing(newest ? 5 : 4).textSelection(.enabled)
                                    }
                                    Label(GlyphBot.seatTitle(l.seat), systemImage: GlyphBot.seatSymbol(l.seat)).font(SiteFont.body(11, relativeTo: .caption)).foregroundStyle(Bone.inkFaint(scheme))
                                }
                                Spacer(minLength: 24)
                            }
                            .id(l.id)
                            .contextMenu {
                                Button("Hear it", systemImage: "speaker.wave.2") { Task { note = await voice.speak(l.text, model: model) } }
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = l.text }
                            }
                        }
                    }
                    if sitting.busy { PLThinkingOrb(size: 34).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).id("typing") }   // GlyphBot thinking (11-13)
                    if let e = sitting.error { SiteNote(text: e) }
                    if let note { SiteNote(text: note) }
                    if sitting.done { Text("The sitting is over. Everything you said is kept word for word.").siteBody(13).padding(.top, 8) }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .onChange(of: sitting.lines.count) { _, _ in withAnimation { proxy.scrollTo(sitting.lines.last?.id, anchor: .bottom) } }
        }
        .background { SiteGround() }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if talk.on { orbPanel } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Your answer", text: $sitting.draft, axis: .vertical).lineLimit(1...8).siteField()
                        Button { Task { await sitting.send(model: model) } } label: { Image(systemName: "arrow.up.circle.fill").font(Font.pl(.largeTitle)).foregroundStyle(Bone.gold).frame(minWidth: 44, minHeight: 44) }
                            .disabled(sitting.busy || sitting.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Send")
                        if talk.supported {
                            Button {
                                talk.setOn(true)
                                if let q = sitting.lines.last, !q.mine, !sitting.done { talk.speak(q.text) { heard in sitting.draft = heard; Task { await sitting.send(model: model) } } }
                            } label: { Image(systemName: "mic.circle").font(Font.pl(.largeTitle)).foregroundStyle(Bone.gold).frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("Answer by voice")
                        }
                    }
                }
                SiteAction(title: sitting.done ? "Finish" : "End the sitting", tone: .faint) { talk.stopAll(); Task { await sitting.end() } }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Bone.ground(scheme))
            .overlay(alignment: .top) { SiteRule() }
        }
    }
}

// MARK: - Record: what the interviews have kept

struct GlyphRecordTab: View {
    let model: AppModel
    @Bindable var state: GlyphBotModel
    private let store = GlyphBotStore.shared

    var body: some View {
        List { Group {
            if let m = state.message { Text(m).font(Font.pl(.footnote)).foregroundStyle(.secondary) }
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
                            ProgressView(value: Double(cov[d] ?? 0), total: Double(top)).tint(Bone.gold)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: { Text("Coverage") } footer: { Text("Answers per domain. GlyphBot steers toward the thinnest.") }
                if let recent = s.recent, !recent.isEmpty {
                    Section("Recent answers") {
                        ForEach(recent) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                if let q = r.question { Text(q).font(Font.pl(.callout)).foregroundStyle(.secondary) }
                                Text(r.answer).plReading().lineLimit(6)
                                HStack { if let d = r.domain { Text(GlyphBot.domainTitle(d)) }; Ago(text: r.at) }.font(Font.pl(.caption2)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else if !GlyphBot.interviewReady(model) {
                SiteEmpty(title: "The record needs the interviewer key", detail: "Your config has no key named interview. Add it to the config file and load it again.")
            } else if !OfflineState.shared.online {
                SiteEmpty(title: "The record needs a connection the first time", detail: "Once it has loaded, it stays on this iPhone for offline use.")
            } else if state.message != nil {
                // the load failed and said why above: a loader here would spin forever (11-14 sweep shot 11)
                SiteAction(title: "Try again") { Task { await state.loadState(model: model) } }
            } else {
                SitePulse()
            }
            Section {
                LabeledContent("Oracle questions on this phone", value: "\(store.turns.count)")
                LabeledContent("Waiting to sync", value: "\(store.unsynced.count)")
                if store.unsynced.count > 0 { Button("Sync now") { Task { await store.flush(model: model); state.publish() } } }
            } header: { Text("The Oracle") } footer: { Text("Every question is kept the moment you ask it, offline too, and syncs when the connection returns.") }
        }.listRowBackground(PLRowGround()) }
        .glyphList()
        .refreshable { await state.loadState(model: model) }
        .task { await state.loadState(model: model) }
    }
}

/// This month's interview spend against the cap, at the top of the Sit tab (pl-cron's R1 door, `usage`). Says so when it cannot read it.
struct GlyphUsageRow: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var text = "Reading this month's spend…"

    var body: some View {
        HStack {
            Text("This month").siteLabel(11)
            Spacer()
            Text(text).font(SiteFont.body(13, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Bone.inkSoft(scheme))
        }
        .task {
            do {
                let u = try await GlyphBot.usage(model: model)
                text = "$" + String(format: "%.2f", u.spent_usd ?? 0) + " of $" + String(format: "%.0f", u.cap_usd ?? 0) + " · " + (u.tier ?? "full") + " · \(u.turns ?? 0) turns"
            } catch {
                text = "Could not read the spend"
            }
        }
    }
}
