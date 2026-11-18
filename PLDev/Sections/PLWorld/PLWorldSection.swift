import SwiftUI
import UserNotifications

/// PL World, native: his open world and the Curve Who's eleven-page ring, in RealityKit. Its own tile (his ruling 11-17).
/// The lane's plan and the frozen contract are in LANES-plworld.md and Contract/PLWContract.swift.
@MainActor enum PLWorldSection: PLSection {
    static let manifest = SectionManifest(id: "plworld", title: "PL World", symbol: "globe.europe.africa", needsKeys: [], needsOrigins: [])

    static func makeRoot(model: AppModel) -> AnyView { AnyView(PLWorldHome()) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

/// The lane replaces this with the title screen and the hero pick (lane A).
struct PLWorldHome: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("PL World").font(.largeTitle.weight(.semibold))
            Text("Building.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
