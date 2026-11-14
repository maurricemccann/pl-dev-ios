import SwiftUI

/// The Persona Academy, native. pl-os `/academy` is the hub (header, four rooms, the seven-section curriculum) and the Worker
/// `pl-academy` is the instrument behind it: the canon reader, the Oracle, the Prompt Forge and the Persona Drills. All four work here
/// against the live Worker, with no web view. Source: `C:\dev\pl-academy\src\index.ts` + `drills.ts`, `C:\dev\pl-os\app\academy\page.tsx`.
/// The Worker is public (it answers anyone), so there is no key; its address is already in this repo's earlier Link.
@MainActor enum Academy {
    static let base = URL(string: "https://pl-academy.psychedluxuries.workers.dev")!

    enum Problem: LocalizedError {
        case unreachable, refused(String)
        var errorDescription: String? {
            switch self {
            case .unreachable: return "The Academy did not answer. Check your connection."
            case .refused(let why): return why
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    private static var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("academy", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func cacheFile(_ key: String) -> URL {
        let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return cacheDir.appendingPathComponent(String(safe.suffix(120)) + ".html")
    }

    /// A page, answered from the copy kept on the phone when the Worker cannot be reached (the canon is read offline).
    static func page(_ path: String, query: [String: String] = [:]) async throws -> String {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let key = path + (query["k"] ?? "")
        do {
            let (data, resp) = try await session.data(from: c.url!)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { throw Problem.unreachable }
            try? data.write(to: cacheFile(key))
            return text
        } catch {
            if let d = try? Data(contentsOf: cacheFile(key)), let t = String(data: d, encoding: .utf8) { return t }
            throw Problem.unreachable
        }
    }

    /// A POST that answers JSON. Throws with the Worker's own sentence when it says no (rate limit, grader down).
    static func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw Problem.unreachable }
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw Problem.refused("Slow down: today's limit is reached.") }
        if !(200..<300).contains(status) && o["error"] != nil { throw Problem.refused(o["error"] as? String ?? "The Academy said no.") }
        if !(200..<300).contains(status) && status != 409 { throw Problem.refused("The Academy said no (\(status)).") }
        return o
    }

    // MARK: kept on the phone (the page keeps these in localStorage; same shapes)

    private static func dict<T>(_ key: String) -> [String: T] {
        guard let d = UserDefaults.standard.data(forKey: key), let o = try? JSONSerialization.jsonObject(with: d) as? [String: T] else { return [:] }
        return o
    }
    private static func save(_ key: String, _ value: Any) {
        if let d = try? JSONSerialization.data(withJSONObject: value) { UserDefaults.standard.set(d, forKey: key) }
    }
    static var read: [String: Double] { dict("pl-academy-read") }
    static func toggleRead(_ key: String) { var r = read; if r[key] != nil { r.removeValue(forKey: key) } else { r[key] = Date().timeIntervalSince1970 }; save("pl-academy-read", r) }
    static var claimed: [String: Bool] { dict("pl-academy-claimed") }
    static func setClaimed(_ id: String) { var c = claimed; c[id] = true; save("pl-academy-claimed", c) }
    static var email: String { get { UserDefaults.standard.string(forKey: "pl-academy-email") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "pl-academy-email") } }
    static var drillScore: [String: [String: Int]] { dict("pl-academy-drills") }
    static func bump(_ drill: String, correct: Bool) {
        var s = drillScore
        var d = s[drill] ?? ["done": 0, "correct": 0]
        d["done", default: 0] += 1
        if correct { d["correct", default: 0] += 1 }
        s[drill] = d
        save("pl-academy-drills", s)
    }
}

// MARK: - The hub (pl-os /academy)

