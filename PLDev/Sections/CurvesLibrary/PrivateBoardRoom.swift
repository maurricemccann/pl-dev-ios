import SwiftUI

/// His private board, ported exactly from pl-curves-gallery `app/manifestation-preview/page.tsx`: four tabs (Home, Pipeline, Signals,
/// More), the same stat tiles, the upward line charts, the panels, the same numbers and words. Every figure is written into the page on
/// purpose and copied here unchanged; nothing is read from a live source. It keeps the page's own cream ground in both appearances.
/// Sizes: the page uses rem; rem x 16 = pt, raised to the 11 pt floor where the page goes smaller.
struct PrivateBoardRoom: View {
    @State private var tab: BoardTab = .home

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BoardHeader()
                Rectangle().fill(LinearGradient(colors: [BD.gold.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1).padding(.bottom, 4)
                Group {
                    switch tab {
                    case .home: BoardHome()
                    case .pipeline: BoardPipeline()
                    case .signals: BoardSignals()
                    case .more: BoardMore()
                    }
                }
                .id(tab)
                .transition(.opacity)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(BD.ground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { BoardTabBar(tab: $tab) }
        .navigationTitle("Private board").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .animation(.easeOut(duration: 0.25), value: tab)
    }
}

// MARK: - the page's figures (fabricated on purpose, copied from the page)

private enum BD {
    static let ground = Color(hex: 0xfaf7f0), ink = Color(hex: 0x1a1510), dim = Color(hex: 0x6b5d48), gold = Color(hex: 0xc9a84c)
    static let goldDeep = Color(hex: 0xa9852f), goldInk = Color(hex: 0x8a7235), green = Color(hex: 0x2d8a6e), violet = Color(hex: 0x9b72cf), sage = Color(hex: 0x8a8270)
    static let hair = Color(red: 160 / 255, green: 140 / 255, blue: 110 / 255)
    static func rem(_ r: CGFloat) -> CGFloat { max(11, r * 16) }
    static func serif(_ r: CGFloat) -> Font { .system(size: rem(r), design: .serif) }
    static func mono(_ r: CGFloat) -> Font { .system(size: rem(r), design: .monospaced) }
    static func sans(_ r: CGFloat) -> Font { .system(size: rem(r)) }

    static let revenueLifetime = 127480, revenueMonth = 38920, revenueWeek = 14207, orders = 843, ordersMonth = 191, avgOrder = 151
    static let igFollowers = 41207, subscribers = 12940, members = 618, archive = 342, fulfillmentDays = 2
    static let returnRate = "1.4"
    static let revSeries: [Double] = [4100, 5200, 6800, 9400, 12100, 15800, 19600, 24300, 30100, 38920]
    static let followerSeries: [Double] = [2100, 4800, 8900, 13400, 18700, 24100, 29800, 34200, 38100, 41207]
    static let subSeries: [Double] = [420, 980, 2100, 3800, 5600, 7400, 9100, 10800, 11900, 12940]

    struct Tile: Identifiable { let label: String; let value: Int?; let text: String?; let prefix: String; let sub: String; let delta: String?; var id: String { label } }
    static let tiles: [Tile] = [
        Tile(label: "Storefront", value: nil, text: "LIVE", prefix: "", sub: "psychedluxuries.com", delta: nil),
        Tile(label: "Revenue", value: revenueLifetime, text: nil, prefix: "$", sub: "lifetime · USD", delta: "+14,207 7d"),
        Tile(label: "Orders", value: orders, text: nil, prefix: "", sub: "\(ordersMonth) this month", delta: "+37 7d"),
        Tile(label: "Avg Order", value: avgOrder, text: nil, prefix: "$", sub: "USD per order", delta: "+9 30d"),
        Tile(label: "Subscribers", value: subscribers, text: nil, prefix: "", sub: "signal list", delta: "+1,040 7d"),
        Tile(label: "Members", value: members, text: nil, prefix: "", sub: "the congregation", delta: "+58 7d"),
        Tile(label: "IG Followers", value: igFollowers, text: nil, prefix: "", sub: "@psychedluxuries", delta: "+3,107 7d"),
        Tile(label: "Archive", value: archive, text: nil, prefix: "", sub: "pieces catalogued", delta: "+12 30d"),
    ]
    static let quarters: [(label: String, score: Int, note: String)] = [
        ("Revenue", 24, "Six figures crossed. Momentum compounding."), ("Reach", 23, "41k on IG, growing ~3k/week."),
        ("Belonging", 24, "618 members, retention holding."), ("Craft", 23, "342 pieces catalogued, pipeline full."),
    ]
    typealias Row = (title: String, meta: String)
    static let pipelineRows: [Row] = [("The Golden Mend — kintsugi capsule", "Fulfillment · 84 orders"), ("Crimson Thread hoodie", "Restock · sold out twice"),
                                      ("Tunnel longsleeve", "Production · ships Friday"), ("Luminous Fold tee — drop 4", "Approved · queued")]
    static let contentRows: [Row] = [("Transmission №215 — \"The law of all becoming\"", "Scheduled · Sun 8PM PT"), ("Reel — Chain piece, breathing glyph", "Published · 18.4k views"),
                                     ("Carousel — Three Truths", "Published · 2,910 likes")]
    static let agentRows: [Row] = [("Council: weekly resonance sweep", "all pass · 06:58 UTC"), ("Buffer: 6 posts queued", "ok · 07:02 UTC"),
                                   ("Fourthwall sync: 191 orders reconciled", "ok · 07:04 UTC")]
    static let signalRows: [Row] = [("Record week — $14,207", "new high · 2 days ago"), ("40,000 followers crossed", "milestone · 5 days ago"), ("$100,000 lifetime revenue", "milestone · April 2026")]
    static let doors: [(label: String, sub: String)] = [("The Site", "psychedluxuries.com"), ("Codex", "sovereign language"), ("Academy", "persona curriculum"), ("Fourthwall", "843 orders · $127k"),
                                                        ("Gallery", "catalogue raisonné"), ("Notion HQ", "operations hub"), ("Lexicon", "resonance dashboard"), ("Site Audit", "all checks green")]

    static let grouped: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US"); return f }()
    static func n(_ v: Int) -> String { grouped.string(from: NSNumber(value: v)) ?? "\(v)" }
}

private enum BoardTab: String, CaseIterable {
    case home = "Home", pipeline = "Pipeline", signals = "Signals", more = "More"
    var symbol: String { switch self { case .home: return "circle.hexagongrid"; case .pipeline: return "list.bullet.indent"; case .signals: return "dot.radiowaves.up.forward"; case .more: return "ellipsis" } }
}

// MARK: - pieces

/// The page's glass card: cream glass, a hairline, no shadow.
private struct BoardCard: ViewModifier {
    var padding: CGFloat = 16, radius: CGFloat = 18, top: Color? = nil
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xfdf9f1).opacity(0.78), in: shape)
            .overlay { shape.strokeBorder(BD.hair.opacity(0.35), lineWidth: 0.8) }
            .overlay(alignment: .top) { if let top { Rectangle().fill(top).frame(height: 2).mask(shape) } }
    }
}
private extension View { func boardCard(padding: CGFloat = 16, radius: CGFloat = 18, top: Color? = nil) -> some View { modifier(BoardCard(padding: padding, radius: radius, top: top)) } }

