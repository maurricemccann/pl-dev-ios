import SwiftUI

/// `/system`, the apparatus behind the practice (`app/system/page.tsx`): the three Truths as its chapters, the receipts under
/// veils you tap to part, the architecture laid flat (`SystemFlowchart`), the fleet, the workflow, the receipts with the live
/// archive count, the dialogue by model, the record drawn from its own numbers (`TelemetryPiece`, pl-cron's public
/// `api/stats`), the timeline, the earned laws, the three bodies, under the hood, the inner veil and the standard.
struct SiteSystemView: View {
    private let count = SiteArchiveCount.shared
    @State private var stats: Stats?
    @Environment(\.colorScheme) private var scheme

    struct Stats: Decodable { let ok: Bool?; let archive_count: Int?; let corpus_fragments: Int?; let corpus_conversations: Int? }

    private var tele: (Int, Int, Int) {
        if let s = stats, s.ok == true, let a = s.archive_count, a > 0 { return (a, s.corpus_fragments ?? 0, s.corpus_conversations ?? 0) }
        return (1615, 466, 86)   // the last counted figures, as the site falls back to them
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                law
                truthI
                truthII
                truthIII
                doctrine
                InnerVeilView()
                close
            }
        }
        .siteScreen()
        .plScreenTitle("The System")
        .task { await count.load() }
        .task { stats = try? await SiteData.cron("api/stats", Stats.self) }
        .refreshable { stats = try? await SiteData.cron("api/stats", Stats.self) }
    }

    // MARK: sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("The System \u{2014} the apparatus behind the practice").siteLabel()
            SiteDisplay(parts: [("The mind made something every day for seven years.\n", false), ("Then it built a second one.", true)], size: 36)
            Text("Not a website. An operating system for a body of work \u{2014} the archive, the engine, the room, a fleet of instruments to carry it, and the laws they obey. One hand on all of it. The receipts are public.").siteBody(16)
            forgeDoor("The same system, taught end to end.")
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 56)
    }

    private func forgeDoor(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(line).font(SiteFont.body(14)).foregroundStyle(Bone.inkFaint(scheme))
            NavigationLink { SiteReaderView(path: "the-forge", title: "The Forge") } label: { Text("Enter the Forge").padding(.horizontal, 8) }.buttonStyle(SitePill(gold: true)).fixedSize()
        }
    }

    private var law: some View {
        VStack(spacing: 24) {
                Text("The Law").siteTag(11, Bone.gold)
                Text("The founder is the mind. The fleet is the instrument.").font(SiteFont.display(32, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                Text("An instrument can research a subject again. It cannot re-think the founder\u{2019}s thought. Every word, every mark, every decision passes through his judgment before it ships. The machine drafts. The founder decides.")
                    .font(SiteFont.body(14)).foregroundStyle(Color(hex: 0x9b937f)).lineSpacing(5).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24).padding(.vertical, 72).frame(maxWidth: .infinity)
        .background { ZStack { Color(hex: 0x0e0c08); GoldCurvesLayer(opacity: 0.18) } }
    }

    private func anchor(_ n: String, _ title: String, dark: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text(n).plHand(26).foregroundStyle(Bone.gold)
            Rectangle().fill(Bone.gold.opacity(0.15)).frame(height: 1)
            Text(title).siteTag(9, Bone.gold.opacity(0.6)).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.bottom, 32)
    }

    private var truthI: some View {
        VStack(alignment: .leading, spacing: 0) {
            anchor("I", "Prepared for Luxury")
            Text("The first run \u{2014} before any of this").siteLabel()
            Text("The practice underneath.").font(SiteFont.display(32)).foregroundStyle(Bone.ink(scheme)).padding(.top, 8)
            Text("The system is weeks old. The work it serves is seven years deep \u{2014} measured once, in the studio, by the artist\u{2019}s own hand:").siteBody(14).padding(.vertical, 20)
            grid(SystemData.practice.map { ($0.0, $0.1, $0.2) }, valueColor: Bone.gold)
            Text("The artist\u{2019}s reckoning, not the machine\u{2019}s \u{2014} the marks are real; the precise total is remembered, not re-counted.")
                .font(SiteFont.body(12)).italic().foregroundStyle(Bone.inkFaint(scheme)).padding(.top, 16)
            VStack(spacing: 10) {
                Text("What it took to build the second one").siteLabel()
                Text("Tap each figure to part the veil.").font(SiteFont.body(12)).italic().foregroundStyle(Bone.inkFaint(scheme))
            }
            .frame(maxWidth: .infinity).padding(.top, 64).padding(.bottom, 24)
            VStack(spacing: 1) {
                ForEach(SystemData.headline, id: \.1) { h in
                    VStack(spacing: 12) {
                        SystemVeil(value: h.0, label: h.1, size: 60)
                        Text(h.1).siteLabel()
                        Text(h.2).siteBody(14).multilineTextAlignment(.center)
                    }
                    .padding(36).frame(maxWidth: .infinity).background(Bone.ground(scheme))
                }
            }
            .background(Bone.line(scheme))
            Text("A month and change. Most of it after a full shift somewhere else.").font(SiteFont.body(12)).italic().foregroundStyle(Bone.inkFaint(scheme)).frame(maxWidth: .infinity).padding(.top, 16)
            forgeDoor("Built after full shifts elsewhere. You can build yours the same way.").padding(.top, 28)
        }
        .padding(.horizontal, 24).padding(.vertical, 64)
    }

    private func grid(_ rows: [(String, String, String)], valueColor: Color, ground: Color? = nil) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
            ForEach(rows, id: \.1) { r in
                VStack(alignment: .leading, spacing: 8) {
                    SystemVeil(value: r.0, label: r.1, size: 28, color: valueColor)
                    Text(r.1).siteLabel(9)
                    Text(r.2).font(SiteFont.body(12)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(3)
                }
                .padding(18).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).background(ground ?? Bone.ground(scheme))
            }
        }
        .background(Bone.line(scheme))
    }

    private var truthII: some View {
        SiteBand {
            anchor("II", "You Are in Control of Your Reality")
            Text("The architecture").siteTag(11, Bone.gold)
            Text("The machine itself.").font(SiteFont.display(32, italic: true)).foregroundStyle(Color(hex: 0xf1ece1))
            Text("Every system, every flow, every hand-off \u{2014} the real architecture, not a picture of one. What\u{2019}s here is what runs.").siteBody(14)
            Text("Laid flat").siteTag(11, Bone.gold).padding(.top, 16)
            Text("Every tier, in order.").font(SiteFont.display(26, italic: true)).foregroundStyle(Color(hex: 0xf1ece1))
            SystemFlow()
            Text("Nothing on this map is withheld. What\u{2019}s sealed on this site is never a system \u{2014} it\u{2019}s a credential, and it never appears here at all.")
                .font(SiteFont.body(12)).foregroundStyle(Color(hex: 0x9b937f)).lineSpacing(4)

            Text("The Fleet").siteTag(11, Bone.gold).padding(.top, 40)
            Text("A second mind, built to carry the first.").font(SiteFont.display(30)).foregroundStyle(Color(hex: 0xf1ece1))
            Text("Seventeen named instruments, each with one lane. They assemble, research, and build around the founder\u{2019}s work. They never overwrite it. When one files new thinking, it stays an instrument\u{2019}s until the founder reviews it and seals it as his own.").siteBody(14)
            VStack(spacing: 1) {
                ForEach(SystemData.fleet, id: \.0) { a in
                    HStack(alignment: .top, spacing: 16) {
                        Group {
                            if !a.3.isEmpty, let u = Site.page("fleet/\(a.3).svg") {
                                SiteFleetPlate(url: u)
                            } else {
                                Text(String(a.0.replacingOccurrences(of: "The ", with: "").prefix(1))).font(SiteFont.display(30)).foregroundStyle(Bone.gold.opacity(0.5))
                            }
                        }
                        .frame(width: 60, height: 80).overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(a.1).siteTag(9, Bone.gold)
                            Text(a.0).font(SiteFont.display(22)).foregroundStyle(Color(hex: 0xf1ece1))
                            Text(a.2).siteBody(13)
                        }
                    }
                    .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x0e0c08))
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color.white.opacity(0.1))
            forgeDoor("This fleet, this pipeline \u{2014} taught end to end, not just shown.").padding(.top, 12)

            Text("The Workflow").siteTag(11, Bone.gold).padding(.top, 40)
            Text("How a piece is made.").font(SiteFont.display(30)).foregroundStyle(Color(hex: 0xf1ece1))
            Text("Seven stages from a deficit in the body of work to a thing the founder is willing to put his name on. Every stage narrows. The last one is a person.").siteBody(14)
            VStack(spacing: 1) {
                ForEach(SystemData.pipeline, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.0).font(SiteFont.display(22)).foregroundStyle(Bone.gold)
                        Text(s.1).font(SiteFont.display(20)).foregroundStyle(Color(hex: 0xf1ece1))
                        Text(s.2).siteBody(13)
                    }
                    .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x0e0c08))
                }
            }
            .background(Color.white.opacity(0.1))
        }
    }

    private var truthIII: some View {
        let t = tele
        let searchable = t.0.formatted()
        let receipts = SystemData.receipts.map { r -> (String, String, String) in
            r.1 == "Archive pieces" ? (count.text, r.1, "the full archive, every piece and study, duplicates folded; \(searchable) live and searchable by meaning") : r
        }
        return VStack(alignment: .leading, spacing: 0) {
            anchor("III", "What Persists in the Mind Becomes Your Reality")
            Text("The build, in receipts").siteLabel().frame(maxWidth: .infinity).padding(.bottom, 24)
            grid(receipts, valueColor: Bone.ink(scheme), ground: Bone.raised(scheme))
            VStack(alignment: .leading, spacing: 12) {
                Text("The dialogue, by model").siteLabel()
                Text("The models the fleet ran on while building \u{2014} distinct from the production inference that runs the site.").font(SiteFont.body(12)).italic().foregroundStyle(Bone.inkFaint(scheme))
                ForEach(SystemData.models, id: \.0) { m in
                    HStack(spacing: 12) {
                        Text(m.0).font(SiteFont.display(14)).foregroundStyle(Bone.ink(scheme)).frame(width: 84, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Bone.line(scheme))
                                Capsule().fill(Bone.gold).frame(width: g.size.width * m.2 / 100)
                            }
                        }
                        .frame(height: 6)
                        Text("\(m.2.formatted(.number.precision(.fractionLength(1))))%").font(SiteFont.body(12)).foregroundStyle(Bone.inkSoft(scheme)).frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(m.0), \(m.2) percent, \(m.1)")
                }
            }
            .padding(.top, 40)
            Text("Receipts recounted Sep 7, 2026 against the same method as every prior count \u{2014} git history since May 13, source files only, vendored code excluded. Tokens-with-the-fleet is still the Jun 22, 2026 figure, not re-counted since. The seven-year practice above is the first run, counted separately." + (stats?.ok == true ? " The archive figure reads live from the record \u{2014} \(searchable) pieces indexed as this page was read." : ""))
                .font(SiteFont.body(11)).italic().foregroundStyle(Bone.inkFaint(scheme)).multilineTextAlignment(.center).padding(.top, 32)

            VStack(spacing: 14) {
                SiteRule().padding(.bottom, 24)
                Text("The record, drawn").siteLabel()
                Text("The numbers above, given a form. Not an illustration of the work \u{2014} a figure generated from the work\u{2019}s own count, redrawn every time the record changes.").siteBody(14).multilineTextAlignment(.center)
                TelemetryFigure(archive: t.0, fragments: t.1, conversations: t.2)
            }
            .padding(.top, 48)

            VStack(alignment: .leading, spacing: 0) {
                Text("In production since May 13").siteLabel()
                Text("From the first keystroke.").font(SiteFont.display(30)).foregroundStyle(Bone.ink(scheme)).padding(.top, 8).padding(.bottom, 32)
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(SystemData.timeline, id: \.1) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.0).siteTag(11, Bone.gold)
                            Text(e.1).font(SiteFont.display(22)).foregroundStyle(Bone.ink(scheme))
                            Text(e.2).siteBody(14)
                        }
                        .overlay(alignment: .topLeading) { Circle().fill(Bone.gold).frame(width: 10, height: 10).offset(x: -29, y: 4) }
                    }
                }
                .padding(.leading, 24)
                .overlay(alignment: .leading) { Rectangle().fill(Bone.line(scheme)).frame(width: 1) }
                forgeDoor("The 37 laws next are taught in full, not summarized.").padding(.top, 40)
            }
            .padding(.top, 72)
        }
        .padding(.horizontal, 24).padding(.vertical, 64)
    }

    private var doctrine: some View {
        SiteBand {
            VStack(spacing: 14) {
                Text("Earned constraints").siteTag(11, Bone.gold)
                Text("The system writes down its mistakes as law.").font(SiteFont.display(30, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                Text("Thirty-seven craft rules bind every draft. A few of them, in the founder\u{2019}s words:").siteBody(14).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.bottom, 16)
            ForEach(SystemData.laws, id: \.0) { l in
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.6)
                    Text(l.0).plHand(22).foregroundStyle(Color(hex: 0xf1ece1)).padding(.top, 18)
                    Text(l.1).siteBody(14)
                }
            }
            VStack(spacing: 14) {
                Text("Never blurred").siteTag(11, Bone.gold)
                Text("Three bodies of work.").font(SiteFont.display(30, italic: true)).foregroundStyle(Color(hex: 0xf1ece1))
            }
            .frame(maxWidth: .infinity).padding(.top, 48)
            VStack(spacing: 1) {
                ForEach(SystemData.bodies, id: \.0) { b in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(b.0).font(SiteFont.display(24)).foregroundStyle(Bone.gold)
                        Text(b.1).siteBody(14)
                    }
                    .padding(28).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x0e0c08))
                }
            }
            .background(Color.white.opacity(0.1))
            Text("Under the hood").siteTag(11, Bone.gold).frame(maxWidth: .infinity).padding(.top, 48)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                ForEach(SystemData.specs, id: \.1) { s in
                    VStack(spacing: 6) {
                        Text(s.0).font(SiteFont.display(32)).foregroundStyle(Color(hex: 0xf1ece1))
                        Text(s.1).siteLabel(9)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 22).background(Color(hex: 0x0e0c08))
                }
            }
            .background(Color.white.opacity(0.1))
            ShopFlowLayout(spacing: 10) {
                ForEach(SystemData.stack, id: \.self) { s in
                    Text(s).siteTag(10, Color(hex: 0xf1ece1).opacity(0.8)).padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8) }
                }
            }
            .padding(.top, 16)
            Text("Inference runs on the edge. The archive lives in object storage. The memory is a vector index of the founding record. None of it decides anything.")
                .siteBody(14).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 24)
        }
    }

    private var close: some View {
        VStack(spacing: 24) {
            Text("The Standard").siteTag(11, Bone.gold)
            Text("Crown\nor crucify.").font(SiteFont.display(52, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
            Text("The tools moved fast. The judgment did not. Everything you see was kept or killed by one hand \u{2014} the same hand that has made something every day for seven years, and still does.")
                .siteBody(14).multilineTextAlignment(.center)
            NavigationLink { SiteReaderView(path: "the-brand", title: "The brand") } label: { Text("The Brand") }.buttonStyle(SitePill())
            NavigationLink { ArchiveView(model: .shared) } label: { Text("The Archive") }.buttonStyle(SiteGhost())
            NavigationLink { SiteShopList() } label: { Text("Enter the Shop") }.buttonStyle(SiteGhost())
            NavigationLink { SiteReaderView(path: "the-forge", title: "The Forge") } label: { Text("The Forge") }.buttonStyle(SiteGhost())
            SiteWatch()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 96)
    }
}

// MARK: - The veil

/// `Veil`: the measure stays visible, the number is sealed under a folded gold corner; a tap peels it open, a second tap
/// re-seals it. The corner lifts a little on its own until the first tap (never under Reduce Motion). VoiceOver reads the value.
struct SystemVeil: View {
    let value: String
    let label: String
    var size: CGFloat = 40
    var color: Color = Bone.gold
    @State private var open = false
    @State private var hint = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { open.toggle() } } label: {
            Text(value).font(SiteFont.display(size)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, 6)
                .overlay {
                    if !open {
                        GeometryReader { g in
                            ZStack(alignment: .topTrailing) {
                                Rectangle().fill(Bone.ink(scheme).opacity(scheme == .dark ? 0.2 : 0.92))
                                Triangle().fill(LinearGradient(colors: [Color(hex: 0xe8d190), Bone.gold, Color(hex: 0x8a7235)], startPoint: .topTrailing, endPoint: .bottomLeading))
                                    .frame(width: hint ? 26 : 16, height: hint ? 26 : 16)
                                    .shadow(color: .black.opacity(0.3), radius: 3, x: -2, y: 2)
                            }
                            .frame(width: g.size.width, height: g.size.height)
                        }
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint(open ? "Seal it again" : "Part the veil")
        .sensoryFeedback(.selection, trigger: open)
        .task {
            guard !reduce else { return }
            while !Task.isCancelled && !open {
                try? await Task.sleep(for: .seconds(Double.random(in: 4...7)))
                withAnimation(.easeInOut(duration: 0.4)) { hint = true }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeInOut(duration: 0.4)) { hint = false }
            }
        }
    }

    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath(); return p }
    }
}

