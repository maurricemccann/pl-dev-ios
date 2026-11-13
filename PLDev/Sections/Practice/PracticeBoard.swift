import PhotosUI
import SwiftUI

// The Vision board: tap an image to choose it, chosen images stay. Sources are the catalogue (default), abundance, love, success,
// and his own photo. Chosen pictures lead the grid; the rest of the twelve fill from the source (web: `loadVisionBoard`).

struct VisionBoardCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var source = "house"
    @State private var pins: [PracticePin] = []
    @State private var fill: [PracticeBoardImages.Image] = []
    @State private var photo: PhotosPickerItem?
    @State private var result: String?
    @State private var uploading = false
    @State private var loaded = false
    @State private var failed = false
    private static let sources = [("house", "the catalogue"), ("abundance", "abundance"), ("love", "love"), ("success", "success")]

    private struct Cell: Identifiable { let url: String; let alt: String; let pinned: Bool; var id: String { url } }

    private var cells: [Cell] {
        let pinned = Set(pins.map(\.url))
        let extra = fill.filter { !pinned.contains($0.url) }.prefix(max(0, 12 - pins.count))
        return pins.map { Cell(url: $0.url, alt: $0.alt ?? "", pinned: true) } + extra.map { Cell(url: $0.url, alt: $0.alt ?? "", pinned: false) }
    }

    var body: some View {
        PCard(title: "Vision board", hint: "tap an image to choose it \u{2014} chosen images stay", id: "vision") {
            WrapLayout(spacing: 6) {
                ForEach(Self.sources, id: \.0) { s in CandleChip(title: s.1, on: source == s.0) { source = s.0 } }
                PhotosPicker(selection: $photo, matching: .images) {
                    Text(uploading ? "adding\u{2026}" : "+ your own").font(.system(size: 13.5)).foregroundStyle(Candle.ink).padding(.horizontal, 15).frame(minHeight: 36)
                        .overlay { Capsule().strokeBorder(Candle.pillLine, lineWidth: 1) }.opacity(0.6)
                }
                .disabled(uploading)
            }
            let grid = cells
            if grid.isEmpty {
                QuietLine(text: failed ? PracticeWords.loadFailed("the board") : loaded ? "Nothing here yet." : "\u{2026}")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6.4), count: 3), spacing: 6.4) {
                    ForEach(grid) { c in
                        Button { Task { await toggle(c.url, c.alt) } } label: {
                            Color.clear.frame(height: 100)
                                .overlay { AsyncImage(url: Practice.imageURL(c.url, model: model)) { $0.resizable().scaledToFill() } placeholder: { Candle.field } }
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(c.pinned ? Candle.gold : .clear, lineWidth: 2) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(c.alt.isEmpty ? "Picture" : c.alt), \(c.pinned ? "chosen, tap to let go" : "tap to choose")")
                    }
                }
                .animation(.snappy, value: pins.count)
            }
            CandleResult(text: result)
        }
        .task(id: source) { await load() }
        .task(id: state.reload) { await loadPins() }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
        .sensoryFeedback(PLHaptic.select, trigger: pins.count)
    }

    private func loadPins() async { if let p = try? await Practice.get("pins", [PracticePin].self, model: model) { pins = p } }

    private func load() async {
        await loadPins()
        let q: [String: String] = source == "house" ? ["source": "house"] : ["category": source]
        do { fill = try await Practice.get("vision-board", PracticeBoardImages.self, model: model, query: q).images; failed = false }
        catch { failed = true }
        loaded = true
    }

    private func toggle(_ url: String, _ alt: String) async {
        do { try await Practice.post("pins/toggle", ["url": url, "alt": alt], model: model); await loadPins(); state.tick += 1 }
        catch { result = error.localizedDescription }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true; defer { uploading = false; photo = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: raw), let jpeg = img.jpegData(compressionQuality: 0.82) else { result = "Not added. That picture would not load."; return }
        struct Up: Decodable { let url: String? }
        do {
            let d = try await Practice.upload("board-upload", jpeg, type: "image/jpeg", model: model)
            guard let u = (try? JSONDecoder().decode(Up.self, from: d))?.url else { result = "Not added. The practice did not take it."; return }
            try await Practice.post("pins/toggle", ["url": u, "alt": "Mine"], model: model)
            result = nil; await loadPins()
        } catch { result = error.localizedDescription }
    }
}
