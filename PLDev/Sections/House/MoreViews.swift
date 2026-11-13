import SwiftUI

/// More: the console's rooms (/catalog, /merch, /precedent, Council, /ops, corpus search, crew, academy) and its
/// system drawer (stack health, automation run-now, costs, agent and notification logs, the capture trail).
/// GlyphBot (/oracle) and the board (/jarvis) become their own apps in the build order.
struct MoreTab: View {
    let model: AppModel

    var body: some View {
        List {
            Section("Rooms") {
                NavigationLink { CouncilView(model: model) } label: { Label("Council", systemImage: "person.3.sequence") }
                NavigationLink { OpsView(model: model) } label: { Label("Ops", systemImage: "questionmark.bubble") }
                NavigationLink { CorpusView(model: model) } label: { Label("Search the corpus", systemImage: "text.magnifyingglass") }
                NavigationLink { CraftView(model: model) } label: { Label("Craft", systemImage: "wand.and.stars") }
                NavigationLink { CodexToolView(model: model) } label: { Label("Codex", systemImage: "book.closed") }
                NavigationLink { SourceInterviewView(model: model) } label: { Label("Source interview", systemImage: "quote.bubble") }
                NavigationLink { CommentsView(model: model) } label: { Label("Comments to post", systemImage: "text.bubble") }
                NavigationLink { MerchView(model: model) } label: { Label("Merch calendar", systemImage: "tshirt") }
                NavigationLink { CatalogMatrixView(model: model) } label: { Label("Catalog", systemImage: "square.grid.3x3") }
                NavigationLink { AtlasView(model: model) } label: { Label("Atlas", systemImage: "map") }
                NavigationLink { PrecedentView(model: model) } label: { Label("Precedent", systemImage: "photo.on.rectangle.angled") }
                NavigationLink { CrewView(model: model) } label: { Label("Crew", systemImage: "figure.2") }
                Link(destination: URL(string: "https://pl-academy.psychedluxuries.workers.dev")!) { Label("Academy", systemImage: "graduationcap") }
            }
            Section("System") {
                NavigationLink { StackHealthView(model: model) } label: { Label("Stack health", systemImage: "stethoscope") }
                NavigationLink { AutomationView(model: model) } label: { Label("Run a job now", systemImage: "play.circle") }
                NavigationLink { CostView(model: model) } label: { Label("Costs and revenue", systemImage: "dollarsign.circle") }
                NavigationLink { LogView(model: model, kind: .agent) } label: { Label("Agent log", systemImage: "list.bullet.rectangle") }
                NavigationLink { LogView(model: model, kind: .notifications) } label: { Label("Notifications sent", systemImage: "bell.badge") }
                NavigationLink { LogView(model: model, kind: .captures) } label: { Label("Where captures went", systemImage: "arrow.triangle.branch") }
            }
        }
    }
}

// MARK: - Council, Ops, corpus search

struct CouncilView: View {
    let model: AppModel
    private let seats = [("research", "Research", "Trend reads, signal analysis"), ("content", "Content", "Captions and drafts"),
                         ("strategist", "Strategist", "Options and direction"), ("language", "Language", "Paste copy to check the voice")]
    @State private var seat = "research"
    @State private var query = ""
    @State private var answer: String?
    @State private var busy = false

