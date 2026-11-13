import AppIntents
import CoreSpotlight
import SwiftUI

// MARK: - Spotlight and Siri: each world is its own room

struct WorldRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "World"
    static let defaultQuery = WorldRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }
    static var all: [WorldRoomEntity] { WorldRoom.allCases.map { WorldRoomEntity(id: $0.rawValue, title: $0.title, line: $0.line) } }
}

struct WorldRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WorldRoomEntity] { WorldRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [WorldRoomEntity] { WorldRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [WorldRoomEntity] { WorldRoomEntity.all }
}

struct OpenWorldIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a World"
    @Parameter(title: "World") var target: WorldRoomEntity
    init() {}
    init(target: WorldRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "library", path: ["worlds", target.id], query: [:])) }
        return .result()
    }
}

enum WorldsSpotlight {
    static func index() async { try? await CSSearchableIndex(name: "worlds").indexAppEntities(WorldRoomEntity.all) }
}
