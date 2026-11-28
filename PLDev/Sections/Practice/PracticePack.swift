import SwiftUI
import WebKit

// One Teacher (S348·9a3e): the pack. A finished lesson earns one card of his art; a unit that turns gold earns a pack of one or
// two cards, each his art or a game card that unlocks that game. The Worker deals them (`POST /api/pack`, one pack per key, for
// good). His rulings 11-15: the backs are the glyph field and nothing tells you what is inside until it opens. The motion follows
// his reference: the pack tears, one gold slab rises and grows, it parts into cards that turn, each stops, squares up, and its
// back burns away in patches to the face.

struct PackCard: Decodable, Sendable, Identifiable, Equatable {
    let kind: String
    let piece: String?
    let game: String?
    let tier: String?   // the finish the server dealt (11-28); nil on packs opened before
    var id: String { kind + (piece ?? game ?? "") }
}

struct PracticePack: Decodable, Sendable, Equatable {
    let key: String
    let cards: [PackCard]
    let earned_at: String
    let new: Bool
}

enum Packs {
    static func open(_ key: String, model: AppModel) async throws -> PracticePack {
        try JSONDecoder().decode(PracticePack.self, from: try await Practice.post("pack", ["key": key], model: model))
    }
    static let tile: UIImage? = Bundle.main.url(forResource: "money-field", withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }
}

