import QuickLook
import RealityKit
import SwiftUI

// The Wardrobe (`app/wardrobe/page.tsx`, `components/WardrobeGrid.tsx`, `components/ModelViewer.tsx`), natively: each garment
// turned in RealityKit, and placed in the room at full scale with Apple's AR Quick Look (the same USDZ the site hands an iPhone
// for AR, `assets…/3d/<slug>.usdz`, so nothing is converted or kept in this repo). The pieces and their `hidden` flags mirror
// `lib/wardrobe.ts`: a model that does not match the garment we sell stays off the page (his S308 ruling), exactly as the site
// keeps it off, and while every model is hidden the page carries only its words and its doors.

struct WardrobePiece: Identifiable, Hashable {
    let slug: String
    let productSlug: String
    let name: String
    let axiom: String
    let note: String
    var hidden = false
    var id: String { slug }

    static let base = "https://assets.psychedluxuries.com/3d/"
    var usdz: URL? { URL(string: Self.base + slug + ".usdz") }

    /// `WARDROBE_PIECES`, with the site's reasons for each hidden one in its comment.
    static let all: [WardrobePiece] = [
        WardrobePiece(slug: "seeds-tee", productSlug: "seed-og-tee", name: "Seeds Tee", axiom: "What persists in the mind becomes your reality",
                      note: "The documented window, made dimensional. Worn by the avatar that arrived before the harvest.", hidden: true),       // a grey tee with the knot mark; the product is a black tee with the seed art
        WardrobePiece(slug: "love-yourself-tee", productSlug: "love-yourself-glyph-tee", name: "Love Yourself Tee", axiom: "You are in control of your reality",
                      note: "The first instruction. The one most refused. Here it stands at full scale, in the room and the realm.", hidden: true),  // the Fall-in-Love art on black; the product is cream with a red heart
        WardrobePiece(slug: "crown-your-mind-tee", productSlug: "crown-your-mind-tee", name: "Crown Your Mind Tee", axiom: "What persists in the mind becomes your reality",
                      note: "The crown is not given. It is the posture you keep before anyone is watching.", hidden: true),                        // a black tee; the product is cream
    ]
    static var visible: [WardrobePiece] { all.filter { !$0.hidden } }
    static var hasVisible: Bool { !visible.isEmpty }
}

/// Downloads a garment's USDZ once and keeps it in Caches (offline after the first look).
enum WardrobeFiles {
    static func local(_ p: WardrobePiece) async -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Wardrobe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(p.slug + ".usdz")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let src = p.usdz, let (tmp, r) = try? await URLSession.shared.download(from: src),
              (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.removeItem(at: file)
        do { try FileManager.default.moveItem(at: tmp, to: file) } catch { return nil }
        return file
    }
}

/// One garment, turning: drag to orbit, pinch to zoom (the site's OrbitControls), on a clear stage over the paper.
struct WardrobeStage: View {
    let piece: WardrobePiece
    @State private var phase = Phase.loading
    enum Phase { case loading, ready, failed }

    var body: some View {
        OrbitStage(distance: 2.6, height: 0, autoSpin: true) { pivot in
            guard let url = await WardrobeFiles.local(piece), let e = try? await Entity(contentsOf: url) else { phase = .failed; return }
            if let anim = e.availableAnimations.first { e.playAnimation(anim.repeat()) }
            pivot.addChild(ThreeDModels.fitted(e, longest: 1.4))
            phase = .ready
        }
        .overlay {
            switch phase {
            case .loading: ProgressView()
            case .failed: EmptyNote(symbol: "cube.transparent", title: "The model did not load", detail: "Check your connection. The piece itself is in the shop.")
            case .ready: EmptyView()
            }
        }
        .accessibilityLabel("\(piece.name), interactive 3D garment. Drag to turn it.")
    }
}

