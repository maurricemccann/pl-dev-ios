import SwiftUI
import UserNotifications

/// House: the pl-os pages that have widget routes. Approvals (draft cards, approve / hold, approve all in two steps),
/// Shift (today's tasks, tick done / skipped) and Standing (the house score, sales). Reads use widgetRead, writes widgetWrite.
@MainActor enum HouseSection: PLSection {
    static let manifest = SectionManifest(id: "house", title: "House", symbol: "house",
                                          needsKeys: ["widgetRead", "widgetWrite"], needsOrigins: ["cron"])
    static let state = HouseModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(HouseView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first, let page = HouseModel.Page(rawValue: first) { state.page = page }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.loadDrafts(model: model)
        let n = state.draftCount
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
    enum Page: String, CaseIterable, Identifiable { case approvals, shift, standing; var id: String { rawValue } }

    struct Draft: Decodable, Identifiable, Equatable { let id: String; let platform: String?; let kind: String?; let caption: String?; let image: String?; let created_at: String? }
    struct ShiftTask: Decodable, Identifiable, Equatable { let id: String; let time: String?; let title: String?; var status: String?; let kind: String? }
    struct Quarter: Decodable, Identifiable, Equatable { let key: String; let label: String; let score: Int; let note: String?; var id: String { key } }
    struct Standing: Decodable, Equatable { let total: Int?; let verdict: String?; let quarters: [Quarter]? }
    struct Sales: Decodable, Equatable { struct Last: Decodable, Equatable { let at: String?; let total: Double?; let currency: String? }; let count: Int?; let last: Last? }

    var page: Page = .approvals
    var drafts: [Draft] = []
    var draftCount = 0
    var tasks: [ShiftTask] = []
    var planDate: String?
    var standing: Standing?
    var sales: Sales?
    var message: String?
    var tick = 0
    var lastNotified = 0
    var confirmAll = false

    private func get<T: Decodable>(_ path: String, _ type: T.Type, model: AppModel) async throws -> T {
        guard let http = model.http else { throw URLError(.notConnectedToInternet) }
        return try JSONDecoder().decode(T.self, from: try await http.send(RequestPlan(origin: "cron", path: path)))
    }

    private func post(_ path: String, _ body: [String: String], model: AppModel) async throws -> Data {
        guard let http = model.http, let write = model.config?.key("widgetWrite") else { throw URLError(.userAuthenticationRequired) }
        return try await http.send(RequestPlan(origin: "cron", method: "POST", path: path, headers: ["content-type": "application/json"],
                                               body: try JSONSerialization.data(withJSONObject: body)),
                                   idempotent: false, extraHeaders: ["Authorization": "Bearer " + write])
    }

    func loadDrafts(model: AppModel) async {
        struct Out: Decodable { let drafts: [Draft]? }
        struct Count: Decodable { let pending: Int? }
        do {
            drafts = try await get("api/widget/drafts", Out.self, model: model).drafts ?? []
            draftCount = (try? await get("api/widget/moderation", Count.self, model: model).pending) ?? drafts.count
            message = nil
        } catch { message = "Could not read the drafts." }
    }

    func loadShift(model: AppModel) async {
        struct Out: Decodable { let plan_date: String?; let tasks: [ShiftTask]? }
        do { let o = try await get("api/widget/dayplan", Out.self, model: model); tasks = o.tasks ?? []; planDate = o.plan_date; message = nil }
        catch { message = "Could not read the shift." }
    }

    func loadStanding(model: AppModel) async {
        do {
            standing = try await get("api/widget/standing", Standing.self, model: model)
            sales = try? await get("api/widget/sales", Sales.self, model: model)
            message = nil
        } catch { message = "Could not read the standing." }
    }

    /// Optimistic: the card leaves at once and comes back if the server refuses.
    func act(_ d: Draft, _ action: String, model: AppModel) async {
        guard let i = drafts.firstIndex(of: d) else { return }
        drafts.remove(at: i)
        do { _ = try await post("api/widget/draft-act", ["id": d.id, "action": action], model: model); tick += 1; draftCount = max(0, draftCount - 1) }
        catch { drafts.insert(d, at: min(i, drafts.count)); message = "Not saved: \(action) failed. Try again." }
    }

    func tickTask(_ t: ShiftTask, _ status: String, model: AppModel) async {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        let before = tasks[i].status
        tasks[i].status = status
        do { _ = try await post("api/widget/dayplan-tick", ["id": t.id, "status": status], model: model); tick += 1 }
        catch { tasks[i].status = before; message = "Not saved. Try again." }
    }

    /// Two steps, as the server requires: arm, then confirm with the nonce within 30 s.
    func approveAll(model: AppModel) async {
        struct Armed: Decodable { let confirm: String?; let pending: Int? }
        struct Done: Decodable { let started: Int? }
        do {
            let armed = try JSONDecoder().decode(Armed.self, from: try await post("api/widget/approve-all", [:], model: model))
            guard let nonce = armed.confirm else { message = "Nothing to approve."; return }
            let done = try JSONDecoder().decode(Done.self, from: try await post("api/widget/approve-all", ["confirm": nonce], model: model))
            message = "Approving \(done.started ?? 0). Slack reports when it finishes."
            tick += 1
            drafts = drafts.filter { $0.platform == "pinterest" }
        } catch { message = "Approve all failed. Nothing changed." }
    }
}

struct HouseView: View {
    let model: AppModel
    @Bindable var state: HouseModel

