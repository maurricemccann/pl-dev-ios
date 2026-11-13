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
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
    }

    // MARK: the house

    private var houseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The house").plHand(20)
            if let h = house {
                HStack(alignment: .top) {
                    stat("Needs you", "\(h.needs)", h.needs > 0 ? PLTone.bad : nil)
                    stat("Approve", "\(h.approve)", nil)
                    stat("In the drip", "\(h.queued)", nil)
                    stat("Standing", "\(h.standing)", nil)
                }
                Text("\(h.week) drafts made this week").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not read yet. House opens with the full console.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
    }

    private func stat(_ name: String, _ value: String, _ tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit().foregroundStyle(tint ?? .primary)
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            Text(name).plLabel(10).foregroundStyle(.secondary)
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