struct AcademyView: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var sections: [AcademyHTML.Section] = []
    @State private var live: Bool?
    @State private var tick = 0

    /// pl-os's own seven, with its own blurbs (the hub page's SECTIONS).
    private let hub: [(id: String, roman: String, title: String, blurb: String)] = [
        ("doctrine", "I", "Doctrine", "The Three Truths: sequential. Preparation, Control, Persistence. Begin here."),
        ("language", "II", "Sovereign Language", "How the brand speaks. What it refuses to say. Voice is law, not preference."),
        ("visual", "III", "Visual Canon", "The glyph system and visual lexicon. Marks carry meaning before style."),
        ("seeds", "IV", "Seeds", "Seed phrases: compressed doctrine, ready to plant."),
        ("territory", "V", "Territory & Strategy", "Mental luxuries. The Congregation. The psychology of the stop."),
        ("craft", "VI", "Craft & Operations", "The crafting doctrine and the operating rules that keep the work honest."),
        ("codex", "VII", "The Master Codex", "260-question foundation. Not a single sitting. Return for the rest of the practice."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Persona Academy").plHand(24, relativeTo: .title2).foregroundStyle(PLOS.goldDim(scheme))
                        Text("16-concept curriculum · CF AI 70b · The Study").osEyebrow(9).foregroundStyle(PLOS.dim(scheme))
                    }
                    Spacer()
                    Text(live == nil ? "…" : live == true ? "\u{25CF} live" : "\u{25CB} unreachable")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(live == true ? Color(hex: 0xa8d4a0) : live == false ? Color(hex: 0xc98a8a) : PLOS.dim(scheme))
                }
                .osCard(padding: 14)

                Text("Rooms").osEyebrow(10).foregroundStyle(PLOS.dim(scheme)).frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    room("Reader", "curriculum · 7 sections", "book.closed") { AcademyCanonView(sections: sections) }
                    room("Oracle", "ask the doctrine", "sparkles") { AcademyOracleView() }
                    room("Forge", "generate from the canon", "flame") { AcademyForgeView() }
                    room("Drills", "rewrite exercises", "pencil.and.list.clipboard") { AcademyDrillsView() }
                }

                Text("Curriculum").osEyebrow(10).foregroundStyle(PLOS.dim(scheme)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                VStack(spacing: 8) {
                    ForEach(hub, id: \.id) { s in
                        let docs = sections.first { $0.id == s.id }?.docs ?? []
                        let done = docs.filter { Academy.read[$0.key] != nil }.count
                        NavigationLink { AcademySectionView(section: sections.first { $0.id == s.id }, fallbackTitle: s.title).osScreen() } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Text(s.roman).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).frame(width: 26, alignment: .leading).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.title).font(.subheadline).foregroundStyle(PLOS.text(scheme))
                                    Text(s.blurb).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).multilineTextAlignment(.leading)
                                    if !docs.isEmpty { Text("\(done) of \(docs.count) absorbed").osEyebrow(9).foregroundStyle(PLOS.goldDim(scheme)).padding(.top, 2) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(PLOS.goldDim(scheme)).padding(.top, 4)
                            }
                            .osCard(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("pl-academy.psychedluxuries.workers.dev").font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).opacity(0.6)
                    Spacer()
                    Text("Watch this.").plHand(18, relativeTo: .callout).foregroundStyle(PLOS.goldDim(scheme))
                }
                .osCard(padding: 14)
            }
            .padding(.horizontal, 14).padding(.bottom, 24)
            .id(tick)
        }
        .navigationTitle("Academy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onAppear { tick += 1 }   // absorbed counts come back up to date after reading
    }

    private func load() async {
        do { sections = AcademyHTML.curriculum(fromHome: try await Academy.page("")); live = !sections.isEmpty }
        catch { live = false }
    }

    private func room<D: View>(_ title: String, _ sub: String, _ symbol: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest().osScreen() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title3).foregroundStyle(PLOS.gold)
                Text(title).osEyebrow(11).foregroundStyle(PLOS.text(scheme))
                Text(sub).font(.system(size: 11)).foregroundStyle(PLOS.dim(scheme)).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).osCard(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Canon (the Worker's home) and a section

struct AcademyCanonView: View {
    let sections: [AcademyHTML.Section]
    @Environment(\.colorScheme) private var scheme
    @State private var email = Academy.email
    @State private var draft = ""
    @State private var tick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let all = sections.flatMap(\.docs)
                let done = all.filter { Academy.read[$0.key] != nil }.count
                Text("\(done) of \(all.count) absorbed").osEyebrow(10).foregroundStyle(PLOS.goldDim(scheme))
                emailGate
                if sections.isEmpty {
                    ContentUnavailableView("The canon is not loaded", systemImage: "book.closed", description: Text("Pull down to try again. Once read, documents stay on the phone."))
                }
                ForEach(sections) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.title).osEyebrow(12).foregroundStyle(PLOS.gold)
                        Text(s.blurb).font(.system(.callout, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme))
                        ForEach(s.docs) { d in docRow(d, section: s) }
                        ClaimRow(section: s, email: email)
                    }
                    .osCard(padding: 14)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 24)
            .id(tick)
        }
        .navigationTitle("Reader")
        .onAppear { tick += 1 }
    }

    private var emailGate: some View {
        Group {
            if email.isEmpty {
                HStack {
                    TextField("your@email.com", text: $draft).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Link") { let v = draft.trimmingCharacters(in: .whitespaces).lowercased(); if v.contains("@") { email = v; Academy.email = v } }
                        .buttonStyle(OSPill())
                }
                .padding(12).background(PLOS.surface2(scheme).opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Track your climb: link the email you use on the site.").font(.footnote).foregroundStyle(PLOS.dim(scheme))
            } else {
                HStack {
                    Text("Climb tracked · \(email)").font(.footnote).foregroundStyle(PLOS.dim(scheme))
                    Spacer()
                    Button("Change") { email = ""; Academy.email = "" }.font(.footnote)
                }
            }
        }
    }

    private func docRow(_ d: AcademyHTML.Doc, section: AcademyHTML.Section) -> some View {
        NavigationLink { AcademyReaderView(doc: d, sectionTitle: section.title).osScreen() } label: {
            HStack(spacing: 12) {
                Text("\u{25C6}").foregroundStyle(Academy.read[d.key] != nil ? PLOS.gold : PLOS.line(scheme)).font(.footnote)
                Text(d.name).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Claim 200 pts" appears when every document of a section is absorbed and an email is linked (the page's claim row).
struct ClaimRow: View {
    let section: AcademyHTML.Section
    let email: String
    @Environment(\.colorScheme) private var scheme
    @State private var busy = false
    @State private var note = ""
    @State private var claimed = false

    var body: some View {
        let all = section.docs.allSatisfy { Academy.read[$0.key] != nil }
        if all && !email.isEmpty {
            HStack(spacing: 12) {
                Button {
                    Task { await claim() }
                } label: { Text(claimed || Academy.claimed[section.id] == true ? "Absorbed \u{25C6}" : busy ? "…" : "\u{25C6} Claim 200 pts") }
                    .buttonStyle(OSPill())
                    .disabled(busy || claimed || Academy.claimed[section.id] == true)
                Text(Academy.claimed[section.id] == true && note.isEmpty ? "200 pts earned" : note).font(.footnote).foregroundStyle(PLOS.dim(scheme))
            }
            .sensoryFeedback(PLHaptic.success, trigger: claimed)
        }
    }

    private func claim() async {
        busy = true; defer { busy = false }
        do {
            let j = try await Academy.post("api/complete", ["email": email, "sectionId": section.id])
            if (j["ok"] as? Bool) == true || (j["already"] as? Bool) == true {
                Academy.setClaimed(section.id); claimed = true
                let pts = j["points"].map { "\($0)" } ?? ""
                note = (j["already"] as? Bool) == true ? "Already earned · \(pts) pts total" : "\(j["granted"] ?? 200) pts · now \(pts) total\((j["tier"] as? String).map { " · \($0)" } ?? "")"
            } else { note = (j["error"] as? String) ?? "Could not reach the climb." }
        } catch { note = error.localizedDescription }
    }
}

struct AcademySectionView: View {
    let section: AcademyHTML.Section?
    let fallbackTitle: String
    var body: some View {
        if let section { AcademyCanonView(sections: [section]).navigationTitle(fallbackTitle) }
        else { ContentUnavailableView("Not loaded yet", systemImage: "book.closed", description: Text("Go back and pull down on the Academy to load the canon.")).navigationTitle(fallbackTitle) }
    }
}

// MARK: - The reader

struct AcademyReaderView: View {
    let doc: AcademyHTML.Doc
    let sectionTitle: String
    @Environment(\.colorScheme) private var scheme
    @State private var blocks: [AcademyBlock]?
    @State private var failure: String?
    @State private var absorbed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(sectionTitle).osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
                    Spacer()
                    Button(absorbed ? "Absorbed \u{25C6}" : "Mark absorbed") { Academy.toggleRead(doc.key); absorbed.toggle() }
                        .buttonStyle(OSPill())
                        .sensoryFeedback(PLHaptic.success, trigger: absorbed)
                }
                Text(doc.name).font(.system(.title, design: .serif)).foregroundStyle(PLOS.text(scheme))
                if let blocks {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in block(b) }
                    Button(absorbed ? "Absorbed \u{25C6}" : "Mark absorbed") { Academy.toggleRead(doc.key); absorbed.toggle() }
                        .buttonStyle(OSPill()).padding(.top, 12)
                } else if let failure {
                    ContentUnavailableView("Could not open this", systemImage: "wifi.exclamationmark", description: Text(failure))
                } else { PLLoader().frame(maxWidth: .infinity, minHeight: 120) }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationTitle(doc.name).navigationBarTitleDisplayMode(.inline)
        .task {
            absorbed = Academy.read[doc.key] != nil
            do {
                let page = try await Academy.page("read", query: ["k": doc.key])
                blocks = AcademyHTML.blocks(fromPage: page)
                if blocks?.isEmpty == true { blocks = [.para("This document has no text.")] }
            } catch { failure = error.localizedDescription }
        }
    }

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    @ViewBuilder private func block(_ b: AcademyBlock) -> some View {
        switch b {
        case .heading(let level, let t):
            let ruled = Text(md(t)).font(.system(level <= 1 ? .title2 : level == 2 ? .title3 : .headline, design: .serif))
            ruled.foregroundStyle(level == 2 ? PLOS.gold : PLOS.text(scheme)).padding(.top, level <= 2 ? 10 : 4)
        case .para(let t): Text(md(t)).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading().textSelection(.enabled)
        case .quote(let t):
            Text(md(t)).font(.system(.body, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme)).plReading()
                .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(PLOS.goldDim(scheme)).frame(width: 2) }.textSelection(.enabled)
        case .item(let t, let depth, let mark):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mark).font(.system(.body, design: .serif)).foregroundStyle(PLOS.goldDim(scheme)).frame(width: 22, alignment: .trailing)
                Text(md(t)).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading().textSelection(.enabled)
            }.padding(.leading, CGFloat(depth) * 16)
        case .code(let t):
            ScrollView(.horizontal) { Text(t).font(.system(size: 12, design: .monospaced)).foregroundStyle(PLOS.text(scheme)).padding(12) }
                .background(PLOS.surface2(scheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .rule: Rectangle().fill(PLOS.line(scheme)).frame(height: 1).padding(.vertical, 8)
        case .table(let rows):
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(r.enumerated()), id: \.offset) { _, c in
                                Text(md(c)).font(.system(size: 14, design: .serif)).foregroundStyle(i == 0 ? PLOS.gold : PLOS.text(scheme))
                                    .frame(width: 150, alignment: .leading).padding(8)
                                    .overlay { Rectangle().strokeBorder(PLOS.line(scheme), lineWidth: 0.5) }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Oracle

struct AcademyOracleView: View {
    @Environment(\.colorScheme) private var scheme
    struct Turn: Identifiable { let id = UUID(); let you: Bool; let text: String; var sources: String? = nil }
    @State private var turns: [Turn] = []
    @State private var q = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ask the canon anything. Answers come from the True Codex and the staged brand knowledge.").font(.system(.callout, design: .serif)).foregroundStyle(PLOS.dim(scheme))
                ForEach(turns) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.you ? "You" : "Oracle").osEyebrow(9).foregroundStyle(t.you ? PLOS.dim(scheme) : PLOS.gold)
                        Text(t.text).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading().textSelection(.enabled)
                        if let s = t.sources { Text(s).font(.system(size: 11)).foregroundStyle(PLOS.dim(scheme)) }
                    }
                }
                if busy { PLLoader() }
            }
            .padding(.horizontal, 18).padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Ask the doctrine…", text: $q, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).submitLabel(.send).onSubmit { Task { await ask() } }
                Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(q.trimmingCharacters(in: .whitespaces).isEmpty || busy).accessibilityLabel("Ask")
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle("Oracle")
        .sensoryFeedback(PLHaptic.success, trigger: turns.count)
    }

    private func ask() async {
        let question = q.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !busy else { return }
        q = ""; busy = true; defer { busy = false }
        turns.append(Turn(you: true, text: question))
        do {
            let j = try await Academy.post("api/ask", ["question": question])
            var sources: String?
            if let ps = j["passages"] as? [[String: Any]] {
                var seen: [String] = []
                for s in ps.compactMap({ $0["source"] as? String }) where !seen.contains(s) { seen.append(s) }
                if !seen.isEmpty { sources = "Sources: " + seen.prefix(4).joined(separator: " · ") }
            }
            turns.append(Turn(you: false, text: (j["answer"] as? String) ?? (j["error"] as? String) ?? "The Oracle is silent.", sources: sources))
        } catch { turns.append(Turn(you: false, text: error.localizedDescription == Academy.Problem.unreachable.errorDescription ? "The Oracle could not be reached." : error.localizedDescription)) }
    }
}

