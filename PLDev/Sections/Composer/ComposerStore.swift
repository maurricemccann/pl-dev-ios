import SwiftUI
import UIKit

// What Composer keeps: the library the laptop's index publishes (read only, cached for offline), the pieces (kept on this phone, in the
// same JSON the web board and the desktop app use), the cards waiting to be handed to the house, and the render board.

// MARK: the library

struct ComposerCatalog: Identifiable, Hashable { let name: String; let count: Int; var id: String { name } }

@MainActor @Observable final class ComposerLibrary {
    static let shared = ComposerLibrary()
    private(set) var manifest: ComposerManifest?
    private(set) var byId: [String: ComposerAsset] = [:]
    private(set) var thumbs: [String: String] = [:]
    var failed: String?
    var loading = false
    var assets: [ComposerAsset] { manifest?.assets ?? [] }
    /// The index plus what he attached from Photos and the Curve Library: what the spec and the graph resolve ids against.
    var allAssets: [ComposerAsset] { assets + ComposerExtras.shared.assets }
    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()

    init() { for a in ComposerExtras.shared.assets { byId[a.id] = a } }

    /// A source from Photos or the Curve Library joins the lookup the moment it is attached.
    func register(_ a: ComposerAsset) { byId[a.id] = a }

    /// The manifest (about 700 KB) and the thumbnail map (about 4 MB); the HTTP client keeps the last copy of each for offline.
    func load(model: AppModel, force: Bool = false) async {
        guard let http = model.http, !loading, force || manifest == nil else { return }
        loading = true; defer { loading = false }
        do {
            let d = try await http.send(RequestPlan(origin: "composer", path: "api/manifest"), timeout: 60)
            let m = try await Task.detached { try JSONDecoder().decode(ComposerManifest.self, from: d) }.value
            manifest = m; byId = Dictionary(m.assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }); failed = nil
            for a in ComposerExtras.shared.assets { byId[a.id] = a }
        } catch {
            if manifest == nil { failed = (error as? HTTPClient.Failure)?.message ?? "The library did not load. Pull to try again." }
        }
        // A failure here costs pictures, never assets.
        if thumbs.isEmpty || force, let t = try? await http.send(RequestPlan(origin: "composer", path: "api/thumbs"), timeout: 60) {
            struct T: Decodable { let thumbs: [String: String]? }
            thumbs = (try? await Task.detached { try JSONDecoder().decode(T.self, from: t).thumbs ?? [:] }.value) ?? thumbs
        }
    }

    /// Thumbnails come as data URLs; decode once.
    func image(_ id: String) -> UIImage? {
        if let c = cache.object(forKey: id as NSString) { return c }
        if let x = ComposerExtras.shared.thumb(id) { cache.setObject(x, forKey: id as NSString); return x }
        guard let s = thumbs[id], let comma = s.firstIndex(of: ","), let d = Data(base64Encoded: String(s[s.index(after: comma)...])), let img = UIImage(data: d) else { return nil }
        cache.setObject(img, forKey: id as NSString)
        return img
    }

    /// Catalogs present in the index, in the web's order (the manifest's roots), counts following the text filter.
    func catalogs(matching needle: String) -> [ComposerCatalog] {
        let n = needle.trimmingCharacters(in: .whitespaces).lowercased()
        var tally: [String: Int] = [:]
        for a in assets where n.isEmpty || a.name.lowercased().contains(n) || a.ext.contains(n) { tally[a.catalog, default: 0] += 1 }
        return (manifest?.roots ?? []).filter { $0.present && $0.count > 0 }.compactMap { r in tally[r.catalog].map { ComposerCatalog(name: r.catalog, count: $0) } }
    }
}

// MARK: the pieces

/// More than one piece can exist. They live on this phone (the web keeps them in the browser), and travel as the board's own JSON.
@MainActor @Observable final class ComposerPieces {
    static let shared = ComposerPieces()

    struct Entry: Codable, Identifiable, Hashable { var id: String; var piece: ComposerPiece }
    private struct Saved: Codable { var active: String; var pieces: [Entry] }

