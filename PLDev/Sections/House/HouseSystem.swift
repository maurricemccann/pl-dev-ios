import ActivityKit
import AppIntents
import CoreSpotlight
import SwiftUI

// House's system add-ons (his loop, 11-13: build in full, test, then the premium feel and system add-ons).
// Built to Apple's guidance read 11-13: Live Activities (defined start and end, update only on new content, end at once),
// App Shortcuts (common tasks, every count in the spoken dialog), Spotlight via IndexedEntity + OpenIntent, TipKit (one or
// two sentences, for what cannot be seen), notification actions (no "just open" buttons, Face ID before acting).

// MARK: - Rooms: every House destination, by name, so a link, Siri or Spotlight can land on it

enum HouseRoom: String, CaseIterable, Identifiable, Hashable {
    case approvals, make, site, inbox, support, seeds, record, leads, tally, calendar, tempo, pipeline, feed, drip, vault, reach,
         opportunities, outbound, pinterest, council, ops, corpus, craft, codex, source, comments, merch, catalog, atlas,
         precedent, crew, health, jobs, costs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .approvals: return "Approvals"; case .make: return "Make a draft"; case .site: return "Site controls"
        case .inbox: return "Inbox"; case .support: return "Support"; case .seeds: return "Seed registrations"
        case .record: return "The record"; case .leads: return "Leads"; case .tally: return "Request and vote"
        case .calendar: return "Content calendar"; case .tempo: return "Tempo"; case .pipeline: return "Pipeline and briefing"
        case .feed: return "PL feed"; case .drip: return "In the drip"; case .vault: return "The vault"; case .reach: return "Post reach"
        case .opportunities: return "Opportunities"; case .outbound: return "Outbound leads"; case .pinterest: return "Pinterest"
        case .council: return "Council"; case .ops: return "Ops"; case .corpus: return "Search the corpus"; case .craft: return "Craft"
        case .codex: return "Codex"; case .source: return "Source interview"; case .comments: return "Comments to post"
        case .merch: return "Merch calendar"; case .catalog: return "Catalog"; case .atlas: return "Atlas"; case .precedent: return "Precedent"
        case .crew: return "Crew"; case .health: return "Stack health"; case .jobs: return "Run a job"; case .costs: return "Costs and revenue"
        }
    }

    @MainActor @ViewBuilder func view(_ model: AppModel) -> some View {
        switch self {
        case .approvals: ApprovalsView(model: model)
        case .make: MakeView(model: model)
        case .site: SiteControlsView(model: model)
        case .inbox: InboxView(model: model)
        case .support: SupportView(model: model)
        case .seeds: SeedRegistrationsView(model: model)
        case .record: RecordView(model: model)
        case .leads: LeadsView(model: model)
        case .tally: TallyView(model: model)
        case .calendar: HouseCalendarView(model: model)
        case .tempo: TempoView(model: model)
        case .pipeline: NotionView(model: model)
        case .feed: FeedView(model: model)
        case .drip: DripView(model: model)
        case .vault: VaultView(model: model)
        case .reach: ReachView(model: model)
        case .opportunities: OpportunityView(model: model)
        case .outbound: OutboundLeadsView(model: model)
        case .pinterest: PinterestView(model: model)
        case .council: CouncilView(model: model)
        case .ops: OpsView(model: model)
        case .corpus: CorpusView(model: model)
        case .craft: CraftView(model: model)
        case .codex: CodexToolView(model: model)
        case .source: SourceInterviewView(model: model)
        case .comments: CommentsView(model: model)
        case .merch: MerchView(model: model)
        case .catalog: CatalogMatrixView(model: model)
        case .atlas: AtlasView(model: model)
        case .precedent: PrecedentView(model: model)
        case .crew: CrewView(model: model)
        case .health: StackHealthView(model: model)
        case .jobs: AutomationView(model: model)
        case .costs: CostView(model: model)
        }
    }
}

// MARK: - The shift Live Activity and the widget's numbers

@MainActor enum ShiftLive {
    nonisolated static var running: Activity<ShiftAttributes>? { Activity<ShiftAttributes>.activities.first }
    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    nonisolated private static func state(_ plan: HouseModel.Plan) -> ShiftAttributes.ContentState {
        let tasks = plan.tasks ?? []
        let open = tasks.first { $0.status != "done" && $0.status != "skipped" }
        let done = tasks.filter { $0.status == "done" || $0.status == "skipped" }.count
        return .init(task: open?.title ?? "Shift done", time: open?.time_pt, done: done, total: tasks.count)
    }

    /// Started only from the foreground, by his tap (Apple: Live Activities for a task with a defined beginning and end).
    static func start(_ plan: HouseModel.Plan) throws {
        guard running == nil, !(plan.tasks ?? []).isEmpty else { return }
        _ = try Activity.request(attributes: ShiftAttributes(planDate: plan.plan_date ?? ""),
                                 content: .init(state: state(plan), staleDate: .now.addingTimeInterval(3 * 3600), relevanceScore: 80))
    }

