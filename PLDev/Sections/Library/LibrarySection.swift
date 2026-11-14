import SwiftUI
import UserNotifications

/// The index and the marks, loaded once and shared by Library and Curate. A failed marks load is an error, never "nothing marked".
@MainActor @Observable final class LibraryData {
    static let shared = LibraryData()
    private(set) var items: [LibraryItem] = []
    var marks: [String: TasteMark] = [:]
    private(set) var marksLoaded = false
    private(set) var loading = false
    var notSaved = 0
    /// His own tags (/api/tags, a table of their own), by vault id. A failed load leaves the last ones.
    var tags: [String: [String]] = [:]
    /// Each piece's batch: its cloud batch, or the date stamp in its own file name (both start YYYYMMDD, so one compare orders all).
    private(set) var batchOf: [String: String] = [:]
    private(set) var unrenderable: Set<String> = []

    private var running: Task<Void, Error>?

    /// One load at a time; a caller that arrives while one runs waits for it and gets its answer (Library, Curate and the
    /// widget refresh all ask at once on launch; the second used to return at once with nothing loaded).
    func load(model: AppModel, force: Bool = false) async throws {
        if let running { return try await running.value }
        let t = Task { try await self.loadNow(model: model, force: force) }
        running = t
        defer { running = nil }
        try await t.value
    }

