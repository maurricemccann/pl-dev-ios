import AVKit
import SwiftUI
import UserNotifications

// "Needs you" (his ask 11-25, S353: "A founders reminder app in pl dev ... anything that needs my attention my hands or my eyes").
// One screen over what the app already reads: drafts to look at (played here, with sound), messages waiting, the board's rows
// for his hands and his calls, today's plan, and what is coming up on the shared calendar (deadlines and renewals).

@MainActor enum NeedsSection: PLSection {
    static let manifest = SectionManifest(id: "needs", title: "Needs you", symbol: "bell.badge", needsKeys: [], needsOrigins: ["console", "cron"])
    static let state = NeedsModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(NeedsView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }   // support and member mail already raise theirs (AppleWatch)
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.loadMessages(model: model)
        await state.loadAhead(model: model)
        state.scheduleNotices()
        let n = state.support.count + state.unread.count
        return SectionRefresh(badge: n > 0 ? n : nil, notify: [])
    }
}

@MainActor @Observable final class NeedsModel {
    var support: [SupportView.Message] = []
    var unread: [InboxView.Thread] = []
    var board: PerformancePage.BoardRows?
    var plan: [HouseModel.PlanTask] = []
    /// Board items carrying a picture or a video of the house's own public files.
    var look: [Look] = []
    struct Look: Identifiable { let url: URL, title: String; var id: URL { url } }
    let calendar = CalendarModel()
    var loaded = false
    var problem: String?
    /// Drafts, and the approve and hold calls, are the Approvals room's own.
    let approvals = ApprovalsModel()

    func loadMessages(model: AppModel) async {
        if let rows = try? await Console.q("contact", [SupportView.Message].self, model: model) { support = rows.filter { $0.status != "resolved" } }
        if let out = try? await Console.get("api/dm/threads", InboxView.Out.self, model: model) { unread = (out.threads ?? []).filter { ($0.unread ?? 0) > 0 } }
    }

    /// Overdue by up to three days, or due within two weeks.
    var ahead: [CalendarItem] {
        let from = Self.day(-3), to = Self.day(14)
        return calendar.items.filter { $0.done == 0 && $0.date >= from && $0.date <= to }
    }

    private static let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .current
    private static func day(_ offset: Int) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = pacific
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date().addingTimeInterval(Double(offset) * 86400))
    }

    func loadAhead(model: AppModel) async {
        if let b = await PerformancePage.readBoard(model) { board = b }
        await calendar.load(model: model, from: CalendarModel.thisMonth)
        struct Tail: Decodable { let text: String }
        if let http = model.http,
           let d = try? await http.send(RequestPlan(origin: "cron", path: "api/widget/note", query: ["t": "eyes"])),
           let t = try? JSONDecoder().decode(Tail.self, from: d) {
            look = t.text.split(separator: "\n").compactMap { line -> Look? in
                let p = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard p.count == 2, let url = URL(string: p[0]), url.scheme == "https" else { return nil }
                return Look(url: url, title: p[1])
            }
        }
    }

    /// Two kinds of notice on the phone: anything due, two days ahead at 4:20 PM Pacific; and a count at the next 4:30 PM.
    func scheduleNotices() {
        let center = UNUserNotificationCenter.current(), d = UserDefaults.standard
        center.removePendingNotificationRequests(withIdentifiers: d.stringArray(forKey: "pldev.needs.notified") ?? [])
        var set: [String] = []
        defer { d.set(set, forKey: "pldev.needs.notified") }
        guard d.bool(forKey: "pldev.notify") else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.pacific
        func add(_ id: String, _ title: String, _ body: String, at when: Date) {
            guard when > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            var parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            parts.timeZone = Self.pacific
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            set.append(id)
        }
        for item in calendar.items where item.done == 0 {
            let p = item.date.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, let due = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 16, minute: 20)),
                  let early = cal.date(byAdding: .day, value: -2, to: due), set.count < 20 else { continue }   // iOS keeps 64 in all
            add("needs-due-\(item.id)", "Due in two days", item.title, at: early)
        }
        let waiting = approvals.drafts.count + approvals.reports.count + support.count + unread.count + (board?.rows.count ?? 0)
        if waiting > 0, let next = cal.nextDate(after: Date(), matching: DateComponents(hour: 16, minute: 30), matchingPolicy: .nextTime) {
            add("needs-shift", "Needs you", "\(waiting) waiting on you, \(ahead.count) coming up.", at: next)
        }
    }

    func done(_ item: CalendarItem, model: AppModel) async {
        let saved = await calendar.send(["action": "done", "id": item.id], model: model)
        if !saved { problem = "Not saved. Try again." }
        scheduleNotices()
    }

    func load(model: AppModel) async {
        await approvals.load(model: model)
        await loadMessages(model: model)
        await loadAhead(model: model)
        let day = try? await Console.get("api/day-plan", HouseModel.Plan.self, model: model)
        if let day { plan = (day.tasks ?? []).filter { $0.status != "done" && $0.status != "skipped" } }
        // an empty screen must not read as "nothing waits" when nothing answered
        problem = approvals.result != nil || board == nil || day == nil || !calendar.loaded
            ? "Some lists did not answer, so this may not be everything. Pull to try again." : nil
        loaded = true
        scheduleNotices()
    }

    func done(_ task: HouseModel.PlanTask, model: AppModel) async {
        do {
            try await Console.post("api/day-plan/complete", ["id": task.id, "status": "done"], model: model)
            plan.removeAll { $0.id == task.id }
        } catch { problem = "Not saved. \(error.localizedDescription)" }
    }
}

