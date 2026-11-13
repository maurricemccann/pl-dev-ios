import SwiftUI

// The Closet: hang a look, wear it together. The site's Closet (lib/closet.ts) in the phone's hands, flats only: one piece per
// slot, a size each, the total. No model, no body, no photograph of anyone (hard-limits, Product imagery); the outfit is the
// garments' own transparent flats side by side. Buying goes through the site, one piece at a time.

enum ClosetSlot: String, CaseIterable, Identifiable, Codable {
    case layer, top, bottom, accessory
    var id: String { rawValue }
    var title: String {
        switch self { case .layer: return "Layer"; case .top: return "Top"; case .bottom: return "Bottom"; case .accessory: return "Accessory" }
    }
    var group: ShopGroup {
        switch self { case .layer: return .layers; case .top: return .tops; case .bottom: return .bottoms; case .accessory: return .accessories }
    }
    static func of(_ g: ShopGroup) -> ClosetSlot? { allCases.first { $0.group == g } }
}

/// The looks the site hangs by default, by piece slug. A look keeps only the pieces that are in the shop today.
struct HouseLook: Identifiable {
    let name: String
    let slugs: [String]
    var id: String { name }
}

enum HouseLooks {
    static let all: [HouseLook] = [
        HouseLook(name: "Heart Mark", slugs: ["heart-mark-crop", "heart-mark-sweats", "heart-mark-sling-bag"]),
        HouseLook(name: "Poverty to Luxury", slugs: ["psyched-zip-hoodie", "poverty-to-luxury-crewneck", "poverty-to-luxury-sweats"]),
        HouseLook(name: "Glyph", slugs: ["glyph-hoodie", "glyph-tee", "glyph-sweats"]),
    ]
}

@MainActor @Observable final class ClosetState {
    static let shared = ClosetState()

    private(set) var picks: [String: String] = [:]   // slot raw value -> piece slug
    private(set) var sizes: [String: String] = [:]   // piece slug -> chosen size
    private let key = "pldev.closet"

    private struct Saved: Codable { var picks: [String: String]; var sizes: [String: String] }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) { picks = s.picks; sizes = s.sizes }
    }

    private func save() { if let d = try? JSONEncoder().encode(Saved(picks: picks, sizes: sizes)) { UserDefaults.standard.set(d, forKey: key) } }

    func put(_ piece: ShopPiece, in slot: ClosetSlot, size: String? = nil) {
        picks[slot.rawValue] = piece.slug
        if let size { sizes[piece.slug] = size }
        save()
    }

    func remove(_ slot: ClosetSlot) { picks[slot.rawValue] = nil; save() }
    func clear() { picks = [:]; save() }
    func setSize(_ size: String, for slug: String) { sizes[slug] = size; save() }

    func slug(for slot: ClosetSlot) -> String? { picks[slot.rawValue] }

    /// Hangs a house look: replaces the slots its pieces fill.
    func hang(_ slugs: [String], from store: ShopStore) {
        for s in slugs {
            guard let p = store.piece(s), let slot = ClosetSlot.of(p.group) else { continue }
            picks[slot.rawValue] = p.slug
        }
        save()
    }
}

/// The Closet, as the site's `/shop` hangs it (components/shop/TheCloset.tsx): "Hang a look. Wear it together." A stage with the
/// look's flats and a rail of the four slots, the rack for the chosen slot, a size for each piece with its price, the house's
/// own looks, the count and the total. Flats only: no model, no body (hard-limits, Product imagery).
struct ClosetView: View {
    @Bindable var state: ShopModel
    private let store = ShopStore.shared
    private let closet = ClosetState.shared
    @State private var active = ClosetSlot.top
    @State private var web: WebPage?
    @State private var confirmClear = false
    @State private var together = false
    @Environment(\.colorScheme) private var scheme

    /// The pieces that are on the rack: in stock, and with a flat to hang.
    private func rack(_ slot: ClosetSlot) -> [ShopPiece] {
        store.pieces.filter { $0.group == slot.group && $0.inStock && $0.hero != nil }
    }

    private struct Hung: Identifiable {
        let slot: ClosetSlot
        let piece: ShopPiece
        var id: String { piece.slug }
    }

    private var chosen: [Hung] {
        ClosetSlot.allCases.compactMap { slot in
            guard let s = closet.slug(for: slot), let p = store.piece(s) else { return nil }
            return Hung(slot: slot, piece: p)
        }
    }

