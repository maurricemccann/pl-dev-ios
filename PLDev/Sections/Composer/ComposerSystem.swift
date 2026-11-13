import AppIntents
import CoreSpotlight
import SwiftUI

// Composer's system add-ons (DESIGN.md §6): every room and every piece in Spotlight, Siri says the board and the open piece, deep links
// land on any room or piece, a tip names the touch-and-hold, the widget carries the board's numbers (Shared/ComposerGlance.swift,
// PLDevWidgets/ComposerWidget.swift), and a render can be followed on the Lock Screen (RenderLive, a Live Activity started on his tap).
// Not fitting: notification buttons (a card moving lane asks nothing of him but to open /curate, and an "Open" button is not a real action).

struct ComposerRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Composer Room"
    static let defaultQuery = ComposerRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }
    static var all: [ComposerRoomEntity] { ComposerRoom.allCases.map { ComposerRoomEntity(id: $0.rawValue, title: $0.title, line: $0.line) } }
}

struct ComposerRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ComposerRoomEntity] { ComposerRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ComposerRoomEntity] { ComposerRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ComposerRoomEntity] { ComposerRoomEntity.all }
}

struct OpenComposerRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Composer Room"
    @Parameter(title: "Room") var target: ComposerRoomEntity
    init() {}
    init(target: ComposerRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "composer", path: [target.id], query: [:])) }
        return .result()
    }
}

/// A piece, by name.
struct ComposerPieceEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Composer Piece"
    static let defaultQuery = ComposerPieceQuery()
    let id: String
    let name: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(line)") }
    @MainActor static var all: [ComposerPieceEntity] {
        ComposerPieces.shared.entries.map { ComposerPieceEntity(id: $0.id, name: $0.piece.piece, line: "\($0.piece.shots.count) shots · \(String(format: "%.1f", $0.piece.duration)) s") }
    }
}

struct ComposerPieceQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [ComposerPieceEntity] { ComposerPieceEntity.all.filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [ComposerPieceEntity] { ComposerPieceEntity.all.filter { $0.name.localizedCaseInsensitiveContains(string) } }
    @MainActor func suggestedEntities() async throws -> [ComposerPieceEntity] { ComposerPieceEntity.all }
}

struct OpenComposerPieceIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Composer Piece"
    @Parameter(title: "Piece") var target: ComposerPieceEntity
    init() {}
    init(target: ComposerPieceEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "composer", path: ["piece", target.id], query: [:])) }
        return .result()
    }
}

enum ComposerSpotlight {
    /// Call at launch and after the pieces change (the lead wires it next to the other Spotlight calls).
    @MainActor static func index() async {
        let idx = CSSearchableIndex(name: "composer")
        try? await idx.indexAppEntities(ComposerRoomEntity.all)
        try? await idx.indexAppEntities(ComposerPieceEntity.all)
    }
}

/// "How are the renders going?" Reads the board in the app's process and says every count.
struct RenderBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Render Board"
    static let description: IntentDescription? = "Says how many renders are sent, rendering, mixing, filed and failed on the Composer board."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.restoreIfNeeded()
        guard model.http != nil else { return .result(dialog: "PL DEV has no config loaded yet.") }
        let s = ComposerSection.state
        await s.load(model: model)
        if s.failed && s.cards.isEmpty { return .result(dialog: "I could not read the render board just now.") }
        if s.cards.isEmpty { return .result(dialog: "The board is empty. Nothing has been sent to render.") }
        let parts = [("sent", s.count("sent")), ("rendering", s.count("rendering")), ("mixing", s.count("mixing")), ("filed", s.count("filed")), ("ruled", s.count("ruled")), ("failed", s.count("failed"))]
            .filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
        return .result(dialog: "\(s.cards.count) \(s.cards.count == 1 ? "card" : "cards") on the board: \(parts.joined(separator: ", ")).")
    }
}

/// "What am I composing?" The open piece: its name, shots, length, and how many shots still have no sources.
struct OpenPieceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Piece Status"
    static let description: IntentDescription? = "Says the piece you have open in Composer: its shots, its length, and the shots with no sources."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let p = ComposerPieces.shared.piece
        if p.shots.isEmpty { return .result(dialog: "\(p.piece) has no shots yet.") }
        let bare = p.shots.filter { $0.sourceIds.isEmpty }.count
        let tail = bare == 0 ? "Every shot has its sources." : "\(bare) \(bare == 1 ? "shot has" : "shots have") no sources and would render black."
        return .result(dialog: "\(p.piece) has \(p.shots.count) \(p.shots.count == 1 ? "shot" : "shots") and runs \(String(format: "%.1f", p.duration)) seconds at \(p.resolution), \(p.fps) frames. \(tail)")
    }
}
