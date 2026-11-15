import SwiftUI

/// The screen dressed by his own output (his pick N13, 11-14; Gemini's "the UI earns its richness from real output"): behind Today's
/// date, a faint band of the pieces he most recently made favourites or kept in Curate. Only his art, never stock; it changes as he
/// marks new pieces, and is empty (not filled with anything else) until he has.
struct EarnedBackdrop: View {
    let model: AppModel
    @State private var library = LibraryData.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var picks: [URL] {
        let ranked = library.items.compactMap { it -> (URL, Bool, String)? in
            guard let m = library.marks[it.vault_id], m.v == "keep", let still = library.media(it, model: model).still else { return nil }
            return (still, m.isFav, m.at ?? "")
        }
        // favourites first, then the newest keeps
        return ranked.sorted { ($0.1 ? 1 : 0, $0.2) > ($1.1 ? 1 : 0, $1.2) }.prefix(8).map(\.0)
    }

    var body: some View {
        let urls = picks
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(urls, id: \.self) { u in
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        .frame(width: max(1, geo.size.width / CGFloat(max(urls.count, 1)) - 2), height: geo.size.height)
                        .clipped()
                }
            }
        }
        .opacity(reduceTransparency ? 0 : 0.28)
        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { if library.items.isEmpty { try? await library.load(model: model) } }
    }
}