    private func variant(_ p: ShopPiece) -> ShopVariant? {
        let size = closet.sizes[p.slug]
        return p.variants.first { $0.size == size && $0.inStock } ?? p.variants.first { $0.inStock } ?? p.variants.first
    }

    private func price(_ p: ShopPiece) -> Int { variant(p)?.cents ?? p.minCents }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("The Closet").siteLabel()
                    SiteHeadline(lead: "Hang a look.", accent: "Wear it together.", size: 32)
                }
                .padding(.horizontal, 24).padding(.top, 20)

                if store.pieces.isEmpty {
                    if let f = store.failure { EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the shop", detail: f, actionTitle: "Try again") { Task { await store.load(force: true) } } }
                    else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
                } else {
                    stage
                    rackRow
                    sizes
                    houseLooks
                    footer
                }
            }
            .padding(.bottom, 32)
        }
        .siteScreen()
        .refreshable { await store.load(force: true) }
        .task { await store.load() }
        .confirmationDialog("Clear your look?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear the look", role: .destructive) { closet.clear(); state.tick += 1 }
        } message: { Text("This takes every piece out of the Closet. Nothing is bought or changed on the site.") }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $together) { togetherSheet }
        .sensoryFeedback(PLHaptic.select, trigger: active)
    }

    // MARK: the stage

    private var stageFill: LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [Color(hex: 0x2b2620), Color(hex: 0x1a1612)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xe7e1d3), Color(hex: 0xd6cebb)], startPoint: .top, endPoint: .bottom)
    }

    private var stage: some View {
        let worn = chosen.filter { $0.slot != .accessory }
        let bag = chosen.first { $0.slot == .accessory }
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 10) {
                ForEach(ClosetSlot.allCases) { slot in
                    let hung = closet.slug(for: slot).flatMap { store.piece($0) }
                    Button { active = slot } label: {
                        VStack(spacing: 4) {
                            Group {
                                if let hung { FlatImage(url: hung.hero, padding: 2) } else { Image(systemName: slotSymbol(slot)).font(.title3).foregroundStyle(Bone.inkFaint(scheme)) }
                            }
                            .frame(width: 44, height: 40)
                            Text(slot.title).font(SiteFont.body(9, relativeTo: .caption2)).textCase(.uppercase).tracking(1.2).foregroundStyle(Bone.inkSoft(scheme))
                        }
                        .frame(width: 66, height: 70)
                        .background(Bone.raised(scheme).opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active == slot ? Bone.gold : Bone.line(scheme), lineWidth: active == slot ? 1.6 : 0.6) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slot.title)\(hung.map { ", \($0.name)" } ?? ", empty")")
                    .accessibilityAddTraits(active == slot ? .isSelected : [])
                }
            }
            .padding(12)
            ZStack {
                if worn.isEmpty && bag == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "hanger").font(.largeTitle).foregroundStyle(Bone.inkFaint(scheme))
                        Text("Nothing hung yet").font(SiteFont.display(20, italic: true)).foregroundStyle(Bone.inkSoft(scheme))
                        Text("Pick a piece below, or hang one of the house looks.").siteLabel(9).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: -22) {
                        ForEach(worn) { h in
                            FlatImage(url: h.piece.hero, padding: 0).frame(maxHeight: worn.count > 2 ? 150 : 190)
                                .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 10, y: 8)
                                .accessibilityLabel(h.piece.name)
                        }
                    }
                    .padding(.vertical, 20)
                    if let bag {
                        FlatImage(url: bag.piece.hero, padding: 0).frame(width: 78, height: 78)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
                            .accessibilityLabel(bag.piece.name)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 360)
        .background(stageFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
        .padding(.horizontal, 24)
        .animation(.snappy, value: closet.picks)
    }

    private func slotSymbol(_ s: ClosetSlot) -> String {
        switch s { case .layer: return "jacket"; case .top: return "tshirt"; case .bottom: return "figure.walk"; case .accessory: return "bag" }
    }

    // MARK: the rack

    private var rackRow: some View {
        let pieces = rack(active)
        let hung = closet.slug(for: active).flatMap { store.piece($0) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(active.title + (hung.map { " \u{00B7} " + $0.name } ?? "")).siteLabel().padding(.horizontal, 24)
            if pieces.isEmpty {
                Text("Nothing in stock for this slot today.").font(SiteFont.body(14)).foregroundStyle(Bone.inkFaint(scheme)).padding(.horizontal, 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pieces) { p in
                            let on = closet.slug(for: active) == p.slug
                            Button { if on { closet.remove(active) } else { closet.put(p, in: active) }; state.tick += 1 } label: {
                                FlatImage(url: p.hero, padding: 4).frame(width: 84, height: 92)
                                    .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Bone.gold : Bone.line(scheme), lineWidth: on ? 1.6 : 0.8) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(p.name)\(on ? ", in your look. Tap to take out" : "")")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 24)
                }
                if !chosen.isEmpty {
                    GeometryReader { g in
                        Rectangle().fill(Bone.gold).frame(width: g.size.width * CGFloat(chosen.count) / 4, height: 6)
                    }
                    .frame(height: 6).padding(.horizontal, 24)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: sizes

    private var sizes: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(chosen) { c in
                let p = c.piece
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(p.name) \u{00B7} \(Money.text(price(p)))").siteLabel(10)
                    if p.sizes.count > 1 {
                        Menu {
                            Picker("Size", selection: Binding(get: { closet.sizes[p.slug] ?? variant(p)?.size ?? p.sizes.first ?? "" }, set: { closet.setSize($0, for: p.slug) })) {
                                ForEach(p.sizes, id: \.self) { Text($0).tag($0) }
                            }
                        } label: {
                            HStack {
                                Text(closet.sizes[p.slug] ?? variant(p)?.size ?? p.sizes.first ?? "")
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Bone.inkFaint(scheme))
                            }
                            .font(SiteFont.body(16)).foregroundStyle(Bone.ink(scheme))
                            .padding(.horizontal, 18).frame(minHeight: 48)
                            .overlay { Capsule().strokeBorder(Bone.line(scheme), lineWidth: 0.9) }
                        }
                        .accessibilityLabel("Size for \(p.name)")
                    } else {
                        Text("One size").font(SiteFont.body(14)).foregroundStyle(Bone.inkFaint(scheme))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: house looks, the total

    private var houseLooks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hung by the house").siteLabel(10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HouseLooks.all) { look in
                        let have = look.slugs.filter { store.piece($0) != nil }
                        if !have.isEmpty {
                            Button { closet.hang(have, from: store); state.tick += 1 } label: {
                                Text(look.name).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme)).padding(.horizontal, 18).frame(minHeight: 46)
                                    .overlay { Capsule().strokeBorder(Bone.line(scheme), lineWidth: 0.9) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteRule()
            HStack(alignment: .firstTextBaseline) {
                Text("\(chosen.count) \(chosen.count == 1 ? "piece" : "pieces")").siteLabel(10).contentTransition(.numericText())
                Spacer()
                Text(Money.text(chosen.reduce(0) { $0 + price($1.piece) })).font(SiteFont.display(26)).foregroundStyle(Bone.ink(scheme)).monospacedDigit().contentTransition(.numericText())
            }
            Button { together = true } label: { Text("Wear this together") }
                .buttonStyle(SitePill())
                .disabled(chosen.isEmpty)
            Text("Each piece keeps its own price.").font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme))
            if !chosen.isEmpty {
                Button(role: .destructive) { confirmClear = true } label: { Text("Clear the look").siteLabel(10).frame(minHeight: 44, alignment: .leading) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    /// The site's "Wear this together" checkout is Square's page behind a human check, one cart at a time; here each piece opens
    /// on the site at the size chosen, so the look is bought in the same hands that hung it.
    private var togetherSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Wear this together").font(SiteFont.display(30)).foregroundStyle(Bone.ink(scheme))
                    Text("Each piece buys on the site at the size you chose. Square's checkout takes the pieces one after another.").siteBody(14)
                    ForEach(chosen) { c in
                        let v = variant(c.piece)
                        Button {
                            together = false
                            if let url = Site.page("shop/\(c.piece.slug)" + (v.flatMap { $0.id.isEmpty ? nil : "?variant=\($0.id)" } ?? "")) { web = WebPage(url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.piece.name).font(SiteFont.display(19)).foregroundStyle(Bone.ink(scheme))
                                    Text([closet.sizes[c.piece.slug] ?? v?.size, v?.color].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme))
                                }
                                Spacer()
                                Text(Money.text(price(c.piece))).monospacedDigit().foregroundStyle(Bone.inkSoft(scheme))
                                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Bone.gold)
                            }
                            .padding(.vertical, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!(v?.inStock ?? false))
                        SiteRule()
                    }
                }
                .padding(24)
            }
            .siteScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { together = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