// MARK: - Prompt Forge

struct AcademyForgeView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var label = ""
    @State private var text = ""
    @State private var seed = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Prompts for research and thinking. Draw from a deck, or forge a new one from the canon.").font(.system(.callout, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme))
                if !text.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(label).osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
                        Text(text).font(.system(.title3, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading().textSelection(.enabled)
                        ShareLink(item: text) { Label("Share this prompt", systemImage: "square.and.arrow.up").font(.footnote) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).osCard(padding: 18)
                }
                ForEach(AcademyBanks.decks, id: \.id) { d in
                    Button { text = d.prompts.randomElement() ?? ""; label = "\(d.title) deck" } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.title).osEyebrow(12).foregroundStyle(PLOS.gold)
                            Text("\(d.prompts.count) prompts: draw one").font(.footnote).foregroundStyle(PLOS.dim(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).osCard(padding: 16)
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Optional focus: a theme, a decision, a doubt…", text: $seed).textFieldStyle(.roundedBorder).submitLabel(.go).onSubmit { Task { await forge() } }
                    Button(busy ? "Forging…" : "Forge new") { Task { await forge() } }.buttonStyle(OSPill()).disabled(busy)
                    Text("Forged prompts are generated live against the brand canon. Decks are fixed and cost nothing.").font(.footnote).foregroundStyle(PLOS.dim(scheme))
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .navigationTitle("Prompt Forge")
        .sensoryFeedback(PLHaptic.success, trigger: text)
    }

    private func forge() async {
        busy = true; label = "Forging…"; text = "The canon is thinking."
        defer { busy = false }
        do {
            let j = try await Academy.post("api/forge", ["seed": seed.trimmingCharacters(in: .whitespaces)])
            label = "Forged from the canon"; text = (j["prompt"] as? String) ?? (j["error"] as? String) ?? "The forge returned nothing."
        } catch { label = "Forge"; text = error.localizedDescription == Academy.Problem.unreachable.errorDescription ? "The forge could not be reached." : error.localizedDescription }
    }
}

