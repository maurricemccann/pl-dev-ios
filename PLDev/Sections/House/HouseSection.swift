import SwiftUI
import TipKit
import UserNotifications

/// House: the whole pl-os console on the phone (his order 11-13, "build everything in plos in full"). The web's three tabs,
/// Founder / Inbound / Outbound, plus More (the rooms and the system drawer). Every call goes through Console (the PL DEV key).
@MainActor enum HouseSection: PLSection {
    static let manifest = SectionManifest(id: "house", title: "House", symbol: "house",
                                          needsKeys: ["pldev"], needsOrigins: ["console"])
    static let state = HouseModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(HouseView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    /// House's own Settings rows: the tips again, and the rooms back into Spotlight.
    static func settingsRows(model: AppModel) -> AnyView? {
        AnyView(Group {
            Button { UserDefaults.standard.set(true, forKey: "pldev.resetTips") } label: {   // TipKit resets only before configure: at next launch
                SettingsLabel("Show the tips again next time PL DEV opens", "lightbulb", IOS27.SystemColors.yellow)
            }
            Button { Task { await HouseSpotlight.index() } } label: {
                SettingsLabel("Add House rooms to Spotlight again", "magnifyingglass", Color(uiColor: .systemGray))
            }
        })
    }
    /// The drafts notice carries one button: approve all (Face ID first, never on a locked phone; Pins still wait).
    static func notificationCategories() -> Set<UNNotificationCategory> {
        NotificationHub.actions["house.approveAll"] = {
            await AppModel.shared.restoreIfNeeded()
            guard let started = try? await HouseActions.approveAll(model: AppModel.shared) else {
                _ = await NotificationHub.shared.post(id: "house.approved", title: "Nothing approved", body: "The console did not answer. Open House and try again.", category: nil, link: nil)
                return
            }
            _ = await NotificationHub.shared.post(id: "house.approved", title: "Approving \(started) drafts", body: "Slack reports when it finishes. Pins still wait for you.", category: nil, link: nil)
        }
        let approve = UNNotificationAction(identifier: "house.approveAll", title: "Approve all", options: [.authenticationRequired],
                                           icon: UNNotificationActionIcon(systemImageName: "checkmark.seal"))
        return [UNNotificationCategory(identifier: "drafts", actions: [approve], intentIdentifiers: [])]
    }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first {
            if let tab = HouseModel.Tab(rawValue: first) { state.tab = tab }
            if let room = HouseRoom(rawValue: first) { state.room = room }
        }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.loadCounts(model: model)
        let n = state.stats?.pending ?? 0
        ShiftLive.publish(drafts: state.stats?.pending, plan: nil)
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
    struct PlanTask: Decodable, Identifiable, Equatable, Sendable {
        let id: String; let slot: String?; let time_pt: String?; let title: String?; let why: String?; var status: String?; let kind: String?; let action_label: String?
    }
    struct Plan: Decodable, Sendable { let plan_date: String?; var tasks: [PlanTask]? }
    struct Day: Decodable, Identifiable { let date: String; let dow: Int?; let work: Bool?; let exception: Bool?; var id: String { date } }
    struct Schedule: Decodable { let days: [Day]? }
    struct Record: Decodable { let days: Int?; let total: Int?; let done: Int?; let skipped: Int?; let since: String?; let streak: Int? }
    struct Digest: Decodable, Identifiable { let id: Int; let session_id: String?; let title: String?; let summary: String?; let closed_at: String? }
    struct Digests: Decodable { let digests: [Digest]? }
    struct Quarter: Decodable, Identifiable { let key: String; let label: String; let score: Int; let note: String?; var id: String { key } }
    struct Standing: Decodable { let total: Int?; let verdict: String?; let quarters: [Quarter]? }
    struct Counts: Decodable { let desiresPending: Int?; let captures: Int? }
    struct FounderTask: Decodable, Identifiable { let notion_page_id: String; let title: String?; let status: String?; let due_date: String?; let priority: String?; let project: String?; var id: String { notion_page_id } }

    var tab: Tab = .founder
    var room: HouseRoom?
    var live = false
    var stats: DraftStats?
    var walls: Declarations?
    var creator: Creator?
    var plan: Plan?
    var schedule: [Day] = []
    var record: Record?
    var tasks: [FounderTask] = []
    var digests: [Digest] = []
    var standing: Standing?
    var counts: Counts?
    var devStuck = 0
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
        async let dg = try? Console.get("api/session-digest", Digests.self, model: model)
        async let st = HouseModel.standingRead(model: model)
        async let ct = try? Console.q("counts", Counts.self, model: model)
        async let nt = try? OS.get("notion", NotionView.NState.self, model: model)
        let (s1, w1, c1, p1, sc1, r1, t1, dg1) = await (s, w, c, p, sc, r, t, dg)
        digests = dg1?.digests ?? []
        let (st1, ct1, nt1) = await (st, ct, nt)
        standing = st1; counts = ct1; devStuck = nt1?.pipeline["Development"] ?? 0
        live = ShiftLive.running != nil
        stats = s1; walls = w1; creator = c1; plan = p1; schedule = sc1?.days ?? []; record = r1; tasks = t1 ?? []
        ShiftLive.publish(drafts: s1?.pending, plan: p1)
        await ShiftLive.sync(p1)
        message = (s1 == nil && p1 == nil) ? "Could not reach the console. Pull to try again." : nil
    }

    /// The house's one number, computed by pl-cron the same way pl-os computes it (lib/standing.ts), read on the widget door.
    static func standingRead(model: AppModel) async -> Standing? {
        guard let http = model.http else { return nil }
        return try? JSONDecoder().decode(Standing.self, from: try await http.send(RequestPlan(origin: "cron", path: "api/widget/standing")))
    }

