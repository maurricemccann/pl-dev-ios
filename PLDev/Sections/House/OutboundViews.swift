import SwiftUI
import Charts

/// Outbound: what goes out. The web's Outbound tab (followers chart, PostReach, ApprovedQueue, Organic winners, PLFeed,
/// Calendar, Opportunity and Outbound leads, Pinterest, the Vault) plus /tempo and /calendar.
@MainActor @Observable final class OutboundModel {
    struct IG: Decodable {
        struct Post: Decodable, Identifiable { let permalink: String; let likes: Int?; let comments: Int?; let timestamp: String?; var id: String { permalink } }
        let followers: Int?; let following: Int?; let media_count: Int?; let recent: [Post]?
    }
    struct Runway: Decodable { let instagram_pending: Int?; let reels_remaining: Int?; let low: Bool? }
    var ig: IG?
    var runway: Runway?
    var days: [InboundModel.Day] = []

    func load(model: AppModel) async {
        async let i = try? Console.get("run/ig-insights", IG.self, model: model)
        async let r = try? Console.get("run/content-runway", Runway.self, model: model)
        async let d = try? Console.get("api/metrics/daily", InboundModel.Days.self, model: model, query: ["days": "90"])
        let (i1, r1, d1) = await (i, r, d)
        ig = i1; runway = r1; days = (d1?.days ?? []).filter { ($0.ig_followers ?? 0) > 0 }.sorted { $0.day < $1.day }
    }
}

struct OutboundTab: View {
    let model: AppModel
    @State private var state = OutboundModel()

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Kpi(title: "Followers", value: state.ig?.followers.map(String.init) ?? "—")
                    Kpi(title: "Instagram ready", value: state.runway?.instagram_pending.map(String.init) ?? "—")
                    Kpi(title: "Reels left", value: state.runway?.reels_remaining.map(String.init) ?? "—")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                if state.runway?.low == true { Label("The Instagram runway is low", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section {
                NavigationLink { CalendarView(model: model) } label: { Label("Content calendar", systemImage: "calendar") }
                NavigationLink { TempoView(model: model) } label: { Label("Tempo · this week", systemImage: "metronome") }
                NavigationLink { NotionView(model: model) } label: { Label("Pipeline and briefing", systemImage: "list.bullet.indent") }
                NavigationLink { FeedView(model: model) } label: { Label("PL feed", systemImage: "square.stack") }
                NavigationLink { DripView(model: model) } label: { Label("In the drip", systemImage: "drop") }
                NavigationLink { VaultView(model: model) } label: { Label("The vault", systemImage: "archivebox") }
                NavigationLink { ReachView(model: model) } label: { Label("Post reach", systemImage: "eye") }
                NavigationLink { OpportunityView(model: model) } label: { Label("Opportunities", systemImage: "sparkle.magnifyingglass") }
                NavigationLink { OutboundLeadsView(model: model) } label: { Label("Outbound leads", systemImage: "mappin.and.ellipse") }
                NavigationLink { PinterestView(model: model) } label: { Label("Pinterest", systemImage: "pin") }
            }
            if !state.days.isEmpty {
                Section("Instagram followers, 90 days") {
                    Chart(state.days) { d in
                        LineMark(x: .value("Day", Date.pl(d.day) ?? .now, unit: .day), y: .value("Followers", d.ig_followers ?? 0))
                            .interpolationMethod(.monotone).foregroundStyle(Color.orange)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                }
            }
            if let recent = state.ig?.recent, !recent.isEmpty {
                Section("Latest on Instagram") {
                    ForEach(recent.prefix(8)) { p in
                        Link(destination: URL(string: p.permalink) ?? URL(string: "https://instagram.com")!) {
                            HStack { Ago(text: p.timestamp); Spacer(); Label("\(p.likes ?? 0)", systemImage: "heart"); Label("\(p.comments ?? 0)", systemImage: "bubble.right") }
                                .font(.callout).monospacedDigit()
                        }
                    }
                }
            }
        }
        .task { await state.load(model: model) }
        .refreshable { await state.load(model: model) }
    }
}

// MARK: - Content calendar (/calendar)

struct CalendarView: View {
    let model: AppModel
    struct Item: Decodable, Identifiable { let id: String; let at: String?; let format: String?; let status: String?; let thumb: String?; let line: String? }
    struct Cell: Decodable { let items: [Item]?; let target: [String: Int]?; let short: [String: Int]?; let paused: Bool? }
    struct Day: Decodable, Identifiable { let date: String; let today: Bool?; let platforms: [String: Cell]?; var id: String { date } }
    struct Out: Decodable { let days: [Day]? }

