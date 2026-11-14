import RealityKit
import SwiftUI

// The rest of the site's /catalogue page around its viewer (`app/catalogue/page.tsx`): Living Curves inside the archive with
// the black-and-white GlyphGuy (`LivingCurvesShowcase`), the Mirror's doors (`MirrorDoors`, each opening its native Lab), the
// Chosen strip, then the close, the Wardrobe while a model is visible, and the Sanctuary.

struct ArchiveStrips: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Within the archive \u{2014} an ongoing series").siteLabel()
                SiteDisplay(parts: [("Living ", false), ("Curves.", true)], size: 36)
                Text("Not finished. Not archived. The mark that governs the archive \u{2014} rendered in code the same way it was drawn in the studio.").siteBody(15)
                NavigationLink { LivingCurvesView() } label: { SiteDoorLabel(title: "The seven systems \u{2192}") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.vertical, 32)

            SiteBand {
                VStack(spacing: 14) {
                    GlyphSolo(look: .marble).frame(height: 300)
                    Text("The curve, embodied.").font(SiteFont.display(22, italic: true)).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.8))
                }
                .frame(maxWidth: .infinity)
            }

            SiteBand {
                Text("The Mirror \u{2014} the doors").siteTag(11, Bone.gold)
                SiteDisplay(parts: [("Seven ways ", false), ("in.", true)], size: 32)
                Text("The generative wing of the archive \u{2014} the doctrine, still running. Walk through any door. The full exhibition lives in The Study.").siteBody(14)
                NavigationLink { StudyView(jumpToMirror: true) } label: { SiteDoorLabel(title: "The Study \u{2192}", gold: true) }.buttonStyle(.plain)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                    ForEach(MirrorDoor.all) { d in
                        NavigationLink { LabHost(page: d.page, model: .shared) } label: {
                            VStack(spacing: 10) {
                                Text(d.numeral).plHand(30).foregroundStyle(Bone.gold.opacity(0.7))
                                Text(d.name).font(SiteFont.display(17)).foregroundStyle(Color(hex: 0xf1ece1))
                            }
                            .frame(maxWidth: .infinity, minHeight: 110).background(Color(hex: 0x0e0c08))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(d.numeral), \(d.name)")
                    }
                }
                .background(Color.white.opacity(0.06))
                .overlay { Rectangle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6) }
            }

            ChosenStrip().padding(.horizontal, 24).padding(.vertical, 32)
            SiteRule().padding(.horizontal, 24)
        }
    }
}

/// `MIRROR` in `components/art/house.ts`: the doors the site lists today (the Engine's door was retired, C31 L-1).
struct MirrorDoor: Identifiable {
    let page: LabPage
    var id: String { page.rawValue }
    var numeral: String { page.mirror?.numeral ?? "" }
    var name: String { page.mirror?.name ?? page.title }
    static let all: [MirrorDoor] = [LabPage.warp, .plotter, .reaction, .glitch, .phyllotaxis, .kinematic].map { MirrorDoor(page: $0) }
}

/// One GlyphGuy standing in a look, breathing (the archive's `GlyphBotHero variant="bw"`). His model, never redrawn.
struct GlyphSolo: View {
    let look: GlyphLook
    var clip: GlyphClip = .idle
    @State private var fig = GlyphFigure()
    @State private var missing = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        RealityView { content in
            let cam = PerspectiveCamera(); cam.camera.fieldOfViewInDegrees = 32
            cam.position = [0, 0.9, 3.6]; cam.look(at: [0, 0.85, 0], from: cam.position, relativeTo: nil)
            content.add(cam)
            content.add(ThreeDModels.light(intensity: 3000, at: [2, 4, 3], look: [0, 1, 0]))
            content.add(ThreeDModels.light(intensity: 1400, at: [-3, 2, 2], look: [0, 1, 0]))
            guard await fig.load(height: 1.7, look: look, world: true) else { missing = true; return }
            content.add(fig.root)
            if !reduce { await fig.play(clip) }
        }
        .task {
            var last = Date()
            while !Task.isCancelled {
                let now = Date(); if !reduce { fig.tick(Float(now.timeIntervalSince(last))) }; last = now
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .overlay { if missing { SiteGlyphMask(url: Site.page("glyphs/glyph-guy.png"), color: Color(hex: 0xf1ece1).opacity(0.5)).frame(width: 120, height: 160) } }
        .shadow(color: .white.opacity(0.12), radius: 30, y: 8)
        .accessibilityLabel("GlyphGuy")
    }
}

struct ArchiveClose: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Text("What you are looking at is the longest argument the brand makes.")
                    .font(SiteFont.display(26, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
                NavigationLink { SiteShopList() } label: { Text("Wear the work \u{2014} shop the collection \u{2192}") }.buttonStyle(SitePill(gold: true))
                Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: { Text("The practice is still running \u{2192}") }.buttonStyle(SitePill())
            }
            .padding(.horizontal, 24).padding(.vertical, 56)

            if WardrobePiece.hasVisible {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Worn in Two Worlds \u{2014} in 3D & AR").siteTag(11, Bone.gold)
                    Text("The Wardrobe").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme))
                    Text("Turn each piece in your hand. On a phone, place it in your room at full scale. The same garment the avatar wears in Horizon \u{2014} one object, two bodies.").siteBody(15)
                    ForEach(WardrobePiece.visible) { WardrobeCard(piece: $0, compact: true) }
                    NavigationLink { WardrobeView() } label: { Text("Enter the full Wardrobe \u{2192}") }.buttonStyle(SiteGhost())
                }
                .padding(.horizontal, 24).padding(.vertical, 48)
                .overlay(alignment: .top) { SiteRule() }
            }

            do {
                VStack(spacing: 22) {
                    Text("The Sanctuary \u{2014} a built space").siteTag(11, Bone.gold)
                    (Text("The archive does not\nend at the ") + Text("page.").foregroundColor(Bone.gold))
                        .font(SiteFont.display(38, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                    Text("It extends into a room \u{2014} architecture you can walk, raised inside Meta Horizon. Every world there is now open on the web. No headset required. You do not look at the Sanctuary. You enter it.")
                        .siteBody(15).multilineTextAlignment(.center)
                    Button { if let u = URL(string: "https://horizon.meta.com/worlds/1149841928202125/") { openURL(u) } } label: { Text("Enter the Sanctuary \u{2192}").padding(.horizontal, 12) }
                        .buttonStyle(SitePill(gold: true)).fixedSize()
                    VStack(spacing: 1) {
                        card("Helium", "Will Haynes\u{2019} sound, made for the brand, carried through the room. The Sanctuary has an ear.")
                        card("The Glyphs", "The visual vocabulary, raised off the page and into the architecture. Symbols you can stand beside.")
                        card("Gatherings", "A room is for more than one. The congregation has somewhere to assemble that is not a feed.")
                    }
                    .background(Color.white.opacity(0.1))
                }
                .padding(.horizontal, 24).padding(.vertical, 72).frame(maxWidth: .infinity)
                .background { ZStack { Color(hex: 0x0e0c08); GoldCurvesLayer(opacity: 0.6) } }
                .environment(\.colorScheme, .dark)
            }
        }
    }

    private func card(_ h: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(h).font(SiteFont.display(22)).foregroundStyle(Color(hex: 0xf1ece1))
            Text(d).siteBody(14)
        }
        .padding(28).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x0e0c08))
        .accessibilityElement(children: .combine)
    }
}
