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
    var stats: HouseModel.DraftStats?
    var sent = 0
    var reach: [ReachView.Row] = []
    var counts: [String: Int] = [:]
    var range = 30

    func load(model: AppModel) async {
        async let i = try? Console.get("run/ig-insights", IG.self, model: model)
        async let r = try? Console.get("run/content-runway", Runway.self, model: model)
        async let d = try? Console.get("api/metrics/daily", InboundModel.Days.self, model: model, query: ["days": "90"])
        let (i1, r1, d1) = await (i, r, d)
        ig = i1; runway = r1; days = (d1?.days ?? []).filter { ($0.ig_followers ?? 0) > 0 }.sorted { $0.day < $1.day }
        struct C: Decodable { let transmissions: Int? }
        struct Feed: Decodable { let drafts: [FeedView.Draft]? }
        struct Leads: Decodable { let leads: [OpportunityView.Lead]? }
        struct Vault: Decodable { let rows: [VaultView.Row]? }
        async let st = try? Console.q("draftstats", HouseModel.DraftStats.self, model: model)
        async let ct = try? Console.q("counts", C.self, model: model)
        async let rc = try? Console.q("postreach", [ReachView.Row].self, model: model)
        async let aq = try? Console.q("approvedqueue", [DripView.Row].self, model: model)
        async let fd = try? Console.get("api/feed/drafts", Feed.self, model: model)
        async let op = try? Console.get("api/opportunity-leads", Leads.self, model: model)
        async let vt = try? Console.get("api/vaulted", Vault.self, model: model)
        async let sg = try? Console.q("signals", [Signal].self, model: model)
        async let nt = try? OS.get("notion", NotionView.NState.self, model: model)
        let (st1, ct1, rc1, aq1, fd1, op1, vt1, sg1, nt1) = await (st, ct, rc, aq, fd, op, vt, sg, nt)
        stats = st1; sent = ct1?.transmissions ?? 0; reach = rc1 ?? []
        counts = ["queue": aq1?.count ?? 0, "feed": fd1?.drafts?.count ?? 0, "opps": (op1?.leads ?? []).filter { ($0.ruled_out ?? 0) == 0 && $0.status != "dead" }.count,
                  "vault": vt1?.rows?.count ?? 0, "rewritten": (vt1?.rows ?? []).filter { $0.rewrite_caption != nil }.count,
                  "signals": sg1?.count ?? 0, "pipeline": nt1?.pipelineTotal ?? 0, "calendar": nt1?.content.count ?? 0]
    }

    struct Signal: Decodable, Identifiable { let title: String?; let at: String?; var id: String { (title ?? "") + (at ?? "") } }
}

struct OutboundTab: View {
    let model: AppModel
    @State private var state = OutboundModel()
    @State private var crafting = false
    @State private var result: String?