// MARK: - The architecture, laid flat

struct SystemFlow: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SystemData.tiers.enumerated()), id: \.offset) { ti, tier in
                VStack(alignment: .leading, spacing: 10) {
                    Text(tier.0).siteTag(10, Color(hex: 0xf1ece1).opacity(0.4))
                    ForEach(tier.1, id: \.0) { n in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(n.0).font(SiteFont.display(18)).foregroundStyle(Color(hex: n.2))
                            Text(n.1).font(SiteFont.body(12)).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.55)).lineSpacing(3)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: n.2).opacity(0.03))
                        .overlay { Rectangle().strokeBorder(Color(hex: n.2).opacity(0.25), lineWidth: 1) }
                    }
                }
                .padding(.vertical, 12)
                if ti < SystemData.tiers.count - 1 {
                    VStack(spacing: 2) {
                        Rectangle().fill(Bone.gold.opacity(0.2)).frame(width: 1, height: 18)
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8)).foregroundStyle(Bone.gold.opacity(0.35))
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

/// A fleet plate (`/fleet/<name>.svg`), his own vector marks, drawn natively from the site's file (the paths, filled in gold).
struct SiteFleetPlate: View {
    let url: URL
    @State private var path: Path?
    var body: some View {
        GeometryReader { geo in
            if let path {
                let b = path.boundingRect, s = min(geo.size.width / max(b.width, 1), geo.size.height / max(b.height, 1)) * 0.86
                path.applying(CGAffineTransform(translationX: -b.midX, y: -b.midY).concatenating(CGAffineTransform(scaleX: s, y: s))
                    .concatenating(CGAffineTransform(translationX: geo.size.width / 2, y: geo.size.height / 2)))
                    .fill(Bone.gold.opacity(0.8), style: FillStyle(eoFill: true))
            } else {
                Image(systemName: "person.crop.rectangle").foregroundStyle(Bone.gold.opacity(0.3)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return }
            let svg = String(decoding: d, as: UTF8.self)
            let ds = SiteData.matches(#"\sd="([^"]+)""#, in: svg).map { $0[0] }
            var all = Path(); for x in ds { all.addPath(SiteLogo.parse(x)) }
            // the plate's group carries one matrix(a,b,c,d,e,f); without it the mark stretches
            if let m = SiteData.matches(#"matrix\(([^)]+)\)"#, in: svg).first?.first {
                let v = m.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
                if v.count == 6 { all = all.applying(CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])) }
            }
            if !all.isEmpty { path = all }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The record, drawn

/// `TelemetryPiece`: one mark per archive piece (capped at 900, and the caption says so), on the golden angle, in a strand
/// per twelve recorded conversations, weighted by the corpus. Seeded from the numbers alone (mulberry32), so the same numbers
/// always draw the same figure.
struct TelemetryFigure: View {
    let archive: Int
    let fragments: Int
    let conversations: Int
    @Environment(\.colorScheme) private var scheme

    struct Mark { let x: Double; let y: Double; let r: Double; let o: Double }

    static func marks(_ total: Int, _ frag: Int, _ conv: Int) -> (pts: [Mark], shown: Int, strands: Int) {
        let shown = min(max(0, total), 900)
        let strands = max(1, conv / 12)
        let weight = max(0.35, min(2.2, Double(frag) / 300))
        var a = UInt32(truncatingIfNeeded: Int64(total) * 73856093 + Int64(frag) * 19349663 + Int64(conv) * 83492791)
        func rnd() -> Double {
            a = a &+ 0x6d2b79f5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
        let W = 1000.0, H = 560.0, maxR = min(W, H) * 0.44, golden = Double.pi * (3 - 5.0.squareRoot())
        var out: [Mark] = []
        for i in 0..<shown {
            let idx = Double(i) / Double(max(1, shown - 1))
            let rad = idx.squareRoot() * maxR
            let twist = Double(i % strands) / Double(strands) * (2 * .pi / Double(strands))
            let ang = Double(i) * golden + twist
            let jitter = (rnd() - 0.5) * 6
            let r = (0.7 + rnd() * 1.5) * weight
            out.append(Mark(x: W / 2 + cos(ang) * rad + jitter, y: H / 2 + sin(ang) * rad + jitter, r: r, o: 0.84 - idx * 0.62))
        }
        return (out, shown, strands)
    }

    var body: some View {
        let m = Self.marks(archive, fragments, conversations)
        VStack(alignment: .leading, spacing: 16) {
            Canvas { g, size in
                let s = size.width / 1000
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0e0c08)))
                let rr = 560 * 0.455 * s
                g.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - rr, y: size.height / 2 - rr, width: rr * 2, height: rr * 2)), with: .color(Bone.gold.opacity(0.14)), lineWidth: 1)
                for p in m.pts {
                    let r = p.r * s * 1.6
                    g.fill(Path(ellipseIn: CGRect(x: p.x * s - r, y: p.y * s - r, width: r * 2, height: r * 2)), with: .color(Bone.gold.opacity(p.o)))
                }
            }
            .aspectRatio(1000.0 / 560.0, contentMode: .fit)
            .accessibilityLabel("A generative mark for each of \(archive.formatted()) archive pieces, arranged on the golden angle in \(m.strands) strands.")
            Text("One mark for every piece in the archive \u{2014} \(archive.formatted()) of them\(archive > m.shown ? ", the densest \(m.shown) drawn" : ""). They fall on the golden angle, in \(m.strands) \(m.strands == 1 ? "strand" : "strands"), one per twelve recorded conversations; their weight is the corpus, \(fragments.formatted()) fragments. The same numbers always draw the same figure. When the record moves, so does this.")
                .font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(4)
        }
    }
}