    var entries: [Entry] = [] { didSet { save() } }
    var activeId = "" { didSet { save() } }
    var selected: String?     // the shot an asset attaches to
    @ObservationIgnored private let file: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("composer-pieces.json")
    }()
    @ObservationIgnored private var restoring = true

    init() {
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: d), !s.pieces.isEmpty {
            entries = s.pieces; activeId = entries.contains { $0.id == s.active } ? s.active : s.pieces[0].id
        } else { startFresh() }
        selected = piece.shots.last?.id
        restoring = false
    }

    private func save() {
        guard !restoring, !entries.isEmpty else { return }
        if let d = try? JSONEncoder().encode(Saved(active: activeId, pieces: entries)) { try? d.write(to: file, options: .atomic) }
        ComposerGlanceWriter.publishPieces(entries.count, active: piece.piece, shots: piece.shots.count, seconds: piece.duration)
    }

    private func startFresh() {
        let id = Self.newId()
        entries = [Entry(id: id, piece: Self.fresh(name: "untitled-1"))]; activeId = id
    }

    static func newId() -> String { "p_" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UInt32.random(in: 0..<46656), radix: 36) }

    /// A new piece starts from the defaults he set in More.
    static func fresh(name: String) -> ComposerPiece {
        let d = UserDefaults.standard
        var p = ComposerPiece(piece: name)
        if let r = d.string(forKey: "composer.defaultResolution"), composerResolutions.contains(r) { p.resolution = r }
        if d.integer(forKey: "composer.defaultFps") > 0 { p.fps = d.integer(forKey: "composer.defaultFps") }
        if let t = d.string(forKey: "composer.defaultTarget"), !t.isEmpty { p.target = t }
        if let t = d.string(forKey: "composer.defaultTransition"), !t.isEmpty { p.transition = t }
        return p
    }

    var index: Int { entries.firstIndex { $0.id == activeId } ?? 0 }
    var piece: ComposerPiece {
        get { entries.indices.contains(index) ? entries[index].piece : ComposerPiece() }
        set { if entries.indices.contains(index) { entries[index].piece = newValue } }
    }

    func newPiece() {
        let id = Self.newId()
        entries.append(Entry(id: id, piece: Self.fresh(name: "untitled-\(entries.count + 1)")))
        activeId = id; selected = nil
    }
    func open(_ id: String) { guard entries.contains(where: { $0.id == id }) else { return }; activeId = id; selected = piece.shots.last?.id }
    func duplicatePiece(_ id: String) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        var p = e.piece; p.piece += "-copy"
        let n = Entry(id: Self.newId(), piece: p)
        entries.append(n); activeId = n.id; selected = p.shots.last?.id
    }
    func delete(_ id: String) {
        entries.removeAll { $0.id == id }
        if entries.isEmpty { startFresh(); selected = nil }
        else if id == activeId { activeId = entries[0].id; selected = piece.shots.last?.id }
    }

    /// Imports a piece from the board's JSON (the-practice-v1.piece.json shape). Says why when it is not one.
    @discardableResult func importJSON(_ data: Data) -> String? {
        guard let p = try? JSONDecoder().decode(ComposerPiece.self, from: data) else { return "Not imported. That file is not a piece." }
        let n = Entry(id: Self.newId(), piece: p)
        entries.append(n); activeId = n.id; selected = p.shots.last?.id
        return nil
    }
    func json(_ id: String? = nil) -> String {
        let p = entries.first { $0.id == (id ?? activeId) }?.piece ?? piece
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(p)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // shots

    private func freeShotId() -> String {
        let used = Set(piece.shots.map(\.id)); var n = piece.shots.count + 1
        while used.contains("shot_" + String(format: "%02d", n)) { n += 1 }
        return "shot_" + String(format: "%02d", n)
    }
    @discardableResult func addShot() -> String {
        let s = ComposerShot(id: freeShotId(), title: "untitled shot", duration: 4, transition: nil, sourceIds: [], nodes: nil)
        piece.shots.append(s); selected = s.id
        return s.id
    }
    func patch(_ id: String, _ edit: (inout ComposerShot) -> Void) {
        guard let i = piece.shots.firstIndex(where: { $0.id == id }) else { return }
        var s = piece.shots[i]; edit(&s); piece.shots[i] = s
    }
    func duplicateShot(_ id: String) {
        guard let i = piece.shots.firstIndex(where: { $0.id == id }) else { return }
        var c = piece.shots[i]; c.id = freeShotId()
        piece.shots.insert(c, at: i + 1); selected = c.id
    }
    func move(_ id: String, _ dir: Int) {
        guard let i = piece.shots.firstIndex(where: { $0.id == id }), piece.shots.indices.contains(i + dir) else { return }
        piece.shots.swapAt(i, i + dir)
    }
    func remove(_ id: String) {
        piece.shots.removeAll { $0.id == id }
        if selected == id { selected = nil }
    }
    /// Attach to the selected shot, or the last one: a tap that does nothing and says nothing reads as a broken library.
    @discardableResult func attach(_ a: ComposerAsset, to shotId: String? = nil) -> String? {
        guard let target = shotId ?? selected ?? piece.shots.last?.id, let shot = piece.shots.first(where: { $0.id == target }) else { return nil }
        selected = target
        if shot.sourceIds.contains(a.id) { return nil }
        patch(target) { $0.sourceIds.append(a.id) }
        return target
    }
}