/// Counts up to its target, the page's `useCountUp` (1.1 s, ease-out cubic).
private struct CountText: View, Animatable {
    var value: Double
    var prefix = ""
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View { Text(prefix + BD.n(Int(value.rounded()))) }
}
private struct CountValue: View {
    let target: Int
    var prefix = ""
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        CountText(value: shown, prefix: prefix)
            .onAppear { if reduce { shown = Double(target) } else { withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 1.1)) { shown = Double(target) } } }
    }
}

/// The page's TrendChart: a polyline of the series in a 280 x 72 box, three faint grid lines.
private struct TrendChart: View {
    let series: [Double]; let accent: Color; var prefix = ""
    var body: some View {
        let last = series.last ?? 0, first = series.first ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prefix + BD.n(Int(last))).font(BD.serif(1.4)).foregroundStyle(BD.ink)
                Text("+\(BD.n(Int(last - first))) trend ▲").font(BD.mono(0.65)).foregroundStyle(BD.green)
            }
            Canvas { ctx, size in
                let W: CGFloat = 280, H: CGFloat = 72, pad: CGFloat = 4
                let lo = series.min() ?? 0, span = max((series.max() ?? 0) - lo, 1)
                let sx = size.width / W, sy = size.height / H
                for g in [0.0, 0.5, 1.0] {
                    var line = Path(); let y = (pad + CGFloat(g) * (H - pad * 2)) * sy
                    line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(accent.opacity(0.12)), lineWidth: 1)
                }
                var p = Path()
                for (i, v) in series.enumerated() {
                    let pt = CGPoint(x: (pad + CGFloat(i) / CGFloat(series.count - 1) * (W - pad * 2)) * sx, y: (H - pad - CGFloat((v - lo) / span) * (H - pad * 2)) * sy)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 72)
            .accessibilityLabel("Trend from \(prefix)\(BD.n(Int(first))) to \(prefix)\(BD.n(Int(last)))")
        }
    }
}

