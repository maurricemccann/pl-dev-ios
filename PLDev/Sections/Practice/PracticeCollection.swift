import SwiftUI

// Phase 6 of the practice spec (S348·9a3e, his rulings 11-15): completing the evening earns one card a day, drawn from his
// favourites (a /curate keep he starred), a shuffled deck with no repeat until it runs out. Nothing is ever taken away.
// The Worker keeps the cards (`GET /api/collection`); the picture comes from the Library's own index, so no image is made here.

struct PracticeEarned: Decodable, Sendable, Identifiable, Equatable {
    let date: String
    let piece: String
    let earned_at: String
    var id: String { date }
}

struct PracticeCollection: Decodable, Sendable {
    let count: Int
    let deck_size: Int
    let cards: [PracticeEarned]
    let games: [String]?   // arcade games his packs have unlocked
}

enum PracticeCards {
    /// The collection, or nil when the Worker can't be read (the card then says so, never a fake zero).
    static func load(model: AppModel) async -> PracticeCollection? {
        try? await Practice.get("collection", PracticeCollection.self, model: model)
    }

    /// True only for a card earned in the last two minutes: a re-saved evening shows the collection, not a second reveal.
    static func isFresh(_ c: PracticeEarned) -> Bool {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: c.earned_at) else { return false }
        return Date().timeIntervalSince(d) < 120
    }

    @MainActor static func still(for piece: String, model: AppModel) async -> URL? {
        try? await LibraryData.shared.load(model: model)
        guard let it = LibraryData.shared.items.first(where: { $0.vault_id == piece }) else { return nil }
        return LibraryData.shared.media(it, model: model).still
    }
}

/// One earned card at full size: the piece itself, never redrawn.
struct EarnedCardFace: View {
    let model: AppModel
    let card: PracticeEarned
    @State private var url: URL?
    @State private var looked = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.35))
                if let url {
                    AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(10)
                } else if looked {
                    Text("This piece has no still picture.").font(.footnote).foregroundStyle(.secondary).padding()
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(0.8, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18)))
            Text(card.date).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .task(id: card.piece) { url = await PracticeCards.still(for: card.piece, model: model); looked = true }
    }
}

/// The reveal after the evening, and the collection behind it. A sheet: Done, swipe down, or back all close it.
struct EarnedCardSheet: View {
    let model: AppModel
    let fresh: PracticeEarned?
    let collection: PracticeCollection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let fresh {
                        Text("Earned tonight").font(.title2.weight(.semibold))
                        EarnedCardFace(model: model, card: fresh)
                    }
                    Text("\(collection.count) in your collection").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(collection.cards) { EarnedCardFace(model: model, card: $0) }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Your cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sensoryFeedback(PLHaptic.success, trigger: fresh?.id ?? "")
    }
}
