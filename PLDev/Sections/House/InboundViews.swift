import SwiftUI
import Charts

/// Inbound: money and people coming in. The web's Inbound tab (KpiRow, StatTiles, ChartCard x2, RecordPanel, LeadsPanel,
/// RequestTallyPanel) plus its doorways: Inbox (DMs), Support, Seed registrations.
@MainActor @Observable final class InboundModel {
    struct Funnel: Decodable {
        struct Progress: Decodable { let quit_amazon_pct: Double?; let worth_line_pct: Double? }
        struct Returning: Decodable { let users_28d: Int?; let users_7d: Int?; let share_pct_28d: Double? }
        let audience: Int?; let participants: Int?; let belonging: Int?; let transmissions: Int?; let captures: Int?; let orders: Int?
        let revenue_total: Double?; let campaign_progress: Progress?; let returning: Returning?
    }
    struct Day: Decodable, Identifiable { let day: String; let subscribers: Int?; let orders: Int?; let ig_followers: Int?; let archive_count: Int?; let desires_total: Int?; let captures_new: Int?; let transmissions: Int?; let ig_posts: Int?; var id: String { day } }
    struct Days: Decodable { let days: [Day]? }
    struct Digest: Decodable { let text: String? }
    struct Pending: Decodable { let count: Int? }
    struct Threads: Decodable { struct T: Decodable { let unread: Int? }; let threads: [T]? }

    var funnel: Funnel?
    var days: [Day] = []
    var mtd: Double?
    var trailing: Double?
    var registered: Int?
    var unread = 0
    var support = 0
    var supportOpen = 0
    var siteUp: Bool?
    var stats: OutboundModel.IG?
    var archiveCount: Int?
    var runway: OutboundModel.Runway?
    var people = 0
    var comments = 0
    var range = 30

    func load(model: AppModel) async {
        async let f = try? Console.get("run/funnel", Funnel.self, model: model)
        async let d = try? Console.get("api/metrics/daily", Days.self, model: model, query: ["days": "90"])
        async let o = try? Console.get("run/order-digest", Digest.self, model: model, query: ["dry": "1"])
        async let s = try? Console.get("run/seed-registration/pending", Pending.self, model: model)
        async let t = try? Console.get("api/dm/threads", Threads.self, model: model)
        async let c = try? Console.q("contact", [SupportView.Message].self, model: model)
        let (f1, d1, o1, s1, t1, c1) = await (f, d, o, s, t, c)
        funnel = f1; days = (d1?.days ?? []).sorted { $0.day < $1.day }; registered = s1?.count
        unread = (t1?.threads ?? []).reduce(0) { $0 + ($1.unread ?? 0) }
        support = (c1 ?? []).filter { $0.status == "new" }.count
        let text = o1?.text ?? ""
        mtd = Self.money(text, "Month to date"); trailing = Self.money(text, "Trailing 365 days")
        supportOpen = (c1 ?? []).filter { $0.status != "resolved" }.count
        struct Stats: Decodable { let archive_count: Int? }
        struct Following: Decodable { let following: Int? }
        async let ig = try? Console.get("run/ig-insights", OutboundModel.IG.self, model: model)
        async let st = try? Console.get("api/stats", Stats.self, model: model)
        async let rw = try? Console.get("run/content-runway", OutboundModel.Runway.self, model: model)
        async let rec = try? Console.q("record", [RecordView.Person].self, model: model)
        async let cm = try? OS.get("comments", CommentsView.Out.self, model: model)
        let (ig1, st1, rw1, rec1, cm1) = await (ig, st, rw, rec, cm)
        stats = ig1; archiveCount = st1?.archive_count; runway = rw1; people = rec1?.count ?? 0; comments = cm1?.items.count ?? 0
        var head = URLRequest(url: URL(string: "https://psychedluxuries.com")!); head.httpMethod = "HEAD"; head.timeoutInterval = 10
        siteUp = ((try? await URLSession.shared.data(for: head))?.1 as? HTTPURLResponse).map { $0.statusCode < 500 }
    }