    /// The Needs You list, built as pl-os builds it (app/page.tsx): pipeline flags first, then founder tasks.
    var needsYou: [String] {
        var flags: [String] = []
        if let d = counts?.desiresPending, d > 0 { flags.append("\(d) desire(s) to moderate") }
        if let c = counts?.captures, c > 0 { flags.append("\(c) capture(s) in inbox") }
        if devStuck > 0 { flags.append("\(devStuck) piece(s) stuck in Development") }
        var out: [String] = []
        if !flags.isEmpty { out.append(flags.joined(separator: " · ")) }
        let pending = tasks.filter { !($0.status ?? "").lowercased().contains("done") }.count
        if pending > 0 { out.append("\(pending) founder task(s) pending") }
        return out
    }

    func tickTask(_ t: PlanTask, _ status: String, model: AppModel) async {
        guard let i = plan?.tasks?.firstIndex(where: { $0.id == t.id }) else { return }
        let before = plan?.tasks?[i].status
        plan?.tasks?[i].status = status
        do {
            try await Console.post("api/day-plan/complete", ["id": t.id, "status": status], model: model); tick += 1
            ShiftLive.publish(drafts: stats?.pending, plan: plan); await ShiftLive.sync(plan)
        }
        catch { plan?.tasks?[i].status = before; message = "Not saved. \(error.localizedDescription)" }
    }

    func setWork(_ d: Day, _ work: Bool, model: AppModel) async {
        do { try await Console.post("api/schedule", ["date": d.date, "work": work], model: model); tick += 1
            schedule = (try? await Console.get("api/schedule", Schedule.self, model: model, query: ["days": "7"]))?.days ?? schedule }
        catch { message = "Not saved. \(error.localizedDescription)" }
    }

    /// The shift on the Lock Screen and in the Dynamic Island, on his switch.
    func setLive(_ on: Bool) async {
        if on, let plan {
            do { try ShiftLive.start(plan) } catch {
                message = ShiftLive.allowed ? "The Lock Screen would not take it: \(error.localizedDescription)" : "Live Activities are off for PL DEV in Settings."
            }
        } else { await ShiftLive.stop() }
        live = ShiftLive.running != nil
        tick += 1
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
        .navigationDestination(item: $state.room) { room in room.view(model) }
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
                Section { Text(line).plHand(26).frame(maxWidth: .infinity).multilineTextAlignment(.center) }
                    .listRowBackground(Color.clear)
            }
            if let q = state.standing?.quarters?.min(by: { $0.score < $1.score }) {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DO NEXT · RAISES \(q.label.uppercased())").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Wallpaper.line)
                        (Text("\(q.score)/25").monospacedDigit().foregroundStyle(.secondary) + Text(" — \(q.note ?? "")")).font(.callout)
                    }
                    if let first = state.needsYou.first {
                        Button { state.room = .approvals } label: { LabeledContent(first) { Text("Open →").font(.caption.weight(.semibold)).foregroundStyle(Wallpaper.line) } }
                    }
                }
            }
            Section {
                HStack(spacing: 12) {
                    Kpi(title: "Needs you", value: "\(state.needsYou.count)")
                    Kpi(title: "Shift", value: "\((state.plan?.tasks ?? []).filter { $0.status == "done" }.count)/\(state.plan?.tasks?.count ?? 0)")
                    Kpi(title: "Approve", value: "\(state.stats?.pending ?? 0)")
                    Kpi(title: "Standing", value: "\(state.standing?.total ?? 0)")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                if !state.needsYou.isEmpty {
                    ForEach(state.needsYou, id: \.self) { Label($0, systemImage: "exclamationmark.circle").font(.callout) }
                } else {
                    Text("Nothing waiting on you.").foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink { ApprovalsView(model: model) } label: {
                    LabeledContent {
                        Text("\(state.stats?.pending ?? 0)").monospacedDigit().contentTransition(.numericText())
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
            if let st = state.standing {
                Section {
                    ForEach(st.quarters ?? []) { q in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(q.label.capitalized).font(.headline); Spacer(); Text("\(q.score)/25").monospacedDigit() }
                            ProgressView(value: Double(q.score), total: 25).tint(Wallpaper.line)
                            if let n = q.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                } header: { Text("Standing · \(st.total ?? 0)/100") } footer: { if let v = st.verdict { Text(v) } }
            }
            Section("Doors") {
                Link(destination: URL(string: "https://psychedluxuries.com/shop?debug=open")!) { Label("Shop debug", systemImage: "ladybug") }
                if let u = model.config?.origins["board"].flatMap(URL.init(string:)) { Link(destination: u) { Label("V.A.U.L.T. board (over Tailscale)", systemImage: "rectangle.3.group") } }
            }
            if !state.digests.isEmpty {
                Section("What the sessions did today") {
                    ForEach(state.digests) { d in
                        DisclosureGroup {
                            Text(d.summary ?? "").font(.callout).textSelection(.enabled)
                        } label: {
                            VStack(alignment: .leading) { Text(d.title ?? d.session_id ?? "Session"); Ago(text: d.closed_at).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
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
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: t.status)
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
        if !tasks.isEmpty {
            Section {
                TipView(ShiftLockScreenTip())
                Toggle(isOn: Binding(get: { state.live }, set: { v in Task { await state.setLive(v) } })) {
                    Label("Shift on the Lock Screen", systemImage: "lock.iphone")
                }
            }
        }
    }
}
