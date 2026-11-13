import AppIntents
import CoreSpotlight
import SwiftUI

// Pick's system add-ons (DESIGN.md §6): both rooms in Spotlight, Siri says who leads the vote, deep links to each room,
// a tip for the touch-and-hold, and the widget's numbers (Shared/PickGlance.swift, PLDevWidgets/PickWidget.swift).
// Not fitting: a Live Activity (a vote has no start and end), notification buttons (nothing here ever pushes).

/// Where a link, Spotlight or Siri wants Pick to go.
@MainActor @Observable final class PickNav {
    static let shared = PickNav()
    var room: PickRoom?
}

struct PickRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pick Room"
    static let defaultQuery = PickRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }
    static var all: [PickRoomEntity] { PickRoom.allCases.map { PickRoomEntity(id: $0.rawValue, title: $0.title, line: $0.line) } }
}

struct PickRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PickRoomEntity] { PickRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [PickRoomEntity] { PickRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PickRoomEntity] { PickRoomEntity.all }
}

struct OpenPickRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Pick Room"
    @Parameter(title: "Room") var target: PickRoomEntity
    init() {}
    init(target: PickRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "pick", path: [target.id], query: [:])) }
        return .result()
    }
}

enum PickSpotlight {
    static func index() async { try? await CSSearchableIndex(name: "pick").indexAppEntities(PickRoomEntity.all) }
}

/// "Which colourway is winning?" Reads the vote in the app's process; says the leader and the count.
struct ColourwayLeaderIntent: AppIntent {
    static let title: LocalizedStringResource = "Colourway Vote"
    static let description: IntentDescription? = "Says which colourway leads the vote for the next piece and how many picks there are."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.restoreIfNeeded()
        guard model.http != nil else { return .result(dialog: "PL DEV has no config loaded yet.") }
        let state = PickSection.state
        if state.palettes.isEmpty { await state.load(model: model) } else { await state.loadTally(model: model) }
        guard let lead = state.ranked.first, state.totalVotes > 0 else {
            return .result(dialog: "No picks yet. \(state.palettes.count) colourways are waiting for the first one.")
        }
        let n = state.totalVotes
        return .result(dialog: "\(lead.name) leads with \(state.votes(lead)) of \(n) \(n == 1 ? "pick" : "picks").")
    }
}
