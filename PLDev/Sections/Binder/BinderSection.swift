import SwiftUI
import UserNotifications
import WebKit

/// PL Binder (his ask 11-27: "all my cards should be saved into a display PL BINDER"): every card he has earned, from the
/// Practice evening, Practice lessons, PL Prod beats, PL Prog lessons and Gate sittings, kept by the practice Worker
/// (`GET /api/collection`, each card naming the pack key that dealt it). Read only: the cards are earned in the apps.
@MainActor enum BinderSection: PLSection {
    static let manifest = SectionManifest(id: "binder", title: "PL Binder", symbol: "books.vertical", needsKeys: [], needsOrigins: ["practice"])
    static func makeRoot(model: AppModel) -> AnyView { AnyView(BinderView(model: model)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }

    /// The app a card came from, by its pack key.
    static func shelf(_ from: String?) -> String {
        guard let f = from else { return "Practice" }
        if f == "evening" { return "Practice evenings" }
        if f.hasPrefix("lesson-") || f.hasPrefix("gold-") { return "Practice lessons" }
        if f.hasPrefix("prod-") { return "PL Prod" }
        if f.hasPrefix("prog-") { return "PL Prog" }
        if f.hasPrefix("gate-") { return "Gate" }
        return "Other"
    }
}

struct BinderView: View {
    let model: AppModel
    @State private var collection: PracticeCollection?
    @State private var failed = false
    @State private var open: PracticeEarned?

    private var shelves: [(String, [PracticeEarned])] {
        let cards = collection?.cards ?? []
        let order = ["PL Prod", "PL Prog", "Gate", "Practice lessons", "Practice evenings", "Practice", "Other"]
        let g = Dictionary(grouping: cards) { BinderSection.shelf($0.from) }
        return order.compactMap { k in g[k].map { (k, $0) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let c = collection {
                    Text(c.count == 1 ? "1 card" : "\(c.count) cards").font(Font.pl(.title2).weight(.semibold))
                    if c.cards.isEmpty {
                        Text("Finish a lesson in PL Prod, PL Prog, Gate or Practice and its pack lands here.").font(Font.pl(.body)).foregroundStyle(.secondary)
                    }
                    if let games = c.games, !games.isEmpty {
                        Text("Games unlocked: " + games.joined(separator: ", ")).font(Font.pl(.subheadline)).foregroundStyle(.secondary)
                    }
                    ForEach(shelves, id: \.0) { name, cards in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(name) · \(cards.count)").font(Font.pl(.headline))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                ForEach(cards) { card in
                                    Button { open = card } label: { EarnedCardFace(model: model, card: card) }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Card from \(name), \(card.date). Opens full size")
                                }
                            }
                        }
                    }
                } else if failed {
                    Text("Could not read your binder: the practice did not answer. Your cards are kept.").font(Font.pl(.body)).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }.buttonStyle(.bordered).frame(minHeight: 44)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding()
        }
        .plScreenTitle("PL Binder")
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(item: $open) { card in BinderSlab(model: model, card: card) { open = nil } }
    }

    private func load() async {
        failed = false
        collection = await PracticeCards.load(model: model)
        failed = collection == nil
    }
}

/// One card in its graded slab, to turn with a finger (his ask 11-27: "the pl binder should hold the spinnable graded card"): the pack
/// page's own three.js slab (`/pack/?binder`), so the case, label and back are the ones the pack deals. Close leaves.
struct BinderSlab: View {
    let model: AppModel
    let card: PracticeEarned
    let close: () -> Void
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url { SlabWeb(url: url).ignoresSafeArea() }
            else if failed { Text("This card has no picture to put in the slab.").font(Font.pl(.body)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            Button(action: close) { Image(systemName: "xmark").font(Font.pl(size: 17, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.4), in: Circle()) }
                .accessibilityLabel("Close").padding(.leading, 16).padding(.top, 8)
        }
        .task { await build() }
    }

    /// Evening cards are graded Obsidian, lesson cards Champagne, a gold unit's card Prism: the grade says how it was earned.
    private var tier: String {
        let f = card.from ?? ""
        return f == "evening" ? "common" : f.hasPrefix("gold-") ? "exclusive" : "legendary"
    }

    private func build() async {
        let base = LibraryData.shared.base(model)
        guard let still = await PracticeCards.still(for: card.piece, model: model), var c = URLComponents(string: base + "/pack/") else { failed = true; return }
        c.queryItems = [URLQueryItem(name: "binder", value: "1"), URLQueryItem(name: "img", value: still.path(percentEncoded: false)),
                        URLQueryItem(name: "name", value: (card.from ?? "practice").replacingOccurrences(of: "-", with: " ")),
                        URLQueryItem(name: "tier", value: tier), URLQueryItem(name: "date", value: card.date)]
        url = c.url
        failed = url == nil
    }
}

private struct SlabWeb: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
