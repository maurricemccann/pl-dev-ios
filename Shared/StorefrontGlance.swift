import Foundation
import WidgetKit

/// What the Site widget shows, written by the app after it reads the shop and the congregation. Counts and words only:
/// no key, no session, no address.
struct StorefrontGlance: Codable, Equatable, Sendable {
    var pieces: Int
    var inStock: Int
    var fresh: [String]        // pieces that appeared since he last looked, at most three
    var held: Int?             // posts and comments waiting for him (only when he is signed in as the founder)
    var members: Int
    var updatedAt: Date
}

extension PLDevKinds {
    static let storefrontWidget = "com.psychedluxuries.dev.storefront"
}

extension SharedState {
    static func writeStorefront(_ g: StorefrontGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readStorefront()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "storefront")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.storefrontWidget) }
    }

    static func readStorefront() -> StorefrontGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "storefront") else { return nil }
        return try? JSONDecoder().decode(StorefrontGlance.self, from: data)
    }
}