    private func loadNow(model: AppModel, force: Bool) async throws {
        guard let http = model.http else { throw URLError(.notConnectedToInternet) }
        loading = true; defer { loading = false }
        await MarkOutbox.flush(model: model)   // marks made offline go first, so the fresh marks below include them
        if items.isEmpty || force {
            URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)   // 9.5k tiles: keep them on disk
            let data = try await http.send(RequestPlan(origin: "gallery", path: "library-index.json"), timeout: 60)
            struct Index: Decodable { let items: [LibraryItem] }
            items = try await Task.detached { try JSONDecoder().decode(Index.self, from: data).items }.value
            indexDerived()
        }
        let tdata = try await http.send(RequestPlan(origin: "gallery", path: "api/taste"), timeout: 60)
        struct Taste: Decodable { let marks: [String: TasteMark]? }
        guard let m = try await Task.detached(operation: { try JSONDecoder().decode(Taste.self, from: tdata).marks }).value else {
            marksLoaded = false
            throw URLError(.cannotParseResponse)
        }
        marks = m
        marksLoaded = true
        await loadTags(model: model)
        LibraryGlanceWriter.publish(self)   // the Curate widget's numbers
    }

    private func indexDerived() {
        let re = try? NSRegularExpression(pattern: #"(20\d{6}[a-z]{1,3})(?=-\d+\.)"#)
        var b: [String: String] = [:], u: Set<String> = []
        for it in items {
            if let x = it.batch { b[it.vault_id] = x }
            else if let n = it.name, let m = re?.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)), let r = Range(m.range(at: 1), in: n) { b[it.vault_id] = String(n[r]) }
            if it.tags?.contains("unrenderable") == true { u.insert(it.vault_id) }
        }
        batchOf = b; unrenderable = u
    }

    func loadTags(model: AppModel) async {
        guard let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/tags"), timeout: 30) else { return }
        struct T: Decodable { let tags: [String: [String]]? }
        if let t = (try? JSONDecoder().decode(T.self, from: d))?.tags { tags = t }
    }

    /// Add or remove one tag on many pieces (500 to a write, as the route allows). Optimistic; put back when the store refuses.
    func tag(_ ids: [String], add: Bool, tag t: String, model: AppModel) async -> String {
        guard let http = model.http, !ids.isEmpty else { return "Not saved. Nothing chosen." }
        let prev = tags
        for id in ids { var c = Set(tags[id] ?? []); if add { c.insert(t) } else { c.remove(t) }; tags[id] = c.isEmpty ? nil : c.sorted() }
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let body = try? JSONSerialization.data(withJSONObject: ["ids": chunk, (add ? "add" : "remove"): t])
            do { _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/tags", headers: ["content-type": "application/json", "Origin": base(model)], body: body), idempotent: false) }
            catch { tags = prev; notSaved += 1; return "Not saved. The store refused the tag; it was put back." }
        }
        return "\(add ? "Tagged" : "Untagged") \(ids.count) · \(t)"
    }

    /// Rename a tag everywhere; renaming onto a tag that exists merges the two.
    func rename(_ from: String, to: String, model: AppModel) async -> String {
        guard let http = model.http else { return "Not saved." }
        let body = try? JSONSerialization.data(withJSONObject: ["rename": ["from": from, "to": to]])
        do {
            _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/tags", headers: ["content-type": "application/json", "Origin": base(model)], body: body), idempotent: false)
            for (id, l) in tags { tags[id] = Array(Set(l.map { $0 == from ? to : $0 })).sorted() }
            return "Renamed \(from) to \(to)."
        } catch { notSaved += 1; return "Not saved. The store refused the rename." }
    }

    /// Many marks at once, 50 to a write as the web sends them. Offline, each waits in the outbox. Returns the ids the store refused.
    func writeMarks(_ wire: [[String: String]], model: AppModel) async -> Set<String> {
        guard let http = model.http else { return Set(wire.compactMap { $0["id"] }) }
        var refused = Set<String>()
        for chunk in stride(from: 0, to: wire.count, by: 50).map({ Array(wire[$0..<min($0 + 50, wire.count)]) }) {
            if !OfflineState.shared.online { chunk.forEach { MarkOutbox.add($0) }; continue }
            guard let body = try? JSONSerialization.data(withJSONObject: ["marks": chunk]) else { continue }
            do { _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/taste", headers: ["content-type": "application/json", "Origin": base(model)], body: body), idempotent: false) }
            catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut].contains(e.code) { chunk.forEach { MarkOutbox.add($0) } }
            catch { refused.formUnion(chunk.compactMap { $0["id"] }) }
        }
        if !refused.isEmpty { notSaved += 1 }
        return refused
    }

    func base(_ model: AppModel) -> String {
        var b = model.config?.origin("gallery")?.base ?? ""
        if b.hasSuffix("/") { b.removeLast() }
        return b
    }

    /// One write to /api/taste. Offline, the mark waits in the outbox (and counts as made); any other failure is counted, never hidden.
    func post(_ body: [String: String], model: AppModel) async -> Bool {
        guard marksLoaded, let http = model.http, let data = try? JSONSerialization.data(withJSONObject: body) else { notSaved += 1; return false }
        if !OfflineState.shared.online { MarkOutbox.add(body); return true }
        do {
            _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/taste",
                                                headers: ["content-type": "application/json", "Origin": base(model)], body: data),
                                    idempotent: false)
            return true
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut].contains(e.code) {
            MarkOutbox.add(body); return true
        } catch { notSaved += 1; return false }
    }

    /// Where a piece's picture or clip lives on the gallery.
    func media(_ it: LibraryItem, model: AppModel) -> (still: URL?, video: URL?) {
        let b = base(model)
        func u(_ p: String) -> URL? { URL(string: b + (p.hasPrefix("/") ? p : "/" + p)) }
        let file = (it.src?.split(separator: "/").last.map(String.init)) ?? it.name ?? ""
        switch it.class {
        case "still", "font": return (it.name.flatMap { u("/generated/" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)) }, nil)
        case "archive-work": return ((it.sub ?? "").contains("· edited") ? u("/archive-edits/ba/\(it.item_id).jpg") : it.src.flatMap(u), nil)
        case "code-piece": return (it.src?.hasPrefix("/thumbs/") == true ? u(it.src!) : nil, nil)
        case "cinematic":
            let poster = file.replacingOccurrences(of: #"\.(mp4|mov)$"#, with: ".jpg", options: [.regularExpression, .caseInsensitive])
            return (u("/cinematic-poster/" + poster), u("/media/cinematic/" + file))
        default: return (nil, nil)
        }
    }
}

/// Library: every piece with its verdict; filter by verdict, class and name; open one full screen to mark it.
@MainActor enum LibrarySection: PLSection {
    static let manifest = SectionManifest(id: "library", title: "Library", symbol: "square.grid.3x3", needsKeys: ["vault"], needsOrigins: ["gallery"])
    static func makeRoot(model: AppModel) -> AnyView { AnyView(LibraryView(model: model)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first {
            if first == "worlds", path.count > 1, let w = WorldRoom(rawValue: path[1]) { WorldsNav.shared.room = w; GalleryNav.shared.room = .worlds }
            else if let room = GalleryRoom(rawValue: first) { GalleryNav.shared.room = room }
        }
        return true
    }
    // the web's gold "new pieces" dot (gap audit 11-14): the Library tile carries how many pieces wait for his verdict,
    // from the same numbers the Library widget shows (written each time the Library or Curate loads)
    static func refresh(model: AppModel) async -> SectionRefresh {
        let n = SharedState.readLibrary()?.unmarked ?? 0
        return SectionRefresh(badge: n > 0 ? n : nil, notify: [])
    }
}

