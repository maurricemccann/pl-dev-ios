import AppIntents
import CoreSpotlight
import SwiftUI

// PL Paint's system add-ons for the canvas (DESIGN.md §6). Widget: the Daily Mark (Shared + PLDevWidgets, already there).
// Siri and Shortcuts: open the canvas, and hear the Daily Mark. Spotlight: the rooms of the canvas, by name. Deep links:
// pldev://section/paint/canvas, and pldev://section/paint/canvas/<works|brushes|colour|layers|timelapse|study|lift|adjust|tools|sync|settings|handbook>.
// Not fitting: a Live Activity (a video is written in seconds and the share sheet takes it from there) and notification buttons (Paint never pushes).

// MARK: - Rooms of the canvas, by name

enum PaintRoom: String, CaseIterable {
    case canvas, works, brushes, colour, layers, timelapse, study, lift, adjust, tools, sync, settings, handbook
    var title: String {
        switch self {
        case .canvas: "Open the canvas"; case .works: "Works"; case .brushes: "Brushes"; case .colour: "Colour"; case .layers: "Layers"
        case .timelapse: "Timelapse"; case .study: "Study"; case .lift: "Lift ink from a photo"; case .adjust: "Adjustments and effects"
        case .tools: "More tools"; case .sync: "Sync with the laptop"; case .settings: "PL Paint settings"; case .handbook: "PL Paint handbook"
        }
    }
    var line: String {
        switch self {
        case .canvas: "Back to the picture you were painting"; case .works: "Your works on this phone and the laptop's"; case .brushes: "His packs and your own"
        case .colour: "The colour card, colourways and palettes"; case .layers: "Layers, groups and masks"; case .timelapse: "Replay, colour passes, the alive loop"
        case .study: "Record how you draw"; case .lift: "Ink off a photo of a physical piece"; case .adjust: "Hue, curves, blur, bloom and more"
        case .tools: "Facet, Echo Fill, nodes, lights, seams, hand trace"; case .sync: "Both ways with the laptop"; case .settings: "Finger, palm guard, Pencil buttons"
        case .handbook: "Everything the app does, in order"
        }
    }
    var panel: NativePanel? {
        switch self {
        case .canvas: nil; case .works: .works; case .brushes: .brushes; case .colour: .colour; case .layers: .layers; case .timelapse: .timelapse
        case .study: .study; case .lift: .lift; case .adjust: .adjust; case .tools: .tools2; case .sync: .sync; case .settings: .settings; case .handbook: .handbook
        }
    }
}

struct PaintRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PL Paint Room"
    static let defaultQuery = PaintRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }
    static var all: [PaintRoomEntity] { PaintRoom.allCases.map { PaintRoomEntity(id: $0.rawValue, title: $0.title, line: $0.line) } }
}

struct PaintRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PaintRoomEntity] { PaintRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [PaintRoomEntity] { PaintRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PaintRoomEntity] { PaintRoomEntity.all }
}

struct OpenPaintRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a PL Paint Room"
    @Parameter(title: "Room") var target: PaintRoomEntity
    init() {}
    init(target: PaintRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "paint", path: ["canvas", target.id], query: [:])) }
        return .result()
    }
}

enum PaintSpotlight {
    static func index() async { try? await CSSearchableIndex(name: "paint").indexAppEntities(PaintRoomEntity.all) }
}

// MARK: - Siri, Shortcuts and the Action button

/// "Open PL Paint's canvas": straight to the picture he was painting.
struct OpenPaintCanvasIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PL Paint's Canvas"
    static let description: IntentDescription? = "Opens the canvas on the picture you were painting."
    static let supportedModes: IntentModes = .foreground
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "paint", path: ["canvas"], query: [:])) }
        return .result()
    }
}

/// "How is my Daily Mark": the streak and today's strokes, spoken.
struct PaintDailyMarkIntent: AppIntent {
    static let title: LocalizedStringResource = "How Is My Daily Mark"
    static let description: IntentDescription? = "Says your Daily Mark streak and how many strokes you have drawn today."
    static let supportedModes: IntentModes = .background
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let streak = NativeDaily.streak, today = NativeDaily.days[NativeDaily.key()] ?? 0
        let s = streak == 0 ? "No streak yet." : "Your Daily Mark streak is \(streak) \(streak == 1 ? "day" : "days")."
        let t = today == 0 ? "Nothing drawn yet today." : "\(today) \(today == 1 ? "stroke" : "strokes") today."
        return .result(dialog: "\(s) \(t)")
    }
}

// MARK: - Tips (only for what cannot be seen)

