import Foundation

/// One card the Pack can deal: `pack/cards.json` (stills and videos = keep + fav; archive = keep) plus, for Prism, the archive
/// pieces he starred in Curate (`/api/taste?favs=1`, S349 SPEC: FAVOURITE MARK IN CURATE). With no star, Prism is empty and says so.
struct PackShowCard: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var tier: String
    var piece: String
    var img: String
    var video: String?
}

/// The geometry the rip reads (`pack/pack.json`, written by the export script beside pack.glb).
struct PackGeometry: Codable, Sendable {
    var X0 = -0.036, X1 = 0.036, TEAR = 0.044, TOP = 0.056
}

/// The decks, kept between visits as the page keeps them (v 2): one card to a pack, the tier drawn by the odds, the piece the next
/// in that tier's own shuffled pile (random = a shuffled deck: no repeat until the whole tier has shown).
struct PackDecks: Codable, Sendable {
    var v = 2
    var seed: Int
    var n = 0
    var since = 0
    var dry = 0
    var cur: Int?
    var piles: [String: [Int]] = [:]
    var opened: [String] = []
    var mod: String?
    var prismSig: String?

    static let storeKey = "pldev.pack.decks"
    static func fresh(_ seed: Int) -> PackDecks { PackDecks(seed: seed) }
    static func load() -> PackDecks? {
        guard let d = UserDefaults.standard.data(forKey: storeKey), let k = try? JSONDecoder().decode(PackDecks.self, from: d), k.v == 2 else { return nil }
        return k
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.storeKey) } }

    var packSeed: Int { seed + n * 31 }

    /// The next pull: tier by the odds (no long run of black; a Prism never more than `pity` packs away; Prism never faked from
    /// keeps), piece by the tier's pile. The modifier roll is the caller's, on its own seed.
    mutating func pull(_ cards: [PackShowCard], odds O: PackSettings.Odds) -> PackShowCard? {
        guard !cards.isEmpty else { return nil }
        var r = PackRNG(seed + n * 977 + 5)
        let tot = max(1, O.obsidian + O.champagne + O.prism), x = r() * tot
        var tier = x < O.obsidian ? "common" : x < O.obsidian + O.champagne ? "legendary" : "exclusive"
        if tier == "common" && O.champagneAfter > 0 && Double(dry) >= O.champagneAfter { tier = "legendary" }
        if O.pity > 0 && Double(since) >= O.pity - 1 { tier = "exclusive" }
        if tier == "exclusive" && !cards.contains(where: { $0.tier == "exclusive" }) { tier = x < O.obsidian ? "common" : "legendary" }
        if !cards.contains(where: { $0.tier == tier }) { tier = cards[0].tier }   // a tier with no cards at all deals from what there is
        var pile = piles[tier] ?? []
        if pile.isEmpty {
            pile = cards.indices.filter { cards[$0].tier == tier }
            if pile.count > 1 { for i in stride(from: pile.count - 1, to: 0, by: -1) { let j = Int(r() * Double(i + 1)); pile.swapAt(i, j) } }
        }
        cur = pile.popLast()
        piles[tier] = pile
        since = tier == "exclusive" ? 0 : since + 1
        dry = tier == "common" ? dry + 1 : 0
        return cur.map { cards[$0] }
    }
}

/// Where a card's picture lives: the page's paths are relative to /pack/ unless they start at the root.
enum PackPaths {
    static func path(_ p: String) -> String {
        p.hasPrefix("/") ? String(p.dropFirst()) : "pack/" + p
    }
    static func url(_ p: String, base: String) -> URL? {
        if p.hasPrefix("http") { return URL(string: p) }
        let enc = path(p).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path(p)
        return URL(string: base + "/" + enc)
    }
}
