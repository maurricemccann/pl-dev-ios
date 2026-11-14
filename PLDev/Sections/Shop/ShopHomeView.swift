import SwiftUI

/// psychedluxuries.com's home page (`app/page.tsx`), natively, at the top of the Shop tab: the hero over the gold curves,
/// the proof band (the archive's live count), the thesis, the Three Truths, the New Drop row, the four doors into the world,
/// the Forge, the congregation's wall (its newest approved declarations, read off the live page), and the closing line.
/// The site's three collections follow it on the shop page (`CollectionsShelf`), so they are not drawn twice.
struct ShopHomeView: View {
    @Bindable var state: ShopModel
    private let store = ShopStore.shared
    private let count = SiteArchiveCount.shared
    @State private var desires: [Desire] = []
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    struct Desire: Hashable { let text: String; let name: String? }

    private static let truths: [(String, String, String)] = [
        ("I", "Prepared for Luxury", "The preparation is the luxury. Readiness as the luxury itself \u{2014} not wealth seeking it. The garment confirms what the mind has already established."),
        ("II", "You Are in Control of Your Reality", "Not influence. Control. Sovereign control. Not a comfort \u{2014} a responsibility. The brand does not sell hope. It sells sovereignty."),
        ("III", "What Persists in the Mind Becomes Your Reality", "The mechanism. The law behind the law. Seven years of daily creation is the longest argument the brand makes."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            proof
            thesis
            doctrine
            newDrop
            gateways
            forge
            congregation
            Text("Luxury is not purchased. It is realized \u{2014} always already present, waiting.")
                .font(SiteFont.display(30, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 16)
            SiteWatch().padding(.bottom, 40)
            SiteRule()
        }
        .task { await count.load() }
        .task { desires = await Self.loadDesires() }
    }

    // MARK: the hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GoldCurvesLayer().frame(height: 620).clipped()
            VStack(alignment: .leading, spacing: 26) {
                Text("Psyched Luxuries \u{2014} Since April 2019").siteLabel()
                SiteDisplay(parts: [("You ", false), ("prepared", true), ("\nbefore you\nknew why.", false)], size: 50)
                Text("A philosophy-first wearable art practice. Seven years of daily creation, unbroken. The archive is not the backstory \u{2014} it is the evidence.")
                    .siteBody(16)
                NavigationLink { SiteRoomView() } label: { Text("Enter the Room \u{2192}").padding(.horizontal, 12) }
                    .buttonStyle(SitePill(gold: true)).fixedSize()
            }
            .padding(.horizontal, 24).padding(.bottom, 56)
        }
    }

    private var proof: some View {
        SiteBand {
            HStack(alignment: .top, spacing: 18) {
                stat(count.text, "pieces in the archive")
                stat("7 years", "unbroken daily practice")
                stat("90%", "Curve-governed")
            }
            Text("The archive is the argument.").font(SiteFont.display(20, italic: true)).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.8))
                .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ v: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(v).font(SiteFont.display(28)).foregroundStyle(Bone.gold).contentTransition(.numericText()).minimumScaleFactor(0.7).lineLimit(1)
            Text(k).siteLabel(9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var thesis: some View {
        SiteBand {
            VStack(spacing: 24) {
                Text("The Thesis").siteTag(11, Bone.gold)
                (Text("The brand is not ") + Text("about").foregroundColor(Color(hex: 0xe8d190)) + Text(" the practice. The brand ")
                 + Text("is").foregroundColor(Color(hex: 0xe8d190)) + Text(" the practice. Its existence \u{2014} the archive, the pricing, the structure \u{2014} is the argument."))
                    .font(SiteFont.display(25, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center).lineSpacing(3)
                Text("The architect is always the first building").siteLabel(10).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private var doctrine: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The Doctrine").siteLabel()
                Text("The Three Truths").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
            }
            Rectangle().fill(Bone.gold).frame(width: 64, height: 1)
            ForEach(Self.truths, id: \.0) { t in
                VStack(alignment: .leading, spacing: 10) {
                    Text(t.0).plHand(46).foregroundStyle(Bone.gold)
                    Text(t.1).plHand(26).foregroundStyle(Bone.ink(scheme))
                    Text(t.2).siteBody(14)
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink { StudyView() } label: { SiteDoorLabel(title: "Read the philosophy \u{2192}") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 64)
    }

    @ViewBuilder private var newDrop: some View {
        let featured = Array(store.pieces.prefix(4))
        if !featured.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Drop \u{2014} Seeds 2026").siteLabel()
                    Text("Wear the argument.").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 24)
                PieceGrid(pieces: featured, state: state)
                Button { withAnimation { state.homeScroll += 1 } } label: { SiteDoorLabel(title: "The full shop \u{2192}") }
                    .buttonStyle(.plain).padding(.horizontal, 24)
            }
            .padding(.bottom, 48)
        }
    }

    private var gateways: some View {
        SitePaper {
            Text("Enter the World").siteLabel().frame(maxWidth: .infinity).padding(.bottom, 12)
            VStack(spacing: 0) {
                gate("The Shop", "Wearable doctrine. Each piece traces to a Truth.") { v in Button { withAnimation { state.homeScroll += 1 } } label: { v }.buttonStyle(.plain) }
                SiteRule()
                gate("The Archive", "The complete works, dated and documented. The evidence.") { v in Button { state.tab = .archive } label: { v }.buttonStyle(.plain) }
                SiteRule()
                gate("Living Curves", "The law of all becoming, made visible.") { v in NavigationLink { LivingCurvesView() } label: { v }.buttonStyle(.plain) }
                SiteRule()
                gate("The Study", "The practice, made accessible to the mind.") { v in NavigationLink { StudyView() } label: { v }.buttonStyle(.plain) }
            }
        }
    }

    private func gate<B: View>(_ h: String, _ d: String, @ViewBuilder wrap: (AnyView) -> B) -> some View {
        wrap(AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(h).font(SiteFont.display(30)).foregroundStyle(Bone.ink(scheme))
                Text(d).siteBody(14)
                Text("View \u{2192}").siteLabel(10)
            }
            .padding(.vertical, 28).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        ))
        .accessibilityElement(children: .combine)
    }

    private var forge: some View {
        SiteBand {
            VStack(spacing: 18) {
                Text("Also Taught").siteTag(11, Bone.gold)
                Text("The Forge.").font(SiteFont.display(40, italic: true)).foregroundStyle(Color(hex: 0xf1ece1))
                Text("The system that built this house \u{2014} the spec, the loop, the fleet \u{2014} taught module by module, the way it was actually learned.")
                    .siteBody(15).multilineTextAlignment(.center)
                NavigationLink { SiteReaderView(path: "the-forge", title: "The Forge") } label: { Text("Enter the Forge \u{2192}").padding(.horizontal, 12) }
                    .buttonStyle(SitePill(gold: true)).fixedSize()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var congregation: some View {
        SiteBand {
            VStack(spacing: 18) {
                Text("The Congregation").siteTag(11, Bone.gold)
                Text("The wall holds your declaration.").font(SiteFont.display(34, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                Text("One wall gets spectators. The other builds disciples. State what you are claiming \u{2014} the archive will reflect it back.")
                    .siteBody(15).multilineTextAlignment(.center)
                ForEach(desires.prefix(3), id: \.self) { d in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\u{201C}\(d.text)\u{201D}").font(SiteFont.display(19, italic: true)).foregroundStyle(Color(hex: 0xe8d190)).lineSpacing(3)
                        if let n = d.name { Text("\u{2014} \(n)").siteLabel(10) }
                    }
                    .padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8) }
                }
                Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: { Text("State Your Reality \u{2192}").padding(.horizontal, 12) }
                    .buttonStyle(SitePill(gold: true)).fixedSize().padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The wall's newest approved declarations, as the home page prints them (there is no JSON route for the wall: the page
    /// reads D1 in a server action). `“text”` then an optional `— name`.
    static func loadDesires() async -> [Desire] {
        // the JSON route first (S348·9a3e: /api/desires, anonymous names never leave the server); the page's markup as fallback
        struct R: Decodable { struct D: Decodable { let text: String; let name: String? }; let desires: [D] }
        if let r = try? await Site.get("api/desires", R.self, query: ["limit": "3"]), !r.desires.isEmpty { return r.desires.map { Desire(text: $0.text, name: $0.name) } }
        guard let html = await SiteData.html("") else { return [] }
        return parseDesires(html)
    }

    nonisolated static func parseDesires(_ html: String) -> [Desire] {
        let rows = SiteData.matches(#"text-gold-light leading-relaxed">“(.{1,600}?)”</p>(?:<p[^>]{0,200}>— (.{1,120}?)</p>)?"#, in: html)
        var seen = Set<String>()
        return rows.compactMap { r in
            let t = SiteHTML.text(r[0])
            guard !t.isEmpty, seen.insert(t).inserted else { return nil }
            let n = SiteHTML.text(r.count > 1 ? r[1] : "")
            return Desire(text: t, name: n.isEmpty ? nil : n)
        }
    }
}