struct NeedsView: View {
    let model: AppModel
    let state: NeedsModel
    private static let shown = 10

    var body: some View {
        List { Group {
            if let p = state.problem { Text(p).plFont(.footnote).foregroundStyle(.secondary) }
            if !state.loaded { ProgressView("Looking everywhere") }
            else if nothing && state.problem == nil { Text("Nothing is waiting on you.").plFont(.callout) }
            eyes
            toLook
            messages
            hands
            today
            comingUp
        }.listRowBackground(PLRowGround()) }
        .plGround()
        .plScreenTitle("Needs you")
        .task { await state.load(model: model) }
        .refreshable { await state.load(model: model) }
        .onDisappear { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private var nothing: Bool {
        state.approvals.drafts.isEmpty && state.approvals.reports.isEmpty && state.support.isEmpty && state.unread.isEmpty
            && (state.board?.rows.isEmpty ?? true) && state.plan.isEmpty && state.ahead.isEmpty && state.look.isEmpty
    }

    @ViewBuilder private var eyes: some View {
        if !state.approvals.drafts.isEmpty {
            Section("Your eyes · \(state.approvals.drafts.count) draft\(state.approvals.drafts.count == 1 ? "" : "s")") {
                ForEach(state.approvals.drafts.prefix(Self.shown)) { d in
                    NeedsDraft(draft: d) { action in Task { await state.approvals.moderate(d, action, model: model) } }
                }
                if let r = state.approvals.result { Text(r).plFont(.footnote) }
                NavigationLink("All approvals") { ApprovalsView(model: model) }.frame(minHeight: PLMetric.touch)
            }
        }
    }

    @ViewBuilder private var toLook: some View {
        if !state.look.isEmpty {
            Section("To look at") {
                ForEach(state.look) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        NeedsMedia(url: item.url, video: ["mp4", "mov", "m4v"].contains(item.url.pathExtension.lowercased()))
                        Text(item.title).plFont(.footnote)
                    }
                }
            }
        }
    }

    @ViewBuilder private var comingUp: some View {
        if !state.ahead.isEmpty {
            Section("Coming up") {
                ForEach(state.ahead) { item in
                    HStack(alignment: .top) {
                        row(item.date < CalendarModel.today ? "exclamationmark.circle" : "calendar.badge.clock",
                            Self.when(item.date), item.title, lines: nil)
                        Spacer(minLength: 8)
                        Button("Done") { Task { await state.done(item, model: model) } }.buttonStyle(.bordered).frame(minHeight: PLMetric.touch)
                    }
                }
            }
        }
    }

    /// "2026-12-07" to "Mon, Dec 7"; today and anything past say so.
    private static func when(_ date: String) -> String {
        if date == CalendarModel.today { return "Today" }
        let read = DateFormatter()
        read.locale = Locale(identifier: "en_US_POSIX")
        read.dateFormat = "yyyy-MM-dd"
        guard let d = read.date(from: date) else { return date }
        let text = d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return date < CalendarModel.today ? "Overdue, \(text)" : text
    }

