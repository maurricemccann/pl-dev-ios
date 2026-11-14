import RealityKit
import SwiftUI

// The three collection pages the site writes by hand (`app/seeds`, `app/glyphs`, `app/the-heart`), wrapped around the
// collection's live pieces in `CollectionView`: Seeds gets its 2019/2026/2029 window and the countdown to April 19 2029,
// Glyphs its manifesto, the GlyphBot pair and the four glyph cards, the Heart its manifesto, the 3D heart and the spinning
// ring. Every word is the page's own.

enum CollectionStory {
    /// Which slugs have a page of their own on the site.
    static func has(_ slug: String) -> Bool { ["seeds", "glyphs", "heart-logo", "classics"].contains(slug) }

    @MainActor @ViewBuilder static func top(_ slug: String) -> some View {
        switch slug {
        case "seeds": SeedsTop()
        case "glyphs": GlyphsTop()
        default: HeartTop()
        }
    }

    @MainActor @ViewBuilder static func bottom(_ slug: String) -> some View {
        switch slug {
        case "seeds": SeedsBottom()
        case "glyphs": GlyphsBottom()
        default: HeartBottom()
        }
    }
}

/// A page opening: eyebrow, the big italic gold title, the lede.
private struct StoryHead: View {
    let eyebrow: String
    let parts: [(String, Bool)]
    let lede: String
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(eyebrow).siteLabel()
            SiteDisplay(parts: parts, size: 52)
            Text(lede).siteBody(16)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
    }
}

// MARK: - Seeds

private struct SeedsTop: View {
    var body: some View {
        VStack(spacing: 28) {
            StoryHead(eyebrow: "Seeds \u{2014} timestamped, 2026\u{2013}2029", parts: [("Seeds.", true)],
                      lede: "A misplaced word. A symbol without explanation. These started as hand-painted art cards, handed to strangers with no context. The art came first; the fabric came second. The garment is the carrier, not the canvas \u{2014} the first public surface a private work ever touched.")
            SiteBand {
                Text("The window").siteTag(11, Bone.gold).frame(maxWidth: .infinity)
                HStack(spacing: 1) {
                    year("2019", "The ledger opens", .past)
                    year("2026", "Seeds launches", .now)
                    year("2029", "Seeds closes", .future)
                }
                .background(Color.white.opacity(0.1))
                Text("Scarcity is not a tactic. It is a timestamp. The person who owns a Seeds piece owns a piece of the becoming \u{2014} not the arrival. Three years from now, this page is an archive.")
                    .siteBody(14).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                SiteRule().padding(.top, 8)
                SeedsCountdown()
            }
        }
    }

    enum When { case past, now, future }

    private func year(_ y: String, _ label: String, _ w: When) -> some View {
        VStack(spacing: 10) {
            Text(y).font(SiteFont.display(34)).foregroundStyle(w == .future ? Bone.gold : w == .now ? Color(hex: 0xf1ece1) : Color(hex: 0x9b937f))
            Text(label).siteLabel(9).multilineTextAlignment(.center)
            if w == .now { Text("you are here").plHand(18).foregroundStyle(Bone.gold) }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .top).padding(.vertical, 20).padding(.horizontal, 4)
        .background(Color(hex: 0x0e0c08))
        .accessibilityElement(children: .combine)
    }
}

/// `SeedsCountdown`: days, hours, minutes, seconds to April 19 2029 at midnight Pacific (PDT, -07:00). A still snapshot under
/// Reduce Motion, as the site's.
struct SeedsCountdown: View {
    static let target: Date = {
        let f = ISO8601DateFormatter(); return f.date(from: "2029-04-19T00:00:00-07:00") ?? .distantFuture
    }()
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var frozen = Date()

    static func parts(_ now: Date) -> (Int, Int, Int, Int) {
        let s = max(0, Int(target.timeIntervalSince(now)))
        return (s / 86400, (s % 86400) / 3600, (s % 3600) / 60, s % 60)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Time remaining").siteLabel(10)
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                let p = Self.parts(reduce ? frozen : tl.date)
                HStack(spacing: 1) {
                    cell("\(p.0)", "Days"); cell(pad(p.1), "Hours"); cell(pad(p.2), "Minutes"); cell(pad(p.3), "Seconds")
                }
                .background(Color.white.opacity(0.1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.0) days, \(p.1) hours, \(p.2) minutes remaining")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    private func cell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(SiteFont.display(30)).foregroundStyle(Bone.gold).monospacedDigit().contentTransition(.numericText())
            Text(l).siteLabel(9)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).background(Color(hex: 0x0e0c08))
    }
}