    var body: some View {
        Loaded(load: { try await Console.get("api/content-calendar", Out.self, model: model, query: ["days": "14", "back": "1"]).days ?? [] }) { days, _ in
            List {
                ForEach(days) { d in
                    Section {
                        ForEach((d.platforms ?? [:]).keys.sorted(), id: \.self) { p in
                            let cell = d.platforms?[p]
                            let short = (cell?.short ?? [:]).values.reduce(0, +)
                            DisclosureGroup {
                                ForEach(cell?.items ?? []) { it in
                                    HStack(spacing: 10) {
                                        if let t = it.thumb, let u = URL(string: t) {
                                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                                                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(it.line ?? "").lineLimit(2).font(.callout)
                                            Text("\(it.format ?? "") · \(it.status ?? "")\(Date.pl(it.at).map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? "")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(p.capitalized)
                                    Spacer()
                                    if cell?.paused == true { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
                                    Text("\(cell?.items?.count ?? 0)").monospacedDigit()
                                    if short > 0 { Text("\(short) short").font(.caption.bold()).foregroundStyle(.orange) }
                                }
                            }
                        }
                    } header: {
                        Text((Date.pl(d.date)?.formatted(.dateTime.weekday(.wide).month().day()) ?? d.date) + (d.today == true ? " · today" : ""))
                    }
                }
            }
        }
        .navigationTitle("Calendar")
    }
}

// MARK: - Tempo (/tempo: the week's plan, the weekly email, the next reel, the run buttons)

struct TempoView: View {
    let model: AppModel
    struct Angle: Decodable, Identifiable { let id: String; let angle: String?; let hook: String?; let persona: String?; let glyph: String?; let beat: String? }
    struct Week: Decodable {
        struct Strategy: Decodable { let angles: [Angle]? }
        struct Email: Decodable { let id: String; let status: String?; let subject: String? }
        struct Perf: Decodable { let top_angle: String?; let top_rate: Double? }
        struct Drafts: Decodable { let pending: Int?; let held: Int? }
        let week_key: String?; let strategy: Strategy?; let email: Email?; let performance: Perf?; let drafts: Drafts?
    }
    struct Preview: Decodable { struct E: Decodable { let subject: String?; let body_text: String?; let status: String? }; let email: E? }
    struct Reel: Decodable { struct N: Decodable { let file: String?; let collection: String?; let url: String?; let duration: Double? }; let next: N?; let remaining: Int? }
    @State private var week: Week?
    @State private var preview: Preview.E?
    @State private var reel: Reel?
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        List {
            if let r = result { ResultLine(text: r) }
            if let w = week {
                Section("Week \(w.week_key ?? "")") {
                    if let p = w.performance?.top_angle { LabeledContent("Best angle last week", value: p) }
                    LabeledContent("Drafts waiting", value: "\(w.drafts?.pending ?? 0) · \(w.drafts?.held ?? 0) held")
                }
                Section("Angles") {
                    ForEach(w.strategy?.angles ?? []) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.angle ?? "").font(.headline)
                            if let h = a.hook { Text(h).font(.callout) }
                            Text([a.persona, a.beat, a.glyph].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let e = w.email {
                    Section {
                        Text(e.subject ?? "").font(.headline)
                        LabeledContent("Status", value: (e.status ?? "").capitalized)
                        if let p = preview?.body_text { Text(p).font(.callout).lineLimit(12) }
                        HStack {
                            Button("Approve") { Task { await act { try await Console.post("api/email/moderate", ["email_id": e.id, "action": "approve"], model: model); return "Approved." } } }
                            Button("Hold") { Task { await act { try await Console.post("api/email/moderate", ["email_id": e.id, "action": "hold"], model: model); return "Held." } } }
                            Spacer()
                            Button("Send now") { Task { await act { try await Console.post("api/email/send", ["email_id": e.id], model: model, timeout: 90); return "Sent." } } }
                                .disabled(e.status != "approved")
                        }
                        .buttonStyle(.bordered)
                    } header: { Text("This week's email") }
                }
            }
            if let n = reel?.next {
                Section {
                    LabeledContent("Next reel", value: n.file ?? "")
                    if let c = n.collection { LabeledContent("From", value: c) }
                    if let u = n.url.flatMap(URL.init(string:)) { Link("Watch it", destination: u) }
                    Button("Queue it") { Task { await act { try await Console.post("api/reels/queue-next", [:], model: model, timeout: 60); return "Queued." } } }
                } header: { Text("Reels · \(reel?.remaining ?? 0) left") }
            }
            Section {
                Button("Plan the week") { Task { await act { await Console.run("run/plan-week", model: model) } } }
                Button("Write the weekly email") { Task { await act { await Console.run("run/generate-email", model: model) } } }
                Button("Pull performance") { Task { await act { await Console.run("run/pull-performance", model: model) } } }
                Button("Run the content wave") { Task { await act { await Console.run("run/content-wave", model: model) } } }
            } header: { Text("Run now") }
        }
        .disabled(busy)
        .navigationTitle("Tempo")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        week = try? await Console.get("api/tempo/current", Week.self, model: model)
        reel = try? await Console.get("api/reels/next", Reel.self, model: model)
        if let id = week?.email?.id { preview = (try? await Console.get("api/email/preview", Preview.self, model: model, query: ["id": id]))?.email }
    }

    private func act(_ work: () async throws -> String) async {
        busy = true; defer { busy = false }
        do { result = try await work() } catch { result = "Not done. \(error.localizedDescription)" }
        await load()
    }
}

// MARK: - PL feed (PLFeedPanel)

struct FeedView: View {
    let model: AppModel
    struct Draft: Decodable, Identifiable { let id: String; let caption: String?; let media_url: String?; let created_at: String? }
    struct Post: Decodable, Identifiable { let id: String; let feed_post_id: String?; let caption: String?; let media_url: String?; let created_at: String? }
    struct D: Decodable { let drafts: [Draft]? }
    struct P: Decodable { let posts: [Post]? }
    @State private var drafts: [Draft] = []
    @State private var posts: [Post] = []
    @State private var result: String?

    var body: some View {
        List {
            if let r = result { ResultLine(text: r) }
            Section("Drafts for the congregation feed") {
                if drafts.isEmpty { Text("No feed drafts. Craft more from Make.").foregroundStyle(.secondary) }
                ForEach(drafts) { d in
                    VStack(alignment: .leading, spacing: 6) {
                        if let u = d.media_url.flatMap(URL.init(string:)) {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }.frame(height: 180).clipped()
                        }
                        Text(d.caption ?? "")
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Publish") { Task { await act("api/feed/publish", ["id": d.id], "Published.") } }.tint(.green)
                        Button("Schedule") { Task { await act("api/feed/approve", ["id": d.id], "Scheduled.") } }.tint(.blue)
                    }
                    .swipeActions(edge: .leading) { Button("Deny", role: .destructive) { Task { await act("api/feed/deny", ["id": d.id], "Denied.") } } }
                }
            }
            Section("Published") {
                ForEach(posts.prefix(30)) { p in
                    VStack(alignment: .leading, spacing: 2) { Text(p.caption ?? "").lineLimit(3); Ago(text: p.created_at).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("PL feed")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        drafts = (try? await Console.get("api/feed/drafts", D.self, model: model).drafts) ?? []
        posts = (try? await Console.get("api/feed/published", P.self, model: model).posts) ?? []
    }

    private func act(_ path: String, _ body: [String: Any], _ ok: String) async {
        do { try await Console.post(path, body, model: model); result = ok } catch { result = "Not done. \(error.localizedDescription)" }
        await load()
    }
}

// MARK: - The drip (ApprovedQueuePanel), the vault (VaultCard), reach (PostReachPanel)

struct DripView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let id: String; let platform: String?; let caption: String?; let publish_at: String? }
    var body: some View {
        Loaded(load: { try await Console.q("approvedqueue", [Row].self, model: model) }) { rows, _ in
            List {
                if rows.isEmpty { ContentUnavailableView("The drip is empty", systemImage: "drop", description: Text("Approve drafts to fill it.")) }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text((r.platform ?? "").capitalized).font(.caption.bold()); Spacer(); Ago(text: r.publish_at).font(.caption) }.foregroundStyle(.secondary)
                        Text(r.caption ?? "").lineLimit(3)
                    }
                }
            }
        }
        .navigationTitle("In the drip")
    }
}

struct VaultView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let id: String; let platform: String?; let caption: String?; let rewrite_caption: String?; let created_at: String?; let violations: [String]? }
    struct Out: Decodable { let rows: [Row]? }
    @State private var result: String?

