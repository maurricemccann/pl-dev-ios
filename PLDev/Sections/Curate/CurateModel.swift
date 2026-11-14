import Foundation
import SwiftUI

/// One deck of the web picker (CurateDeck.tsx `<select>`): the base decks PLDevCore deals, plus the two the web builds inline
/// (the archive categories deck and a tag deck). `id` is the deep link: `pldev://section/curate/<id>`.
struct CurateMode: Hashable, Identifiable, Sendable {
    enum Kind: String, Sendable { case unmarked, new, cloud, api, unseen, all, trash, maybes, repass, favs, categories, tag }
    var kind: Kind
    var cls: String? = nil
    var tag: String? = nil

    var id: String { [kind.rawValue, cls ?? "", tag ?? ""].joined(separator: ":") }

    static let classLabels: [(String?, String)] = [(nil, "Everything"), ("seed", "Seed phrases"), ("still", "Stills"), ("cinematic", "Shorts (cinematics)"),
                                                   ("code-piece", "Code"), ("archive-work", "Archive"), ("essay", "Essays"), ("font", "Fonts")]
    static func classLabel(_ c: String?) -> String { classLabels.first { $0.0 == c }?.1 ?? (c ?? "Everything") }

    var title: String {
        switch kind {
        case .new: return "New · unmarked only"
        case .cloud: return "Cloud batches · curate + re-pass"
        case .api: return "API renders · curate + re-pass"
        case .unseen: return "\(Self.classLabel(cls)) · not yet seen by you"
        case .all: return "\(Self.classLabel(cls)) · every verdict"
        case .trash: return "Trash · everything you cut"
        case .unmarked: return Self.classLabel(cls)
        case .maybes: return "\(Self.classLabel(cls)) · maybes"
        case .repass: return "\(Self.classLabel(cls)) · re-pass"
        case .favs: return "Keeps · star the favourites"
        case .categories: return "Archive · categories"
        case .tag: return "Tag · \(tag ?? "")"
        }
    }

    /// Short name for the header and Siri.
    var short: String {
        switch kind {
        case .unmarked: return Self.classLabel(cls)
        case .new: return "New"; case .cloud: return "Cloud batches"; case .api: return "API renders"; case .trash: return "Trash"
        case .favs: return "Favourites"; case .categories: return "Categories"; case .tag: return "Tag · \(tag ?? "")"
        default: return title
        }
    }

    var deck: CurateDeck? {
        switch kind {
        case .unmarked: return .everything; case .new: return .new; case .cloud: return .cloud; case .api: return .api; case .unseen: return .unseen
        case .all: return .all; case .trash: return .trash; case .maybes: return .maybes; case .repass: return .repass; case .favs: return .favs
        case .categories, .tag: return nil
        }
    }

    /// The web's `repass = repass || fresh || src || tagFilter`: a keep on a keep leaves it as it was, undo restores the old mark.
    var rePassRules: Bool { [.new, .cloud, .api, .unseen, .all, .repass, .tag].contains(kind) }
    /// A re-pass of one class takes its maybe through the image / phrase / layout strip instead of a swipe up.
    var maybeNeedsTag: Bool { kind == .repass || kind == .new || kind == .cloud || kind == .api || kind == .unseen || kind == .all || kind == .tag }
    var isCategories: Bool { kind == .categories }
    var isMaybes: Bool { kind == .maybes }
    var usesSeedIndex: Bool { cls == "seed" && kind != .categories && kind != .tag }

    static let groups: [(String, [CurateMode])] = [
        ("New", [CurateMode(kind: .new)]),
        ("Cloud + API (every verdict, re-pass rules)", [CurateMode(kind: .cloud), CurateMode(kind: .api),
            CurateMode(kind: .unseen, cls: "cinematic"), CurateMode(kind: .unseen, cls: "still"), CurateMode(kind: .unseen),
            CurateMode(kind: .all, cls: "cinematic"), CurateMode(kind: .all, cls: "still")]),
        ("Trash", [CurateMode(kind: .trash)]),
        ("Curate", classLabels.map { CurateMode(kind: .unmarked, cls: $0.0) }),
        ("Maybes", classLabels.map { CurateMode(kind: .maybes, cls: $0.0) }),
        ("Re-pass (keeps + favourites + maybes)", [nil, "seed", "still", "cinematic", "code-piece", "font"].map { CurateMode(kind: .repass, cls: $0) } + [CurateMode(kind: .favs)]),
        ("Catalogue", [CurateMode(kind: .categories)]),
    ]