private struct SeedsBottom: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 28) {
            Text("This window runs three years. What you wore becomes what you lived through.")
                .font(SiteFont.display(30, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
            NavigationLink { SiteShopList() } label: { Text("Acquire the work").padding(.horizontal, 12) }.buttonStyle(SitePill(gold: true)).fixedSize()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
    }
}

// MARK: - Glyphs

struct SiteGlyph: Identifiable {
    let name: String
    let slug: String
    let img: String
    let body: String
    var id: String { slug }
    @MainActor var url: URL? { Site.page(img) }

    static let four: [SiteGlyph] = [
        SiteGlyph(name: "What Goes Around Comes Around", slug: "what-goes-around-comes-around", img: "glyphs/smiley.png", body: "The arrow exits and creates the smile on its way back. The expression is not fixed \u{2014} it is generated by the motion itself. The act of giving produces the joy."),
        SiteGlyph(name: "Love Yourself", slug: "love-yourself-glyph", img: "glyphs/love-yourself.png", body: "The arrow does not leave the heart. It curves inward, pointing back to the center \u{2014} back to you. Before the philosophy can move outward, it has to live inside first."),
        SiteGlyph(name: "Money Glyph", slug: "money-glyph", img: "glyphs/money.png", body: "The dollar sign with an arrow. One direction. Up. Not as greed. As physics. As a decision made about the trajectory of a life, and a refusal to entertain the alternative."),
        SiteGlyph(name: "Glyph Guy", slug: "money-glyphguy", img: "glyphs/glyph-guy.png", body: "A figure built from the word money. Jester crown floating above. Arms raised in celebration. This is abundance as a posture \u{2014} not something pursued, something inhabited."),
    ]
}

private struct GlyphsTop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StoryHead(eyebrow: "Glyphs \u{2014} the visual vocabulary", parts: [("Glyphs.", true)],
                      lede: "Every mark is a word in a language that existed before it had an audience. These are not graphics. They are glyphs \u{2014} symbols carrying psychological weight, pulled from a seven-year archive of original work.")
            GlyphPair().frame(height: 260).padding(.horizontal, 24)
            VStack(spacing: 0) {
                ForEach(SiteGlyph.four) { g in
                    NavigationLink { CollectionView(slug: g.slug, state: ShopSection.state) } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            SiteGlyphMask(url: g.url, color: Bone.ink(scheme)).frame(width: 96, height: 112, alignment: .leading)
                            Text(g.name).font(SiteFont.display(30)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.leading)
                            Text(g.body).siteBody(14).multilineTextAlignment(.leading)
                            Text("Wear this glyph \u{2192}").siteLabel(10)
                        }
                        .padding(28).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    SiteRule()
                }
            }
            .overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
            .padding(.horizontal, 24)
            SiteBand {
                VStack(spacing: 24) {
                    Text("The set is the commitment").siteTag(11, Bone.gold)
                    Text("A single piece is a statement. The matching set \u{2014} sweater and sweatpants in the same glyph \u{2014} is a uniform.")
                        .font(SiteFont.display(25, italic: true)).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                    HStack(alignment: .bottom, spacing: 32) {
                        ForEach(SiteGlyph.four) { SiteGlyphMask(url: $0.url, color: Bone.gold.opacity(0.8)).frame(width: 44, height: 56) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Text("The glyph collection").siteLabel().padding(.horizontal, 24)
        }
    }
}

private struct GlyphsBottom: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 22) {
            Text("The symbol you choose reveals more than you think.").font(SiteFont.display(30, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: { SiteDoorLabel(title: "State Your Reality \u{2192}") }.buttonStyle(.plain)
                NavigationLink { StudyView() } label: { SiteDoorLabel(title: "The Study \u{2192}") }.buttonStyle(.plain)
            }
            NavigationLink { SiteReaderView(path: "three-bodies", title: "Three bodies of work") } label: { SiteDoorLabel(title: "The Three Bodies \u{2192}") }.buttonStyle(.plain)
            SiteWatch()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
    }
}