    var body: some View {
        Loaded(load: { try await Console.get("api/vaulted", Out.self, model: model).rows ?? [] }) { rows, reload in
            List {
                if let r = result { ResultLine(text: r) }
                if rows.isEmpty { ContentUnavailableView("The vault is empty", systemImage: "archivebox") }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        Text((r.platform ?? "").capitalized).font(.caption.bold()).foregroundStyle(.secondary)
                        Text(r.caption ?? "").lineLimit(5)
                        if let rw = r.rewrite_caption { Text("Rewrite: ").bold() + Text(rw) }
                        if let v = r.violations, !v.isEmpty { Text(v.joined(separator: " · ")).font(.caption).foregroundStyle(.orange) }
                    }
                    .swipeActions {
                        Button("Restore") { Task { await restore(r, "original", reload) } }.tint(.blue)
                        if r.rewrite_caption != nil { Button("Use rewrite") { Task { await restore(r, "rewrite", reload) } }.tint(.green) }
                    }
                }
            }
        }
        .navigationTitle("The vault")
    }

    private func restore(_ r: Row, _ use: String, _ reload: () async -> Void) async {
        do { try await Console.post("api/vaulted/restore", ["id": r.id, "use": use], model: model); result = "Back in Approvals."; await reload() }
        catch { result = "Not restored. \(error.localizedDescription)" }
    }
}

