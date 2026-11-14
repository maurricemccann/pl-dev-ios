import SwiftUI

/// The manifestation preview, native (the gallery's `/manifestation-preview`): his private, aspirational Mastermind Board, a lookalike of the
/// real pl-os console standing as a six-figure house. **Every number here is made up on purpose**, by his design ("what persists in the mind
/// becomes your reality"): nothing on this screen reads a server, and it must never be wired to one. If real numbers are ever wanted, that is
/// the House app. So it says what it is, twice: a pill under the header and a footer ("manifestation preview, not live data"), and the one
/// "live" badge the web wears on Recent Signals reads "vision" here. House look: the PLOS skin (pl-os's own chrome), its header and glass.
enum VisionFigures {
    static let revenueLifetime = 127480, revenueMonth = 38920, revenueWeek = 14207
    static let orders = 843, ordersMonth = 191, avgOrder = 151
    static let igFollowers = 41207, subscribers = 12940, members = 618, archive = 342
    static let fulfillmentDays = 2, returnRate = "1.4"

    static let revSeries: [Double] = [4100, 5200, 6800, 9400, 12100, 15800, 19600, 24300, 30100, 38920]
    static let followerSeries: [Double] = [2100, 4800, 8900, 13400, 18700, 24100, 29800, 34200, 38100, 41207]
    static let subSeries: [Double] = [420, 980, 2100, 3800, 5600, 7400, 9100, 10800, 11900, 12940]

    struct Tile { let label: String; let value: Int?; let text: String?; let sub: String; let delta: String?; let money: Bool }
    static let tiles: [Tile] = [
        Tile(label: "Storefront", value: nil, text: "LIVE", sub: "psychedluxuries.com", delta: nil, money: false),
        Tile(label: "Revenue", value: revenueLifetime, text: nil, sub: "lifetime \u{00B7} USD", delta: "+14,207 7d", money: true),
        Tile(label: "Orders", value: orders, text: nil, sub: "\(ordersMonth) this month", delta: "+37 7d", money: false),
        Tile(label: "Avg Order", value: avgOrder, text: nil, sub: "USD per order", delta: "+9 30d", money: true),
        Tile(label: "Subscribers", value: subscribers, text: nil, sub: "signal list", delta: "+1,040 7d", money: false),
        Tile(label: "Members", value: members, text: nil, sub: "the congregation", delta: "+58 7d", money: false),
        Tile(label: "IG Followers", value: igFollowers, text: nil, sub: "@psychedluxuries", delta: "+3,107 7d", money: false),
        Tile(label: "Archive", value: archive, text: nil, sub: "pieces catalogued", delta: "+12 30d", money: false),
    ]
    static let quarters: [(String, Int, String)] = [
        ("Revenue", 24, "Six figures crossed. Momentum compounding."), ("Reach", 23, "41k on IG, growing ~3k/week."),
        ("Belonging", 24, "618 members, retention holding."), ("Craft", 23, "342 pieces catalogued, pipeline full."),
    ]
    static let pipeline = [("The Golden Mend \u{2014} kintsugi capsule", "Fulfillment \u{00B7} 84 orders"), ("Crimson Thread hoodie", "Restock \u{00B7} sold out twice"),
                           ("Tunnel longsleeve", "Production \u{00B7} ships Friday"), ("Luminous Fold tee \u{2014} drop 4", "Approved \u{00B7} queued")]
    static let content = [("Transmission \u{2116}215 \u{2014} \u{201C}The law of all becoming\u{201D}", "Scheduled \u{00B7} Sun 8PM PT"), ("Reel \u{2014} Chain piece, breathing glyph", "Published \u{00B7} 18.4k views"),
                          ("Carousel \u{2014} Three Truths", "Published \u{00B7} 2,910 likes")]
    static let agents = [("Council: weekly resonance sweep", "all pass \u{00B7} 06:58 UTC"), ("Buffer: 6 posts queued", "ok \u{00B7} 07:02 UTC"),
                         ("Fourthwall sync: 191 orders reconciled", "ok \u{00B7} 07:04 UTC")]
    static let signals = [("Record week \u{2014} $14,207", "new high \u{00B7} 2 days ago"), ("40,000 followers crossed", "milestone \u{00B7} 5 days ago"),
                          ("$100,000 lifetime revenue", "milestone \u{00B7} April 2026")]
    static let doors = [("The Site", "psychedluxuries.com"), ("Codex", "sovereign language"), ("Academy", "persona curriculum"), ("Fourthwall", "843 orders \u{00B7} $127k"),
                        ("Gallery", "catalogue raisonn\u{00E9}"), ("Notion HQ", "operations hub"), ("Lexicon", "resonance dashboard"), ("Site Audit", "all checks green")]
}

