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
    @AppStorage("house.tab") private var savedTab = HouseModel.Tab.founder.rawValue   // the tab is remembered, as pl-os does

    var body: some View {
        Group {
            switch state.tab {
            case .founder: FounderTab(model: model, state: state)
            case .inbound: InboundTab(model: model)
            case .outbound: OutboundTab(model: model)
            case .more: MoreTab(model: model)
            }
        }
        .osScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OSTabBar(tab: $state.tab, badge: state.needsYou.count + (state.stats?.pending ?? 0))
        }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .sensoryFeedback(.selection, trigger: state.tab)
        .navigationDestination(item: $state.room) { room in room.view(model).osScreen() }
        .onAppear { if let t = HouseModel.Tab(rawValue: savedTab) { state.tab = t } }
        .onChange(of: state.tab) { _, t in savedTab = t.rawValue }
        // swipe between the three places, as the web does (a sideways drag only; a vertical scroll is left alone)
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
            guard abs(v.translation.width) > 2.2 * abs(v.translation.height), abs(v.translation.width) > 90 else { return }
            let all = HouseModel.Tab.allCases
            guard let i = all.firstIndex(of: state.tab) else { return }
            let j = v.translation.width < 0 ? min(i + 1, all.count - 1) : max(i - 1, 0)
            withAnimation(.snappy) { state.tab = all[j] }
        })
    }
}

/// Founder: pl-os's default place, in its order: the header and clock, the strip, the call bar, Do next, the KPI row, then the
/// panels (Needs you, Shift, Approvals, Make, Craft, Rooms, The house, Standing, the doors).
struct FounderTab: View {
    let model: AppModel
    @Bindable var state: HouseModel
    @Environment(\.colorScheme) private var scheme