// MARK: - Persona Drills

struct AcademyDrillsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var drill: String?
    @State private var score = Academy.drillScore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reading the canon is knowing. Drilling it is becoming. Three instruments: run them until the voice is reflex.").font(.system(.callout, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme))
                let parts = ["purge", "laws", "rewrite"].compactMap { d in score[d].flatMap { $0["done"] ?? 0 > 0 ? "\(d): \($0["correct"] ?? 0)/\($0["done"] ?? 0)" : nil } }
                Text(parts.isEmpty ? "No reps yet. Begin." : parts.joined(separator: "  ·  ")).osEyebrow(10).foregroundStyle(PLOS.goldDim(scheme))
                if let drill {
                    HStack {
                        Text(drill == "purge" ? "The Purge" : drill == "laws" ? "Sequence" : "The Rewrite").osEyebrow(11).foregroundStyle(PLOS.dim(scheme))
                        Spacer()
                        Button("Back to drills") { self.drill = nil; score = Academy.drillScore }.buttonStyle(OSPill())
                    }
                    switch drill {
                    case "purge": PurgeDrill { score = Academy.drillScore }
                    case "laws": SequenceDrill { score = Academy.drillScore }
                    default: RewriteDrill { score = Academy.drillScore }
                    }
                } else {
                    menu("purge", "The Purge", "Banned words hide in plausible copy. Hunt them. Some passages are clean: a false accusation costs too.")
                    menu("laws", "Sequence", "Scenarios from the founder's desk. Call which Truth governs. The reveal teaches the why.")
                    menu("rewrite", "The Rewrite", "Hype copy goes in. Sovereign voice must come out. The examiner crowns or crucifies.")
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .navigationTitle("Persona Drills")
    }

    private func menu(_ id: String, _ title: String, _ blurb: String) -> some View {
        Button { drill = id } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).osEyebrow(12).foregroundStyle(PLOS.gold)
                Text(blurb).font(.footnote).foregroundStyle(PLOS.dim(scheme)).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).osCard(padding: 16)
        }
        .buttonStyle(.plain)
    }
}

