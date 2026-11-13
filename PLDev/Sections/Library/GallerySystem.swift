import AppIntents
import CoreSpotlight
import SwiftUI
import WidgetKit

// The Curve Library's system add-ons (DESIGN.md §6): every room in Spotlight, Siri can say what waits in Curate,
// a widget with the curate queue and the newest batch, a tip for the swipes, deep links to any room.

/// Where a link, Spotlight or Siri wants the Library to go.
@MainActor @Observable final class GalleryNav {
    static let shared = GalleryNav()
    var room: GalleryRoom?
}

struct GalleryRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Curve Library Room"
    static let defaultQuery = GalleryRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }
    static var all: [GalleryRoomEntity] { GalleryRoom.allCases.map { GalleryRoomEntity(id: $0.rawValue, title: $0.title, line: $0.line) } }
}

struct GalleryRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GalleryRoomEntity] { GalleryRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [GalleryRoomEntity] { GalleryRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [GalleryRoomEntity] { GalleryRoomEntity.all }
}

struct OpenGalleryRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Curve Library Room"
    @Parameter(title: "Room") var target: GalleryRoomEntity
    init() {}
    init(target: GalleryRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "library", path: [target.id], query: [:])) }
        return .result()
    }
}

enum GallerySpotlight {
    static func index() async { try? await CSSearchableIndex(name: "gallery").indexAppEntities(GalleryRoomEntity.all) }
}

/// "How many pieces wait in Curate?" Reads the index and the marks in the app's process; says the count and the newest batch.
struct CurateWaitingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pieces Waiting in Curate"
    static let description: IntentDescription? = "Says how many pieces have no mark yet and what the newest batch holds."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.restoreIfNeeded()
        guard model.http != nil else { return .result(dialog: "PL DEV has no config loaded yet.") }
        let data = LibraryData.shared
        try await data.load(model: model)
        LibraryGlanceWriter.publish(data)
        let g = SharedState.readLibrary()
        return .result(dialog: "\(g?.unmarked ?? 0) pieces wait in Curate. The newest batch, \(g?.batch ?? "none"), has \(g?.batchNew ?? 0) unmarked.")
    }
}

/// The widget's numbers, from the loaded index and marks.
@MainActor enum LibraryGlanceWriter {
    static func publish(_ d: LibraryData) {
        guard d.marksLoaded, !d.items.isEmpty else { return }
        let pool = d.items.filter { $0.class != "archive-work" && !$0.tagList.contains("unrenderable") }
        let newest = pool.compactMap(\.batch).max()
        SharedState.writeLibrary(LibraryGlance(unmarked: pool.filter { d.marks[$0.vault_id] == nil }.count,
                                               kept: pool.filter { d.marks[$0.vault_id]?.v == "keep" }.count,
                                               batch: newest,
                                               batchNew: pool.filter { $0.batch == newest && d.marks[$0.vault_id] == nil }.count,
                                               updatedAt: .now))
    }
}
