import SwiftUI

// One Teacher (S348·9a3e): the pack. A finished lesson earns one card of his art; a unit that turns gold earns a pack of one or
// two cards, each his art or a game card that unlocks that game. The Worker deals them (`POST /api/pack`, one pack per key, for
// good). His rulings 11-15: the backs are the glyph field and nothing tells you what is inside until it opens. The motion follows
// his reference: the pack tears, one gold slab rises and grows, it parts into cards that turn, each stops, squares up, and its
// back burns away in patches to the face.

struct PackCard: Decodable, Sendable, Identifiable, Equatable {
    let kind: String
    let piece: String?
    let game: String?
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
    var body: some View {
        ZStack {
            Candle.card
            if let t = Packs.tile {
                Image(uiImage: t).renderingMode(.template).resizable(resizingMode: .tile).foregroundStyle(Candle.gold.opacity(strength))
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
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    Text("Game unlocked").font(.system(size: 11)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                    Text(gameName).plHand(22, relativeTo: .title2).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
                }
                .padding(10)
            } else if let url {
                AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView().tint(Candle.gold) }
            } else if looked {
                Text("This piece has no still picture.").font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.6)).multilineTextAlignment(.center).padding(8)
            }
        }
    }
}

/// The opening. Tap the pack to start; with Reduce Motion, or for a pack already opened, the cards are simply shown face up.
struct PackOpening: View {
    let model: AppModel
    let cards: [PackCard]
    let animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var done = false

    private var stops: [Double] { cards.indices.map { 4.6 + Double($0) * 1.5 } }
    private var end: Double { (stops.last ?? 4.6) + 1.5 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if done || !animate || reduceMotion {
                    row(geo.size, t: 999)
                } else if let start {
                    TimelineView(.animation) { ctx in scene(geo.size, t: ctx.date.timeIntervalSince(start)) }
                } else {
                    closed(geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .sensoryFeedback(PLHaptic.success, trigger: done)
    }

    private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
    private func packFrame(_ s: CGSize) -> CGRect {
        let w = min(s.width * 0.5, 220), h = w * 0.62
        return CGRect(x: (s.width - w) / 2, y: s.height - h - 12, width: w, height: h)
    }

    private func packBody(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Candle.gold.gradient)
            .overlay { GlyphField(strength: 0.35).blendMode(.multiply).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) }
            .frame(width: r.width, height: r.height)
    }

    private func closed(_ s: CGSize) -> some View {
        let r = packFrame(s)
        return Button {
            start = .now
            let wait = end
            Task { try? await Task.sleep(for: .seconds(wait)); withAnimation(.easeOut(duration: 0.3)) { done = true } }
        } label: {
            VStack(spacing: 12) {
                packBody(r)
                Text("Tap to open").font(.system(size: 13)).foregroundStyle(Candle.ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the pack")
    }

    @ViewBuilder private func scene(_ s: CGSize, t: Double) -> some View {
        let r = packFrame(s)
        ZStack {
            if t < 0.9 {
                packBody(r).position(x: r.midX, y: r.midY).opacity(1 - ease((t - 0.6) / 0.3))
                // the strip torn off the top
                Rectangle().fill(Candle.goldHi).frame(width: r.width, height: 6)
                    .position(x: r.midX + 30 * ease(t / 0.6), y: r.minY - 40 * ease(t / 0.6)).opacity(1 - ease(t / 0.6))
            }
            if t >= 0.6 && t < 3.25 {
                let k = ease((t - 0.6) / 1.6)
                let w = r.width * 0.8 + (min(s.width * 0.7, 300) - r.width * 0.8) * k
                let h = r.height * 0.9 + (min(s.height * 0.72, 430) - r.height * 0.9) * k
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Candle.gold)
                    .frame(width: w, height: h)
                    .shadow(color: Candle.gold.opacity(0.75), radius: 18 + 10 * sin(t * 6))
                    .position(x: s.width / 2, y: r.midY + (s.height * 0.46 - r.midY) * k)
                    .opacity(1 - ease((t - 3.0) / 0.25))
            }
            if t >= 3.0 { row(s, t: t).opacity(ease((t - 3.0) / 0.25)) }
        }
    }

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

/// A gold unit's pack, opened from the Path. The close button, and Done, both leave.
struct PackScreen: View {
    let model: AppModel
    let key: String
    let close: () -> Void
    @State private var pack: PracticePack?
    @State private var failure: String?
    @State private var buddy = BuddyModel()

    var body: some View {
        ZStack {
            CandleGround()
            GlyphField(strength: 0.08).ignoresSafeArea().blendMode(.screen)
            VStack(spacing: 16) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Candle.ink).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close")
                    Spacer()
                    BuddyView(model: buddy).frame(width: 46, height: 46)
                }
                if let pack {
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
        do { pack = try await Packs.open(key, model: model); buddy.react(key.hasPrefix("gold-") ? .gold : .pack) }
        catch { failure = "Could not reach the practice. Your pack is kept; open it when you are back online." }
    }
}