    /// `kind`, `kind:class`, `tag:<name>`, or a PLDevCore deck name (`everything` is Unmarked).
    static func parse(_ s: String) -> CurateMode? {
        let p = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if p.first == "tag", p.count >= 2 { return CurateMode(kind: .tag, tag: p[1]) }
        let k: Kind? = p.first == "everything" ? .unmarked : Kind(rawValue: p.first ?? "")
        guard let k else { return nil }
        let c = p.count > 1 && !p[1].isEmpty ? p[1] : nil
        return CurateMode(kind: k, cls: c)
    }
}

/// The three archive categories (web CATEGORIES) and the machine's guess for a card.
let curateCategories: [(String, String)] = [("digital", "Digital"), ("physical", "Physical"), ("seeds", "Seeds")]

@MainActor @Observable final class CurateModel {
    struct Done { let item: LibraryItem; let dir: String; let prev: TasteMark? }
    struct Carry { var prev = ""; var note = ""; var comment = "" }
    struct Extra: Decodable { let vault_id: String; let provenance: String?; let palette: String? }
    enum CommentState { case idle, saving, saved, failed }

    var mode = CurateMode(kind: .unmarked) {
        didSet { UserDefaults.standard.set(mode.id, forKey: "curate.mode") }
    }
    var queue: [LibraryItem] = []
    var index = 0
    var marks: [String: TasteMark] {   // one store: a mark here shows in the Library at once
        get { LibraryData.shared.marks }
        set { LibraryData.shared.marks = newValue }
    }
    var loading = false
    var loadFailed = false
    var classifyFails = 0
    var kept = 0
    var cuts = 0
    var maybes = 0
    var linkTick = 0
    var history: [Done] = []
    var comment = ""
    var commentState: CommentState = .idle
    var note = ""            // the maybes deck's own box: what is wrong with this one
    var starred = false
    var full = false
    var locked = false
    var tick = 0
    var undoTick = 0
    var carry: [String: Carry] = [:]
    var extras: [String: Extra] = [:]
    var qa: [String: String] = [:]
    var waiting: [String: Int] = [:]
    var tagNames: [String] = []

    private(set) var allItems: [LibraryItem] = []
    private var seeds: [LibraryItem] = []
    private var cats: [String: (cat: String?, by: String?)] = [:]
    private var tagMap: [String: [String]] = [:]
    private var redo: Set<String> = []
    private var csaved = ""
    private var committing = false
    private var side = false

    var current: LibraryItem? { index < queue.count ? queue[index] : nil }
    var notSaved: Int { LibraryData.shared.notSaved + classifyFails }
    func carried(_ it: LibraryItem) -> Carry { carry[it.vault_id] ?? Carry() }

    init() {
        if UserDefaults.standard.object(forKey: "curate.rememberDeck") as? Bool ?? true, let s = UserDefaults.standard.string(forKey: "curate.mode"), let m = CurateMode.parse(s) { mode = m }
    }

    // MARK: loading

