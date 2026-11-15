import SwiftUI

/// Home page 4: PL Performance (Plans/SPEC — PL DEV PERFORMANCE PAGE (S348), his ask 11-14). Business and social numbers that are not on
/// the Today page, in one read from pl-cron `api/widget/performance` (totals only). A number that was not read shows a dash, never a zero.
struct PerformancePage: View {
    let model: AppModel
    @State private var data: Performance?
    @State private var failed = false
    @State private var loading = false

    struct Performance: Decodable {
        struct Line: Decodable { let amount: Double; let label: String }
        struct Money: Decodable { let ytd: Double?; let month: Double?; let last7: Double?; let orders_ytd: Int?; let lines: [Line]?; let source: String? }
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
    }

    /// The on-device model's word on one suggestion: nil = not judged yet.
    @State private var judged: [Int: (can: Bool, step: String)] = [:]
    @State private var judging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Performance").plFont(.title2, emphasized: true).foregroundStyle(.white)
                Text(failed ? "Could not read the house. Pull down to try again." : (data == nil ? "Reading the house…" : "Business and social, live from the house."))
                    .plFont(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            moneyCard
            monthsCard
            tasksCard
            suggestionsCard
            audienceCard
            landedCard
            weeklyCard
            topCard
            costCard
        }
        .padding(.horizontal, PLSpace.margin).padding(.top, PLSpace.gap).padding(.bottom, 120)
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
            await judge()
        } catch {
            failed = data == nil
        }
    }

    // MARK: cards

    private func card<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).plHand(20)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
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
        card("Money") {
            let m = data?.money
            HStack(alignment: .top) {
                figure("This year", dollars(m?.ytd))
                figure("This month", dollars(m?.month))
                figure("Last 7 days", dollars(m?.last7))
                figure("Orders", count(m?.orders_ytd))
            }
            // the goal lines and their words come from the house (private), never from this public code
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
            if let s = m?.source { Text("Source: \(s).").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var audienceCard: some View {
        card("Audience") {
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
        card("What landed, 14 days") {
            let l = data?.landed
            if let rows = l?.channels, !rows.isEmpty {
                HStack {
                    Text("Channel").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Posts").frame(width: 40, alignment: .trailing)
                    Text("Avg views").frame(width: 66, alignment: .trailing)
                    Text("Likes").frame(width: 44, alignment: .trailing)
                    Text("Comments").frame(width: 66, alignment: .trailing)
                }
                .plLabel(9).foregroundStyle(.secondary)
                ForEach(rows) { r in
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(level(r)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.channel.capitalized).font(.callout).lineLimit(1).minimumScaleFactor(0.7)
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
        }
    }

    /// The colour of a channel's row: green when it is landing (ten or more responses), amber when it gets some, grey when it cannot be compared.
    private func level(_ r: Performance.Channel) -> Color {
        if r.engagement >= 10 { return PLTone.good }
        if r.engagement > 0 || (r.avg_views ?? 0) >= 20 { return PLTone.warn }
        return Color.secondary
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
        }
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
        card("Revenue by month") {
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
        card("13 weeks") {
            let rows = data?.weekly ?? []
            let top = Double(max(rows.map(\.engagement).max() ?? 0, 1))
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "No posts measured.").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Week of").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Posts").frame(width: 48, alignment: .trailing)
                    Text("Reach").frame(width: 60, alignment: .trailing)
                    Text("Engaged").frame(width: 64, alignment: .trailing)
                }
                .plLabel(10).foregroundStyle(.secondary)
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
        card("Best posts, 30 days") {
            let rows = data?.top_posts ?? []
            if rows.isEmpty {
                Text(data == nil ? "Not read yet." : "No posts measured.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(r.channel.capitalized) · \(r.day) · \(r.engagement) engaged · reach \(count(r.reach))").plLabel(10).foregroundStyle(.secondary)
                    Text(r.caption).font(.footnote).lineLimit(3)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var costCard: some View {
        card("AI cost") {
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
        }
    }
}
