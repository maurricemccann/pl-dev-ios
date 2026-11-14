import AppIntents
import CoreSpotlight
import SwiftUI

// Capture's system add-ons (DESIGN.md §6). Widget: Shared/CaptureGlance.swift + PLDevWidgets/CaptureWidget.swift.
// Siri and Shortcuts: capture a thought by voice, hear what waits on him, hear where the last capture went.
// Spotlight: the three rooms and the four ways in. Deep links: pldev://section/capture/<add|trail|waiting>?mode=<artwork|text|quote|link>.
// Not fitting: a Live Activity (a capture sends in about a second; the badge and the Waiting room show anything left over) and
// notification buttons (Capture never pushes; a notice with a button that changes things belongs to House's drafts).

// MARK: - Rooms and ways in, by name

struct CaptureRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Room"
    static let defaultQuery = CaptureRoomQuery()
    let id: String
    let title: String
    let line: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(line)") }

    static var all: [CaptureRoomEntity] {
        var out = CaptureRoom.allCases.map { CaptureRoomEntity(id: $0.rawValue, title: $0.title, line: $0.line) }
        for k in CaptureKind.allCases {
            let title: String
            switch k {
            case .artwork: title = "Capture artwork"; case .text: title = "Capture a note"
            case .quote: title = "Capture a quote"; case .link: title = "Capture a link"
            }
            out.append(CaptureRoomEntity(id: "add:\(k.rawValue)", title: title, line: k.sub))
        }
        return out
    }
}

struct CaptureRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CaptureRoomEntity] { CaptureRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [CaptureRoomEntity] { CaptureRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [CaptureRoomEntity] { CaptureRoomEntity.all }
}

struct OpenCaptureRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Capture Room"
    @Parameter(title: "Room") var target: CaptureRoomEntity
    init() {}
    init(target: CaptureRoomEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        let parts = target.id.split(separator: ":").map(String.init)
        let query = parts.count > 1 ? ["mode": parts[1]] : [:]
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "capture", path: [parts.first ?? "add"], query: query)) }
        return .result()
    }
}

enum CaptureSpotlight {
    static func index() async { try? await CSSearchableIndex(name: "capture").indexAppEntities(CaptureRoomEntity.all) }
}

// MARK: - Siri, Shortcuts and the Action button (app target, so they run in the app's process with its keys)

@MainActor private func readyCaptureModel() async throws -> AppModel {
    let m = AppModel.shared
    await m.restoreIfNeeded()
    guard m.http != nil else { throw Console.Problem.notSetUp }
    return m
}

/// "Capture a thought": the words by voice or typed, into the intake. Nothing is posted anywhere, so it asks nothing back.
struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Thought"
    static let description: IntentDescription? = "Saves a thought, a quote or a link into the intake. Nothing is posted anywhere."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Words", requestValueDialog: "What do you want to capture?") var words: String

    init() {}
    init(words: String) { self.words = words }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await readyCaptureModel()
        let t = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .result(dialog: "There was nothing to capture.") }
        let isLink = URL(string: t).map { ($0.scheme == "https" || $0.scheme == "http") && !t.contains(" ") } ?? false
        let sent = await CaptureSection.state.enqueue(kind: isLink ? "url" : "text", text: t, note: nil, file: nil,
                                                      label: String(t.prefix(120)), toBoard: false, model: model)
        let line = sent ? "Captured. It is in your intake." : "Saved on this phone. It goes in when the house answers."
        return .result(dialog: "\(line)")
    }
}

/// "What is waiting on me": every count, spoken.
struct WaitingOnMeIntent: AppIntent {
    static let title: LocalizedStringResource = "What Is Waiting on Me"
    static let description: IntentDescription? = "Says what waits on you across the house: drafts, Pins, tasks, the shift, captures, and anything still on this phone."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let model = try await readyCaptureModel()
        await CaptureSection.state.loadWaiting(model: model)
        await model.drainInbox()
        guard let w = CaptureSection.state.waiting else { return .result(dialog: "The house did not answer. Try again in a moment.", view: AppleCard(title: "Waiting on you", rows: [("The house", "did not answer")])) }
        func part(_ n: Int?, _ one: String, _ many: String) -> String? {
            guard let n, n > 0 else { return nil }
            return "\(n) \(n == 1 ? one : many)"
        }
        let parts = [part(w.drafts, "draft", "drafts"), part(w.pins, "Pin", "Pins"), part(w.manual, "manual post", "manual posts"), part(w.ads, "ad", "ads"),
                     part(w.emails, "email", "emails"), part(w.tasks, "task", "tasks"), part(w.captures, "new capture", "new captures"),
                     part(w.shift_open, "open shift item", "open shift items")].compactMap { $0 }
        var line = parts.isEmpty ? "Nothing is waiting on you." : parts.joined(separator: ", ") + " waiting on you."
        if model.inboxCount > 0 { line += " \(model.inboxCount) \(model.inboxCount == 1 ? "capture is" : "captures are") still on this phone to send." }
        var rows: [(String, String)] = [("Drafts", "\(w.drafts ?? 0)"), ("Pins", "\(w.pins ?? 0)"), ("Tasks", "\(w.tasks ?? 0)"), ("New captures", "\(w.captures ?? 0)")]
        if model.inboxCount > 0 { rows.append(("Still on this phone", "\(model.inboxCount)")) }
        return .result(dialog: "\(line)", view: AppleCard(title: "Waiting on you", rows: rows))
    }
}

/// "Where did my last capture go": the newest row of the trail, in words.
struct LastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Where Did My Last Capture Go"
    static let description: IntentDescription? = "Says what became of the most recent capture."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await readyCaptureModel()
        await CaptureSection.state.loadTrail(model: model)
        if let g = CaptureSection.state.ghosts.first {
            let line = g.sent ? "\"\(g.label)\" is on its way to the intake." : "\"\(g.label)\" is still on this phone. It goes in when the house answers."
            return .result(dialog: "\(line)")
        }
        guard let r = CaptureSection.state.trail.first else { return .result(dialog: "Nothing has been captured yet.") }
        let s = r.state
        return .result(dialog: "\"\(String(r.label.prefix(80)))\" is \(s.label.lowercased()). \(s.detail)")
    }
}
