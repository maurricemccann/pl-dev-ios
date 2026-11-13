import SwiftUI
import TipKit
import UserNotifications

/// Congregation: the members' side of psychedluxuries.com as a native app (lane A, his order 11-13). The public stream, the
/// members' room (posts, reactions, answers, and his moderation), the members, and the signed-in account's own page. It speaks to
/// the same routes the website does. His sign-in is the site's email and password; the session lives in the Keychain.
@MainActor enum CongregationSection: PLSection {
    static let manifest = SectionManifest(id: "congregation", title: "Congregation", symbol: "person.3.fill", needsKeys: [], needsOrigins: ["site"])
    static let state = CongregationModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(CongregationView(model: model, state: state)) }

    static func probes(model: AppModel) -> [ProbeModel.Item] {
        [ProbeModel.Item(id: "congregation.room", title: "Congregation room", detail: "Reads the members' room and the stream, and says whether the saved sign-in is still good.", result: .untested, run: {
            do {
                let room = try await Site.get("api/congregation/feed", RoomReply.self)
                let stream = try await Site.get("api/congregation/stream", StreamProbe.self, query: ["limit": "1"])
                await SiteAccount.shared.refresh()
                let who = SiteAccount.shared.signedIn ? (SiteAccount.shared.isFounder ? "signed in as the founder" : "signed in") : "not signed in"
                return .pass("\(room.posts.count) room posts, \(stream.total ?? 0) in the stream, \(who)")
            } catch { return .fail(error.localizedDescription) }
        })]
    }

    static func settingsRows(model: AppModel) -> AnyView? { AnyView(CongregationSettingsRows()) }
    /// No buttons on these notices: moderating is a judgement on each item, so the notice opens the room. Declaring them gives each a switch in Settings.
    static func notificationCategories() -> Set<UNNotificationCategory> {
        [UNNotificationCategory(identifier: "congregation.held", actions: [], intentIdentifiers: []),
         UNNotificationCategory(identifier: "congregation.activity", actions: [], intentIdentifiers: [])]
    }

    static func handle(link: DeepLink, model: AppModel) -> Bool {
        guard case .section(_, let path, _) = link, let first = path.first else { return true }
        if let tab = CongregationModel.Tab(rawValue: first) { state.tab = tab }
        else if let room = CongregationRoom(rawValue: first) { state.open(room) }
        else if first == "member", path.count > 1 { state.tab = .members; state.memberHandle = path[1] }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        await SiteAccount.shared.refresh()
        var held: Int?
        var notify: [LocalNotice] = []
        if SiteAccount.shared.isFounder, let room = try? await Site.get("api/congregation/feed", RoomReply.self) {
            let n = room.posts.filter { $0.status == "pending" }.count + room.posts.reduce(0) { $0 + $1.comments.filter { $0.status == "pending" }.count }
            held = n
            if n > 0, n != state.lastHeld {
                notify.append(LocalNotice(id: "congregation.held", title: "Waiting for you in the room", body: n == 1 ? "One post or answer is waiting for your word." : "\(n) posts and answers are waiting for your word.",
                                          category: "congregation.held", link: .section(id: "congregation", path: ["room"], query: [:])))
            }
            state.lastHeld = n
        }
        if SiteAccount.shared.signedIn, let a = try? await Site.get("api/notifications", ActivityReply.self), a.visibleUnread > 0, a.visibleUnread != state.lastUnread {
            notify.append(LocalNotice(id: "congregation.activity", title: "New in your Congregation", body: a.visibleUnread == 1 ? "One new reaction, answer or follow." : "\(a.visibleUnread) new reactions, answers or follows.",
                                      category: "congregation.activity", link: .section(id: "congregation", path: ["me"], query: [:])))
            state.lastUnread = a.visibleUnread
        } else if SiteAccount.shared.signedIn { state.lastUnread = 0 }
        let members = (try? await Site.get("api/members/directory", DirectoryReply.self))?.members.count ?? 0
        StorefrontGlanceWriter.publishCongregation(held: held, members: members)
        return SectionRefresh(badge: (held ?? 0) > 0 ? held : nil, notify: notify)
    }
}

struct StreamProbe: Decodable { let total: Int? }

@MainActor @Observable final class CongregationModel {
    enum Tab: String, CaseIterable, Identifiable {
        case stream, room, members, me
        var id: String { rawValue }
        var title: String { self == .me ? "Me" : rawValue.capitalized }
    }

    var tab: Tab = .stream
    var room: CongregationRoom?
    var memberHandle: String?
    /// The owner's tab inside Me to land on (Boards, Settings, Games), read once by the member hub.
    var hubTab: String?
    var tick = 0
    var lastHeld = 0
    var lastUnread = 0

    func open(_ r: CongregationRoom) {
        if let t = Tab(rawValue: r.rawValue) { tab = t; room = nil; return }
        switch r {
        case .boards: tab = .me; hubTab = "Boards"
        case .games: tab = .me; hubTab = "Games"
        case .settings, .profile: tab = .me; hubTab = "Settings"
        default: tab = .me; room = r
        }
    }
}

struct CongregationView: View {
    let model: AppModel
    @Bindable var state: CongregationModel
    @State private var stream = StreamModel(kind: nil)

    var body: some View {
        Group {
            switch state.tab {
            case .stream: StreamTabView(stream: stream, state: state)
            case .room: RoomTabView(state: state)
            case .members: MembersTabView(state: state)
            case .me: AccountTabView(state: state)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SiteTabs(titles: CongregationModel.Tab.allCases.map(\.title), index: Binding(
                get: { CongregationModel.Tab.allCases.firstIndex(of: state.tab) ?? 0 },
                set: { state.tab = CongregationModel.Tab.allCases[$0] }))
        }
        .background { SiteGround() }
        .navigationTitle("Congregation")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.select, trigger: state.tab)
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .navigationDestination(item: $state.room) { room in room.view(model, state: state) }
        .navigationDestination(item: $state.memberHandle) { handle in MemberView(handle: handle, state: state) }
        .task { await SiteAccount.shared.refresh() }
    }
}

/// The Congregation's own rows in Settings: the signed-in state.
struct CongregationSettingsRows: View {
    private let account = SiteAccount.shared

    var body: some View {
        Group {
            LabeledContent {
                Text(account.signedIn ? (account.me?.handle ?? "Signed in") : "Not signed in").foregroundStyle(.secondary)
            } label: {
                SettingsLabel("Site account", "person.crop.circle", IOS27.SystemColors.indigo)
            }
            ForEach(BellKinds.all, id: \.key) { kind in
                Toggle(isOn: Binding(get: { BellKinds.shows(kind.key) }, set: { UserDefaults.standard.set($0, forKey: "pldev.bell." + kind.key) })) {
                    SettingsLabel(kind.label, "bell", Color(uiColor: .systemGray))
                }
            }
            Text("The activity list and its notice show these kinds. News that a post went live or was removed always reaches you.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tips

struct RoomSwipeTip: Tip {
    var title: Text { Text("Your word on each one") }
    var message: Text? { Text("Approve or remove what is waiting with the buttons under it. Touch and hold a post to copy it or open its author.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
