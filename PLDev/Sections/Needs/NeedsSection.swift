import AVKit
import SwiftUI
import UserNotifications

// "Needs you" (his ask 11-25, S353: "A founders reminder app in pl dev ... anything that needs my attention my hands or my eyes").
// One screen over what the app already reads: drafts to look at (played here, with sound), messages waiting, the board's rows
// for his hands and his calls, and today's plan. Nothing new is stored. Deadlines and subscriptions come next.

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
        let n = state.support.count + state.unread.count
        return SectionRefresh(badge: n > 0 ? n : nil, notify: [])
    }
}

@MainActor @Observable final class NeedsModel {
    var support: [SupportView.Message] = []
    var unread: [InboxView.Thread] = []
    var board: PerformancePage.BoardRows?
    var plan: [HouseModel.PlanTask] = []
    var loaded = false
    var problem: String?
    /// Drafts, and the approve and hold calls, are the Approvals room's own.
    let approvals = ApprovalsModel()

    func loadMessages(model: AppModel) async {
        if let rows = try? await Console.q("contact", [SupportView.Message].self, model: model) { support = rows.filter { $0.status != "resolved" } }
        if let out = try? await Console.get("api/dm/threads", InboxView.Out.self, model: model) { unread = (out.threads ?? []).filter { ($0.unread ?? 0) > 0 } }
    }

    func load(model: AppModel) async {
        await approvals.load(model: model)
        await loadMessages(model: model)
        if let b = await PerformancePage.readBoard(model) { board = b }
        let day = try? await Console.get("api/day-plan", HouseModel.Plan.self, model: model)
        if let day { plan = (day.tasks ?? []).filter { $0.status != "done" && $0.status != "skipped" } }
        // an empty screen must not read as "nothing waits" when nothing answered
        problem = approvals.result != nil || board == nil || day == nil ? "Some lists did not answer, so this may not be everything. Pull to try again." : nil
        loaded = true
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
            messages
            hands
            today
        }.listRowBackground(PLRowGround()) }
        .plGround()
        .plScreenTitle("Needs you")
        .task { await state.load(model: model) }
        .refreshable { await state.load(model: model) }
        .onDisappear { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private var nothing: Bool {
        state.approvals.drafts.isEmpty && state.approvals.reports.isEmpty && state.support.isEmpty && state.unread.isEmpty
            && (state.board?.rows.isEmpty ?? true) && state.plan.isEmpty
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
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            media
            Text([draft.platform?.capitalized, draft.title].compactMap { $0 }.joined(separator: " · ")).plFont(.callout, emphasized: true)
            if let c = draft.caption, !c.isEmpty { Text(c).plFont(.footnote).lineLimit(6) }
            HStack {
                Button("Approve") { player?.pause(); act("approve") }.buttonStyle(.borderedProminent)
                Button("Hold") { player?.pause(); act("hold") }.buttonStyle(.bordered)
            }
            .frame(minHeight: PLMetric.touch)
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private var media: some View {
        if let s = draft.media_url, let url = URL(string: s), url.scheme == "https" {
            if draft.media_type == "video" {
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
    }
}
