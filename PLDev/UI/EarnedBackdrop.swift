import SwiftUI

/// The screen dressed by his own output (his pick N13, 11-14): the pieces he most recently made favourites or kept in Curate, shown on
/// a panel under Today's date at full strength (his note 11-14: "way too faint, the pieces should be on a panel"). Only his art; a
/// picture that does not load is left out rather than leaving a gap; no panel at all until he has kept something.
struct EarnedBackdrop: View {
    let model: AppModel
    @State private var library = LibraryData.shared
    @State private var failed: Set<URL> = []

    private var picks: [URL] {
        let ranked = library.items.compactMap { it -> (URL, Bool, String)? in
            guard let m = library.marks[it.vault_id], m.v == "keep", let still = library.media(it, model: model).still else { return nil }
            return (still, m.isFav, m.at ?? "")
        }
        // favourites first, then the newest keeps
        return ranked.sorted { ($0.1 ? 1 : 0, $0.2) > ($1.1 ? 1 : 0, $1.2) }.map(\.0).filter { !failed.contains($0) }.prefix(10).map { $0 }
    }

    var body: some View {
        let urls = picks
        Group {
            if !urls.isEmpty {
                Button { if let u = URL(string: "pldev://section/library") { UIApplication.shared.open(u) } } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Your latest keeps").plHand(20)
                            Spacer()
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(urls, id: \.self) { u in
                                    AsyncImage(url: u) { phase in
                                        switch phase {
                                        case .success(let img): img.resizable().scaledToFill()
                                        case .failure: Color.clear.onAppear { failed.insert(u) }
                                        default: Color.white.opacity(0.06)
                                        }
                                    }
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
                .accessibilityLabel("Your latest keeps, \(urls.count) pieces. Opens the Library")
            }
        }
        .task { if library.items.isEmpty { try? await library.load(model: model) } }
    }
}
