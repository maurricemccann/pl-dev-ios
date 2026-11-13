import AppIntents
import CoreSpotlight
import SwiftUI

// The Congregation's system add-ons, built to the same guidance as House: an App Shortcut that says every count, Spotlight through
// IndexedEntity + OpenIntent, deep links by room name (pldev://section/congregation/<room>, and /member/<handle>).

enum CongregationRoom: String, CaseIterable, Identifiable, Hashable {
    case stream, room, members, me, activity, messages, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .stream: return "The stream"; case .room: return "The room"; case .members: return "Members"; case .me: return "Your page"
        case .activity: return "Activity"; case .messages: return "Messages to the Founder"; case .profile: return "Your profile"
        }
    }

    @MainActor @ViewBuilder func view(_ model: AppModel, state: CongregationModel) -> some View {
        switch self {
        case .activity: ActivityView()
        case .messages: MessagesView()
        case .profile: if let me = SiteAccount.shared.me { ProfileEditView(me: me) } else { EmptyNote(symbol: "person.crop.circle", title: "Sign in first", detail: "Your profile is on your page, after you sign in.") }
        default: EmptyView()   // the four tabs are not pushed
        }
    }
}

@MainActor private func congregationReady() async throws -> Void {
    await AppModel.shared.restoreIfNeeded()
    guard Site.base != nil else { throw Site.Problem.notSetUp }
}

struct CongregationStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "What's in the Congregation"
    static let description: IntentDescription? = "Says how many members there are and, once you are signed in, what waits for your word and what is new."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await congregationReady()
        await SiteAccount.shared.refresh()
        let members = (try? await Site.get("api/members/directory", DirectoryReply.self))?.members.count ?? 0
        var line = "\(members) members are listed."
        var held: Int?
        if SiteAccount.shared.isFounder, let room = try? await Site.get("api/congregation/feed", RoomReply.self) {
            let n = room.posts.filter { $0.status == "pending" }.count + room.posts.reduce(0) { $0 + $1.comments.filter { $0.status == "pending" }.count }
            held = n
            line += n == 0 ? " Nothing is waiting for your word." : " \(n) posts and answers are waiting for your word."
        }
        if SiteAccount.shared.signedIn, let a = try? await Site.get("api/notifications", ActivityReply.self) {
            line += a.unread == 0 ? " No new activity." : " \(a.unread) new reactions, answers or follows."
        } else if !SiteAccount.shared.signedIn { line += " You are not signed in on this phone." }
        StorefrontGlanceWriter.publishCongregation(held: held, members: members)
        return .result(dialog: "\(line)")
    }
}

/// Opens a Congregation room. Also what Spotlight runs when he picks a Congregation result.
struct OpenCongregationRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Congregation Room"
    @Parameter(title: "Room") var target: CongregationRoomEntity

    init() {}
    init(target: CongregationRoomEntity) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "congregation", path: [target.id], query: [:])) }
        return .result()
    }
}

struct CongregationRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Congregation Room"
    static let defaultQuery = CongregationRoomQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "Congregation") }

    static var all: [CongregationRoomEntity] { CongregationRoom.allCases.map { CongregationRoomEntity(id: $0.rawValue, title: $0.title) } }
}

struct CongregationRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CongregationRoomEntity] { CongregationRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [CongregationRoomEntity] { CongregationRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [CongregationRoomEntity] { CongregationRoomEntity.all }
}

enum CongregationSpotlight {
    static func index() async {
        try? await CSSearchableIndex(name: "congregation").indexAppEntities(CongregationRoomEntity.all)
    }
}