    var body: some View {
        Form {
            Picker("Seat", selection: $seat) { ForEach(seats, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
            Section {
                TextField(seats.first { $0.0 == seat }?.2 ?? "", text: $query, axis: .vertical).lineLimit(3...10)
                Button(busy ? "Asking…" : "Ask the \(seats.first { $0.0 == seat }?.1 ?? "") seat") { Task { await ask() } }.disabled(query.isEmpty || busy)
            }
            if let answer { Section("Answer") { Text(answer).plReading().textSelection(.enabled) } }
        }
        .navigationTitle("Council")
    }

    private func ask() async {
        busy = true; defer { busy = false }
        struct R: Decodable { let response: String?; let error: String? }
        do {
            let r = try JSONDecoder().decode(R.self, from: try await Console.post("api/council-route", ["seat": seat, "query": query], model: model, timeout: 90))
            answer = r.response ?? r.error ?? "No answer came back."
        } catch { answer = "Not answered. \(error.localizedDescription)" }
    }
}

struct OpsView: View {
    let model: AppModel
    struct Turn: Identifiable { let id = UUID(); let you: Bool; let text: String }
    @State private var turns: [Turn] = []
    @State private var q = ""
    @State private var busy = false

    var body: some View {
        List {
            if turns.isEmpty { Text("Ask how anything in the house works: a job, a route, a number.").foregroundStyle(.secondary) }
            ForEach(turns) { t in
                Text(t.text).plReading().textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: t.you ? .trailing : .leading)
                    .background(t.you ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowSeparator(.hidden)
            }
            if busy { ProgressView() }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Ask Ops", text: $q, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(q.isEmpty || busy).accessibilityLabel("Ask")
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle("Ops")
    }

    private func ask() async {
        let question = q; q = ""; busy = true; defer { busy = false }
        let history = turns.map { ["role": $0.you ? "user" : "assistant", "content": $0.text] }
        turns.append(Turn(you: true, text: question))
        struct R: Decodable { let answer: String?; let error: String? }
        do {
            let r = try JSONDecoder().decode(R.self, from: try await Console.post("api/ops-ai", ["question": question, "history": history], model: model, timeout: 90))
            turns.append(Turn(you: false, text: r.answer ?? r.error ?? "No answer."))
        } catch { turns.append(Turn(you: false, text: "Not answered. \(error.localizedDescription)")) }
    }
}

struct CorpusView: View {
    let model: AppModel
    struct Hit: Decodable, Identifiable { let id: Int; let source: String?; let lens: String?; let date: String?; let label: String?; let principle: String?; let quote: String?; let note: String? }
    struct Out: Decodable { let results: [Hit]?; let error: String? }
    struct Stats: Decodable { let archive_count: Int?; let corpus_fragments: Int?; let corpus_conversations: Int? }
    @State private var q = ""
    @State private var lens = "all"
    @State private var hits: [Hit] = []
    @State private var stats: Stats?
    @State private var searched = false

    var body: some View {
        List {
            Picker("Lens", selection: $lens) { ForEach(["all", "doctrine", "voice", "record", "vault"], id: \.self) { Text($0.capitalized).tag($0) } }
                .pickerStyle(.segmented)
            if searched && hits.isEmpty { ContentUnavailableView.search(text: q) }
            ForEach(hits) { h in
                VStack(alignment: .leading, spacing: 4) {
                    if let p = h.principle { Text(p).font(.headline) }
                    if let quote = h.quote { Text("“\(quote)”").italic() }
                    if let n = h.note { Text(n).font(.callout) }
                    Text([h.lens, h.label, h.source, h.date].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }
            if let s = stats {
                Section { Text("\(s.corpus_fragments ?? 0) fragments from \(s.corpus_conversations ?? 0) conversations · \(s.archive_count ?? 0) archive pieces").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .searchable(text: $q, prompt: "What did he say about…")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: lens) { if !q.isEmpty { Task { await search() } } }
        .navigationTitle("Corpus")
        .task { stats = try? await Console.get("api/stats", Stats.self, model: model) }
    }

    private func search() async {
        var query = ["q": q, "limit": "8"]
        if lens != "all" { query["lens"] = lens }
        hits = (try? await Console.get("api/search", Out.self, model: model, query: query).results) ?? []
        searched = true
    }
}

// MARK: - Merch, catalog queue, precedent, crew

struct MerchView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let product_name: String; var season: String; let updated_at: String?; var id: String { product_name } }
    struct Candidate: Decodable, Identifiable { let name: String; let placement: String?; let slug: String?; let image: String?; let group: String?; var id: String { (slug ?? "") + name } }
    struct C: Decodable { let items: [Candidate]? }
    struct Ask: Decodable, Identifiable { let question_id: String; let answer_id: String; let n: Int; var id: String { question_id + answer_id } }
    @State private var rows: [Row] = []
    @State private var candidates: [Candidate] = []
    @State private var asks: [Ask] = []
    @State private var result: String?
    private let seasons = [("fw", "Fall / Winter"), ("ss", "Spring / Summer"), ("always", "Always"), ("rest", "Resting")]
    /// fw = Sep 1 to the end of Feb, ss = Mar 1 to Aug 31 (pl-headless isOutOfSeason).
    private var nowSeason: String { let m = Calendar.current.component(.month, from: .now); return (m >= 9 || m <= 2) ? "fw" : "ss" }
    private func onGrid(_ season: String) -> Bool { season == "always" || season == nowSeason }

    var body: some View {
        List {
            if let r = result { ResultLine(text: r) }
            Section {
                LabeledContent("Now", value: nowSeason == "fw" ? "Fall / Winter" : "Spring / Summer")
                LabeledContent("Next switch", value: nowSeason == "fw" ? "Mar 1" : "Sep 1")
            } footer: { Text("Black and white bases are always live. A resting colourway leaves the grid but stays buyable by its own link.") }
            Section("Colourways") {
                ForEach($rows) { $r in
                    Picker(selection: Binding(get: { r.season }, set: { v in r.season = v; Task { await save(r.product_name, v) } })) {
                        ForEach(seasons, id: \.0) { Text($0.1).tag($0.0) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.product_name)
                            Text(onGrid(r.season) ? "ON THE GRID" : "RESTING").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(onGrid(r.season) ? Color.green : Color.secondary)
                        }
                    }
                }
            }
            if !candidates.isEmpty {
                Section("Drop candidates · unlisted and hidden") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(candidates) { c in
                            VStack(spacing: 4) {
                                AsyncImage(url: c.image.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.12) }
                                    .frame(height: 96)
                                Text(c.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                                Text(c.placement ?? "").font(.caption2.bold()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !asks.isEmpty {
                Section("The Ask on /shop") {
                    ForEach(asks) { a in LabeledContent("\(a.question_id) · \(a.answer_id)", value: "\(a.n)") }
                }
            }
        }
        .navigationTitle("Merch")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        rows = (try? await Console.q("merch", [Row].self, model: model)) ?? rows
        candidates = (try? await Console.get("api/drop-candidates", C.self, model: model, timeout: 40).items) ?? candidates
        asks = (try? await Console.q("asktally", [Ask].self, model: model)) ?? asks
    }

    private func save(_ name: String, _ season: String) async {
        struct R: Decodable { let message: String? }
        do { result = (try? JSONDecoder().decode(R.self, from: try await Console.post("api/pldev/x/merch", ["product_name": name, "season": season], model: model)))?.message ?? "Saved." }
        catch { result = "Not saved. \(error.localizedDescription)"; await load() }
    }
}

struct CatalogQueueView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let id: String; let design: String?; let colorway: String?; let blank: String?; let technique: String?; let tier_price: Int?; let queued_at: String?; let built_at: String?; let sync_product_id: Int?; let note: String? }
    struct Out: Decodable { let rows: [Row]? }
    @State private var building: Row?
    @State private var syncId = ""
    @State private var result: String?

    var body: some View {
        Loaded(load: { try await Console.get("api/catalog-build-queue", Out.self, model: model).rows ?? [] }) { rows, reload in
            List {
                if let r = result { ResultLine(text: r) }
                let waiting = rows.filter { $0.built_at == nil }
                Section("Waiting to build · \(waiting.count)") {
                    ForEach(waiting) { r in row(r).swipeActions { Button("Built") { building = r }.tint(.green) } }
                }
                Section("Built") { ForEach(rows.filter { $0.built_at != nil }) { row($0) } }
            }
            .alert("Mark \(building?.design ?? "") built", isPresented: Binding(get: { building != nil }, set: { if !$0 { building = nil } })) {
                TextField("Printful sync product id", text: $syncId).keyboardType(.numberPad)
                Button("Mark built") { if let b = building { Task { await built(b, reload) } } }
                Button("Cancel", role: .cancel) {}
            }
        }
        .navigationTitle("Catalog queue")
    }

    private func row(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(r.design ?? "") · \(r.colorway ?? "")").font(.headline)
            Text([r.blank, r.technique, r.tier_price.map { "$\($0)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            if let n = r.note, !n.isEmpty { Text(n).font(.caption) }
        }
    }

    private func built(_ r: Row, _ reload: () async -> Void) async {
        var body: [String: Any] = [:]
        if let n = Int(syncId) { body["sync_product_id"] = n }
        do { try await Console.post("api/catalog-build-queue/\(r.id)/built", body, model: model); result = "Marked built."; syncId = ""; await reload() }
        catch { result = "Not saved. \(error.localizedDescription)" }
    }
}

struct PrecedentView: View {
    let model: AppModel
    struct Item: Decodable, Identifiable { let slug: String; let source: String?; let surface: String?; let viewport: String?; let tongue: String?; let pattern: String?; let note: String?; let r2_key: String?; var id: String { slug } }
    struct Out: Decodable { let items: [Item]? }
    @State private var open: Item?

    var body: some View {
        Loaded(load: { try await Console.get("api/precedent", Out.self, model: model).items ?? [] }) { items, _ in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(items) { it in
                        Button { open = it } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: url(it)) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                                    .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(it.pattern ?? it.slug).font(.caption.bold()).lineLimit(1)
                                Text([it.tongue, it.viewport].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .sheet(item: $open) { it in
                NavigationStack {
                    ScrollView {
                        AsyncImage(url: url(it)) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        Text(it.note ?? "").padding()
                    }
                    .navigationTitle(it.pattern ?? it.slug).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { open = nil } }
                }
            }
        }
        .navigationTitle("Precedent")
    }

    private func url(_ it: Item) -> URL? { it.r2_key.flatMap { URL(string: "https://assets.psychedluxuries.com/\($0)") } }
}

struct CrewView: View {
    let model: AppModel
    struct Member: Decodable, Identifiable { let agent: String; let n: Int?; let last: String?; let last_job: String?; var id: String { agent } }
    struct Out: Decodable { let crew: [Member]? }
    var body: some View {
        Loaded(load: { try await Console.get("api/crew", Out.self, model: model).crew ?? [] }) { crew, _ in
            List(crew) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(m.agent).font(.headline); Spacer(); Text("\(m.n ?? 0) runs").font(.caption).monospacedDigit() }
                    HStack { Text(m.last_job ?? ""); Spacer(); Ago(text: m.last) }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Crew")
    }
}

// MARK: - System drawer

struct StackHealthView: View {
    let model: AppModel
    struct Result: Decodable { let pass: Bool; let latency: Int?; let error: String? }
    struct Run: Decodable, Identifiable { let id: String; let ran_at: String?; let results: [String: Result]?; let all_pass: Bool?; let summary: String? }
    struct Latest: Decodable { let data: Run? }
    @State private var latest: Run?
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        List {
            if let r = result { ResultLine(text: r) }
            if let l = latest {
                Section {
                    Label(l.all_pass == true ? "Every check passed" : "Something failed", systemImage: l.all_pass == true ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(l.all_pass == true ? .green : .red)
                    if let s = l.summary { Text(s).font(.callout) }
                    HStack { Text("Ran"); Spacer(); Ago(text: l.ran_at) }.foregroundStyle(.secondary)
                }
                Section("Checks") {
                    ForEach((l.results ?? [:]).keys.sorted(), id: \.self) { k in
                        let r = l.results?[k]
                        HStack {
                            Image(systemName: r?.pass == true ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r?.pass == true ? .green : .red)
                            Text(k)
                            Spacer()
                            if let ms = r?.latency { Text("\(ms) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Button(busy ? "Running… about a minute" : "Run the checks now") { Task { await run() } }.disabled(busy)
        }
        .navigationTitle("Stack health")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async { latest = (try? await Console.get("run/stack-health/latest", Latest.self, model: model))?.data }
    private func run() async { busy = true; result = await Console.run("run/stack-health", model: model); busy = false; await load() }
}

struct AutomationView: View {
    let model: AppModel
    private let jobs = [("run/digest", "Morning digest", "sun.horizon"), ("run/ig-insights", "Instagram numbers", "chart.line.uptrend.xyaxis"),
                        ("run/content-wave", "Content wave", "water.waves"), ("run/captures", "Sort the captures", "tray.and.arrow.down"),
                        ("run/stack-health", "Stack health", "stethoscope")]
    @State private var running: String?
    @State private var results: [String: String] = [:]

    var body: some View {
        List {
            ForEach(jobs, id: \.0) { j in
                Button { Task { running = j.0; results[j.0] = await Console.run(j.0, model: model); running = nil } } label: {
                    HStack {
                        Label(j.1, systemImage: j.2)
                        Spacer()
                        if running == j.0 { ProgressView() } else if let r = results[j.0] { Text(r).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                .disabled(running != nil)
            }
        }
        .navigationTitle("Run a job")
    }
}

struct CostView: View {
    let model: AppModel
    struct Line: Decodable, Identifiable { let label: String; let value: Double; var id: String { label } }
    struct Cost: Decodable { let recurringMonthly: [Line]?; let oneTimeTotal: Double?; let revenueAllTime: Double?; let revenue30d: Double?; let orderCountAllTime: Int?; let orderCount30d: Int?; let aovAllTime: Double?; let aov30d: Double? }
    var body: some View {
        Loaded(load: { try await Console.q("cost", Cost.self, model: model) }) { c, _ in
            List {
                Section("Revenue") {
                    LabeledContent("Last 30 days", value: (c.revenue30d ?? 0).formatted(.currency(code: "USD")))
                    LabeledContent("All time", value: (c.revenueAllTime ?? 0).formatted(.currency(code: "USD")))
                    LabeledContent("Orders", value: "\(c.orderCount30d ?? 0) in 30 days · \(c.orderCountAllTime ?? 0) all time")
                    LabeledContent("Average order", value: (c.aovAllTime ?? 0).formatted(.currency(code: "USD")))
                }
                Section {
                    ForEach(c.recurringMonthly ?? []) { LabeledContent($0.label, value: $0.value.formatted(.currency(code: "USD"))) }
                    LabeledContent("Monthly total", value: (c.recurringMonthly ?? []).reduce(0) { $0 + $1.value }.formatted(.currency(code: "USD")))
                    LabeledContent("Spent once", value: (c.oneTimeTotal ?? 0).formatted(.currency(code: "USD")))
                } header: { Text("Costs") } footer: { Text("The recurring costs are kept by hand, as in pl-os; there is no billing feed.") }
            }
        }
        .navigationTitle("Costs")
    }
}

struct LogView: View {
    enum Kind { case agent, notifications, captures }
    let model: AppModel
    let kind: Kind
    struct Row: Decodable, Identifiable {
        let agent: String?; let job: String?; let result: String?; let ran_at: String?
        let title: String?; let message: String?; let created_at: String?
        let type: String?; let payload: String?; let status: String?; let source: String?; let pool_key: String?
        let rid = UUID()
        var id: UUID { rid }
        private enum CodingKeys: String, CodingKey { case agent, job, result, ran_at, title, message, created_at, type, payload, status, source, pool_key }
    }

    var body: some View {
        Loaded(load: { try await Console.q(kind == .agent ? "agentlog" : kind == .notifications ? "notifications" : "capturetrail", [Row].self, model: model) }) { rows, _ in
            List(rows) { r in
                VStack(alignment: .leading, spacing: 3) {
                    switch kind {
                    case .agent:
                        HStack { Text(r.agent ?? "").font(.headline); Spacer(); Ago(text: r.ran_at).font(.caption) }
                        Text(r.job ?? "").font(.callout)
                        Text(r.result ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(4)
                    case .notifications:
                        HStack { Text(r.title ?? "").font(.headline); Spacer(); Ago(text: r.created_at).font(.caption) }
                        Text(r.message ?? "").font(.callout).lineLimit(5)
                    case .captures:
                        HStack { Text((r.status ?? "").capitalized).font(.caption.bold()); Spacer(); Ago(text: r.created_at).font(.caption) }
                        Text(r.payload ?? "").lineLimit(3)
                        Text([r.type, r.source, r.pool_key.map { _ in "in the research pool" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }
        }
        .navigationTitle(kind == .agent ? "Agent log" : kind == .notifications ? "Notifications" : "Captures")
    }
}
