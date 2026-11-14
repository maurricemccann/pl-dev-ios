import SwiftUI
import Charts

/// Under the Home grid (his ask 11-13: "the 3D heart model also on our home app to make it less empty, we can add a dashboard with
/// my PC's stats and stats of anything you think is useful"): the PC's own numbers from the PL Call
/// server (tailnet, keyed), and the house at a glance. Every card says when it could not be read; nothing here writes.
struct HomeDashboard: View {
    let model: AppModel
    @State private var pc: PCStats?
    @State private var pcFailed = false
    @State private var house: HouseGlanceNumbers?

    struct PCStats: Decodable {
        struct Reading: Decodable, Identifiable {
            let time: String; let temp_c: String; let cpu_pct: String; let clock_pct: String; let free_ram_gb: String; let battery_pct: String; let on_ac: String
            var id: String { time }
            var date: Date { ISO8601DateFormatter().date(from: time) ?? .distantPast }
        }
        let thermal: [Reading]?; let disk_free_gb: Double?; let disk_total_gb: Double?; let uptime_h: Double?; let sessions: Int?
    }
    struct HouseGlanceNumbers { var needs = 0; var approve = 0; var standing = 0; var queued = 0; var week = 0 }

    var body: some View {
        VStack(spacing: 14) {
            HomeStatusStrip(model: model)
            pcCard
            houseCard
        }
        .task { await load() }
        .task {   // the PC moves; read it again every minute while Home is on screen
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); await loadPC() }
        }
    }

    // MARK: the PC

    private var pcCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The PC").plHand(20)
                Spacer()
                if let at = pc?.thermal?.last?.date { Text(at, style: .relative).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) + Text(" ago").font(.caption2).foregroundStyle(.secondary) }
            }
            if let last = pc?.thermal?.last {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    stat("Heat", "\(last.temp_c)°", Double(last.temp_c).map { $0 >= 85 ? PLTone.bad : $0 >= 70 ? PLTone.warn : PLTone.good })
                    stat("CPU", "\(last.cpu_pct)%", nil)
                    stat("Free RAM", "\(last.free_ram_gb) GB", Double(last.free_ram_gb).map { $0 < 2 ? PLTone.bad : $0 < 4 ? PLTone.warn : PLTone.good })
                    stat("Battery", "\(last.battery_pct)%\(last.on_ac == "True" ? " ⚡︎" : "")", nil)
                    stat("Disk free", pc?.disk_free_gb.map { "\(Int($0)) GB" } ?? "·", (pc?.disk_free_gb).map { $0 < 30 ? PLTone.bad : $0 < 80 ? PLTone.warn : PLTone.good })
                    stat("Up", pc?.uptime_h.map { $0 >= 48 ? "\(Int($0 / 24)) d" : "\(Int($0)) h" } ?? "·", nil)
                }
                if let rows = pc?.thermal, rows.count > 2 {
                    Chart(rows) { r in
                        LineMark(x: .value("Time", r.date), y: .value("Heat", Double(r.temp_c) ?? 0), series: .value("", "Heat")).foregroundStyle(PLTone.accent)
                        LineMark(x: .value("Time", r.date), y: .value("CPU", Double(r.cpu_pct) ?? 0), series: .value("", "CPU")).foregroundStyle(.secondary)
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(height: 54)
                    .accessibilityLabel("Heat and CPU over the last two hours")
                }
                if let n = pc?.sessions { Label("\(n) Claude session\(n == 1 ? "" : "s") on the bus", systemImage: "terminal").font(.caption).foregroundStyle(.secondary) }
            } else if pcFailed {
                Text("The PC did not answer. It may be asleep, or off the tailnet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // full width whatever the text (11-13: a short line shrank the card)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
    }

    // MARK: the house

    private var houseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The house").plHand(20)
            if let h = house {
                HStack(alignment: .top) {
                    door("house/founder") { stat("Needs you", "\(h.needs)", h.needs > 0 ? PLTone.bad : nil) }   // a tap opens what needs him (his note 11-13)
                    door("house/approvals") { stat("Approve", "\(h.approve)", nil) }
                    stat("In the drip", "\(h.queued)", nil)
                    stat("Standing", "\(h.standing)", nil)
                }
                Text("\(h.week) drafts made this week").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not read yet. House opens with the full console.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // full width whatever the text (11-13: a short line shrank the card)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
    }

    @Environment(\.openURL) private var openURL
    private func door<V: View>(_ path: String, @ViewBuilder _ content: () -> V) -> some View {
        Button { if let u = URL(string: "pldev://section/" + path) { openURL(u) } } label: { content().contentShape(Rectangle()) }.buttonStyle(.plain)
    }

    private func stat(_ name: String, _ value: String, _ tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit().foregroundStyle(tint ?? .primary)
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            Text(name).plLabel(10).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)   // "Standing" kept its g on one line (11-13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: reads

    private func load() async {
        async let p: Void = loadPC()
        async let h: Void = loadHouse()
        _ = await (p, h)
    }

    private func loadPC() async {
        guard let http = model.http, let key = model.config?.key("call"), !key.isEmpty else { pcFailed = true; return }
        do {
            let d = try await http.send(RequestPlan(origin: "call", path: "pcstats"), extraHeaders: ["X-Call-Key": key], timeout: 12, cache: false)
            pc = try JSONDecoder().decode(PCStats.self, from: d); pcFailed = false
        } catch { pcFailed = pc == nil }
    }

    private func loadHouse() async {
        guard model.config?.origins["console"] != nil else { return }
        let stats = try? await Console.q("draftstats", HouseModel.DraftStats.self, model: model)
        let standing = await HouseModel.standingRead(model: model)
        let counts = try? await Console.q("counts", HouseModel.Counts.self, model: model)
        var h = HouseGlanceNumbers()
        h.approve = stats?.pending ?? 0; h.queued = stats?.queued ?? 0; h.week = stats?.week_total ?? 0
        h.standing = standing?.total ?? 0
        h.needs = (counts?.desiresPending ?? 0) + (counts?.captures ?? 0)
        if stats != nil || standing != nil { house = h }
    }
}


