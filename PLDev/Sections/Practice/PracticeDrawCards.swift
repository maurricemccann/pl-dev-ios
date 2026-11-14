import SwiftUI

/// The R1's two draws, on the phone: the seed phrase draw (`pl-r1/public/seeds`) and the PL tarot (`public/games`, a three-card spread read
/// together through the Oracle). Both are private to the practice and never published. Each draw is a shuffled deck, not a coin: nothing
/// comes up twice until the whole deck has been shown, then it is shuffled again (his rule, 11-13).
struct SeedDrawCard: View {
    @State private var order: [Int] = []
    @State private var pos = -1                   // position in `shown`
    @State private var shown: [Int] = []          // what has been drawn this visit, so the arrows can go back
    @State private var next = 0                   // how far into `order` the deck is
    private let total = PracticeDraws.seeds.count

    var body: some View {
        PCard(title: "Seed phrase draw", hint: "Draw one of his seeds. Sit with it, then plant it.", id: "seeds") {
            if pos >= 0, shown.indices.contains(pos) {
                let s = PracticeDraws.seeds[shown[pos]]
                VStack(spacing: 10) {
                    Text(s.title).plHand(28, relativeTo: .title).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
                    Text(s.sentence).plHand(20, relativeTo: .body).foregroundStyle(Candle.ink).multilineTextAlignment(.center).lineSpacing(4).textSelection(.enabled)
                    Text("\(pos + 1) of \(shown.count) drawn \u{00B7} \(total - next) left in the deck").candleHint()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = s.title + ". " + s.sentence } }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 10) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(CandleGhost()).disabled(pos <= 0).accessibilityLabel("Previous seed")
                Button(pos < 0 ? "Draw a seed" : "Draw another") { draw() }.buttonStyle(CandleButton())
                Button { move(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(CandleGhost()).disabled(pos < 0 || pos >= shown.count - 1).accessibilityLabel("Next seed")
            }
        }
        .sensoryFeedback(PLHaptic.select, trigger: pos)
        .onAppear { restore() }
    }

    private func restore() {
        guard order.isEmpty else { return }
        let d = UserDefaults.standard
        if let saved = d.array(forKey: "practice.seedDeck") as? [Int], saved.count == total { order = saved; next = min(total, d.integer(forKey: "practice.seedNext")) }
        else { reshuffle(avoiding: nil) }
    }

    private func reshuffle(avoiding last: Int?) {
        var o = Array(0..<total).shuffled()
        if let last, o.first == last, o.count > 1 { o.swapAt(0, o.count - 1) }   // the seed just shown never opens the next deck
        order = o; next = 0
        UserDefaults.standard.set(order, forKey: "practice.seedDeck")
    }

    private func draw() {
        if next >= order.count { reshuffle(avoiding: shown.last) }
        shown.append(order[next]); next += 1; pos = shown.count - 1
        UserDefaults.standard.set(next, forKey: "practice.seedNext")
    }

    private func move(_ d: Int) { pos = max(0, min(shown.count - 1, pos + d)) }
}

struct TarotCard: View {
    let model: AppModel
    @State private var spread: [Int] = []
    @State private var pos = 0
    @State private var synthesis = ""
    @State private var reading = false

    var body: some View {
        PCard(title: "PL tarot", hint: "Three cards from the twenty-two. Browse them, then read them together.", id: "tarot") {
            if !spread.isEmpty {
                let c = PracticeDraws.deck[spread[pos]]
                VStack(spacing: 6) {
                    Text(c.num).font(.system(size: 11)).tracking(3.3).textCase(.uppercase).foregroundStyle(Candle.ink.opacity(0.5))
                    Text(c.symbol).font(.system(size: 40)).foregroundStyle(Candle.gold)
                    Text(c.name).plHand(26, relativeTo: .title2).foregroundStyle(Candle.goldHi)
                    Text(c.reading).plHand(18, relativeTo: .body).foregroundStyle(Candle.ink).multilineTextAlignment(.center).lineSpacing(4).textSelection(.enabled)
                    Text(c.law).font(.system(size: 10.5)).tracking(2.1).textCase(.uppercase).foregroundStyle(Candle.ink.opacity(0.5)).padding(.top, 4)
                    Text("\(pos + 1) of 3").candleHint()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if !synthesis.isEmpty {
                    CandleRule()
                    Text(synthesis).plHand(17, relativeTo: .body).foregroundStyle(Candle.goldHi).lineSpacing(4).textSelection(.enabled)
                }
            }
            HStack(spacing: 10) {
                Button { pos = max(0, pos - 1) } label: { Image(systemName: "chevron.left") }.buttonStyle(CandleGhost()).disabled(spread.isEmpty || pos == 0).accessibilityLabel("Previous card")
                Button(spread.isEmpty ? "Draw three" : "Draw again") { spread = Array(Array(0..<PracticeDraws.deck.count).shuffled().prefix(3)); pos = 0; synthesis = "" }.buttonStyle(CandleButton())
                Button { pos = min(2, pos + 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(CandleGhost()).disabled(spread.isEmpty || pos == 2).accessibilityLabel("Next card")
            }
            if !spread.isEmpty {
                Button(reading ? "Reading\u{2026}" : "Read them together") { Task { await read() } }.buttonStyle(CandleGhost()).disabled(reading)
            }
        }
        .sensoryFeedback(PLHaptic.select, trigger: spread)
    }

    /// The Oracle reads the three together, grounded in the brand's doctrine (the R1's long press).
    private func read() async {
        guard !spread.isEmpty else { return }
        reading = true; synthesis = "\u{2026}"; defer { reading = false }
        let names = spread.map { PracticeDraws.deck[$0].name }
        let q = "Three cards drawn from the Psyched Luxuries tarot: \(names[0]), \(names[1]), and \(names[2]). In two or three sentences, read them together as one message grounded in the brand's doctrine."
        do {
            let r = try await GlyphBot.ask(q, model: model)
            let t = r.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            synthesis = t.isEmpty ? "The reading is silent." : t
        } catch { synthesis = "The reading is unreachable right now." }
    }
}