    /// Today against yesterday, from the daily metrics (the live tiles' "±0 1d").
    func delta(_ k: KeyPath<Day, Int?>) -> String {
        guard days.count >= 2, let a = days[days.count - 1][keyPath: k], let b = days[days.count - 2][keyPath: k] else { return "" }
        let d = a - b
        return d == 0 ? "±0 1d" : (d > 0 ? "+\(d) 1d" : "\(d) 1d")
    }

    /// The digest's "… → $1,234.56" for a line, as pl-os reads it, so the two can never disagree.
    static func money(_ text: String, _ label: String) -> Double? {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(label) }),
              let r = line.range(of: #"→\s*\$([\d,]+\.\d{2})"#, options: .regularExpression) else { return nil }
        return Double(line[r].replacingOccurrences(of: #"[^\d.]"#, with: "", options: .regularExpression))
    }
}

struct InboundTab: View {
    let model: AppModel
    @State private var state = InboundModel()

    var body: some View {
        let shown = Array(state.days.suffix(state.range))
        List {
            Section {
                HStack(spacing: 12) {
                    Kpi(title: "Month", value: state.mtd.map { $0.formatted(.currency(code: "USD")) } ?? "·")
                    Kpi(title: "12 months", value: state.trailing.map { $0.formatted(.currency(code: "USD")) } ?? "·")
                    Kpi(title: "Audience", value: "\(state.people)")
                    Kpi(title: "Registered", value: "\(state.registered ?? 0)")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                if let p = state.funnel?.campaign_progress {
                    Gauge(value: min(p.quit_amazon_pct ?? 0, 100), in: 0...100) { Text("Quit Amazon · $65k") } currentValueLabel: { Text("\(p.quit_amazon_pct ?? 0, specifier: "%.2f")%") }
                    Gauge(value: min(p.worth_line_pct ?? 0, 100), in: 0...100) { Text("Worth line · $100k") } currentValueLabel: { Text("\(p.worth_line_pct ?? 0, specifier: "%.2f")%") }
                }
            }
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatTile(title: "Storefront", value: state.siteUp == nil ? "·" : state.siteUp! ? "LIVE" : "DOWN", line: "psychedluxuries.com", alert: state.siteUp == false)
                    StatTile(title: "Subscribers", value: "\(state.days.last?.subscribers ?? 0)", line: "signal list · \(state.delta(\.subscribers))")
                    StatTile(title: "Desires", value: "\(state.days.last?.desires_total ?? 0)", line: state.delta(\.desires_total))
                    StatTile(title: "Captures", value: "\(state.days.last?.captures_new ?? 0)", line: "new · inbox · \(state.delta(\.captures_new))")
                    StatTile(title: "Transmissions", value: "\(state.days.last?.transmissions ?? 0)", line: "signals published · \(state.delta(\.transmissions))")
                    if let r = state.funnel?.returning { StatTile(title: "Returning", value: "\(r.users_28d ?? 0)", line: "\(Int((r.share_pct_28d ?? 0).rounded()))% of 28 days") }
                    StatTile(title: "Archive", value: (state.archiveCount ?? state.days.last?.archive_count ?? 0).formatted(), line: "pieces catalogued")
                    StatTile(title: "IG followers", value: (state.stats?.followers ?? 0).formatted(), line: "@psychedluxuries · \(state.delta(\.ig_followers))")
                    StatTile(title: "IG posts", value: (state.stats?.media_count ?? 0).formatted(), line: "total published · \(state.delta(\.ig_posts))")
                    StatTile(title: "Content runway", value: "\(state.runway?.instagram_pending ?? 0)", line: "\(state.runway?.reels_remaining ?? 0) reels in manifest", alert: state.runway?.low == true)
                    if let f = state.stats?.following { StatTile(title: "IG following", value: f.formatted(), line: "keep unfollowing non-mutuals") }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: { Text("Live · each against yesterday.") }
            Section {
                NavigationLink { InboxView(model: model) } label: { Label("Member inbox", systemImage: "bubble.left.and.bubble.right").badge(state.unread) }
                NavigationLink { CommentsView(model: model) } label: { Label("Comments", systemImage: "text.bubble").badge(state.comments) }
                NavigationLink { SupportView(model: model) } label: {
                    LabeledContent { Text(state.supportOpen == 0 ? "All resolved" : "\(state.supportOpen) open") } label: { Label("Support", systemImage: "lifepreserver") }
                }
                NavigationLink { SeedRegistrationsView(model: model) } label: { Label("Seed registrations", systemImage: "seal").badge(state.registered ?? 0) }
            }
            if !state.days.isEmpty {
                Section {
                    Picker("Range", selection: $state.range) { Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90) }.pickerStyle(.segmented)
                    Text("Orders").font(.headline)
                    Chart(shown) { d in
                        BarMark(x: .value("Day", Date.pl(d.day) ?? .now, unit: .day), y: .value("Orders", d.orders ?? 0)).foregroundStyle(Wallpaper.line)
                    }
                    .frame(height: 130)
                    Text("Audience").font(.headline)
                    Chart(shown) { d in
                        LineMark(x: .value("Day", Date.pl(d.day) ?? .now, unit: .day), y: .value("Subscribers", d.subscribers ?? 0)).interpolationMethod(.monotone)
                    }
                    .frame(height: 130)
                }
            }
            Section {
                NavigationLink { RecordView(model: model) } label: { LabeledContent { Text("\(state.people)") } label: { Label("The record", systemImage: "person.3") } }
                NavigationLink { LeadsView(model: model) } label: { Label("By intent", systemImage: "person.crop.circle.badge.questionmark") }
                NavigationLink { TallyView(model: model) } label: { Label("The ballot", systemImage: "chart.bar.doc.horizontal") }
                NavigationLink { OracleSignalView(model: model) } label: { Label("Oracle signal: what they ask", systemImage: "questionmark.bubble") }
            }
        }
        .task { await state.load(model: model) }
        .refreshable { await state.load(model: model) }
    }
}

/// One live tile: the label, the number, the line under it (with the change since yesterday), red when it needs a look.
struct StatTile: View {
    let title: String
    let value: String
    let line: String
    var alert = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).plLabel().foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(alert ? Color.red : Color.primary).contentTransition(.numericText())
            Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// What people ask GlyphBot (the console's Oracle Signal panel).
struct OracleSignalView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let id: String; let question: String?; let answer: String?; let via: String?; let asked_at: String? }
    var body: some View {
        Loaded(load: { try await Console.q("oracle", [Row].self, model: model) }) { rows, _ in
            List(rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.question ?? "").font(.headline)
                    Text(r.answer ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(4).plReading()
                    HStack { Text(r.via ?? ""); Spacer(); Ago(text: r.asked_at) }.font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Oracle signal")
    }
}

struct Kpi: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inbox (InboxPanel)

struct InboxView: View {
    let model: AppModel
    struct Thread: Decodable, Identifiable { let email: String; let handle: String?; let last_body: String?; let last_at: String?; let unread: Int?; var id: String { email } }
    struct Out: Decodable { let threads: [Thread]? }

    var body: some View {
        Loaded(load: { try await Console.get("api/dm/threads", Out.self, model: model).threads ?? [] }) { threads, _ in
            List {
                if threads.isEmpty { ContentUnavailableView("No messages", systemImage: "bubble.left.and.bubble.right", description: Text("When a member writes to you, it shows here.")) }
                ForEach(threads) { t in
                    NavigationLink { DMThreadView(model: model, email: t.email, title: t.handle ?? t.email) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(t.handle.map { "@\($0)" } ?? t.email).font(.headline); Spacer(); Ago(text: t.last_at).font(.caption).foregroundStyle(.secondary) }
                            Text(t.last_body ?? "").lineLimit(2).foregroundStyle(.secondary)
                        }
                        .badge(t.unread ?? 0)
                    }
                }
            }
        }
        .navigationTitle("Inbox")
    }
}