    func load(model: AppModel, force: Bool = false) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            try await LibraryData.shared.load(model: model, force: force)
            allItems = LibraryData.shared.items
            loadFailed = false
            await loadSide(model: model, force: force)
            await deal(model: model)
        } catch {
            loadFailed = true; queue = []   // never deal a deck over marks that did not load
        }
    }

    /// The small files beside the index: the machine's flaw reads, the lock state, each work's palette and provenance.
    private func loadSide(model: AppModel, force: Bool) async {
        guard let http = model.http, force || !side else { return }
        side = true
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "curate-qa.json"), timeout: 30),
           let q = try? JSONDecoder().decode([String: String].self, from: d) { qa = q }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/unlock"), timeout: 15),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { locked = (o["unlocked"] as? Bool) == false }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "library-index.json"), timeout: 60) {
            struct Index: Decodable { let items: [Extra] }
            let rows = await Task.detached { (try? JSONDecoder().decode(Index.self, from: d).items) ?? [] }.value
            extras = Dictionary(rows.map { ($0.vault_id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func loadSeeds(model: AppModel) async {
        guard seeds.isEmpty, let http = model.http else { return }
        struct Index: Decodable { let items: [LibraryItem] }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "seed-index.json"), timeout: 60),
           let i = await Task.detached(operation: { try? JSONDecoder().decode(Index.self, from: d) }).value { seeds = i.items }
    }

    private func loadCats(model: AppModel) async {
        guard let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/classify"), timeout: 30, cache: false),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = o["cats"] as? [String: Any] else { return }
        cats = c.compactMapValues { v in
            guard let m = v as? [String: Any] else { return nil }
            return (m["cat"] as? String, m["by"] as? String)
        }
    }

    private func loadTags(model: AppModel) async {
        guard let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/tags"), timeout: 30, cache: false),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = o["tags"] as? [String: [String]] else { return }
        tagMap = t
        tagNames = Set(t.values.flatMap { $0 }).sorted()
    }

    func ensureTags(model: AppModel) async { if tagNames.isEmpty { await loadTags(model: model) } }

    /// The tags on the piece in front of him (his note 11-14: "there's no way to add tags in curate").
    var currentTags: [String] { current.map { tagMap[$0.vault_id] ?? [] } ?? [] }

    /// Adds or removes one tag on the current piece through the gallery's /api/tags, the same store the web Library writes.
    @discardableResult func setTag(_ raw: String, on: Bool, model: AppModel) async -> Bool {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let it = current, !tag.isEmpty, tag.count <= 60, let http = model.http,
              let body = try? JSONSerialization.data(withJSONObject: ["ids": [it.vault_id], (on ? "add" : "remove"): tag]) else { return false }
        do {
            _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/tags",
                                                headers: ["content-type": "application/json", "Origin": LibraryData.shared.base(model)], body: body),
                                    idempotent: false)
        } catch { return false }
        var t = tagMap[it.vault_id] ?? []
        if on { if !t.contains(tag) { t.append(tag) } } else { t.removeAll { $0 == tag } }
        tagMap[it.vault_id] = t
        if on, !tagNames.contains(tag) { tagNames = (tagNames + [tag]).sorted() }
        return true
    }

    func select(_ m: CurateMode, model: AppModel) async {
        mode = m
        await deal(model: model)
    }

    // MARK: dealing

    private func guessCat(_ c: String?) -> String? {
        guard let c else { return nil }
        if c == "finished_works" || c == "studies" { return "physical" }
        return curateCategories.contains { $0.0 == c } ? c : nil
    }

    func deal(model: AppModel) async {
        guard !loadFailed else { return }
        if mode.usesSeedIndex { await loadSeeds(model: model) }
        let marks = self.marks, m = mode
        var items: [LibraryItem]
        var noteFor: [String: String] = [:]
        switch m.kind {
        case .categories:
            await loadCats(model: model)
            items = allItems.filter { $0.class == "archive-work" && marks[$0.vault_id]?.v == "keep" && cats[$0.item_id]?.by != "founder" }
            for it in items { noteFor[it.vault_id] = guessCat(cats[it.item_id]?.cat) ?? "" }
        case .tag:
            await loadTags(model: model)
            let t = m.tag ?? ""
            items = allItems.filter { (tagMap[$0.vault_id] ?? []).contains(t) && (m.cls == nil || $0.class == m.cls) }
                .enumerated().sorted { a, b in
                    let ma = marks[a.element.vault_id] == nil ? 0 : 1, mb = marks[b.element.vault_id] == nil ? 0 : 1
                    if ma != mb { return ma < mb }
                    let ka = "\(a.element.batch ?? "")\(a.element.vault_id)", kb = "\(b.element.batch ?? "")\(b.element.vault_id)"
                    return ka != kb ? ka > kb : a.offset < b.offset
                }.map(\.element)
        default:
            let pool = m.usesSeedIndex ? seeds : allItems
            items = CurateQueue.build(m.deck ?? .everything, items: pool, marks: marks, cls: m.cls)
            if m.kind == .unmarked, m.cls == "archive-work" {   // his redo order: old keeps, then old keeps now edited, then other edited, then the rest
                if redo.isEmpty, let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "archive-redo.json"), timeout: 30),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let w = o["was_keep"] as? [String] { redo = Set(w) }
                func rank(_ it: LibraryItem) -> Int { let ed = (it.sub ?? "").contains("· edited"); return redo.contains(it.item_id) ? (ed ? 1 : 0) : (ed ? 2 : 3) }
                items = items.enumerated().sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }.map(\.element)
            }
        }
        var c: [String: Carry] = [:]
        for it in items {
            let mk = marks[it.vault_id]
            c[it.vault_id] = Carry(prev: mk?.prevName ?? "", note: m.kind == .categories ? (noteFor[it.vault_id] ?? "") : (mk?.note ?? ""),
                                   comment: ownComment(mk?.comment))
        }
        carry = c
        queue = items
        index = 0; history = []; kept = 0; cuts = 0; maybes = 0
        openCard()
        publishCounts()
    }

    /// His own comment only: the system's provenance notes stay in the record but never show in the box (S308).
    private func ownComment(_ c: String?) -> String {
        let s = c ?? ""
        return s.range(of: #"^(regenerated from your favourites|replaced by)"#, options: .regularExpression) != nil ? "" : s
    }

    /// Each card opens with the note it already carries (maybes) and its own comment.
    private func openCard() {
        starred = false
        if let it = current {
            let c = carried(it)
            note = c.note; comment = c.comment; csaved = c.comment
        } else { note = ""; comment = ""; csaved = "" }
        commentState = .idle
    }

    /// How many cards wait in each deck, so a cleared screen says where the work is (web Empty).
    func publishCounts() {
        var n: [String: Int] = [:]
        let marks = self.marks
        for it in allItems.filter({ $0.class != "seed" }) + seeds {
            let mk = marks[it.vault_id]
            if mk?.v == "maybe" { n["m:\(it.class)", default: 0] += 1; if it.class != "seed" { n["m:", default: 0] += 1 } }
            if mk != nil || it.tagList.contains("unrenderable") { continue }
            n[it.class, default: 0] += 1
            if it.class != "archive-work" && it.class != "seed" { n["", default: 0] += 1 }
        }
        waiting = n
    }

    func ensureSeedCount(model: AppModel) async {
        if seeds.isEmpty { await loadSeeds(model: model); publishCounts() }
    }

    // MARK: marks

    private func post(_ body: [String: String], model: AppModel) async -> Bool {
        await LibraryData.shared.post(body, model: model)
    }

    func saveComment(model: AppModel) async {
        guard let it = current, !mode.isCategories, !mode.isMaybes else { return }
        let t = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != csaved else { return }
        commentState = .saving
        marks[it.vault_id, default: TasteMark(v: "")].comment = t
        if await post(["only": "comment", "id": it.vault_id, "comment": String(t.prefix(1000))], model: model) { csaved = t; commentState = .saved }
        else { commentState = .failed }
    }

    /// keep / cut / maybe, with the web's rules: a keep on a keep leaves it as it was (re-pass rules), the favourites deck posts
    /// nothing for a keep, the maybes deck sends the typed note, a re-pass maybe carries its image / phrase / layout tag.
    func commit(_ dir: String, tag: String? = nil, model: AppModel) async {
        guard !committing, !starred, let it = current else { return }
        committing = true; defer { committing = false }
        await saveComment(model: model)
        let prev = marks[it.vault_id], c = carried(it)
        let leaves = mode.rePassRules && dir == "keep" && (c.prev == "keep" || c.prev == "fav")
        if leaves {
            var b = ["id": it.vault_id, "v": "keep"]; if !c.note.isEmpty { b["note"] = c.note }
            _ = await post(b, model: model)   // stamps the time so it leaves the re-pass; note and comment stay as they were
            marks[it.vault_id] = TasteMark(v: "keep", note: c.note.isEmpty ? nil : c.note, comment: prev?.comment)
        } else if !(mode.kind == .favs && dir == "keep") {
            var b = ["id": it.vault_id, "v": dir]
            let n = mode.isMaybes ? note.trimmingCharacters(in: .whitespacesAndNewlines) : (mode.maybeNeedsTag && dir == "maybe" ? (tag ?? "") : "")
            if !n.isEmpty { b["note"] = n }
            _ = await post(b, model: model)
            marks[it.vault_id] = TasteMark(v: dir, note: n.isEmpty ? nil : n, comment: prev?.comment)
        }
        if dir == "cut" { PLHaptics.cut() } else if dir == "keep" { PLHaptics.keep() }   // apple lane: each verdict has its own feel
        advance(it, dir: dir == "cut" || dir == "maybe" ? dir : "keep", prev: prev)
    }

    /// A favourite is a keep carrying the note `fav`; the star fills for a beat before the card leaves.
    func favourite(model: AppModel) async {
        guard !committing, !starred, let it = current else { return }
        committing = true
        await saveComment(model: model)
        let prev = marks[it.vault_id]
        _ = await post(["id": it.vault_id, "v": "keep", "note": "fav"], model: model)
        marks[it.vault_id] = TasteMark(v: "keep", note: "fav", comment: prev?.comment)
        starred = true; tick += 1
        PLHaptics.crown()   // apple lane
        try? await Task.sleep(for: .milliseconds(380))
        committing = false
        advance(it, dir: "keep", prev: prev)
    }

    /// An edited archive work: keep the work but revert its edit (applied at the next archive publish).
    func keepOriginal(model: AppModel) async {
        guard !committing, let it = current else { return }
        committing = true; defer { committing = false }
        let prev = marks[it.vault_id]
        _ = await post(["id": it.vault_id, "v": "keep", "note": "use-original"], model: model)
        marks[it.vault_id] = TasteMark(v: "keep", note: "use-original", comment: prev?.comment)
        advance(it, dir: "keep", prev: prev)
    }

    /// The categories deck: a tap rules the category and moves on; it never touches his keep or cut.
    func classify(_ cat: String, model: AppModel) async {
        guard !committing, let it = current, let http = model.http else { return }
        committing = true; defer { committing = false }
        let body = try? JSONSerialization.data(withJSONObject: ["cr": it.item_id, "cat": cat])
        var ok = false
        if let body, let d = try? await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/classify",
                                                              headers: ["content-type": "application/json", "Origin": LibraryData.shared.base(model)], body: body), idempotent: false, cache: false),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { ok = (o["ok"] as? Bool) == true }
        if !ok { classifyFails += 1 }
        cats[it.item_id] = (cat, "founder")
        advance(it, dir: "keep", prev: nil)
    }

    private func advance(_ it: LibraryItem, dir: String, prev: TasteMark?) {
        if dir == "keep" { kept += 1 } else if dir == "cut" { cuts += 1 } else if dir == "maybe" { maybes += 1 }
        history.append(Done(item: it, dir: dir, prev: prev))
        tick += 1
        index += 1
        openCard()
        refreshGlance()
    }

    func undo(model: AppModel) async {
        guard !committing, let last = history.popLast() else { return }
        committing = true; defer { committing = false }
        if mode.isCategories, let http = model.http {
            let body = try? JSONSerialization.data(withJSONObject: ["cr": last.item.item_id, "undo": true])
            if let body { _ = try? await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/classify",
                                                               headers: ["content-type": "application/json", "Origin": LibraryData.shared.base(model)], body: body), idempotent: false, cache: false) }
        } else if let p = last.prev, !p.v.isEmpty {
            // one rule for every deck: put back the mark the card had before, note included
            var b = ["id": last.item.vault_id, "v": p.v]; if let n = p.note, !n.isEmpty { b["note"] = n }
            _ = await post(b, model: model)
        } else {
            _ = await post(["id": last.item.vault_id, "v": "clear"], model: model)
        }
        marks[last.item.vault_id] = last.prev
        if last.dir == "keep" { kept = max(0, kept - 1) } else if last.dir == "cut" { cuts = max(0, cuts - 1) } else if last.dir == "maybe" { maybes = max(0, maybes - 1) }
        index = max(0, index - 1)
        undoTick += 1
        openCard()
        refreshGlance()
    }

    private func refreshGlance() { LibraryGlanceWriter.publish(LibraryData.shared) }

    func media(_ it: LibraryItem, model: AppModel) -> (still: URL?, video: URL?) { LibraryData.shared.media(it, model: model) }

    // MARK: what the card says

    func palette(_ it: LibraryItem) -> [Color] {
        guard let s = extras[it.vault_id]?.palette, let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return ["g", "body", "hi", "ink"].compactMap { (o[$0] as? String).flatMap(Color.init(cssHex:)) }
    }

    enum Origin { case claudeWords, cloud, api }
    /// A card in Claude's own words, a cloud batch or an API render gets the orange wash and ring (web S311, S327).
    func origin(_ it: LibraryItem) -> Origin? {
        if (it.sub ?? "").hasPrefix("claude ·") { return .claudeWords }
        let s = "\(it.name ?? "")\(it.src ?? "")"
        if s.range(of: #"\d{8}g\d{4}"#, options: .regularExpression) != nil { return .cloud }
        if it.origin == "onmodel" || (it.name ?? "").contains("pl-onmodel") { return .api }
        return nil
    }

    /// The quiet line under the title (web caption).
    func caption(_ it: LibraryItem) -> String {
        let c = carried(it)
        var parts: [String] = ["#\(index + 1) \(it.item_id)"]
        if it.class == "code-piece" || it.class == "cinematic" { parts.append("moving") }
        if extras[it.vault_id]?.provenance == "hand" { parts.append("by hand") }
        if !mode.rePassRules && mode.kind != .repass, let s = it.sub, !s.isEmpty { parts.append(s) }
        if mode.rePassRules || mode.kind == .repass {
            if c.prev == "maybe", !c.note.isEmpty { parts.append("was maybe, liked the \(c.note)") }
            if c.prev == "cut" { parts.append("was cut") }
            if mode.kind == .new { parts.append(c.prev.isEmpty ? "new" : (c.prev == "cut" ? "" : "was \(c.prev)")) }
        }
        if let q = qa[it.vault_id] { parts.append(q) }
        return parts.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

extension Color {
    /// A `#rrggbb` string as the pieces store their palettes.
    init?(cssHex s: String) {
        var t = s.trimmingCharacters(in: .whitespaces); if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        self.init(hex: v)
    }
}
