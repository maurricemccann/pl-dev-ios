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
            if let l = piece.line { Text(l).font(SiteFont.body(12)).italic().foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(3).lineLimit(2) }
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

// MARK: - The grid (the site's /shop: the page's opening, the three collections, then everything)

struct ShopGridView: View {
    @Bindable var state: ShopModel
    private let store = ShopStore.shared

    @State private var query = ""
    @State private var filter = ShopFilter()
    @State private var filtering = false
    @Environment(\.colorScheme) private var scheme

    private var shown: [ShopPiece] { filter.apply(store.pieces, query: query) }
    private var browsing: Bool { filter.active == 0 && query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // the site's home page opens the tab; a search or a filter goes straight to the pieces
                if browsing { ShopHomeView(state: state) }
                SitePageHead(eyebrow: "The shop" + (store.pieces.isEmpty ? "" : " \u{2014} \(store.pieces.count) pieces"), lead: "Wearable", accent: "doctrine.",
                             lede: "A Psyched Luxuries piece is a wearable argument. The price is the first argument. The art is the second. What you do after you put it on is the third.")
                    .id("shop-head")
                if !store.pieces.isEmpty {
                    if browsing { CollectionsShelf(pieces: store.pieces, state: state).padding(.top, 8) }
                    TipView(PieceHoldTip()).padding(.horizontal, 24)
                    Text("Everything").siteLabel().padding(.horizontal, 24).padding(.top, browsing ? 12 : 0)
                    HStack {
                        Text("\(shown.count) of \(store.pieces.count) pieces").siteLabel(10).contentTransition(.numericText())
                        Spacer()
                        Button { filtering = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal.decrease")
                                Text(filter.active > 0 ? "Filter \u{00B7} \(filter.active)" : "Filter")
                            }
                            .font(SiteFont.body(11, relativeTo: .caption, weight: filter.active > 0 ? .medium : .regular)).textCase(.uppercase).tracking(2)
                            .foregroundStyle(filter.active > 0 ? Color(hex: 0x15120b) : Bone.ink(scheme))
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .background { if filter.active > 0 { Capsule().fill(Bone.gold) } }
                            .overlay { Capsule().strokeBorder(filter.active > 0 ? Color.clear : Bone.line(scheme), lineWidth: 0.9) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.active > 0 ? "Filter, \(filter.active) on" : "Filter")
                    }
                    .padding(.horizontal, 24)
                    SiteRule().padding(.horizontal, 24)
                }
                content
            }
            .padding(.bottom, 32)
        }
        .onChange(of: state.homeScroll) { _, _ in withAnimation(.smooth) { proxy.scrollTo("shop-head", anchor: .top) } }
        }
        .siteScreen()
        .searchable(text: $query, prompt: "Search the shop")
        .refreshable { await store.load(force: true) }
        .task { await store.load() }
        .sheet(isPresented: $filtering) { ShopFilterSheet(filter: $filter, pieces: store.pieces, query: query) }
        .sensoryFeedback(PLHaptic.select, trigger: filter.active)
    }

    @ViewBuilder private var content: some View {
        if store.pieces.isEmpty {
            if let f = store.failure {
                EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the shop", detail: f, actionTitle: "Try again") { Task { await store.load(force: true) } }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18, alignment: .top)], spacing: PLSpace.margin) {
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
                query = ""; filter = ShopFilter()
            }
        } else {
            PieceGrid(pieces: shown, state: state)
        }
    }
}

// MARK: - A piece

/// A line that opens and closes, as the site's `<details>` rows do: tracked capitals, a gold plus that turns.
struct SiteFold: View {
    let title: String
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    Text(title).siteLabel()
                    Spacer()
                    Image(systemName: "plus").font(.footnote.weight(.regular)).foregroundStyle(Bone.gold).rotationEffect(.degrees(open ? 45 : 0))
                }
                .frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(open ? "Open" : "Closed")
            if open { Text(text).siteBody(15).padding(.bottom, 16).transition(.opacity) }
            SiteRule()
        }
    }
}

