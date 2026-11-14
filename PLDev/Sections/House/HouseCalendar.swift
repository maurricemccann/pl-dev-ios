import SwiftUI

/// One calendar for the house (his word 11-13: "the product calendar or drop calendar or content calendar should be a calendar with
/// different dots showing which calendar it is on that date; the merch should show the actual merch"). A month grid; each day carries
/// a dot per calendar it is on: gold = content going out, oxblood = merch (a season switch: colourways going on or off the grid),
/// green = a drop (a piece chosen from the tally that day).
/// Tap a day for what is on it, with the real pictures. The day pager and the merch seasons stay one tap away for the detail work.
struct HouseCalendarView: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var content: [String: [CalendarView.Item]] = [:]   // yyyy-mm-dd → items, every platform
    @State private var platforms: [String: Set<String>] = [:]
    @State private var merch: [MerchView.Row] = []
    /// The drop calendar: each piece chosen from the tally, on the day it was chosen (pl-cron door q/chosen).
    struct Drop: Decodable, Identifiable { let chosen_no: Int; let cr: String; let product: String; let url: String?; let created_at: String; var id: Int { chosen_no } }
    @State private var drops: [String: [Drop]] = [:]
    @State private var pictures: [String: URL] = [:]                  // product name → its picture
    @State private var picked: String?
    @State private var failed: String?

    private static let contentDot = PLOS.gold
    private static let merchDot = Color(hex: 0xa3453f)
    private static let dropDot = PLOS.ok
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                grid
                legend
                if let failed { Text(failed).font(.footnote).foregroundStyle(PLOS.dim(scheme)) }
                OSPanel(title: "The detail rooms") {
                    NavigationLink { CalendarView(model: model).osScreen() } label: { OSRow(title: "Content, day by day", meta: "every platform, its target, what is short") { chevron } }.buttonStyle(.plain)
                    NavigationLink { MerchView(model: model).osScreen() } label: { OSRow(title: "Merch seasons", meta: "set each colourway's season") { chevron } }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 24)
        }
        .navigationTitle("Calendar")
        .sheet(item: Binding(get: { picked.map(DayKey.init) }, set: { picked = $0?.id })) { d in
            NavigationStack { dayDetail(d.id).navigationTitle(title(d.id)).navigationBarTitleDisplayMode(.inline) }
                .presentationDetents([.medium, .large]).osScreen()
        }
        .task { await load() }
        .refreshable { await load() }
    }

    struct DayKey: Identifiable { let id: String }

    private var chevron: some View { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(PLOS.goldDim(scheme)) }

    // MARK: the month

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(OSPill()).frame(width: 64)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).plHand(24).foregroundStyle(PLOS.gold)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(OSPill()).frame(width: 64)
        }
    }

    private var grid: some View {
        let first = month
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let symbols = cal.veryShortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        let today = key(.now)
        return VStack(spacing: 6) {
            HStack { ForEach(ordered.indices, id: \.self) { Text(ordered[$0]).osEyebrow(9).foregroundStyle(PLOS.goldDim(scheme)).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<(lead + days), id: \.self) { i in
                    if i < lead { Color.clear.frame(height: 52) }
                    else {
                        let d = cal.date(byAdding: .day, value: i - lead, to: first) ?? first
                        let k = key(d)
                        Button { picked = k } label: {
                            VStack(spacing: 4) {
                                Text("\(i - lead + 1)").osValue(15).foregroundStyle(k == today ? Color.black : PLOS.text(scheme))
                                HStack(spacing: 3) {
                                    if !(content[k] ?? []).isEmpty { Circle().fill(Self.contentDot).frame(width: 6, height: 6) }
                                    if isMerchDay(d) { Circle().fill(Self.merchDot).frame(width: 6, height: 6) }
                                    if !(drops[k] ?? []).isEmpty { Circle().fill(Self.dropDot).frame(width: 6, height: 6) }
                                }
                                .frame(height: 6)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background { if k == today { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PLOS.gold) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibility(d, k))
                    }
                }
            }
        }
        .osCard(padding: 10)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in if abs(v.translation.width) > 60 { shift(v.translation.width < 0 ? 1 : -1) } })
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Label { Text("Content going out").font(.caption) } icon: { Circle().fill(Self.contentDot).frame(width: 8, height: 8) }
            Label { Text("Merch season").font(.caption) } icon: { Circle().fill(Self.merchDot).frame(width: 8, height: 8) }
            Label { Text("Drop").font(.caption) } icon: { Circle().fill(Self.dropDot).frame(width: 8, height: 8) }
        }
        .foregroundStyle(PLOS.dim(scheme))
    }

    // MARK: a day

    @ViewBuilder private func dayDetail(_ k: String) -> some View {
        let items = content[k] ?? []
        let d = date(k)
        List {
            if let d, isMerchDay(d) {
                let season = cal.component(.month, from: d) == 3 ? "ss" : "fw"
                let on = merch.filter { $0.season == season }, off = merch.filter { $0.season == (season == "ss" ? "fw" : "ss") }
                Section("Going on the grid · \(season == "ss" ? "Spring / Summer" : "Fall / Winter")") {
                    if on.isEmpty { Text("No colourway is set to this season.").foregroundStyle(.secondary) }
                    ForEach(on) { r in merchRow(r.product_name) }
                }.listRowBackground(OSRowBackground())
                if !off.isEmpty { Section("Resting from today") { ForEach(off) { r in merchRow(r.product_name) } }.listRowBackground(OSRowBackground()) }
            }
            if let ds = drops[k], !ds.isEmpty {
                Section("Dropped · \(ds.count)") {
                    ForEach(ds) { dr in
                        HStack(spacing: 12) {
                            AsyncImage(url: pictures[dr.product] ?? pictures[dr.cr]) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "sparkles").foregroundStyle(.secondary) }
                                .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dr.product).font(.callout)
                                Text("\(dr.cr) · \(dr.fulfilled_at == nil ? "chosen" : "made")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let u = dr.url.flatMap(URL.init(string:)) { Link(destination: u) { Image(systemName: "arrow.up.right") } }
                        }
                    }
                }.listRowBackground(OSRowBackground())
            }
            Section("Content · \(items.count)") {
                if items.isEmpty { Text("Nothing scheduled this day.").foregroundStyle(.secondary) }
                ForEach(items) { it in
                    HStack(spacing: 10) {
                        if let t = it.thumb, let u = URL(string: t) {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.line ?? "").font(.callout).lineLimit(2)
                            Text("\(it.format ?? "") · \(it.status ?? "")\(Date.pl(it.at).map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.listRowBackground(OSRowBackground())
            if let ps = platforms[k], !ps.isEmpty {
                Section { HStack { ForEach(ps.sorted(), id: \.self) { p in Text(p == "pl_feed" ? "PL feed" : p.capitalized).osEyebrow(8).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3).background(PLOS.platform(p), in: Capsule()) } } }
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// The colourway with its real picture (the shop's transparent PNG, else the Square photo), never a name alone.
    private func merchRow(_ name: String) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: pictures[name]) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "tshirt").foregroundStyle(.secondary) }
                .frame(width: 64, height: 64)
            Text(name).font(.callout)
        }
    }

    // MARK: reads

    private func load() async {
        failed = nil
        async let c = try? Console.get("api/content-calendar", CalendarView.Out.self, model: model, query: ["days": "45", "back": "35"])
        async let m = try? Console.q("merch", [MerchView.Row].self, model: model)
        async let ch = try? Console.q("chosen", [Drop].self, model: model)
        async let cand = try? Console.get("api/drop-candidates", MerchView.C.self, model: model, timeout: 40)
        await ShopStore.shared.load()
        let (cc, mm, cd, chosen) = await (c, m, cand, ch)
        var byDrop: [String: [Drop]] = [:]
        for d in chosen ?? [] { if let day = Date.pl(d.created_at) { byDrop[key(day), default: []].append(d) } }
        drops = byDrop
        if let days = cc?.days {
            var byDay: [String: [CalendarView.Item]] = [:], plats: [String: Set<String>] = [:]
            for d in days {
                for (p, cell) in d.platforms ?? [:] where !(cell.items ?? []).isEmpty {
                    byDay[d.date, default: []] += cell.items ?? []
                    plats[d.date, default: []].insert(p)
                }
            }
            content = byDay; platforms = plats
        } else { failed = "The content calendar did not load. Pull to try again." }
        merch = mm ?? merch
        var pics: [String: URL] = [:]
        for p in ShopStore.shared.pieces { if let s = p.images.first, let u = URL(string: s) { pics[p.name] = u } }
        for c in cd?.items ?? [] where pics[c.name] == nil { if let s = c.image, let u = URL(string: s) { pics[c.name] = u; if let g = c.group, pics[g] == nil { pics[g] = u } } }
        pictures = pics
    }

    // MARK: helpers

    private func shift(_ n: Int) { withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month) ?? month } }
    private func key(_ d: Date) -> String { let c = cal.dateComponents([.year, .month, .day], from: d); return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) }
    private func date(_ k: String) -> Date? { let p = k.split(separator: "-").compactMap { Int($0) }; guard p.count == 3 else { return nil }; return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) }
    private func isMerchDay(_ d: Date) -> Bool { let c = cal.dateComponents([.month, .day], from: d); return c.day == 1 && (c.month == 3 || c.month == 9) }
    private func title(_ k: String) -> String { date(k)?.formatted(.dateTime.weekday(.wide).month().day()) ?? k }
    private func accessibility(_ d: Date, _ k: String) -> String {
        var parts = [d.formatted(.dateTime.weekday(.wide).month().day())]
        let n = content[k]?.count ?? 0
        if n > 0 { parts.append("\(n) post\(n == 1 ? "" : "s") going out") }
        if isMerchDay(d) { parts.append("merch season changes") }
        if let n = drops[k]?.count, n > 0 { parts.append("\(n) drop\(n == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}
