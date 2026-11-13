import SwiftUI
import TipKit

// The shop grid and the piece page. Pictures are the site's transparent flats only (ShopCatalogue drops everything else).

/// A flat garment picture on the card's plate. A piece with no flat yet shows a quiet hanger, never a borrowed photograph.
struct FlatImage: View {
    let url: URL?
    var padding: CGFloat = PLSpace.pad

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().padding(padding)
                    case .failure: Image(systemName: "photo").font(.title).foregroundStyle(Bone.inkFaint(.light).opacity(0.5))
                    default: ProgressView()
                    }
                }
            } else {
                Image(systemName: "hanger").font(.largeTitle).foregroundStyle(Bone.inkFaint(.light).opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PieceCard: View {
    let piece: ShopPiece
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // the site's tile: the transparent flat sits straight on the ground (no plate), as `.pl-img-wrap` does
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { FlatImage(url: piece.hero, padding: 4) }
                .overlay(alignment: .topLeading) {
                    if !piece.inStock { Text("Sold out").siteLabel(9).padding(.top, 2) }
                }
            Text(piece.name).font(SiteFont.display(21)).foregroundStyle(Bone.ink(scheme)).lineLimit(2).multilineTextAlignment(.leading)
            Text(piece.priceLine).siteLabel(10).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(piece.name), \(piece.priceLine)\(piece.inStock ? "" : ", sold out")")
        .accessibilityAddTraits(.isButton)
    }
}

/// The two things a piece's context menu does everywhere it shows: share it, and put it in the Closet.
struct PieceMenu: ViewModifier {
    let piece: ShopPiece
    let state: ShopModel?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let url = Site.page("shop/\(piece.slug)") { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
            if let slot = ClosetSlot.of(piece.group) {
                Button {
                    ClosetState.shared.put(piece, in: slot)
                    state?.tick += 1
                } label: { Label("Put in the Closet", systemImage: "hanger") }
            }
        }
    }
}

extension View {
    func pieceMenu(_ piece: ShopPiece, state: ShopModel?) -> some View { modifier(PieceMenu(piece: piece, state: state)) }
}

// MARK: - The grid

struct ShopGridView: View {
    @Bindable var state: ShopModel
    private let store = ShopStore.shared

    enum Order: String, CaseIterable, Identifiable {
        case shop = "The shop's order", low = "Price, low to high", high = "Price, high to low", name = "Name"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var group: ShopGroup?
    @State private var order = Order.shop
    @State private var inStockOnly = false