/// Status as one strip on Home (his mockup 11-13: the Status tile crossed out, its checks shown in a row): a green check for each
/// address that answers, red for one that does not, and a gold check for each key that is set. Tap it for the full Status screen.
struct HomeStatusStrip: View {
    let model: AppModel
    private var state: StatusModel { StatusSection.state }

    var body: some View {
        let origins = model.config?.origins.keys.sorted() ?? []
        let keys = (model.config?.keys ?? [:]).sorted { $0.key < $1.key }
        NavigationLink { StatusSection.makeRoot(model: model) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status").plHand(18)
                    Spacer()
                    let down = state.downCount
                    Text(state.checkedAt == nil ? "checking" : down == 0 ? "all answering" : "\(down) not answering")
                        .plLabel(10).foregroundStyle(down == 0 ? PLTone.good : PLTone.bad)
                }
                // a signal per address and a key per key (his note 11-13: checkmarks said nothing about what they were)
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 18)
                    FlowRow {
                        ForEach(origins, id: \.self) { name in mark(reach: state.reach[name]).accessibilityLabel("\(name): \(label(state.reach[name]))") }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 18)
                    FlowRow {
                        ForEach(keys, id: \.key) { k in
                            Image(systemName: k.value.isEmpty ? "key.slash" : "key.fill")
                                .font(.system(size: 17)).foregroundStyle(k.value.isEmpty ? Color.secondary : Color(hex: 0xc9a84c))
                                .accessibilityLabel("\(k.key) key \(k.value.isEmpty ? "not set" : "set")")
                        }
                    }
                }
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .task { if state.checkedAt == nil { await state.check(model: model) } }
    }

    private func mark(reach: OriginReach?) -> some View {
        let (symbol, tint): (String, Color) = {
            switch reach { case .up?: return ("cellularbars", PLTone.good); case .down?: return ("antenna.radiowaves.left.and.right.slash", PLTone.bad); default: return ("cellularbars", Color.secondary) }
        }()
        return Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint)
    }

    private func label(_ r: OriginReach?) -> String {
        switch r { case .up?: return "answering"; case .down(let why)?: return "not answering, \(why)"; default: return "not asked yet" }
    }
}

/// Wraps its marks onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320; var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for v in subviews { let s = v.sizeThatFits(.unspecified); if x + s.width > w, x > 0 { x = 0; y += line + spacing; line = 0 }; x += s.width + spacing; line = max(line, s.height) }
        return CGSize(width: w, height: y + line)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, line: CGFloat = 0
        for v in subviews { let s = v.sizeThatFits(.unspecified); if x + s.width > b.maxX, x > b.minX { x = b.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += s.width + spacing; line = max(line, s.height) }
    }
}
