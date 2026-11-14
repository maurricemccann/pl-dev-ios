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
        struct Pool: Decodable { let time: String; let nonpaged_mb: Int; let paged_mb: Int; var gb: Double { Double(nonpaged_mb + paged_mb) / 1024 } }
        let thermal: [Reading]?; let disk_free_gb: Double?; let disk_total_gb: Double?; let uptime_h: Double?; let sessions: Int?; let pool: [Pool]?
    }
    struct HouseGlanceNumbers { var needs = 0; var approve = 0; var standing = 0; var queued = 0; var week = 0 }

    var body: some View {
        VStack(spacing: 14) {
            nowLine
            HomeStatusStrip(model: model)
            pcCard
            houseCard
            townCard
            practiceCard
            askBar
        }
        .task { await load() }
        .task {   // the PC moves; read it again every minute while Home is on screen
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); await loadPC() }
        }
    }

    // MARK: now (WHOOP's insight line on Mobbin, 11-13): the one thing worth knowing, in a sentence, from the real numbers

    private var nowLine: some View {
        let pool = pc?.pool?.last?.gb
        // the fourth value is where a tap goes (his note 11-14: "The 230 approve at the top: if I click on it, it should take me to where
        // I need to approve"): the approvals list when drafts wait, the founder's list when only requests wait, nothing for the PC lines
        let (text, tint, symbol, target): (String, Color, String, String?) = {
            if let h = house, h.needs > 0 { return ("\(h.needs) need\(h.needs == 1 ? "s" : "") you\(h.approve > 0 ? ", \(h.approve) to approve" : "").", PLTone.bad, "exclamationmark.circle.fill", h.approve > 0 ? "house/approvals" : "house/founder") }
            if let p = pool, p >= 5 { return (String(format: "Kernel pool at %.1f GB: reboot the PC soon.", p), PLTone.bad, "arrow.clockwise.circle.fill", nil) }
            if let h = house, h.approve > 0 { return ("\(h.approve) to approve.", PLTone.warn, "checkmark.seal.fill", "house/approvals") }
            if let p = pool, p >= 3 { return (String(format: "Kernel pool climbing: %.1f GB.", p), PLTone.warn, "square.stack.3d.down.right.fill", nil) }
            if house == nil && pc == nil { return pcFailed ? ("The house and the PC are out of reach: Tailscale may be off.", PLTone.warn, "wifi.exclamationmark", nil) : ("Reading the house and the PC.", Color.secondary, "ellipsis.circle", nil) }
            return ("All clear.", PLTone.good, "checkmark.circle.fill", nil)
        }()
        let line = HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).plFont(.callout, emphasized: true).lineLimit(2)
            Spacer(minLength: 0)
            if target != nil { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
        }
        .padding(14)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        return Group {
            if let target { door(target) { line }.accessibilityHint("Opens the list") } else { line }
        }
    }

    // MARK: practice (the streak tiles of How We Feel and pillowtalk on Mobbin): read from the glance Practice writes

    /// Task Town on the Today page (his note 11-14: "we're missing the town widget"): the Roadmap's counts and where the session is.
    private var townCard: some View {
        let g = SharedState.readTown()
        return door("town") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Task Town").plHand(20)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                }
                if let g {
                    HStack(alignment: .top) {
                        stat("Open", icon: "building.2", "\(g.open)", nil)
                        stat("Done", icon: "checkmark", "\(g.done)", g.done > 0 ? PLStatus.good : nil)
                        stat("On you", icon: "person", "\(g.his)", g.his > 0 ? PLStatus.warn : nil)
                        stat("Blocked", icon: "exclamationmark.octagon", "\(g.blocked)", g.blocked > 0 ? PLStatus.bad : nil)
                    }
                    Text(g.working ? "The session is at \((g.at ?? "work").capitalized)." : "The session is quiet.").plFont(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Open the town once and its numbers live here.").plFont(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        }
    }

    @ViewBuilder private var practiceCard: some View {
        if let g = PracticeGlance.read() {
            door("practice") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("The practice").plHand(20)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    }
                    HStack(alignment: .top) {
                        stat("This month", icon: "flame", "\(g.monthDays)", g.monthDays > 0 ? PLStatus.good : nil)
                        stat("This week", icon: "calendar", "\(g.weekDays)/7", nil)
                        stat("Morning", icon: "sunrise", g.morning ? "Done" : "Open", g.morning ? PLStatus.good : PLStatus.warn)
                        stat("Evening", icon: "moon.stars", g.evening ? "Done" : "Open", g.evening ? PLStatus.good : nil)
                    }
                    if let line = g.line { Text(line).plHand(16).foregroundStyle(.primary).lineLimit(3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
            }
        }
    }

    // MARK: ask (Bevel's "Ask anything" bar on Mobbin): one tap from the dashboard to the Oracle

    private var askBar: some View {
        door("glyphbot/ask") {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(.white)
                Text("Ask GlyphBot anything").foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "arrow.up.circle.fill").font(.title3).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    // MARK: the PC

    private var pcCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The PC").plHand(20)
                Spacer()
                if let at = pc?.thermal?.last?.date {
                    // the PC logs every 5 minutes: a reading over 10 minutes old is late, over 30 means the logger has stopped
                    let fresh = PLStatus.higherIsWorse(Date.now.timeIntervalSince(at) / 60, warn: 10, bad: 30)
                    Text(at, style: .relative).font(.caption2.monospacedDigit()).foregroundStyle(fresh.tone) + Text(" ago").font(.caption2).foregroundStyle(fresh.tone)
                }
            }
            if let last = pc?.thermal?.last {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    // every threshold below is what the number means on this PC: the chassis heat (throttling starts near 85), the CPU's load at this
                    // instant, free RAM (under 2 GB it pages to disk), free disk. Uptime has no good or bad of its own: the kernel pool is its signal.
                    stat("Heat", icon: "thermometer.medium", "\(last.temp_c)°", Double(last.temp_c).map { PLStatus.higherIsWorse($0, warn: 70, bad: 85) })
                    stat("CPU", icon: "cpu", "\(last.cpu_pct)%", Double(last.cpu_pct).map { PLStatus.higherIsWorse($0, warn: 70, bad: 90) })
                    stat("Free RAM", icon: "memorychip", "\(last.free_ram_gb) GB", Double(last.free_ram_gb).map { PLStatus.lowerIsWorse($0, warn: 4, bad: 2) })
                    stat("Disk free", icon: "internaldrive", pc?.disk_free_gb.map { "\(Int($0)) GB" } ?? "·", (pc?.disk_free_gb).map { PLStatus.lowerIsWorse($0, warn: 80, bad: 30) })
                    stat("Up", icon: "clock", pc?.uptime_h.map { $0 >= 48 ? "\(Int($0 / 24)) d" : "\(Int($0)) h" } ?? "·", nil)
                    // kernel pool: grows with file activity and only a reboot clears it; amber at 3 GB, red (reboot) at 5 GB (his ask 11-13)
                    if let k = pc?.pool?.last {
                        stat("Kernel pool", icon: "square.stack.3d.down.right", String(format: "%.1f GB", k.gb), PLStatus.higherIsWorse(k.gb, warn: 3, bad: 5))
                    }
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
                PLLoader().frame(maxWidth: .infinity)
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
                    door("house/founder") { stat("Needs you", icon: "exclamationmark.circle", "\(h.needs)", PLStatus.waiting(h.needs, whenAny: .bad)) }   // a tap opens what needs him (his note 11-13)
                    door("house/approvals") { stat("Approve", icon: "checkmark.seal", "\(h.approve)", PLStatus.waiting(h.approve)) }   // drafts waiting on his tap: none is clear, any is amber
                    stat("In the drip", icon: "drop", "\(h.queued)", nil)
                    stat("Standing", icon: "chart.bar", "\(h.standing)", nil)
                }
                Text("\(h.week) drafts made this week").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not read yet. House opens with the full console.").font(.callout).foregroundStyle(.secondary)
            }
            door("house") {   // the card's foot opens the whole room, like a widget's "see trends" (11-13)
                HStack(spacing: 4) { Text("Open the house").plLabel(10); Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)) }
                    .foregroundStyle(.white.opacity(0.9)).padding(.top, 2)   // white on the Today page: the key colour is the wallpaper's own (11-13)
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

    /// A tile the way the tile dashboards draw one (How We Feel, Bevel on Mobbin, 11-13): the icon, the number, the word. A known
    /// good or bad (his note 11-14) tints the number, washes the tile and hints the name; no level, no tint.
    private func stat(_ name: String, icon: String, _ value: String, _ level: PLStatus?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(level?.tone ?? PLTone.accent).frame(height: 16)
            Text(value).font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit().plStatusValue(level)
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            Text(name).plLabel(10).plStatusName(level).lineLimit(1).minimumScaleFactor(0.6)   // "Standing" kept its g on one line (11-13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, level == nil ? 0 : 8).padding(.vertical, level == nil ? 0 : 6)
        .plStatusTile(level)
        .accessibilityElement(children: .combine)
        .accessibilityValue(level.map { $0 == .good ? "fine" : $0 == .warn ? "watch" : "needs you" } ?? "")
    }

    // MARK: reads

    private func load() async {
        #if targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: "simDemo") { demoFixtures(); return }   // the screenshots workflow has no key: fixed numbers, one of each level
        #endif
        async let p: Void = loadPC()
        async let h: Void = loadHouse()
        _ = await (p, h)
    }

    #if targetEnvironment(simulator)
    /// Simulator only, never in a device build: numbers that show every level (green, amber, red) so the tints can be looked at in a screenshot.
    private func demoFixtures() {
        let now = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-4 * 60))
        func r(_ t: Int, _ cpu: Int, _ ram: Double, _ at: String) -> PCStats.Reading { .init(time: at, temp_c: "\(t)", cpu_pct: "\(cpu)", clock_pct: "100", free_ram_gb: String(ram), battery_pct: "100", on_ac: "True") }
        var rows: [PCStats.Reading] = []
        for i in 0..<12 { rows.append(r(60 + i * 2, 40 + (i % 5) * 9, 5.2 - Double(i) * 0.15, ISO8601DateFormatter().string(from: .now.addingTimeInterval(Double(-(60 - i * 5)) * 60)))) }
        rows.append(r(78, 93, 1.6, now))
        pc = PCStats(thermal: rows, disk_free_gb: 412, disk_total_gb: 953, uptime_h: 61, sessions: 3, pool: [.init(time: now, nonpaged_mb: 1800, paged_mb: 1700)])
        house = HouseGlanceNumbers(needs: 0, approve: 230, standing: 71, queued: 38, week: 142)
        pcFailed = false
    }
    #endif

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
    /// The strip's wash: green while every address answers, red when one does not, none until the first check is back.
    private var stripTone: Color? { state.checkedAt == nil ? nil : state.downCount == 0 ? PLTone.good : PLTone.bad }

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
            .glassEffect(.regular.tint(stripTone.map { $0.opacity(0.14) }), in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
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