    @ViewBuilder private var messages: some View {
        if !state.support.isEmpty || !state.unread.isEmpty || !state.approvals.reports.isEmpty {
            Section("Waiting for an answer") {
                ForEach(state.support) { m in
                    NavigationLink { SupportView(model: model) } label: { row("envelope", m.name ?? "Support message", m.message ?? "") }
                }
                ForEach(state.unread) { t in
                    NavigationLink { InboxView(model: model) } label: { row("bubble.left", t.handle ?? "A member", t.last_body ?? "") }
                }
                if !state.approvals.reports.isEmpty {
                    NavigationLink { ApprovalsView(model: model) } label: { row("flag", "Reported posts", "\(state.approvals.reports.count) to look at") }
                }
            }
        }
    }

    @ViewBuilder private var hands: some View {
        if let b = state.board, !b.rows.isEmpty {
            Section {
                ForEach(Array(b.rows.enumerated()), id: \.offset) { _, r in
                    row(r.call ? "questionmark.circle" : "hand.raised", r.call ? "Your call" : "Your hands", r.text, lines: nil)
                }
                if let link = b.link { Link("Open the board", destination: link).frame(minHeight: PLMetric.touch) }
            } header: { Text("Your hands and your calls") } footer: { Text("From the board, \(b.pulled).") }
        }
    }

    @ViewBuilder private var today: some View {
        if !state.plan.isEmpty {
            Section("Today") {
                ForEach(state.plan) { t in
                    HStack(alignment: .top) {
                        row("calendar", t.time_pt ?? t.slot ?? "Today", t.title ?? "", lines: nil)
                        Spacer(minLength: 8)
                        Button("Done") { Task { await state.done(t, model: model) } }.buttonStyle(.bordered).frame(minHeight: PLMetric.touch)
                    }
                }
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ text: String, lines: Int? = 2) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(PLTone.accent).frame(width: 22).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).plFont(.callout, emphasized: true)
                if !text.isEmpty { Text(text).plFont(.footnote).foregroundStyle(.secondary).lineLimit(lines) }
            }
        }
    }
}

/// One draft, seen and heard here: the picture, or the video with its own sound, then Approve or Hold.
private struct NeedsDraft: View {
    let draft: ApprovalsModel.Draft
    let act: (String) -> Void
    @State private var acted = 0

    init(draft: ApprovalsModel.Draft, act: @escaping (String) -> Void) { self.draft = draft; self.act = act }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = draft.media_url, let url = URL(string: s), url.scheme == "https" {
                NeedsMedia(url: url, video: draft.media_type == "video", stop: acted)
            }
            Text([draft.platform?.capitalized, draft.title].compactMap { $0 }.joined(separator: " · ")).plFont(.callout, emphasized: true)
            if let c = draft.caption, !c.isEmpty { Text(c).plFont(.footnote).lineLimit(6) }
            HStack {
                Button("Approve") { acted += 1; act("approve") }.buttonStyle(.borderedProminent)
                Button("Hold") { acted += 1; act("hold") }.buttonStyle(.bordered)
            }
            .frame(minHeight: PLMetric.touch)
        }
    }
}

/// A picture, or a video that plays here with its sound. A change of `stop` pauses it.
private struct NeedsMedia: View {
    let url: URL
    let video: Bool
    var stop: Int
    @State private var player: AVPlayer?

    init(url: URL, video: Bool, stop: Int = 0) { self.url = url; self.video = video; self.stop = stop }

    var body: some View {
        Group {
            if video {
                if let player {
                    VideoPlayer(player: player).frame(height: 360)
                } else {
                    Button {
                        try? AVAudioSession.sharedInstance().setCategory(.playback)   // he hears it with the silent switch on
                        let p = AVPlayer(url: url)
                        player = p
                        p.play()
                    } label: { Label("Play with sound", systemImage: "play.circle.fill").frame(maxWidth: .infinity, minHeight: 120) }
                    .buttonStyle(.bordered)
                }
            } else {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.15).frame(height: 200) }
                    .frame(maxHeight: 360).frame(maxWidth: .infinity)
            }
        }
        .onChange(of: stop) { player?.pause() }
        .onDisappear { player?.pause() }
    }
}
