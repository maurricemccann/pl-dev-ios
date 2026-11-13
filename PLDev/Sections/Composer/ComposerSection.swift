import ActivityKit
import SwiftUI
import UserNotifications

/// Composer: the render Board (Sent, Rendering, Mixing, Filed, Ruled, Failed), read from Composer's own worker.
/// The graph editor and the render stay on the laptop (sub-spec 7). A card moving lane raises a notice.
@MainActor enum ComposerSection: PLSection {
    static let manifest = SectionManifest(id: "composer", title: "Composer", symbol: "film.stack", needsKeys: [], needsOrigins: ["composer"])
    static let state = ComposerModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(ComposerView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }

    static func refresh(model: AppModel) async -> SectionRefresh {
        let before = state.lanes
        await state.load(model: model)
        var notify: [LocalNotice] = []
        if !before.isEmpty {
            for c in state.cards where before[c.id] != nil && before[c.id] != c.lane {
                notify.append(LocalNotice(id: "composer.\(c.id).\(c.lane)", title: "Composer", body: "\(c.shot ?? c.id) moved to \(c.lane.capitalized).",
                                          category: "composer", link: .section(id: "composer", path: [], query: [:])))
            }
        }
        await RenderLive.sync(state.cards)
        let rendering = state.cards.filter { $0.lane == "rendering" || $0.lane == "mixing" }.count
        return SectionRefresh(badge: rendering > 0 ? rendering : nil, notify: notify)
    }
}

@MainActor @Observable final class ComposerModel {
    struct Card: Decodable, Identifiable, Equatable, Sendable {
        let id: String; let piece: String?; let shot: String?; let look: String?; let lane: String
        let progress: String?; let file: String?; let note: String?; let created: String?
    }
    static let order = ["sent", "rendering", "mixing", "filed", "ruled", "failed"]
    var cards: [Card] = []
    var pulled: String?
    var failed = false
    var lanes: [String: String] { Dictionary(cards.map { ($0.id, $0.lane) }, uniquingKeysWith: { a, _ in a }) }

    func load(model: AppModel) async {
        struct Board: Decodable { let pulled: String?; let cards: [Card]? }
        guard let http = model.http else { return }
        do {
            let b = try JSONDecoder().decode(Board.self, from: try await http.send(RequestPlan(origin: "composer", path: "api/board")))
            cards = b.cards ?? []; pulled = b.pulled; failed = false
        } catch { failed = true }
    }
}

struct ComposerView: View {
    let model: AppModel
    let state: ComposerModel

    var body: some View {
        List {
            Section {
                NavigationLink { ComposerPiecesView(model: model) } label: { Label("Pieces", systemImage: "film.stack") }
                NavigationLink { AssetLibraryView(model: model) } label: { Label("Asset library", systemImage: "photo.stack") }
            } footer: { Text("Author a piece here; the graph and the render run on the laptop.") }
            if state.failed { Text("Could not read the board. Pull to try again.").foregroundStyle(.secondary) }
            if let p = state.pulled { Text("Board pulled \(p)").font(.caption).foregroundStyle(.secondary) }
            ForEach(ComposerModel.order, id: \.self) { lane in
                let cards = state.cards.filter { $0.lane == lane }
                if !cards.isEmpty {
                    Section("\(lane.capitalized) · \(cards.count)") {
                        ForEach(cards) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.shot ?? c.id).font(.headline)
                                HStack(spacing: 8) {
                                    if let p = c.piece { Text(p) }
                                    if let l = c.look { Text("· \(l)") }
                                    if let pr = c.progress { Text("· \(pr)").monospacedDigit() }
                                }.font(.caption).foregroundStyle(.secondary)
                                if let f = c.file { Text(f).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                if let n = c.note, !n.isEmpty { Text(n).font(.caption) }
                            }
                            .contextMenu {
                                if let f = c.file { Button("Copy file name") { UIPasteboard.general.string = f } }
                                if c.lane == "sent" || c.lane == "rendering" || c.lane == "mixing" {
                                    Button("Follow on the Lock Screen", systemImage: "lock.iphone") { RenderLive.follow(c) }
                                }
                            }
                        }
                    }
                }
            }
            if state.cards.isEmpty && !state.failed { Text("No cards on the board.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Composer")
        .refreshable { await state.load(model: model) }
        .task { await state.load(model: model); await RenderLive.sync(state.cards) }
    }
}

/// A render followed on the Lock Screen: started on his tap (foreground), moved as the card changes lane, ended when it is filed, ruled or failed.
@MainActor enum RenderLive {
    static func follow(_ c: ComposerModel.Card) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !Activity<RenderAttributes>.activities.contains(where: { $0.attributes.cardID == c.id }) else { return }
        _ = try? Activity.request(attributes: RenderAttributes(cardID: c.id, shot: c.shot ?? c.id),
                                  content: .init(state: .init(lane: c.lane, progress: c.progress), staleDate: .now.addingTimeInterval(2 * 3600)))
    }

    nonisolated static func sync(_ cards: [ComposerModel.Card]) async {   // off the main actor: Activity is not Sendable
        for a in Activity<RenderAttributes>.activities {
            guard let c = cards.first(where: { $0.id == a.attributes.cardID }) else { await a.end(nil, dismissalPolicy: .immediate); continue }
            let s = RenderAttributes.ContentState(lane: c.lane, progress: c.progress)
            if ["filed", "ruled", "failed"].contains(c.lane) { await a.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(900))) }
            else if a.content.state != s { await a.update(.init(state: s, staleDate: .now.addingTimeInterval(2 * 3600))) }
        }
    }
}
