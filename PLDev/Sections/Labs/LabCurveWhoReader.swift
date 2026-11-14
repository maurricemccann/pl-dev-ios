import RealityKit
import SwiftUI

/// /curve-who: The Curve Who as a scroll-through claymation reader (gallery `app/curve-who/page.tsx`, WIP on the site too).
/// One clay being and the Curve, morphing through the book's arc as you scroll: Birth (yellow), the storm (red), the deep
/// (blue-purple), then the Signing, where the whole form dissolves and integrates down to the single gold-marked Totem.
/// Wordless, like the book. The same clay figure and 12-frames-a-second stop-motion cadence as the orbit study (`LabCurveWhoView`), but
/// the stage is fixed and the scroll position is the story. The page's stops, scales and chaos curve are copied one for one.
struct LabCurveWhoReaderView: View {
    /// Colour stops the book moves through: ground (paper behind), skin (the being), curve.
    private static let stops: [(at: Double, bg: UInt32, skin: UInt32, curve: UInt32)] = [
        (0.0, 0xeceef4, 0xe6c341, 0x94743a),   // Birth: yellow
        (0.4, 0xf1e2dc, 0xc23b2b, 0x7a2a1e),   // the storm: red
        (0.72, 0xdadbe8, 0x5b4a86, 0x3a2f57),  // the deep: blue-purple
        (1.0, 0xf4f2ee, 0x1a1512, 0xc9a84c),   // the Signing: integrated to the gold Totem
    ]

    enum Kind { case bg, skin, curve }

