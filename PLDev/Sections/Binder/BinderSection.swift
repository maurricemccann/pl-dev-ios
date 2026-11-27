import SwiftUI
import UserNotifications

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
        .sheet(item: $open) { card in
            NavigationStack {
                ScrollView { EarnedCardFace(model: model, card: card).padding() }
                    .navigationTitle(BinderSection.shelf(card.from)).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { open = nil } } }
            }
        }
    }

    private func load() async {
        failed = false
        collection = await PracticeCards.load(model: model)
        failed = collection == nil
    }
}
