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
            if room == .freetalk { state.sitting.mode = .free } else if room == .interview { state.sitting.mode = .interview } else if room == .mastermind { state.sitting.mode = .mastermind }
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
    case ask, interview, freetalk, mastermind, record
    var id: String { rawValue }
    var title: String {
        switch self { case .ask: return "Ask the Oracle"; case .interview: return "Interview sitting"; case .freetalk: return "Free talk"; case .mastermind: return "Mastermind"; case .record: return "The interview record" }
    }
    var tab: GlyphBotModel.Tab {
        switch self { case .ask: return .ask; case .interview, .freetalk, .mastermind: return .sit; case .record: return .record }
    }
}

@MainActor @Observable final class GlyphBotModel {
    enum Tab: String, CaseIterable, Identifiable {
        case ask, sit, record
        var id: String { rawValue }
        var title: String { switch self { case .ask: return "Ask"; case .sit: return "Sit"; case .record: return "Record" } }
    }

    var tab: Tab = .ask
    var interview: GlyphBot.StateReply? = GlyphBotModel.simFixture() ?? GlyphBot.cachedState()
    var message: String?
    let sitting = SittingModel()

    /// Screens workflow only (the same gate as `simLink`, never on a device): made-up numbers and sample lines so the setup screen can be seen with its lists filled.
    static func simFixture() -> GlyphBot.StateReply? {
        guard UserDefaults.standard.string(forKey: "simConfig") != nil else { return nil }
        let json = """
        {"bank":{"asked":112,"total":501,"next_round":"origins"},
         "coverage":{"philosophy":14,"art-design":9,"process":7,"seeds":3,"archive":5,"business":2,"social-content":1,"world":0,"taste":4,"legacy":0,"origin":6},
         "queue":[{"id":9,"text":"Sample topic: what the daily practice asks of you that nothing else does"},{"id":8,"text":"Sample topic: the first piece you would not sell"},{"id":7,"text":"Sample topic: who the Defiance is for"},{"id":6,"text":"Sample topic: what luxury means when nobody is watching"},{"id":5,"text":"Sample topic: the line you redraw the most"}],
         "bank_next":[{"id":40,"round":"origins","text":"Sample question: what did you make first, and who saw it?"},{"id":41,"round":"origins","text":"Sample question: what did you stop making, and why?"},{"id":42,"round":"origins","text":"Sample question: which year changed the work?"}],
         "recent":[{"id":3,"answer":"Sample answer. The practice is the part nobody sees, and it is the only part that holds.","at":"2026-11-23T03:10:00Z","domain":"philosophy","question":"Sample question: what holds the work together?"},
                   {"id":2,"answer":"Sample answer. I draw the same gesture until it stops being a gesture and becomes a position.","at":"2026-11-22T02:40:00Z","domain":"process","question":"Sample question: how do you start?"}]}
        """
        return try? JSONDecoder().decode(GlyphBot.StateReply.self, from: Data(json.utf8))
    }

    func loadState(model: AppModel) async {
        guard GlyphBot.interviewReady(model), UserDefaults.standard.string(forKey: "simConfig") == nil else { return }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch state.tab {
            case .ask: AskTab(model: model, state: state)
            case .sit: SitTab(model: model, state: state, sitting: state.sitting)
            case .record: GlyphRecordTab(model: model, state: state)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            GlyphHeader(titles: GlyphBotModel.Tab.allCases.map(\.title), index: Binding(
                get: { GlyphBotModel.Tab.allCases.firstIndex(of: state.tab) ?? 0 },
                set: { state.tab = GlyphBotModel.Tab.allCases[$0] }), online: GlyphBotNet.shared.online)
        }
        .background { SiteGround() }
        .tint(Bone.goldDim)
        .sensoryFeedback(PLHaptic.select, trigger: state.tab)
        .navigationTitle("GlyphBot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // his own rigged GlyphGuy (his GLB converted to USDZ, the gallery lab's clips): shown, never redrawn ("Not my model")
            NavigationLink { GlyphGuyRoom(kind: .glyphbot) } label: { Image(systemName: "figure.stand") }   // native now: his model, his clips, in RealityKit
                .accessibilityLabel("See GlyphGuy")
        }
    }
}
