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
    @Environment(\.colorScheme) private var scheme

    /// pl-os OutboundTab's order: Instagram followers and post reach first, then the eight cards (PL Queue, Organic Winners,
    /// PL Feed, Drop Pipeline, Calendar, Signals Sent, Opportunity Scout, Outbound Sourcing), then the app's extra doors.
    var body: some View {
        let shown = Array(state.days.suffix(state.range))
        ScrollView {
            VStack(spacing: 12) {
                OSHeader()
                OSKpis(items: [("Instagram", (state.ig?.followers ?? 0).formatted(), "followers"), ("Drafted", "\(state.stats?.week_total ?? 0)", "this week"),
                               ("Queued", "\(state.stats?.queued ?? 0)", nil), ("Sent", "\(state.sent)", nil)],
                       status: state.runway?.low == true ? ("Watch  the Instagram runway is low", PLOS.warn) : nil,
                       levels: [nil, nil, state.runway?.low == true ? PLStatus.warn : nil, nil])   // Queued is the runway: tinted only when the server says it is low
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Range", selection: $state.range) { Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90) }.pickerStyle(.segmented)
                        MetricTrend(title: "Instagram followers", days: shown, value: { $0.ig_followers }, unit: "followers")
                    }
                    .osCard()
                }
                if !state.reach.isEmpty {
                    let top = max(state.reach.map { $0.reach ?? 0 }.max() ?? 1, 1)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Post reach").plHand(19).foregroundStyle(PLOS.dim(scheme))
                            Spacer()
                            Text("\(state.reach.reduce(0) { $0 + ($1.reach ?? 0) }) reach · \(state.reach.reduce(0) { $0 + ($1.likes ?? 0) + ($1.comments ?? 0) }) engaged").osValue(11).foregroundStyle(PLOS.gold)
                        }
                        ForEach(state.reach.prefix(6)) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r.channel == "instagram" ? "IG" : "@").osEyebrow(9).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(PLOS.platform(r.channel == "instagram" ? "instagram" : "threads"), in: Capsule())
                                    Ago(text: r.sent_at).font(.caption2).foregroundStyle(PLOS.dim(scheme))
                                    Spacer()
                                    Label("\(r.reach ?? 0)", systemImage: "eye").font(.caption2.monospacedDigit()).foregroundStyle(PLOS.dim(scheme))
                                    Label("\(r.likes ?? 0)", systemImage: "heart").font(.caption2.monospacedDigit()).foregroundStyle(PLOS.dim(scheme))
                                }
                                Text(r.caption_excerpt ?? "").font(.callout).foregroundStyle(PLOS.text(scheme)).lineLimit(2)
                                // pl-os PostReachPanel: each post's reach as a bar against the top post
                                GeometryReader { g in Capsule().fill(PLOS.gold.opacity(0.7)).frame(width: max(4, g.size.width * CGFloat(r.reach ?? 0) / CGFloat(top))) }.frame(height: 4)
                            }
                        }
                        NavigationLink { ReachView(model: model).osScreen() } label: { Text("Every post →").osEyebrow(10).foregroundStyle(PLOS.gold) }
                    }
                    .osCard()
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    card("PL Queue", count(state.counts["queue"]), "approved, in line") { DripView(model: model) }
                    card("Organic Winners", "\(state.ig?.recent?.count ?? 0)", "top posts first") { WinnersView(posts: state.ig?.recent ?? []) }
                    card("PL Feed", count(state.counts["feed"]), "ready to push") { FeedView(model: model) }
                    card("Drop Pipeline", count(state.counts["pipeline"]), "active") { NotionView(model: model) }
                    card("Calendar", count(state.counts["calendar"]), "content + merch") { HouseCalendarView(model: model) }
                    card("Signals Sent", count(state.counts["signals"]), "transmissions") { SignalsView(model: model) }
                    card("Opportunity Scout", count(state.counts["opps"]), "placements + licensing") { OpportunityView(model: model) }
                    card("Outbound Sourcing", "→", "no paid API") { OutboundLeadsView(model: model) }
                }
                OSPanel(title: "Make more", startOpen: true) {
                    Button { Task { await craft() } } label: { Text(crafting ? "Crafting…" : "Craft more +") }.buttonStyle(OSPill()).disabled(crafting)
                    if let r = result { ResultLine(text: r) }
                    Text("Congregation feed drafts: review and push them in PL Feed.").font(.caption).foregroundStyle(PLOS.dim(scheme))
                }
                OSPanel(title: "More doors") {
                    door("Tempo · this week's plan and email") { TempoView(model: model) }
                    door("Pinterest") { PinterestView(model: model) }
                    door("The vault · \(state.counts["vault"] ?? 0) held · \(state.counts["rewritten"] ?? 0) rewritten") { VaultView(model: model) }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 24)
        }
        .task { await state.load(model: model) }
        .refreshable { await state.load(model: model) }
    }

    private func count(_ n: Int?) -> String { n.map(String.init) ?? "·" }

    private func card<D: View>(_ name: String, _ count: String, _ sub: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest().osScreen() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).plHand(17).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                Text(count).osValue(26).foregroundStyle(PLOS.text(scheme))
                Text(sub).osEyebrow(8).foregroundStyle(PLOS.goldDim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .osCard()
        }
        .buttonStyle(.plain)
    }

    private func door<D: View>(_ title: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest().osScreen() } label: {
            OSRow(title: title) { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(PLOS.goldDim(scheme)) }
        }
        .buttonStyle(.plain)
    }

    private func craft() async {
        crafting = true; defer { crafting = false }
        do { try await Console.post("api/craft-batch", ["count": 3], model: model, timeout: 90); result = "Crafted. They wait in the PL Feed."; await state.load(model: model) }
        catch { result = "Not crafted. \(plainSentence(error))" }
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
    // pl-os's filler line and ghosts (the gap audit 11-14: the phone read only `days`): what the auto-filler slotted, or would slot
    struct Move: Decodable { let id: String; let platform: String; let format: String?; let date: String; let to: String }
    struct Ask: Decodable { let gen: String }
    struct Fill: Decodable { let live: Bool; let at: String?; let planned: Int?; let moved: Int?; let moves: [Move]?; let asked: [Ask]? }
    struct Out: Decodable { let days: [Day]?; let fill: Fill? }
    @State private var page: String?
    @State private var fill: Fill?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Loaded(load: { () async throws -> [Day] in
            let o = try await Console.get("api/content-calendar", Out.self, model: model, query: ["days": "14", "back": "3"])
            await MainActor.run { fill = o.fill }
            return o.days ?? []
        }) { days, _ in
          VStack(spacing: 0) {
            // the fortnight at a glance: each day as strong as what is scheduled, ringed where it is short (his ask 11-14)
            // one row per platform (his pick P1): a short platform shows on its own row, not lost in a sum
            let platforms = Array(Set(days.flatMap { ($0.platforms ?? [:]).keys })).sorted()
            VStack(alignment: .leading, spacing: 3) {
                ForEach(platforms, id: \.self) { p in
                    HStack(spacing: 2) {
                        Text(p == "pl_feed" ? "PL feed" : p.capitalized).font(.system(size: 9, weight: .semibold)).foregroundStyle(PLOS.platform(p))
                            .frame(width: 58, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                        ForEach(days) { d in
                            let cell = d.platforms?[p]
                            let have = cell?.items?.count ?? 0, want = (cell?.target ?? [:]).values.reduce(0, +), short = (cell?.short ?? [:]).values.reduce(0, +)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(cell?.paused == true ? PLOS.dim(scheme).opacity(0.08) : (have > 0 ? PLOS.platform(p).opacity(want > 0 ? 0.3 + 0.7 * min(1, Double(have) / Double(want)) : 0.8) : PLOS.dim(scheme).opacity(0.14)))
                                .overlay { RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(d.date == page ? PLOS.gold : (short > 0 && cell?.paused != true ? PLOS.warn : .clear), lineWidth: 1.2) }
                                .frame(height: 14)
                                .onTapGesture { withAnimation(.snappy) { page = d.date } }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(p): \(days.map { $0.platforms?[p]?.items?.count ?? 0 }.reduce(0, +)) scheduled in \(days.count) days")
                }
            }
            .padding(.horizontal).padding(.top, 8)
            HStack(spacing: 12) {
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).strokeBorder(PLOS.warn, lineWidth: 1.5).frame(width: 10, height: 10); Text("short") }
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).strokeBorder(PLOS.gold, lineWidth: 1.5).frame(width: 10, height: 10); Text("showing") }
                Spacer()
            }
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).padding(.horizontal).padding(.top, 4)
            fillLine.padding(.horizontal).padding(.vertical, 6)
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
        }
        .navigationTitle("Calendar")
    }

    private static let gen = ["story-batch": "story batch", "queue-weekly-reel": "reel", "keep-feeder": "KEEP feeder", "content-wave": "content wave"]
    private var fillLine: some View {
        Group {
            if let f = fill {
                let asked = (f.asked ?? []).map { Self.gen[$0.gen] ?? $0.gen }.joined(separator: ", ")
                Text("Filler \(f.live ? "on" : "dry run (not switched on)") · \(f.live ? "slotted \(f.moved ?? 0)" : "would slot \(f.planned ?? 0)")\(asked.isEmpty ? "" : " · \(f.live ? "asked" : "would ask") \(asked)")")
            } else {
                Text("Filler: no run recorded yet.")
            }
        }
        .font(.caption.monospaced()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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
                        // a dry run's moves into this cell, shown as ghosts before the filler is switched on
                        if let f = fill, !f.live {
                            ForEach((f.moves ?? []).filter { $0.platform == p && $0.date == d.date }, id: \.id) { m in
                                Label("Would slot \(m.format ?? "") · \(Date.pl(m.to)?.formatted(date: .omitted, time: .shortened) ?? "")", systemImage: "square.dashed")
                                    .font(.caption).foregroundStyle(PLOS.gold.opacity(0.8))
                            }
                        }
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
                            Text(p == "pl_feed" ? "PL feed" : p.capitalized).fontWeight(.semibold).foregroundStyle(PLOS.platform(p))
                            Spacer()
                            if cell?.paused == true { Text("paused").font(.caption).foregroundStyle(.secondary) }
                            else {
                                let target = (cell?.target ?? [:]).map { "\($0.value) \($0.key == "any" ? "" : $0.key)".trimmingCharacters(in: .whitespaces) }.sorted().joined(separator: " + ")
                                let want = (cell?.target ?? [:]).values.reduce(0, +), have = cell?.items?.count ?? 0
                                if want > 0 {
                                    ZStack {
                                        Circle().stroke(PLOS.dim(scheme).opacity(0.2), lineWidth: 3)
                                        Circle().trim(from: 0, to: min(1, Double(have) / Double(want))).stroke(have >= want ? PLOS.ok : PLOS.warn, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                                    }
                                    .frame(width: 18, height: 18).accessibilityHidden(true)
                                }
                                Text("\(have)\(target.isEmpty ? "" : " of " + target)").font(.callout.monospacedDigit())
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
            }.listRowBackground(OSRowBackground())
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            if let r = result { ResultLine(text: r) }
            if let w = week {
                // last week at a glance: the rate as a ring, what won as chips, the drafts as a bar (his ask 11-14)
                Section("Week \(w.week_key ?? "")") {
                    HStack(alignment: .center, spacing: 16) {
                        if let r = w.performance?.top_rate {
                            // pl-cron's engagement_rate is raw likes + comments per post, not a percent (it read "2.0%" before 11-14)
                            PLBigTile(number: String(format: "%.1f", r), label: "Responses per post", tint: PLOS.gold, text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                                .frame(width: 120)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if let p = w.performance?.top_angle {
                                VStack(alignment: .leading, spacing: 3) { Text("Top angle last week").osEyebrow().foregroundStyle(PLOS.dim(scheme)); PLChip(word: p, tint: PLOS.gold) }
                            }
                            if let g = w.performance?.top_glyph {
                                VStack(alignment: .leading, spacing: 3) { Text("Top glyph").osEyebrow().foregroundStyle(PLOS.dim(scheme)); PLChip(word: g, tint: PLOS.philosophy) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    PLStageBar(stages: [.init(name: "Drafts waiting", count: w.drafts?.pending ?? 0, tint: PLOS.gold), .init(name: "Held", count: w.drafts?.held ?? 0, tint: PLOS.warn)],
                               text: PLOS.text(scheme), dim: PLOS.dim(scheme), height: 10)
                        .padding(.vertical, 4)
                }.listRowBackground(OSRowBackground())
                Section {
                    ForEach((w.strategy?.angles ?? []).sorted { ($0.priority ?? 9) < ($1.priority ?? 9) }) { a in
                        HStack(alignment: .top, spacing: 12) {
                            // the priority as a filled badge: P1 is the brightest
                            Text("\(a.priority ?? 0)").font(.system(.headline, design: .monospaced)).foregroundStyle(PLOS.bg(scheme))
                                .frame(width: 30, height: 30)
                                .background(PLOS.gold.opacity(max(0.3, 1.0 - Double((a.priority ?? 1) - 1) * 0.14)), in: Circle())
                                .accessibilityLabel("Priority \(a.priority ?? 0)")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(a.angle ?? "").font(.headline)
                                if let h = a.hook { Text("“\(h)”").plHand(20, relativeTo: .callout) }
                                if let pr = a.persona { Text(pr).font(.footnote).foregroundStyle(PLOS.dim(scheme)) }
                                HStack(spacing: 6) {
                                    if let g = a.glyph { PLChip(word: g, tint: PLOS.gold) }
                                    if let c = a.doctrine_cluster { PLChip(word: c.replacingOccurrences(of: "-", with: " "), tint: PLOS.philosophy) }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: { Text("This week's angles\(w.strategy?.used_by_wave.map { " · \($0) waves used" } ?? "")") }.listRowBackground(OSRowBackground())
                if let e = w.email {
                    Section {
                        Text(e.subject ?? "").font(.headline)
                        PLStateDot(word: (e.status ?? "").capitalized, tint: e.status == "sent" ? PLOS.ok : (e.status == "approved" ? PLOS.gold : PLOS.warn), text: PLOS.text(scheme))
                        if let p = preview?.body_text { Text(p).font(.callout).plReading().lineLimit(12) }
                        HStack {
                            ConfirmButton(title: "Approve", question: "Approve this email to go out to the list?") { await act { try await Console.post("api/email/moderate", ["email_id": e.id, "action": "approve"], model: model); return "Approved." } }
                            Button("Hold") { Task { await act { try await Console.post("api/email/moderate", ["email_id": e.id, "action": "hold"], model: model); return "Held." } } }
                            Spacer()
                            ConfirmButton(title: "Send now", question: "Send this email to everyone on the list now? It cannot be called back.") { await act { try await Console.post("api/email/send", ["email_id": e.id], model: model, timeout: 90); return "Sent." } }
                                .disabled(e.status != "approved")
                        }
                        .buttonStyle(.bordered)
                    } header: { Text("This week's email") }.listRowBackground(OSRowBackground())
                }
            }
            if let n = reel?.next {
                Section {
                    PLBigTile(number: "\(reel?.remaining ?? 0)", label: "Reels left", tint: PLOS.gold, text: PLOS.text(scheme), dim: PLOS.dim(scheme)) {
                        Image(systemName: "film.stack").font(.title).foregroundStyle(PLOS.goldDim(scheme))
                    }
                    LabeledContent("Next reel", value: n.file ?? "")
                    if let c = n.collection { LabeledContent("From", value: c) }
                    if let u = n.url.flatMap(URL.init(string:)) { Link("Watch it", destination: u) }
                    ConfirmButton(title: "Queue it", question: "Queue this reel to post?") { await act { try await Console.post("api/reels/queue-next", [:], model: model, timeout: 60); return "Queued." } }
                } header: { Text("Reels · \(reel?.remaining ?? 0) left") }.listRowBackground(OSRowBackground())
            }
            Section {
                Button("Plan the week") { Task { await act { await Console.run("run/plan-week", model: model) } } }
                Button("Write the weekly email") { Task { await act { await Console.run("run/generate-email", model: model) } } }
                Button("Pull performance") { Task { await act { await Console.run("run/pull-performance", model: model) } } }
                Button("Run the content wave") { Task { await act { await Console.run("run/content-wave", model: model) } } }
            } header: { Text("Run now") }.listRowBackground(OSRowBackground())
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
    @State private var swapping: Post?
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
            }.listRowBackground(OSRowBackground())
            Section("Published") {
                ForEach(posts.prefix(30)) { p in
                    HStack(spacing: 10) {
                        if let u = p.media_url.flatMap(URL.init(string:)) {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 2) { Text(p.caption ?? "").lineLimit(3); Ago(text: p.created_at).font(.caption).foregroundStyle(.secondary) }
                    }
                    .contextMenu { if p.feed_post_id != nil { Button("Change the picture", systemImage: "photo.on.rectangle") { swapping = p } } }
                    .swipeActions { if p.feed_post_id != nil { Button("Picture") { swapping = p }.tint(PLOS.gold) } }
                }
            }.listRowBackground(OSRowBackground())
        }
        .navigationTitle("PL feed")
        .confirmationDialog("Publish this post now, everywhere it is set to go?", isPresented: Binding(get: { publishing != nil }, set: { if !$0 { publishing = nil } }), titleVisibility: .visible) {
            Button("Publish") { if let id = publishing { Task { await act("api/feed/publish", ["id": id], "Published.") } }; publishing = nil }
            Button("Cancel", role: .cancel) { publishing = nil }
        }
        .sheet(item: $swapping) { p in
            PicturePicker { url in swapping = nil; Task { await act("api/feed/update-image", ["feed_post_id": p.feed_post_id ?? "", "media_url": url], "Picture changed on the live post."); await load() } }
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
    @Environment(\.colorScheme) private var scheme
    struct Row: Decodable, Identifiable { let id: String; let platform: String?; let caption: String?; let publish_at: String? }
    var body: some View {
        Loaded(load: { try await Console.q("approvedqueue", [Row].self, model: model) }) { rows, _ in
            List {
                if rows.isEmpty { ContentUnavailableView("The drip is empty", systemImage: "drop", description: Text("Approve drafts to fill it.")) }
                else {
                    Section("Waiting to post · \(rows.count)") {
                        let by = Dictionary(grouping: rows, by: { $0.platform ?? "" })
                        PLStageBar(stages: by.keys.sorted().map { .init(name: $0.isEmpty ? "other" : $0, count: by[$0]?.count ?? 0, tint: PLOS.platform($0)) },
                                   text: PLOS.text(scheme), dim: PLOS.dim(scheme)).padding(.vertical, 4)
                    }.listRowBackground(OSRowBackground())
                }
                // grouped by the day they go out (his pick P2)
                let days = Dictionary(grouping: rows, by: { String(($0.publish_at ?? "").prefix(10)) })
                ForEach(days.keys.sorted(), id: \.self) { day in
                  Section(Date.pl(day)?.formatted(.dateTime.weekday(.wide).month().day()) ?? (day.isEmpty ? "No date" : day)) {
                    ForEach(days[day] ?? []) { r in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text((r.platform ?? "").capitalized).font(.caption.bold()).foregroundStyle(PLOS.platform(r.platform)); Spacer(); Ago(text: r.publish_at).font(.caption) }.foregroundStyle(.secondary)
                            Text(r.caption ?? "").lineLimit(3)
                        }
                    }
                    }
                  }.listRowBackground(OSRowBackground())
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Loaded(load: { try await Console.get("api/vaulted", Out.self, model: model).rows ?? [] }) { rows, reload in
            List {
                if let r = result { ResultLine(text: r) }
                if rows.isEmpty { ContentUnavailableView("The vault is empty", systemImage: "archivebox") }
                else {
                    Section {
                        PLBigTile(number: "\(rows.count)", label: "Held back", tint: PLOS.warn, text: PLOS.text(scheme), dim: PLOS.dim(scheme)) {
                            Text("\(rows.filter { $0.rewrite_caption != nil }.count) with a rewrite").font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme))
                        }
                    }.listRowBackground(OSRowBackground())
                }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        Text((r.platform ?? "").capitalized).font(.caption.bold()).foregroundStyle(PLOS.platform(r.platform))
                        Text(r.caption ?? "").lineLimit(5)
                        if let rw = r.rewrite_caption { Text("Rewrite: ").bold() + Text(rw) }
                        if let v = r.violations, !v.isEmpty { HStack(spacing: 5) { ForEach(v.prefix(3), id: \.self) { PLChip(word: $0, tint: PLOS.warn) } } }
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
    @Environment(\.colorScheme) private var scheme
    struct Row: Decodable, Identifiable { let sent_at: String?; let channel: String?; let reach: Int?; let likes: Int?; let comments: Int?; let caption_excerpt: String?; var id: String { (sent_at ?? "") + (channel ?? "") } }
    var body: some View {
        Loaded(load: { try await Console.q("postreach", [Row].self, model: model) }) { rows, _ in
            let top = Double(rows.map { ($0.reach ?? 0) + ($0.likes ?? 0) + ($0.comments ?? 0) }.max() ?? 0)
            List {
                Section {
                    HStack(spacing: 12) {
                        PLBigTile(number: "\(rows.map { $0.reach ?? 0 }.reduce(0, +))", label: "Reach", text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                        PLBigTile(number: "\(rows.map { $0.likes ?? 0 }.reduce(0, +))", label: "Likes", text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                        PLBigTile(number: "\(rows.map { $0.comments ?? 0 }.reduce(0, +))", label: "Comments", text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                    }
                    // newest on the right, the latest post lit: is the response rising or falling
                    PLSpark(values: rows.prefix(24).reversed().map { Double(($0.reach ?? 0) + ($0.likes ?? 0) + ($0.comments ?? 0)) }, tint: PLOS.gold, dim: PLOS.dim(scheme), height: 34)
                } header: { Text("Last \(rows.count) posts") }.listRowBackground(OSRowBackground())
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Text((r.channel ?? "").capitalized).font(.caption.bold()).foregroundStyle(PLOS.platform(r.channel)); Spacer(); Ago(text: r.sent_at).font(.caption) }.foregroundStyle(.secondary)
                        Text(r.caption_excerpt ?? "").lineLimit(2)
                        HStack(spacing: 14) { Label("\(r.reach ?? 0)", systemImage: "eye"); Label("\(r.likes ?? 0)", systemImage: "heart"); Label("\(r.comments ?? 0)", systemImage: "bubble.right") }
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .plBar(Double((r.reach ?? 0) + (r.likes ?? 0) + (r.comments ?? 0)), of: top, tint: PLOS.platform(r.channel))
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
    @Environment(\.colorScheme) private var scheme

    private func statusTone(_ s: String) -> Color { s == "pursued" ? PLOS.ok : (s == "reviewed" ? PLOS.gold : PLOS.muted) }
    /// The scout's confidence as a colour: its text begins "high", "medium" or "low".
    private func confidenceTone(_ c: String?) -> Color {
        let c = (c ?? "").lowercased()
        return c.hasPrefix("high") ? PLOS.ok : (c.hasPrefix("med") ? PLOS.gold : PLOS.muted)
    }

    var body: some View {
        Loaded(load: { try await Console.get("api/opportunity-leads", Out.self, model: model).leads ?? [] }) { leads, reload in
            List {
                if let r = result { ResultLine(text: r) }
                let open = leads.filter { ($0.ruled_out ?? 0) == 0 && $0.status != "dead" }
                if !open.isEmpty {
                    Section("Open leads · \(open.count)") {
                        let by = Dictionary(grouping: open, by: { $0.status ?? "new" })
                        PLStageBar(stages: ["new", "reviewed", "pursued"].map { .init(name: $0, count: by[$0]?.count ?? 0, tint: statusTone($0)) }
                                   + by.keys.filter { !["new", "reviewed", "pursued"].contains($0) }.sorted().map { .init(name: $0, count: by[$0]?.count ?? 0, tint: PLOS.muted) },
                                   text: PLOS.text(scheme), dim: PLOS.dim(scheme)).padding(.vertical, 4)
                    }.listRowBackground(OSRowBackground())
                }
                ForEach(open) { l in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(confidenceTone(l.confidence)).frame(width: 9, height: 9)
                            Text(l.name ?? "").font(.headline)
                            Spacer()
                            PLChip(word: l.status ?? "new", tint: statusTone(l.status ?? "new"))
                        }
                        if let w = l.why_fits { Text(w).font(.callout) }
                        if let t = l.what_it_takes { Text("Takes: \(t)").font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 6) {
                            if let c = l.confidence { PLChip(word: String(c.prefix(18)), tint: confidenceTone(c)) }
                            if let d = l.deadline, !d.isEmpty { PLChip(word: "due " + d, tint: PLOS.warn) }
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Loaded(load: { try await Console.get("api/outbound/leads", Out.self, model: model).leads ?? [] }) { leads, _ in
            List {
              if !leads.isEmpty {
                Section("Leads · \(leads.count)") {
                    let by = Dictionary(grouping: leads, by: { $0.stage ?? "new" })
                    let tones: [Color] = [PLOS.muted, PLOS.gold, PLOS.ok, PLOS.philosophy, PLOS.warn]
                    PLStageBar(stages: by.keys.sorted().enumerated().map { .init(name: $0.element, count: by[$0.element]?.count ?? 0, tint: tones[$0.offset % tones.count]) },
                               text: PLOS.text(scheme), dim: PLOS.dim(scheme)).padding(.vertical, 4)
                }.listRowBackground(OSRowBackground())
              }
              ForEach(leads) { l in
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.name ?? "").font(.headline)
                    HStack(spacing: 5) {
                        if let s = l.stage { PLChip(word: s, tint: PLOS.gold) }
                        if let n = l.niche { PLChip(word: n, tint: PLOS.dim(scheme)) }
                        if let p = l.location { PLChip(word: p, tint: PLOS.dim(scheme)) }
                    }
                    if let w = l.website, let u = URL(string: w.hasPrefix("http") ? w : "https://\(w)") { Link(w, destination: u).font(.caption) }
                    if let o = l.opener { Text(o).font(.caption) }
                }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            if let failed, s == nil { Text(failed).foregroundStyle(.secondary) }
            if s == nil && failed == nil { PLLoader() }
            if let s {
                Section {
                    // the state first, as a colour: green and breathing when connected, red when Pinterest refuses the house (his ask 11-14)
                    HStack {
                        PLStateDot(word: s.connected == true ? "Connected" : "Not connected", tint: s.connected == true ? PLOS.ok : PLOS.danger, text: PLOS.text(scheme))
                        Spacer()
                        if s.connected == true, let u = s.account?.username { PLChip(word: "@" + u, tint: PLOS.gold) }
                    }
                    if s.connected == true {
                        HStack(spacing: 12) {
                            PLBigTile(number: "\((s.queue ?? []).count)", label: "Drafts waiting", tint: PLOS.gold, text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                            PLBigTile(number: "\((s.pins ?? []).count)", label: "Pins on the board", tint: PLOS.gold, text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                        }
                        HStack(spacing: 6) {
                            PLChip(word: s.board?.name ?? "board made with the first pin", tint: PLOS.dim(scheme))
                            if let t = s.account?.account_type { PLChip(word: t, tint: PLOS.dim(scheme)) }
                        }
                    } else {
                        Text("Pinterest refused the house's sign-in. Connect it again in pl-os on the laptop: Pinterest's sign-in returns to that page.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let e = s.error { Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(PLOS.warn) }
                }.listRowBackground(OSRowBackground())
                if s.connected == true {
                    Section {
                        if (s.queue ?? []).isEmpty { Text("No Pinterest drafts waiting.").foregroundStyle(.secondary) }
                        ForEach(s.queue ?? []) { r in
                            HStack(spacing: 12) {
                                AsyncImage(url: r.media_url.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(r.caption ?? "").font(.callout).lineLimit(3)
                                Spacer(minLength: 0)
                                // a Pin is published by approving its draft (his tap), through the real publisher with its title, link and board
                                Link("Approve", destination: URL(string: "pldev://section/house/approvals")!)
                                    .buttonStyle(.bordered).tint(PLOS.gold)
                            }
                        }
                    } header: { Text("Drafts") } footer: { Text("Each Pin waits for your tap, as Pinterest's rules require: approve it in Approvals and it goes out with its title, link and board.") }.listRowBackground(OSRowBackground())
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
                        }.listRowBackground(OSRowBackground())
                    }
                }
            }
            if let note { Section { ResultLine(text: note) }.listRowBackground(OSRowBackground()) }
        }
        .navigationTitle("Pinterest")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { s = try await Console.get("run/pinterest-sandbox", Sandbox.self, model: model); failed = nil }
        catch { failed = plainSentence(error) }
    }
}
