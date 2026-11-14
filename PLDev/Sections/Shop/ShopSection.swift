import SwiftUI
import TipKit
import UserNotifications

/// Shop: the public face of psychedluxuries.com as a native app (lane A, his order 11-13). The shop grid, the piece pages,
/// the Closet, the archive and the small rooms (the signal, track an order, the site's status, the pages). Everything reads the
/// site itself through `Site`; the catalogue is the site's product feed, so it cannot disagree with the till. Checkout is
/// Square's hosted page behind a human check, so "Buy" opens the piece on the site in Safari's sheet.
@MainActor enum ShopSection: PLSection {
    static let manifest = SectionManifest(id: "shop", title: "Shop", symbol: "bag.fill", needsKeys: [], needsOrigins: ["site"])
    static let state = ShopModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(ShopView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] {
        [ProbeModel.Item(id: "shop.catalogue", title: "Shop catalogue", detail: "Reads the site's product feed and counts the pieces and their flat pictures.", result: .untested, run: {
            await ShopStore.shared.load(force: true)
            let s = ShopStore.shared
            if s.pieces.isEmpty { return .fail(s.failure ?? "The feed came back empty.") }
            let flats = s.pieces.reduce(0) { $0 + $1.images.count }
            return .pass("\(s.pieces.count) pieces, \(flats) flat pictures")
        })]
    }

    /// The Shop's rows in Settings: how fresh the list is, and a reload.
    static func settingsRows(model: AppModel) -> AnyView? { AnyView(ShopSettingsRows()) }
    /// "A new piece" has no button: the notice opens the piece. Declaring the type gives it a switch in Settings.
    static func notificationCategories() -> Set<UNNotificationCategory> {
        [UNNotificationCategory(identifier: "shop.new", actions: [], intentIdentifiers: [])]
    }

    static func handle(link: DeepLink, model: AppModel) -> Bool {
        guard case .section(_, let path, _) = link, let first = path.first else { return true }
        if first == "piece", path.count > 1 { state.tab = .shop; state.pieceSlug = path[1]; return true }
        if first == "collection", path.count > 1 { state.tab = .shop; state.collectionSlug = path[1]; return true }
        if first == "tag", path.count > 1 { model.open(.section(id: "congregation", path: ["tag", path[1]], query: [:])); return true }   // one tag view: the Congregation's, on the JSON route
        if let room = ShopRoom(rawValue: first) { state.open(room) }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        let store = ShopStore.shared
        await store.load()
        let fresh = store.takeNewPieces()
        StorefrontGlanceWriter.publishShop(store: store, fresh: fresh)
        var notify: [LocalNotice] = []
        if !fresh.isEmpty {
            let body = fresh.count == 1 ? "\(fresh[0].name) is in the shop." : "\(fresh.count) new pieces: " + fresh.prefix(3).map(\.name).joined(separator: ", ") + (fresh.count > 3 ? " and more." : ".")
            notify.append(LocalNotice(id: "shop.new", title: "New in the shop", body: body, category: "shop.new",
                                      link: .section(id: "shop", path: fresh.count == 1 ? ["piece", fresh[0].slug] : [], query: [:])))
        }
        return SectionRefresh(badge: nil, notify: notify)
    }
}

@MainActor @Observable final class ShopModel {
    enum Tab: String, CaseIterable, Identifiable {
        case shop, closet, archive, more
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var tab: Tab = .shop
    var room: ShopRoom?
    var pieceSlug: String?
    var collectionSlug: String?
    /// A congregation hashtag opened here (`pldev://section/shop/tag/<tag>`).
    var tick = 0
    /// Bumped by the home page's "The full shop →": the grid scrolls to its own opening.
    var homeScroll = 0

    /// A room by name: the three that are tabs switch the tab, the rest are pushed.
    func open(_ r: ShopRoom) {
        if let t = Tab(rawValue: r.rawValue) { tab = t; room = nil } else { tab = .more; room = r }
    }
}

struct ShopView: View {
    let model: AppModel
    @Bindable var state: ShopModel

    var body: some View {
        Group {
            switch state.tab {
            case .shop: ShopGridView(state: state)
            case .closet: ClosetView(state: state)
            case .archive: ArchiveView(model: model)
            case .more: ShopMoreView(model: model, state: state)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SiteTabs(titles: ShopModel.Tab.allCases.map(\.title), index: Binding(
                get: { ShopModel.Tab.allCases.firstIndex(of: state.tab) ?? 0 },
                set: { state.tab = ShopModel.Tab.allCases[$0] }))
        }
        .background { SiteGround() }
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.select, trigger: state.tab)
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .navigationDestination(item: $state.room) { room in room.view(model) }
        .navigationDestination(item: $state.pieceSlug) { slug in PieceView(slug: slug, state: state) }
        .navigationDestination(item: $state.collectionSlug) { slug in CollectionView(slug: slug, state: state) }
    }
}

/// The Shop's own rows in Settings.
struct ShopSettingsRows: View {
    private let store = ShopStore.shared
    @State private var note: String?

    var body: some View {
        Group {
            LabeledContent {
                if let at = store.loadedAt { Text(at, format: .relative(presentation: .named)) } else { Text("Not read yet") }
            } label: {
                SettingsLabel("Shop list: \(store.pieces.count) pieces", "bag", IOS27.SystemColors.orange)
            }
            Button {
                Task {
                    await store.load(force: true)
                    note = store.pieces.isEmpty ? "Not reloaded. \(store.failure ?? "")" : "Reloaded: \(store.pieces.count) pieces."
                }
            } label: {
                SettingsLabel("Reload the shop list now", "arrow.clockwise", Color(uiColor: .systemGray))
            }
            ResultLine(text: note)
        }
    }
}

// MARK: - Tips (only for what cannot be seen)

struct PieceHoldTip: Tip {
    var title: Text { Text("More on every piece") }
    var message: Text? { Text("Touch and hold a piece to share it, put it in the Closet or open it on the site.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
