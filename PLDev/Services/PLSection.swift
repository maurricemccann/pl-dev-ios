import SwiftUI
import UserNotifications

/// One section on the home grid, as the UI sees it: what it declared, whether the loaded config lets it run, and how to build its screen.
struct SectionEntry: Identifiable {
    let manifest: SectionManifest
    let readiness: Readiness
    let makeRoot: @MainActor () -> AnyView
    var badge: Int?
    var id: String { manifest.id }
}

/// The section contract: every future section conforms, and is added to `SectionRegistry.all`. Nothing else in the shell changes.
@MainActor protocol PLSection {
    static var manifest: SectionManifest { get }
    static func makeRoot(model: AppModel) -> AnyView
    static func probes(model: AppModel) -> [ProbeModel.Item]             // may be empty
    static func settingsRows(model: AppModel) -> AnyView?                // may be nil
    static func notificationCategories() -> Set<UNNotificationCategory>  // may be empty
    static func handle(link: DeepLink, model: AppModel) -> Bool
    static func refresh(model: AppModel) async -> SectionRefresh          // called by the poller and background refresh
}

/// What a section reports after a refresh: its badge, and any notices to raise.
struct SectionRefresh {
    var badge: Int?
    var notify: [LocalNotice]
}

/// A local notification a section wants shown. `category` doubles as the notice's type for the per-type switch in Settings.
struct LocalNotice {
    var id: String
    var title: String
    var body: String
    var category: String?
    var link: DeepLink?
}

extension Readiness {
    /// One quiet line for a tile or an alert; nil when the section can run.
    var plNote: String? {
        switch self {
        case .ready: return nil
        case .missingKeys(let names): return names.count == 1 ? "Needs a key" : "Needs \(names.count) keys"
        case .missingOrigins(let names): return names.count == 1 ? "Needs an address" : "Needs \(names.count) addresses"
        case .notListed: return "Not in your config"
        }
    }

    /// The full sentence, naming what the config lacks. Names only, never values.
    var plDetail: String? {
        switch self {
        case .ready: return nil
        case .missingKeys(let names): return "Your config has no key named " + names.joined(separator: ", ") + ". Add it to the config file and load it again."
        case .missingOrigins(let names): return "Your config has no address named " + names.joined(separator: ", ") + ". Add it to the config file and load it again."
        case .notListed: return "Your config does not list this section."
        }
    }

    var isReady: Bool { self == .ready }
}
