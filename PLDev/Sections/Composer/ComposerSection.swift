import ActivityKit
import SwiftUI
import UserNotifications

/// Composer in full (his order 11-13): author a piece, wire each shot's graph by hand, browse the whole asset library, build the spec,
/// hand a render card to the house and watch it walk the board. Twin of pl-composer (`app/page.tsx`, `components/*`, `lib/*`); the same
/// spec text comes out of it. The one thing it never does is compute pixels: the renderer on the PC does that.
/// Sub-spec: `Plans/SPEC — PL DEV SUB-SPECS (S348).md` section 7.
@MainActor enum ComposerSection: PLSection {
    static let manifest = SectionManifest(id: "composer", title: "Composer", symbol: "film.stack", needsKeys: [], needsOrigins: ["composer"])
    static let state = ComposerModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(ComposerView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first, let room = ComposerRoom(rawValue: first) {
            if room == .piece, path.count > 1 { ComposerPieces.shared.open(path[1]) }   // pldev://section/composer/piece/<id>
            ComposerNav.shared.room = room
        }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        let before = state.lanes
        await state.load(model: model)
        await ComposerOutbox.shared.flush(model: model)
        var notify: [LocalNotice] = []
        if !before.isEmpty {
            for c in state.cards where before[c.id] != nil && before[c.id] != c.lane {
                notify.append(LocalNotice(id: "composer.\(c.id).\(c.lane)", title: "Composer", body: "\(c.title) moved to \(ComposerModel.label(c.lane)).",
                                          category: "composer", link: c.lane == "filed" ? .section(id: "curate", path: [], query: [:]) : .section(id: "composer", path: ["board"], query: [:])))
            }
        }
        await RenderLive.sync(state.cards)
        await ComposerSpotlight.index()
        let busy = state.cards.filter { $0.lane == "rendering" || $0.lane == "mixing" }.count
        return SectionRefresh(badge: busy > 0 ? busy : nil, notify: notify)
    }
}

/// The four areas, under the title as a segmented control (DESIGN 1). Each is also a case a link, Siri or Spotlight can land on by name.
enum ComposerRoom: String, CaseIterable, Identifiable {
    case piece, library, board, more
    var id: String { rawValue }
    var title: String { switch self { case .piece: return "Piece"; case .library: return "Library"; case .board: return "Board"; case .more: return "More" } }
    var line: String {
        switch self {
        case .piece: return "Shots, sources and each shot's graph"
        case .library: return "Every asset the index knows"
        case .board: return "The renders the house is making"
        case .more: return "Handbook, pieces, defaults"
        }
    }
    var symbol: String { switch self { case .piece: return "film.stack"; case .library: return "photo.stack"; case .board: return "square.grid.3x2"; case .more: return "ellipsis.circle" } }
}

@MainActor @Observable final class ComposerNav {
    static let shared = ComposerNav()
    var room: ComposerRoom?
}

// MARK: the render board

@MainActor @Observable final class ComposerModel {
    struct Card: Decodable, Identifiable, Equatable, Sendable {
        let id: String
        let piece: String?; let shot: String?; let look: String?; let path: String?; let bed: String?
        let created: String?; var lane: String
        let progress: String?; let file: String?; let note: String?; let at: String?
        var title: String { shot ?? id }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            id = try c.decode(String.self, forKey: .id)
            piece = try? c.decode(String.self, forKey: .piece); shot = try? c.decode(String.self, forKey: .shot); look = try? c.decode(String.self, forKey: .look)
            path = try? c.decode(String.self, forKey: .path); bed = try? c.decode(String.self, forKey: .bed); created = try? c.decode(String.self, forKey: .created)
            let raw = (try? c.decode(String.self, forKey: .lane)) ?? "sent"
            lane = raw == "rendered" ? "mixing" : raw           // the board's own id for Mixing is "rendered"
            progress = try? c.decode(String.self, forKey: .progress); file = try? c.decode(String.self, forKey: .file)
            note = try? c.decode(String.self, forKey: .note); at = try? c.decode(String.self, forKey: .at)
        }
        enum K: String, CodingKey { case id, piece, shot, look, path, bed, created, lane, progress, file, note, at }
        /// "412/832" as a fraction for the bar.
        var fraction: Double? {
            guard let p = progress else { return nil }
            let parts = p.split(separator: "/").compactMap { Double($0) }
            return parts.count == 2 && parts[1] > 0 ? min(1, parts[0] / parts[1]) : nil
        }
    }

    static let order = ["sent", "rendering", "mixing", "filed", "ruled", "failed"]
    static func label(_ id: String) -> String { id.capitalized }
    static func why(_ id: String) -> String {
        switch id {
        case "sent": return "The card is written; the house has not picked it up yet."
        case "rendering": return "In the render queue, one job at a time."
        case "mixing": return "Rendered; the bed goes on and the word check runs."
        case "filed": return "On /curate, unmarked. Rule it there."
        case "ruled": return "You marked it: keep, maybe or cut."
        default: return "The render or the mix stopped. The note says why."
        }
    }

    var cards: [Card] = []
    var pulled: String?
    var source: String?
    var failed = false
    var loading = false
    var lanes: [String: String] { Dictionary(cards.map { ($0.id, $0.lane) }, uniquingKeysWith: { a, _ in a }) }
    func count(_ lane: String) -> Int { cards.filter { $0.lane == lane }.count }

    func load(model: AppModel) async {
        struct Board: Decodable { let pulled: String?; let source: String?; let cards: [Card]? }
        guard let http = model.http, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let d = try await http.send(RequestPlan(origin: "composer", path: "api/board"))
            let b = try JSONDecoder().decode(Board.self, from: d)
            cards = b.cards ?? []; pulled = b.pulled; source = b.source; failed = false
            publish()
        } catch { failed = true }
    }

    /// The widget's numbers (names and counts only).
    func publish() {
        let newest = cards.first
        ComposerGlanceWriter.publishBoard(sent: count("sent"), rendering: count("rendering"), mixing: count("mixing"), filed: count("filed"), ruled: count("ruled"),
                                          failed: count("failed"), newestShot: newest?.title, newestLane: newest?.lane)
    }
}

// MARK: Lock Screen

/// A render followed on the Lock Screen: started on his tap (foreground), moved as the card changes lane, ended when it is filed, ruled or failed.
@MainActor enum RenderLive {
    static func follow(_ c: ComposerModel.Card) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !Activity<RenderAttributes>.activities.contains(where: { $0.attributes.cardID == c.id }) else { return }
        _ = try? Activity.request(attributes: RenderAttributes(cardID: c.id, shot: c.title),
                                  content: .init(state: .init(lane: c.lane, progress: c.progress), staleDate: .now.addingTimeInterval(2 * 3600)))
    }
    static func following(_ c: ComposerModel.Card) -> Bool { Activity<RenderAttributes>.activities.contains { $0.attributes.cardID == c.id } }

    nonisolated static func sync(_ cards: [ComposerModel.Card]) async {   // off the main actor: Activity is not Sendable
        for a in Activity<RenderAttributes>.activities {
            guard let c = cards.first(where: { $0.id == a.attributes.cardID }) else { await a.end(nil, dismissalPolicy: .immediate); continue }
            let s = RenderAttributes.ContentState(lane: c.lane, progress: c.progress)
            if ["filed", "ruled", "failed"].contains(c.lane) { await a.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(900))) }
            else if a.content.state != s { await a.update(.init(state: s, staleDate: .now.addingTimeInterval(2 * 3600))) }
        }
    }
}
