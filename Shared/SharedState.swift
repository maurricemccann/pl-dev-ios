import Foundation
import WidgetKit

/// The kinds the widget extension registers, named once so the app can reload them.
enum PLDevKinds {
    static let snapshotWidget = "com.psychedluxuries.dev.snapshot"
    static let homeControl = "com.psychedluxuries.dev.control.home"
}

/// What the app tells the widgets. It never holds a key or an address.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var inboxCount: Int
    var badges: [String: Int]
    var statusLine: String
}

/// The small state the app shares with its extensions through an App Group.
/// A build signed without the group has no shared store: writes do nothing and reads return nil.
enum SharedState {
    static let baseGroup = "group.com.psychedluxuries.dev"

    /// The group this install can really open, or nil. Some signers rename the group and list the new name in Info.plist.
    static let groupID: String? = {
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension == "appex" {
            let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let app = Bundle(url: appURL) { bundles.append(app) }
        }
        var candidates: [String] = []
        for bundle in bundles {
            let listed = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
            candidates += listed.filter { $0.hasPrefix(SharedState.baseGroup) }
        }
        candidates.append(SharedState.baseGroup)
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    static var isAvailable: Bool { groupID != nil }

    /// The group's folder, where the shared inbox keeps its files.
    static var containerURL: URL? {
        guard let groupID else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private static var store: UserDefaults? {
        guard let groupID else { return nil }
        return UserDefaults(suiteName: groupID)
    }

    /// Redraws the widget only when something other than the time changed.
    static func writeSnapshot(_ s: WidgetSnapshot) {
        guard let store, let data = try? JSONEncoder().encode(s) else { return }
        var before = readSnapshot()
        before?.updatedAt = s.updatedAt
        store.set(data, forKey: "snapshot")
        if before != s {
            WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.snapshotWidget)
        }
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let data = store?.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Stores the keyless copy only, whatever it is handed.
    static func writePublicConfig(_ c: PLDevConfig) {
        guard let store, let data = try? JSONEncoder().encode(c.publicCopy) else { return }
        store.set(data, forKey: "publicConfig")
    }

    static func readPublicConfig() -> PLDevConfig? {
        guard let data = store?.data(forKey: "publicConfig") else { return nil }
        return try? JSONDecoder().decode(PLDevConfig.self, from: data)
    }

    /// Removes the shared copy when the owner forgets the config.
    static func clearPublicConfig() {
        store?.removeObject(forKey: "publicConfig")
    }
}
