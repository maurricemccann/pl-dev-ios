import SwiftUI

// The collections and the filter drawer of psychedluxuries.com's /shop, twinned from pl-headless: `lib/square.ts` COLLECTIONS (the
// name tests that put a piece in a collection), `components/home/Collections.tsx` (the three on the shop page) and
// `components/shop/FilterableShopGrid.tsx` (garment, line and price facets, three orders). The tests run on the piece's name, as the
// site's do, so a collection here holds exactly the pieces the site's collection page holds.

private func test(_ n: String, _ pattern: String) -> Bool { n.range(of: pattern, options: .regularExpression) != nil }

struct ShopCollection: Identifiable, Hashable {
    let slug: String
    let name: String
    let match: @Sendable (String) -> Bool
    var id: String { slug }

    static func == (a: ShopCollection, b: ShopCollection) -> Bool { a.slug == b.slug }
    func hash(into h: inout Hasher) { h.combine(slug) }

    func pieces(in all: [ShopPiece]) -> [ShopPiece] { all.filter { match($0.name.uppercased()) } }

    /// The collection's name as the site titles it: each word capitalised, the apostrophe left alone.
    var title: String {
        name.lowercased().split(separator: " ", omittingEmptySubsequences: false).map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }.joined(separator: " ")
    }

    /// Every collection the site has, in its order (`COLLECTIONS`, less the newest-N drop, which is a time rule and not a name).
    static let all: [ShopCollection] = [
        ShopCollection(slug: "classics", name: "CLASSICS") { $0.contains("HEART") || $0.hasPrefix("PSYCHED") },
        ShopCollection(slug: "glyphs", name: "Glyphs") { $0.contains("GLYPH") },
        ShopCollection(slug: "what-goes-around-comes-around", name: "WHAT GOES AROUND COMES AROUND") { $0.contains("WHAT GOES AROUND") },
        ShopCollection(slug: "money-glyphguy", name: "GLYPH GUY") { $0.contains("GLYPH GUY") },
        ShopCollection(slug: "love-yourself-glyph", name: "LOVE YOURSELF GLYPH") { $0.contains("LOVE YOURSELF GLYPH") },
        ShopCollection(slug: "money-glyph", name: "MONEY GLYPH") { $0.contains("MONEY GLYPH") },
        ShopCollection(slug: "seeds", name: "SEEDS") { $0.contains("SEED") },
        ShopCollection(slug: "heart-logo", name: "HEART MARK") { $0.contains("HEART") },
        ShopCollection(slug: "poverty-to-luxury", name: "POVERTY TO LUXURY") { $0.contains("POVERTY") },
        ShopCollection(slug: "psyched", name: "PSYCHED") { $0.hasPrefix("PSYCHED") },
        ShopCollection(slug: "tees", name: "TEES") { $0.contains("TEE") || $0.contains("T-SHIRT") },
        ShopCollection(slug: "hoodies", name: "HOODIES") { $0.contains("HOODIE") },
        ShopCollection(slug: "sweats", name: "SWEATS") { test($0, #"\bSWEATS\b"#) },
        ShopCollection(slug: "crops", name: "CROPS") { $0.contains("CROP") },
        ShopCollection(slug: "crewnecks", name: "CREWNECKS") { $0.contains("CREWNECK") || $0.contains("SWEATSHIRT") },
        ShopCollection(slug: "womens", name: "WOMEN'S") { $0.contains("CROP") || $0 == "FALL IN LOVE WITH YOURSELF TANK" },
        ShopCollection(slug: "mens", name: "MEN'S") { $0.contains("TEE") || $0.contains("T-SHIRT") || $0.contains("HOODIE") || $0.contains("CREWNECK") || $0.contains("SWEATSHIRT") || test($0, #"\bSWEATS\b"#) || $0 == "HEART MARK TANK" },
        ShopCollection(slug: "art-supplies", name: "ART SUPPLIES") { test($0, "NOTEBOOK|JOURNAL|NOTEPAD|POSTCARD|GREETING CARD|MAGNET|PIN BUTTON") },
        ShopCollection(slug: "home-goods", name: "HOME GOODS") { $0.contains("POSTER") || $0.contains("STICKER") || $0.contains("TUMBLER") || $0.contains("MUG") || $0.contains("COASTER") },
    ]

    static func named(_ slug: String) -> ShopCollection? { all.first { $0.slug == slug } }
}

/// The three on the shop page: the permanent line, the visual vocabulary, the three-year run (`Collections.tsx`, its words kept).
struct ShopShelfEntry: Identifiable {
    let slug: String
    let label: String
    let name: String
    let blurb: String
    var limited = false
    var id: String { slug }

    static let three: [ShopShelfEntry] = [
        ShopShelfEntry(slug: "classics", label: "Permanent Collection", name: "Classic", blurb: "The institution. Heart and hands on the golden spiral. This is the floor. It never leaves."),
        ShopShelfEntry(slug: "glyphs", label: "The Visual Vocabulary", name: "Glyphs", blurb: "Crown. Smile. Heart. Money. Choose your symbol. Wear your position."),
        ShopShelfEntry(slug: "seeds", label: "The Three-Year Run", name: "Seeds", blurb: "Three years. Then they\u{2019}re gone. What you wore becomes what you lived through.", limited: true),
    ]
}

// MARK: - Filter drawer

enum ShopOrder: String, CaseIterable, Identifiable {
    case newest = "Newest", low = "Price, low to high", high = "Price, high to low", name = "Name"
    var id: String { rawValue }
}

struct ShopFacet: Identifiable {
    let key: String
    let title: String
    let match: @Sendable (String) -> Bool
    var id: String { key }

    private static func coll(_ slug: String, _ title: String) -> ShopFacet {
        let c = ShopCollection.named(slug)
        return ShopFacet(key: slug, title: title, match: { c?.match($0) ?? false })
    }

    static let garments: [ShopFacet] = [
        coll("tees", "Tees"), coll("hoodies", "Hoodies"), coll("crewnecks", "Crewnecks"), coll("sweats", "Sweats"), coll("crops", "Crops"),
        ShopFacet(key: "headwear", title: "Headwear") { test($0, #"BEANIE|HAT|CAP\b"#) },
        ShopFacet(key: "objects", title: "Objects & Prints") { test($0, "POSTER|STICKER|TUMBLER|TOWEL|BANDANA|GAITER|MUG") },
    ]

    static let lines: [ShopFacet] = [
        coll("classics", "Classics"), coll("glyphs", "Glyphs"), coll("seeds", "Seeds"), coll("poverty-to-luxury", "Poverty to Luxury"),
    ]
}

struct ShopPriceBucket: Identifiable {
    let key: String
    let title: String
    let test: @Sendable (Int) -> Bool
    var id: String { key }

    static let all: [ShopPriceBucket] = [
        ShopPriceBucket(key: "under-30", title: "Under $30") { $0 < 3000 },
        ShopPriceBucket(key: "30-60", title: "$30 \u{2013} $60") { $0 >= 3000 && $0 < 6000 },
        ShopPriceBucket(key: "60-plus", title: "$60+") { $0 >= 6000 },
    ]
}

struct ShopFilter: Equatable {
    var garments: Set<String> = []
    var lines: Set<String> = []
    var prices: Set<String> = []
    var order = ShopOrder.newest
    var inStockOnly = false

    var active: Int { garments.count + lines.count + prices.count + (order == .newest ? 0 : 1) + (inStockOnly ? 1 : 0) }

    func apply(_ pieces: [ShopPiece], query: String = "") -> [ShopPiece] {
        var out = pieces
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { out = out.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) || ($0.line ?? "").localizedCaseInsensitiveContains(q) } }
        if !garments.isEmpty { let on = ShopFacet.garments.filter { garments.contains($0.key) }; out = out.filter { p in on.contains { $0.match(p.name.uppercased()) } } }
        if !lines.isEmpty { let on = ShopFacet.lines.filter { lines.contains($0.key) }; out = out.filter { p in on.contains { $0.match(p.name.uppercased()) } } }
        if !prices.isEmpty { let on = ShopPriceBucket.all.filter { prices.contains($0.key) }; out = out.filter { p in on.contains { $0.test(p.minCents) } } }
        if inStockOnly { out = out.filter(\.inStock) }
        switch order {
        case .newest: break   // the site's grid is already newest first
        case .low: out.sort { $0.minCents < $1.minCents }
        case .high: out.sort { $0.minCents > $1.minCents }
        case .name: out.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return out
    }
}

struct ShopFilterSheet: View {
    @Binding var filter: ShopFilter
    let pieces: [ShopPiece]
    let query: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                facetSection("Garment", ShopFacet.garments, keyPath: \.garments)
                facetSection("Line", ShopFacet.lines, keyPath: \.lines)
                Section("Price") {
                    ForEach(ShopPriceBucket.all) { b in
                        row(b.title, count: pieces.filter { b.test($0.minCents) }.count, on: filter.prices.contains(b.key)) { toggle(\.prices, b.key) }
                    }
                }
                Section("Order") {
                    Picker("Order", selection: $filter.order) { ForEach(ShopOrder.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden()
                }
                Section { Toggle("In stock only", isOn: $filter.inStockOnly) }
                if filter.active > 0 {
                    Section { Button("Clear every filter", role: .destructive) { filter = ShopFilter() } }
                }
            }
            .siteList()
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Show \(filter.apply(pieces, query: query).count)") { dismiss() }.fontWeight(.semibold) }
            }
            .sensoryFeedback(PLHaptic.select, trigger: filter)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func facetSection(_ title: String, _ facets: [ShopFacet], keyPath: WritableKeyPath<ShopFilter, Set<String>>) -> some View {
        Section(title) {
            ForEach(facets) { f in
                row(f.title, count: pieces.filter { f.match($0.name.uppercased()) }.count, on: filter[keyPath: keyPath].contains(f.key)) { toggle(keyPath, f.key) }
            }
        }
    }

    private func toggle(_ keyPath: WritableKeyPath<ShopFilter, Set<String>>, _ key: String) {
        if filter[keyPath: keyPath].contains(key) { filter[keyPath: keyPath].remove(key) } else { filter[keyPath: keyPath].insert(key) }
    }

    private func row(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Bone.gold : Color.secondary.opacity(0.5)).symbolEffect(.bounce, value: on)
            }
            .frame(minHeight: PLMetric.touch).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The grid of pieces, shared by the shop and a collection

struct PieceGrid: View {
    let pieces: [ShopPiece]
    @Bindable var state: ShopModel
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 18, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 28) {
            ForEach(pieces) { p in
                NavigationLink { PieceView(slug: p.slug, state: state) } label: { PieceCard(piece: p) }
                    .buttonStyle(.plain)
                    .pieceMenu(p, state: state)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - The three collections, as the shop page opens

struct CollectionsShelf: View {
    let pieces: [ShopPiece]
    @Bindable var state: ShopModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Three collections").siteLabel().frame(maxWidth: .infinity).padding(.bottom, 24)
            SiteRule()
            ForEach(ShopShelfEntry.three) { e in
                let count = ShopCollection.named(e.slug)?.pieces(in: pieces).count ?? 0
                NavigationLink { CollectionView(slug: e.slug, state: state) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(e.label).siteLabel().foregroundStyle(e.limited ? Bone.gold : Bone.inkFaint(scheme))
                            if e.limited {
                                Text("Closing 2029").font(SiteFont.body(10, relativeTo: .caption2)).textCase(.uppercase).tracking(1.6).foregroundStyle(Bone.gold)
                                    .padding(.horizontal, 9).padding(.vertical, 3)
                                    .background(Bone.gold.opacity(0.1), in: Capsule())
                                    .overlay { Capsule().strokeBorder(Bone.gold.opacity(0.3), lineWidth: 0.6) }
                            }
                        }
                        Text(e.name).font(SiteFont.display(46, italic: true)).foregroundStyle(Bone.ink(scheme))
                        Text(e.blurb).siteBody(14)
                        Text((e.limited ? "Closes April 2029 \u{00B7} " : "") + "\(count) pieces \u{00B7} Enter \u{2192}").siteLabel(10)
                    }
                    .padding(.vertical, 28).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                SiteRule()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShopCollection.all.filter { !["classics", "glyphs", "seeds"].contains($0.slug) }) { c in
                        NavigationLink { CollectionView(slug: c.slug, state: state) } label: {
                            Text(c.title).font(SiteFont.body(11, relativeTo: .caption)).textCase(.uppercase).tracking(2).foregroundStyle(Bone.inkSoft(scheme))
                                .padding(.horizontal, 14).frame(minHeight: 40)
                                .overlay { Capsule().strokeBorder(Bone.line(scheme), lineWidth: 0.9) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// `/collections/<slug>`: `Shop / Name`, `The collection \u{2014} N pieces`, the name in italic gold, the pieces.
struct CollectionView: View {
    let slug: String
    @Bindable var state: ShopModel
    private let store = ShopStore.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = ShopCollection.named(slug)
        let pieces = c?.pieces(in: store.pieces) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if CollectionStory.has(slug) {
                    CollectionStory.top(slug)   // the collection's own page on the site (/seeds, /glyphs, /the-heart)
                } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Shop / \(c?.title ?? slug)").siteLabel()
                    Text("The collection \u{2014} \(store.pieces.isEmpty ? "\u{2014}" : "\(pieces.count)") pieces").siteLabel()
                    Text("\(c?.title ?? slug).").font(SiteFont.display(48, italic: true)).foregroundStyle(Bone.gold).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 24).padding(.top, 20)
                }
                if pieces.isEmpty {
                    if store.pieces.isEmpty && store.failure == nil { PLLoader().frame(maxWidth: .infinity, minHeight: 160) }
                    else if let f = store.failure, store.pieces.isEmpty {
                        EmptyNote(symbol: "wifi.exclamationmark", title: "Could not reach the catalogue", detail: f, actionTitle: "Try again") { Task { await store.load(force: true) } }
                    } else {
                        EmptyNote(symbol: "bag", title: "Nothing in this collection yet", detail: "The full shop has everything that is listed today.")
                    }
                } else {
                    PieceGrid(pieces: pieces, state: state)
                }
                if CollectionStory.has(slug) { CollectionStory.bottom(slug) }
            }
            .padding(.bottom, 32)
        }
        .siteScreen()
        .navigationTitle(c?.title ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load(force: true) }
    }
}
