import RealityKit
import SwiftUI

/// `/curve`, the seed-card tap page (`app/curve/page.tsx`, `components/curve/CurveNameRitual.tsx`): "You were gifted a seed.",
/// GlyphBot in hammered gold acknowledging, the three seals that the visitor stamps by holding a finger on them, the social
/// doors, the name typed and shown in his curve alphabet (Curvedabc, fetched once like the Labs do) and saved as a picture,
/// then the register door. The register form itself is the site's human-check form, in Apple's sheet (allowed).
struct CurveNameView: View {
    @State private var name = ""
    @State private var curveFont: String?
    @State private var web: WebPage?
    @State private var shareImage: ShareImage?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    struct ShareImage: Identifiable { let image: Image; let id = UUID() }

    private static let socials: [(String, String)] = [
        ("Instagram", "https://instagram.com/psychedluxuries"), ("Threads", "https://www.threads.net/@psychedluxuries"),
        ("Tumblr", "https://psychedluxuries.tumblr.com"), ("Bluesky", "https://bsky.app/profile/psychedluxuries.bsky.social"),
        ("X", "https://x.com/psychedluxuries"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                do {
                    VStack(spacing: 22) {
                        CurveHeadline()
                        Text("A seed is a hand-made piece, meant to open your eyes to a new perspective. What you\u{2019}re holding is real \u{2014} it\u{2019}s a token of my life. It found you for a reason. Stay psyched.")
                            .siteBody(16).multilineTextAlignment(.center).padding(.bottom, 24)
                        GlyphSolo(look: .gold, clip: .wave).frame(height: 300)
                        StampSeals()
                        VStack(spacing: 14) {
                            Text("Find the practice").siteLabel(10)
                            HStack(spacing: 18) {
                                ForEach(Self.socials, id: \.0) { s in
                                    Button { if let u = URL(string: s.1) { openURL(u) } } label: { Text(s.0).siteLabel(10) }.buttonStyle(.plain).frame(minHeight: 44)
                                }
                            }
                        }
                        .padding(.top, 24)
                        VStack(spacing: 16) {
                            SiteRule().padding(.bottom, 24)
                            Text("One more thing (optional)").siteLabel(10)
                            TextField("Your name", text: $name)
                                .font(SiteFont.body(18)).multilineTextAlignment(.center).textContentType(.name).submitLabel(.done)
                                .padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(name.isEmpty ? Bone.line(scheme) : Bone.gold).frame(height: 1) }
                            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(name).font(curveFont.map { .custom($0, size: 54) } ?? SiteFont.display(48, italic: true))
                                    .foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center).minimumScaleFactor(0.4).lineLimit(3)
                                    .frame(minHeight: 72).padding(.top, 16)
                                    .accessibilityLabel("\(name), in the house curve alphabet")
                                Button { shareImage = render() } label: { Text("Get it as a picture \u{2192}") }.buttonStyle(SiteGhost()).fixedSize()
                            }
                        }
                        .padding(.top, 40)
                        VStack(spacing: 14) {
                            SiteRule().padding(.bottom, 24)
                            Text("Welcome to the family. The piece in your hand is a 1:1, made for you.").siteBody(16).multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                    }
                    .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 48)
                    .background { CurveDepthGlyphs() }
                }
                VStack(spacing: 18) {
                    SiteRule().padding(.bottom, 32)
                    Text("Send a photograph of your seed \u{2014} never the piece itself. It goes on record, dated and numbered.").siteBody(16).multilineTextAlignment(.center)
                    Button {   // the registration form runs behind the site's human check: Apple's sheet, the name carried by the clipboard
                        if !name.isEmpty { UIPasteboard.keep(name.trimmingCharacters(in: .whitespaces)) }
                        if let u = Site.page("register") { web = WebPage(u) }
                    } label: { Text("Register your seed \u{2192}") }.buttonStyle(SiteGhost()).fixedSize()
                    SiteRule().padding(.top, 32)
                    Text("Carry it further").siteLabel(10).padding(.top, 24)
                    NavigationLink { CollectionView(slug: "seeds", state: ShopSection.state) } label: { SiteDoorLabel(title: "The Seeds collection \u{2192}") }.buttonStyle(.plain)
                    Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: { SiteDoorLabel(title: "The Congregation \u{2192}") }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.bottom, 56)
            }
        }
        .siteScreen()
        .plScreenTitle("The Curve")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sheet(item: $shareImage) { s in
            VStack(spacing: 20) {
                s.image.resizable().scaledToFit().padding()
                ShareLink(item: s.image, preview: SharePreview(name, image: s.image)) { Text("Save or send") }.buttonStyle(SitePill())
            }
            .padding(24).presentationDetents([.medium])
        }
        .task { curveFont = await LabFonts.curved(model: .shared) }
    }

    /// The site's `exportPng`: 1200 by 400, the name centred in the curve face, ink on clear.
    @MainActor private func render() -> ShareImage? {
        let label = Text(name.trimmingCharacters(in: .whitespaces)).font(curveFont.map { .custom($0, size: 120) } ?? .system(size: 110, design: .serif))
            .foregroundStyle(Color(hex: 0x15120b)).minimumScaleFactor(0.3).lineLimit(1).frame(width: 1200, height: 400)
        let r = ImageRenderer(content: label); r.scale = 1
        guard let ui = r.uiImage else { return nil }
        return ShareImage(image: Image(uiImage: ui))
    }
}

