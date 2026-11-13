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
                    case .failure: Image(systemName: "photo").font(.title).foregroundStyle(.tertiary)
                    default: ProgressView()
                    }
                }
            } else {
                Image(systemName: "hanger").font(.largeTitle).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PieceCard: View {
    let piece: ShopPiece

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpace.tight) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { FlatImage(url: piece.hero) }
                .background(PLTone.surface, in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if !piece.inStock {
                        Text("Sold out").plFont(.caption2, emphasized: true).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule()).padding(PLSpace.gap)
                    }
                }
            Text(piece.name).plFont(.subhead, emphasized: true).lineLimit(2).multilineTextAlignment(.leading)
            Text(piece.priceLine).plFont(.footnote).foregroundStyle(.secondary).monospacedDigit()
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

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: PLSpace.margin, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PLSpace.margin) {
                if !store.pieces.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PLSpace.gap) {
                            chip("All", nil)
                            ForEach(ShopGroup.allCases) { g in
                                let n = store.pieces.filter { $0.group == g }.count
                                if n > 0 { chip("\(g.title) · \(n)", g) }
                            }
                        }
                        .padding(.horizontal, PLSpace.margin)
                    }
                    TipView(PieceHoldTip()).padding(.horizontal, PLSpace.margin)
                    Text("\(shown.count) of \(store.pieces.count) pieces").plFont(.footnote).foregroundStyle(.secondary)
                        .contentTransition(.numericText()).padding(.horizontal, PLSpace.margin)
                }
                content
            }
            .padding(.vertical, PLSpace.gap)
        }
        .background(PLTone.canvas)
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
                            RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous).fill(PLTone.surface).aspectRatio(1, contentMode: .fit)
                            Text("Placeholder piece name").plFont(.subhead); Text("$00.00").plFont(.footnote)
                        }.redacted(reason: .placeholder)
                    }
                }
                .padding(.horizontal, PLSpace.margin).accessibilityLabel("Loading the shop")
            }
        } else if shown.isEmpty {
            EmptyNote(symbol: "magnifyingglass", title: "Nothing matches", detail: "No piece fits that search and filter. Clear one to see more.", actionTitle: "Clear") {
                query = ""; group = nil; inStockOnly = false
            }
        } else {
            LazyVGrid(columns: columns, spacing: PLSpace.roomy) {
                ForEach(shown) { p in
                    NavigationLink { PieceView(slug: p.slug, state: state) } label: { PieceCard(piece: p) }
                        .buttonStyle(.plain)
                        .pieceMenu(p, state: state)
                }
            }
            .padding(.horizontal, PLSpace.margin)
        }
    }

    private func chip(_ title: String, _ g: ShopGroup?) -> some View {
        let on = group == g
        return Button { withAnimation(.smooth) { group = g } } label: {
            Text(title).plFont(.callout, emphasized: on).padding(.horizontal, PLSpace.pad).frame(minHeight: PLMetric.touch - 8)
                .background(on ? PLTone.accent.opacity(0.22) : PLTone.well, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - A piece

struct PieceView: View {
    let slug: String
    @Bindable var state: ShopModel
    private let store = ShopStore.shared

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
        .background(PLTone.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func content(_ piece: ShopPiece) -> some View {
        let variant = piece.variant(color: color, size: size)
        let images = piece.images
        return ScrollView {
            VStack(alignment: .leading, spacing: PLSpace.margin) {
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
                .background(PLTone.surface, in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                .padding(.horizontal, PLSpace.margin)

                VStack(alignment: .leading, spacing: PLSpace.gap) {
                    Text(piece.name).plTitle(.title2).accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline) {
                        Text(variant.map { Money.text($0.cents) } ?? piece.priceLine).plFont(.title3).monospacedDigit().contentTransition(.numericText())
                        if let v = variant, !v.inStock { Text("Sold out").plFont(.callout).foregroundStyle(.secondary) }
                    }
                }
                .padding(.horizontal, PLSpace.margin)

                if piece.colors.count > 1 {
                    pickerBlock("Colour", options: piece.colors, selection: $color, enabled: { c in piece.variants.contains { $0.color == c && $0.inStock } })
                }
                if piece.sizes.count > 1 {
                    pickerBlock("Size", options: piece.sizes, selection: $size,
                                enabled: { s in piece.variants.contains { $0.color == color && $0.size == s && $0.inStock } || (color == nil && piece.variants.contains { $0.size == s && $0.inStock }) })
                }

                if !piece.description.isEmpty {
                    Text(piece.description).plFont(.body).plReading().padding(.horizontal, PLSpace.margin)
                }

                VStack(spacing: PLSpace.pad) {
                    Button {
                        guard let url = Site.page(buyPath(piece, variant)) else { line = "Not opened. The config has no address for the site."; return }
                        web = WebPage(url)
                    } label: {
                        Label("Buy on psychedluxuries.com", systemImage: "bag").frame(maxWidth: .infinity, minHeight: PLMetric.touch)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(variant?.inStock ?? false))
                    HStack(spacing: PLSpace.pad) {
                        if let slot = ClosetSlot.of(piece.group) {
                            Button {
                                ClosetState.shared.put(piece, in: slot, size: size)
                                line = "In the Closet."; state.tick += 1
                            } label: { Label("Closet", systemImage: "hanger").frame(maxWidth: .infinity, minHeight: PLMetric.touch) }
                                .buttonStyle(.bordered)
                        }
                        if let url = Site.page("shop/\(piece.slug)") {
                            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: PLMetric.touch) }
                                .buttonStyle(.bordered)
                        }
                    }
                    Button {
                        if let url = Site.page("shop/\(piece.slug)") { web = WebPage(url) }
                    } label: { Label("Size guide and care on the site", systemImage: "ruler").frame(maxWidth: .infinity, minHeight: PLMetric.touch) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    ResultLine(text: line)
                }
                .padding(.horizontal, PLSpace.margin)
            }
            .padding(.vertical, PLSpace.gap)
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
        VStack(alignment: .leading, spacing: PLSpace.gap) {
            Text(title).plFont(.footnote, emphasized: true).foregroundStyle(.secondary).padding(.horizontal, PLSpace.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PLSpace.gap) {
                    ForEach(options, id: \.self) { o in
                        let on = selection.wrappedValue == o
                        let ok = enabled(o)
                        Button { selection.wrappedValue = o } label: {
                            Text(o).plFont(.callout, emphasized: on).strikethrough(!ok).padding(.horizontal, PLSpace.pad).frame(minWidth: PLMetric.touch, minHeight: PLMetric.touch)
                                .background(on ? PLTone.accent.opacity(0.22) : PLTone.well, in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                                .opacity(ok ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(o)\(ok ? "" : ", sold out")")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, PLSpace.margin)
            }
        }
    }
}
