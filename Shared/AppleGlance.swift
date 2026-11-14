import AppIntents
import Foundation
import WidgetKit

// The apple lane (11-13): what the interactive widget shows, and the queue its buttons write into.
// A widget holds no key and never uses the network, so a button only writes a line to the queue in the App Group;
// the app (which holds the keys) reads the queue on its next refresh and sends it. Counts and words only.

/// What the interactive widget shows: the draft on top, the Curate card on top, the next habit.
struct AppleGlance: Codable, Equatable, Sendable {
    var draftCount = 0
    var draftID: String?
    var draftPlatform: String?
    var draftCaption: String?
    var curateID: String?
    var curateLabel: String?
    var habitID: String?
    var habitLabel: String?
    var habitsLeft = 0
    var queued = 0                  // button taps waiting for the app to send
    var updatedAt = Date()
}

extension PLDevKinds {
    static let appleWidget = "com.psychedluxuries.dev.apple.actions"
}

extension SharedState {
    static func writeApple(_ g: AppleGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readApple()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "apple")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.appleWidget) }
    }

    static func readApple() -> AppleGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "apple") else { return nil }
        return try? JSONDecoder().decode(AppleGlance.self, from: data)
    }
}

/// One button tap: what to do and to which item. `kind` is draft.approve, draft.hold, curate.keep, curate.cut or practice.tick.
struct AppleAction: Codable, Equatable, Sendable, Identifiable {
    var id = UUID().uuidString
    var kind: String
    var target: String
    var at = Date()
}

enum AppleActionQueue {
    /// Set by the app: when a button's intent runs inside the app's own process, the queue is sent at once instead of at the next refresh.
    nonisolated(unsafe) static var onAdd: (@Sendable () -> Void)?

    private static var store: UserDefaults? {
        guard let id = SharedState.groupID else { return nil }
        return UserDefaults(suiteName: id)
    }

    static func all() -> [AppleAction] {
        guard let data = store?.data(forKey: "appleQueue") else { return [] }
        return (try? JSONDecoder().decode([AppleAction].self, from: data)) ?? []
    }

    private static func save(_ list: [AppleAction]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        store?.set(data, forKey: "appleQueue")
    }

    static func add(kind: String, target: String) {
        var list = all()
        if list.contains(where: { $0.kind == kind && $0.target == target }) { return }   // a double tap is one action
        list.append(AppleAction(kind: kind, target: target))
        save(Array(list.suffix(40)))
        var g = SharedState.readApple() ?? AppleGlance()
        g.queued = list.count
        if kind.hasPrefix("draft."), g.draftID == target { g.draftID = nil; g.draftCaption = nil; g.draftPlatform = nil; g.draftCount = max(0, g.draftCount - 1) }
        if kind.hasPrefix("curate."), g.curateID == target { g.curateID = nil; g.curateLabel = nil }
        if kind == "practice.tick", g.habitID == target { g.habitID = nil; g.habitLabel = nil; g.habitsLeft = max(0, g.habitsLeft - 1) }
        SharedState.writeApple(g)
        onAdd?()
    }

    /// The app takes everything at once; what it could not send it adds back.
    static func take() -> [AppleAction] {
        let list = all()
        save([])
        return list
    }
}

// MARK: the widget's buttons (an intent per decision; Face ID guards the ones that change the queue of posts)

struct ApproveDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Approve the Draft on Top"
    static let description: IntentDescription? = "Approves the draft the widget shows. Face ID first. The app sends it at its next refresh."
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Draft") var draft: String
    init() {}
    init(draft: String) { self.draft = draft }

    func perform() async throws -> some IntentResult {
        AppleActionQueue.add(kind: "draft.approve", target: draft)
        return .result()
    }
}

struct HoldDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Hold the Draft on Top"
    static let description: IntentDescription? = "Holds the draft the widget shows, so it does not post. The app sends it at its next refresh."
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Draft") var draft: String
    init() {}
    init(draft: String) { self.draft = draft }

    func perform() async throws -> some IntentResult {
        AppleActionQueue.add(kind: "draft.hold", target: draft)
        return .result()
    }
}

struct MarkCurateCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep or Cut the Curate Card"
    static let description: IntentDescription? = "Marks the Curate card the widget shows as a keep or a cut. The app sends it at its next refresh."

    @Parameter(title: "Card") var card: String
    @Parameter(title: "Verdict") var verdict: String   // "keep" or "cut"
    init() {}
    init(card: String, verdict: String) { self.card = card; self.verdict = verdict }

    func perform() async throws -> some IntentResult {
        AppleActionQueue.add(kind: verdict == "cut" ? "curate.cut" : "curate.keep", target: card)
        return .result()
    }
}

struct TickHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick the Habit"
    static let description: IntentDescription? = "Ticks the next habit the widget shows. The app sends it at its next refresh."

    @Parameter(title: "Habit") var habit: String
    init() {}
    init(habit: String) { self.habit = habit }

    func perform() async throws -> some IntentResult {
        AppleActionQueue.add(kind: "practice.tick", target: habit)
        return .result()
    }
}
