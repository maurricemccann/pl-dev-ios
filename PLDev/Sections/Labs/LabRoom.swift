import RealityKit
import SwiftUI

/// /lab/room: the scroll room and the world gallery (gallery `app/lab/room/page.tsx`, `components/room/ScrollRoomLab.tsx`,
/// `components/world/WorldGalleryLab.tsx`; the site's `/room` tour is this same piece). A walk-in showroom: obsidian walls, a gold-trimmed
/// floor, six framed glyphs on the side walls, his gold GlyphGuy standing in a pool of light, and a door that is ajar with warm light spilling
/// out. Scrolling moves the camera along the page's own six-key path (`PATH`, smoothed 12 % a frame, eased with smoothstep); at the end the
/// word Enter appears and takes you out to the labs. The page's capture and still modes are video-render hooks and are not ported.
/// The page's three entrances map as follows: scroll (desktop) is the scroll here; the auto tour (touch) is not needed because a phone scrolls;
/// the still poster (reduced motion or no WebGL) is the scene held at one frame, with Enter shown at once.
/// Differences from the page, named: RealityKit has no planar reflector or fog, so the floor is a glossy dark surface and distance is carried
/// by the lights alone; the walls and floor are lit by the same placed lights rather than an environment map.
struct LabRoomView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var target = 0.0     // the scroll position, 0...1
    @State private var smooth = 0.0     // eased toward it, 12 % a frame, as the page does
    @State private var ready = false
    @State private var aspect = 0.5

    private static let path: [(pos: SIMD3<Float>, look: SIMD3<Float>)] = [
        ([0, 1.75, 6.8], [0, 1.6, -2]), ([-1.7, 1.6, 5.0], [-3.2, 1.6, 2.5]), ([-0.6, 1.5, 3.4], [2.0, 1.5, 1.2]),
        ([1.0, 1.5, 3.3], [0.15, 1.3, -1.6]), ([0.55, 1.45, 2.85], [0.05, 1.3, -1.9]), ([0.2, 1.48, 2.5], [-0.02, 1.28, -1.95]),
    ]
    private static let obsidian = UIColor(red: 14 / 255, green: 12 / 255, blue: 8 / 255, alpha: 1)

    var body: some View {
        let p = reduceMotion ? 0.35 : smooth
        let reveal = reduceMotion ? 1 : min(1, max(0, (smooth - 0.88) / 0.12))
        ZStack {
            Color(Self.obsidian).ignoresSafeArea()
            GeometryReader { geo in
                RealityView { content in
                    let cam = Entity(); cam.name = "cam"
                    cam.components.set(PerspectiveCameraComponent(near: 0.1, far: 100, fieldOfViewInDegrees: 40))
                    content.add(cam)
                    content.add(await Self.room(base: LibraryData.shared.base(model)))
                    ready = true
                } update: { content in
                    guard let cam = content.entities.first(where: { $0.name == "cam" }) else { return }
                    let (pos, look) = Self.camera(at: p)
                    cam.position = pos
                    cam.look(at: look, from: pos, relativeTo: nil)
                    // the page widens the view on narrow screens: 40 degrees at 1.6:1 and wider, up to 60 at 0.4:1
                    let a = geo.size.height > 0 ? Double(geo.size.width / geo.size.height) : 1
                    cam.components.set(PerspectiveCameraComponent(near: 0.1, far: 100, fieldOfViewInDegrees: Float(a >= 1.6 ? 40 : 40 + min(1, (1.6 - a) / 1.2) * 20)))
                }
                .onAppear { aspect = Double(geo.size.width / max(1, geo.size.height)) }
            }
            .allowsHitTesting(false)
            // the page's vignette
            RadialGradient(colors: [.clear, .black.opacity(0.28), .black.opacity(0.55)], center: .center, startRadius: 160, endRadius: 520).ignoresSafeArea().allowsHitTesting(false)

            if !reduceMotion {
                ScrollView { Color.clear.frame(height: UIScreen.main.bounds.height * 4.5) }   // the page's 450vh runway
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: Double.self) { g in Double(g.contentOffset.y / max(1, g.contentSize.height - g.containerSize.height)) } action: { _, v in
                        target = min(1, max(0, v))
                    }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .regular)).foregroundStyle(PLG.gold.opacity(0.75))
                            .frame(width: 44, height: 44).overlay { Circle().strokeBorder(PLG.gold.opacity(0.25), lineWidth: 1) }
                    }
                    .accessibilityLabel("Leave the room")
                }
                .padding(.horizontal, 20).padding(.top, 8)
                Spacer()
                if !reduceMotion && smooth < 0.12 {
                    VStack(spacing: 8) {
                        Text("scroll to enter").font(.system(size: 11, design: .serif)).labCaps().tracking(2.4).foregroundStyle(PLG.gold.opacity(0.7))
                        Rectangle().fill(PLG.gold.opacity(0.4)).frame(width: 1, height: 28)
                    }
                    .opacity(max(0, 1 - smooth * 8)).padding(.bottom, 30)
                }
                if reveal > 0.01 {
                    Button { dismiss() } label: {
                        VStack(spacing: 10) {
                            Text("Enter").font(.system(size: 52, design: .serif).italic()).foregroundStyle(PLG.gold)
                            Text("the labs").font(.system(size: 11, design: .serif)).labCaps().tracking(2.4).foregroundStyle(PLG.goldDim(.dark))
                        }
                        .frame(minWidth: 160, minHeight: 88)
                    }
                    .buttonStyle(.plain)
                    .opacity(reveal).offset(y: (1 - reveal) * 28).allowsHitTesting(reveal > 0.6).padding(.bottom, 60)
                }
            }
            VStack {
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%03d", Int((p * 99).rounded()) + 1)).font(.system(size: 24, design: .serif)).monospacedDigit().foregroundStyle(PLG.gold.opacity(0.55))
                    Text("the room").font(.system(size: 10, design: .serif)).labCaps().tracking(2.2).foregroundStyle(PLG.goldDim(.dark).opacity(0.7))
                    Spacer()
                }
                .padding(.leading, 24).padding(.bottom, 26).opacity(ready ? 1 : 0).animation(.easeIn(duration: 0.7), value: ready)
            }
            .allowsHitTesting(false)
        }
        .task {
            // the page's own easing: toward the scroll position, 12 % of the way each frame
            while !Task.isCancelled {
                if abs(target - smooth) > 0.0005 { smooth += (target - smooth) * 0.12 } else { smooth = target }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The room. A walk-in showroom with framed glyphs on the walls, a gold figure under a light, and a half-open door. Scroll to walk in.")
    }

    private static func camera(at progress: Double) -> (SIMD3<Float>, SIMD3<Float>) {
        let t = Float(progress), e = t * t * (3 - 2 * t)
        return (LabTube.point(path.map(\.pos), e), LabTube.point(path.map(\.look), e))
    }

    // MARK: the room

    @MainActor private static func room(base: String) async -> Entity {
        let root = Entity()
        let obsidianTint = UIColor(red: 0x17 / 255, green: 0x13 / 255, blue: 0x10 / 255, alpha: 1)
        func pbr(_ c: UIColor, rough: Float, metal: Float = 0) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial(); m.baseColor = .init(tint: c)
            m.roughness = .init(floatLiteral: rough); m.metallic = .init(floatLiteral: metal); return m
        }
        var gold = pbr(ThreeDHouse.gold, rough: 0.28, metal: 1)
        gold.emissiveColor = .init(color: UIColor(red: 0x2a / 255, green: 0x20 / 255, blue: 0x08 / 255, alpha: 1)); gold.emissiveIntensity = 0.45
        func plane(_ w: Float, _ h: Float, _ m: RealityKit.Material, at p: SIMD3<Float>, ry: Float = 0, rx: Float = 0) -> ModelEntity {
            let e = ModelEntity(mesh: .generatePlane(width: w, height: h), materials: [m])
            e.position = p
            e.orientation = simd_quatf(angle: ry, axis: [0, 1, 0]) * simd_quatf(angle: rx, axis: [1, 0, 0])
            return e
        }
        func box(_ w: Float, _ h: Float, _ d: Float, _ m: RealityKit.Material, at p: SIMD3<Float>) -> ModelEntity {
            let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [m]); e.position = p; return e
        }
        func point(_ rgb: UInt32, _ lumens: Float, radius: Float, at p: SIMD3<Float>) -> Entity {
            let e = Entity()
            e.components.set(PointLightComponent(color: UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1), intensity: lumens, attenuationRadius: radius))
            e.position = p; return e
        }
        func spot(_ rgb: UInt32, _ lumens: Float, at p: SIMD3<Float>, look: SIMD3<Float>, angle: Float) -> Entity {
            let e = Entity()
            e.components.set(SpotLightComponent(color: UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1),
                                                intensity: lumens, innerAngleInDegrees: angle * 0.6, outerAngleInDegrees: angle, attenuationRadius: 12))
            e.position = p; e.look(at: look, from: p, relativeTo: nil); return e
        }

        // the shell
        let wall = pbr(obsidianTint, rough: 0.9)
        root.addChild(plane(10, 4.5, wall, at: [0, 2.25, -2]))
        root.addChild(plane(9, 4.5, wall, at: [-5, 2.25, 2.5], ry: .pi / 2))
        root.addChild(plane(9, 4.5, wall, at: [5, 2.25, 2.5], ry: -.pi / 2))
        root.addChild(plane(10, 9, wall, at: [0, 4.5, 2.5], rx: .pi / 2))
        // the floor: dark and glossy (the page's mirror, without the mirror)
        root.addChild(plane(40, 40, pbr(UIColor(red: 0x22 / 255, green: 0x1b / 255, blue: 0x0f / 255, alpha: 1), rough: 0.16, metal: 0.55), at: [0, 0, 0], rx: -.pi / 2))
        // gold skirting
        root.addChild(box(10, 0.05, 0.05, gold, at: [0, 0.025, -1.98]))
        for sx: Float in [-1, 1] { root.addChild(box(0.05, 0.05, 9, gold, at: [sx * 4.98, 0.025, 2.5])) }

        // the mark above the door: his own PL mark, gold, lit from a wash light
        if let mark = UIImage(named: "PLIcons/pl-mark")?.withRenderingMode(.alwaysTemplate), let tinted = Self.tint(mark, ThreeDHouse.gold), let cg = tinted.cgImage,
           let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            var m = UnlitMaterial(); m.color = .init(tint: .white, texture: .init(tex)); m.blending = .transparent(opacity: .init(floatLiteral: 1))
            root.addChild(plane(1.25, 1.25, m, at: [0, 3.5, -1.95]))
            root.addChild(point(0xffe6ad, 9000, radius: 6, at: [0, 3.4, -1.3]))
        }

        // the door, ajar: warm light beyond, gold jambs, the dark panel swung open
        let doorW: Float = 1.2, doorH: Float = 2.5, dz: Float = -1.95
        root.addChild(plane(doorW, doorH, pbr(UIColor(red: 0x2a / 255, green: 0x10 / 255, blue: 0x05 / 255, alpha: 1), rough: 1), at: [0, doorH / 2, dz - 0.04]))
        root.addChild(box(doorW + 0.2, 0.1, 0.1, gold, at: [0, doorH + 0.05, dz]))
        root.addChild(box(0.1, doorH + 0.15, 0.1, gold, at: [-(doorW / 2 + 0.05), doorH / 2, dz]))
        root.addChild(box(0.1, doorH + 0.15, 0.1, gold, at: [doorW / 2 + 0.05, doorH / 2, dz]))
        let hinge = Entity(); hinge.position = [doorW / 2 + 0.05, doorH / 2, dz + 0.06]
        let panel = box(doorW, doorH, 0.06, pbr(UIColor(red: 0x14 / 255, green: 0x11 / 255, blue: 0x0b / 255, alpha: 1), rough: 0.42, metal: 0.5), at: [-doorW / 2, 0, 0])
        hinge.addChild(panel); hinge.orientation = simd_quatf(angle: 1.15, axis: [0, 1, 0]); root.addChild(hinge)
        root.addChild(point(0xffb060, 60000, radius: 8, at: [0, 1.8, -1.0]))
        root.addChild(point(0xffc070, 20000, radius: 5, at: [0, 2.4, -1.6]))

        // the lights: a soft key, a fill, a wash on each wall, three downlights, and a key, fill and rim on the figure
        root.addChild(ThreeDModels.light(intensity: 900, at: [2, 6, 5], look: .zero))
        root.addChild(point(0xfff0d0, 30000, radius: 24, at: [0, 3.6, 3.8]))
        for wx: Float in [-4.4, 4.4] { root.addChild(point(0xffe9c0, 14000, radius: 13, at: [wx, 2.4, 3])) }
        for (sx, iz) in [(Float(-2.4), Float(0.5)), (2.4, 0.5), (0, 3)] { root.addChild(spot(0xfff4df, 40000, at: [sx, 4.3, iz], look: [sx, 0, iz - 0.5], angle: 26)) }
        root.addChild(spot(0xfff3df, 80000, at: [2.6, 3.4, 1.4], look: [0.95, 1.1, -0.2], angle: 20))
        root.addChild(point(0xbcd0ff, 12000, radius: 6, at: [-1.0, 1.8, 1.6]))
        root.addChild(spot(0xffe2a8, 60000, at: [-0.4, 2.6, -1.4], look: [0.95, 1.1, -0.2], angle: 18))

        // a soft pool of shadow under the figure
        if let cg = Self.shadowDisc(), let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            var m = UnlitMaterial(); m.color = .init(tint: .white, texture: .init(tex)); m.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            root.addChild(plane(2.2, 1.4, m, at: [0.95, 0.012, -0.2], rx: -.pi / 2))
        }

        // six niches on the side walls: a gold frame, paper, and a glyph of his, contain-fitted
        let paper = pbr(UIColor(red: 0xf4 / 255, green: 0xf1 / 255, blue: 0xea / 255, alpha: 1), rough: 0.95)
        let glyphs = ["glyph-guy", "money", "love-yourself", "smiley", "poverty-to-luxury"]
        var textures: [TextureResource?] = []
        for g in glyphs {
            if let u = URL(string: base + "/glyphs/\(g).png") { textures.append(await ThreeDPictures.texture(u)) } else { textures.append(nil) }
        }
        var gi = 0
        func niche(_ x: Float, _ z: Float, _ ry: Float) {
            let nW: Float = 0.92, nH: Float = 1.24
            let g = Entity(); g.position = [x, 1.65, z]; g.orientation = simd_quatf(angle: ry, axis: [0, 1, 0])
            g.addChild(plane(nW + 0.08, nH + 0.08, gold, at: .zero))
            g.addChild(plane(nW, nH, paper, at: [0, 0, 0.012]))
            if let t = textures[gi % textures.count] {
                let maxW = nW * 0.8, maxH = nH * 0.8
                let aspect = Float(t.width) / Float(max(1, t.height))
                var aw = maxW, ah = maxW / aspect
                if ah > maxH { ah = maxH; aw = maxH * aspect }
                var m = UnlitMaterial(); m.color = .init(tint: .white, texture: .init(t)); m.blending = .transparent(opacity: .init(floatLiteral: 1))
                g.addChild(plane(aw, ah, m, at: [0, 0, 0.02]))
            }
            gi += 1; root.addChild(g)
        }
        for nz: Float in [-0.4, 1.7, 3.8] { niche(-4.92, nz, .pi / 2); niche(4.92, nz, -.pi / 2) }

        // his gold GlyphGuy, standing where the page puts him, turned toward the door side
        let fig = GlyphFigure()
        if await fig.load(height: 1.9, look: .gold) {
            await fig.play(.idle)
            fig.root.position = [0.95, 0, -0.2]
            fig.root.orientation = simd_quatf(angle: -2.3, axis: [0, 1, 0])
            root.addChild(fig.root)
        }
        return root
    }

    /// The mark, tinted a flat colour (a template image drawn in that colour, transparent elsewhere).
    private static func tint(_ img: UIImage, _ color: UIColor) -> UIImage? {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            let r = CGRect(origin: .zero, size: size)
            img.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: r.insetBy(dx: 20, dy: 20))
        }
    }

    private static func shadowDisc() -> CGImage? {
        let n = 256
        return UIGraphicsImageRenderer(size: CGSize(width: n, height: n)).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.black.withAlphaComponent(0.62).cgColor, UIColor.black.withAlphaComponent(0.28).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.55, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 8, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }.cgImage
    }
}