/// The size and fit table, a manufacturer's chart read off the piece's page.
struct SizeGuideView: View {
    let guide: PieceDetail.Guide
    @State private var open = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    Text("Size & fit").siteLabel()
                    Spacer()
                    Image(systemName: "plus").font(.footnote).foregroundStyle(Bone.gold).rotationEffect(.degrees(open ? 45 : 0))
                }
                .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 0) {
                            GridRow {
                                Text("Size").siteLabel(10).gridColumnAlignment(.leading)
                                ForEach(guide.columns, id: \.self) { Text($0).siteLabel(10) }
                            }
                            .padding(.vertical, 8)
                            Divider().overlay(Bone.line(scheme))
                            ForEach(Array(guide.rows.enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                                        Text(cell).font(SiteFont.body(14)).foregroundStyle(i == 0 ? Bone.ink(scheme) : Bone.inkSoft(scheme)).monospacedDigit()
                                    }
                                }
                                .padding(.vertical, 9)
                                Divider().overlay(Bone.line(scheme).opacity(0.5))
                            }
                        }
                    }
                    if let note = guide.note { Text(note).font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(4) }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
    }
}

struct PieceView: View {
    let slug: String
    @Bindable var state: ShopModel
    private let store = ShopStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    @State private var design: String?
    @State private var color: String?
    @State private var size: String?
    @State private var page = 0
    @State private var web: WebPage?
    @State private var line: String?
    @State private var started = false
    @State private var detail: PieceDetail?

    private var piece: ShopPiece? {
        guard let base = store.piece(slug) else { return nil }
        return detail.map { $0.applied(to: base) } ?? base
    }

    var body: some View {
        Group {
            if let piece { content(piece) }
            else if store.pieces.isEmpty && store.failure == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { EmptyNote(symbol: "bag", title: "That piece is not in the shop", detail: "It may have been retired. The shop's list has what is there now.") }
        }
        .siteScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: slug) {
            await store.load()
            if let d = await PieceDetail.fetch(slug) {
                detail = d
                if let base = store.piece(slug), base.thin == true, !d.variants.isEmpty { store.adopt(d.applied(to: base)) }
                if let p = piece { started = false; start(p) }
            }
        }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func content(_ piece: ShopPiece) -> some View {
        let variant = piece.variant(design: design, color: color, size: size)
        let images = piece.images
        let axiom = detail?.axiom
        let about = piece.description.isEmpty ? detail?.about : piece.description
        let related = Array((detail?.related ?? []).compactMap { store.piece($0) }.filter { $0.slug != slug }.prefix(4))
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
                    Text(axiom ?? piece.group.title).siteLabel()
                    Text(piece.name).font(SiteFont.display(34)).foregroundStyle(Bone.ink(scheme)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Rectangle().fill(Bone.gold).frame(width: 64, height: 1)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(variant.map { Money.text($0.cents) } ?? piece.priceLine).font(SiteFont.display(24, italic: true)).foregroundStyle(Bone.gold).monospacedDigit().contentTransition(.numericText())
                        if let v = variant, !v.inStock { Text("Sold out").siteLabel(10) }
                    }
                }
                .padding(.horizontal, 24)