struct VisionPreviewView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, pipeline, signals, more
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String { switch self { case .home: return "circle.hexagongrid"; case .pipeline: return "list.bullet.indent"; case .signals: return "dot.radiowaves.up.forward"; case .more: return "ellipsis" } }
    }

    @State private var tab: Tab = .home
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                OSHeader()
                VStack(spacing: 6) {
                    Text("The Mastermind Board").osEyebrow(9).foregroundStyle(PLOS.goldDim(scheme))
                    Label("A vision \u{00B7} not live data", systemImage: "eye").osEyebrow(10).foregroundStyle(PLOS.gold)
                        .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.clear, in: Capsule())
                        .overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) }
                }
                Group {
                    switch tab {
                    case .home: VisionHome()
                    case .pipeline: VisionPipeline()
                    case .signals: VisionSignals()
                    case .more: VisionMore()
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .frame(maxWidth: 640).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24).frame(maxWidth: .infinity)
        }
        .background { OSGround() }
        .tint(PLOS.gold)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(PLHaptic.select, trigger: tab)
        .accessibilityElement(children: .contain)
    }

    private var tabBar: some View {
        GlassEffectContainer {
            HStack(spacing: 6) {
                ForEach(Tab.allCases) { t in
                    let on = tab == t
                    Button { withAnimation(.snappy) { tab = t } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.symbol).font(.system(size: 17, weight: .medium))
                            Text(t.title).osEyebrow(8)
                        }
                        .foregroundStyle(on ? Color.black : PLOS.dim(scheme))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background { if on { Capsule().fill(PLOS.gold) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(6).glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }
}

// MARK: - Home

private struct VisionHome: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            // milestone banner
            HStack(spacing: 14) {
                CountText(target: VisionFigures.revenueLifetime, prefix: "$").font(.system(size: 40, design: .serif)).foregroundStyle(PLOS.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Six figures crossed").plHand(20, relativeTo: .headline).foregroundStyle(PLOS.dim(scheme))
                    Text("Lifetime revenue passed $100,000 \u{00B7} record week +$\(VisionFigures.revenueWeek.formatted())").font(.footnote).foregroundStyle(PLOS.text(scheme))
                }
            }
            .osCard(padding: 16)

            // standing hero
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("94").font(.system(size: 54, design: .serif)).foregroundStyle(PLOS.ok)
                        Text("/100").osValue(13).foregroundStyle(PLOS.dim(scheme))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Standing").plHand(20, relativeTo: .headline).foregroundStyle(PLOS.dim(scheme))
                        Text("Ascending. Every quarter strong.").font(.footnote).foregroundStyle(PLOS.text(scheme))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)
                Divider().overlay(PLOS.line(scheme))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(VisionFigures.quarters.indices, id: \.self) { i in
                        let q = VisionFigures.quarters[i]
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(q.0).osEyebrow(9).foregroundStyle(PLOS.dim(scheme))
                                Spacer()
                                HStack(spacing: 0) { Text("\(q.1)").foregroundStyle(PLOS.ok); Text("/25").foregroundStyle(PLOS.dim(scheme).opacity(0.5)) }.osValue(12)
                            }
                            GeometryReader { g in
                                Capsule().fill(PLOS.line(scheme)).overlay(alignment: .leading) { Capsule().fill(PLOS.ok).frame(width: g.size.width * CGFloat(q.1) / 25) }
                            }.frame(height: 4)
                            Text(q.2).font(.caption2).foregroundStyle(PLOS.dim(scheme)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 12)
            }
            .osCard(padding: 16)

            // stat tiles
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(VisionFigures.tiles.indices, id: \.self) { i in VisionTile(tile: VisionFigures.tiles[i]) }
            }

            VisionPanel(title: "Recent Signals", badge: "vision", rows: VisionFigures.signals, accent: PLOS.gold)
        }
    }
}