    var body: some View {
        List {
            Picker("Page", selection: $state.page) {
                Text("Approvals").tag(HouseModel.Page.approvals)
                Text("Shift").tag(HouseModel.Page.shift)
                Text("Standing").tag(HouseModel.Page.standing)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if let m = state.message { Text(m).foregroundStyle(.secondary) }
            switch state.page {
            case .approvals: approvals
            case .shift: shift
            case .standing: standingView
            }
        }
        .navigationTitle("House")
        .refreshable { await load() }
        .task(id: state.page) { await load() }
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .confirmationDialog("Approve every waiting draft except Pins?", isPresented: $state.confirmAll, titleVisibility: .visible) {
            Button("Approve all") { Task { await state.approveAll(model: model) } }
        } message: {
            Text("Up to 50 drafts join the drip. Pins still wait for your tap one by one.")
        }
    }

    private func load() async {
        switch state.page {
        case .approvals: await state.loadDrafts(model: model)
        case .shift: await state.loadShift(model: model)
        case .standing: await state.loadStanding(model: model)
        }
    }

    @ViewBuilder private var approvals: some View {
        if state.drafts.isEmpty && state.message == nil {
            ContentUnavailableView("Nothing waiting", systemImage: "checkmark.seal", description: Text("No drafts need you. New ones land here."))
        }
        Section {
            ForEach(state.drafts) { d in
                VStack(alignment: .leading, spacing: 8) {
                    if let s = d.image, let url = URL(string: s) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                            .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                    }
                    Text((d.platform ?? "?").capitalized).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(d.caption ?? "").font(.body)
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing) { Button("Approve") { Task { await state.act(d, "approve", model: model) } }.tint(.green) }
                .swipeActions(edge: .leading) { Button("Hold") { Task { await state.act(d, "hold", model: model) } }.tint(.orange) }
                .contextMenu {
                    Button("Copy caption") { UIPasteboard.general.string = d.caption }
                    Button("Approve") { Task { await state.act(d, "approve", model: model) } }
                    Button("Hold") { Task { await state.act(d, "hold", model: model) } }
                }
            }
        } header: {
            Text("\(state.draftCount) waiting · showing the newest \(state.drafts.count)")
        } footer: {
            Text("Swipe left to approve, right to hold.")
        }
        if state.draftCount > 0 {
            Button("Approve all…") { state.confirmAll = true }
        }
    }

    @ViewBuilder private var shift: some View {
        if state.tasks.isEmpty && state.message == nil {
            ContentUnavailableView("No shift today", systemImage: "calendar", description: Text("Today's plan has not been written yet."))
        }
        Section(state.planDate.map { "Shift for \($0)" } ?? "Shift") {
            ForEach(state.tasks) { t in
                HStack {
                    Image(systemName: t.status == "done" ? "checkmark.circle.fill" : t.status == "skipped" ? "minus.circle" : "circle")
                        .foregroundStyle(t.status == "done" ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(t.title ?? "").strikethrough(t.status == "done" || t.status == "skipped")
                        if let time = t.time { Text(time).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions(edge: .trailing) { Button("Done") { Task { await state.tickTask(t, "done", model: model) } }.tint(.green) }
                .swipeActions(edge: .leading) { Button("Skip") { Task { await state.tickTask(t, "skipped", model: model) } }.tint(.gray) }
            }
        }
    }

    @ViewBuilder private var standingView: some View {
        if let s = state.standing {
            Section {
                LabeledContent("Score", value: s.total.map { "\($0)" } ?? "?")
                if let v = s.verdict { Text(v).font(.headline) }
            }
            Section("Quarters") {
                ForEach(s.quarters ?? []) { q in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(q.label).font(.headline); Spacer(); Text("\(q.score)").monospacedDigit() }
                        ProgressView(value: Double(q.score), total: 25)
                        if let n = q.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        if let sales = state.sales {
            Section("Sales") {
                LabeledContent("Orders", value: sales.count.map(String.init) ?? "?")
                if let t = sales.last?.total { LabeledContent("Last", value: String(format: "%@ %.2f", sales.last?.currency ?? "", t)) }
            }
        }
    }
}