/// A line-wrapping layout for the words of a passage.
private struct AcademyWrapLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

private struct PurgeDrill: View {
    let changed: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var idx = Int.random(in: 0..<AcademyBanks.purge.count)
    @State private var picked: Set<Int> = []
    @State private var verdict: String?

    private func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0 == "'" } }

    var body: some View {
        let item = AcademyBanks.purge[idx]
        let words = item.text.split(separator: " ").map(String.init)
        let violationParts = Set(item.violations.flatMap { $0.lowercased().split(separator: " ").map(String.init) })
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap every word that violates the voice. If the passage is clean, accuse nothing.").font(.system(.callout, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme))
            AcademyWrapLayout {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    let isViolation = verdict != nil && violationParts.contains(norm(w))
                    Text(w).font(.system(.title3, design: .serif))
                        .foregroundStyle(picked.contains(i) ? PLOS.bg(scheme) : PLOS.text(scheme))
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(picked.contains(i) ? PLOS.goldDim(scheme) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(alignment: .bottom) { if isViolation { Rectangle().fill(PLOS.danger).frame(height: 2) } }
                        .onTapGesture { if verdict == nil { if picked.contains(i) { picked.remove(i) } else { picked.insert(i) } } }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .osCard(padding: 16)
            if let verdict {
                Text(verdict).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading()
                Button("Next passage") { idx = pickNext(); picked = []; self.verdict = nil }.buttonStyle(OSPill())
            } else {
                Button("Judge") { judge(words: words, item: item, parts: violationParts) }.buttonStyle(OSPill())
            }
        }
    }

    private func pickNext() -> Int {
        var i = idx
        while AcademyBanks.purge.count > 1 && i == idx { i = Int.random(in: 0..<AcademyBanks.purge.count) }
        return i
    }

    private func judge(words: [String], item: AcademyBanks.Purge, parts: Set<String>) {
        let selected = picked.map { norm(words[$0]) }
        let hits = item.violations.filter { v in v.lowercased().split(separator: " ").contains { selected.contains(String($0)) } }
        let falsePos = selected.filter { !parts.contains($0) }
        let clean = hits.count == item.violations.count && falsePos.isEmpty
        Academy.bump("purge", correct: clean); changed()
        verdict = clean ? (item.violations.isEmpty ? "Correct. The passage holds: you accused nothing." : "Clean kill. Every violation found, nothing innocent accused.")
                        : "Missed. Violations in this passage: \(item.violations.isEmpty ? "none, it was clean" : item.violations.joined(separator: ", "))" + (falsePos.isEmpty ? "" : ". Falsely accused: \(falsePos.joined(separator: ", "))")
    }
}

