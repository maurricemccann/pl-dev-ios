import SwiftUI
import Charts

/// Home page 4: PL Performance (Plans/SPEC — PL DEV PERFORMANCE PAGE (S348), his ask 11-14). Business and social numbers that are not on
/// the Today page, in one read from pl-cron `api/widget/performance` (totals only). A number that was not read shows a dash, never a zero.
struct PerformancePage: View {
    let model: AppModel
    @State private var data: Performance?
    @State private var failed = false
    @State private var loading = false
    /// The Standing Board's "needs you" rows, pushed by the PC sync as a note tail (`api/widget/note?t=board`). nil = not read.
    @State private var board: BoardRows?
    struct BoardRows { let pulled: String; let link: URL?; let rows: [(call: Bool, text: String)] }
    private struct BoardTail: Decodable { let text: String }

    struct Performance: Decodable {
        struct Line: Decodable { let amount: Double; let label: String }
        struct Patron: Decodable, Identifiable { let seat: Int; let day: String; let total: Double?; var id: Int { seat } }
        struct Money: Decodable { let ytd: Double?; let month: Double?; let last7: Double?; let orders_ytd: Int?; let patrons: [Patron]?; let lines: [Line]?; let source: String? }
        struct Audience: Decodable { let ig_followers: Int?; let ig_7d: Int?; let ig_30d: Int?; let subscribers: Int?; let subscribers_30d: Int? }
        struct Channel: Decodable, Identifiable {
            let channel: String; let posts: Int; let reach: Int; let engagement: Int
            let likes: Int?; let comments: Int?; let avg_views: Double?
            var id: String { channel }
        }
        struct TaskLine: Decodable, Identifiable { let title: String; let due: String?; var id: String { title } }
        struct Lead: Decodable, Identifiable { let id: Int; let name: String; let why: String?; let takes: String?; let confidence: String?; let deadline: String? }
        struct Suggestions: Decodable { let rules: String?; let leads: [Lead]? }
        struct Post: Decodable { let channel: String?; let day: String?; let reach: Int?; let engagement: Int?; let caption: String? }
        struct Landed: Decodable { let days: Int?; let channels: [Channel]?; let comments_total: Int?; let best: Post?; let weakest: Post? }
        struct Job: Decodable, Identifiable { let job: String; let calls: Int; var id: String { job } }
        struct Cost: Decodable { let calls_7d: Int?; let calls_today: Int?; let cap_per_day: Int?; let jobs: [Job]? }
        struct Month: Decodable, Identifiable { let month: String; let total: Double; let orders: Int; var id: String { month } }
        struct Week: Decodable, Identifiable { let start: String; let posts: Int; let reach: Int; let engagement: Int; var id: String { start } }
        struct Top: Decodable, Identifiable { let channel: String; let day: String; let reach: Int?; let engagement: Int; let caption: String; var id: String { channel + day + caption } }
        let money: Money?; let audience: Audience?; let landed: Landed?; let cost: Cost?
        let months: [Month]?; let weekly: [Week]?; let top_posts: [Top]?
        let tasks: [TaskLine]?; let suggestions: Suggestions?
        struct Order: Decodable, Identifiable { let no: String?; let day: String; let total: Double?; let currency: String?; let status: String?; let kind: String?; var id: String { (no ?? "") + day + "\(total ?? 0)" } }
        struct Attention: Decodable, Identifiable { let label: String; let count: Int?; let room: String?; var id: String { label } }
        let orders: [Order]?; let attention: [Attention]?
        /// The site's last 28 days from Google Analytics (the PC board reads it each night and posts it to the house).
        struct Site: Decodable {
            struct Totals: Decodable { let users_28d: Int?; let sessions_28d: Int?; let views_28d: Int? }
            struct Day: Decodable, Identifiable { let date: String; let users: Int; let sessions: Int; let views: Int; var id: String { date } }
            struct Page: Decodable, Identifiable { let path: String; let views: Int; let users: Int; var id: String { path } }
            struct Source: Decodable, Identifiable { let source: String; let medium: String; let sessions: Int; var id: String { source + "/" + medium } }
            let totals: Totals?; let days: [Day]?; let pages: [Page]?; let sources: [Source]?; let as_of: String?
        }
        let site: Site?
    }

    @Environment(\.openURL) private var openURL

    /// Claude usage as this PC records it (PL Call's `pcstats`, tailnet, keyed): the board's Console calls, Claude Code's 5-hour block,
    /// and the weekly limit only when a session has read it off the account page. Nothing here is estimated.
    struct ClaudeUse: Decodable {
        struct Block: Decodable { let generated: String?; let active: Bool?; let block_end: String?; let minutes_left: Int?; let tokens: Double?; let requests: Int?; let pct_of_peak: Double? }
        struct Week: Decodable { let pct: Double?; let read_at: String?; let resets: String? }
        /// The Console's own Billing and Cost pages, as a session last read them (11-23: the board is not the only Console spender)
        struct Credit: Decodable { let read_at: String?; let credit_left: Double?; let credit_total: Double?; let expires: String?; let spent_7d: Double?; let spent_30d: Double? }
        let board_day: String?; let board_calls: Int?; let board_cap: Int?; let block: Block?; let week: Week?; let five: Week?; let console: Credit?
    }
    private struct PCReply: Decodable { let claude: ClaudeUse? }
    @State private var claude: ClaudeUse?
    @State private var claudeFailed = false

