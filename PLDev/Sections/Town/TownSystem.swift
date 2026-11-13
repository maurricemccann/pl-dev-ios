import AppIntents
import CoreSpotlight
import SwiftUI
import TipKit

// Task Town's system add-ons (DESIGN.md §6): every mode and every building is a room Spotlight and Siri can open, Siri can say what the
// session is doing and what waits, a widget carries the counts, a tip names the one thing that cannot be seen, and a deep link lands on any room.

/// A place in the town: one of the three towns (Tasks, Live, Lore) or a building (`pldev://section/town/studio`).
enum TownRoom: Hashable {
    case mode(TownMode)
    case building(String)

    init?(id: String) {
        if let m = TownMode.allCases.first(where: { $0.rawValue.lowercased() == id.lowercased() }) { self = .mode(m) }
        else if TownStreet.building(id.lowercased()) != nil { self = .building(id.lowercased()) }
        else { return nil }
    }

    var id: String {
        switch self { case .mode(let m): return m.rawValue.lowercased(); case .building(let b): return b }
    }

    var title: String {
        switch self {
        case .mode(let m): return "Town: \(m.rawValue)"
        case .building(let b): return "Town: " + (TownStreet.building(b)?.label.capitalized ?? b)
        }
    }

    var line: String {
        switch self {
        case .mode(.tasks): return "The Roadmap as townspeople"
        case .mode(.live): return "Only the session, walking to each call"
        case .mode(.lore): return "The house's mistakes, one person each"
        case .building(let b): return TownStreet.building(b)?.note ?? ""
        }
    }

    static var all: [TownRoom] { TownMode.allCases.map { .mode($0) } + TownStreet.buildings.map { .building($0.id) } }
}

struct TownRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task Town Room"
    static let defaultQuery = TownRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }
    static var all: [TownRoomEntity] { TownRoom.all.map { TownRoomEntity(id: $0.id, title: $0.title, line: $0.line) } }
}

struct TownRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TownRoomEntity] { TownRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [TownRoomEntity] { TownRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [TownRoomEntity] { TownRoomEntity.all }
}

/// Opens a room of the town. Also what Spotlight runs when he picks a Task Town result.
struct OpenTownRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Task Town Room"
    @Parameter(title: "Room") var target: TownRoomEntity
    init() {}
    init(target: TownRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "town", path: [target.id], query: [:])) }
        return .result()
    }
}

enum TownSpotlight {
    /// Every room into Spotlight, once per launch, in Task Town's own named index.
    static func index() async { try? await CSSearchableIndex(name: "town").indexAppEntities(TownRoomEntity.all) }
}

/// "What is the session doing in Task Town?" Reads the live feed in the app's process and says every count.
struct TownStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "What the Session Is Doing"
    static let description: IntentDescription? = "Says where the session is working, and how many tasks are open, done, waiting on you, blocked and stale."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.restoreIfNeeded()
        guard let http = model.http else { return .result(dialog: "PL DEV has no config loaded yet.") }
        let f = try JSONDecoder().decode(TownFeed.self, from: try await http.send(RequestPlan(origin: "gallery", path: "api/town")))
        TownGlanceWriter.publish(f)
        let g = SharedState.readTown()
        let who = g?.working == true ? "The session is working at the \((g?.at ?? "street").capitalized), call \(g?.calls ?? 0)." : "The session is quiet."
        return .result(dialog: "\(who) \(g?.open ?? 0) tasks are open and \(g?.done ?? 0) are done. \(g?.his ?? 0) wait on you, \(g?.blocked ?? 0) are blocked and \(g?.stale ?? 0) are stale.")
    }
}

/// The widget's numbers, from the feed.
@MainActor enum TownGlanceWriter {
    static func publish(_ f: TownFeed) {
        let tasks = f.tasks ?? []
        let open = tasks.filter { $0.state != "done" }
        let live = (f.live?.age_s ?? 999) < 90 ? f.live : nil
        SharedState.writeTown(TownGlance(open: open.count,
                                         done: tasks.count - open.count,
                                         his: open.filter { $0.state == "his" }.count,
                                         blocked: open.filter { $0.state == "blocked" }.count,
                                         stale: open.filter { ($0.age_days ?? 0) >= 7 }.count,
                                         working: f.working == true,
                                         at: live.flatMap { TownStreet.target(area: $0.area, kind: $0.kind)?.label },
                                         calls: f.live?.calls,
                                         updatedAt: .now))
    }
}

struct TownDragTip: Tip {
    var title: Text { Text("Walk the street") }
    var message: Text? { Text("Drag the town sideways to walk it. Tap anyone to hear what they are on, and tap a building to read it. Touch the mini-map to jump.") }
    var image: Image? { Image(systemName: "hand.draw") }
}
