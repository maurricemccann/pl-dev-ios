import SwiftUI
import UserNotifications

/// House: the whole pl-os console on the phone (his order 11-13, "build everything in plos in full"). The web's three tabs,
/// Founder / Inbound / Outbound, plus More (the rooms and the system drawer). Every call goes through Console (the PL DEV key).
@MainActor enum HouseSection: PLSection {
    static let manifest = SectionManifest(id: "house", title: "House", symbol: "house",
                                          needsKeys: ["pldev"], needsOrigins: ["console"])
    static let state = HouseModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(HouseView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first {
            if let tab = HouseModel.Tab(rawValue: first) { state.tab = tab }
            if first == "approvals" { state.tab = .founder; state.openApprovals = true }
        }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.loadCounts(model: model)
        let n = state.stats?.pending ?? 0
        var notify: [LocalNotice] = []
        if n > 0, n != state.lastNotified {
            state.lastNotified = n
            notify.append(LocalNotice(id: "house.drafts", title: "Drafts waiting", body: "\(n) drafts are waiting for you.",
                                      category: "drafts", link: .section(id: "house", path: ["approvals"], query: [:])))
        }
        return SectionRefresh(badge: n > 0 ? n : nil, notify: notify)
    }
}

@MainActor @Observable final class HouseModel {
    enum Tab: String, CaseIterable, Identifiable {
        case founder, inbound, outbound, more
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    struct DraftStats: Decodable { let pending: Int?; let queued: Int?; let held: Int?; let week_total: Int? }
    struct Declarations: Decodable { let approve: String?; let now: String?; let bulk: String?; let madman: String? }
    struct Creator: Decodable { let status: String; let label: String; let updated: String? }
    struct PlanTask: Decodable, Identifiable, Equatable {
        let id: String; let slot: String?; let time_pt: String?; let title: String?; let why: String?; var status: String?; let kind: String?; let action_label: String?
    }
    struct Plan: Decodable { let plan_date: String?; var tasks: [PlanTask]? }
    struct Day: Decodable, Identifiable { let date: String; let dow: Int?; let work: Bool?; let exception: Bool?; var id: String { date } }
    struct Schedule: Decodable { let days: [Day]? }
    struct Record: Decodable { let days: Int?; let total: Int?; let done: Int?; let skipped: Int?; let since: String?; let streak: Int? }
    struct FounderTask: Decodable, Identifiable { let notion_page_id: String; let title: String?; let status: String?; let due_date: String?; let priority: String?; let project: String?; var id: String { notion_page_id } }

    var tab: Tab = .founder
    var openApprovals = false
    var stats: DraftStats?
    var walls: Declarations?
    var creator: Creator?
    var plan: Plan?
    var schedule: [Day] = []
    var record: Record?
    var tasks: [FounderTask] = []
    var message: String?
    var tick = 0
    var lastNotified = 0

    func loadCounts(model: AppModel) async {
        stats = try? await Console.q("draftstats", DraftStats.self, model: model)
    }

    func loadFounder(model: AppModel) async {
        async let s = try? Console.q("draftstats", DraftStats.self, model: model)
        async let w = try? Console.get("api/declarations", Declarations.self, model: model)
        async let c = try? Console.q("creator", Creator.self, model: model)
        async let p = try? Console.get("api/day-plan", Plan.self, model: model)
        async let sc = try? Console.get("api/schedule", Schedule.self, model: model, query: ["days": "7"])
        async let r = try? Console.get("api/record", Record.self, model: model)
        async let t = try? Console.q("foundertasks", [FounderTask].self, model: model)
        let (s1, w1, c1, p1, sc1, r1, t1) = await (s, w, c, p, sc, r, t)
        stats = s1; walls = w1; creator = c1; plan = p1; schedule = sc1?.days ?? []; record = r1; tasks = t1 ?? []
        message = (s1 == nil && p1 == nil) ? "Could not reach the console. Pull to try again." : nil
    }

    func tickTask(_ t: PlanTask, _ status: String, model: AppModel) async {
        guard let i = plan?.tasks?.firstIndex(where: { $0.id == t.id }) else { return }
        let before = plan?.tasks?[i].status
        plan?.tasks?[i].status = status
        do { try await Console.post("api/day-plan/complete", ["id": t.id, "status": status], model: model); tick += 1 }
        catch { plan?.tasks?[i].status = before; message = "Not saved. \(error.localizedDescription)" }
    }

    func setWork(_ d: Day, _ work: Bool, model: AppModel) async {
        do { try await Console.post("api/schedule", ["date": d.date, "work": work], model: model); tick += 1
            schedule = (try? await Console.get("api/schedule", Schedule.self, model: model, query: ["days": "7"]))?.days ?? schedule }
        catch { message = "Not saved. \(error.localizedDescription)" }
    }

    func setCreator(awake: Bool, model: AppModel) async {
        do {
            try await Console.post("api/pldev/x/creator", ["status": awake ? "awake" : "asleep"], model: model)
            creator = try? await Console.q("creator", Creator.self, model: model); tick += 1
        } catch { message = "Not saved. \(error.localizedDescription)" }
    }