    private var callBase: String? { model.config?.origins["call"]?.base }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                OSHeader()
                strip
                if let m = state.message { Text(m).font(.footnote).foregroundStyle(PLOS.dim(scheme)).frame(maxWidth: .infinity, alignment: .leading) }
                if let line = state.walls?.madman {
                    Text(line).plHand(24).foregroundStyle(PLOS.text(scheme)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                doNext
                kpis
                OSPanel(title: "Needs you", badge: "\(state.needsYou.count)", owed: !state.needsYou.isEmpty) {
                    if state.needsYou.isEmpty { Text("Nothing waiting on you.").foregroundStyle(PLOS.dim(scheme)) }
                    ForEach(state.needsYou, id: \.self) { n in
                        Button { state.room = .approvals } label: { OSRow(title: n) { Image(systemName: "arrow.right").foregroundStyle(PLOS.gold) } }.buttonStyle(.plain)
                    }
                    ForEach(state.tasks) { t in
                        OSRow(title: t.title ?? "", meta: [t.project, t.priority, t.due_date].compactMap { $0 }.joined(separator: " · ")) {
                            ConfirmButton(title: "Done", question: "Mark \"\(t.title ?? "this")\" done in Notion?") { await state.complete(t, model: model) }
                                .font(.caption.weight(.semibold)).foregroundStyle(PLOS.gold)
                        }
                    }
                }
                shiftPanel
                OSPanel(title: "Approvals", badge: "\(state.stats?.pending ?? 0)", startOpen: (state.stats?.pending ?? 0) > 0) {
                    if let s = state.stats { Text("\(s.queued ?? 0) in the drip · \(s.held ?? 0) held · \(s.week_total ?? 0) made this week").font(.system(size: 12, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) }
                    door("Review the drafts", "checkmark.seal", .approvals)
                    door("In the drip", "drop", .drip)
                }
                OSPanel(title: "Make") {
                    door("Artwork, text, quote or link", "square.and.pencil", .make)
                    door("The Craft · archive captions", "paintbrush", .craft)
                    door("Tempo engine", "metronome", .tempo)
                }
                OSPanel(title: "Rooms") {
                    door("The Atlas · the whole house, drawn", "map", .atlas)
                    door("Operations · support, shipping, returns", "shippingbox", .ops)
                    door("Codex", "book.closed", .codex)
                    door("Source interview", "quote.bubble", .source)
                    door("Comments to post", "text.bubble", .comments)
                    door("Precedent", "square.grid.2x2", .precedent)
                    door("Search the corpus", "magnifyingglass", .corpus)
                    door("Council", "person.3", .council)
                    if let u = model.config?.origins["board"].flatMap({ URL(string: $0.base) }) {
                        Link(destination: u) { OSRow(title: "V.A.U.L.T. board", meta: "Full board · Conductor · over Tailscale") { Image(systemName: "arrow.up.right").foregroundStyle(PLOS.gold) } }
                    }
                }
                houseSwitches
                standingPanel
                OSPanel(title: "Calendars and the catalog") {
                    door("Content calendar", "calendar", .calendar)
                    door("Merch calendar", "calendar.badge.clock", .merch)
                    door("Catalog matrix · every design × every Printful category", "tablecells", .catalog)
                    Link(destination: URL(string: "https://psychedluxuries.com/shop?debug=open")!) { OSRow(title: "Shop debug") { Image(systemName: "arrow.up.right").foregroundStyle(PLOS.gold) } }
                }
                if !state.digests.isEmpty {
                    OSPanel(title: "What the sessions did today", badge: "\(state.digests.count)") {
                        ForEach(state.digests) { d in
                            DisclosureGroup {
                                Text(d.summary ?? "").font(.callout).foregroundStyle(PLOS.text(scheme)).textSelection(.enabled)
                            } label: {
                                VStack(alignment: .leading) { Text(d.title ?? d.session_id ?? "Session").foregroundStyle(PLOS.text(scheme)); Ago(text: d.closed_at).font(.caption).foregroundStyle(PLOS.dim(scheme)) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 24)
        }
        .refreshable { await state.loadFounder(model: model) }
        .task { await state.loadFounder(model: model) }
    }

    // MARK: the strip and the call bar (pl-os StatusStrip)

    private var strip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    door("Stack health", "waveform.path.ecg", .health, plain: true)
                    door("Run a job", "play.circle", .jobs, plain: true)
                    door("Costs and revenue", "dollarsign.circle", .costs, plain: true)
                    door("Crew", "person.2", .crew, plain: true)
                } label: { Text("System") }.buttonStyle(OSPill())
                Button { state.room = .site } label: { Text("Site controls") }.buttonStyle(OSPill())
            }
            if let base = callBase {
                HStack(spacing: 8) {
                    callLink("Call", base)
                    callLink("Replay", base + "?replay")
                    callLink("Approve", base + "?approve")
                }
            }
        }
    }

    private func callLink(_ title: String, _ s: String) -> some View {
        Group { if let u = URL(string: s) { Link(destination: u) { Text(title) }.buttonStyle(OSPill()) } }
    }

    // MARK: Do next + KPI row

    @ViewBuilder private var doNext: some View {
        if let q = state.standing?.quarters?.min(by: { $0.score < $1.score }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Do next · raises \(q.label)").osEyebrow(10).foregroundStyle(PLOS.goldDim(scheme))
                (Text("\(q.score)/25").font(.system(.callout, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) + Text(" · \(q.note ?? "")").foregroundStyle(PLOS.text(scheme))).font(.callout)
                if let first = state.needsYou.first {
                    Button { state.room = .approvals } label: { OSRow(title: first) { Text("Open →").osEyebrow(10).foregroundStyle(PLOS.gold) } }.buttonStyle(.plain)
                }
            }
            .osCard()
        }
    }

    private var kpis: some View {
        let tasks = state.plan?.tasks ?? []
        let done = tasks.filter { $0.status == "done" }.count
        let needs = state.needsYou.count, pending = state.stats?.pending ?? 0
        let word: (String, Color) = needs > 0 ? ("Act  \(needs) need you · \(pending) to approve", PLOS.danger)
            : pending > 0 ? ("Watch  \(pending) to approve", PLOS.warn) : ("Clear", PLOS.ok)
        return OSKpis(items: [("Needs you", "\(needs)", nil), ("Shift", "\(done)/\(tasks.count)", "done today"),
                              ("Approve", "\(pending)", nil), ("Standing", "\(state.standing?.total ?? 0)", "of 100")], status: word)
    }

    // MARK: Shift (DayPlanPanel): the plan, the Amazon week, the record, the Lock Screen

    private var shiftPanel: some View {
        let tasks = state.plan?.tasks ?? []
        return OSPanel(title: "Shift", badge: "\(tasks.filter { $0.status == "done" }.count)/\(tasks.count)") {
            if tasks.isEmpty { Text("Today's plan has not been written yet.").foregroundStyle(PLOS.dim(scheme)) }
            ForEach(tasks) { t in
                HStack(alignment: .top, spacing: 10) {
                    Button { if t.status != "done" { Task { await state.tickTask(t, "done", model: model) } } } label: {
                        Image(systemName: t.status == "done" ? "checkmark.circle.fill" : t.status == "skipped" ? "minus.circle" : "circle")
                            .font(.title3).foregroundStyle(t.status == "done" ? PLOS.ok : PLOS.goldDim(scheme))
                            .contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: t.status)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.status == "done" ? "Done." : "Not done. Tap to mark done.")
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if let time = t.time_pt { Text(time).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) }
                            Text(t.kind == "auto" ? "⚙" : "✋").font(.caption2).accessibilityLabel(t.kind == "auto" ? "Runs itself" : "By hand")
                        }
                        Text(t.title ?? "").foregroundStyle(PLOS.text(scheme)).strikethrough(t.status == "done" || t.status == "skipped")
                        if let why = t.why, !why.isEmpty { Text(why).font(.caption).foregroundStyle(PLOS.dim(scheme)).lineLimit(3) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(PLOS.surface2(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contextMenu {
                    Button("Done", systemImage: "checkmark") { Task { await state.tickTask(t, "done", model: model) } }
                    Button("Skip", systemImage: "minus.circle") { Task { await state.tickTask(t, "skipped", model: model) } }
                }
            }
            if !state.schedule.isEmpty {
                Text("Amazon shifts · tap a day to flip it").osEyebrow(9).foregroundStyle(PLOS.goldDim(scheme)).padding(.top, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.schedule) { d in
                            let work = d.work ?? false
                            Button { Task { await state.setWork(d, !work, model: model) } } label: {
                                VStack(spacing: 4) {
                                    Text(Date.pl(d.date)?.formatted(.dateTime.weekday(.abbreviated)) ?? d.date).osEyebrow(9)
                                    Text(Date.pl(d.date)?.formatted(.dateTime.day()) ?? "").osValue(20)
                                    Text(work ? "Work" : "Off").font(.caption2)
                                }
                                .foregroundStyle(work ? Color.black : PLOS.text(scheme))
                                .padding(.vertical, 10).frame(minWidth: 52)
                                .background(work ? PLOS.gold : PLOS.surface2(scheme).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(d.date), \(work ? "work day" : "day off"). Tap to change.")
                        }
                    }
                }
            }
            if let r = state.record {
                HStack {
                    Text("The record").plHand(16).foregroundStyle(PLOS.dim(scheme))
                    Spacer()
                    Text("\(r.streak ?? 0) day streak · \(r.done ?? 0)/\(r.total ?? 0)").font(.system(size: 12, design: .monospaced)).foregroundStyle(PLOS.text(scheme))
                }
            }
            if !tasks.isEmpty {
                TipView(ShiftLockScreenTip())
                Toggle(isOn: Binding(get: { state.live }, set: { v in Task { await state.setLive(v) } })) {
                    Label("Shift on the Lock Screen", systemImage: "lock.iphone").foregroundStyle(PLOS.text(scheme))
                }
            }
        }
    }

    // MARK: The house (Creator signal + site controls)

    private var houseSwitches: some View {
        OSPanel(title: "The house") {
            if let c = state.creator {
                Toggle(isOn: Binding(get: { c.status == "awake" }, set: { v in Task { await state.setCreator(awake: v, model: model) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Creator Signal").foregroundStyle(PLOS.text(scheme))
                        Text(c.label).font(.caption).foregroundStyle(PLOS.dim(scheme))
                    }
                }
                .disabled(c.status == "dnd")
                Text("One signal the whole site reads: lightOS when you are working, nightOS when resting.").font(.caption).foregroundStyle(PLOS.dim(scheme))
            }
            door("Site controls · maintenance, shop, words on the site", "switch.2", .site)
        }
    }

    // MARK: Standing (HeroCard + StandingCurve)

    @ViewBuilder private var standingPanel: some View {
        if let st = state.standing {
            OSPanel(title: "Standing", badge: "\(st.total ?? 0)/100") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(st.total ?? 0)").font(.system(size: 56, design: .serif).italic()).foregroundStyle(PLOS.gold)
                    Text("of 100").osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
                }
                if let v = st.verdict { Text(v).font(.callout).foregroundStyle(PLOS.text(scheme)) }
                ForEach(st.quarters ?? []) { q in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(q.label.capitalized).plHand(16).foregroundStyle(PLOS.dim(scheme)); Spacer(); Text("\(q.score)/25").osValue(13).foregroundStyle(PLOS.text(scheme)) }
                        Gauge(value: Double(q.score), in: 0...25) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(q.score < 10 ? PLOS.danger : q.score < 18 ? PLOS.warn : PLOS.gold)
                        if let n = q.note { Text(n).font(.caption).foregroundStyle(PLOS.dim(scheme)) }
                    }
                }
            }
        }
    }

    // MARK: a door to a room

    private func door(_ title: String, _ symbol: String, _ room: HouseRoom, plain: Bool = false) -> some View {
        Button { state.room = room } label: {
            if plain { Label(title, systemImage: symbol) }
            else {
                OSRow(title: title) { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(PLOS.goldDim(scheme)) }
            }
        }
        .buttonStyle(.plain)
    }
}