private struct HubMark: View {
    var size: CGFloat = 32
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 24, c = CGPoint(x: 12 * k, y: 12 * k), gold = BD.gold
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.2 * k, y: c.y - 2.2 * k, width: 4.4 * k, height: 4.4 * k)), with: .color(gold))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7.5 * k, y: c.y - 7.5 * k, width: 15 * k, height: 15 * k)), with: .color(gold.opacity(0.5)), lineWidth: 1.4 * k)
            for d in stride(from: 0.0, to: 360, by: 60) {
                let a = CGFloat(d * .pi / 180); var l = Path()
                l.move(to: CGPoint(x: c.x + cos(a) * 3 * k, y: c.y + sin(a) * 3 * k)); l.addLine(to: CGPoint(x: c.x + cos(a) * 7.5 * k, y: c.y + sin(a) * 7.5 * k))
                ctx.stroke(l, with: .color(gold.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round))
            }
        }
        .frame(width: size, height: size).opacity(0.8).accessibilityHidden(true)
    }
}

private struct BoardHeader: View {
    var body: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 12) {
                HubMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Psyched Luxuries").plHand(32).foregroundStyle(BD.gold).lineLimit(1).minimumScaleFactor(0.6)
                    Text("The Mastermind Board").font(BD.mono(0.5)).textCase(.uppercase).tracking(1.4).foregroundStyle(BD.goldInk)
                }
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text(t.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_US")))).font(BD.serif(1.6).italic()).foregroundStyle(BD.gold)
            }
        }
        .boardCard(padding: 16)
    }
}

private struct BoardPanel: View {
    let title: String; var badge: String? = nil; var accent: Color = BD.sage; let rows: [BD.Row]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).plHand(16).foregroundStyle(accent)
                Spacer()
                if let badge { Text(badge).font(BD.mono(0.7)).foregroundStyle(BD.gold) }
            }
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(BD.sans(0.86)).foregroundStyle(BD.ink)
                        Text(r.meta).font(BD.mono(0.68)).foregroundStyle(BD.dim)
                    }
                    .boardCard(padding: 12, radius: 12)
                }
            }
        }
        .boardCard(padding: 16)
    }
}

private struct BoardSection: View {
    let title: String
    var body: some View {
        HStack(spacing: 11) {
            Text(title).plHand(18).foregroundStyle(BD.dim.opacity(0.85))
            Rectangle().fill(LinearGradient(colors: [BD.gold.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
        }
    }
}

private struct ChartCard: View {
    let label: String; let series: [Double]; let accent: Color; var prefix = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(BD.mono(0.7)).textCase(.uppercase).tracking(2.2).foregroundStyle(BD.dim)
            TrendChart(series: series, accent: accent, prefix: prefix)
        }
        .boardCard(padding: 16)
    }
}

// MARK: - tabs

private struct BoardHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                CountValue(target: BD.revenueLifetime, prefix: "$").font(BD.serif(2.6)).foregroundStyle(BD.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Six figures crossed").plHand(18).foregroundStyle(BD.dim)
                    Text("Lifetime revenue passed $100,000 · record week +$\(BD.n(BD.revenueWeek))").font(BD.sans(0.82)).foregroundStyle(BD.ink)
                }
            }
            .boardCard(padding: 16)

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("94").font(BD.serif(3.4)).foregroundStyle(BD.green)
                        Text("/100").font(BD.mono(0.8)).foregroundStyle(BD.dim)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Standing").plHand(18).foregroundStyle(BD.dim)
                        Text("Ascending. Every quarter strong.").font(BD.sans(0.8)).foregroundStyle(BD.ink)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                Divider().overlay(BD.hair.opacity(0.2))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0, alignment: .top), GridItem(.flexible(), spacing: 0, alignment: .top)], spacing: 0) {
                    ForEach(BD.quarters, id: \.label) { q in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(q.label).font(BD.mono(0.62)).textCase(.uppercase).tracking(1.6).foregroundStyle(BD.dim.opacity(0.7))
                                Spacer()
                                (Text("\(q.score)").foregroundStyle(BD.green) + Text("/25").foregroundStyle(BD.green.opacity(0.4))).font(BD.mono(0.72))
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(BD.hair.opacity(0.18))
                                    Capsule().fill(BD.green).frame(width: g.size.width * CGFloat(q.score) / 25)
                                }
                            }.frame(height: 4)
                            Text(q.note).font(BD.sans(0.66)).foregroundStyle(BD.dim)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(BD.hair.opacity(0.12)).frame(height: 1) }
                    }
                }
            }
            .boardCard(padding: 0)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BD.tiles) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(t.label).font(BD.mono(0.6)).textCase(.uppercase).tracking(2.2).foregroundStyle(BD.dim).lineLimit(1)
                            Spacer()
                            PulseDot()
                        }
                        if let text = t.text {
                            Text(text).font(BD.serif(1.3)).tracking(1.6).foregroundStyle(BD.gold)
                        } else if let v = t.value {
                            CountValue(target: v, prefix: t.prefix).font(BD.serif(1.5)).foregroundStyle(BD.ink)
                        }
                        HStack {
                            Text(t.sub).font(BD.mono(0.6)).foregroundStyle(BD.dim).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 4)
                            if let d = t.delta { Text(d).font(BD.mono(0.6)).foregroundStyle(BD.green).lineLimit(1).fixedSize() }
                        }
                    }
                    .boardCard(padding: 12, radius: 18, top: t.text != nil ? BD.gold : BD.gold.opacity(0.18))
                }
            }

            BoardPanel(title: "Recent Signals", badge: "live", accent: BD.gold, rows: BD.signalRows)
        }
    }
}