private struct VisionTile: View {
    let tile: VisionFigures.Tile
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tile.label).osEyebrow(9).foregroundStyle(PLOS.dim(scheme)).lineLimit(1)
                Spacer()
                Circle().fill(PLOS.gold).frame(width: 6, height: 6)
            }
            if let t = tile.text { Text(t).font(.system(size: 21, design: .serif)).tracking(2).foregroundStyle(PLOS.gold) }
            else if let v = tile.value { CountText(target: v, prefix: tile.money ? "$" : "").font(.system(size: 24, design: .serif)).foregroundStyle(PLOS.text(scheme)) }
            HStack {
                Text(tile.sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if let d = tile.delta { Text(d).font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.ok).lineLimit(1) }
            }
        }
        .osCard(padding: 12)
        .overlay(alignment: .top) { Rectangle().fill(tile.text != nil ? PLOS.gold : PLOS.gold.opacity(0.18)).frame(height: 2).clipShape(UnevenRoundedRectangle(topLeadingRadius: PLOS.radius, topTrailingRadius: PLOS.radius)) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pipeline, Signals, More

private struct VisionPipeline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VisionSection("The Work")
            VisionPanel(title: "Drop Pipeline", badge: "4 active", rows: VisionFigures.pipeline)
            VisionPanel(title: "Content Calendar", badge: "this week", rows: VisionFigures.content, accent: PLOS.philosophy)
            VisionSection("Fulfillment")
            HStack(alignment: .top, spacing: 8) {
                ForEach([("Ships in", "\(VisionFigures.fulfillmentDays) days", "avg turnaround"), ("Return rate", "\(VisionFigures.returnRate)%", "well under target"),
                         ("This month", "$\(VisionFigures.revenueMonth.formatted())", "\(VisionFigures.ordersMonth) orders")], id: \.0) { x in
                    VStack(spacing: 4) {
                        Text(x.0).osEyebrow(8).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(x.1).font(.system(size: 22, design: .serif)).foregroundStyle(PLOS.ok).lineLimit(1).minimumScaleFactor(0.6)
                        Text(x.2).font(.caption2).foregroundStyle(PLOS.dim(scheme)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .osCard(padding: 16)
        }
    }
}

private struct VisionSignals: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VisionSection("Reach")
            VisionChart(title: "Revenue \u{00B7} monthly", series: VisionFigures.revSeries, accent: PLOS.gold, prefix: "$")
            VisionChart(title: "Instagram followers", series: VisionFigures.followerSeries, accent: PLOS.philosophy)
            VisionChart(title: "Subscribers", series: VisionFigures.subSeries, accent: PLOS.ok)
            VisionPanel(title: "Agent Log", badge: "24h", rows: VisionFigures.agents, accent: PLOS.ok)
        }
    }
}

