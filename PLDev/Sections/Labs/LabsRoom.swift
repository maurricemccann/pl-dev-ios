import SwiftUI

// The Labs, native (wave 3, his order 11-13: "there should not be any web views, just native").
// Every row of the gallery's lab index is its own native view in this folder: shaders in Metal, the sketches in Core Graphics,
// the 3D pieces in RealityKit, the camera pieces on AVFoundation / ARKit, the mic through VJAudio. Source of each: pl-curves-gallery
// `app/lab/*`, `components/lab/*`, `components/art/*`. The look is the gallery's own (`PLG`, GallerySkin).

enum LabPage: String, CaseIterable, Identifiable, Hashable {
    // The Mirror, in the order of its numerals (components/art/house.ts MIRROR)
    case warp, plotter, reaction, glitch, phyllotaxis, kinematic, webgpu, life
    // Instruments and experiments
    case ribbon, goldenMend, fluid, ar, fly
    // Figures and models
    case dance, glyphbot, heart, wordmark, cards, curveWho, curveWhoReader
    // The room (the scroll room and world gallery)
    case room
    // Studies
    case hero, homeStudy, study, components, curveMotion, hand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ribbon: return "Ribbon curves"; case .goldenMend: return "Golden Mend"; case .life: return "Life"; case .ar: return "AR curves"
        case .fly: return "The fly"; case .dance: return "GlyphGuy dances"; case .glyphbot: return "GlyphBot"; case .heart: return "Heart coin"
        case .wordmark: return "Wordmark"; case .cards: return "Cards"; case .hero: return "Hero grammar"; case .fluid: return "Fluid"
        case .glitch: return "Glitch"; case .warp: return "Warp"; case .reaction: return "Reaction diffusion"; case .plotter: return "Glyph plotter"
        case .kinematic: return "Kinematic"; case .phyllotaxis: return "Phyllotaxis"; case .homeStudy: return "Home study"; case .study: return "The study"
        case .webgpu: return "Metal"; case .components: return "Components"; case .curveWho: return "Curve who"; case .curveWhoReader: return "The Curve Who, reader"; case .room: return "The room"
        case .curveMotion: return "The curve in motion"; case .hand: return "His hand"
        }
    }
    var line: String {
        switch self {
        case .ribbon: return "Ribbons from his comps, drawn on the GPU"; case .goldenMend: return "A kintsugi instrument played by the mic"
        case .life: return "Game of Life on the GPU, fed by the mic"; case .ar: return "Gold curves over the camera"
        case .fly: return "A connectome steering a gold line"; case .dance: return "His animation clips"; case .glyphbot: return "GlyphGuy under a spotlight"
        case .heart: return "The spinning heart"; case .wordmark: return "His hand in 3D"; case .cards: return "GlyphGuy on his palettes"
        case .hero: return "The painting-grammar generator"; case .fluid: return "Fluid cursor reveal"; case .glitch: return "Shader study"
        case .warp: return "Shader study"; case .reaction: return "Shader study"; case .plotter: return "Four pens on fixed angles"
        case .kinematic: return "Five chains following"; case .phyllotaxis: return "The golden angle"; case .homeStudy: return "2,000 curves"
        case .study: return "A door and the Three Truths"; case .webgpu: return "What this phone's GPU reports"
        case .components: return "Glass, borders, countdowns"; case .curveWho: return "Clay story, in progress"
        case .curveWhoReader: return "Scroll from birth to the mark"; case .room: return "Scroll into the showroom"
        case .curveMotion: return "Curves in motion"; case .hand: return "Type, rendered in his hands"
        }
    }
    var symbol: String {
        switch self {
        case .ribbon: return "scribble.variable"; case .goldenMend: return "waveform"; case .life: return "square.grid.3x3.fill"; case .ar: return "camera.viewfinder"
        case .fly: return "ant"; case .dance: return "figure.dance"; case .glyphbot: return "person.crop.square"; case .heart: return "heart.fill"
        case .wordmark: return "textformat"; case .cards: return "rectangle.stack"; case .hero: return "paintbrush.pointed"; case .fluid: return "drop"
        case .glitch: return "rectangle.split.3x1"; case .warp: return "wind"; case .reaction: return "circle.hexagongrid"; case .plotter: return "pencil.and.ruler"
        case .kinematic: return "point.3.connected.trianglepath.dotted"; case .phyllotaxis: return "sunflower"; case .homeStudy: return "scribble"
        case .study: return "door.left.hand.open"; case .webgpu: return "cpu"; case .components: return "square.on.square.intersection.dashed"
        case .curveWho: return "face.smiling"; case .curveWhoReader: return "face.dashed"; case .room: return "door.left.hand.open"; case .curveMotion: return "waveform.path"; case .hand: return "signature"
        }
    }
    /// The public page this piece ports, for the share sheet.
    var path: String {
        switch self {
        case .ribbon: return "lab"; case .goldenMend: return "lab/golden-mend"; case .life: return "lab/life"; case .ar: return "lab/ar"; case .fly: return "lab/fly"
        case .dance: return "lab/dance"; case .glyphbot: return "lab/glyphbot"; case .heart: return "lab/heart"; case .wordmark: return "lab/wordmark"
        case .cards: return "lab/nft-candidates"; case .hero: return "lab/trained-hero"; case .fluid: return "lab/fluid"; case .glitch: return "lab/glitch"
        case .warp: return "lab/warp"; case .reaction: return "lab/reaction-diffusion"; case .plotter: return "lab/glyph-plotter"; case .kinematic: return "lab/kinematic"
        case .phyllotaxis: return "lab/phyllotaxis"; case .homeStudy: return "lab/home"; case .study: return "lab/study"; case .webgpu: return "lab/webgpu-probe"
        case .components: return "components"; case .curveWho: return "lab/curve-who"; case .curveWhoReader: return "curve-who"; case .room: return "lab/room"; case .curveMotion: return "living-curves-art/"; case .hand: return "hand.html"
        }
    }

    /// The Mirror: the eight pieces that carry a numeral, a line and a technique (house.ts).
    var mirror: MirrorInfo? {
        switch self {
        case .warp: return MirrorInfo(numeral: "I", name: "The Breath", carries: "Prepared for luxury. The prepared state is a living one — it never rests.", technique: "UV displacement · gold HSV surface")
        case .plotter: return MirrorInfo(numeral: "II", name: "The Hand", carries: "You are in control of your reality. Control is constraint — every angle chosen.", technique: "constrained plotter walk · accumulating field")
        case .reaction: return MirrorInfo(numeral: "III", name: "The Seed", carries: "What persists in the mind becomes your reality. One point persists, spreads, becomes the field.", technique: "Gray-Scott reaction-diffusion · ping-pong texture")
        case .glitch: return MirrorInfo(numeral: "IV", name: "The Mend", carries: "The Defiance. What survives the break, gilded — the Golden Mend.", technique: "block glitch · chromatic aberration")
        case .phyllotaxis: return MirrorInfo(numeral: "V", name: "The Unfolding", carries: "Growth that obeys a law — the golden angle, the same ratio in seeds, shells, and petals.", technique: "phyllotaxis · golden angle")
        case .kinematic: return MirrorInfo(numeral: "VI", name: "The Following", carries: "Each link follows the last — the hand follows the mind, the mind follows the law.", technique: "kinematic beziers · five chains")
        case .webgpu: return MirrorInfo(numeral: "VII", name: "The Engine", carries: "What the house is built on — the bare machine, shown its own capability.", technique: "Metal · gold gradient shader")
        case .life: return MirrorInfo(numeral: "VIII", name: "The Company", carries: "Two neighbours or three. Alone you go out, crowded you go out — what you keep around you decides whether you last.", technique: "Conway's Life · ping-pong texture · rule driven by the envelope")
        default: return nil
        }
    }
    static let mirrorOrder: [LabPage] = [.warp, .plotter, .reaction, .glitch, .phyllotaxis, .kinematic, .webgpu, .life]

    @MainActor @ViewBuilder func content(_ model: AppModel) -> some View {
        switch self {
        case .warp: LabWarpView()
        case .plotter: LabPlotterView()
        case .reaction: LabReactionView()
        case .glitch: LabGlitchView()
        case .phyllotaxis: LabPhyllotaxisView()
        case .kinematic: LabKinematicView()
        case .webgpu: LabMetalProbeView()
        case .life: LabLifeView()
        case .ribbon: LabRibbonView(model: model)
        case .goldenMend: LabGoldenMendView()
        case .fluid: LabFluidView()
        case .ar: LabARView(model: model)
        case .fly: LabFlyView(model: model)
        case .dance: GlyphGuyRoom(kind: .dance)
        case .glyphbot: GlyphGuyRoom(kind: .glyphbot)
        case .heart: LabHeartView()
        case .wordmark: LabWordmarkView()
        case .cards: LabCardsView(model: model)
        case .curveWho: LabCurveWhoView()
        case .curveWhoReader: LabCurveWhoReaderView()
        case .room: LabRoomView(model: model)
        case .hero: LabHeroView()
        case .homeStudy: LabHomeStudyView()
        case .study: LabStudyView()
        case .components: LabComponentsView()
        case .curveMotion: LabCurveMotionView()
        case .hand: LabHandView()
        }
    }
}