    func complete(_ t: FounderTask, model: AppModel) async {
        tasks.removeAll { $0.id == t.id }
        do { try await Console.post("api/founder-task/complete", ["task_id": t.notion_page_id], model: model); tick += 1 }
        catch { tasks.append(t); message = "Not saved. \(error.localizedDescription)" }
    }
}

struct HouseView: View {
    let model: AppModel
    @Bindable var state: HouseModel

    var body: some View {
        Group {
            switch state.tab {
            case .founder: FounderTab(model: model, state: state)
            case .inbound: InboundTab(model: model)
            case .outbound: OutboundTab(model: model)
            case .more: MoreTab(model: model)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Page", selection: $state.tab) {
                ForEach(HouseModel.Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, PLSpace.margin).padding(.vertical, PLSpace.gap)
            .background(.bar)
        }
        .navigationTitle("House")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .navigationDestination(isPresented: $state.openApprovals) { ApprovalsView(model: model) }
    }
}

/// Founder: the shift, the approvals door, the house switches. What the web's default tab shows.
struct FounderTab: View {
    let model: AppModel
    @Bindable var state: HouseModel

    var body: some View {
        List {
            if let m = state.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
            if let line = state.walls?.madman {
                Section { Text(line).font(.headline).tracking(1).frame(maxWidth: .infinity).multilineTextAlignment(.center) }
                    .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink { ApprovalsView(model: model) } label: {
                    LabeledContent {
                        Text("\(state.stats?.pending ?? 0)").monospacedDigit()
                    } label: {
                        Label("Approvals", systemImage: "checkmark.seal")
                        if let s = state.stats { Text("\(s.queued ?? 0) in the drip · \(s.held ?? 0) held · \(s.week_total ?? 0) made this week") }
                    }
                }
                NavigationLink { MakeView(model: model) } label: { Label("Make a draft", systemImage: "square.and.pencil") }
                NavigationLink { SiteControlsView(model: model) } label: { Label("Site controls", systemImage: "switch.2") }
                if let c = state.creator {
                    Toggle(isOn: Binding(get: { c.status == "awake" }, set: { v in Task { await state.setCreator(awake: v, model: model) } })) {
                        Label { Text("The creator is awake"); Text(c.label) } icon: { Image(systemName: c.status == "awake" ? "sun.max" : "moon") }
                    }
                    .disabled(c.status == "dnd")
                }
            }
            shift
            if !state.schedule.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(state.schedule) { d in
                                let work = d.work ?? false
                                Button { Task { await state.setWork(d, !work, model: model) } } label: {
                                    VStack(spacing: 4) {
                                        Text(Date.pl(d.date)?.formatted(.dateTime.weekday(.abbreviated)) ?? d.date).font(.caption.bold())
                                        Text(Date.pl(d.date)?.formatted(.dateTime.day()) ?? "").font(.title3.monospacedDigit())
                                        Text(work ? "Work" : "Off").font(.caption2)
                                    }
                                    .frame(width: 52, height: 72)
                                    .background(work ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(d.date), \(work ? "work day" : "day off"). Tap to change.")
                            }
                        }
                    }
                } header: { Text("Amazon shifts") } footer: { Text("Tap a day to flip it. The day plan reads this.") }
            }
            if let r = state.record {
                Section("The record") {
                    LabeledContent("Streak", value: "\(r.streak ?? 0) days")
                    LabeledContent("Done", value: "\(r.done ?? 0) of \(r.total ?? 0)")
                    if let since = r.since { LabeledContent("Since", value: since) }
                }
            }
            if !state.tasks.isEmpty {
                Section("Founder tasks") {
                    ForEach(state.tasks) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title ?? "")
                            Text([t.project, t.priority, t.due_date].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Done") { Task { await state.complete(t, model: model) } }.tint(.green) }
                    }
                }
            }
        }
        .refreshable { await state.loadFounder(model: model) }
        .task { await state.loadFounder(model: model) }
    }

    @ViewBuilder private var shift: some View {
        let tasks = state.plan?.tasks ?? []
        Section {
            if tasks.isEmpty { Text("Today's plan has not been written yet.").foregroundStyle(.secondary) }
            ForEach(tasks) { t in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: t.status == "done" ? "checkmark.circle.fill" : t.status == "skipped" ? "minus.circle" : "circle")
                        .foregroundStyle(t.status == "done" ? .green : .secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title ?? "").strikethrough(t.status == "done" || t.status == "skipped")
                        if let why = t.why, !why.isEmpty { Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        if let time = t.time_pt { Text(time).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                    }
                }
                .swipeActions(edge: .trailing) { Button("Done") { Task { await state.tickTask(t, "done", model: model) } }.tint(.green) }
                .swipeActions(edge: .leading) { Button("Skip") { Task { await state.tickTask(t, "skipped", model: model) } }.tint(.gray) }
            }
        } header: { Text(state.plan?.plan_date.map { "Shift · \($0)" } ?? "Shift") } footer: {
            if !tasks.isEmpty { Text("Swipe left for done, right to skip.") }
        }
    }
}