    @State private var progress = 0.0
    @State private var bg = Color(hex: 0xeceef4)
    @State private var chapter = "Birth"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            RealityView { content in
                let cam = ThreeDModels.camera(fov: 40)
                cam.position = [0, 0.8, 11.5]
                content.add(cam)
                content.add(ThreeDModels.light(intensity: 3600, at: [4, 6, 5], look: .zero))
                content.add(ThreeDModels.light(intensity: 900, at: [-5, 1, 3], look: .zero))
                content.add(ThreeDModels.light(intensity: 1400, at: [0, 3, -6], look: .zero))
                let rig = await Self.build { progress }
                content.add(rig)
            }
            .allowsHitTesting(false)
            // the runway: five screens, the four states and a beat to rest on the Totem
            ScrollView {
                Color.clear.frame(height: UIScreen.main.bounds.height * 5.2)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Double.self) { g in
                Double(g.contentOffset.y / max(1, g.contentSize.height - g.containerSize.height))
            } action: { _, v in
                progress = min(1, max(0, v))
                bg = Self.color(at: progress, Kind.bg)
                chapter = progress < 0.4 ? "Birth" : progress < 0.72 ? "The storm" : progress < 0.97 ? "The deep" : "The Signing"
            }
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    LabCaption(title: "The Curve Who", line: "claymation reader \u{00B7} scroll \u{2014} birth to the mark", tint: Color(red: 40 / 255, green: 32 / 255, blue: 20 / 255))
                    Spacer()
                    Text(chapter).font(.system(size: 13, design: .serif).italic()).foregroundStyle(Color(red: 40 / 255, green: 32 / 255, blue: 20 / 255).opacity(0.5)).padding(.trailing, 20).padding(.bottom, 30)
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Curve Who, a scroll reader. A clay figure changes colour from yellow to red to blue-purple, then dissolves into a single gold-marked Totem. Scroll to move through it.")
        .accessibilityValue("\(Int(progress * 100)) percent, \(chapter)")
    }

    // MARK: colour

    private static func pick(_ s: (at: Double, bg: UInt32, skin: UInt32, curve: UInt32), _ k: Kind) -> UInt32 { k == .bg ? s.bg : k == .skin ? s.skin : s.curve }

    private static func color(at p: Double, _ kind: Kind) -> Color {
        Color(uiColor: uiColor(at: p, kind))
    }

    private static func uiColor(at p: Double, _ kind: Kind) -> UIColor {
        var a = stops[0], b = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where p >= stops[i].at && p <= stops[i + 1].at { a = stops[i]; b = stops[i + 1]; break }
        let f = CGFloat(min(1, max(0, (p - a.at) / ((b.at - a.at) == 0 ? 1 : (b.at - a.at)))))
        func c(_ x: UInt32) -> (CGFloat, CGFloat, CGFloat) { (CGFloat((x >> 16) & 255) / 255, CGFloat((x >> 8) & 255) / 255, CGFloat(x & 255) / 255) }
        let (r1, g1, b1) = c(pick(a, kind)), (r2, g2, b2) = c(pick(b, kind))
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f, blue: b1 + (b2 - b1) * f, alpha: 1)
    }

    // MARK: the being

    @MainActor private static func build(progress: @escaping @MainActor () -> Double) async -> Entity {
        let bump = await LabCurveWhoView.dimples()
        func clay(_ ui: UIColor) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: ui)
            m.roughness = .init(floatLiteral: 0.95); m.metallic = .init(floatLiteral: 0)
            if let bump { m.normal = .init(texture: .init(bump)) }
            return m
        }
        func hex(_ rgb: UInt32) -> UIColor { UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1) }

        let rig = Entity(), being = Entity()
        rig.addChild(being)

        // the head: a squashed clay capsule, three parts that share the skin
        let skinParts: [ModelEntity] = [
            ModelEntity(mesh: .generateCylinder(height: 1.5, radius: 1.15)),
            { let s = ModelEntity(mesh: .generateSphere(radius: 1.15)); s.position.y = -0.75; return s }(),
            { let s = ModelEntity(mesh: .generateSphere(radius: 1.15)); s.position.y = 0.75; return s }(),
        ]
        let head = Entity()
        skinParts.forEach { $0.model?.materials = [clay(hex(0xe6c341))]; head.addChild($0) }
        head.scale = [1.05, 1.0, 0.9]
        being.addChild(head)

        // eyes and grin: they go when the being dissolves
        let face = Entity()
        let black = clay(hex(0x0d0b0a))
        for x: Float in [-0.52, 0.52] {
            let e = ModelEntity(mesh: .generateSphere(radius: 0.34), materials: [black])
            e.scale = [0.82, 1.15, 0.6]; e.position = [x, 0.55, 1.02]; face.addChild(e)
            let glint = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [UnlitMaterial(color: .white)])
            glint.position = [x - 0.08, 0.7, 1.28]; face.addChild(glint)
        }
        let grin: [SIMD3<Float>] = [[-0.75, -0.25, 1.0], [-0.35, -0.5, 1.15], [0.35, -0.5, 1.15], [0.75, -0.25, 1.0]]
        if let gm = LabTube.mesh(grin, radius: 0.11, samples: 24) { face.addChild(ModelEntity(mesh: gm, materials: [clay(hex(0x8a6a2e))])) }
        let teeth = clay(hex(0xf2ede0))
        for i in 0..<6 {
            let p = LabTube.point(grin, 0.12 + Float(i) / 5 * 0.76)
            let t = ModelEntity(mesh: .generateBox(width: 0.13, height: 0.16, depth: 0.06), materials: [teeth])
            t.position = [p.x, p.y + 0.12, p.z + 0.02]; face.addChild(t)
        }
        being.addChild(face)

        // the Totem: the destination, grows as the being integrates
        let totem = Entity(); totem.position = [0, -2.35, 0.7]; being.addChild(totem)
        totem.addChild(ModelEntity(mesh: .generateSphere(radius: 0.42), materials: [clay(hex(0x0d0b0a))]))
        let glyph: [SIMD3<Float>] = [[-0.12, 0.28, 0.34], [0.06, 0.05, 0.42], [-0.05, -0.15, 0.4], [0.12, -0.3, 0.3]]
        if let gl = LabTube.mesh(glyph, radius: 0.05, samples: 20, sides: 6) {
            totem.addChild(ModelEntity(mesh: gl, materials: [SimpleMaterial(color: ThreeDHouse.gold, roughness: 0.5, isMetallic: true)]))
        }

        // the Curve: seven noodles; chaos is the writhe, and it resolves to near-straight as the book integrates
        let noodles: [(ModelEntity, Float, Float)] = (0..<7).map { i in
            let e = ModelEntity(); being.addChild(e)
            return (e, Float(i) * 1.7, (Float(i) / 6 - 0.5) * 1.8)
        }
        func noodle(_ baseX: Float, _ seed: Float, _ tt: Float, _ chaos: Float) -> MeshResource? {
            var pts: [SIMD3<Float>] = []
            for k in 0..<7 {
                let u = Float(k) / 6
                let sway = sin(tt * 1.3 + seed + u * 3.2) * (0.35 + u * 0.7) * chaos
                let swayZ = cos(tt * 1.1 + seed * 1.4 + u * 2.6) * (0.25 + u * 0.6) * chaos
                pts.append([baseX * (1 - u * 0.3) + sway, 1.4 + u * 3.0 + sin(tt + seed) * 0.15 * chaos, swayZ])
            }
            return LabTube.mesh(pts, radius: 0.17)
        }

        let reduce = UIAccessibility.isReduceMotionEnabled
        Task { @MainActor in
            var poseT: Float = 0
            var lastP = -1.0
            while rig.parent != nil {
                let p = progress()
                if !reduce || abs(p - lastP) > 0.002 {   // reduced motion: the pose changes only when the scroll does
                    lastP = p
                    let skin = clay(uiColor(at: p, Kind.skin)), curve = clay(uiColor(at: p, Kind.curve))
                    skinParts.forEach { $0.model?.materials = [skin] }
                    let chaos = Float(max(0.04, 1 - p * 1.05))
                    for (e, seed, bx) in noodles { if let m = noodle(bx, seed, poseT, chaos) { e.model = ModelComponent(mesh: m, materials: [curve]) } }
                    // dissolution to integration: 0 until the deep, 1 at the Signing
                    let dissolve = Float(max(0, (p - 0.72) / 0.28))
                    being.scale = SIMD3<Float>(repeating: max(0.18, 1 - dissolve * 0.82))
                    head.isEnabled = dissolve < 0.96; face.isEnabled = dissolve < 0.96
                    totem.scale = SIMD3<Float>(repeating: 1 + dissolve * 2.4)
                    being.orientation = simd_quatf(angle: sin(poseT * 0.9) * 0.04 * (1 - dissolve), axis: [0, 0, 1])
                    totem.orientation = simd_quatf(angle: poseT * 0.6, axis: [0, 1, 0])
                    let j: Float = reduce ? 0 : 0.012
                    rig.position = [Float.random(in: -j...j) / 2, Float.random(in: -j...j) / 2 - dissolve * 1.2, 0]
                    rig.orientation = simd_quatf(angle: reduce ? 0 : Float.random(in: -0.003...0.003), axis: [0, 0, 1])
                }
                try? await Task.sleep(for: .milliseconds(83))   // stop motion: a new pose twelve times a second
                if !reduce { poseT += 1.0 / 12 }
            }
        }
        return rig
    }
}