// MARK: the hand-off

/// A card on its way to the house. The worker answers "no disk" (it has none) until the phone's door exists, so a card that cannot be
/// written waits here and goes in the next time the board accepts it. Nothing is lost.
@MainActor @Observable final class ComposerOutbox {
    static let shared = ComposerOutbox()
    struct Waiting: Codable, Identifiable, Hashable { var id: String; var piece: String; var shot: String; var look: String; var body: String; var made: Date; var note: String? }
    private(set) var waiting: [Waiting] = []
    private let key = "composer.outbox"

    init() { waiting = (try? JSONDecoder().decode([Waiting].self, from: UserDefaults.standard.data(forKey: key) ?? Data())) ?? [] }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(waiting), forKey: key) }

    enum Outcome { case made(String), queued(String), refused(String) }

    /// One POST to the board. 200 `{ok, id}` is a card; 503 means the board has no disk to write on; 400 says what the card lacked.
    private func post(_ body: Data, model: AppModel) async -> Outcome {
        guard let http = model.http else { return .queued("Waiting for the house. The phone has no config loaded.") }
        do {
            let d = try await http.send(RequestPlan(origin: "composer", method: "POST", path: "api/board", headers: ["content-type": "application/json"], body: body), idempotent: false, timeout: 30, cache: false)
            struct R: Decodable { let ok: Bool?; let id: String? }
            let r = try? JSONDecoder().decode(R.self, from: d)
            return .made(r?.id ?? "")
        } catch let f as HTTPClient.Failure {
            if case .http(let code) = f, code == 503 { return .queued("Waiting for the house. The board cannot take cards from the phone yet; it goes in when it can.") }
            if case .http(let code) = f, code == 400 { return .refused("Not sent. The board refused the card.") }
            return .queued("Waiting for the house. " + f.message)
        } catch { return .queued("Waiting for the house. The phone could not reach the board.") }
    }

    func send(body: [String: Any], model: AppModel) async -> Outcome {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .refused("Not sent. The card could not be written.") }
        let out = await post(data, model: model)
        if case .queued(let why) = out {
            let r = body["render"] as? [String: Any]
            waiting.append(Waiting(id: UUID().uuidString, piece: body["piece"] as? String ?? "", shot: body["shot"] as? String ?? "", look: r?["look"] as? String ?? "", body: String(decoding: data, as: UTF8.self), made: .now, note: why))
            save()
        }
        return out
    }

    /// Try every waiting card again. Returns how many went in.
    @discardableResult func flush(model: AppModel) async -> Int {
        var sent = 0
        for w in waiting {
            if case .made = await post(Data(w.body.utf8), model: model) { waiting.removeAll { $0.id == w.id }; sent += 1 }
        }
        if sent > 0 { save() }
        return sent
    }
    func discard(_ id: String) { waiting.removeAll { $0.id == id }; save() }
}