    /// Updated only when the shift changes; ended at once when every task is ticked (dismissed 15 minutes later).
    nonisolated static func sync(_ plan: HouseModel.Plan?) async {   // off the main actor: Activity is not Sendable
        guard let plan, let a = running else { return }
        let s = state(plan)
        if s.total > 0 && s.done >= s.total {
            await a.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(900)))
        } else if a.content.state != s {
            await a.update(.init(state: s, staleDate: .now.addingTimeInterval(3 * 3600), relevanceScore: 80))
        }
    }

    nonisolated static func stop() async {
        for a in Activity<ShiftAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// The widget's numbers, from what the app just read.
    static func publish(drafts: Int?, plan: HouseModel.Plan?) {
        let tasks = plan?.tasks ?? []
        let open = tasks.first { $0.status != "done" && $0.status != "skipped" }
        let before = SharedState.readHouse()
        SharedState.writeHouse(HouseGlance(drafts: drafts ?? before?.drafts ?? 0,
                                           done: plan == nil ? before?.done ?? 0 : tasks.filter { $0.status == "done" || $0.status == "skipped" }.count,
                                           total: plan == nil ? before?.total ?? 0 : tasks.count,
                                           next: plan == nil ? before?.next : open?.title, nextTime: plan == nil ? before?.nextTime : open?.time_pt,
                                           updatedAt: .now))
    }
}

// MARK: - Siri, Shortcuts and the Action button (app target only, so they run in the app's process with its keys)

@MainActor private func readyModel() async throws -> AppModel {
    let m = AppModel.shared
    await m.restoreIfNeeded()
    guard m.http != nil else { throw Console.Problem.notSetUp }
    return m
}

struct HouseStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Waiting in the House"
    static let description: IntentDescription? = "Says how many drafts wait for you and how far today's shift has come."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await readyModel()
        async let stats = try? Console.q("draftstats", HouseModel.DraftStats.self, model: model)
        async let plan = try? Console.get("api/day-plan", HouseModel.Plan.self, model: model)
        let (s, p) = await (stats, plan)
        ShiftLive.publish(drafts: s?.pending, plan: p)
        let tasks = p?.tasks ?? []
        let left = tasks.filter { $0.status != "done" && $0.status != "skipped" }
        var line = "\(s?.pending ?? 0) drafts are waiting."
        if tasks.isEmpty { line += " Today's shift plan is not written yet." }
        else if left.isEmpty { line += " The shift is done: all \(tasks.count) tasks." }
        else { line += " \(left.count) of \(tasks.count) shift tasks left. Next: \(left[0].title ?? "")." }
        return .result(dialog: "\(line)")
    }
}

struct NextShiftTaskDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark the Next Shift Task Done"
    static let description: IntentDescription? = "Ticks the next open task on today's shift."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await readyModel()
        let plan = try await Console.get("api/day-plan", HouseModel.Plan.self, model: model)
        guard let t = (plan.tasks ?? []).first(where: { $0.status != "done" && $0.status != "skipped" }) else {
            return .result(dialog: "Nothing is left on today's shift.")
        }
        try await requestConfirmation(actionName: .set, dialog: "Mark \"\(t.title ?? "the next task")\" done?")
        try await Console.post("api/day-plan/complete", ["id": t.id, "status": "done"], model: model)
        var after = plan
        if let i = after.tasks?.firstIndex(where: { $0.id == t.id }) { after.tasks?[i].status = "done" }
        ShiftLive.publish(drafts: nil, plan: after)
        await ShiftLive.sync(after)
        return .result(dialog: "Done. \(t.title ?? "That task") is ticked.")
    }
}

struct ApproveAllDraftsIntent: AppIntent {
    static let title: LocalizedStringResource = "Approve All Drafts"
    static let description: IntentDescription? = "Approves every waiting draft except Pins, which still wait for your tap."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await readyModel()
        let n = (try? await Console.q("draftstats", HouseModel.DraftStats.self, model: model))?.pending ?? 0
        guard n > 0 else { return .result(dialog: "No drafts are waiting.") }
        try await requestConfirmation(actionName: .continue, dialog: "Approve up to 50 of the \(n) waiting drafts? Pins still wait for you.")
        let started = try await HouseActions.approveAll(model: model)
        return .result(dialog: "Approving \(started). Slack reports when it finishes.")
    }
}

/// Opens a House room. Also what Spotlight runs when he picks a House result.
struct OpenHouseRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a House Room"
    @Parameter(title: "Room") var target: HouseRoomEntity

    init() {}
    init(target: HouseRoomEntity) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "house", path: [target.id], query: [:])) }
        return .result()
    }
}

struct HouseRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "House Room"
    static let defaultQuery = HouseRoomQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "House") }

    static var all: [HouseRoomEntity] { HouseRoom.allCases.map { HouseRoomEntity(id: $0.rawValue, title: $0.title) } }
}

struct HouseRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [HouseRoomEntity] { HouseRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [HouseRoomEntity] { HouseRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [HouseRoomEntity] { HouseRoomEntity.all }
}

enum HouseSpotlight {
    /// Every room into Spotlight, once per launch, in House's own named index (Apple: not the default index).
    static func index() async {
        try? await CSSearchableIndex(name: "house").indexAppEntities(HouseRoomEntity.all)
    }
}

// MARK: - Actions shared by Siri and the notification button

@MainActor enum HouseActions {
    /// The widget route's two-step approve-all (it skips Pins and reports to Slack). Returns how many it started.
    static func approveAll(model: AppModel) async throws -> Int {
        guard let http = model.http, let write = model.config?.key("widgetWrite") else { throw Console.Problem.notSetUp }
        struct Armed: Decodable { let confirm: String? }
        struct Done: Decodable { let started: Int? }
        func post(_ body: [String: String]) async throws -> Data {
            try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/approve-all", headers: ["content-type": "application/json"],
                                            body: try JSONSerialization.data(withJSONObject: body)),
                                idempotent: false, extraHeaders: ["Authorization": "Bearer " + write])
        }
        guard let nonce = try JSONDecoder().decode(Armed.self, from: try await post([:])).confirm else { return 0 }
        return try JSONDecoder().decode(Done.self, from: try await post(["confirm": nonce])).started ?? 0
    }
}
