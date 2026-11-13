import Foundation

// What the site's own pages say about the shop, read natively. The Google feed carries 52 of the site's 89 pieces, so the shop
// list is the site's /shop page (the grid it shows, in its order) joined to the feed (variants, stock, flats). A piece's own page
// carries what the feed does not: its axiom, its argument, the size guide, care, production, delivery, and the variants of the
// pieces the feed leaves out. All of it is read from the live pages, so the app cannot disagree with the site, and kept for offline.

// MARK: - The shop page's grid

extension ShopCatalogue {
    struct Card: Sendable {
        let slug: String
        let name: String
        let cents: Int
        let line: String
        let flats: [String]
    }

    /// The cards of the site's /shop grid, in the order the site shows them.
    nonisolated static func cards(fromPage html: String) -> [Card] {
        guard let re = try? NSRegularExpression(pattern: #"<a class="pl-card[^"]*"[^>]*href="/shop/([^"?#]+)"[^>]*>([\s\S]*?)</a>"#),
              let img = try? NSRegularExpression(pattern: #"<img src="([^"]+)""#),
              let para = try? NSRegularExpression(pattern: #"<p[^>]*>([\s\S]*?)</p>"#),
              let head = try? NSRegularExpression(pattern: #"<h3[^>]*>([\s\S]*?)</h3>"#),
              let money = try? NSRegularExpression(pattern: #"([0-9][0-9,]*(?:\.[0-9]+)?)"#) else { return [] }
        let ns = html as NSString
        var out: [Card] = []
        var seen = Set<String>()
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let slug = ns.substring(with: m.range(at: 1))
            guard seen.insert(slug).inserted else { continue }
            let body = ns.substring(with: m.range(at: 2))
            let b = body as NSString
            let whole = NSRange(location: 0, length: b.length)
            let name = head.firstMatch(in: body, range: whole).map { SiteReaderView.clean(b.substring(with: $0.range(at: 1))) } ?? slug
            let ps = para.matches(in: body, range: whole).map { SiteReaderView.clean(b.substring(with: $0.range(at: 1))) }
            var cents = 0
            if let first = ps.first, let mm = money.firstMatch(in: first, range: NSRange(location: 0, length: (first as NSString).length)) {
                let n = (first as NSString).substring(with: mm.range(at: 1)).replacingOccurrences(of: ",", with: "")
                cents = Int(((Double(n) ?? 0) * 100).rounded())
            }
            // the card's pictures go through the site's /api/img proxy; the real address is its `src`
            var flats: [String] = []
            for im in img.matches(in: body, range: whole) {
                let raw = b.substring(with: im.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
                let real = URLComponents(string: raw)?.queryItems?.first { $0.name == "src" }?.value ?? raw
                if isFlat(real), !flats.contains(real) { flats.append(real) }
            }
            out.append(Card(slug: slug, name: name, cents: cents, line: ps.count > 1 ? ps[1] : "", flats: flats))
        }
        return out
    }

    /// The site's grid joined to the feed: the grid decides which pieces exist and in what order, the feed adds variants and stock.
    /// A piece the feed does not carry becomes a thin piece (one price, its flats) until its own page is read.
    nonisolated static func merge(page: Data?, feed: Data?) -> [ShopPiece] {
        let fromFeed = feed.map { build($0) } ?? []
        guard let page, let html = String(data: page, encoding: .utf8) else { return fromFeed }
        let grid = cards(fromPage: html)
        guard !grid.isEmpty else { return fromFeed }
        let bySlug = Dictionary(fromFeed.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        return grid.map { c in
            if var p = bySlug[c.slug] { p.line = c.line.isEmpty ? nil : c.line; return p }
            let v = ShopVariant(id: "", color: nil, size: nil, cents: c.cents, inStock: true, images: c.flats)
            return ShopPiece(slug: c.slug, name: c.name, description: "", group: ShopGroup.of(c.name), variants: [v], images: c.flats,
                             line: c.line.isEmpty ? nil : c.line, thin: true)
        }
    }
}

// MARK: - A piece's own page

struct PieceDetail: Codable, Sendable {
    struct Guide: Codable, Sendable, Hashable {
        var columns: [String]
        var rows: [[String]]
        var note: String?
    }
    struct Fold: Codable, Sendable, Hashable, Identifiable {
        var title: String
        var text: String
        var id: String { title }
    }

    var axiom: String?
    var provenance: String?
    var argument: String?
    var about: String?
    var guide: Guide?
    var folds: [Fold] = []
    var returnsLine: String?
    var related: [String] = []
    var twin = false
    var variants: [ShopVariant] = []
    var flats: [String] = []

    /// The piece with what its own page added. Only a thin piece takes the page's variants and flats: the feed's are richer.
    func applied(to piece: ShopPiece) -> ShopPiece {
        var p = piece
        if p.description.isEmpty, let about { p = ShopPiece(slug: p.slug, name: p.name, description: about, group: p.group, variants: p.variants, images: p.images, line: p.line, thin: p.thin) }
        guard p.thin == true else { return p }
        let vs = variants.isEmpty ? p.variants : variants
        let imgs = flats.isEmpty ? p.images : flats
        return ShopPiece(slug: p.slug, name: p.name, description: p.description, group: p.group, variants: vs, images: imgs, line: p.line, thin: variants.isEmpty ? p.thin : false)
    }

    // MARK: reading

    @MainActor static func fetch(_ slug: String) async -> PieceDetail? {
        let key = "shop-piece|" + slug
        do {
            let r = try await Site.call("GET", "shop/" + slug, timeout: 30)
            if (200..<300).contains(r.status), let html = String(data: r.data, encoding: .utf8) {
                let d = await Task.detached { parse(html) }.value
                if let d, let data = try? JSONEncoder().encode(d) { OfflineCache.save(data, for: key); return d }
            }
        } catch {}
        if let (saved, at) = OfflineCache.load(key), let d = try? JSONDecoder().decode(PieceDetail.self, from: saved) { OfflineState.servedCopy(from: at); return d }
        return nil
    }

    nonisolated static func parse(_ html: String) -> PieceDetail? {
        var d = PieceDetail()
        d.axiom = first(#"<p class="label mb-4">([\s\S]*?)</p><h1"#, in: html)
        d.provenance = first(#"Provenance</p><p class="[^"]*">([\s\S]*?)</p>"#, in: html)
        d.argument = first(#"The argument</p><p class="[^"]*">([\s\S]*?)</p>"#, in: html)
        d.about = first(#"About this piece</p>([\s\S]*?)</div></div>"#, in: html)
        d.returnsLine = first(#"<p class="font-body text-ink-faint text-\[0\.72rem\] mt-3">(30 days[\s\S]*?)</p>"#, in: html)
        d.twin = html.contains("The digital twin")

        // the size guide table
        if let block = firstRaw(#"<details class="pl-psy-panel mt-5[\s\S]*?</details>"#, in: html) {
            let cols = all(#"<th scope="col"[^>]*>([\s\S]*?)</th>"#, in: block).dropFirst()
            var rows: [[String]] = []
            for tr in all(#"<tr class="border-b border-line/40[^"]*">([\s\S]*?)</tr>"#, in: block, clean: false) {
                let size = first(#"<th scope="row"[^>]*>([\s\S]*?)</th>"#, in: tr) ?? ""
                rows.append([size] + all(#"<td[^>]*>([\s\S]*?)</td>"#, in: tr))
            }
            if !cols.isEmpty, !rows.isEmpty {
                d.guide = Guide(columns: Array(cols), rows: rows, note: first(#"<p class="font-body text-ink-faint text-\[0\.72rem\][^"]*">([\s\S]*?)</p>"#, in: block))
            }
        }

        // Production, Care, Delivery & returns
        if let re = try? NSRegularExpression(pattern: #"<details class="group py-4"><summary[^>]*>([\s\S]*?)<span[\s\S]*?</summary><p[^>]*>([\s\S]*?)</p></details>"#) {
            let ns = html as NSString
            for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let t = SiteReaderView.clean(ns.substring(with: m.range(at: 1)))
                let x = SiteReaderView.clean(ns.substring(with: m.range(at: 2)))
                if !t.isEmpty, !x.isEmpty { d.folds.append(Fold(title: t, text: x)) }
            }
        }

        // more from the drop
        if let r = html.range(of: "More from the drop") {
            var seen = Set<String>()
            d.related = all(#"href="/shop/([^"?#]+)""#, in: String(html[r.upperBound...]), clean: false).filter { seen.insert($0).inserted }
        }

        // the page's props: variants and the pictures that lead them
        let f = flight(html)
        if let vr = f.range(of: "\"variants\":[") {
            let from = f.index(before: vr.upperBound)
            if let arr = balanced(f, from: from), let json = try? JSONSerialization.jsonObject(with: Data(arr.utf8)) as? [[String: Any]] {
                func s(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty || $0.hasPrefix("$") ? nil : $0 } }
                d.variants = json.compactMap { v in
                    guard let id = v["id"] as? String, let price = v["price"] as? Int else { return nil }
                    let img = s(v["image"])
                    return ShopVariant(id: id, color: s(v["color"]), size: s(v["size"]), cents: price, inStock: (v["inStock"] as? Bool) ?? false,
                                       images: img.map { ShopCatalogue.isFlat($0) ? [$0] : [] } ?? [], design: s(v["design"]))
                }
            }
            if let ir = f.range(of: "\"images\":[", options: .backwards, range: f.startIndex..<vr.lowerBound) {
                let from = f.index(before: ir.upperBound)
                if let arr = balanced(f, from: from), let urls = try? JSONSerialization.jsonObject(with: Data(arr.utf8)) as? [String] {
                    var seen = Set<String>()
                    d.flats = urls.filter { ShopCatalogue.isFlat($0) && seen.insert($0).inserted }
                }
            }
        }
        // a page with none of its own words is not a piece page (a 404 or an outage page)
        return d.axiom == nil && d.argument == nil && d.variants.isEmpty ? nil : d
    }

    // MARK: small readers

    nonisolated private static func firstRaw(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (s as NSString).substring(with: m.range)
    }

    nonisolated private static func first(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1 else { return nil }
        let t = SiteReaderView.clean((s as NSString).substring(with: m.range(at: 1)))
        return t.isEmpty ? nil : t
    }

    nonisolated private static func all(_ pattern: String, in s: String, clean: Bool = true) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            let t = ns.substring(with: $0.range(at: 1))
            return clean ? SiteReaderView.clean(t) : t
        }
    }

    /// The page's Next.js flight data (`self.__next_f.push([1,"..."])`), decoded and joined.
    nonisolated private static func flight(_ html: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)"#) else { return "" }
        let ns = html as NSString
        var out = ""
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            if let data = ("[\"" + inner + "\"]").data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [String], let s = arr.first { out += s }
        }
        return out
    }

    /// The JSON array that opens at `from` (which must be a `[`), brackets matched and strings skipped.
    nonisolated private static func balanced(_ s: String, from: String.Index) -> String? {
        guard s[from] == "[" else { return nil }
        var depth = 0, inString = false, escaped = false
        var i = from
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "[" { depth += 1 }
            else if c == "]" { depth -= 1; if depth == 0 { return String(s[from...i]) } }
            i = s.index(after: i)
        }
        return nil
    }
}
