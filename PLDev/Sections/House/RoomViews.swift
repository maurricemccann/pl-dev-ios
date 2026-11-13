import SwiftUI

/// The pl-os rooms whose content lives inside pl-os itself (atlas, the Source interview, the Codex tool, comment drafts,
/// the catalog matrix, Notion), read from pl-os's PL DEV door (origin "os"), plus the Craft room.
@MainActor enum OS {
    static func get<T: Decodable>(_ name: String, _ type: T.Type, model: AppModel) async throws -> T {
        guard let http = model.http else { throw Console.Problem.notSetUp }
        return try JSONDecoder().decode(DataWrap<T>.self, from: try await http.send(RequestPlan(origin: "os", path: "api/pldev/\(name)"), timeout: 30)).data
    }
}

// MARK: - Atlas (/atlas)

struct AtlasView: View {
    let model: AppModel
    struct Node: Decodable, Identifiable { let id: String; let label: String; let zone: String; let blurb: String?; let what: String?; let does: [String]?; let use: String?; let control: String?; let link: String? }
    struct Step: Decodable, Hashable { let label: String; let system: String?; let note: String? }
    struct Journey: Decodable, Identifiable { let id: String; let title: String; let subtitle: String?; let steps: [Step] }
    struct Slot: Decodable, Hashable { let days: [Int]; let timePT: String; let label: String; let detail: String?; let `where`: String? }
    struct Zone: Decodable { let title: String }
    struct Control: Decodable { let label: String; let emoji: String? }
    struct Atlas: Decodable { let nodes: [Node]; let journeys: [Journey]; let schedule: [Slot]; let zones: [String: Zone]; let controls: [String: Control] }
    @State private var part = 0

