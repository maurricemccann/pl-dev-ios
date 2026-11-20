import SwiftUI
import UserNotifications

/// The rooms of the curves library that had no native home (`Plans/SPEC — CURVES LIBRARY NATIVE IN PL DEV (S350).md`).
/// Its own section; each room is a file in this folder. No network, no keys: a room that needs data says so itself.
@MainActor enum CurvesLibrarySection: PLSection {
    static let manifest = SectionManifest(id: "curveslibrary", title: "Curves Library", symbol: "scribble.variable", needsKeys: [], needsOrigins: [])

    static func makeRoot(model: AppModel) -> AnyView { AnyView(CurvesLibraryRooms()) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

/// The section's list of rooms.
private struct CurvesLibraryRooms: View {
    var body: some View {
        List {
            NavigationLink { PrivateBoardRoom() } label: {
                Label("Private board", systemImage: "chart.line.uptrend.xyaxis").frame(minHeight: 44)
            }
            // MERGE POINT: the second room, CurvesPackRoom (the Pack, built by the pack lane), gets its row here at merge.
            // Not referenced in this branch so it compiles alone.
        }
        .gScreen()
        .navigationTitle("Curves Library")
    }
}