                if let prov = detail?.provenance {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provenance").siteLabel(10).foregroundStyle(Bone.gold)
                        Text(prov).font(SiteFont.body(14)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(4)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Bone.gold.opacity(0.3), lineWidth: 0.8) }
                    .padding(.horizontal, 24)
                }

                if let guide = detail?.guide { SizeGuideView(guide: guide).padding(.horizontal, 24) }

                if piece.designs.count > 1 {
                    pickerBlock("Design", options: piece.designs, selection: $design, enabled: { d in piece.variants.contains { $0.design == d && $0.inStock } })
                }
                if piece.colors(design: design).count > 1 {
                    pickerBlock("Colour", options: piece.colors(design: design), selection: $color, enabled: { c in piece.variants.contains { ($0.design == design || design == nil) && $0.color == c && $0.inStock } })
                }
                if piece.sizes.count > 1 {
                    pickerBlock("Size", options: piece.sizes, selection: $size,
                                enabled: { s in piece.variants.contains { ($0.design == design || design == nil) && $0.color == color && $0.size == s && $0.inStock } || (color == nil && piece.variants.contains { $0.size == s && $0.inStock }) })
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
                    ResultLine(text: line)
                    Text(detail?.returnsLine ?? "30 days to report a flaw. Damaged, defective, or not what you ordered \u{2014} remade free, nothing sent back, and you keep the original. Every piece is made for one person after they order it, so check the size guide before you decide.")
                        .font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(4)
                }
                .padding(.horizontal, 24)

                if let about, !about.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About this piece").siteLabel()
                        Text(about).siteBody(15)
                    }
                    .padding(.horizontal, 24)
                }

                if let folds = detail?.folds, !folds.isEmpty {
                    VStack(spacing: 0) {
                        SiteRule()
                        ForEach(folds) { SiteFold(title: $0.title, text: $0.text) }
                    }
                    .padding(.horizontal, 24)
                }

                if let arg = detail?.argument ?? piece.line {
                    VStack(alignment: .leading, spacing: 12) {
                        SiteRule()
                        Text("The argument").siteLabel().padding(.top, 8)
                        Text(arg).font(SiteFont.body(15)).italic().foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(5)
                    }
                    .padding(.horizontal, 24)
                }

                if detail?.twin == true {
                    VStack(alignment: .leading, spacing: 8) {
                        SiteRule()
                        Text("The digital twin").siteLabel().padding(.top, 8)
                        Text("Worn on the street and on the avatar \u{2014} one object, two bodies. Turn it in 3D, place it in your room.").siteBody(14)
                        NavigationLink { WardrobeView() } label: { Text("The Wardrobe \u{2192}").siteLabel(10).frame(minHeight: 44, alignment: .leading) }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SiteRule()
                    Text("The congregation").siteLabel().padding(.top, 8)
                    Text("Decisions declared by others who prepared the same ground. The archive is the evidence \u{2014} every piece dated, documented, one hand.").siteBody(14)
                    Button { if let url = URL(string: "pldev://section/congregation/stream") { openURL(url) } } label: { Text("See the wall \u{2192}").siteLabel(10).frame(minHeight: 44, alignment: .leading) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                if let truth = axiom {
                    VStack(spacing: 14) {
                        Text("The Truth").siteLabel().foregroundStyle(Bone.gold)
                        Text(truth + ".").font(SiteFont.display(30, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        NavigationLink { SiteReaderView(path: "the-three-truths", title: "The Three Truths") } label: { Text("The Three Truths \u{2192}").siteLabel(10).frame(minHeight: 44) }.buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 24)
                }

                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("More from the drop").siteLabel().frame(maxWidth: .infinity)
                        PieceGrid(pieces: related, state: state)
                    }
                }
            }
            .padding(.vertical, 8).padding(.bottom, 24)
        }
        .navigationTitle(piece.name)
        .sensoryFeedback(PLHaptic.select, trigger: color)
        .sensoryFeedback(PLHaptic.select, trigger: size)
        .sensoryFeedback(PLHaptic.select, trigger: design)
        .onAppear { start(piece) }
        .onChange(of: design) { _, d in
            // a design's own picture leads: jump to it, and keep a colour that exists in that design
            if let first = piece.variants.first(where: { $0.design == d })?.images.first, let i = piece.images.firstIndex(of: first) { withAnimation { page = i } }
            let cs = piece.colors(design: d)
            if let c = color, !cs.contains(c) { color = cs.first }
        }
        .onChange(of: color) { _, c in
            // the colour's own pictures lead: jump to its first flat
            if let first = piece.variants.first(where: { ($0.design == design || design == nil) && $0.color == c })?.images.first, let i = piece.images.firstIndex(of: first) { withAnimation { page = i } }
            if let s = size, !piece.variants.contains(where: { ($0.design == design || design == nil) && $0.color == c && $0.size == s && $0.inStock }) {
                size = piece.variants.first { ($0.design == design || design == nil) && $0.color == c && $0.inStock }?.size
            }
        }
    }

    /// Opens on the first variant that is in stock, once.
    private func start(_ piece: ShopPiece) {
        guard !started else { return }
        started = true
        let lead = piece.variants.first { $0.inStock } ?? piece.variants.first
        design = lead?.design
        color = lead?.color
        size = lead?.size
    }

    private func buyPath(_ piece: ShopPiece, _ v: ShopVariant?) -> String {
        guard let v, !v.id.isEmpty else { return "shop/\(piece.slug)" }
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
