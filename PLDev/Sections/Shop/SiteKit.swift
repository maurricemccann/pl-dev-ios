import SwiftUI

// Shared pieces for the site's story pages (home, the collection pages, the study, the system, the archive strips), each a
// twin of something pl-headless draws on every page: the obsidian band, the gold curves behind a hero, "Watch this." in his
// hand, the tracked-capital door links and gold pills, and the readers for the site's public data.

/// The site's obsidian band (`bg-obsidian text-bone`): dark in both appearances, the way the site draws it.
struct SiteBand<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(.horizontal, padding).padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0e0c08))
            .environment(\.colorScheme, .dark)
    }
}

/// The site's paper band (`bg-paper border-y border-line`).
struct SitePaper<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(.horizontal, 24).padding(.vertical, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Bone.raised(scheme))
            .overlay(alignment: .top) { SiteRule() }
            .overlay(alignment: .bottom) { SiteRule() }
    }
}

/// "Watch this." in his hand, gold: the line every page of the site closes on.
struct SiteWatch: View {
    var size: CGFloat = 30
    var body: some View {
        Text("Watch this.").plHand(size).foregroundStyle(Bone.gold).frame(maxWidth: .infinity).accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// The `.label` style in a chosen colour (`label text-gold`). `siteLabel` sets ink-faint on the text itself, which an outer
    /// colour cannot override, so a coloured label uses this.
    func siteTag(_ size: CGFloat = 11, _ color: Color) -> some View {
        font(SiteFont.body(size, relativeTo: .caption)).textCase(.uppercase).tracking(size * 0.3).foregroundStyle(color)
    }
}

/// A tracked-capital text door (`… →`), 44 points tall.
struct SiteDoorLabel: View {
    let title: String
    var gold = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title).siteTag(10, gold ? Bone.gold : Bone.inkFaint(scheme)).frame(minHeight: 44)
    }
}

/// A large headline in the display face with one italic gold run, wherever the run sits ("You *prepared* before you knew why.").
struct SiteDisplay: View {
    let parts: [(String, Bool)]
    var size: CGFloat = 44
    var center = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        parts.reduce(Text("")) { acc, p in
            acc + Text(p.0).font(SiteFont.display(size, italic: p.1)).foregroundColor(p.1 ? Bone.gold : Bone.ink(scheme))
        }
        .lineSpacing(0).multilineTextAlignment(center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The homepage's gold curves (`components/art/GoldCurves.tsx`, the same rig `CurveLiveView` runs) as a quiet layer behind
/// a section on the bone ground. A finger pushes the ropes aside, as on the site. Reduce Motion holds one still frame.
struct GoldCurvesLayer: View {
    var opacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rig = CurveRig()
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                rig.reduce = reduceMotion
                rig.setup(size)
                rig.advance(tl.date)
                rig.draw(&ctx, rgb: Bone.gold)
            }
        }
        .opacity(opacity)
        .simultaneousGesture(DragGesture(minimumDistance: 0)   // alongside the page's scroll, never instead of it
            .onChanged { v in rig.mx = v.location.x; rig.my = v.location.y }
            .onEnded { _ in rig.mx = -1e9; rig.my = -1e9 })
        .accessibilityHidden(true)
    }
}

/// A glyph drawn as a mask in one colour (the site's `mask-image` glyph cards). Loads the site's own PNG and tints it.
struct SiteGlyphMask: View {
    let url: URL?
    var color: Color = Bone.gold
    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let i) = phase { color.mask { i.resizable().scaledToFit() } } else { Color.clear }
        }
        .accessibilityHidden(true)
    }
}

/// The site's public reads that are not its own JSON: a page's HTML (for a server-rendered list with no JSON route yet),
/// kept for offline like every read, and pl-cron's public routes through the config's "cron" origin.
@MainActor enum SiteData {
    /// A page of the site as text, the saved copy when the site cannot be reached.
    static func html(_ path: String) async -> String? {
        let key = "site-page|" + path
        if let r = try? await Site.call("GET", path), (200..<300).contains(r.status) {
            OfflineCache.save(r.data, for: key)
            return String(data: r.data, encoding: .utf8)
        }
        if let (saved, at) = OfflineCache.load(key) { OfflineState.servedCopy(from: at); return String(data: saved, encoding: .utf8) }
        return nil
    }

    /// A public pl-cron route (no key). Throws a plain sentence.
    static func cron<T: Decodable>(_ path: String, _ type: T.Type, query: [String: String] = [:]) async throws -> T {
        guard let http = AppModel.shared.http, AppModel.shared.config?.origin("cron") != nil else { throw Site.Problem.notSetUp }
        let data = try await http.send(RequestPlan(origin: "cron", path: path, query: query), timeout: 25)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Site.Problem.refused("The answer came back in a shape this app does not know yet.") }
    }

    /// Every match of a regex's capture groups in a string (the HTML readers). Pure.
    nonisolated static func matches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
        }
    }
}

/// The archive's live count (`lib/archive-count.ts`: the manifest's own `count`, never a rounded claim).
@MainActor @Observable final class SiteArchiveCount {
    static let shared = SiteArchiveCount()
    var count: Int?
    private struct M: Decodable { let count: Int? }
    func load() async {
        if count != nil { return }
        let key = "archive|count"
        if let u = URL(string: "https://assets.psychedluxuries.com/manifest.json"),
           let (d, r) = try? await URLSession.shared.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200,
           let n = try? JSONDecoder().decode(M.self, from: d).count {
            OfflineCache.save(Data("\(n)".utf8), for: key); count = n; return
        }
        if let (d, _) = OfflineCache.load(key), let n = Int(String(decoding: d, as: UTF8.self)) { count = n; return }
        if !ArchiveStore.shared.works.isEmpty { count = ArchiveStore.shared.works.count }
    }
    /// "1,347", or the archive grid's own count while the manifest is on its way.
    var text: String { (count ?? (ArchiveStore.shared.works.isEmpty ? nil : ArchiveStore.shared.works.count)).map { $0.formatted() } ?? "\u{2014}" }
}

/// The shop's pieces as a pushed page, for doors on pages that are themselves pushed (`/shop` from the Wardrobe, Seeds…).
struct SiteShopList: View {
    private let store = ShopStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SitePageHead(eyebrow: "The shop" + (store.pieces.isEmpty ? "" : " \u{2014} \(store.pieces.count) pieces"), lead: "Wearable", accent: "doctrine.")
                if store.pieces.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                else { PieceGrid(pieces: store.pieces, state: ShopSection.state) }
            }
            .padding(.bottom, 32)
        }
        .siteScreen()
        .plScreenTitle("The shop")
        .task { await store.load() }
        .refreshable { await store.load(force: true) }
    }
}