struct DMThreadView: View {
    let model: AppModel
    let email: String
    let title: String
    struct Msg: Decodable, Identifiable { let id: String; let sender: String; let body: String; let createdAt: String? }
    struct Out: Decodable { let messages: [Msg]? }
    @State private var messages: [Msg] = []
    @State private var draft = ""
    @State private var result: String?
    @State private var sending = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(messages) { m in
                    HStack {
                        if m.sender == "founder" { Spacer(minLength: 40) }
                        Text(m.body).plReading()
                            .padding(10)
                            .background(m.sender == "founder" ? PLTone.house.opacity(0.25) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if m.sender != "founder" { Spacer(minLength: 40) }
                    }
                    .listRowSeparator(.hidden)
                    .id(m.id)
                }
                if let r = result { ResultLine(text: r) }
            }
            .listStyle(.plain)
            .onChange(of: messages.count) { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Message", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                    .accessibilityLabel("Send")
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        messages = (try? await Console.get("api/dm/thread", Out.self, model: model, query: ["email": email]).messages) ?? messages
    }

    private func send() async {
        sending = true; defer { sending = false }
        do { try await Console.post("api/dm/send", ["email": email, "body": draft.trimmingCharacters(in: .whitespacesAndNewlines)], model: model); draft = ""; result = nil; await load() }
        catch { result = "Not sent. \(error.localizedDescription)" }
    }
}

