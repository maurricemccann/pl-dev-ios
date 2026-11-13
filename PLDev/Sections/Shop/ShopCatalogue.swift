import Foundation
import Observation

// The shop's catalogue, read from the site's own product feed (the one Google Shopping reads: per-variant price, stock and
// picture, grouped by piece). It is the live catalogue, so the app cannot disagree with the till.
//
// THE IMAGE RULE (hard-limits, Product imagery): flat or ghost garment shots, PNG, transparent, nothing else. The feed also
// lists Square's raw pictures, which can be on-model JPEGs, so this reader keeps ONLY pictures on the site's
// product-transparent path and drops the rest before anything can draw them. A piece with none shows a quiet placeholder.

struct ShopVariant: Codable, Hashable, Sendable {
    let id: String
    let color: String?
    let size: String?
    let cents: Int
    let inStock: Bool
    let images: [String]
}

/// What a piece is, for the filter chips and the Closet's slots.
enum ShopGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case tops, layers, bottoms, accessories, home, gifts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tops: return "Tops"; case .layers: return "Layers"; case .bottoms: return "Bottoms"
        case .accessories: return "Accessories"; case .home: return "Home and paper"; case .gifts: return "Gift cards"
        }
    }

    var symbol: String {
        switch self {
        case .tops: return "tshirt"; case .layers: return "jacket"; case .bottoms: return "figure.walk"
        case .accessories: return "bag"; case .home: return "house"; case .gifts: return "giftcard"
        }
    }

    /// The same reading the site's Closet uses for a piece's slot, with hats counted as accessories.
    static func of(_ name: String) -> ShopGroup {
        let n = name.uppercased()
        func has(_ pattern: String) -> Bool { n.range(of: "\\b(\(pattern))\\b", options: .regularExpression) != nil }
        if has("GIFT CARD") { return .gifts }
        if has("GIFT BAG") || has("POSTER|PILLOW|PILLOW CASE|MAGNET|STICKER|PATCH|PIN SET|PIN|COASTER|MOUSE PAD|JOURNAL|NOTEBOOK|MUG|BLANKET") { return .home }
        if has("HOODIE|ZIP") { return .layers }
        if has("PANTS?|SWEATS|JOGGERS?|SKIRT|SHORTS|CARGO") { return .bottoms }
        if has("TEE|CROP|TANK|CREWNECK|CREW|LONG SLEEVE|JERSEY|SHIRT") { return .tops }
        if has("BAG|BANDANA|GAITER|BEANIE|HAT|CAP|TRUCKER") { return .accessories }
        return .home
    }
}

struct ShopPiece: Codable, Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    let description: String
    let group: ShopGroup
    let variants: [ShopVariant]
    let images: [String]            // transparent PNGs only, the first variant's leading
    var id: String { slug }

    var minCents: Int { variants.map(\.cents).min() ?? 0 }
    var maxCents: Int { variants.map(\.cents).max() ?? 0 }
    var inStock: Bool { variants.contains { $0.inStock } }
    var hero: URL? { images.first.flatMap { URL(string: $0) } }

    /// Colours in the order the feed lists them.
    var colors: [String] {
        var seen = Set<String>()
        return variants.compactMap(\.color).filter { seen.insert($0).inserted }
    }

    /// Sizes in the order the feed lists them (it lists S to XL in order).
    var sizes: [String] {
        var seen = Set<String>()
        return variants.compactMap(\.size).filter { seen.insert($0).inserted }
    }

    /// "$60.00", or "From $60.00" when sizes or colours price differently.
    var priceLine: String {
        minCents == maxCents ? Money.text(minCents) : "From " + Money.text(minCents)
    }

    /// The first sentence of the description: the card's one line.
    var oneLine: String {
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = d.firstIndex(where: { ".!?".contains($0) }) else { return d }
        return String(d[...end])
    }

    /// A variant by colour and size, falling back to the closest.
    func variant(color: String?, size: String?) -> ShopVariant? {
        variants.first { $0.color == color && $0.size == size }
            ?? variants.first { $0.color == color }
            ?? variants.first
    }
}

enum Money {
    /// US dollars with cents, as the site shows them.
    static func text(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100)"
    }
}

// MARK: - The feed reader

enum ShopCatalogue {
    struct Row: Sendable {
        var id = "", group = "", title = "", desc = "", imageLink = "", availability = "", price = ""
        var extra: [String] = []
        var color: String?, size: String?
    }

