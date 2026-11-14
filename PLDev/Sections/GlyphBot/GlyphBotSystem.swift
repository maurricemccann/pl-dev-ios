import ActivityKit
import AppIntents
import CoreSpotlight
import SwiftUI

// GlyphBot's system add-ons, built the way House's are (DESIGN.md section 6): a sitting as a Live Activity, Siri and Shortcuts
// that say every count, Spotlight rooms and a deep link to each. No notification: GlyphBot never speaks first.

// MARK: - The sitting Live Activity

@MainActor enum SittingLive {
    nonisolated static var running: Activity<SittingAttributes>? { Activity<SittingAttributes>.activities.first }

    /// Started only from the foreground, by his tap on Begin; ends the moment the sitting ends.
    static func start(mode: String, started: Date) {
        guard running == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: SittingAttributes(mode: mode, started: started),
                                  content: .init(state: .init(answers: 0, seat: "GlyphBot"), staleDate: started.addingTimeInterval(4 * 3600), relevanceScore: 70))
    }

    /// Updated only when an answer lands.
    nonisolated static func update(answers: Int, seat: String) async {
        guard let a = running, a.content.state.answers != answers || a.content.state.seat != seat else { return }
        await a.update(.init(state: .init(answers: answers, seat: seat), staleDate: .now.addingTimeInterval(4 * 3600), relevanceScore: 70))
    }

    nonisolated static func stop() async {
        for a in Activity<SittingAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }
}

// MARK: - Siri, Shortcuts and the Action button (app target only, so they run in the app's process)

@MainActor private func glyphModel() async throws -> AppModel {
    let m = AppModel.shared
    await m.restoreIfNeeded()
    guard m.http != nil else { throw Console.Problem.notSetUp }
    return m
}

struct AskGlyphBotIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask GlyphBot"
    static let description: IntentDescription? = "Asks the Oracle a question and says its answer. Offline, it answers from memory."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask?") var question: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .result(dialog: "Nothing was asked. The question was empty.") }
        let store = GlyphBotStore.shared
        var turn = GlyphTurn(id: UUID().uuidString, question: q, answer: "", via: "", passages: [], askedAt: ISO8601DateFormatter().string(from: .now), synced: false)
        store.save(turn)
        let m = try? await glyphModel()
        if let m, GlyphBotNet.shared.online, let r = try? await GlyphBot.ask(q, model: m), !r.answer.isEmpty {
            turn.answer = r.answer; turn.via = r.via; turn.passages = r.passages
        } else {
            let hit = store.cached(for: q)
            if hit == nil, let local = await PLIntelligence.glyphAnswer(question: q, turns: store.turns) {   // apple lane
                turn.answer = local; turn.via = "on-device · offline"
            } else {
                turn.answer = hit?.answer ?? GlyphDoctrine.pick(q)
                turn.via = hit == nil ? "doctrine · offline" : "cached · offline"
            }
        }
        store.save(turn)
        if let m { await store.flush(model: m) }
        return .result(dialog: "\(turn.answer)")
    }
}

struct GlyphBotStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How Far Is the Interview"
    static let description: IntentDescription? = "Says how many bank questions have been asked, how many answers are on the record and which domain is thinnest."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = try await glyphModel()
        guard GlyphBot.interviewReady(m) else { return .result(dialog: "The interviewer key is not in your config yet.") }
        let s = try await GlyphBot.state(model: m)
        GlyphBotSection.state.interview = s; GlyphBotSection.state.publish()
        let cov = s.coverage ?? [:]
        let thin = GlyphBot.domains.min { (cov[$0] ?? 0) < (cov[$1] ?? 0) }
        var line = "\(s.bank?.asked ?? 0) of \(s.bank?.total ?? 0) bank questions asked. \(cov.values.reduce(0, +)) answers on the record."
        if let thin { line += " The thinnest domain is \(GlyphBot.domainTitle(thin)), with \(cov[thin] ?? 0)." }
        let waiting = GlyphBotStore.shared.unsynced.count
        if waiting > 0 { line += " \(waiting) Oracle questions are waiting to sync." }
        return .result(dialog: "\(line)")
    }
}

/// Opens a GlyphBot room. Also what Spotlight runs when he picks a GlyphBot result.
struct OpenGlyphBotRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a GlyphBot Room"
    @Parameter(title: "Room") var target: GlyphBotRoomEntity

    init() {}
    init(target: GlyphBotRoomEntity) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "glyphbot", path: [target.id], query: [:])) }
        return .result()
    }
}

struct GlyphBotRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "GlyphBot Room"
    static let defaultQuery = GlyphBotRoomQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "GlyphBot") }

    static var all: [GlyphBotRoomEntity] { GlyphBotRoom.allCases.map { GlyphBotRoomEntity(id: $0.rawValue, title: $0.title) } }
}

struct GlyphBotRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GlyphBotRoomEntity] { GlyphBotRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [GlyphBotRoomEntity] { GlyphBotRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [GlyphBotRoomEntity] { GlyphBotRoomEntity.all }
}

enum GlyphBotSpotlight {
    /// Every room into Spotlight, in GlyphBot's own named index (Apple: not the default index).
    static func index() async {
        try? await CSSearchableIndex(name: "glyphbot").indexAppEntities(GlyphBotRoomEntity.all)
    }
}
