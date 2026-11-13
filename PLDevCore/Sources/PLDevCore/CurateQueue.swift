import Foundation

/// The Curate deck's brain, ported from the gallery's CurateDeck.tsx (S348, sub-spec 4). Pure: no network, no UI,
/// so it is tested on Linux against the same rules the web uses. Decks ported in v1: everything (the default),
/// new, trash, maybes, favs ("Keeps: star the favourites"). Not yet: repass, source=, tag=, the categories deck.
public struct LibraryItem: Codable, Sendable, Equatable, Identifiable {
    public var vault_id: String
    public var item_id: String
    public var `class`: String
    public var name: String?
    public var sub: String?
    public var origin: String?
    public var tags: String?
    public var src: String?
    public var source: String?
    public var batch: String?
    public var id: String { vault_id }

    public init(vault_id: String, item_id: String = "", class cls: String, name: String? = nil, sub: String? = nil,
                origin: String? = nil, tags: String? = nil, src: String? = nil, source: String? = nil, batch: String? = nil) {
        self.vault_id = vault_id; self.item_id = item_id; self.class = cls; self.name = name; self.sub = sub
        self.origin = origin; self.tags = tags; self.src = src; self.source = source; self.batch = batch
    }

    /// `tags` is a JSON array in a string, as the index stores it.
    public var tagList: [String] {
        guard let tags, let d = tags.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [Any] else { return [] }
        return a.map { "\($0)" }
    }
}

public struct TasteMark: Codable, Sendable, Equatable {
    public var v: String
    public var at: String?
    public var note: String?
    public var comment: String?
    public init(v: String, at: String? = nil, note: String? = nil, comment: String? = nil) { self.v = v; self.at = at; self.note = note; self.comment = comment }
    public var isFav: Bool { v == "keep" && note == "fav" }
}

public enum CurateDeck: String, Sendable, CaseIterable {
    case everything, new, trash, maybes, favs
    public var title: String {
        switch self {
        case .everything: return "Unmarked"
        case .new: return "New"
        case .trash: return "Trash"
        case .maybes: return "Maybes"
        case .favs: return "Keeps: star the favourites"
        }
    }
}

public enum CurateQueue {
    /// The deck for one class filter (nil = all classes). Returns the items in the order the web deals them.
    public static func build(_ deck: CurateDeck, items all: [LibraryItem], marks: [String: TasteMark], cls: String? = nil) -> [LibraryItem] {
        let renderable = { (it: LibraryItem) in !it.tagList.contains("unrenderable") }
        switch deck {
        case .trash:
            return all.filter { marks[$0.vault_id]?.v == "cut" && (cls == nil || $0.class == cls) }
                .sorted { (marks[$0.vault_id]?.at ?? "") > (marks[$1.vault_id]?.at ?? "") }
        case .new:
            return all.filter { (cls == nil || $0.class == cls) && renderable($0) && marks[$0.vault_id] == nil && $0.class != "archive-work" }
                .enumerated().sorted { a, b in
                    let sa = stamp(a.element), sb = stamp(b.element)
                    return sa != sb ? sa > sb : a.offset < b.offset   // stable, as Array.sort is in JS engines
                }.map(\.element)
        case .maybes:
            var items = all.filter { cls == nil || $0.class == cls }
            items = items.filter { marks[$0.vault_id]?.v == "maybe" }
            return items.filter(renderable)
        case .favs:
            var items = all.filter { cls == nil || $0.class == cls }
            items = items.filter { let m = marks[$0.vault_id]; return m?.v == "keep" && m?.note != "fav" && $0.class != "archive-work" }.reversed()
            items = items.filter(renderable)
            return cls == nil ? items.filter { $0.class != "archive-work" } : items
        case .everything:
            var items = all.filter { (cls == nil || $0.class == cls) && marks[$0.vault_id] == nil }
            items = rankAndMix(items)
            items = items.filter(renderable)
            if cls == nil { items = items.filter { $0.class != "archive-work" } }
            return items
        }
    }