// MARK: - The inner veil

/// `InnerVeil`: a stranger meets a sealed panel ("Belonging parts this veil."), which opens the congregation's sign-in; a
/// signed-in member finds themselves in the record: their mark, their marks (points), their standing.
struct InnerVeilView: View {
    private let account = SiteAccount.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private static let tiers = ["none": "Member", "initiate": "Initiate", "aligned": "Aligned", "kin": "Kin"]

    var body: some View {
        SitePaper {
            if let me = account.me, account.signedIn {
                Text("The inner tongue \u{2014} the record").siteLabel().frame(maxWidth: .infinity).padding(.bottom, 20)
                HStack(spacing: 1) {
                    cell(me.glyph.map { $0.replacingOccurrences(of: "-", with: " ").capitalized } ?? "\u{2014}", "your mark", big: false)
                    cell("\(me.points ?? 0)", "marks", big: true)
                    cell(Self.tiers[me.pointsTier ?? "none"] ?? "Member", "the climb", big: false)
                }
                .background(Bone.line(scheme))
                Text(me.firstName.map { "You are in the record now, \($0)." } ?? "You are in the record now.")
                    .font(SiteFont.display(26, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 32)
                Text("What persists in the mind becomes your reality. You came to read the record. You are in it.").siteBody(14).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            } else {
                Text("The inner tongue").siteLabel().frame(maxWidth: .infinity).padding(.bottom, 24)
                Button { if let u = URL(string: "pldev://section/congregation/me") { openURL(u) } } label: {
                    VStack(spacing: 24) {
                        Rectangle().fill(Bone.ink(.light)).frame(height: 96).overlay(alignment: .leading) { Rectangle().fill(Bone.gold).frame(width: 2) }
                        Text("Belonging parts this veil.").font(SiteFont.display(26, italic: true)).foregroundStyle(Bone.ink(scheme))
                        Text("Enter the congregation \u{2192}").siteTag(11, Bone.gold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign in. Belonging parts this veil.")
            }
        }
        .task { if !account.checked { await account.refresh() } }
    }

    private func cell(_ v: String, _ l: String, big: Bool) -> some View {
        VStack(spacing: 8) {
            Text(v).font(SiteFont.display(big ? 40 : 18)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center).minimumScaleFactor(0.6)
            Text(l).siteLabel(9)
        }
        .frame(maxWidth: .infinity, minHeight: 120).padding(10).background(Bone.raised(scheme))
    }
}

// MARK: - The page's own words and counts (each array is the page's, in its order)

enum SystemData {
    static let practice: [(String, String, String)] = [
        ("~500", "completed works", "across seven years \u{00B7} ~83 a year"), ("~250,000", "marks made", "roughly 500 a piece"),
        ("~150,000", "curved gestures", "the recurring motif, counted"), ("~1,000", "studio hours", "\u{2248}125 eight-hour days of creation"),
        ("~6,000", "canvas layers", "~12 per major work"), ("~3,000", "archive images", "the photographed record"),
    ]
    static let headline: [(String, String, String)] = [
        ("7", "years", "A daily creative practice \u{2014} the first run. The one thing nothing here replaces."),
        ("1,950", "commits", "Every one dated and signed, across nineteen repositories. The work, on the record."),
        ("94", "days worked", "From a study on May 13 to now. The build, still running."),
    ]
    static let fleet: [(String, String, String, String)] = [
        ("Prometheus \u{00B7} Clair", "The Architect", "Creative director who codes. Builds the house and guards its voice.", "prometheus"),
        ("Athena", "Strategy", "The compass. Direction, audits, course-correction \u{2014} founder only.", "athena"),
        ("Oracle", "Memory", "Reads the entire corpus. Answers from the founding record, in the register.", "oracle"),
        ("The Council \u{00D7}4", "The Board", "Research \u{00B7} Content \u{00B7} Strategist \u{00B7} Language. Independent reads, peer-reviewed, ruled.", "council-liaison"),
        ("Ody", "Research Instrument", "Long voyages into a single domain. Returns binding doctrine, not opinions.", "aether"),
        ("Explore", "Retrieval", "Finds anything across the vault and the code. Reads, never writes.", "explore"),
        ("Plan", "Architecture", "Scopes the build before a line is written. Names the risk first.", "plan"),
        ("Scribe", "The Record", "Keeps the logs. Every session documented; nothing lost.", "scribe"),
        ("The PL OG Crew", "Production", "Nine seats \u{2014} layout, copy, supply, signal, philosophy. Convened together on the work that needs all of them.", "pl-og-crew"),
        ("Corpus", "The Graph", "Holds the whole vault as a knowledge graph \u{2014} every link, every relation.", "corpus"),
        ("Zeus", "Placement", "Hierarchy, typography, colour, motion. Decides where the eye goes and why.", ""),
        ("Orama", "The Studio", "Creative code \u{2014} shaders, generative work, the VJ instrument. Builds and looks at what it built.", ""),
        ("Rhapso", "The Garment", "Which artwork becomes which product, on which cloth, by which technique.", ""),
        ("The Foundry", "Formatting", "Turns a finished piece into a shippable record \u{2014} dated, named, filed.", ""),
        ("Mockup Artist", "Variants", "One piece into its full visual set \u{2014} product shots, crops, per-surface formats.", ""),
        ("Growth Researcher", "Reach", "Watches the real numbers and researches what actually moves them.", ""),
        ("Opportunity Scout", "Outbound", "Finds the doors \u{2014} galas, placements, licensing. Proposes; never negotiates.", ""),
    ]
    static let pipeline: [(String, String, String)] = [
        ("01", "The deficit", "The engine reads the whole body of work and finds which Truth, which register, is under-served. It builds toward the gap, not the trend."),
        ("02", "The doctrine", "Thirty-seven binding craft rules load into every draft, verbatim. Not suggestions. The constraints the work has earned."),
        ("03", "The memory", "The Oracle retrieves from the founding record \u{2014} the actual conversations, the seven-year archive \u{2014} so the voice answers from itself, not from the internet."),
        ("04", "The voice gate", "Banned words, borrowed prestige, engagement bait \u{2014} rejected automatically before a human ever reads it. The register is law."),
        ("05", "The pairing", "A seed phrase and a glyph are drawn from the lexicon and matched to the piece. Symbol and sentence, set together."),
        ("06", "The draft", "Assembled with its artwork into the queue. Complete, but not yet real."),
        ("07", "The founder\u{2019}s say", "Nothing posts. Nothing ships. Not until one hand approves it. The machine drafts; the founder decides. Always."),
    ]
    static let receipts: [(String, String, String)] = [
        ("317,227", "Lines of code", "across nineteen systems, written and reviewed \u{2014} source files only, vendored code excluded"),
        ("1,950", "Commits", "dated and continuous, every repository"),
        ("1,391", "Notes", "the Second Mind \u{2014} doctrine, evidence, memory"),
        ("ARCHIVE", "Archive pieces", "the full archive, every piece and study, duplicates folded; live from the archive manifest"),
        ("33 / 4", "Games / 3D garments", "built into the site \u{2014} spin, zoom, AR"),
        ("257+", "Build sessions", "each one opened, logged, and closed on the record"),
        ("95.1M", "Tokens with the fleet", "the dialogue that built the second mind \u{2014} measured to Jun 22 2026, not re-counted since"),
    ]
    static let models: [(String, String, Double)] = [("Opus 4.8", "63.0M total", 66.2), ("Sonnet 4.6", "25.3M total", 26.6), ("Fable 5", "6.7M total", 7.1), ("Haiku 4.5", "0.1M total", 0.1)]
    static let timeline: [(String, String, String)] = [
        ("May 13", "The first keystroke", "It begins with the study \u{2014} the philosophy, mapped. Three weeks before the first line of the site is committed."),
        ("May 15\u{2013}28", "The experiments", "Curve studies, the archive, an early site, the outreach and signal engines. The shape gets found by building it wrong first."),
        ("Jun 5", "The Second Mind opens", "The work consolidates. The continuous record begins \u{2014} every session from here is dated, signed, kept."),
        ("Jun 6", "The True Codex", "225 founding conversations encoded into the vault \u{2014} the brand\u{2019}s primary source, made searchable."),
        ("Jun 8", "The brand & company audit", "The whole house benchmarked against seven luxury brands. The moat named: belonging, not spend."),
        ("Jun 9", "The Archive Classifier", "1,768 pieces read and sorted by an instrument; the site becomes a progressive web app."),
        ("Jun 10", "The Oracle goes live", "The founding record activated as memory \u{2014} the system answers in the voice, from itself."),
        ("Jun 12", "The Congregation", "Accounts, the climb, the room, the Creator Signal, 33 games \u{2014} the members layer, end to end."),
        ("Jun 13", "The 3D world + first signal", "The room rendered in three dimensions. The first transmission sent to the congregation."),
        ("Jun 14", "The media pipeline", "128 4K editorial renders and 96 films generated; four garments made interactive in 3D and AR."),
        ("Jun 15", "The apex", "psychedluxuries.com goes live on the new system. First order placed. The first patron sealed. This page written."),
    ]
    static let laws: [(String, String)] = [
        ("Every name passes the test before it exists", "Two tongues, two altitudes \u{2014} what the world sees, what the member discovers. A name that explains itself or borrows prestige fails."),
        ("Pain as doctrine, suffering as release", "The foundation under everything. The work is made under pressure, and heals by being made. It is not decoration."),
        ("Never instruct the model to answer in raw JSON", "A hard lesson, verified three times: it crashes the inference. Label the output in plain text and parse it. The machine has edges; the system maps them."),
        ("Never test an exclusion against the whole payload", "One field present on every order silently zeroed a core mechanic for days. Match the specific thing, never the blob. Found, written down, never again."),
        ("The standard is the Codex, the wall, or the storefront", "If a piece does not belong in one of the three, it does not ship. Crown or crucify \u{2014} there is no third response."),
    ]
    static let bodies: [(String, String)] = [
        ("Commercial", "The storefront. Funds the infrastructure. It sells."),
        ("The Defiance", "Healing through the hurt \u{2014} the work made under pressure, that reaches those carrying the same weight. The Golden Mend."),
        ("Fine Art", "The private archive. The permanent record. The one body never sold as product."),
    ]
    static let stack = ["Next.js 16", "Cloudflare Workers", "D1", "R2", "Vectorize", "AI Search", "Workers AI \u{00B7} llama-3.3-70b", "Resend", "Square"]
    static let specs: [(String, String)] = [("19", "systems"), ("317,227", "lines of code"), ("48", "skills"), ("17", "named instruments"), ("37", "craft laws"), ("10", "vault domains")]

    /// `SystemFlowchart`'s tiers: label, then each node's name, line and colour.
    static let tiers: [(String, [(String, String, UInt32)])] = [
        ("The Founder", [("You", "Capture \u{00B7} approve \u{00B7} publish \u{00B7} watch. The one node a Worker cannot replace.", 0xc9a84c)]),
        ("The Mind", [("Obsidian", "Doctrine \u{00B7} archive manifest \u{00B7} Codex \u{00B7} drafts. Agents read it through a local bridge.", 0x9b82c0),
                      ("Incubation Chamber", "Where founder Transmissions are drafted before they enter the pipeline.", 0x9b82c0),
                      ("V.A.U.L.T.", "The local board. NPU \u{00B7} Ollama \u{00B7} the Conductor \u{00B7} night crew.", 0x9b82c0)]),
        ("The Core", [("\u{2726} PSYCHED LUXURIES", "One living entity. You capture \u{2014} it creates itself.", 0xc9a84c)]),
        ("Operations", [("Notion", "Drop Pipeline \u{00B7} Content Calendar \u{00B7} Art Intake \u{00B7} System Status", 0x7d9a6b),
                        ("\u{27F3} Night Agents", "Briefing \u{00B7} Intake \u{00B7} Content wave \u{00B7} Pipeline sync. Stack health check 22:00 UTC.", 0x7d9a6b),
                        ("The Council", "The board \u{2014} Research \u{00B7} Content \u{00B7} Strategist \u{00B7} Language.", 0x7d9a6b),
                        ("Publishing", "Instagram \u{00B7} Threads \u{00B7} Bluesky \u{00B7} Tumblr \u{00B7} LinkedIn \u{00B7} Facebook \u{00B7} YouTube \u{2014} automated, direct from pl-cron. Pinterest \u{2014} the one manual lane, blocked on credentials. PL Feed \u{2192} Congregation (approve \u{00B7} push).", 0xc2603f)]),
        ("The Surface", [("The Site", "psychedluxuries.com \u{2014} pl-headless on CF Workers. The front door. Member Hub: profile \u{00B7} settings \u{00B7} chosen works \u{00B7} games \u{00B7} ask the founder.", 0xc9a84c),
                         ("PL-OS", "Master console \u{00B7} 3-brain board: /oracle \u{00B7} /ops \u{00B7} /jarvis \u{00B7} Tempo \u{00B7} PL Feed Queue \u{00B7} Post Queue \u{00B7} /inbox (member DMs) \u{00B7} auth-gated PWA", 0xc9a84c),
                         ("The Study", "Persona Academy \u{00B7} Oracle \u{00B7} Forge \u{00B7} Drills \u{00B7} Reader \u{00B7} Gated \u{00B7} CF AI 70b", 0x9b82c0),
                         ("The adaptation engine", "Resonance \u{2014} what the congregation wants.", 0xc9a84c),
                         ("The founder ledger", "The climb \u{00B7} the seals \u{00B7} who belongs.", 0xc9a84c)]),
        ("The Spine", [("Cloudflare", "Workers \u{00B7} D1 \u{00B7} R2 \u{00B7} Vectorize \u{00B7} AI Gateway \u{2014} edge in 200+ cities", 0x6f93a8),
                       ("R2 pl-archive", "~12,000 assets \u{00B7} images public via pl-os /i/", 0x6f93a8),
                       ("D1 pl-transmission", "subscribers \u{00B7} posts_queue \u{00B7} desires \u{00B7} captures \u{00B7} transmissions \u{00B7} accounts \u{00B7} member_dms \u{00B7} public_comments \u{00B7} feed_posts", 0x6f93a8),
                       ("The Oracle", "Memory \u{2014} Vectorize corpus \u{00B7} AI Search \u{00B7} the founding record.", 0x6f93a8)]),
        ("Commerce", [("Square", "Commerce backend only \u{2014} Printful catalog \u{00B7} Payment Link checkout \u{00B7} fulfillment. The site is pl-headless, not Square.", 0xc2603f)]),
    ]
}
