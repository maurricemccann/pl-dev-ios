import SwiftUI
import UserNotifications

/// Task Town, first cut (sub-spec 6): the same data as the pixel town (gallery /api/town) as a native list:
/// where the live session is working now, its recent path, the Roadmap's townspeople, and visitors.
/// The SpriteKit town with his baked sprites is its own later phase.
@MainActor enum TownSection: PLSection {
    static let manifest = SectionManifest(id: "town", title: "Town", symbol: "building.2", needsKeys: ["vault"], needsOrigins: ["gallery"])
    static let state = TownModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(TownView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.load(model: model)
        return SectionRefresh(badge: nil, notify: [])
    }
}

@MainActor @Observable final class TownModel {
    struct Step: Decodable, Hashable { let k: String?; let a: String?; let t: String? }
    struct Live: Decodable { let kind: String?; let area: String?; let tool: String?; let age_s: Int?; let calls: Int?; let hist: [Step]? }
    struct Person: Decodable, Identifiable { let title: String?; let state: String?; let n: Int?; var id: String { "\(n ?? 0)-\(title ?? "")" } }
    struct Visitor: Decodable, Identifiable { let name: String?; let at: String?; var id: String { (name ?? "") + (at ?? "") } }
    struct Town: Decodable { let working: Bool?; let live: Live?; let tasks: [Person]?; let visitors: [Visitor]? }

    var town: Town?
    var failed = false

    func load(model: AppModel) async {
        guard let http = model.http else { return }
        do {
            town = try JSONDecoder().decode(Town.self, from: try await http.send(RequestPlan(origin: "gallery", path: "api/town")))
            failed = false
        } catch { failed = true }
    }
}

struct TownView: View {
    let model: AppModel
    let state: TownModel

    private func building(_ area: String?) -> String {
        switch area ?? "" {
        case "vault", "studio": return "STUDIO"
        case "forge", "terminal": return "TERMINAL"
        case "library": return "LIBRARY"
        case "web", "lookout": return "LOOKOUT"
        case "post", "cloud": return "POST"
        case "shop", "bank": return "SHOP"
        default: return (area ?? "?").uppercased()
        }
    }

    var body: some View {
        List {
            if state.failed { Text("Could not reach the town. Pull to try again.").foregroundStyle(.secondary) }
            if let live = state.town?.live {
                Section("Now") {
                    LabeledContent("Session", value: state.town?.working == true ? "Working" : "Quiet")
                    LabeledContent("At", value: building(live.area))
                    if let t = live.tool { LabeledContent("Tool", value: t) }
                    if let s = live.age_s { LabeledContent("Last step", value: s < 90 ? "\(s) s ago" : "\(s / 60) min ago") }
                    if let c = live.calls { LabeledContent("Steps today", value: "\(c)") }
                }
                if let hist = live.hist, !hist.isEmpty {
                    Section("Recent path") {
                        ForEach(Array(hist.prefix(8).enumerated()), id: \.offset) { _, s in
                            Text("\(building(s.a)) · \(s.k ?? "")").font(.callout)
                        }
                    }
                }
            }
            Section("Townspeople (the Roadmap)") {
                let tasks = state.town?.tasks ?? []
                if tasks.isEmpty { Text("No one in town.").foregroundStyle(.secondary) }
                ForEach(tasks) { t in
                    LabeledContent(t.title ?? "", value: t.state ?? "")
                }
            }
            if let v = state.town?.visitors, !v.isEmpty {
                Section("Visitors") { ForEach(v) { Text($0.name ?? "visitor") } }
            }
        }
        .navigationTitle("Town")
        .refreshable { await state.load(model: model) }
        .task {
            while !Task.isCancelled {   // the web polls every 10 s; so does this, only while it is on screen
                await state.load(model: model)
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