struct MirrorInfo { let numeral: String; let name: String; let carries: String; let technique: String }

/// The Labs index: every lab, native. Replaces `WebListRoom(title: "Labs")` (the line is in LANES-labs.md).
struct LabsRoom: View {
    let model: AppModel
    var body: some View {
        List {
            Section {
                NavigationLink { NativeVJRoom(model: model) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("● Live").gEyebrow(10).foregroundStyle(PLG.red)
                        Text("The VJ").gTitle(22)
                        Text("The living set as a controller: tracks, tap tempo, rack.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { LabHost(page: .ribbon, model: model) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ribbon").gEyebrow(10).foregroundStyle(PLG.goldDim(.dark))
                        Text("Living Curves, the ribbon lab").gTitle(22)
                    }
                }
            } header: { Text("Instruments and experiments. The VJ lives here now.") }
            Section("The Mirror") { ForEach(LabPage.mirrorOrder) { row($0) } }
            Section("Instruments") { ForEach([LabPage.goldenMend, .fluid, .ar, .fly]) { row($0) } }
            Section("Figures and models") { ForEach([LabPage.dance, .glyphbot, .heart, .wordmark, .cards, .curveWho, .curveWhoReader, .room]) { row($0) } }
            Section("Studies") { ForEach([LabPage.hero, .homeStudy, .study, .components, .curveMotion, .hand]) { row($0) } }
        }
        .gScreen()
        .navigationTitle("The Labs")
    }

    private func row(_ p: LabPage) -> some View {
        NavigationLink { LabHost(page: p, model: model) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let m = p.mirror { Text(m.numeral).gEyebrow(10).foregroundStyle(PLG.goldDim(.dark)) }
                        Text(p.mirror?.name ?? p.title)
                    }
                    Text(p.line).font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: p.symbol) }
        }
    }
}