    /// The on-device model's word on one suggestion: nil = not judged yet.
    @State private var judged: [Int: (can: Bool, step: String)] = [:]
    @State private var judging = false
    @State private var goalsOpen = false
    @State private var opened: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which half to draw: `.action` leads Today (what needs him, what he can do); `.pulse` is the third Home page.
    enum Part { case action, pulse }
    var part: Part = .pulse
    @State private var runway: ApprovalsModel.Runway?
    /// His one decision per week (Codex's "truth review", his ruling 11-14), kept on this phone by ISO week: "2026-W46" -> text.
    @AppStorage("pldev.weekDecisions") private var decisionsJSON = "{}"
    /// Every "Tonight" tap, newest last: "2026-11-14|approvals" (the first half of Gemini's self-weighting prompts, kept honest).
    @AppStorage("pldev.moveLog") private var moveLog = ""
    /// One experiment a week, from the best post (Codex's reach-into-experiment, his pick N17): "2026-W46" -> text.
    @AppStorage("pldev.weekExperiments") private var experimentsJSON = "{}"
    @State private var experimentDraft = ""
    /// The app's own changes (his pick N19): what it changed, and what it was before, newest last.
    @AppStorage("pldev.todayLead") private var todayLead = ""
    @AppStorage("pldev.appliedChanges") private var appliedJSON = "[]"
    @AppStorage("pldev.settledProposals") private var settledCSV = ""
    @AppStorage("pldev.proposalWeek") private var proposalWeek = ""   // the week he last answered one: one answer a week
    @State private var decisionDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if part == .action {
                tonightCard
                attentionCard
                suggestionsCard
                tasksCard
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pulse").plFont(.title2, emphasized: true).foregroundStyle(.white)
                    Text(failed ? "Could not read the house. Pull down to try again." : (data == nil ? "Reading the house…" : "Reach first, then money, then the machine."))
                        .plFont(.footnote).foregroundStyle(.white.opacity(0.75))
                }
                weekCard
                // reach first (both reviews 11-14: the constraint is reach, not production)
                landedCard
                siteCard
                audienceCard
                topCard
                moneyCard
                ordersCard
                // the machine, moved off Today (his ruling 11-14)
                HomeStatusStrip(model: model)
                HomeDashboard(model: model, part: .machine)
                costCard
            }
        }
        .padding(.horizontal, part == .action ? 0 : PLSpace.margin).padding(.top, part == .action ? 0 : PLSpace.gap).padding(.bottom, part == .action ? 0 : 120)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard !loading, let http = model.http else { failed = model.http == nil; return }
        loading = true
        defer { loading = false }
        do {
            data = try JSONDecoder().decode(Performance.self, from: try await http.send(RequestPlan(origin: "cron", path: "api/widget/performance"), timeout: 30))
            failed = false
            await loadBoard()
            if part == .action { runway = try? await Console.get("run/moderation-runway", ApprovalsModel.Runway.self, model: model) }
            await loadClaude()
            await judge()
        } catch {
            failed = data == nil
        }
    }

    // MARK: cards

    /// A card. With a `glance` it folds (his ruling 11-14, from the Cosmos card he sent): closed it is one line, the title and one
    /// number at a glance; a tap opens it with a small tilt, and the detail grows in. Without a glance it is always open.
    private func card<V: View>(_ title: String, glance: String? = nil, @ViewBuilder _ content: () -> V) -> some View {
        let foldable = glance != nil, isOpen = !foldable || opened.contains(title)
        return VStack(alignment: .leading, spacing: 10) {
            if let glance {
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.28)) {
                        if isOpen { opened.remove(title) } else { opened.insert(title) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).plHand(20)
                        Spacer(minLength: 6)
                        Text(glance).font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit()
                            .foregroundStyle(PLTone.accent).lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(glance)")
                .accessibilityHint(isOpen ? "Folds the card" : "Opens the card")
                if isOpen { content().transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top))) }
            } else {
                Text(title).plHand(20)
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        // the Cosmos card's motion: a closed card leans back a little and comes flat as it opens
        .rotation3DEffect(.degrees(foldable && !isOpen && !reduceMotion ? 7 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
    }

    private func dollars(_ v: Double?) -> String {
        guard let v else { return "\u{2014}" }
        return "$" + (v >= 1000 ? String(format: "%.0f", v) : String(format: "%.2f", v))
    }

    private func count(_ v: Int?) -> String { v.map { "\($0)" } ?? "\u{2014}" }

    private func change(_ v: Int?) -> String {
        guard let v else { return "\u{2014}" }
        return v > 0 ? "+\(v)" : "\(v)"
    }

    private func figure(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(name).plLabel(10).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var moneyCard: some View {
        card("Money", glance: dollars(data?.money?.ytd)) {
            let m = data?.money
            HStack(alignment: .top) {
                figure("This year", dollars(m?.ytd))
                Divider().frame(height: 34)
                figure("This month", dollars(m?.month))
                Divider().frame(height: 34)
                figure("Last 7 days", dollars(m?.last7))
                Divider().frame(height: 34)
                figure("Orders", count(m?.orders_ytd))
            }
            patronsLedger(m?.patrons ?? [])
            // the goal lines and their words come from the house (private), never from this public code; one tap away (his ruling 11-14)
            if !(m?.lines ?? []).isEmpty {
                Button { withAnimation(.snappy) { goalsOpen.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(goalsOpen ? "Hide the goals" : "The goals").plLabel(10)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(goalsOpen ? 90 : 0))
                    }
                    .foregroundStyle(.secondary).frame(minHeight: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if goalsOpen {
                ForEach(Array((m?.lines ?? []).enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(line.label).font(.caption)
                            Spacer()
                            Text(m?.ytd.map { String(format: "%.2f%%", min($0 / max(line.amount, 1), 1) * 100) } ?? "\u{2014}").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: min((m?.ytd ?? 0) / max(line.amount, 1), 1)).tint(PLTone.accent)
                    }
                }
            }
            if (data?.months ?? []).count > 1 { Divider(); monthsCard }   // by month, inside Money (merged 11-14)
        }
    }

    private var audienceCard: some View {
        card("Audience", glance: count(data?.audience?.ig_followers)) {
            let a = data?.audience
            HStack(alignment: .top) {
                figure("IG followers", count(a?.ig_followers))
                figure("7 days", change(a?.ig_7d))
                figure("30 days", change(a?.ig_30d))
            }
            HStack(alignment: .top) {
                figure("Subscribers", count(a?.subscribers))
                figure("30 days", change(a?.subscribers_30d))
                figure("", "")
            }
        }
    }

    private var landedCard: some View {
        card("What landed, 14 days", glance: "\((data?.landed?.channels ?? []).map(\.engagement).reduce(0, +))") {
            let l = data?.landed
            if let rows = l?.channels, !rows.isEmpty {
                HStack {
                    Text("Channel").plLabel(9).frame(maxWidth: .infinity, alignment: .leading)
                    head("square.stack", "Posts").frame(width: 40, alignment: .trailing)
                    head("eye", "Average views").frame(width: 66, alignment: .trailing)
                    head("heart", "Likes").frame(width: 44, alignment: .trailing)
                    head("bubble.right", "Comments").frame(width: 66, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                ForEach(rows) { r in
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(level(r)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.channel.capitalized).font(.callout.weight(.semibold)).foregroundStyle(PLOS.platform(r.channel)).lineLimit(1).minimumScaleFactor(0.7)
                                if r.engagement < 10 { Text("not enough to compare").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(r.posts)").frame(width: 40, alignment: .trailing)
                        Text(r.avg_views.map { String(format: "%.0f", $0) } ?? "\u{2014}").frame(width: 66, alignment: .trailing).foregroundStyle(level(r))
                        Text(count(r.likes)).frame(width: 44, alignment: .trailing)
                        Text(count(r.comments)).frame(width: 66, alignment: .trailing)
                    }
                    .font(.system(.footnote, design: .monospaced)).monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
                Text("\(count(l?.comments_total)) comments across every platform in 14 days. Green: landing. Amber: some response. Grey: not enough to compare.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let b = l?.best, let c = b.caption, !c.isEmpty { post("Best", b, c) }
                if let w = l?.weakest, let c = w.caption, !c.isEmpty { post("Weakest", w, c) }
            } else {
                Text(data == nil ? "Not read yet." : "No posts measured in the last 14 days.").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            weeklyCard   // the 13 weeks, inside What landed (merged 11-14)
        }
    }

    /// The colour of a channel's row: green when it is landing (ten or more responses), amber when it gets some, grey when it cannot be compared.
    private func level(_ r: Performance.Channel) -> Color {
        if r.engagement >= 10 { return PLTone.good }
        if r.engagement > 0 || (r.avg_views ?? 0) >= 20 { return PLTone.warn }
        return Color.secondary
    }

    /// Everything that waits on him, most urgent look first: only lines with something waiting are listed, and a tap opens the room that
    /// handles it. A count that could not be read says so and is never shown as zero.
    private var attentionCard: some View {
        let lines = (data?.attention ?? []).filter { ($0.count ?? 1) > 0 }
        let total = lines.compactMap(\.count).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Needs your attention").plHand(20)
            if data == nil {
                Text("Not read yet.").font(.callout).foregroundStyle(.secondary)
            } else if lines.isEmpty {
                Label("Nothing is waiting on you.", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(PLTone.good)
            }
            ForEach(lines) { a in
                Button {
                    let path = (a.room ?? "").isEmpty ? "section/house" : "section/house/" + (a.room ?? "")
                    if let u = URL(string: "pldev://" + path) { openURL(u) }
                } label: {
                    HStack {
                        Text(a.label).font(.callout)
                        Spacer(minLength: 8)
                        Text(a.count.map { "\($0)" } ?? "not read").font(.system(.callout, design: .monospaced).weight(.semibold)).monospacedDigit()
                            .foregroundStyle(a.count == nil ? Color.secondary : PLTone.warn)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .plGlass(tint: (total > 0 ? PLTone.warn : PLTone.good).opacity(0.18), in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
    }

    /// The latest orders: day, number, amount and state. No customer detail is sent to the phone for this.
    private var ordersCard: some View {
        card("Orders", glance: count(data?.orders?.count)) {
            let rows = data?.orders ?? []
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "No orders yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows) { o in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.day).font(.system(.footnote, design: .monospaced))
                    }
                    Spacer(minLength: 8)
                    Text(dollars(o.total)).font(.system(.callout, design: .monospaced)).monospacedDigit()
                    Text((o.status ?? "").replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(orderTone(o.status))
                        .lineLimit(1).minimumScaleFactor(0.7).frame(width: 78, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func orderTone(_ status: String?) -> Color {
        let s = (status ?? "").uppercased()
        if ["COMPLETED", "FULFILLED", "DELIVERED"].contains(s) { return PLTone.good }
        if ["CANCELED", "CANCELLED", "REFUNDED"].contains(s) { return Color.secondary }
        return PLTone.warn
    }

    /// Site visits from Google Analytics: 28-day totals, visits by day, the pages people open and where they came from.
    private var siteCard: some View {
        card("Site visits", glance: count(data?.site?.totals?.users_28d)) {
            if let s = data?.site {
                HStack(alignment: .top) {
                    figure("Visitors", count(s.totals?.users_28d))
                    Divider().frame(height: 34)
                    figure("Visits", count(s.totals?.sessions_28d))
                    Divider().frame(height: 34)
                    figure("Page views", count(s.totals?.views_28d))
                }
                if let days = s.days, !days.isEmpty {
                    Chart(days) { d in
                        BarMark(x: .value("Day", String(d.date.suffix(5))), y: .value("Visitors", d.users))
                            .foregroundStyle(PLTone.accent.gradient)
                    }
                    .chartXAxis { AxisMarks(values: [days.first, days[days.count / 2], days.last].compactMap { $0.map { String($0.date.suffix(5)) } }) { _ in AxisValueLabel() } }
                    .frame(height: 120)
                    .accessibilityLabel("Visitors each day for 28 days")
                }
                if let pages = s.pages, !pages.isEmpty {
                    Text("Pages they open").plLabel(10).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(pages.prefix(6)) { p in
                        HStack {
                            Text(p.path).font(.system(.footnote, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text("\(p.views)").font(.system(.footnote, design: .monospaced)).monospacedDigit()
                        }
                    }
                }
                if let sources = s.sources, !sources.isEmpty {
                    Text("Where they came from").plLabel(10).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(sources.prefix(6)) { x in
                        HStack {
                            Text(x.source == "(direct)" ? "Typed or bookmarked" : x.source).font(.footnote).lineLimit(1)
                            if x.medium != "(none)" && !x.medium.isEmpty { Text(x.medium).font(.caption2).foregroundStyle(.secondary) }
                            Spacer(minLength: 8)
                            Text("\(x.sessions)").font(.system(.footnote, design: .monospaced)).monospacedDigit()
                        }
                    }
                }
                // Gemini's threshold-unlocked telemetry (his "anything else", 11-14): a rate is shown only when its counts can carry it
                let orders = data?.money?.patrons?.count ?? 0, visitors = s.totals?.users_28d ?? 0
                if orders >= 5 {
                    let recentOrders = (data?.money?.patrons ?? []).filter { $0.day >= String(Date.now.addingTimeInterval(-28 * 86400).formatted(.iso8601.year().month().day())) }.count
                    figure("Visitor to order, 28 days", visitors > 0 ? String(format: "%.1f%%", Double(recentOrders) / Double(visitors) * 100) : "\u{2014}")
                } else {
                    Label("The visitor-to-order rate opens at 5 orders (now \(orders)); fewer cannot carry a rate.", systemImage: "lock")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if visitors < 500 {
                    Label("Page drop-off opens at 500 visitors a month (now \(visitors)).", systemImage: "lock").font(.caption2).foregroundStyle(.secondary)
                }
                Text("Last 28 days, Google Analytics. Read \(String((s.as_of ?? "").prefix(10))).").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(data == nil ? "Not read yet." : "No site read yet: the PC board posts it each night.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// A column head as an icon: never wraps, and says its word to VoiceOver.
    private func head(_ symbol: String, _ name: String) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).accessibilityLabel(name)
    }

    // MARK: the screen is a practice (his idea 11-14; Codex and Gemini's build-first set, all four by his ruling)

    /// The one finishable thing for tonight, from real counts only (PLDevCore `TonightsMove`, tested there).
    private var tonightCard: some View {
        let lanes = (runway?.lane_runway_days ?? [:]).map { TonightsMove.Lane(platform: $0.key, days: $0.value) }
        let waiting = (data?.attention ?? []).compactMap { a in a.count.map { TonightsMove.Waiting(label: a.label, count: $0, room: a.room ?? "") } }
        let move = TonightsMove.pick(lanes: lanes, target: runway?.lane_runway_ceiling_days ?? 14, waiting: waiting,
                                     firstTask: data?.tasks?.first?.title, postsThisWeek: data?.weekly?.last?.posts)
        return Button {
            let entry = String(Date.now.formatted(.iso8601.year().month().day())) + "|" + move.room
            moveLog = (moveLog.split(separator: "\n").suffix(199).map(String.init) + [entry]).joined(separator: "\n")
            if let u = URL(string: "pldev://section/house/" + move.room) { openURL(u) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tonight").plHand(22)
                Text(data == nil ? "Reading the house\u{2026}" : move.text).font(.title3.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                HStack(spacing: 4) { Text("Do it").plLabel(10); Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)) }.foregroundStyle(PLTone.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plGlass(tint: PLTone.accent.opacity(0.22), interactive: true, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        .disabled(data == nil)
        .accessibilityLabel("Tonight: \(move.text)")
    }

    /// Gemini's "First 100 Patrons": a hundred numbered seats, each real paid order fills one (day and amount, no buyer detail).
    private func patronsLedger(_ seats: [Performance.Patron]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("First 100 patrons").plLabel(10).foregroundStyle(.secondary)
                Spacer()
                Text(seats.count >= 100 ? "All 100 seats filled" : "Next: patron \(seats.count + 1)").font(.system(.caption, design: .monospaced)).foregroundStyle(PLTone.accent)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 10), spacing: 3) {
                ForEach(1...100, id: \.self) { n in
                    let filled = n <= seats.count, next = n == seats.count + 1
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(filled ? PLTone.accent : Color.white.opacity(0.06))
                        .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(next ? PLTone.accent : Color.clear, lineWidth: 1.2) }
                        .overlay { if filled || next { Text("\(n)").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(filled ? Color.black : PLTone.accent) } }
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(seats.count) of the first 100 patron seats filled")
            if let last = seats.last { Text("Latest: patron \(last.seat), \(last.day)").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.top, 4)
    }

    /// Codex's weekly truth review: the real week against the one before, and one decision carried into next week.
    private var weekCard: some View {
        let cal = Calendar(identifier: .iso8601)
        let key = { (d: Date) in String(format: "%04d-W%02d", cal.component(.yearForWeekOfYear, from: d), cal.component(.weekOfYear, from: d)) }
        let thisWeek = key(.now), lastWeek = key(cal.date(byAdding: .day, value: -7, to: .now) ?? .now)
        let decisions = (try? JSONDecoder().decode([String: String].self, from: Data(decisionsJSON.utf8))) ?? [:]
        let days = data?.site?.days ?? []
        let recent = days.suffix(7).map(\.users).reduce(0, +), before = days.dropLast(7).suffix(7).map(\.users).reduce(0, +)
        let weeks = data?.weekly ?? []
        return card("This week, honestly", glance: dollars(data?.money?.last7)) {
            HStack(alignment: .top) {
                figure("Sales, 7 days", dollars(data?.money?.last7))
                Divider().frame(height: 34)
                figure("Visitors, 7 days", "\(recent)\(days.count >= 14 ? " (\(recent >= before ? "+" : "")\(recent - before))" : "")")
                Divider().frame(height: 34)
                figure("Posts", weeks.last.map { "\($0.posts)\(weeks.count > 1 ? " (\(weeks[weeks.count - 2].posts) before)" : "")" } ?? "\u{2014}")
            }
            // what he actually did this week, from his own Tonight taps (no guess about what it caused)
            let since = String(Date.now.addingTimeInterval(-7 * 86400).formatted(.iso8601.year().month().day()))
            let moves = moveLog.split(separator: "\n").compactMap { l -> String? in let p = l.split(separator: "|"); return p.count == 2 && String(p[0]) >= since ? String(p[1]) : nil }
            if !moves.isEmpty {
                let by = Dictionary(moves.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value > $1.value }
                Text("Your moves: " + by.map { "\($0.key) \($0.value)" }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            }
            experimentRows(thisWeek: thisWeek, lastWeek: lastWeek)
            proposalRows(moves: moves, thisWeek: thisWeek)
            if let d = decisions[lastWeek], !d.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last week you decided").plLabel(10).foregroundStyle(.secondary)
                    Text(d).font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("One decision for this week").plLabel(10).foregroundStyle(.secondary)
                TextField(decisions[thisWeek] ?? "What will you do differently?", text: $decisionDraft, axis: .vertical)
                    .font(.callout).lineLimit(1...3)
                    .onSubmit { saveDecision(thisWeek) }
                if !decisionDraft.isEmpty {
                    Button("Keep it") { saveDecision(thisWeek) }.font(.footnote.weight(.semibold)).tint(PLTone.accent)
                }
            }
        }
    }

    /// Last week's experiment beside this week's real result, and one experiment for this week drawn from the best post.
    @ViewBuilder private func experimentRows(thisWeek: String, lastWeek: String) -> some View {
        let ex = (try? JSONDecoder().decode([String: String].self, from: Data(experimentsJSON.utf8))) ?? [:]
        let weeks = data?.weekly ?? []
        if let e = ex[lastWeek], !e.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last week's experiment").plLabel(10).foregroundStyle(.secondary)
                Text(e).font(.callout)
                if let w = weeks.last { Text("This week so far: \(w.posts) posts, \(w.reach) reach, \(w.engagement) likes and comments. A hypothesis, not proof.").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            if let best = data?.top_posts?.first {
                Text("Best post: \(best.channel.capitalized), \(best.engagement) likes and comments").font(.caption2).foregroundStyle(.secondary)
            }
            TextField(ex[thisWeek] ?? "One experiment from it this week", text: $experimentDraft, axis: .vertical).font(.callout).lineLimit(1...3)
            if !experimentDraft.isEmpty {
                Button("Keep the experiment") {
                    var d = ex; d[thisWeek] = String(experimentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
                    if let s = try? JSONEncoder().encode(d), let j = String(data: s, encoding: .utf8) { experimentsJSON = j }
                    experimentDraft = ""
                }
                .font(.footnote.weight(.semibold)).tint(PLTone.accent)
            }
        }
    }

    /// The app's one proposal this week (Plans/SPEC — PL DEV PROPOSES ITS OWN CHANGES). The list of what it changed, with Undo, is in Settings.
    @ViewBuilder private func proposalRows(moves: [String], thisWeek: String) -> some View {
        let settled = Set(settledCSV.split(separator: ",").map(String.init))
        let oldest = CaptureSection.state.deck.compactMap { Date.pl($0.created_at) }.min()
        let p = ProposalRules.pick(.init(movesLast7: Dictionary(moves.map { ($0, 1) }, uniquingKeysWith: +),
                                         oldestWaitingCaptureDays: oldest.map { Int(Date.now.timeIntervalSince($0) / 86400) }, settled: settled,
                                         thisWeek: thisWeek, lastActedWeek: proposalWeek.isEmpty ? nil : proposalWeek))
        if let p {
            VStack(alignment: .leading, spacing: 6) {
                Label(p.text, systemImage: "wand.and.stars").font(.callout)
                HStack(spacing: 8) {
                    Button("Yes") {
                        let log = (try? JSONDecoder().decode([ProposalRules.Change].self, from: Data(appliedJSON.utf8))) ?? []
                        let rec = ProposalRules.Change(id: p.id, text: p.text, before: todayLead, at: String(Date.now.formatted(.iso8601.year().month().day())))
                        if p.setting == "todayLead", ProposalRules.allowed["todayLead"]?.contains(p.value) == true { todayLead = p.value }
                        if let s = try? JSONEncoder().encode(log + [rec]), let j = String(data: s, encoding: .utf8) { appliedJSON = j }
                        settledCSV = settled.union([p.id]).joined(separator: ",")
                        proposalWeek = thisWeek
                    }
                    .buttonStyle(.bordered).tint(PLTone.accent).frame(minHeight: 44)
                    Button("Not now") { proposalWeek = thisWeek }.buttonStyle(.bordered).tint(.secondary).frame(minHeight: 44)
                    Button("Never ask") { settledCSV = settled.union([p.id]).joined(separator: ","); proposalWeek = thisWeek }.buttonStyle(.bordered).tint(.secondary).frame(minHeight: 44)
                }
            }
        }
    }

    private func saveDecision(_ week: String) {
        var d = (try? JSONDecoder().decode([String: String].self, from: Data(decisionsJSON.utf8))) ?? [:]
        let t = decisionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        d[week] = String(t.prefix(280))
        if let s = try? JSONEncoder().encode(d), let j = String(data: s, encoding: .utf8) { decisionsJSON = j }
        decisionDraft = ""
    }

    /// His open founder tasks, as the house lists them.
    private var tasksCard: some View {
        card("Founder tasks") {
            let rows = data?.tasks ?? []
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "Nothing open.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows) { t in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle").font(.caption).foregroundStyle(PLTone.accent).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.callout)
                        if let d = t.due, !d.isEmpty { Text("Due \(String(d.prefix(10)))").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Divider().padding(.vertical, 2)
            boardRows
        }
    }

    /// Under the divider: what the Standing Board says needs him, straight from the board's own data. A hand is a thing to do, a
    /// question mark is a call to make. The board itself opens from the last row.
    @ViewBuilder private var boardRows: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Standing Board").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let b = board { Text("\(b.rows.count) · pulled \(b.pulled)").font(.caption2).foregroundStyle(.secondary) }
        }
        if let b = board {
            if b.rows.isEmpty { Text("Nothing waiting on you.").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(b.rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: r.call ? "questionmark.circle" : "hand.raised").font(.caption).foregroundStyle(PLTone.accent).padding(.top, 3)
                        .accessibilityLabel(r.call ? "Your call" : "Your hands")
                    Text(r.text).font(.callout)
                }
            }
            if let u = b.link {
                Button { openURL(u) } label: { Label("Open the Standing Board", systemImage: "arrow.up.right.square").font(.callout) }
                    .frame(minHeight: 44, alignment: .leading)
            }
        } else {
            Text("The board has not been read yet. The PC sends it every 5 minutes.").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Reads the board rows. Lines: "pulled <date>", "link <url>", then "YOURS|text" or "CALL|text". A failed read keeps the last one.
    private func loadBoard() async {
        guard let http = model.http,
              let d = try? await http.send(RequestPlan(origin: "cron", path: "api/widget/note", query: ["t": "board"])),
              let t = try? JSONDecoder().decode(BoardTail.self, from: d), !t.text.isEmpty else { return }
        var pulled = "", link: URL?, rows: [(call: Bool, text: String)] = []
        for line in t.text.split(separator: "\n") {
            if line.hasPrefix("pulled ") { pulled = String(line.dropFirst(7)) }
            else if line.hasPrefix("link ") { link = URL(string: String(line.dropFirst(5))) }
            else if line.hasPrefix("YOURS|") { rows.append((false, String(line.dropFirst(6)))) }
            else if line.hasPrefix("CALL|") { rows.append((true, String(line.dropFirst(5)))) }
        }
        board = BoardRows(pulled: pulled, link: link, rows: rows)
    }

    /// The scouts' suggestions, kept to what he can do: the on-device model checks each against the rules the house sends. A suggestion
    /// it says he cannot do is left out; one it could not judge is shown and marked so.
    private var suggestionsCard: some View {
        card("Suggestions you can do") {
            let leads = data?.suggestions?.leads ?? []
            let shown = leads.filter { judged[$0.id]?.can != false }
            if leads.isEmpty {
                Text(data == nil ? "Not read yet." : "The scouts have nothing open.").font(.callout).foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text("Nothing here that you can start this week.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(shown) { l in
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.name).font(.callout.weight(.semibold))
                    if let w = l.why, !w.isEmpty { Text(w).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
                    if let j = judged[l.id] {
                        if !j.step.isEmpty { Label(j.step, systemImage: "arrow.right.circle").font(.footnote).foregroundStyle(PLTone.good) }
                    } else {
                        Text(judging ? "Checking it against what you can do\u{2026}" : "Not checked by the phone: Apple Intelligence is off or still loading.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let d = l.deadline, !d.isEmpty { Text("Deadline \(d)").font(.caption2).foregroundStyle(PLTone.warn) }
                }
                .padding(.vertical, 3)
            }
            let hidden = leads.count - shown.count
            if hidden > 0 { Text("\(hidden) left out: not doable on your terms.").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func loadClaude() async {
        guard let http = model.http, let key = model.config?.key("call"), !key.isEmpty else { claudeFailed = true; return }
        do {
            let d = try await http.send(RequestPlan(origin: "call", path: "pcstats"), extraHeaders: ["X-Call-Key": key], timeout: 12, cache: false)
            claude = try JSONDecoder().decode(PCReply.self, from: d).claude
            claudeFailed = false
        } catch { claudeFailed = claude == nil }
    }

    /// Asks the on-device model about each suggestion, one at a time. Nothing leaves the phone.
    private func judge() async {
        guard !judging, let s = data?.suggestions, let rules = s.rules, !rules.isEmpty else { return }
        judging = true
        defer { judging = false }
        for l in (s.leads ?? []) where judged[l.id] == nil {
            let what = [l.name, l.why ?? "", "What it takes: " + (l.takes ?? "")].joined(separator: "\n")
            if let verdict = await PLIntelligence.doable(what, rules: rules) { judged[l.id] = verdict }
        }
    }

    private func post(_ name: String, _ p: Performance.Post, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(name) · \((p.channel ?? "").capitalized) · \(p.day ?? "") · \(count(p.engagement)) engaged").plLabel(10).foregroundStyle(.secondary)
            Text(caption).font(.footnote).lineLimit(3)
        }
        .padding(.top, 4)
    }

    /// Revenue by month this year (the artifact's "revenue by month" block), a row and a bar per month.
    private var monthsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By month").plLabel(10).foregroundStyle(.secondary)
            let rows = data?.months ?? []
            let top = max(rows.map(\.total).max() ?? 0, 1)
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "No orders this year.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(r.month).font(.system(.footnote, design: .monospaced))
                        Spacer()
                        Text("\(dollars(r.total)) · \(r.orders) order\(r.orders == 1 ? "" : "s")").font(.system(.footnote, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(r.total / top, 1)).tint(PLTone.accent)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Posts, reach and engagement per week for 13 weeks (the artifact's "posts by platform and week", all platforms together).
    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("13 weeks").plLabel(10).foregroundStyle(.secondary)
            let rows = data?.weekly ?? []
            if rows.count >= 3 {
                // reach against his own rhythm (his pick P11): each dot a week, more posts to the right, more reach higher
                Chart(rows) { w in
                    PointMark(x: .value("Posts", w.posts), y: .value("Reach", w.reach)).foregroundStyle(PLTone.accent).symbolSize(60)
                }
                .chartXAxisLabel("posts that week").chartYAxisLabel("reach")
                .frame(height: 140)
                .accessibilityLabel("Reach against posts, one dot per week")
                Text("Each dot is a week. If the dots climb to the right, posting more moved reach.").font(.caption2).foregroundStyle(.secondary)
            }
            let top = Double(max(rows.map(\.engagement).max() ?? 0, 1))
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "No posts measured.").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Week of").plLabel(10).frame(maxWidth: .infinity, alignment: .leading)
                    head("square.stack", "Posts").frame(width: 48, alignment: .trailing)
                    head("eye", "Reach").frame(width: 60, alignment: .trailing)
                    head("heart", "Likes and comments").frame(width: 64, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                VStack(spacing: 3) {
                    HStack {
                        Text(String(r.start.suffix(5))).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(r.posts)").frame(width: 48, alignment: .trailing)
                        Text("\(r.reach)").frame(width: 60, alignment: .trailing)
                        Text("\(r.engagement)").frame(width: 64, alignment: .trailing)
                    }
                    .font(.system(.footnote, design: .monospaced)).monospacedDigit()
                    ProgressView(value: min(Double(r.engagement) / top, 1)).tint(PLTone.accent)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The best posts of the last 30 days, with their captions (the artifact's "best posts").
    private var topCard: some View {
        card("Best posts, 30 days", glance: count(data?.top_posts?.first?.engagement)) {
            let rows = data?.top_posts ?? []
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "No posts measured.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(r.channel.capitalized).font(.caption.weight(.semibold)).foregroundStyle(PLOS.platform(r.channel))
                        Text(String(r.day.suffix(5))).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Label("\(r.engagement)", systemImage: "heart").font(.system(.caption, design: .monospaced))
                        if (r.reach ?? 0) > 0 { Label(count(r.reach), systemImage: "eye").font(.system(.caption, design: .monospaced)) }
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    Text(r.caption).font(.footnote).lineLimit(3)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var costCard: some View {
        card("AI cost", glance: "\(count(data?.cost?.calls_today))/\(count(data?.cost?.cap_per_day))") {
            let c = data?.cost
            HStack(alignment: .top) {
                figure("Calls, 7 days", count(c?.calls_7d))
                figure("Today", count(c?.calls_today))
                figure("Daily cap", count(c?.cap_per_day))
            }
            if let cap = c?.cap_per_day, cap > 0 {
                ProgressView(value: min(Double(c?.calls_today ?? 0) / Double(cap), 1)).tint(PLTone.accent)
            }
            ForEach(c?.jobs ?? []) { j in
                HStack {
                    Text(j.job).font(.footnote).lineLimit(1)
                    Spacer()
                    Text("\(j.calls)").font(.system(.footnote, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Claude").plLabel(10).foregroundStyle(.secondary)
            if let u = claude {
                HStack(alignment: .top) {
                    figure("Board calls today", u.board_calls.map { "\($0) / \(u.board_cap ?? 200)" } ?? "\u{2014}")
                    Divider().frame(height: 34)
                    figure("5-hour limit", u.five?.pct.map { String(format: "%.0f%%", $0) } ?? u.block?.pct_of_peak.map { String(format: "%.0f%% of peak", $0) } ?? "\u{2014}")
                    Divider().frame(height: 34)
                    figure("Week limit", u.week?.pct.map { String(format: "%.0f%%", $0) } ?? "\u{2014}")
                }
                if let b = u.block, let left = b.minutes_left, b.active == true {
                    Text("Block ends \(b.block_end ?? ""), \(left) min left. Read \(String((b.generated ?? "").prefix(16))).").font(.caption2).foregroundStyle(.secondary)
                }
                if let w = u.week, w.pct != nil {
                    Text("Week limit read \(String((w.read_at ?? "").prefix(16)))\(w.resets.map { ", resets \($0)" } ?? "").").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("The limits show here once a Claude Code session on the PC has read them.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
                Text("Console credit").plLabel(10).foregroundStyle(.secondary)
                if let c = u.console, c.credit_left != nil {
                    HStack(alignment: .top) {
                        figure("Credit left", c.credit_left.map { String(format: "$%.2f", $0) + (c.credit_total.map { String(format: " / %.0f", $0) } ?? "") } ?? "\u{2014}")
                        Divider().frame(height: 34)
                        figure("Spent, 7 days", dollars(c.spent_7d))
                        Divider().frame(height: 34)
                        figure("Spent, 30 days", dollars(c.spent_30d))
                    }
                    Text("Read off the Console \(String((c.read_at ?? "").prefix(16)))\(c.expires.map { ", credit expires \(String($0.prefix(10)))" } ?? ""). Board, batches, agents and web search all draw on it.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Shows once a session has read the Console's Billing page.").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(claudeFailed ? "Could not reach the PC (Tailscale may be off)." : "Reading the PC\u{2026}").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