// MARK: - Support (SupportInboxPanel)

struct SupportView: View {
    let model: AppModel
    struct Message: Decodable, Identifiable { let id: String; let name: String?; let email: String?; let message: String?; let created_at: String?; var status: String?; let order_id: String? }
    @State private var rows: [Message] = []
    @State private var loaded = false
    @State private var result: String?

    var body: some View {
        List {
            if let r = result { ResultLine(text: r) }
            if loaded && rows.isEmpty { ContentUnavailableView("No messages", systemImage: "lifepreserver", description: Text("The contact form is quiet.")) }
            ForEach(rows) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.name ?? m.email ?? "").font(.headline)
                        Spacer()
                        Text(m.status == "resolved" ? "Resolved" : "New").font(.caption.bold()).foregroundStyle(m.status == "resolved" ? Color.secondary : PLTone.house)
                    }
                    Text(m.message ?? "")
                    HStack {
                        if let e = m.email, let u = URL(string: "mailto:\(e)") { Link(e, destination: u) }
                        if let o = m.order_id { Text("Order \(o)") }
                        Spacer()
                        Ago(text: m.created_at)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(m.status == "resolved" ? "Reopen" : "Resolve") { Task { await toggle(m) } }.tint(m.status == "resolved" ? PLTone.house : .green)
                }
            }
        }
        .navigationTitle("Support")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if let r = try? await Console.q("contact", [Message].self, model: model) { rows = r; result = nil } else { result = "Not loaded. Pull to try again." }
        loaded = true
    }

    private func toggle(_ m: Message) async {
        let to = m.status == "resolved" ? "new" : "resolved"
        do { try await Console.post("api/pldev/x/contact", ["id": m.id, "status": to], model: model); await load() }
        catch { result = "Not saved. \(error.localizedDescription)" }
    }
}

// MARK: - Seed registrations (SeedRegistrationPanel)

struct SeedRegistrationsView: View {
    let model: AppModel
    struct Item: Decodable, Identifiable { let id: Int; let holder_name: String?; let holder_email: String?; let photo_url: String?; let submitted_at: String?; let unsent: Int? }
    struct Out: Decodable { let items: [Item]? }