/// One lab full-bleed on the Mirror's dark ground, with the caption the web page draws at the bottom left. The eight Mirror pieces
/// carry the page's own ‹ and › to their neighbours. The back gesture and the title bar stay.
struct LabHost: View {
    let page: LabPage
    let model: AppModel
    @State private var current: LabPage
    @Environment(\.colorScheme) private var scheme

    init(page: LabPage, model: AppModel) { self.page = page; self.model = model; _current = State(initialValue: page) }

    var body: some View {
        ZStack {
            Color(hex: 0x0a0a0a).ignoresSafeArea()
            current.content(model).id(current).ignoresSafeArea(edges: .bottom)
            if let m = current.mirror { mirrorChrome(m) }
        }
        .navigationTitle(current.mirror?.name ?? current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let u = URL(string: LibraryData.shared.base(model) + "/" + current.path) { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } } }
        }
    }

    private func mirrorChrome(_ m: MirrorInfo) -> some View {
        let order = LabPage.mirrorOrder
        let i = order.firstIndex(of: current) ?? 0
        let gold = PLG.gold
        return ZStack {
            HStack {
                Button { current = order[(i - 1 + order.count) % order.count] } label: { Text("‹").font(.system(size: 30, design: .serif)).foregroundStyle(gold.opacity(0.4)).frame(width: 44, height: 88) }
                    .accessibilityLabel("Previous: \(order[(i - 1 + order.count) % order.count].mirror?.name ?? "")")
                Spacer()
                Button { current = order[(i + 1) % order.count] } label: { Text("›").font(.system(size: 30, design: .serif)).foregroundStyle(gold.opacity(0.4)).frame(width: 44, height: 88) }
                    .accessibilityLabel("Next: \(order[(i + 1) % order.count].mirror?.name ?? "")")
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(m.numeral) · The Mirror").font(.system(size: 11, design: .serif)).labCaps().tracking(2.4).foregroundStyle(gold.opacity(0.55))
                    Text(m.name).font(.system(size: 21, design: .serif)).foregroundStyle(gold.opacity(0.95)).padding(.top, 6)
                    Text(m.carries).font(.system(size: 12, design: .serif)).foregroundStyle(gold.opacity(0.62)).lineSpacing(3).padding(.top, 8)
                    Text(m.technique).font(.system(size: 10, design: .serif)).labCaps().tracking(1.4).foregroundStyle(gold.opacity(0.38)).padding(.top, 8)
                }
                .padding(.horizontal, 20).padding(.bottom, 26).frame(maxWidth: 330, alignment: .leading)
                .shadow(color: .black.opacity(0.8), radius: 6)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
    }
}

/// The caption the single pieces draw at the bottom left (Heart, Golden Mend): italic title over a spaced caps line.
struct LabCaption: View {
    let title: String
    let line: String
    var tint: Color = PLG.gold
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, design: .serif).italic()).foregroundStyle(tint.opacity(0.85))
            Text(line.uppercased()).font(.system(size: 10)).tracking(2.2).foregroundStyle(tint.opacity(0.5))
        }
        .padding(.leading, 20).padding(.bottom, 26)
        .shadow(color: tint == PLG.gold ? .black.opacity(0.8) : .clear, radius: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Small caps as the web draws them: capitals, spaced by the caller.
    func labCaps() -> some View { textCase(.uppercase) }
}

/// A small gold pill button for a lab's own control, as the web draws it (the mic opt-in, the step arrows).
struct LabPill: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).gEyebrow(11)
            }
            .foregroundStyle(PLG.gold)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background { Capsule().fill(PLG.gold.opacity(0.1)) }
            .overlay { Capsule().strokeBorder(PLG.gold.opacity(0.4), lineWidth: 0.9) }
        }
        .buttonStyle(.plain)
    }
}