    /// Reads the feed's XML into pieces. Pure: no network, no state, so it runs off the main thread.
    nonisolated static func build(_ data: Data) -> [ShopPiece] {
        let rows = Reader().rows(in: data)
        var order: [String] = []
        var byGroup: [String: [Row]] = [:]
        for r in rows where !r.group.isEmpty {
            if byGroup[r.group] == nil { order.append(r.group) }
            byGroup[r.group, default: []].append(r)
        }
        return order.compactMap { slug in
            guard let rs = byGroup[slug], let first = rs.first else { return nil }
            let name = first.title.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? first.title
            var seen = Set<String>()
            var all: [String] = []
            let variants = rs.map { r -> ShopVariant in
                let imgs = ([r.imageLink] + r.extra).filter(isFlat)
                for u in imgs where seen.insert(u).inserted { all.append(u) }
                return ShopVariant(id: r.id, color: r.color, size: r.size, cents: cents(r.price), inStock: r.availability == "in_stock", images: imgs)
            }
            return ShopPiece(slug: slug, name: name, description: first.desc, group: ShopGroup.of(name), variants: variants, images: all)
        }
    }

    /// True only for the site's own transparent flat PNGs. Everything else is dropped (the product-imagery rule).
    nonisolated static func isFlat(_ url: String) -> Bool {
        guard let u = URL(string: url), u.host == "assets.psychedluxuries.com" else { return false }
        return u.path.contains("/product-transparent/") && u.path.lowercased().hasSuffix(".png")
    }

    nonisolated private static func cents(_ price: String) -> Int {
        let number = price.split(separator: " ").first.map(String.init) ?? price
        return Int(((Double(number) ?? 0) * 100).rounded())
    }

    private final class Reader: NSObject, XMLParserDelegate, @unchecked Sendable {
        private var out: [Row] = []
        private var cur: Row?
        private var text = ""
        private var inShipping = false

        func rows(in data: Data) -> [Row] {
            let p = XMLParser(data: data)
            p.delegate = self
            p.parse()
            return out
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
            text = ""
            if name == "item" { cur = Row() } else if name == "g:shipping" { inShipping = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard var row = cur else { return }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "item": out.append(row); cur = nil; return
            case "g:shipping": inShipping = false; return
            default: break
            }
            if inShipping { return }
            switch name {
            case "g:id": row.id = t
            case "g:item_group_id": row.group = t
            case "g:title": row.title = t
            case "g:description": row.desc = t
            case "g:image_link": row.imageLink = t
            case "g:additional_image_link": row.extra.append(t)
            case "g:availability": row.availability = t
            case "g:price": row.price = t
            case "g:color": row.color = t
            case "g:size": row.size = t
            default: break
            }
            cur = row
        }
    }
}

// MARK: - The store the screens read

@MainActor @Observable final class ShopStore {
    static let shared = ShopStore()

    var pieces: [ShopPiece] = []
    var loadedAt: Date?
    var failure: String?
    var loading = false

    private let seenKey = "pldev.shop.seen"
    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("shop-catalogue.json")
    }

    private init() {
        if let url = cacheURL, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            pieces = saved.pieces
            loadedAt = saved.at
        }
    }

    private struct Saved: Codable { let at: Date; let pieces: [ShopPiece] }

    func piece(_ slug: String) -> ShopPiece? { pieces.first { $0.slug == slug } }

    /// Reads the feed. The site caches it for an hour, so a pull inside ten minutes keeps what the phone has.
    func load(force: Bool = false) async {
        if !force, let at = loadedAt, !pieces.isEmpty, Date().timeIntervalSince(at) < 600 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let reply = try await Site.call("GET", "feed/products.xml", timeout: 40)
            guard (200..<300).contains(reply.status) else { throw Site.Problem.refused("The shop did not answer. Pull to try again.") }
            let data = reply.data
            let built = await Task.detached(priority: .userInitiated) { ShopCatalogue.build(data) }.value
            guard !built.isEmpty else { throw Site.Problem.refused("The shop's list came back empty. Pull to try again.") }
            pieces = built
            loadedAt = Date()
            failure = nil
            if let url = cacheURL, let saved = try? JSONEncoder().encode(Saved(at: Date(), pieces: built)) { try? saved.write(to: url) }
        } catch {
            if pieces.isEmpty { failure = error.localizedDescription } else { failure = nil }   // numbers already on screen stay
        }
    }

    /// Pieces that appeared since the last time the app looked, for the new-piece notice. The first read only records.
    func takeNewPieces() -> [ShopPiece] {
        let seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let now = pieces.map(\.slug)
        defer { if !now.isEmpty { UserDefaults.standard.set(now, forKey: seenKey) } }
        guard !seen.isEmpty else { return [] }
        return pieces.filter { !seen.contains($0.slug) }
    }
}