    var body: some View {
        let shown = Array(state.days.suffix(state.range))
        List {
            Section {
                HStack(spacing: 12) {
                    Kpi(title: "Instagram", value: (state.ig?.followers ?? 0).formatted())
                    Kpi(title: "Drafted this week", value: "\(state.stats?.week_total ?? 0)")
                    Kpi(title: "Queued", value: "\(state.stats?.queued ?? 0)")
                    Kpi(title: "Sent", value: "\(state.sent)")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                if state.runway?.low == true { Label("The Instagram runway is low", systemImage: "exclamationmark.triangle").foregroundStyle(PLTone.house) }
            }
            Section {
                NavigationLink { FeedView(model: model) } label: {
                    LabeledContent { Text("\(state.counts["feed"] ?? 0) ready") } label: { Label("PL Feed", systemImage: "square.stack") }
                }
                Button(crafting ? "Crafting…" : "Craft more +") { Task { await craft() } }.disabled(crafting)
                if let r = result { ResultLine(text: r) }
            } footer: { Text("Congregation feed drafts: review and push.") }
            if !shown.isEmpty {
                Section("Instagram followers") {
                    Picker("Range", selection: $state.range) { Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90) }.pickerStyle(.segmented)
                    Chart(shown) { d in
                        LineMark(x: .value("Day", Date.pl(d.day) ?? .now, unit: .day), y: .value("Followers", d.ig_followers ?? 0))
                            .interpolationMethod(.monotone).foregroundStyle(Wallpaper.line)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 140)
                }
            }
            if !state.reach.isEmpty {
                Section {
                    ForEach(state.reach.prefix(6)) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(r.channel == "instagram" ? "IG" : "@").font(.caption.bold()); Ago(text: r.sent_at).font(.caption); Spacer(); Label("\(r.reach ?? 0)", systemImage: "eye").font(.caption.monospacedDigit()); Label("\(r.likes ?? 0)", systemImage: "heart").font(.caption.monospacedDigit()) }
                                .foregroundStyle(.secondary)
                            Text(r.caption_excerpt ?? "").lineLimit(2)
                        }
                    }
                    NavigationLink("Every post") { ReachView(model: model) }
                } header: {
                    Text("Post reach · \(state.reach.count) posts · \(state.reach.reduce(0) { $0 + ($1.reach ?? 0) }) reach · \(state.reach.reduce(0) { $0 + ($1.likes ?? 0) + ($1.comments ?? 0) }) engaged")
                }
            }
            Section {
                door("PL queue", "approved, in line", "list.number", state.counts["queue"]) { DripView(model: model) }
                door("Organic winners", "top posts first", "trophy", nil) { WinnersView(posts: state.ig?.recent ?? []) }
                door("Drop pipeline", "active", "list.bullet.indent", state.counts["pipeline"]) { NotionView(model: model) }
                door("Calendar", "this week", "calendar", state.counts["calendar"]) { CalendarView(model: model) }
                door("Signals sent", "transmissions", "paperplane", state.counts["signals"]) { SignalsView(model: model) }
                door("Opportunity scout", "placements and licensing", "sparkle.magnifyingglass", state.counts["opps"]) { OpportunityView(model: model) }
                door("Outbound sourcing", "no paid API", "mappin.and.ellipse", nil) { OutboundLeadsView(model: model) }
                door("Tempo", "this week's plan and email", "metronome", nil) { TempoView(model: model) }
            }
            Section {
                NavigationLink { PinterestView(model: model) } label: { Label("Pinterest", systemImage: "pin") }
                NavigationLink { VaultView(model: model) } label: {
                    LabeledContent { Text("\(state.counts["vault"] ?? 0) held · \(state.counts["rewritten"] ?? 0) rewritten") } label: { Label("The vault", systemImage: "archivebox") }
                }
            }
        }
        .task { await state.load(model: model) }
        .refreshable { await state.load(model: model) }
    }

    private func door<D: View>(_ title: String, _ line: String, _ symbol: String, _ count: Int?, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            LabeledContent {
                if let count { Text("\(count)").monospacedDigit() }
            } label: { Label { Text(title); Text(line) } icon: { Image(systemName: symbol) } }
        }
    }

    private func craft() async {
        crafting = true; defer { crafting = false }
        do { try await Console.post("api/craft-batch", ["count": 3], model: model, timeout: 90); result = "Crafted. They wait in the PL Feed."; await state.load(model: model) }
        catch { result = "Not crafted. \(error.localizedDescription)" }
    }
}

/// Instagram's latest, best first (the console's Organic Winners).
struct WinnersView: View {
    let posts: [OutboundModel.IG.Post]
    var body: some View {
        List(posts.sorted { ($0.likes ?? 0) + ($0.comments ?? 0) > ($1.likes ?? 0) + ($1.comments ?? 0) }) { p in
            Link(destination: URL(string: p.permalink) ?? URL(string: "https://instagram.com")!) {
                HStack { Ago(text: p.timestamp); Spacer(); Label("\(p.likes ?? 0)", systemImage: "heart"); Label("\(p.comments ?? 0)", systemImage: "bubble.right") }.monospacedDigit()
            }
        }
        .navigationTitle("Organic winners")
    }
}