    private var shown: [ShopPiece] {
        var list = store.pieces
        if let group { list = list.filter { $0.group == group } }
        if inStockOnly { list = list.filter(\.inStock) }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) } }
        switch order {
        case .shop: break
        case .low: list.sort { $0.minCents < $1.minCents }
        case .high: list.sort { $0.minCents > $1.minCents }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return list
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 18, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SitePageHead(eyebrow: "The shop" + (store.pieces.isEmpty ? "" : " \u{2014} \(store.pieces.count) pieces"), lead: "Wearable", accent: "doctrine.",
                             lede: "A Psyched Luxuries piece is a wearable argument. The price is the first argument. The art is the second. What you do after you put it on is the third.")
                if !store.pieces.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            SiteChip(title: "All", on: group == nil) { withAnimation(.smooth) { group = nil } }
                            ForEach(ShopGroup.allCases) { g in
                                let n = store.pieces.filter { $0.group == g }.count
                                if n > 0 { SiteChip(title: "\(g.title) \u{00B7} \(n)", on: group == g) { withAnimation(.smooth) { group = g } } }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    TipView(PieceHoldTip()).padding(.horizontal, 24)
                    Text("\(shown.count) of \(store.pieces.count) pieces").siteLabel(10)
                        .contentTransition(.numericText()).padding(.horizontal, 24)
                    SiteRule().padding(.horizontal, 24)
                }
                content
            }
            .padding(.bottom, 32)
        }
        .siteScreen()
        .searchable(text: $query, prompt: "Search the shop")
        .refreshable { await store.load(force: true) }
        .task { await store.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Order", selection: $order) { ForEach(Order.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("In stock only", isOn: $inStockOnly)
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Order and filter")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if store.pieces.isEmpty {
            if let f = store.failure {
                EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the shop", detail: f, actionTitle: "Try again") { Task { await store.load(force: true) } }
            } else {
                LazyVGrid(columns: columns, spacing: PLSpace.margin) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: PLSpace.tight) {
                            Rectangle().fill(Bone.line(.light).opacity(0.5)).aspectRatio(1, contentMode: .fit)
                            Text("Placeholder piece name").plFont(.subhead); Text("$00.00").plFont(.footnote)
                        }.redacted(reason: .placeholder)
                    }
                }
                .padding(.horizontal, 24).accessibilityLabel("Loading the shop")
            }
        } else if shown.isEmpty {
            EmptyNote(symbol: "magnifyingglass", title: "Nothing matches", detail: "No piece fits that search and filter. Clear one to see more.", actionTitle: "Clear") {
                query = ""; group = nil; inStockOnly = false
            }
        } else {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(shown) { p in
                    NavigationLink { PieceView(slug: p.slug, state: state) } label: { PieceCard(piece: p) }
                        .buttonStyle(.plain)
                        .pieceMenu(p, state: state)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - A piece

struct PieceView: View {
    let slug: String
    @Bindable var state: ShopModel
    private let store = ShopStore.shared
    @Environment(\.colorScheme) private var scheme

    @State private var color: String?
    @State private var size: String?
    @State private var page = 0
    @State private var web: WebPage?
    @State private var line: String?
    @State private var started = false

    var body: some View {
        Group {
            if let piece = store.piece(slug) { content(piece) }
            else if store.pieces.isEmpty && store.failure == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { EmptyNote(symbol: "bag", title: "That piece is not in the shop", detail: "It may have been retired. The shop's list has what is there now.") }
        }
        .siteScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func content(_ piece: ShopPiece) -> some View {
        let variant = piece.variant(color: color, size: size)
        let images = piece.images
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    if images.isEmpty { FlatImage(url: nil) }
                    else {
                        TabView(selection: $page) {
                            ForEach(Array(images.enumerated()), id: \.offset) { i, u in
                                FlatImage(url: URL(string: u), padding: PLSpace.roomy).tag(i).accessibilityLabel("\(piece.name), picture \(i + 1) of \(images.count)")
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
                    }
                }
                .frame(height: 380)
                .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text(piece.group.title).siteLabel()
                    Text(piece.name).font(SiteFont.display(34)).foregroundStyle(Bone.ink(scheme)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(variant.map { Money.text($0.cents) } ?? piece.priceLine).font(SiteFont.display(24, italic: true)).foregroundStyle(Bone.gold).monospacedDigit().contentTransition(.numericText())
                        if let v = variant, !v.inStock { Text("Sold out").siteLabel(10) }
                    }
                }
                .padding(.horizontal, 24)
                SiteRule().padding(.horizontal, 24)

                if piece.colors.count > 1 {
                    pickerBlock("Colour", options: piece.colors, selection: $color, enabled: { c in piece.variants.contains { $0.color == c && $0.inStock } })
                }
                if piece.sizes.count > 1 {
                    pickerBlock("Size", options: piece.sizes, selection: $size,
                                enabled: { s in piece.variants.contains { $0.color == color && $0.size == s && $0.inStock } || (color == nil && piece.variants.contains { $0.size == s && $0.inStock }) })
                }

                if !piece.description.isEmpty {
                    Text(piece.description).siteBody(16).padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    Button {
                        guard let url = Site.page(buyPath(piece, variant)) else { line = "Not opened. The config has no address for the site."; return }
                        web = WebPage(url)
                    } label: {
                        Text("Buy on psychedluxuries.com \u{2192}")
                    }
                    .buttonStyle(SitePill())
                    .disabled(!(variant?.inStock ?? false))
                    HStack(spacing: 12) {
                        if let slot = ClosetSlot.of(piece.group) {
                            Button {
                                ClosetState.shared.put(piece, in: slot, size: size)
                                line = "In the Closet."; state.tick += 1
                            } label: { Text("Closet") }
                                .buttonStyle(SiteGhost())
                        }
                        if let url = Site.page("shop/\(piece.slug)") {
                            ShareLink(item: url) { Text("Share") }
                                .buttonStyle(SiteGhost())
                        }
                    }
                    Button {
                        if let url = Site.page("shop/\(piece.slug)") { web = WebPage(url) }
                    } label: { Text("Size guide and care on the site").siteLabel(10).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.plain)
                    ResultLine(text: line)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 8).padding(.bottom, 24)
        }
        .navigationTitle(piece.name)
        .sensoryFeedback(PLHaptic.select, trigger: color)
        .sensoryFeedback(PLHaptic.select, trigger: size)
        .onAppear { start(piece) }
        .onChange(of: color) { _, c in
            // the colour's own pictures lead: jump to its first flat
            if let first = piece.variants.first(where: { $0.color == c })?.images.first, let i = piece.images.firstIndex(of: first) { withAnimation { page = i } }
            if let s = size, !piece.variants.contains(where: { $0.color == c && $0.size == s && $0.inStock }) { size = piece.variants.first { $0.color == c && $0.inStock }?.size }
        }
    }

    /// Opens on the first variant that is in stock, once.
    private func start(_ piece: ShopPiece) {
        guard !started else { return }
        started = true
        let lead = piece.variants.first { $0.inStock } ?? piece.variants.first
        color = lead?.color
        size = lead?.size
    }

    private func buyPath(_ piece: ShopPiece, _ v: ShopVariant?) -> String {
        guard let v else { return "shop/\(piece.slug)" }
        return "shop/\(piece.slug)?variant=\(v.id)"
    }

    private func pickerBlock(_ title: String, options: [String], selection: Binding<String?>, enabled: @escaping (String) -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).siteLabel(10).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { o in
                        let ok = enabled(o)
                        SiteChip(title: o, on: selection.wrappedValue == o, dim: !ok) { selection.wrappedValue = o }
                            .strikethrough(!ok)
                            .accessibilityLabel("\(o)\(ok ? "" : ", sold out")")
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