/// The glyph field, as a card back and as the ground under the pack.
struct GlyphField: View {
    var strength = 0.5
    var tint = Candle.gold   // the check-in reveal tints it with the step colour between bands
    var body: some View {
        ZStack {
            Candle.card
            if let t = Packs.tile {
                Image(uiImage: t).renderingMode(.template).resizable(resizingMode: .tile).foregroundStyle(tint.opacity(strength))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Patches that close as `progress` goes 0 to 1: what is still drawn is the part of the back not yet burnt away.
struct BurnMask: View {
    let progress: Double
    let seed: Double
    var body: some View {
        Canvas { ctx, size in
            let cols = 10, rows = 14
            let w = size.width / Double(cols), h = size.height / Double(rows)
            for y in 0..<rows {
                for x in 0..<cols {
                    let fx = Double(x), fy = Double(y)
                    let n = sin(fx * 12.9898 + fy * 78.233 + seed) * 43758.5453
                    let grain = n - floor(n)
                    let v = (0.5 + 0.25 * sin(fx * 0.9 + seed) + 0.25 * sin(fy * 0.7 + seed * 1.3)) * 0.85 + 0.15 * grain
                    if v >= progress * 1.2 {
                        ctx.fill(Path(CGRect(x: fx * w - 0.5, y: fy * h - 0.5, width: w + 1, height: h + 1)), with: .color(.white))
                    }
                }
            }
        }
    }
}

struct PackCardView: View {
    let model: AppModel
    let card: PackCard
    let burn: Double
    let seed: Double
    @State private var url: URL?
    @State private var looked = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14 * PLStyle.radius, style: .continuous)
        let lit = burn >= 1
        ZStack {
            face
            if burn < 1 { GlyphField().mask(BurnMask(progress: burn, seed: seed)) }
        }
        .aspectRatio(0.7, contentMode: .fit)
        .clipShape(shape)
        .overlay { shape.strokeBorder(lit ? Candle.gold : Candle.hairline, lineWidth: lit ? 2 : 1) }
        .shadow(color: lit ? Candle.gold.opacity(0.6) : .clear, radius: 14)
        .task(id: card.id) { if let p = card.piece { url = await PracticeCards.still(for: p, model: model) }; looked = true }
        .accessibilityLabel(lit ? (card.kind == "game" ? "Game unlocked: \(gameName)" : "A card of your art") : "A card, face down")
    }

    private var gameName: String { (card.game ?? "").replacingOccurrences(of: "-", with: " ").capitalized }

    @ViewBuilder private var face: some View {
        ZStack {
            Color.black
            if card.kind == "game" {
                VStack(spacing: 8) {
                    Text("Game unlocked").font(Font.pl(size: 11)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                    Text(gameName).plHand(22, relativeTo: .title2).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
                }
                .padding(10)
            } else if let url {
                AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView().tint(Candle.gold) }
            } else if looked {
                Text("This piece has no still picture.").font(Font.pl(size: 12)).foregroundStyle(Candle.ink.opacity(0.6)).multilineTextAlignment(.center).padding(8)
            }
        }
    }
}

/// The opening: the pack in real 3D (PracticePack3D.swift), then the cards face up in a row. With Reduce Motion, or for a pack
/// already opened, the cards are simply shown face up.
struct PackOpening: View {
    let model: AppModel
    let cards: [PackCard]
    let animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false

    private var stops: [Double] { cards.indices.map { 4.6 + Double($0) * 1.5 } }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if done || !animate || reduceMotion {
                    row(geo.size, t: 999)
                } else {
                    // the opening in real 3D (his ruling 11-15, PracticePack3D.swift); the cards then rest face up, readable, below
                    Pack3DStage(model: model, cards: cards) { withAnimation(.easeOut(duration: 0.4)) { done = true } }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .sensoryFeedback(PLHaptic.success, trigger: done)
    }

    private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

    private func row(_ s: CGSize, t: Double) -> some View {
        let w = cards.count > 1 ? min((s.width - 16) / 2, 190) : min(s.width * 0.62, 250)
        return HStack(spacing: 16) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                let stop = stops[i], speed = 300.0 + 70.0 * Double(i)
                let a0 = (stop - 3) * speed, target = (a0 / 360).rounded(.up) * 360
                let angle = t >= stop + 0.5 ? 0 : (t < stop ? (t - 3) * speed : a0 + (target - a0) * ease((t - stop) / 0.5))
                PackCardView(model: model, card: c, burn: ease((t - (stop + 0.6)) / 0.7), seed: Double(i) * 3.7 + 1)
                    .frame(width: w)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A finished lesson in any app earns a pack (his ask 11-27: "no matter what app it is"). Set the key and the pack opens; a key
/// already opened on this phone does not pop again (the Worker keeps one pack per key for good, so nothing is lost).
struct PackKey: Identifiable, Equatable { let id: String }

enum PackEarn {
    private static let seen = "packs.opened"
    /// The key to open, or nil when this phone already opened it.
    static func fresh(_ key: String) -> PackKey? {
        var s = Set(UserDefaults.standard.stringArray(forKey: seen) ?? [])
        guard s.insert(key).inserted else { return nil }
        UserDefaults.standard.set(Array(s), forKey: seen)
        return PackKey(id: key)
    }
}

extension View {
    func earnsPack(_ key: Binding<PackKey?>) -> some View {
        background { Color.clear.fullScreenCover(item: key) { k in PackScreen(model: AppModel.shared, key: k.id) { key.wrappedValue = nil } } }
    }
}

/// A gold unit's pack, opened from the Path. The close button, and Done, both leave.
struct PackScreen: View {
    let model: AppModel
    let key: String
    let close: () -> Void
    @State private var pack: PracticePack?
    @State private var failure: String?
    @State private var buddy = BuddyModel()
    @State private var web: URL?   // a new pack with a tiered art card opens the real pack page, sealed, on that card (S356·c41f)

    var body: some View {
        ZStack {
            CandleGround()
            GlyphField(strength: 0.08).ignoresSafeArea().blendMode(.screen)
            VStack(spacing: 16) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(Font.pl(size: 15, weight: .medium)).foregroundStyle(Candle.ink).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close")
                    Spacer()
                    BuddyHead(model: buddy, side: 64)
                }
                if let pack, let web {
                    SlabWeb(url: web).clipShape(RoundedRectangle(cornerRadius: 14 * PLStyle.radius))
                        .accessibilityLabel("Your pack. Swipe across the top to rip it open")
                    let rest = pack.cards.filter { $0 != hero(pack) }
                    if !rest.isEmpty { PackOpening(model: model, cards: rest, animate: false).frame(height: 150) }
                    Button("Done") { close() }.buttonStyle(CandleButton())
                } else if let pack {
                    PackOpening(model: model, cards: pack.cards, animate: pack.new)
                    Button("Done") { close() }.buttonStyle(CandleButton())
                } else if let failure {
                    Text(failure).candleHint()
                    Button("Try again") { Task { await load() } }.buttonStyle(CandleGhost())
                    Spacer()
                } else {
                    ProgressView().tint(Candle.gold).frame(maxHeight: .infinity)
                }
            }
            .padding(20).frame(maxWidth: 640)
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func load() async {
        failure = nil
        do {
            let p = try await Packs.open(key, model: model)
            if p.new, let h = hero(p), let piece = h.piece, let tier = h.tier {
                web = await PracticeCards.packPage(piece: piece, tier: tier, name: BinderSection.shelf(key), date: String(p.earned_at.prefix(10)), earned: true, model: model)
            }
            pack = p; buddy.react(key.hasPrefix("gold-") ? .gold : .pack)
        } catch { failure = "Could not reach the practice. Your pack is kept; open it when you are back online." }
    }

    /// The card the web pack rips to: the first art card the server gave a tier.
    private func hero(_ p: PracticePack) -> PackCard? { p.cards.first { $0.kind == "art" && $0.tier != nil } }
}

/// The pack as it stands on the test page (his word 11-16: "Publish what you have for now ... to pl dev the iOS app"): the live 3D pack,
/// its three tiers, the odds and the editor, shown in a web view until the RealityKit build replaces it. The page is public and holds
/// no key; there is no script bridge to the app. Videos play inline (Champagne cards play when opened).
struct LivePackWeb: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if let url = URL(string: "https://pl-curve-library.psychedluxuries.workers.dev/pack/") {
            web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct LivePackScreen: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { close() } label: { Image(systemName: "xmark").font(Font.pl(size: 15, weight: .medium)).foregroundStyle(Candle.ink).frame(width: 44, height: 44) }
                    .accessibilityLabel("Close")
                Text("The pack \u{00b7} live test").candleHint()
                Spacer()
            }
            .padding(.horizontal, 8)
            LivePackWeb()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