/// Transmissions and sent emails, newest first (the console's Signals Sent).
struct SignalsView: View {
    let model: AppModel
    var body: some View {
        Loaded(load: { try await Console.q("signals", [OutboundModel.Signal].self, model: model) }) { rows, _ in
            List(rows) { r in VStack(alignment: .leading) { Text(r.title ?? ""); Ago(text: r.at).font(.caption).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Signals sent")
    }
}

// MARK: - Content calendar (/calendar)

struct CalendarView: View {
    let model: AppModel
    struct Item: Decodable, Identifiable { let id: String; let at: String?; let format: String?; let status: String?; let thumb: String?; let line: String? }
    struct Cell: Decodable { let items: [Item]?; let target: [String: Int]?; let short: [String: Int]?; let paused: Bool? }
    struct Day: Decodable, Identifiable { let date: String; let today: Bool?; let platforms: [String: Cell]?; var id: String { date } }
    struct Out: Decodable { let days: [Day]? }
    @State private var page: String?

    var body: some View {
        Loaded(load: { try await Console.get("api/content-calendar", Out.self, model: model, query: ["days": "14", "back": "3"]).days ?? [] }) { days, _ in
            // pl-os's day pager: one day a page, swiped sideways, opening at today
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(days) { d in dayPage(d).containerRelativeFrame(.horizontal).id(d.date) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $page)
            .onAppear { if page == nil { page = days.first(where: { $0.today == true })?.date ?? days.first?.date } }
        }
        .navigationTitle("Calendar")
    }

    private func dayPage(_ d: Day) -> some View {
        let shortAll = (d.platforms ?? [:]).filter { $0.value.paused != true }.values.flatMap { ($0.short ?? [:]).values }.reduce(0, +)
        return List {
            Section {
                ForEach((d.platforms ?? [:]).keys.sorted(), id: \.self) { p in
                    let cell = d.platforms?[p]
                    let short = (cell?.short ?? [:]).values.reduce(0, +)
                    DisclosureGroup {
                        if (cell?.items ?? []).isEmpty { Text("Nothing scheduled.").foregroundStyle(.secondary) }
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
                            Circle().fill(PLOS.platform(p)).frame(width: 9, height: 9)
                            Text(p == "pl_feed" ? "PL feed" : p.capitalized)
                            Spacer()
                            if cell?.paused == true { Text("paused").font(.caption).foregroundStyle(.secondary) }
                            else {
                                let target = (cell?.target ?? [:]).map { "\($0.value) \($0.key == "any" ? "" : $0.key)".trimmingCharacters(in: .whitespaces) }.sorted().joined(separator: " + ")
                                Text("\(cell?.items?.count ?? 0)\(target.isEmpty ? "" : " of " + target)").font(.callout.monospacedDigit())
                                if short > 0 { Text("\(short) short").font(.caption.bold()).foregroundStyle(PLOS.warn) }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text((Date.pl(d.date)?.formatted(.dateTime.weekday(.wide).month().day()) ?? d.date) + (d.today == true ? " · today" : ""))
                    Spacer()
                    Text(shortAll == 0 ? "full" : "\(shortAll) short").foregroundStyle(shortAll == 0 ? PLOS.ok : PLOS.warn)
                }
            }
        }
    }
}

// MARK: - Tempo (/tempo: the week's plan, the weekly email, the next reel, the run buttons)

struct TempoView: View {
    let model: AppModel
    struct Angle: Decodable, Identifiable { let id: String; let angle: String?; let hook: String?; let persona: String?; let glyph: String?; let beat: String?; let priority: Int?; let doctrine_cluster: String? }
    struct Week: Decodable {
        struct Strategy: Decodable { let angles: [Angle]?; let used_by_wave: Int? }
        struct Email: Decodable { let id: String; let status: String?; let subject: String? }
        struct Perf: Decodable { let top_angle: String?; let top_glyph: String?; let top_rate: Double? }
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
                    if let p = w.performance?.top_angle { LabeledContent("Top angle last week", value: p) }
                    if let g = w.performance?.top_glyph { LabeledContent("Top glyph", value: g) }
                    if let r = w.performance?.top_rate { LabeledContent("Engagement rate", value: String(format: "%.1f%%", r)) }
                    LabeledContent("Drafts waiting", value: "\(w.drafts?.pending ?? 0) · \(w.drafts?.held ?? 0) held")
                }
                Section {
                    ForEach((w.strategy?.angles ?? []).sorted { ($0.priority ?? 9) < ($1.priority ?? 9) }) { a in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text("P\(a.priority ?? 0)").font(.caption.bold().monospacedDigit()).foregroundStyle(Wallpaper.line); if let g = a.glyph { Text(g).font(.caption).foregroundStyle(.secondary) } }
                            Text(a.angle ?? "").font(.headline)
                            if let pr = a.persona { Text(pr).font(.callout) }
                            if let h = a.hook { Text("“\(h)”").plHand(20, relativeTo: .callout) }
                            if let c = a.doctrine_cluster { Text(c.replacingOccurrences(of: "-", with: " ").uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary) }
                        }
                    }
                } header: { Text("This week's angles\(w.strategy?.used_by_wave.map { " · \($0) waves used" } ?? "")") }
                if let e = w.email {
                    Section {
                        Text(e.subject ?? "").font(.headline)
                        LabeledContent("Status", value: (e.status ?? "").capitalized)
                        if let p = preview?.body_text { Text(p).font(.callout).plReading().lineLimit(12) }
                        HStack {
                            ConfirmButton(title: "Approve", question: "Approve this email to go out to the list?") { await act { try await Console.post("api/email/moderate", ["email_id": e.id, "action": "approve"], model: model); return "Approved." } }
                            Button("Hold") { Task { await act { try await Console.post("api/email/moderate", ["email_id": e.id, "action": "hold"], model: model); return "Held." } } }
                            Spacer()
                            ConfirmButton(title: "Send now", question: "Send this email to everyone on the list now? It cannot be called back.") { await act { try await Console.post("api/email/send", ["email_id": e.id], model: model, timeout: 90); return "Sent." } }
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
                    ConfirmButton(title: "Queue it", question: "Queue this reel to post?") { await act { try await Console.post("api/reels/queue-next", [:], model: model, timeout: 60); return "Queued." } }
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
    @State private var publishing: String?
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
                        Button("Schedule") { Task { await act("api/feed/approve", ["id": d.id], "Scheduled.") } }.tint(.blue)
                        Button("Publish") { publishing = d.id }.tint(.green)
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
        .confirmationDialog("Publish this post now, everywhere it is set to go?", isPresented: Binding(get: { publishing != nil }, set: { if !$0 { publishing = nil } }), titleVisibility: .visible) {
            Button("Publish") { if let id = publishing { Task { await act("api/feed/publish", ["id": id], "Published.") } }; publishing = nil }
            Button("Cancel", role: .cancel) { publishing = nil }
        }
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
                        if let v = r.violations, !v.isEmpty { Text(v.joined(separator: " · ")).font(.caption).foregroundStyle(PLTone.house) }
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
    struct Sandbox: Decodable {
        struct Account: Decodable { let username: String?; let account_type: String? }
        struct Board: Decodable { let id: String?; let name: String? }
        struct Pin: Decodable, Identifiable { let id: String; let description: String?; let image: String?; let link: String? }
        struct Row: Decodable, Identifiable { let id: String; let caption: String?; let media_url: String?; let status: String? }
        let connected: Bool?; let error: String?; let status: String?; let step: String?
        let account: Account?; let board: Board?; let pins: [Pin]?; let queue: [Row]?
    }
    @State private var s: Sandbox?
    @State private var failed: String?
    @State private var busy: String?
    @State private var note: String?

    var body: some View {
        List {
            if let failed, s == nil { Text(failed).foregroundStyle(.secondary) }
            if s == nil && failed == nil { ProgressView() }
            if let s {
                Section {
                    LabeledContent("Account", value: s.connected == true ? "@\(s.account?.username ?? "")" : "Not connected")
                    if s.connected == true {
                        LabeledContent("Board", value: s.board?.name ?? "made with the first pin")
                        LabeledContent("Account type", value: s.account?.account_type ?? "·")
                    } else {
                        Text("Connecting Pinterest happens in pl-os on the laptop: Pinterest's sign-in returns to that page.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let e = s.error { Text(e).font(.footnote).foregroundStyle(.secondary) }
                }
                if s.connected == true {
                    Section {
                        if (s.queue ?? []).isEmpty { Text("No Pinterest drafts waiting.").foregroundStyle(.secondary) }
                        ForEach(s.queue ?? []) { r in
                            HStack(spacing: 12) {
                                AsyncImage(url: r.media_url.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(r.caption ?? "").font(.callout).lineLimit(3)
                                Spacer(minLength: 0)
                                ConfirmButton(title: busy == r.id ? "Creating…" : "Create pin", question: "Publish this Pin to the board now?", confirm: "Create the pin") { await create(r.id) }
                                    .buttonStyle(.bordered).disabled(busy != nil)
                            }
                        }
                    } header: { Text("Drafts") } footer: { Text("Each Pin waits for your tap, as Pinterest's rules require.") }
                    if !(s.pins ?? []).isEmpty {
                        Section("Pins on the board") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                ForEach(s.pins ?? []) { p in
                                    Link(destination: URL(string: p.link ?? "") ?? URL(string: "https://www.pinterest.com")!) {
                                        AsyncImage(url: p.image.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                                            .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .accessibilityLabel(p.description ?? "Pin")
                                }
                            }
                        }
                    }
                }
            }
            if let note { Section { ResultLine(text: note) } }
        }
        .navigationTitle("Pinterest")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { s = try await Console.get("run/pinterest-sandbox", Sandbox.self, model: model); failed = nil }
        catch { failed = plainSentence(error) }
    }

    private func create(_ id: String) async {
        busy = id; defer { busy = nil }
        do {
            let d = try await Console.post("run/pinterest-sandbox/pin", ["row_id": id], model: model, timeout: 30)
            let r = try? JSONDecoder().decode(Sandbox.self, from: d)
            if r?.status == "error" { note = "Pinterest said no (\(r?.step ?? "error"))." } else { if let r { s = r }; note = "Pin created on the board." }
        } catch { note = "Not created. \(plainSentence(error))" }
    }
}