/// The room at full scale: Apple's AR Quick Look on the downloaded USDZ.
struct WardrobeAR: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Source { Source(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController(); c.dataSource = context.coordinator; return c
    }
    func updateUIViewController(_ c: QLPreviewController, context: Context) {}
    final class Source: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

struct ARFile: Identifiable { let url: URL; var id: String { url.path } }

/// One garment's block, as `WardrobeGrid` draws it: the stage, the axiom, the name, the gold line, the note, the doors.
struct WardrobeCard: View {
    let piece: WardrobePiece
    var compact = false
    @State private var ar: ARFile?
    @State private var line: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WardrobeStage(piece: piece).frame(height: 360)
                .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(piece.axiom).siteLabel()
            NavigationLink { PieceView(slug: piece.productSlug, state: ShopSection.state) } label: {
                Text(piece.name).font(SiteFont.display(32)).foregroundStyle(Bone.ink(scheme))
            }.buttonStyle(.plain)
            if !compact {
                Rectangle().fill(Bone.gold).frame(width: 96, height: 1)
                Text(piece.note).siteBody(14)
            }
            HStack(spacing: 12) {
                Button {
                    Task {
                        if let u = await WardrobeFiles.local(piece) { ar = ARFile(url: u); line = nil } else { line = "Not opened. The model did not download." }
                    }
                } label: { Text("Place it in your room") }.buttonStyle(SiteGhost())
                NavigationLink { PieceView(slug: piece.productSlug, state: ShopSection.state) } label: { Text("Wear it \u{2192}") }.buttonStyle(SitePill())
            }
            ResultLine(text: line)
        }
        .fullScreenCover(item: $ar) { f in
            NavigationStack {
                WardrobeAR(url: f.url).ignoresSafeArea()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { ar = nil } } }
            }
        }
    }
}

/// `/wardrobe`: the hero, the garments, the digital twin.
struct WardrobeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SiteBand {
                    VStack(spacing: 22) {
                        Text("Worn in the World, and the World to Come").siteTag(11, Bone.gold).multilineTextAlignment(.center)
                        Text("The Wardrobe").font(SiteFont.display(50, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).accessibilityAddTraits(.isHeader)
                        Text("Each piece, rendered in three dimensions. Turn it in your hand. On a phone, place it in your room at full scale. The same doctrine the avatar wears in Horizon \u{2014} the garment is one object with two bodies, the physical and the dimensional.")
                            .siteBody(15).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                if WardrobePiece.hasVisible {
                    SitePaper {
                        VStack(spacing: 56) { ForEach(WardrobePiece.visible) { WardrobeCard(piece: $0) } }
                    }
                } else {
                    SitePaper {
                        Text("The garments are being remade to match the cloth we sell. Until each one is true to its piece, the room stays closed and the archive holds the evidence.")
                            .font(SiteFont.display(22, italic: true)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(3)
                        NavigationLink { ArchiveView(model: .shared) } label: { Text("The Archive \u{2192}") }.buttonStyle(SiteGhost())
                    }
                }
                SiteBand {
                    VStack(spacing: 22) {
                        Text("The Digital Twin").siteTag(11, Bone.gold)
                        Text("One Object,\nTwo Bodies").font(SiteFont.display(40, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                        Text("The new luxury is not what you own \u{2014} it is where you have been and what you stand for. A piece you can wear on the street and on the avatar is the same argument, told twice. The archive is the proof. The form is the offering.")
                            .siteBody(15).multilineTextAlignment(.center)
                        NavigationLink { SiteShopList() } label: { Text("Wear it in the world") }.buttonStyle(SitePill(gold: true))
                        NavigationLink { SiteWorldView() } label: { Text("The Collections") }.buttonStyle(SiteGhost())
                        NavigationLink { ArchiveView(model: .shared) } label: { Text("The Archive") }.buttonStyle(SiteGhost())
                        SiteWatch().padding(.top, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .siteScreen()
        .plScreenTitle("The Wardrobe")
    }
}
