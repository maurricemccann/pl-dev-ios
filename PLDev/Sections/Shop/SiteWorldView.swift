import SwiftUI

/// `/world`, the Collections page: the hero, every collection as a tile with its own glyphs drifting faint behind the type
/// (`TileGlyphs`, the founder's S311 crown), the manifesto, and the live signal (his newest Instagram posts from pl-cron's
/// public `api/ig-feed`, the same read the site makes).
struct SiteWorldView: View {
    @State private var feed: [IGItem] = []
    @State private var feedFailed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    struct IGItem: Decodable, Identifiable { let id: String; let permalink: String?; let image: String?; let caption: String? }
    private struct IGReply: Decodable { let items: [IGItem]? }

    private let tiles = ShopCollection.all

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SiteBand {
                    VStack(spacing: 24) {
                        Text("The Psyched Luxuries Collections").siteTag(11, Bone.gold)
                        (Text("The Collections\n").foregroundColor(Color(hex: 0xf1ece1)) + Text("Expand").foregroundColor(Bone.gold))
                            .font(SiteFont.display(50, italic: true)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        Text("Each drop is not a product release. It is a chapter in an ongoing mythology. Every glyph expands the vocabulary. Every piece adds to the architecture. The world is being built in real time.")
                            .siteBody(15).multilineTextAlignment(.center)
                        NavigationLink { SiteShopList() } label: { Text("Enter the Collection") }.buttonStyle(SitePill(gold: true))
                        if WardrobePiece.hasVisible { NavigationLink { WardrobeView() } label: { Text("The Wardrobe \u{2014} in 3D") }.buttonStyle(SiteGhost()) }
                        NavigationLink { StudyView() } label: { Text("Read the Philosophy") }.buttonStyle(SiteGhost())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                SitePaper {
                    VStack(spacing: 10) {
                        Text("The Drops").siteLabel()
                        Text("Collections").font(SiteFont.display(40)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
                        Rectangle().fill(Bone.gold.opacity(0.5)).frame(width: 64, height: 1).padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 20)
                    VStack(spacing: 0) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { i, c in
                            NavigationLink { CollectionView(slug: c.slug, state: ShopSection.state) } label: { tile(c, seed: 20 + i * 13) }
                                .buttonStyle(.plain)
                            SiteRule()
                        }
                    }
                    .overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
                }
                SiteBand {
                    VStack(spacing: 22) {
                        Text("Built by Those Who\nBelieve Before It Arrives").font(SiteFont.display(36, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                        Text("Psyched Luxuries was not founded to compete in fashion. It was built to document a state of mind. The mythology grows with each drop. The philosophy deepens with each piece added to the archive.")
                            .siteBody(15).multilineTextAlignment(.center)
                        Text("You are not buying a shirt. You are joining a language.").siteBody(15).multilineTextAlignment(.center)
                        NavigationLink { ArchiveView(model: .shared) } label: { Text("Enter the Archive") }.buttonStyle(SitePill(gold: true))
                        NavigationLink { StudyView() } label: { Text("The Philosophy") }.buttonStyle(SiteGhost())
                        SiteWatch().padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                signal
            }
        }
        .siteScreen()
        .plScreenTitle("The Collections")
        .task { await loadFeed() }
        .refreshable { await loadFeed() }
    }

    private func tile(_ c: ShopCollection, seed: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collection").siteLabel()
            Text(c.title).font(SiteFont.display(28)).foregroundStyle(Bone.ink(scheme))
            Text("View \u{2192}").siteLabel(10).padding(.top, 14)
        }
        .padding(32).frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .background { TileGlyphs(glyphs: SiteTileGlyphs.of(c.slug), seed: seed) }
        .clipped().contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var signal: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The signal, live").siteLabel()
            if feed.isEmpty {
                if feedFailed { Text("The signal did not answer. Pull to try again.").siteBody(14) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(feed) { it in
                        Button { if let p = it.permalink, let u = URL(string: p) { openURL(u) } } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit).overlay {
                                AsyncImage(url: it.image.flatMap(URL.init(string:))) { ph in
                                    if case .success(let i) = ph { i.resizable().scaledToFill() } else { Bone.line(scheme) }
                                }
                            }
                            .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String((it.caption ?? "Instagram post").prefix(80)))
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 48)
    }

    private func loadFeed() async {
        do { feed = (try await SiteData.cron("api/ig-feed", IGReply.self, query: ["limit": "6"])).items ?? []; feedFailed = feed.isEmpty }
        catch { feedFailed = true }
    }
}

/// `collectionGlyphs(slug)`: the print-file glyphs a collection's tile carries.
enum SiteTileGlyphs {
    struct G: Hashable { let url: URL; let k: Double; let o: Double }
    private static func suffix(_ s: String) -> [String] { SiteDesignGlyphs.table.keys.filter { $0.hasSuffix(s) }.sorted() }
    private static let keys: [String: [String]] = [
        "classics": ["heart-mark-tee", "psyched-wordmark-tee", "money-glyph-tee"],
        "glyphs": ["glyph-guy-tee", "money-glyph-tee", "love-yourself-glyph-tee", "money-grin-tee", "what-goes-around-comes-around-tee", "money-always-goes-up-tee"],
        "what-goes-around-comes-around": ["what-goes-around-comes-around-tee"], "money-glyphguy": ["glyph-guy-tee"],
        "love-yourself-glyph": ["love-yourself-glyph-tee"], "money-glyph": ["money-glyph-tee"],
        "seeds": ["seed-og-tee", "faces-tee", "smiling-faces-tee"], "heart-logo": ["heart-mark-tee"],
        "psyched": ["psyched-wordmark-tee", "psyched-tee", "psyched-signature-tee"],
        "tees": suffix("-tee"), "hoodies": suffix("-hoodie"), "sweats": suffix("-sweats"), "crops": suffix("-crop"), "crewnecks": suffix("-crewneck"),
        "womens": suffix("-crop"), "mens": Array(suffix("-tee").prefix(6)) + Array(suffix("-hoodie").prefix(6)),
        "art-supplies": ["money-glyph-tee", "heart-mark-tee"], "home-goods": ["love-yourself-glyph-tee", "heart-mark-tee", "money-glyph-tee"],
    ]
    private static func url(_ key: String) -> URL? { URL(string: "https://assets.psychedluxuries.com/design-glyphs/\(key).png?v=2") }

    static func of(_ slug: String) -> [G] {
        if slug == "poverty-to-luxury" { return url("poverty-to-luxury").map { [G(url: $0, k: 1.75, o: 1.2)] } ?? [] }
        return (keys[slug] ?? []).compactMap { k in
            guard let t = SiteDesignGlyphs.table[k], let u = url(k) else { return nil }
            return G(url: u, k: t.k, o: t.o)
        }
    }
}

/// Fetched pictures kept for the life of the app, so a page full of tiles draws each glyph once.
@MainActor @Observable final class SiteImages {
    static let shared = SiteImages()
    private(set) var images: [URL: UIImage] = [:]
    private var pending: Set<URL> = []
    func want(_ urls: [URL]) {
        for u in urls where images[u] == nil && !pending.contains(u) {
            pending.insert(u)
            Task {
                if let (d, r) = try? await URLSession.shared.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200, let i = UIImage(data: d) { images[u] = i }
                pending.remove(u)
            }
        }
    }
}

/// One tile's glyph pattern: a grid of cells, one glyph each, seeded placement and tilt, three faint planes.
struct TileGlyphs: View {
    let glyphs: [SiteTileGlyphs.G]
    let seed: Int
    private let pics = SiteImages.shared

    var body: some View {
        Canvas { ctx, size in
            guard !glyphs.isEmpty else { return }
            let cell = 80.0
            var s = seed
            func rnd() -> Double { s = (s * 9301 + 49297) % 233280; return Double(s) / 233280 }
            var i = 0
            for y in 0..<Int((size.height / cell).rounded(.up)) {
                for x in 0..<Int((size.width / cell).rounded(.up)) {
                    let g = glyphs[i % glyphs.count]; i += 1
                    let side = (cell * min(0.46 * g.k, 0.8)).rounded(), plane = Int(rnd() * 3)
                    let px = Double(x) * cell + (cell - side) * (0.04 + rnd() * 0.92)
                    let py = Double(y) * cell + (cell - side) * (0.04 + rnd() * 0.92)
                    let rot = (rnd() * 44 - 22).rounded()
                    let op = min((0.12 + Double(plane) * 0.04) * g.o, 0.32)
                    guard let img = pics.images[g.url] else { continue }
                    var c = ctx
                    c.opacity = op
                    c.translateBy(x: px + side / 2, y: py + side / 2)
                    c.rotate(by: .degrees(rot))
                    c.draw(Image(uiImage: img).resizable(), in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                }
            }
        }
        .onAppear { pics.want(glyphs.map(\.url)) }
        .accessibilityHidden(true)
    }
}