    var body: some View {
        Loaded(load: { try await Console.get("run/seed-registration/pending", Out.self, model: model).items ?? [] }) { items, reload in
            List {
                if items.isEmpty { ContentUnavailableView("None waiting", systemImage: "seal", description: Text("When a holder registers a seed, it waits here for you to authenticate.")) }
                ForEach(items) { it in
                    NavigationLink { SeedAuthView(model: model, item: it, done: reload) } label: {
                        VStack(alignment: .leading) {
                            Text(it.holder_name ?? "").font(.headline)
                            Text(it.holder_email ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Seed registrations")
    }
}

struct SeedAuthView: View {
    let model: AppModel
    let item: SeedRegistrationsView.Item
    let done: () async -> Void
    @State private var piece = ""
    @State private var circa = ""
    @State private var notes = ""
    @State private var preview: UIImage?
    @State private var result: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let p = item.photo_url, let u = URL(string: p) {
                Section("Their photo") { AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 320) }
            }
            Section("Certificate") {
                TextField("Piece name", text: $piece)
                TextField("Made circa", text: $circa)
                TextField("Notes", text: $notes, axis: .vertical)
                Button("Preview the certificate") { Task { await doPreview() } }.disabled(busy)
            }
            if let preview { Section("Preview") { Image(uiImage: preview).resizable().scaledToFit() } }
            if let r = result { Section { ResultLine(text: r) } }
            Section {
                ConfirmButton(title: "Authenticate and send", question: "Authenticate this piece and email the certificate?") { await act("authenticate") }.disabled(busy || piece.isEmpty).bold()
                Button("Resend the certificate") { Task { await act("resend") } }.disabled(busy)
                ConfirmButton(title: "Reject", question: "Reject this registration?", role: .destructive) { await act("reject") }.disabled(busy)
            }
        }
        .navigationTitle(item.holder_name ?? "Registration")
    }

    private func doPreview() async {
        busy = true; defer { busy = false }
        guard let http = model.http else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["id": item.id, "piece_name": piece, "made_circa": circa])
            let d = try await http.send(RequestPlan(origin: "console", method: "POST", path: "run/seed-registration/preview", headers: ["content-type": "application/json"], body: body), idempotent: true, timeout: 40)
            preview = UIImage(data: d); result = preview == nil ? "The preview did not come back as a picture." : nil
        } catch { result = "No preview. \(error.localizedDescription)" }
    }

    private func act(_ action: String) async {
        busy = true; defer { busy = false }
        do {
            try await Console.post("run/seed-registration/authenticate", ["id": item.id, "action": action, "piece_name": piece, "made_circa": circa, "notes": notes], model: model, timeout: 60)
            await done(); dismiss()
        } catch { result = "Not done. \(error.localizedDescription)" }
    }
}

// MARK: - The record (RecordPanel), Leads (LeadsPanel), Request and vote (RequestTallyPanel)

struct RecordView: View {
    let model: AppModel
    struct Person: Decodable, Identifiable { let email: String; let name: String?; let founding: Int?; let stage: String?; let provenance: String?; let joined_at: String?; let is_member: Int?; let is_subscriber: Int?; var id: String { email } }
    @State private var search = ""

