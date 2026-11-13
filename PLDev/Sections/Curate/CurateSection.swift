import AppIntents
import CoreSpotlight
import SwiftUI
import UserNotifications

/// Curate: one card at a time; right = keep, left = cut, up = maybe, star = favourite (a keep with the note "fav").
/// Every deck of the web picker is here (CurateMode), dealt by PLDevCore's CurateQueue (the web's rules) or built as the web builds
/// it (categories, tags). Marks go to the gallery's /api/taste, the same store the web deck, the Library and the R1 write; offline a
/// mark waits in the outbox. A failed marks load deals no deck; a failed save is counted on screen.
@MainActor enum CurateSection: PLSection {
    static let manifest = SectionManifest(id: "curate", title: "Curate", symbol: "rectangle.stack", needsKeys: ["vault"], needsOrigins: ["gallery"])
    static let state = CurateModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(CurateView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? {
        AnyView(Group {
            CurateSettingsRows()
            Button { Task { await CurateSpotlight.index() } } label: {
                SettingsLabel("Add the Curate decks to Spotlight again", "magnifyingglass", Color(uiColor: .systemGray))
            }
        })
    }
    /// Nothing arrives for Curate: a pass is something he starts, so there is no notification to give a button to (gap check).
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let m = path.first.flatMap(CurateMode.parse) { state.mode = m; state.linkTick += 1 }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh {
        await CurateSpotlight.index()
        return SectionRefresh(badge: nil, notify: [])
    }
}

/// Settings > Curate: the sound choice for clips and whether the deck opens on the last deck (the web resets to Unmarked).
struct CurateSettingsRows: View {
    @AppStorage("pl-curate-sound") private var sound = false
    @AppStorage("curate.rememberDeck") private var remember = true
    var body: some View {
        Toggle(isOn: $sound) { SettingsLabel("Curate clips play with sound", "speaker.wave.2", Color(hex: 0xc9a84c)) }
        Toggle(isOn: $remember) { SettingsLabel("Open Curate on the last deck", "rectangle.stack", Color(hex: 0xc9a84c)) }
    }
}

// MARK: the favourites viewer (web /library?v=fav)

/// Every favourite he has starred, newest first, each with its comment box: the words he leaves for taste learning.
struct CurateFavourites: View {
    let model: AppModel
    let state: CurateModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var favs: [LibraryItem] { LibraryData.shared.items.filter { LibraryData.shared.marks[$0.vault_id]?.isFav == true }.reversed() }

    var body: some View {
        NavigationStack {
            Group {
                if favs.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "star", description: Text("Star a keep in the deck and it appears here with room for your words."))
                } else {
                    List(favs) { it in FavouriteRow(model: model, item: it) }
                        .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .background { GalleryGround() }
            .navigationTitle("Favourites").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(PLG.gold)
    }
}

private struct FavouriteRow: View {
    let model: AppModel
    let item: LibraryItem
    @State private var text = ""
    @State private var saved = ""
    @State private var state = ""
    @FocusState private var focus: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let m = LibraryData.shared.media(item, model: model)
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: m.still) { $0.resizable().scaledToFit() } placeholder: { PLC.bone }
                .frame(width: 96, height: 120).background(PLC.bone).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.class == "seed" ? (item.origin ?? "seed") : (item.name ?? item.item_id)).gTitle(17).foregroundStyle(PLG.ink(scheme)).lineLimit(2)
                Text(item.item_id).gEyebrow(9).foregroundStyle(PLG.dim(scheme))
                TextField("A word about this piece", text: $text, axis: .vertical).lineLimit(1...4).focused($focus)
                    .padding(10).background(PLG.surface(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PLG.line(scheme), lineWidth: 0.8) }
                    .onChange(of: focus) { _, f in if !f { Task { await save() } } }
                if !state.isEmpty { Text(state).gEyebrow(9).foregroundStyle(state.hasPrefix("NOT") ? PLG.red : PLG.dim(scheme)) }
            }
        }
        .listRowBackground(Color.clear).listRowSeparatorTint(PLG.line(scheme))
        .onAppear { let c = LibraryData.shared.marks[item.vault_id]?.comment ?? ""; text = c; saved = c }
    }

    private func save() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != saved else { return }
        state = "saving…"
        if await LibraryData.shared.post(["only": "comment", "id": item.vault_id, "comment": String(t.prefix(1000))], model: model) {
            saved = t; state = "saved ✓"; LibraryData.shared.marks[item.vault_id, default: TasteMark(v: "")].comment = t
        } else { state = "NOT SAVED: tap the box and tap away to retry" }
    }
}

// MARK: Siri, Shortcuts, Spotlight (DESIGN.md §6)

/// A Curate deck as Siri and Spotlight know it.
struct CurateDeckEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Curate Deck"
    static let defaultQuery = CurateDeckQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    static var all: [CurateDeckEntity] {
        CurateMode.groups.flatMap(\.1).filter { $0.kind != .unseen && $0.kind != .all }.map { CurateDeckEntity(id: $0.id, title: $0.title) }
    }
}

struct CurateDeckQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CurateDeckEntity] { CurateDeckEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [CurateDeckEntity] { CurateDeckEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [CurateDeckEntity] { CurateDeckEntity.all }
}

/// "Open the cloud batches in Curate": lands on the deck by name.
struct OpenCurateDeckIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Curate Deck"
    @Parameter(title: "Deck") var target: CurateDeckEntity
    init() {}
    init(target: CurateDeckEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "curate", path: [target.id], query: [:])) }
        return .result()
    }
}

/// "How many cards wait in the new deck?": deals the deck in the app's process and says the count.
struct CurateDeckCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Cards Waiting in a Curate Deck"
    static let description: IntentDescription? = "Says how many cards a Curate deck holds right now."
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Deck") var target: CurateDeckEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.restoreIfNeeded()
        guard model.http != nil else { return .result(dialog: "PL DEV has no config loaded yet.") }
        try await LibraryData.shared.load(model: model)
        guard let m = CurateMode.parse(target.id), let deck = m.deck else { return .result(dialog: "That deck is dealt in the app. Open it to see its count.") }
        let n = CurateQueue.build(deck, items: LibraryData.shared.items, marks: LibraryData.shared.marks, cls: m.cls).count
        return .result(dialog: "\(n.formatted()) cards wait in \(target.title).")
    }
}

enum CurateSpotlight {
    static func index() async { try? await CSSearchableIndex(name: "curate").indexAppEntities(CurateDeckEntity.all) }
}