/// The GlyphBot pair from Aim for Love (`GlyphBotHero pair`): him in hammered gold, her in clay, side by side, each dancing at
/// its own tempo so they drift apart. His model, converted, never redrawn. Her dress (`buildHer` on the web) is not drawn here.
struct GlyphPair: View {
    @State private var him = GlyphFigure()
    @State private var her = GlyphFigure()
    @State private var missing = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        RealityView { content in
            let cam = PerspectiveCamera(); cam.camera.fieldOfViewInDegrees = 34
            cam.position = [0, 0.9, 4.4]; cam.look(at: [0, 0.85, 0], from: cam.position, relativeTo: nil)
            content.add(cam)
            content.add(ThreeDModels.light(intensity: 3000, at: [2, 4, 3], look: [0, 1, 0]))
            content.add(ThreeDModels.light(intensity: 1200, at: [-3, 2, 2], look: [0, 1, 0]))
            guard await him.load(height: 1.7, look: .gold, world: false), await her.load(height: 1.6, look: .gold, world: false) else { missing = true; return }
            if let m = her.model { ThreeDModels.paint(m, SimpleMaterial(color: UIColor(red: 0.76, green: 0.55, blue: 0.43, alpha: 1), roughness: 0.8, isMetallic: false)) }
            him.root.position.x = -0.55; her.root.position.x = 0.55
            content.add(him.root); content.add(her.root)
            if !reduce { await him.play(.samba); await her.play(.gangnam) }
        }
        .task {
            var last = Date()
            while !Task.isCancelled {
                let now = Date(), dt = Float(now.timeIntervalSince(last)); last = now
                if !reduce { him.tick(dt); her.tick(dt * 0.93) }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .overlay { if missing { SiteGlyphMask(url: Site.page("glyphs/glyph-guy.png"), color: Bone.gold.opacity(0.5)).frame(width: 120, height: 160) } }
        .shadow(color: Bone.gold.opacity(0.18), radius: 24, y: 8)
        .accessibilityLabel("GlyphBot and his partner, dancing")
    }
}

// MARK: - The Heart

private struct HeartTop: View {
    var body: some View {
        VStack(spacing: 18) {
            StoryHead(eyebrow: "The Heart \u{2014} Permanent Collection", parts: [("This is the ", false), ("floor.", true)],
                      lede: "The logo. The constitutional document of Psyched Luxuries rendered in fabric. It does not rotate. It does not drop. The heart is the conviction. The hands are the labor. The golden spiral is the proof that growth follows a pattern. What stays is what matters.")
            HeartCoin().frame(height: 380)
            Text("Heart \u{00B7} two hands \u{00B7} the golden spiral \u{2014} 3D sculpture of the permanent logo").siteLabel(10).multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }
}

/// `Heart3D`: his heart in true metallic gold (his S310 ruling), turning on its coin axis; drag to turn it yourself.
struct HeartCoin: View {
    @State private var missing = false
    var body: some View {
        OrbitStage(distance: 3.2, height: 0, autoSpin: true) { pivot in
            guard let url = Bundle.main.url(forResource: "heart1", withExtension: "usdz"), let e = try? await Entity(contentsOf: url) else { missing = true; return }
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0xe3 / 255, green: 0xa6 / 255, blue: 0x4c / 255, alpha: 1))
            m.roughness = .init(floatLiteral: 0.24)
            m.metallic = .init(floatLiteral: 1.0)
            ThreeDModels.paint(e, m)
            pivot.addChild(ThreeDModels.fitted(e, longest: 1.5))
        }
        .overlay { if missing { Image(systemName: "heart").font(.largeTitle).foregroundStyle(Bone.gold.opacity(0.4)) } }
        .accessibilityLabel("The heart mark in gold, turning. Drag to turn it.")
    }
}

private struct HeartBottom: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 28) {
            SpinningRing(text: "THE GARMENT IS NOT THE POINT \u{00B7} ") {
                Text("What stays is\nwhat matters.").font(SiteFont.display(22, italic: true)).foregroundStyle(Bone.gold).multilineTextAlignment(.center)
            }
            .frame(width: 260, height: 260)
            Text("You are not buying a season. You are buying the position itself.")
                .font(SiteFont.display(30, italic: true)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
            NavigationLink { CollectionView(slug: "glyphs", state: ShopSection.state) } label: { Text("The Glyphs") }.buttonStyle(SiteGhost())
            NavigationLink { CollectionView(slug: "seeds", state: ShopSection.state) } label: { Text("Seeds \u{2014} closing 2029") }.buttonStyle(SitePill())
            NavigationLink { StudyView() } label: { SiteDoorLabel(title: "The Philosophy \u{2192}") }.buttonStyle(.plain)
            SiteWatch()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
    }
}

/// `SpinningRing`: a line of tracked gold capitals around a circle, turning slowly, with something held in its middle.
struct SpinningRing<Center: View>: View {
    let text: String
    @ViewBuilder let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            let turn = reduce ? 0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 30) / 30 * 360
            Canvas { ctx, size in
                let chars = Array(String(repeating: text, count: 2))
                let r = min(size.width, size.height) / 2 - 10
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for (i, ch) in chars.enumerated() {
                    let a = (Double(i) / Double(chars.count)) * 2 * .pi + turn * .pi / 180
                    var g = ctx
                    g.translateBy(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    g.rotate(by: .radians(a + .pi / 2))
                    g.draw(Text(String(ch)).font(SiteFont.body(11)).foregroundColor(Bone.gold), at: .zero)
                }
            }
        }
        .overlay { center }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The garment is not the point. What stays is what matters.")
    }
}