    var body: some View {
        Loaded(load: { try await OS.get("atlas", Atlas.self, model: model) }) { a, _ in
            List {
                Picker("Part", selection: $part) { Text("Map").tag(0); Text("Journeys").tag(1); Text("Week").tag(2) }.pickerStyle(.segmented)
                switch part {
                case 0:
                    ForEach(["desk", "spine", "doors", "world"], id: \.self) { z in
                        Section(a.zones[z]?.title ?? z.capitalized) {
                            ForEach(a.nodes.filter { $0.zone == z }) { n in
                                NavigationLink { node(n, a) } label: {
                                    VStack(alignment: .leading, spacing: 2) { Text(n.label).font(.headline); if let b = n.blurb { Text(b).font(.caption).foregroundStyle(.secondary) } }
                                }
                            }
                        }
                    }
                case 1:
                    ForEach(a.journeys) { j in
                        Section { ForEach(Array(j.steps.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .top) {
                                Text("\(i + 1)").font(.caption.bold().monospacedDigit()).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) { Text(s.label); Text([s.system, s.note].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            }
                        } } header: { Text(j.title) } footer: { if let s = j.subtitle { Text(s) } }
                    }
                default:
                    ForEach(a.schedule, id: \.self) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(s.label).font(.headline); Spacer(); Text(s.timePT).font(.caption.monospacedDigit()) }
                            Text(days(s.days)).font(.caption).foregroundStyle(.secondary)
                            if let d = s.detail { Text(d).font(.callout) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Atlas")
    }

    private func days(_ d: [Int]) -> String {
        d.count == 7 ? "Every day" : d.map { Calendar.current.shortWeekdaySymbols[(($0 % 7) + 7) % 7] }.joined(separator: ", ")
    }

    private func node(_ n: Node, _ a: Atlas) -> some View {
        List {
            if let w = n.what { Section { Text(w) } }
            if let does = n.does, !does.isEmpty { Section("What it does") { ForEach(does, id: \.self) { Text($0) } } }
            if let u = n.use { Section("How you use it") { Text(u) } }
            if let c = n.control, let meta = a.controls[c] { Section("Control") { Text("\(meta.emoji ?? "") \(meta.label)") } }
            if let l = n.link, let url = URL(string: l) { Link("Open", destination: url) }
        }
        .navigationTitle(n.label)
    }
}

// MARK: - Codex tool (/codex): anchors, laws, diagnostic, vocabulary, modules, and a private log kept on this phone

struct CodexToolView: View {
    let model: AppModel
    struct Module: Decodable, Identifiable { let name: String; let trigger: String; let lines: [String]; var id: String { name } }
    struct Codex: Decodable { let anchors: [String]; let laws: [String]; let diagnostic: [[String]]; let vocab: [[String]]; let modules: [Module] }
    struct Entry: Codable, Identifiable { var id: String { date }; let date: String; let text: String; let stateWord: String }
    @AppStorage("pldev.codexLog") private var logData = Data()
    @State private var anchor = 0
    @State private var entry = ""
    @State private var word = ""
    @State private var filter = ""

    private var log: [Entry] { (try? JSONDecoder().decode([Entry].self, from: logData)) ?? [] }

    var body: some View {
        Loaded(load: { try await OS.get("codex", Codex.self, model: model) }) { c, _ in
            List {
                Section {
                    ForEach(Array(c.vocab.enumerated()), id: \.offset) { _, v in
                        HStack(alignment: .firstTextBaseline) {
                            Text(v.first ?? "").foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                            Text(v.dropFirst().joined(separator: " ")).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.callout)
                    }
                } header: { Text("Vocabulary install: scarcity → sovereign") } footer: { Text("Swap these out, immediately and permanently.") }
                Section("Anchor") {
                    Text(c.anchors.isEmpty ? "" : c.anchors[anchor % c.anchors.count]).plHand(24)
                    Button("Another", systemImage: "shuffle") { anchor = Int.random(in: 0..<max(c.anchors.count, 1)) }
                }
                Section("The laws") { ForEach(c.laws, id: \.self) { Text($0).plHand(20, relativeTo: .body) } }
                Section {
                    TextField("What happened today", text: $entry, axis: .vertical).lineLimit(3...8)
                    TextField("One word for your state", text: $word)
                    Button("Keep it") { save() }.disabled(entry.isEmpty)
                    ForEach(log.prefix(20)) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.text)
                            Text("\(String(e.date.prefix(10)))\(e.stateWord.isEmpty ? "" : " · \(e.stateWord)")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("The log") } footer: { Text("Kept on this iPhone only, as the web keeps it in the browser.") }
                Section("Diagnostic") {
                    TextField("Filter", text: $filter)
                    ForEach(Array(c.diagnostic.enumerated()).filter { filter.isEmpty || $0.element.joined(separator: " ").localizedCaseInsensitiveContains(filter) }, id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 2) { ForEach(Array(d.enumerated()), id: \.offset) { i, t in Text(t).font(i == 0 ? .headline : .callout) } }
                    }
                }
                Section("Modules") {
                    ForEach(c.modules) { m in
                        DisclosureGroup {
                            ForEach(m.lines, id: \.self) { Text($0).font(.callout) }
                        } label: { VStack(alignment: .leading) { Text(m.name).font(.headline); Text(m.trigger).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
            }
        }
        .navigationTitle("Codex")
    }

    private func save() {
        let e = Entry(date: ISO8601DateFormatter().string(from: .now), text: entry, stateWord: word)
        logData = (try? JSONEncoder().encode(Array(([e] + log).prefix(200)))) ?? logData
        entry = ""; word = ""
    }
}

// MARK: - Source interview (/source)

struct SourceInterviewView: View {
    let model: AppModel
    struct Q: Decodable, Identifiable { let id: String; let section: String; let prompt: String }
    struct QSet: Decodable { let sections: [String]; let questions: [Q] }
    @State private var answers: [String: String] = [:]
    @State private var answersLoaded = false

    var body: some View {
        Loaded(load: { try await OS.get("interview", QSet.self, model: model) }) { s, _ in
            List {
                if !answersLoaded {
                    Section { Text("Your saved answers did not load, so answering is closed until they do (it would replace them).").foregroundStyle(.secondary)
                        Button("Try again") { Task { await loadAnswers() } } }
                }
                ForEach(s.sections, id: \.self) { sec in
                    let qs = s.questions.filter { $0.section == sec }
                    NavigationLink {
                        List(qs) { q in
                            NavigationLink { AnswerView(model: model, q: q, answer: answers[q.id] ?? "") { answers[q.id] = $0 } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.prompt).lineLimit(3)
                                    if let a = answers[q.id], !a.isEmpty { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                        }
                        .navigationTitle(sec)
                    } label: {
                        LabeledContent(sec, value: "\(qs.filter { !(answers[$0.id] ?? "").isEmpty }.count) of \(qs.count)")
                    }
                }
            }
        }
        .navigationTitle("Source interview")
        .task { await loadAnswers() }
    }

    private func loadAnswers() async {
        if let a = try? await Console.q("interview", [String: String].self, model: model) { answers = a; answersLoaded = true }
    }

    struct AnswerView: View {
        let model: AppModel
        let q: Q
        @State var answer: String
        let saved: (String) -> Void
        @State private var result: String?

        var body: some View {
            Form {
                Section { Text(q.prompt).font(.headline) }
                Section { TextEditor(text: $answer).frame(minHeight: 240) }
                Button("Save") { Task { await save() } }
                if let r = result { ResultLine(text: r) }
            }
            .navigationTitle(q.section).navigationBarTitleDisplayMode(.inline)
        }

        private func save() async {
            do { try await Console.post("api/pldev/x/interview", ["question_id": q.id, "section": q.section, "answer": answer], model: model); saved(answer); result = "Saved." }
            catch { result = "Not saved. \(error.localizedDescription)" }
        }
    }
}

// MARK: - Comments (/comments)

struct CommentsView: View {
    let model: AppModel
    struct Item: Decodable, Identifiable { let id: String; let account: String; let post: String; let context: String?; let text: String; let written: String? }
    struct Out: Decodable { let items: [Item] }
    @AppStorage("pldev.commentsDone") private var done = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        Loaded(load: { try await OS.get("comments", Out.self, model: model).items }) { items, _ in
            List {
                if items.isEmpty { ContentUnavailableView("No comment drafts", systemImage: "text.bubble") }
                ForEach(items) { it in
                    let posted = done.split(separator: ",").contains(Substring(it.id))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(it.account).font(.headline); Spacer(); if posted { Label("Posted", systemImage: "checkmark").font(.caption).foregroundStyle(.green) } }
                        if let c = it.context { Text(c).font(.caption).foregroundStyle(.secondary) }
                        Text(it.text).plReading()
                        HStack {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = it.text }
                            Button("Open the post", systemImage: "arrow.up.forward.app") { if let u = URL(string: it.post) { openURL(u) } }
                        }
                        .buttonStyle(.bordered).font(.caption)
                    }
                    .opacity(posted ? 0.55 : 1)
                    .swipeActions { Button(posted ? "Not posted" : "Posted") { toggle(it.id) }.tint(.green) }
                }
            }
        }
        .navigationTitle("Comments")
    }

    private func toggle(_ id: String) {
        var s = Set(done.split(separator: ",").map(String.init))
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        done = s.sorted().joined(separator: ",")
    }
}

// MARK: - Catalog matrix (/catalog)

struct CatalogMatrixView: View {
    let model: AppModel
    struct Colorway: Decodable, Hashable { let colorway: String; let hex: String?; let note: String? }
    struct Cell: Decodable, Hashable { let status: String?; let value: String?; let product: String?; let syncProductId: Int? }
    struct Row: Decodable, Hashable { let printfulId: Int?; let blank: String; let role: String?; let techniques: [String]?; let cells: [Cell] }
    struct Design: Decodable, Identifiable { let design: String; let technique: String?; let colorways: [Colorway]; let rows: [Row]; var id: String { design } }
    struct Matrix: Decodable { let generatedAt: String?; let designs: [Design] }
    @State private var search = ""

    var body: some View {
        Loaded(load: { try await OS.get("matrix", Matrix.self, model: model) }) { m, _ in
            List {
                Section { NavigationLink { CatalogQueueView(model: model) } label: { Label("Build queue", systemImage: "hammer") } }
                Section {
                    ForEach(m.designs.filter { search.isEmpty || $0.design.localizedCaseInsensitiveContains(search) }) { d in
                        NavigationLink { DesignMatrix(model: model, d: d) } label: {
                            let cells = d.rows.flatMap(\.cells)
                            let built = cells.filter { $0.syncProductId != nil }.count
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.design)
                                Text("\(d.technique ?? "") · \(built) built · \(cells.count - built) open").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: { if let g = m.generatedAt { Text("Matrix from \(g).") } }
            }
            .searchable(text: $search, prompt: "Design")
        }
        .navigationTitle("Catalog")
    }

    struct DesignMatrix: View {
        let model: AppModel
        let d: Design
        @State private var result: String?

        var body: some View {
            List {
                if let r = result { ResultLine(text: r) }
                ForEach(d.rows, id: \.self) { row in
                    Section(row.role ?? row.blank) {
                        ForEach(Array(zip(d.colorways, row.cells).enumerated()), id: \.offset) { _, pair in
                            let (cw, cell) = pair
                            HStack {
                                Circle().fill(Color(hex: cw.hex) ?? .secondary).frame(width: 14, height: 14)
                                Text(cw.colorway)
                                Spacer()
                                if cell.syncProductId != nil { Text(cell.value ?? "Built").foregroundStyle(.secondary) }
                                else { Text(cell.status == "price" ? (cell.value ?? "") : (cell.value ?? "—")).foregroundStyle(.tertiary) }
                            }
                            .font(.callout)
                            .swipeActions { if cell.syncProductId == nil { Button("Queue") { Task { await queue(row, cw) } }.tint(.orange) } }
                        }
                    }
                }
            }
            .navigationTitle(d.design)
        }

        private func queue(_ row: Row, _ cw: Colorway) async {
            var body: [String: Any] = ["design": d.design, "colorway": cw.colorway, "blank": row.blank, "technique": d.technique ?? ""]
            if let p = row.printfulId { body["printful_product_id"] = p }
            do { try await Console.post("api/catalog-build-queue", body, model: model); result = "\(cw.colorway) \(row.role ?? "") queued for build." }
            catch { result = "Not queued. \(error.localizedDescription)" }
        }
    }
}

extension Color {
    /// "#rrggbb" → a colour; anything else (a gradient string) → nil.
    init?(hex: String?) {
        guard let c = ThemePack.components(hex: hex ?? "") else { return nil }
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

// MARK: - Notion: pipeline, content calendar, latest briefing (the Outbound PipelinePanel and Calendar)

struct NotionView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let name: String; let meta: String?; let url: String?; let pageId: String?; var id: String { pageId ?? name } }
    struct NState: Decodable { let connected: Bool; let pipeline: [String: Int]; let pipelineTotal: Int; let pipelineRows: [Row]; let content: [Row]; let latestBriefing: String? }
    @State private var result: String?

    var body: some View {
        Loaded(load: { try await OS.get("notion", NState.self, model: model) }) { s, reload in
            List {
                if !s.connected { Text("pl-os is not connected to Notion.").foregroundStyle(.secondary) }
                if let r = result { ResultLine(text: r) }
                if let b = s.latestBriefing { Section("Latest briefing") { Text(b) } }
                Section("Pipeline · \(s.pipelineTotal)") {
                    ForEach(s.pipeline.keys.sorted(), id: \.self) { k in LabeledContent(k, value: "\(s.pipeline[k] ?? 0)") }
                }
                Section {
                    ForEach(s.pipelineRows) { r in
                        VStack(alignment: .leading) { Text(r.name); Text(r.meta ?? "").font(.caption).foregroundStyle(.secondary) }
                            .swipeActions { if let id = r.pageId { Button("Advance") { Task { await advance(id, reload) } }.tint(.blue) } }
                    }
                } header: { Text("In the pipeline") } footer: { Text("Swipe to move a piece to its next stage.") }
                Section("Content calendar") {
                    ForEach(s.content) { r in
                        if let u = r.url.flatMap(URL.init(string:)) { Link(destination: u) { VStack(alignment: .leading) { Text(r.name); Text(r.meta ?? "").font(.caption) } } }
                        else { Text(r.name) }
                    }
                }
            }
        }
        .navigationTitle("Pipeline")
    }

    private func advance(_ id: String, _ reload: () async -> Void) async {
        struct R: Decodable { let from: String?; let to: String? }
        do {
            let r = try JSONDecoder().decode(R.self, from: try await Console.post("api/pipeline/advance", ["page_id": id], model: model))
            result = "Moved \(r.from ?? "") → \(r.to ?? "")."; await reload()
        } catch { result = "Not moved. \(error.localizedDescription)" }
    }
}

// MARK: - Craft room (/craft): the "Wouldn't it be nice" game and archive captions

struct CraftView: View {
    let model: AppModel
    // the web's prompts, word for word (pl-os components/CraftRoom.tsx)
    private static let game = "You write for Psyched Luxuries — a philosophy-first wearable art brand built on a seven-year daily practice. The founder plays 'Wouldn't It Be Nice': he names a desire softly, and you return it as ONE sovereign declaration — present tense, already true, in house voice: declarative, earned certainty, spare and weighted. Grounded in the Three Truths: Prepared for luxury. You are in control of your reality. What persists in the mind becomes your reality. One to three sentences. Never use: excited, honored, blessed, check out, amazing, unique, limited, exclusive, manifest. No exclamation marks. No questions. Output ONLY the declaration."
    private static let caption = "You write Psyched Luxuries social captions — declarative, spare, catalogue-register voice. The piece is one mark in a seven-year unbroken daily practice; the archive is proof of a mind that did not stop. Never use 'excited', 'amazing', 'unique', 'exclusive', 'limited', or the word 'manifest'. No questions, no exclamation marks. Never invent facts: no dimensions, no medium or materials beyond what is given, no provenance, no certificates, no ownership claims. Only the facts provided and the practice itself. Write ONE caption of 1 to 3 short paragraphs. End with the line 'Watch this.' Output ONLY the caption text — no preamble, no quotation marks."

    struct Piece: Decodable, Identifiable, Hashable { let cr: String; let url: String; let thumb: String?; let title: String?; let year: Int?; let medium: String?; let shareable: Bool?; var id: String { cr } }
    struct Manifest: Decodable { let pieces: [Piece] }
    @State private var desire = ""
    @State private var declaration = ""
    @State private var pieces: [Piece] = []
    @State private var picked: Piece?
    @State private var text = ""
    @State private var voice = ""
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("…the archive hung in a room with tall windows", text: $desire, axis: .vertical).lineLimit(2...4)
                Button("Say it") { Task { await play() } }.disabled(desire.isEmpty || busy)
                if !declaration.isEmpty {
                    Text(declaration).plHand(26)
                    Button("Capture it") { Task { await capture() } }.disabled(busy)
                }
            } header: { Text("Wouldn't it be nice if…") }
            Section("Caption a piece from the archive") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(pieces.prefix(60)) { p in
                            Button { picked = p; text = ""; voice = "" } label: {
                                AsyncImage(url: URL(string: p.thumb ?? p.url)) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                                    .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(picked == p ? Color.orange : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.title ?? p.cr)
                        }
                    }
                }
                .frame(height: 90)
                if let p = picked {
                    Text([p.title ?? p.cr, p.year.map { "made \($0)" }, p.medium].compactMap { $0 }.joined(separator: ", ")).font(.caption)
                    Button("Write the caption") { Task { await craft(p) } }.disabled(busy)
                }
                if !text.isEmpty {
                    TextEditor(text: $text).frame(minHeight: 160)
                    if !voice.isEmpty { Text(voice).font(.caption).foregroundStyle(.secondary) }
                    Button("Add to Approvals") { Task { await queue() } }.disabled(busy)
                }
            }
            if let r = result { Section { ResultLine(text: r) } }
        }
        .navigationTitle("Craft")
        .disabled(busy)
        .task {
            if let r = try? await URLSession.shared.data(from: URL(string: "https://assets.psychedluxuries.com/manifest.json")!),
               let m = try? JSONDecoder().decode(Manifest.self, from: r.0) { pieces = m.pieces.filter { $0.shareable != false } }
        }
    }

    private func llm(_ system: String, _ prompt: String) async throws -> String {
        struct R: Decodable { let response: String?; let error: String? }
        let r = try JSONDecoder().decode(R.self, from: try await Console.post("api/llm", ["system": system, "prompt": prompt, "max_tokens": 400], model: model, timeout: 60))
        guard let t = r.response, !t.isEmpty else { throw Console.Problem.refused(r.error ?? "No words came back.") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func play() async {
        busy = true; defer { busy = false }
        do { declaration = try await llm(Self.game, "Wouldn't it be nice if \(desire)") } catch { result = "The room is quiet right now. Try again in a moment." }
    }

    private func capture() async {
        busy = true; defer { busy = false }
        do { try await Console.post("api/pldev/x/intake", ["type": "text", "note": "Wouldn't it be nice if \(desire)\n\n\(declaration)"], model: model); result = "Captured." }
        catch { result = "Not captured. \(error.localizedDescription)" }
    }

    private func craft(_ p: Piece) async {
        busy = true; defer { busy = false }
        let facts = [p.title ?? p.cr, p.year.map { "made \($0)" }, p.medium].compactMap { $0 }.joined(separator: ", ")
        do {
            text = try await llm(Self.caption, "The piece: \(facts) (\(p.cr)). Write the caption.")
            if let d = try? await Console.post("api/voicecheck", ["text": text], model: model) { voice = String(data: d, encoding: .utf8) ?? "" }
        } catch { result = "The room is quiet right now. Try again in a moment." }
    }

    private func queue() async {
        guard let p = picked else { return }
        busy = true; defer { busy = false }
        do { try await Console.post("api/drafts/create", ["id": "craft-\(UUID().uuidString.prefix(8).lowercased())", "caption": text, "media_url": p.url, "platform": "instagram"], model: model); result = "Added. It waits in Approvals." }
        catch { result = "Not added. \(error.localizedDescription)" }
    }
}