/// "You were gifted a seed." in his hand, gold, word by word out of a soft blur (`CurveHeader`); still under Reduce Motion.
struct CurveHeadline: View {
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let words = ["You", "were", "gifted", "a", "seed."]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w).plHand(48).foregroundStyle(Bone.gold)
                    .opacity(reduce || i < shown ? 1 : 0).blur(radius: reduce || i < shown ? 0 : 6).offset(y: reduce || i < shown ? 0 : 20)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore).accessibilityLabel("You were gifted a seed.").accessibilityAddTraits(.isHeader)
        .task {
            guard !reduce else { return }
            try? await Task.sleep(for: .milliseconds(150))
            for i in 1...words.count { withAnimation(.easeOut(duration: 0.8)) { shown = i }; try? await Task.sleep(for: .milliseconds(160)) }
        }
    }
}

/// The background glyphs on three planes, faint ink (`DepthGlyphs`).
struct CurveDepthGlyphs: View {
    private static let glyphs = ["glyph-guy", "money", "love-yourself", "smiley"]
    private static let spots: [(Int, Double, Double, Double, Double)] = [(0, 0.03, 0.03, 78, -12), (1, 0.54, 0.82, 62, 8), (2, 0.68, 0.02, 72, 15), (3, 0.01, 0.78, 66, -6),
                                                                         (1, 0.24, 0.04, 54, 22), (3, 0.82, 0.70, 58, -18), (0, 0.90, 0.04, 50, 6)]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(Self.spots.enumerated()), id: \.offset) { i, s in
                let plane = Double(i % 3), size = s.3 * (0.85 + plane * 0.2)
                PLIcon.symbol(Self.glyphs[s.0]).resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(Bone.ink(scheme).opacity(0.045 + plane * 0.02))
                    .frame(width: size, height: size).rotationEffect(.degrees(s.4))
                    .position(x: geo.size.width * s.2 + size / 2, y: geo.size.height * s.1 + size / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The three seals are the control: they rest dim and ash-grey with a gold breath behind them; held for 0.9 s they fill with
/// gold and land with a stamp (`StampHero`). Stamped stays stamped for the session.
struct StampSeals: View {
    @State private var progress: Double = 0
    @State private var holding = false
    @State private var stamped = false
    @State private var landed = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    nonisolated(unsafe) private static var stampedThisSession = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                HouseSeal()
                VerifiedSeal()
                AuthenticitySeal()
            }
            .frame(maxWidth: 320).frame(height: 96)
            .saturation(stamped ? 1 : progress).opacity(stamped ? 1 : 0.3 + 0.7 * progress)
            .scaleEffect(holding ? 0.965 : 1)
            .background {
                if !stamped {
                    Ellipse().fill(RadialGradient(colors: [Bone.gold.opacity(0.55), Bone.gold.opacity(0)], center: .center, startRadius: 0, endRadius: 170))
                        .opacity(holding ? 0.35 + 0.5 * progress : 0.3).padding(-20)
                        .phaseAnimator([0.9, 1.05]) { v, p in v.scaleEffect(reduce ? 1 : p) } animation: { _ in .easeInOut(duration: 1.6) }
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.9, maximumDistance: 30) { complete() } onPressingChanged: { pressing in
                guard !stamped else { return }
                holding = pressing
                withAnimation(pressing ? .linear(duration: 0.9) : .easeOut(duration: 0.4)) { progress = pressing ? 1 : 0 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stamped ? "Your seals, stamped" : "Press and hold to stamp your seals")
            .accessibilityAction { complete() }
            .sensoryFeedback(.impact(weight: .heavy), trigger: landed)
            Text(stamped ? "Stamped" : "Press and hold").siteLabel(10)
        }
        .onAppear { if reduce || Self.stampedThisSession { stamped = true; progress = 1 } }
    }

    private func complete() {
        guard !stamped else { return }
        holding = false; stamped = true; progress = 1; landed += 1; Self.stampedThisSession = true
    }
}

// MARK: - The seals, drawn from the site's SVGs (each viewBox -102…102 scaled to the frame)

private func starPath(base: Double, long: Double, short: Double, points: Int, half: Bool) -> Path {
    var p = Path()
    let n = half ? points * 2 : points
    for i in 0..<n {
        let t = (half ? Double.pi : 2 * Double.pi) * Double(i) / Double(half ? points : points)
        let r = i % 2 == 0 ? base + long : base + short
        let pt = CGPoint(x: r * cos(t), y: r * sin(t))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

private func arcText(_ g: inout GraphicsContext, _ text: String, radius: Double, centerAngle: Double, size: CGFloat, tracking: Double, color: Color, top: Bool) {
    let chars = Array(text)
    let step = (Double(size) * 0.62 + tracking) / radius
    let start = centerAngle - step * Double(chars.count - 1) / 2 * (top ? 1 : -1)
    for (i, ch) in chars.enumerated() {
        let a = start + step * Double(i) * (top ? 1 : -1)
        var c = g
        c.translateBy(x: radius * cos(a), y: radius * sin(a))
        c.rotate(by: .radians(top ? a + .pi / 2 : a - .pi / 2))
        c.draw(Text(String(ch)).font(.custom("Jost-Semi", size: size)).foregroundColor(color), at: .zero)
    }
}

private struct SealCanvas: View {
    let draw: (inout GraphicsContext) -> Void
    var body: some View {
        Canvas { g, size in
            let s = min(size.width, size.height) / 204
            g.translateBy(x: size.width / 2, y: size.height / 2); g.scaleBy(x: s, y: s)
            draw(&g)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private let foil = Gradient(colors: [Color(hex: 0xe8d190), Color(hex: 0xd4b86a), Color(hex: 0xc9a84c), Color(hex: 0x7a5f2a)])
private let disc = Gradient(colors: [Color(hex: 0xf6e9c4), Color(hex: 0xe3c876), Color(hex: 0xa3812f)])

/// `HeartSeal`: sunburst foil, the disc, PSYCHED over LUXURIES on the arc, his heart mark pressed in the centre.
private struct HouseSeal: View {
    var body: some View {
        SealCanvas { g in
            let burst = starPath(base: 80, long: 20, short: 6, points: 48, half: false)
            g.fill(burst.offsetBy(dx: 1.4, dy: 2), with: .color(Color(hex: 0x3a2c14).opacity(0.45)))
            g.fill(burst, with: .linearGradient(foil, startPoint: CGPoint(x: -70, y: -80), endPoint: CGPoint(x: 70, y: 80)))
            g.stroke(burst, with: .color(Color(hex: 0x5c471f)), lineWidth: 0.6)
            let c74 = Path(ellipseIn: CGRect(x: -74, y: -74, width: 148, height: 148))
            g.fill(c74, with: .radialGradient(disc, center: CGPoint(x: -12, y: -20), startRadius: 0, endRadius: 96))
            g.stroke(c74, with: .color(Color(hex: 0x7a5f2a)), lineWidth: 1.2)
            g.stroke(Path(ellipseIn: CGRect(x: -70, y: -70, width: 140, height: 140)), with: .color(Color(hex: 0x5c471f).opacity(0.5)), lineWidth: 0.8)
            arcText(&g, "PSYCHED", radius: 58, centerAngle: -.pi / 2, size: 11.5, tracking: 2.6, color: Color(hex: 0x4a3818), top: true)
            arcText(&g, "LUXURIES", radius: 58, centerAngle: .pi / 2, size: 11.5, tracking: 2.6, color: Color(hex: 0x4a3818), top: false)
            let c34 = Path(ellipseIn: CGRect(x: -34, y: -34, width: 68, height: 68))
            g.fill(c34.offsetBy(dx: 0.8, dy: 1.2), with: .color(Color(hex: 0x3a2c14).opacity(0.18)))
            g.fill(c34, with: .radialGradient(disc, center: CGPoint(x: -5, y: -9), startRadius: 0, endRadius: 44))
            g.stroke(c34, with: .color(Color(hex: 0x4a3818)), lineWidth: 1)
        }
        .overlay { SiteLogoMark().foregroundStyle(Color(hex: 0x3a2c14)).scaleEffect(0.26) }
        .accessibilityLabel("Psyched Luxuries, the house mark seal")
    }
}

/// `VerifiedSeal`: two rough ink rules and VERIFIED in his hand, tilted, in dark gold.
private struct VerifiedSeal: View {
    var body: some View {
        ZStack {
            VStack(spacing: 34) {
                Capsule().fill(Color(hex: 0x7a5f22).opacity(0.9)).frame(height: 3)
                Capsule().fill(Color(hex: 0x7a5f22).opacity(0.9)).frame(height: 3)
            }
            Text("VERIFIED").plHand(24).foregroundStyle(Color(hex: 0x7a5f22)).lineLimit(1).minimumScaleFactor(0.5)
        }
        .rotationEffect(.degrees(-9))
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Verified, Psyched Luxuries")
    }
}

/// `AuthenticitySeal`: serrated foil, embossed rings, CERTIFICATE OF AUTHENTICITY / ORIGINAL ARTWORK, his curve in the centre.
private struct AuthenticitySeal: View {
    var body: some View {
        SealCanvas { g in
            let ser = starPath(base: 84, long: 14, short: 0, points: 44, half: true)
            g.fill(ser.offsetBy(dx: 1.4, dy: 2), with: .color(Color(hex: 0x3a2c14).opacity(0.4)))
            g.fill(ser, with: .linearGradient(Gradient(colors: [Color(hex: 0xecd695), Color(hex: 0xd4b86a), Color(hex: 0xc9a84c), Color(hex: 0x7a5f2a)]),
                                              startPoint: CGPoint(x: -76, y: -84), endPoint: CGPoint(x: 76, y: 84)))
            g.stroke(ser, with: .color(Color(hex: 0x5c471f)), lineWidth: 0.6)
            for (r, c, a) in [(80.0, UInt32(0xf6e9c4), 0.75), (77, 0x5c471f, 0.45), (52, 0xf6e9c4, 0.7), (49, 0x5c471f, 0.45)] {
                g.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(Color(hex: c).opacity(a)), lineWidth: 0.8)
            }
            arcText(&g, "CERTIFICATE OF AUTHENTICITY", radius: 66, centerAngle: -.pi / 2, size: 8.4, tracking: 0.9, color: Color(hex: 0xf6e9c4), top: true)
            arcText(&g, "ORIGINAL ARTWORK", radius: 66, centerAngle: .pi / 2, size: 9.2, tracking: 2.2, color: Color(hex: 0xf6e9c4), top: false)
            g.fill(Path(ellipseIn: CGRect(x: -38, y: -38, width: 76, height: 76)), with: .color(Color(hex: 0xf6e9c4).opacity(0.35)))
            var curve = Path()   // his curve-comp-01 stroke, as the site's seal carries it
            curve.move(to: CGPoint(x: -23.56, y: -10.26))
            curve.addCurve(to: CGPoint(x: 17.53, y: -1.95), control1: CGPoint(x: -2.28, y: -16.50), control2: CGPoint(x: 23.58, y: -18.89))
            curve.addCurve(to: CGPoint(x: -11.13, y: 18.87), control1: CGPoint(x: 11.47, y: 14.99), control2: CGPoint(x: -11.13, y: 18.87))
            g.stroke(curve.offsetBy(dx: 0.6, dy: 1), with: .color(Color(hex: 0x5c471f).opacity(0.4)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            g.stroke(curve, with: .color(Color(hex: 0xf6e9c4).opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .accessibilityLabel("Certificate of authenticity")
    }
}

// MARK: - His heart mark, read from the site's own logo.svg

/// The site's `/logo.svg` (a potrace trace: absolute and relative M, L, C and Z), fetched once and drawn as a native shape.
struct SiteLogoMark: View {
    @State private var path: Path?
    var body: some View {
        GeometryReader { geo in
            if let path {
                let b = path.boundingRect, s = min(geo.size.width / max(b.width, 1), geo.size.height / max(b.height, 1))
                path.applying(CGAffineTransform(translationX: -b.midX, y: -b.midY).concatenating(CGAffineTransform(scaleX: s, y: s))
                    .concatenating(CGAffineTransform(translationX: geo.size.width / 2, y: geo.size.height / 2)))
                    .fill()
            }
        }
        .task { path = await SiteLogo.path() }
        .accessibilityHidden(true)
    }
}

@MainActor enum SiteLogo {
    private static var cached: Path?
    static func path() async -> Path? {
        if let cached { return cached }
        guard let svg = await SiteData.html("logo.svg") else { return nil }
        let ds = SiteData.matches(#"<path d="([^"]+)""#, in: svg).map { $0[0] }
        guard !ds.isEmpty else { return nil }
        var all = Path()
        for d in ds { all.addPath(parse(d)) }
        // the trace's group: translate(0, 300) scale(0.1, -0.1)
        let p = all.applying(CGAffineTransform(a: 0.1, b: 0, c: 0, d: -0.1, tx: 0, ty: 300))
        cached = p
        return p
    }

    /// M/m, L/l, C/c, Z/z with implicit repeats: all a potrace path uses.
    nonisolated static func parse(_ d: String) -> Path {
        var tokens: [String] = []
        var num = ""
        for ch in d {
            if "MmLlCcZz".contains(ch) { if !num.isEmpty { tokens.append(num); num = "" }; tokens.append(String(ch)) }
            else if ch == " " || ch == "," || ch == "\n" || ch == "\r" || ch == "\t" { if !num.isEmpty { tokens.append(num); num = "" } }
            else if ch == "-" && !num.isEmpty && !num.hasSuffix("e") { tokens.append(num); num = "-" }
            else { num.append(ch) }
        }
        if !num.isEmpty { tokens.append(num) }
        var p = Path(), cur = CGPoint.zero, start = CGPoint.zero, cmd: Character = "M", i = 0
        func n() -> CGFloat? { guard i < tokens.count, let v = Double(tokens[i]) else { return nil }; i += 1; return CGFloat(v) }
        while i < tokens.count {
            if let c = tokens[i].first, tokens[i].count == 1, "MmLlCcZz".contains(c) { cmd = c; i += 1; if c == "Z" || c == "z" { p.closeSubpath(); cur = start }; continue }
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                guard let x = n(), let y = n() else { i += 1; continue }
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y); start = cur; p.move(to: cur)
                cmd = rel ? "l" : "L"
            case "L", "l":
                guard let x = n(), let y = n() else { i += 1; continue }
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y); p.addLine(to: cur)
            case "C", "c":
                guard let x1 = n(), let y1 = n(), let x2 = n(), let y2 = n(), let x = n(), let y = n() else { i += 1; continue }
                let o = rel ? cur : .zero
                let end = CGPoint(x: o.x + x, y: o.y + y)
                p.addCurve(to: end, control1: CGPoint(x: o.x + x1, y: o.y + y1), control2: CGPoint(x: o.x + x2, y: o.y + y2)); cur = end
            default: i += 1
            }
        }
        return p
    }
}