    var body: some View {
        Loaded(load: { try await Console.q("record", [Person].self, model: model) }) { people, _ in
            let shown = search.isEmpty ? people : people.filter { $0.email.localizedCaseInsensitiveContains(search) || ($0.name ?? "").localizedCaseInsensitiveContains(search) }
            List {
                Section {
                    LabeledContent("People", value: "\(people.count)")
                    LabeledContent("Members", value: "\(people.filter { $0.is_member == 1 }.count)")
                    LabeledContent("On the signal", value: "\(people.filter { $0.is_subscriber == 1 }.count)")
                    LabeledContent("Founding", value: "\(people.filter { ($0.founding ?? 0) > 0 }.count)")
                }
                Section {
                    ForEach(shown) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.name ?? p.email).font(.headline)
                                if (p.founding ?? 0) > 0 { Image(systemName: "star.fill").foregroundStyle(PLTone.house).accessibilityLabel("Founding") }
                            }
                            Text([p.stage, p.provenance, p.joined_at.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Name or email")
        }
        .navigationTitle("The record")
    }
}

struct LeadsView: View {
    let model: AppModel
    struct Lead: Decodable, Identifiable { let email: String; let name: String?; let intent: String?; let stage: String?; let provenance: String?; let last_touched: String?; var id: String { email } }
    struct Out: Decodable { let leads: [Lead]? }

    var body: some View {
        Loaded(load: { try await Console.get("api/leads", Out.self, model: model).leads ?? [] }) { leads, _ in
            List {
                if leads.isEmpty { ContentUnavailableView("No leads", systemImage: "person.crop.circle.badge.questionmark") }
                ForEach(leads) { l in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.name ?? l.email).font(.headline)
                        Text([l.intent, l.stage, l.provenance].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Leads")
    }
}

struct TallyView: View {
    let model: AppModel
    struct Product: Decodable, Identifiable { let product: String; let points: Int?; let votes: Int?; var id: String { product } }
    struct Piece: Decodable, Identifiable { let cr: String; let points: Int?; let votes: Int?; let products: [Product]?; var id: String { cr } }
    struct Ask: Decodable, Identifiable { let id: String; let email: String?; let cr: String?; let product: String?; let promise_hours_left: Double? }
    struct Tally: Decodable { let month: String?; let ranked: [Piece]?; let founder_queue: [Ask]?; let founders_sealed: Int?; let chosen_count: Int? }
    @State private var result: String?
    @State private var choosing: Piece?
    @State private var url = ""
    @State private var month = Self.months.first ?? ""
    /// This month and the eleven before it, as the tally's month param (YYYY-MM).
    static let months: [String] = (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: -$0, to: .now) }.map {
        let c = Calendar.current.dateComponents([.year, .month], from: $0); return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    var body: some View {
        Loaded(load: { try await Console.get("api/tally", Tally.self, model: model, query: ["month": month]) }) { t, reload in
            List {
                if let r = result { ResultLine(text: r) }
                Section {
                    Picker("Month", selection: $month) { ForEach(Self.months, id: \.self) { Text($0).tag($0) } }
                    LabeledContent("Founders sealed", value: "\(t.founders_sealed ?? 0)")
                    LabeledContent("Chosen this month", value: "\(t.chosen_count ?? 0)")
                }
                if let q = t.founder_queue, !q.isEmpty {
                    Section("Founder requests waiting") {
                        ForEach(q) { a in
                            VStack(alignment: .leading) {
                                Text("\(a.cr ?? "") · \(a.product ?? "")").font(.headline)
                                Text("\(a.email ?? "") · \(Int(a.promise_hours_left ?? 0)) h left on the promise").font(.caption).foregroundStyle((a.promise_hours_left ?? 99) < 0 ? PLOS.danger : (a.promise_hours_left ?? 99) < 24 ? PLOS.warn : .secondary)
                            }
                        }
                    }
                }
                Section("Ranked") {
                    if (t.ranked ?? []).isEmpty { Text("No votes yet this month.").foregroundStyle(.secondary) }
                    ForEach(t.ranked ?? []) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(p.cr).font(.headline); Spacer(); Text("\(p.points ?? 0) pts").monospacedDigit() }
                            Text((p.products ?? []).map { "\($0.product) \($0.points ?? 0)" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Choose") { choosing = p }.tint(PLTone.house) }
                    }
                }
            }
            .alert("Choose \(choosing?.cr ?? "")", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } })) {
                TextField("Product page address", text: $url)
                Button("Choose and tell the founders") { if let p = choosing { Task { await choose(p, mode: "founder", reload: reload) } } }
                Button("Choose and tell everyone") { if let p = choosing { Task { await choose(p, mode: "wide", reload: reload) } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Marks it chosen for \(choosing?.products?.first?.product ?? "its top product") and sends the drop notice.") }
        }
        .id(month)   // a new month reads its own tally
        .navigationTitle("Request and vote")
    }

    private func choose(_ p: Piece, mode: String, reload: () async -> Void) async {
        let product = p.products?.first?.product ?? ""
        do { try await Console.post("api/chosen", ["cr": p.cr, "product": product, "url": url, "offerId": ""], model: model) }
        catch { result = "Not done. \(plainSentence(error))"; return }
        do {
            try await Console.post("run/drop-notice", ["cr": p.cr, "mode": mode, "url": url], model: model, timeout: 60)
            result = "\(p.cr) chosen; the notice went to \(mode == "wide" ? "everyone" : "the founders")."; url = ""
            await reload()
        } catch { result = "\(p.cr) is marked chosen, but the notice did not go out: \(plainSentence(error)). Send it from Automation, not by choosing again."; await reload() }
    }
}