private struct PulseDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Circle().fill(BD.gold).frame(width: 6, height: 6).opacity(on ? 1 : 0.4)
            .onAppear { if reduce { on = true } else { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { on = true } } }
            .accessibilityHidden(true)
    }
}

private struct BoardPipeline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BoardSection(title: "The Work")
            BoardPanel(title: "Drop Pipeline", badge: "4 active", rows: BD.pipelineRows)
            BoardPanel(title: "Content Calendar", badge: "this week", accent: BD.violet, rows: BD.contentRows)
            BoardSection(title: "Fulfillment")
            let cells: [(k: String, v: String, s: String)] = [("Ships in", "\(BD.fulfillmentDays) days", "avg turnaround"), ("Return rate", "\(BD.returnRate)%", "well under target"),
                                                            ("This month", "$\(BD.n(BD.revenueMonth))", "\(BD.ordersMonth) orders")]
            HStack(alignment: .top, spacing: 14) {
                ForEach(cells, id: \.k) { x in
                    VStack(spacing: 4) {
                        Text(x.k).font(BD.mono(0.6)).textCase(.uppercase).tracking(1.9).foregroundStyle(BD.dim.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(x.v).font(BD.serif(1.6)).foregroundStyle(BD.green).lineLimit(1).minimumScaleFactor(0.6)
                        Text(x.s).font(BD.sans(0.68)).foregroundStyle(BD.dim).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
            }
            .boardCard(padding: 18)
        }
    }
}

private struct BoardSignals: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BoardSection(title: "Reach")
            ChartCard(label: "Revenue · monthly", series: BD.revSeries, accent: BD.gold, prefix: "$")
            ChartCard(label: "Instagram followers", series: BD.followerSeries, accent: BD.violet)
            ChartCard(label: "Subscribers", series: BD.subSeries, accent: BD.green)
            BoardPanel(title: "Agent Log", badge: "24h", accent: BD.green, rows: BD.agentRows)
        }
    }
}

private struct BoardMore: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BoardSection(title: "Doors")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(BD.doors.enumerated()), id: \.offset) { i, d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%02d", i + 1)).font(BD.mono(0.68)).foregroundStyle(BD.gold.opacity(0.55))
                        Text(d.label).font(BD.sans(0.85)).foregroundStyle(BD.ink)
                        Text(d.sub).font(BD.mono(0.65)).foregroundStyle(BD.dim).lineLimit(2)
                    }
                    .boardCard(padding: 12, radius: 18)
                }
            }
            HStack {
                Text("manifestation preview · not live data").font(BD.sans(0.62)).textCase(.uppercase).tracking(2).foregroundStyle(BD.dim.opacity(0.5)).lineLimit(2)
                Spacer(minLength: 8)
                Text("Watch this.").plHand(18).foregroundStyle(BD.goldInk)
            }
            .boardCard(padding: 14, radius: 18)
        }
    }
}

private struct BoardTabBar: View {
    @Binding var tab: BoardTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(BoardTab.allCases, id: \.self) { t in
                let active = tab == t
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol).font(.system(size: 20)).frame(height: 22)
                        Text(t.rawValue).font(BD.mono(0.62)).textCase(.uppercase).tracking(1.2)
                    }
                    .foregroundStyle(active ? BD.goldDeep : BD.dim.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .overlay(alignment: .top) { if active { Capsule().fill(BD.gold).frame(width: 26, height: 2).shadow(color: BD.gold.opacity(0.6), radius: 4) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0xfcf8f0).opacity(0.94).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(BD.gold.opacity(0.22)).frame(height: 1) }
    }
}