private struct VisionMore: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VisionSection("Doors")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(VisionFigures.doors.indices, id: \.self) { i in
                    let d = VisionFigures.doors[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.gold.opacity(0.55))
                        Text(d.0).font(.subheadline).foregroundStyle(PLOS.text(scheme))
                        Text(d.1).font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .osCard(padding: 12)
                    .accessibilityElement(children: .combine)
                }
            }
            HStack {
                Text("manifestation preview \u{00B7} not live data").osEyebrow(8).foregroundStyle(PLOS.dim(scheme).opacity(0.7))
                Spacer()
                Text("Watch this.").plHand(20, relativeTo: .headline).foregroundStyle(PLOS.goldDim(scheme))
            }
            .osCard(padding: 14)
        }
    }
}

// MARK: - Pieces

private struct VisionSection: View {
    let title: String
    init(_ t: String) { title = t }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 10) {
            Text(title).plHand(20, relativeTo: .headline).foregroundStyle(PLOS.dim(scheme))
            LinearGradient(colors: [PLOS.gold.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct VisionPanel: View {
    let title: String
    var badge: String? = nil
    let rows: [(String, String)]
    var accent: Color? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).plHand(19, relativeTo: .headline).foregroundStyle(accent ?? PLOS.muted)
                Spacer()
                if let badge { Text(badge).osValue(13).foregroundStyle(PLOS.gold) }
            }
            VStack(spacing: 6) { ForEach(rows.indices, id: \.self) { OSRow(title: rows[$0].0, meta: rows[$0].1) } }
        }
        .osCard(padding: 16)
    }
}

/// The web's `TrendChart`: the made-up series as a gold-hairline grid and one polyline, the last value and its trend above it.
private struct VisionChart: View {
    let title: String
    let series: [Double]
    let accent: Color
    var prefix = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let first = series.first ?? 0, last = series.last ?? 0
        VStack(alignment: .leading, spacing: 10) {
            Text(title).osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(prefix)\(Int(last).formatted())").font(.system(size: 24, design: .serif)).foregroundStyle(PLOS.text(scheme))
                Text("+\(Int(last - first).formatted()) trend \u{25B2}").font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.ok)
            }
            Canvas { ctx, size in
                let pad = 4.0, mn = series.min() ?? 0, span = max(1, (series.max() ?? 1) - mn)
                for g in [0.0, 0.5, 1.0] {
                    var l = Path(); let y = pad + g * (size.height - pad * 2)
                    l.move(to: CGPoint(x: 0, y: y)); l.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(l, with: .color(accent.opacity(0.12)), lineWidth: 1)
                }
                var p = Path()
                for (i, v) in series.enumerated() {
                    let pt = CGPoint(x: pad + CGFloat(i) / CGFloat(max(1, series.count - 1)) * (size.width - pad * 2), y: size.height - pad - CGFloat((v - mn) / span) * (size.height - pad * 2))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 72)
            .accessibilityHidden(true)
        }
        .osCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(prefix)\(Int(last).formatted()), up \(Int(last - first).formatted())")
    }
}

/// The web's count-up (1.1 s, ease-out cubic). Reduce Motion shows the number at once.
private struct CountText: View {
    let target: Int
    var prefix = ""
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var start = Date()
    var body: some View {
        if reduce { Text("\(prefix)\(target.formatted())").monospacedDigit() }
        else {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: Date().timeIntervalSince(start) > 1.3)) { tl in
                let p = min(1, tl.date.timeIntervalSince(start) / 1.1), e = 1 - pow(1 - p, 3)
                Text("\(prefix)\(Int((Double(target) * e).rounded()).formatted())").monospacedDigit()
            }
        }
    }
}

/// The card on Practice's record screen that opens the preview. It says what it is before it opens.
struct VisionPreviewCard: View {
    @Bindable var state: PracticeModel
    var body: some View {
        PCard(title: "Vision preview", hint: "The house, standing at six figures. Made up on purpose: nothing here is live.", id: "preview") {
            Button { state.preview = true } label: {
                Label("Open the Mastermind Board", systemImage: "eye").frame(maxWidth: .infinity)
            }
            .buttonStyle(CandleGhost())
        }
    }
}