private struct SequenceDrill: View {
    let changed: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var idx = Int.random(in: 0..<AcademyBanks.laws.count)
    @State private var answered: Int?

    var body: some View {
        let item = AcademyBanks.laws[idx]
        VStack(alignment: .leading, spacing: 14) {
            Text("Which Truth governs? The Truths are sequential: Preparation, Control, Persistence.").font(.system(.callout, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme))
            Text(item.scenario).font(.system(.title3, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading().osCard(padding: 18)
            ForEach([(1, "Truth 1: Prepared"), (2, "Truth 2: Control"), (3, "Truth 3: Persistence")], id: \.0) { n, label in
                Button(label) {
                    answered = n
                    Academy.bump("laws", correct: n == item.answer); changed()
                }
                .buttonStyle(OSPill()).disabled(answered != nil)
                .opacity(answered != nil && answered != n ? 0.45 : 1)
            }
            if let answered {
                Text((answered == item.answer ? "Correct. " : "No: Truth \(item.answer). ") + item.why).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading()
                    .sensoryFeedback(answered == item.answer ? PLHaptic.success : PLHaptic.warning, trigger: answered)
                Button("Next scenario") {
                    var i = idx
                    while AcademyBanks.laws.count > 1 && i == idx { i = Int.random(in: 0..<AcademyBanks.laws.count) }
                    idx = i; self.answered = nil
                }.buttonStyle(OSPill())
            }
        }
    }
}

private struct RewriteDrill: View {
    let changed: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var idx = Int.random(in: 0..<AcademyBanks.rewrite.count)
    @State private var text = ""
    @State private var busy = false
    @State private var result: [String: Any]?
    @State private var failure: String?

    var body: some View {
        let original = AcademyBanks.rewrite[idx]
        VStack(alignment: .leading, spacing: 14) {
            Text("Rewrite this in the sovereign voice. The examiner crowns or crucifies.").font(.system(.callout, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme))
            Text(original).font(.system(.title3, design: .serif).italic()).foregroundStyle(PLOS.dim(scheme)).osCard(padding: 18)
            if result == nil {
                TextField("The rewrite. Declarative. Spare. No reaching.", text: $text, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder)
                Button(busy ? "The examiner is reading…" : "Face the examiner") { Task { await grade(original) } }
                    .buttonStyle(OSPill()).disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                if let failure { Text(failure).font(.footnote).foregroundStyle(PLOS.danger) }
            } else if let r = result {
                let crown = (r["verdict"] as? String) == "crown"
                (Text(crown ? "CROWNED. " : "CRUCIFIED. ").bold().foregroundStyle(crown ? PLOS.gold : PLOS.danger) + Text((r["critique"] as? String) ?? ""))
                    .font(.system(.body, design: .serif)).plReading()
                    .sensoryFeedback(crown ? PLHaptic.success : PLHaptic.warning, trigger: crown)
                if let v = r["violations"] as? [String], !v.isEmpty { Text("Violations: " + v.joined(separator: ", ")).font(.footnote).foregroundStyle(PLOS.dim(scheme)) }
                if let m = r["model"] as? String, !m.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The examiner's rewrite").osEyebrow(9).foregroundStyle(PLOS.dim(scheme))
                        Text(m).font(.system(.body, design: .serif)).foregroundStyle(PLOS.text(scheme)).plReading().textSelection(.enabled)
                    }.osCard(padding: 16)
                }
                Button("Next original") {
                    var i = idx
                    while AcademyBanks.rewrite.count > 1 && i == idx { i = Int.random(in: 0..<AcademyBanks.rewrite.count) }
                    idx = i; result = nil; text = ""
                }.buttonStyle(OSPill())
            }
        }
    }

    private func grade(_ original: String) async {
        busy = true; failure = nil; defer { busy = false }
        do {
            let j = try await Academy.post("api/drill/rewrite", ["original": original, "rewrite": text.trimmingCharacters(in: .whitespaces)])
            if let e = j["error"] as? String { failure = "Examiner unreachable: \(e)"; return }
            Academy.bump("rewrite", correct: (j["verdict"] as? String) == "crown"); changed()
            result = j
        } catch { failure = "Examiner unreachable. \(error.localizedDescription)" }
    }
}
