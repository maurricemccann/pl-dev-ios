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

struct ClosetView: View {
    @Bindable var state: ShopModel
    private let store = ShopStore.shared
    private let closet = ClosetState.shared
    @State private var web: WebPage?
    @State private var confirmClear = false

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

    private func price(_ p: ShopPiece) -> Int {
        let size = closet.sizes[p.slug]
        return (p.variants.first { $0.size == size && $0.inStock } ?? p.variants.first { $0.inStock } ?? p.variants.first)?.cents ?? p.minCents
    }

    var body: some View {
        List {
            if store.pieces.isEmpty {
                if let f = store.failure { EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the shop", detail: f, actionTitle: "Try again") { Task { await store.load(force: true) } } }
                else { SkeletonRow() }
            } else {
                Section {
                    if chosen.isEmpty {
                        ContentUnavailableView("Nothing hung yet", systemImage: "hanger", description: Text("Pick a piece for each slot below, or hang one of the house looks."))
                            .listRowBackground(Color.clear)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PLSpace.pad) {
                                ForEach(chosen) { c in
                                    Color.clear.frame(width: 130, height: 150)
                                        .overlay { FlatImage(url: c.piece.hero, padding: 4) }
                                        .background(Bone.line(.light).opacity(0.4), in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                                        .accessibilityLabel(c.piece.name)
                                }
                            }
                            .padding(.vertical, PLSpace.gap)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: PLSpace.margin, bottom: 0, trailing: PLSpace.margin))
                        LabeledContent {
                            Text(Money.text(chosen.reduce(0) { $0 + price($1.piece) })).monospacedDigit().contentTransition(.numericText())
                        } label: {
                            Label("\(chosen.count) \(chosen.count == 1 ? "piece" : "pieces")", systemImage: "hanger")
                        }
                    }
                } header: { Text("Your look") } footer: { if !chosen.isEmpty { Text("Each piece buys on the site, one at a time.") } }

                Section("House looks") {
                    ForEach(HouseLooks.all) { look in
                        let have = look.slugs.filter { store.piece($0) != nil }
                        if !have.isEmpty {
                            Button { closet.hang(have, from: store); state.tick += 1 } label: {
                                LabeledContent(look.name) { Text("\(have.count) pieces").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }

                ForEach(ClosetSlot.allCases) { slot in
                    let pieces = rack(slot)
                    if !pieces.isEmpty {
                        Section(slot.title) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: PLSpace.gap) {
                                    ForEach(pieces) { p in
                                        let on = closet.slug(for: slot) == p.slug
                                        Button { if on { closet.remove(slot) } else { closet.put(p, in: slot) }; state.tick += 1 } label: {
                                            VStack(spacing: PLSpace.hair) {
                                                Color.clear.frame(width: 92, height: 104).overlay { FlatImage(url: p.hero, padding: 2) }
                                                    .background(on ? Bone.gold.opacity(0.28) : Bone.line(.light).opacity(0.4), in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                                                    .overlay(alignment: .topTrailing) { if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Bone.gold).padding(4) } }
                                                Text(p.name).plFont(.caption2).lineLimit(2).frame(width: 92)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(p.name)\(on ? ", in your look. Tap to take out" : "")")
                                    }
                                }
                                .padding(.vertical, PLSpace.tight)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: PLSpace.margin, bottom: 0, trailing: PLSpace.margin))
                            if let s = closet.slug(for: slot), let p = store.piece(s) {
                                Picker("Size", selection: Binding(get: { closet.sizes[p.slug] ?? p.sizes.first ?? "" }, set: { closet.setSize($0, for: p.slug) })) {
                                    ForEach(p.sizes, id: \.self) { Text($0).tag($0) }
                                }
                                Button {
                                    let v = p.variants.first { $0.size == closet.sizes[p.slug] && $0.inStock } ?? p.variants.first { $0.inStock }
                                    if let url = Site.page("shop/\(p.slug)" + (v.map { "?variant=\($0.id)" } ?? "")) { web = WebPage(url) }
                                } label: { Label("Buy \(p.name)", systemImage: "bag") }
                            }
                        }
                    }
                }

                if !chosen.isEmpty {
                    Section {
                        Button(role: .destructive) { confirmClear = true } label: { Label("Clear the look", systemImage: "trash") }
                    }
                }
            }
        }
        .siteList()
        .refreshable { await store.load(force: true) }
        .task { await store.load() }
        .confirmationDialog("Clear your look?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear the look", role: .destructive) { closet.clear(); state.tick += 1 }
        } message: { Text("This takes every piece out of the Closet. Nothing is bought or changed on the site.") }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }
}
