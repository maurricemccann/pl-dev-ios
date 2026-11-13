import SwiftUI
import UserNotifications

/// Shop: his side of psychedluxuries.com (sub-spec 9). Placeholder until its build.
@MainActor enum ShopSection: PLSection {
    static let manifest = SectionManifest(id: "shop", title: "Shop", symbol: "bag.fill")
    static func makeRoot(model: AppModel) -> AnyView { AnyView(ComingSection(model: model, title: "Shop", symbol: manifest.symbol, webPath: nil,
        webURL: "https://psychedluxuries.com/shop",
        points: ["Orders and the sales glance", "The catalogue as it stands: listed, unlisted, hidden",
                 "Each piece with its flat and its price", "New-order notifications"])) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

/// Congregation: the members' feed, wall and DMs (sub-spec 9). Placeholder until its build.
@MainActor enum CongregationSection: PLSection {
    static let manifest = SectionManifest(id: "congregation", title: "Congregation", symbol: "person.3.fill")
    static func makeRoot(model: AppModel) -> AnyView { AnyView(ComingSection(model: model, title: "Congregation", symbol: manifest.symbol, webPath: nil,
        webURL: "https://psychedluxuries.com/congregation",
        points: ["The feed and the wall, native", "Member DMs to you, with replies", "Moderation", "Notifications for new members and messages"])) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}
