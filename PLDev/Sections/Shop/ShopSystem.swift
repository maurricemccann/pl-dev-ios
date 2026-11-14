import AppIntents
import CoreSpotlight
import SwiftUI
import WidgetKit

// The Shop's system add-ons (his loop: build in full, test, then the premium feel). Built to the same guidance as House:
// App Shortcuts that say every count, Spotlight through IndexedEntity + OpenIntent, the widget's numbers from the app's last read,
// deep links by room name. A Live Activity is not fitting here (see LANES-storefront.md).

// MARK: - Rooms

enum ShopRoom: String, CaseIterable, Identifiable, Hashable {
    case shop, closet, archive, curve, signal, contact, track, orders, status, pages
    case world, wardrobe, chosen, livingCurves = "living-curves", source, study, curveName = "curve-name", system, room, journal
    var id: String { rawValue }

    /// The rooms listed under More; the first three are tabs.
    static var moreRooms: [ShopRoom] { [.world, .study, .livingCurves, .chosen, .wardrobe, .room, .system, .curveName, .curve, .signal, .contact, .track, .orders, .status, .pages] }

    var title: String {
        switch self {
        case .shop: return "The shop"; case .closet: return "The Closet"; case .archive: return "The archive"; case .curve: return "The Curve"
        case .signal: return "The signal"; case .contact: return "Contact"; case .track: return "Track an order"; case .orders: return "Your orders"
        case .status: return "The site"; case .pages: return "Pages"
        case .world: return "The Collections"; case .wardrobe: return "The Wardrobe"; case .chosen: return "The Chosen"
        case .livingCurves: return "Living Curves"; case .source: return "The source"; case .study: return "The Psyched Study"
        case .curveName: return "You were gifted a seed"; case .system: return "The System"; case .room: return "The Room"; case .journal: return "The Journal"
        }
    }

    var symbol: String {
        switch self {
        case .shop: return "bag"; case .closet: return "hanger"; case .archive: return "square.grid.3x3"; case .curve: return "scribble.variable"
        case .signal: return "antenna.radiowaves.left.and.right"; case .contact: return "envelope"; case .track: return "shippingbox"; case .orders: return "receipt"
        case .status: return "globe"; case .pages: return "doc.text"
        case .world: return "square.grid.2x2"; case .wardrobe: return "tshirt"; case .chosen: return "number"; case .livingCurves: return "scribble"
        case .source: return "chevron.left.forwardslash.chevron.right"; case .study: return "book"; case .curveName: return "signature"
        case .system: return "point.3.connected.trianglepath.dotted"; case .room: return "door.left.hand.open"; case .journal: return "text.book.closed"
        }
    }

    @MainActor @ViewBuilder func view(_ model: AppModel) -> some View {
        switch self {
        case .curve: CurveLiveView()
        case .signal: SignalView()
        case .contact: ContactView()
        case .track: TrackOrderView()
        case .orders: MyOrdersView()
        case .status: SiteStatusView()
        case .pages: SitePagesView()
        case .world: SiteWorldView()
        case .wardrobe: WardrobeView()
        case .chosen: ChosenView()
        case .livingCurves: LivingCurvesView()
        case .source: LivingCurvesSourceView()
        case .study: StudyView()
        case .curveName: CurveNameView()
        case .system: SiteSystemView()
        case .room: SiteRoomView()
        case .journal: SiteReaderView(path: "journal", title: "The Journal", art: .goldLine)
        default: EmptyView()   // the three tabs are not pushed
        }
    }
}

// MARK: - Siri, Shortcuts and the Action button (app target only: they run in the app's process)

@MainActor private func shopReady() async throws -> Void {
    await AppModel.shared.restoreIfNeeded()
    guard Site.base != nil else { throw Site.Problem.notSetUp }
}

struct ShopStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "What's in the Shop"
    static let description: IntentDescription? = "Says how many pieces are in the shop, how many are in stock, and what is new."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await shopReady()
        let store = ShopStore.shared
        await store.load(force: true)
        guard !store.pieces.isEmpty else { return .result(dialog: "The shop's list did not load. Try again in a moment.") }
        let fresh = store.takeNewPieces()
        StorefrontGlanceWriter.publishShop(store: store, fresh: fresh)
        let stocked = store.pieces.filter(\.inStock).count
        var line = "\(store.pieces.count) pieces are in the shop, \(stocked) in stock."
        if !fresh.isEmpty { line += " New since you last looked: " + fresh.prefix(3).map(\.name).joined(separator: ", ") + "." }
        return .result(dialog: "\(line)")
    }
}

/// Opens a Shop room. Also what Spotlight runs when he picks a Shop result.
struct OpenShopRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Shop Room"
    @Parameter(title: "Room") var target: ShopRoomEntity

    init() {}
    init(target: ShopRoomEntity) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "shop", path: [target.id], query: [:])) }
        return .result()
    }
}

struct ShopRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shop Room"
    static let defaultQuery = ShopRoomQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "Shop") }

    static var all: [ShopRoomEntity] { ShopRoom.allCases.map { ShopRoomEntity(id: $0.rawValue, title: $0.title) } }
}

struct ShopRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShopRoomEntity] { ShopRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ShopRoomEntity] { ShopRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ShopRoomEntity] { ShopRoomEntity.all }
}

enum ShopSpotlight {
    /// Every room into Spotlight, in the Shop's own named index (Apple: not the default index).
    static func index() async {
        try? await CSSearchableIndex(name: "shop").indexAppEntities(ShopRoomEntity.all)
    }
}

// MARK: - The widget's numbers

@MainActor enum StorefrontGlanceWriter {
    private static var indexedThisLaunch = false
    private static var indexedCongregation = false

    /// What the Site widget shows, from what the app just read. Keeps the congregation's half when only the shop was read.
    static func publishShop(store: ShopStore, fresh: [ShopPiece]) {
        let before = SharedState.readStorefront()
        SharedState.writeStorefront(StorefrontGlance(pieces: store.pieces.count, inStock: store.pieces.filter(\.inStock).count,
                                                     fresh: fresh.isEmpty ? (before?.fresh ?? []) : fresh.prefix(3).map(\.name),
                                                     held: before?.held, members: before?.members ?? 0, updatedAt: .now))
        if !indexedThisLaunch { indexedThisLaunch = true; Task { await ShopSpotlight.index() } }
    }

    static func publishCongregation(held: Int?, members: Int) {
        let before = SharedState.readStorefront()
        SharedState.writeStorefront(StorefrontGlance(pieces: before?.pieces ?? 0, inStock: before?.inStock ?? 0, fresh: before?.fresh ?? [],
                                                     held: held, members: members, updatedAt: .now))
        if !indexedCongregation { indexedCongregation = true; Task { await CongregationSpotlight.index() } }
    }
}
