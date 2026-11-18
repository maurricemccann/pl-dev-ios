import Foundation

/// Progress on disk. Every change goes through `commit`, which writes the whole file atomically (temp file then rename), so a kill
/// mid-write leaves the last good save. The runtime also calls `flush` when the app leaves the foreground.
@MainActor final class PLWSaveStore {
    private(set) var save: PLWSave
    private(set) var existed: Bool
    private let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PLWorld", isDirectory: true).appendingPathComponent("save.json")
    }

    init(url: URL = PLWSaveStore.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url) {
            if let s = try? JSONDecoder().decode(PLWSave.self, from: data), s.schemaVersion >= 1 {
                save = s; existed = true; return
            }
            // unreadable (a newer build wrote it, or it is damaged): keep it aside, never overwrite it silently
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bad"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bad"))
            AppModel.shared.debug.note("plworld", "save unreadable; kept as save.json.bad, starting fresh")
        }
        save = PLWSave(); existed = false
    }

    func commit(_ edit: (inout PLWSave) -> Void) {
        edit(&save)
        flush()
    }

    func flush() {
        do {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            try enc.encode(save).write(to: url, options: .atomic)
            existed = true
        } catch {
            AppModel.shared.debug.note("plworld", "save failed: \(error.localizedDescription)")
        }
    }

    func reset(hero: PLWHero) { save = PLWSave(); save.hero = hero; flush() }
}
