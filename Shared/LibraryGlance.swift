import Foundation
import WidgetKit

/// What the Curve Library widget shows: the curate queue and the newest batch. Counts only.
struct LibraryGlance: Codable, Equatable, Sendable {
    var unmarked: Int
    var kept: Int
    var batch: String?
    var batchNew: Int
    var updatedAt: Date
}

extension PLDevKinds {
    static let libraryWidget = "com.psychedluxuries.dev.library"
}

extension SharedState {
    static func writeLibrary(_ g: LibraryGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readLibrary()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "library")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.libraryWidget) }
    }

    static func readLibrary() -> LibraryGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "library") else { return nil }
        return try? JSONDecoder().decode(LibraryGlance.self, from: data)
    }
}