    /// YYYYMMDD from a name like "...20261112a-3..." (New's sort key).
    static func stamp(_ it: LibraryItem) -> String {
        firstMatch(#"(20\d{6})[a-z]{0,3}[-_]\d"#, in: "\(it.vault_id) \(it.name ?? "null")", group: 1) ?? ""
    }

    /// Hoodie week first (newest wkNN, newest vN), then cloud batches newest stamp first, then on-model, then the rest in index order;
    /// then batch-filed clips are mixed in their own slots so one drawing never shows twice in a row.
    static func rankAndMix(_ input: [LibraryItem]) -> [LibraryItem] {
        let cloudRe = #"\d{8}g\d{4}"#
        func cloudStamp(_ it: LibraryItem) -> String { firstMatch(cloudRe, in: "\(it.name ?? "")\(it.src ?? "")", group: 0) ?? "" }
        func wk(_ it: LibraryItem) -> Int {
            // one match, both groups from it, as the web's single .match() does
            let s = "\(it.vault_id)\(it.name ?? "")"
            guard let re = try? NSRegularExpression(pattern: #"wk(\d{2})(?:v(\d+))?"#),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r1 = Range(m.range(at: 1), in: s), let n = Int(s[r1]) else { return 0 }
            let v = Range(m.range(at: 2), in: s).flatMap { Int(s[$0]) } ?? 0
            return n * 100 + v
        }
        let week = (input.map(wk).max() ?? 0) / 100
        func rk(_ it: LibraryItem) -> Int {
            if week > 0 && wk(it) / 100 == week { return -1 }
            if firstMatch(cloudRe, in: "\(it.name ?? "")\(it.src ?? "")", group: 0) != nil { return 0 }
            if it.origin == "onmodel" || (it.name ?? "").contains("pl-onmodel") { return 1 }
            return 2
        }
        var items = input.enumerated().sorted { a, b in
            let ra = rk(a.element), rb = rk(b.element)
            if ra != rb { return ra < rb }
            if ra == -1 { let d = wk(b.element) - wk(a.element); if d != 0 { return d < 0 } }
            if ra == 0 { let sa = cloudStamp(a.element), sb = cloudStamp(b.element); if sa != sb { return sa > sb } }
            return a.offset < b.offset
        }.map(\.element)

        let batchRe = #"\d{8}b[a-z]-\d+\.mp4"#
        let slots = items.indices.filter { firstMatch(batchRe, in: "\(items[$0].name ?? "")\(items[$0].src ?? "")", group: 0) != nil }
        if slots.count > 1 {
            func piece(_ it: LibraryItem) -> String {
                it.tagList.first { firstMatch(#"^(PL-\d{4}|curve-comp-\d+)$"#, in: $0, group: 0) != nil } ?? it.vault_id
            }
            var pool = slots.map { items[$0] }.sorted { fnv($0.vault_id) < fnv($1.vault_id) }
            var mixed: [LibraryItem] = []
            while !pool.isEmpty {
                let last = mixed.last.map(piece)
                var left: [String: Int] = [:]
                for it in pool { left[piece(it), default: 0] += 1 }
                var k = -1
                for j in pool.indices {
                    let p = piece(pool[j])
                    if p != last && (k < 0 || left[p]! > left[piece(pool[k])]!) { k = j }
                }
                mixed.append(pool.remove(at: k < 0 ? 0 : k))
            }
            for (k, n) in slots.enumerated() { items[n] = mixed[k] }
        }
        return items
    }

    /// FNV-1a over UTF-16 units, as the web's `h()` does (charCodeAt), so the shuffle matches.
    static func fnv(_ s: String) -> UInt32 {
        var x: UInt32 = 2166136261
        for c in s.utf16 { x = (x ^ UInt32(c)) &* 16777619 }
        return x
    }

    static func firstMatch(_ pattern: String, in s: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }
}
