import SwiftUI
import TipKit
import UserNotifications

/// GlyphBot: the Oracle room and the interviewer, native (his order 11-13: "GlyphBot in full"). Ask answers from the practice,
/// offline too; Sit is the interviewer, with its own key; Record is what the interviews have kept.
/// GlyphGuy has no face and is not redrawn here: the room is words, as the R1's is.
@MainActor enum GlyphBotSection: PLSection {
    static let manifest = SectionManifest(id: "glyphbot", title: "GlyphBot", symbol: "bubbles.and.sparkles",
                                          needsKeys: ["pldev"], needsOrigins: ["console"])
    static let state = GlyphBotModel()
    private static var indexed = false

    static func makeRoot(model: AppModel) -> AnyView { AnyView(GlyphBotView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }   // GlyphBot has nothing to tell him: he starts it

    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first, let room = GlyphBotRoom(rawValue: first) {
            state.tab = room.tab
            if room == .freetalk { state.sitting.mode = .free } else if room == .interview { state.sitting.mode = .interview }
        }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        _ = GlyphBotNet.shared   // starts watching the connection, so the backlog syncs when it returns
        await state.loadState(model: model)
        await GlyphBotStore.shared.flush(model: model)
        state.publish()
        if !indexed { indexed = true; await GlyphBotSpotlight.index() }
        return SectionRefresh(badge: nil, notify: [])
    }
}

struct AnswerHoldTip: Tip {
    var title: Text { Text("More on every answer") }
    var message: Text? { Text("Touch and hold an answer to see its sources or hear it in GlyphBot's voice.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Every GlyphBot destination, by name, so a link, Siri or Spotlight can land on it.
enum GlyphBotRoom: String, CaseIterable, Identifiable, Hashable {
    case ask, interview, freetalk, record
    var id: String { rawValue }
    var title: String {
        switch self { case .ask: return "Ask the Oracle"; case .interview: return "Interview sitting"; case .freetalk: return "Free talk"; case .record: return "The interview record" }
    }
    var tab: GlyphBotModel.Tab {
        switch self { case .ask: return .ask; case .interview, .freetalk: return .sit; case .record: return .record }
    }
}

@MainActor @Observable final class GlyphBotModel {
    enum Tab: String, CaseIterable, Identifiable {
        case ask, sit, record
        var id: String { rawValue }
        var title: String { switch self { case .ask: return "Ask"; case .sit: return "Sit"; case .record: return "Record" } }
    }

    var tab: Tab = .ask
    var interview: GlyphBot.StateReply? = GlyphBot.cachedState()
    var message: String?
    let sitting = SittingModel()

    func loadState(model: AppModel) async {
        guard GlyphBot.interviewReady(model) else { return }
        do { interview = try await GlyphBot.state(model: model); message = nil }
        catch { message = "Could not reach the record. \(plainSentence(error))" }
        publish()
    }

    /// The widget's numbers, from what the app just read.
    func publish() {
        guard let s = interview else { return }
        let cov = s.coverage ?? [:]
        let thin = GlyphBot.domains.min { (cov[$0] ?? 0) < (cov[$1] ?? 0) }
        GlyphBotGlance.write(GlyphBotGlance(asked: s.bank?.asked ?? 0, total: s.bank?.total ?? 0, answers: cov.values.reduce(0, +),
                                            thinnest: thin.map(GlyphBot.domainTitle), thinnestCount: thin.map { cov[$0] ?? 0 } ?? 0,
                                            waiting: GlyphBotStore.shared.unsynced.count, updatedAt: .now))
    }
}

struct GlyphBotView: View {
    let model: AppModel
    @Bindable var state: GlyphBotModel

    var body: some View {
        Group {
            switch state.tab {
            case .ask: AskTab(model: model, state: state)
            case .sit: SitTab(model: model, state: state, sitting: state.sitting)
            case .record: GlyphRecordTab(model: model, state: state)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Page", selection: $state.tab) { ForEach(GlyphBotModel.Tab.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)
                .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap)
                .background(.bar)
        }
        .navigationTitle("GlyphBot")
        .navigationBarTitleDisplayMode(.inline)
    }
}
