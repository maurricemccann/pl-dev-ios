import Foundation
import Observation

/// The Backend page's tiles (Plans/SPEC — PL DEV BACKEND PAGE (S348)). The three built-ins plus the ones he adds, kept in a file on this
/// phone only (premise 3). The matching rules live in PLDevCore's `BackendTemplates` and are tested in CI.
@MainActor @Observable final class BackendStore {
    static let shared = BackendStore()

    private(set) var tiles: [BackendTemplate]
    private let file: URL

    private init() {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        file = dir.appendingPathComponent("backend-tiles.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([BackendTemplate].self, from: data) {
            tiles = saved
        } else {
            tiles = BackendTemplates.builtIn
        }
    }

    /// Adds a tile, or fills in a built-in that had no address yet (Horizon). Returns the line to show him.
    func add(_ t: BackendTemplate) -> String {
        if let i = tiles.firstIndex(where: { $0.id == t.id }) {
            if !tiles[i].isReady && t.isReady {
                tiles[i].startURL = t.startURL
                save()
                return "\(t.name) is set."
            }
            return "\(t.name) is already there."
        }
        tiles.append(t)
        save()
        return "\(t.name) added."
    }

    func remove(_ id: String) {
        tiles.removeAll { $0.id == id }
        save()
    }

    /// Brings every built-in back (keeping any address already set) and keeps the tiles he added.
    func reset() {
        var out = BackendTemplates.builtIn.map { b in tiles.first(where: { $0.id == b.id }) ?? b }
        out += tiles.filter { t in !BackendTemplates.builtIn.contains { $0.id == t.id } }
        tiles = out
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tiles) { try? data.write(to: file, options: .atomic) }
    }
}