struct ReachView: View {
    let model: AppModel
    struct Row: Decodable, Identifiable { let sent_at: String?; let channel: String?; let reach: Int?; let likes: Int?; let comments: Int?; let caption_excerpt: String?; var id: String { (sent_at ?? "") + (channel ?? "") } }
    var body: some View {
        Loaded(load: { try await Console.q("postreach", [Row].self, model: model) }) { rows, _ in
            List(rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text((r.channel ?? "").capitalized).font(.caption.bold()); Spacer(); Ago(text: r.sent_at).font(.caption) }.foregroundStyle(.secondary)
                    Text(r.caption_excerpt ?? "").lineLimit(2)
                    HStack(spacing: 14) { Label("\(r.reach ?? 0)", systemImage: "eye"); Label("\(r.likes ?? 0)", systemImage: "heart"); Label("\(r.comments ?? 0)", systemImage: "bubble.right") }
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .navigationTitle("Post reach")
    }
}

// MARK: - Leads (OpportunityLeadsPanel, OutboundLeadsPanel), Pinterest (PinterestCard)

struct OpportunityView: View {
    let model: AppModel
    struct Lead: Decodable, Identifiable { let id: Int; let name: String?; let why_fits: String?; let what_it_takes: String?; let confidence: String?; let deadline: String?; let source_url: String?; let ruled_out: Int?; let status: String? }
    struct Out: Decodable { let leads: [Lead]? }
    @State private var result: String?

    var body: some View {
        Loaded(load: { try await Console.get("api/opportunity-leads", Out.self, model: model).leads ?? [] }) { leads, reload in
            List {
                if let r = result { ResultLine(text: r) }
                ForEach(leads.filter { ($0.ruled_out ?? 0) == 0 && $0.status != "dead" }) { l in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(l.name ?? "").font(.headline); Spacer(); Text((l.status ?? "new").capitalized).font(.caption).foregroundStyle(.secondary) }
                        if let w = l.why_fits { Text(w).font(.callout) }
                        if let t = l.what_it_takes { Text("Takes: \(t)").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            if let c = l.confidence { Text(c.capitalized) }
                            if let d = l.deadline { Text("Due \(d)") }
                            if let s = l.source_url.flatMap(URL.init(string:)) { Link("Source", destination: s) }
                        }
                        .font(.caption)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Pursue") { Task { await set(l, "pursued", reload) } }.tint(.green)
                        Button("Reviewed") { Task { await set(l, "reviewed", reload) } }.tint(.blue)
                    }
                    .swipeActions(edge: .leading) { Button("Dead", role: .destructive) { Task { await set(l, "dead", reload) } } }
                }
            }
        }
        .navigationTitle("Opportunities")
    }

    private func set(_ l: Lead, _ status: String, _ reload: () async -> Void) async {
        do { try await Console.post("api/opportunity-leads", ["id": l.id, "status": status], model: model, method: "PATCH"); result = "Marked \(status)."; await reload() }
        catch { result = "Not saved. \(error.localizedDescription)" }
    }
}

struct OutboundLeadsView: View {
    let model: AppModel
    struct Lead: Decodable, Identifiable { let id: Int; let name: String?; let niche: String?; let location: String?; let website: String?; let stage: String?; let email: String?; let opener: String? }
    struct Out: Decodable { let leads: [Lead]? }
    var body: some View {
        Loaded(load: { try await Console.get("api/outbound/leads", Out.self, model: model).leads ?? [] }) { leads, _ in
            List(leads) { l in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.name ?? "").font(.headline)
                    Text([l.niche, l.location, l.stage].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    if let w = l.website, let u = URL(string: w.hasPrefix("http") ? w : "https://\(w)") { Link(w, destination: u).font(.caption) }
                    if let o = l.opener { Text(o).font(.caption) }
                }
            }
        }
        .navigationTitle("Outbound leads")
    }
}

struct PinterestView: View {
    let model: AppModel
    struct Status: Decodable { let connected: Bool?; let error: String?; let status: String? }
    var body: some View {
        Loaded(load: { try await Console.get("run/pinterest-sandbox", Status.self, model: model) }) { s, _ in
            List {
                LabeledContent("Connected", value: s.connected == true ? "Yes" : "No")
                if let e = s.error { Text(e).foregroundStyle(.secondary) }
                Text("Every Pin still waits for your tap in Approvals. Connecting Pinterest happens in pl-os on the laptop, because Pinterest's sign-in returns to that page.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pinterest")
    }
}
