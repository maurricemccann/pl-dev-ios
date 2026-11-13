import RealityKit
import SwiftUI
import UIKit

// The 3D labs in RealityKit: the Heart (his model, breathing), the Wordmark (his hand in 3D), the Cards (GlyphGuy on his palettes,
// five real camera angles) and the Curve Who (a claymation study, all procedural, moved at 12 frames a second like stop motion).
// Sources: app/lab/heart, wordmark, nft-candidates, curve-who. His models are converted, never redrawn (lore: Not my model).

// MARK: - The Heart

struct LabHeartView: View {
    @State private var missing = false

    var body: some View {
        ZStack {
            Color(hex: 0x0e0c08).ignoresSafeArea()
            OrbitStage(distance: 3.4, height: 0.65, autoSpin: true) { pivot in
                // gold light from behind, the page's rim light
                let rim = Entity()
                rim.components.set(PointLightComponent(color: UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1), intensity: 40000, attenuationRadius: 25))
                rim.position = [0, 1.2, -4]
                pivot.addChild(rim)
                guard let url = Bundle.main.url(forResource: "heart1", withExtension: "usdz"), let e = try? await Entity(contentsOf: url) else { missing = true; return }
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: UIColor(red: 0.039, green: 0.031, blue: 0.024, alpha: 1))
                m.roughness = .init(floatLiteral: 0.12)
                m.metallic = .init(floatLiteral: 0.45)
                ThreeDModels.paint(e, m)
                let fit = ThreeDModels.fitted(e, longest: 1.3)
                pivot.addChild(fit)
                let base = fit.scale
                Task { @MainActor in   // a slow breath, 3 % on the fitted size
                    let t0 = Date()
                    while fit.parent != nil {
                        fit.scale = base * Float(1 + sin(Date().timeIntervalSince(t0) * 1.2) * 0.03)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }
            if missing { ContentUnavailableView("Model not found", systemImage: "heart", description: Text("The heart is not in this build.")).foregroundStyle(PLG.gold) }
            LabCaption(title: "The Heart", line: "gold · breathing · drag to orbit")
        }
        .accessibilityLabel("The Heart. A gold heart, breathing. Drag to orbit.")
    }
}

// MARK: - The Wordmark

struct LabWordmarkView: View {
    var body: some View {
        ZStack {
            Color(hex: 0x0e0c08).ignoresSafeArea()
            OrbitStage(distance: 3.0, height: 0, autoSpin: true) { pivot in
                let top = await panel("PSYCHED", y: 0.49)
                let bot = await panel("LUXURIES", y: -0.49)
                pivot.addChild(top); pivot.addChild(bot)
                let gold = UnlitMaterial(color: UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1))
                let line = ModelEntity(mesh: .generatePlane(width: 1.92, height: 0.004), materials: [gold])
                line.position = [0, 0, 0.005]
                pivot.addChild(line)
                Task { @MainActor in   // the planes breathe against each other
                    let t0 = Date()
                    while top.parent != nil {
                        let s = Float(sin(Date().timeIntervalSince(t0) * 0.5) * 0.012)
                        top.position.y = 0.49 + s; bot.position.y = -0.49 - s
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }
            LabCaption(title: "The Mark", line: "hand · gold · drag to orbit")
        }
        .accessibilityLabel("The Mark. PSYCHED over LUXURIES in his hand, in gold. Drag to orbit.")
    }

    /// The text drawn in his hand on a 1024 x 256 sheet: a gold glow under, the gold on top (the page's canvas texture).
    private func panel(_ text: String, y: Float) async -> ModelEntity {
        let size = CGSize(width: 1024, height: 256)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let font = UIFont(name: PLFace.handV1, size: 80) ?? UIFont.italicSystemFont(ofSize: 80)
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let box = CGRect(x: 0, y: (size.height - font.lineHeight) / 2, width: size.width, height: font.lineHeight)
            let glow = NSShadow(); glow.shadowColor = UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 0.6); glow.shadowBlurRadius = 24; glow.shadowOffset = .zero
            (text as NSString).draw(in: box, withAttributes: [.font: font, .foregroundColor: UIColor(red: 0.914, green: 0.863, blue: 0.627, alpha: 1), .paragraphStyle: para, .shadow: glow])
            (text as NSString).draw(in: box, withAttributes: [.font: font, .foregroundColor: UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1), .paragraphStyle: para])
        }
        var mat = PhysicallyBasedMaterial()
        if let cg = img.cgImage, let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            mat.baseColor = .init(texture: .init(tex))
            mat.emissiveColor = .init(color: UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1), texture: .init(tex))
            mat.emissiveIntensity = 0.15
        }
        mat.metallic = .init(floatLiteral: 0.6)
        mat.roughness = .init(floatLiteral: 0.3)
        mat.blending = .transparent(opacity: .init(floatLiteral: 1))
        let e = ModelEntity(mesh: .generatePlane(width: 3.3, height: 0.84), materials: [mat])
        e.position = [0, y, 0]
        return e
    }
}

// MARK: - The Cards: GlyphGuy on his palettes, five camera angles

struct LabCardsView: View {
    let model: AppModel
    private struct Card: Identifiable { let id: String; let label: String; let pose: GlyphCardPose }
    private let cards = [
        Card(id: "spiral", label: "01 — Gold", pose: .init(azimuth: -22, elevation: 4, yaw: 8, zoom: 1)),
        Card(id: "truchet", label: "02 — Oxblood", pose: .init(azimuth: 38, elevation: 9, yaw: -18, zoom: 1.12)),
        Card(id: "lattice", label: "03 — Obsidian", pose: .init(azimuth: 14, elevation: -12, yaw: 25, zoom: 0.94)),
        Card(id: "harmono", label: "04 — Bone", pose: .init(azimuth: -46, elevation: 18, yaw: -12, zoom: 1.05)),
        Card(id: "moire", label: "05 — Copper", pose: .init(azimuth: 58, elevation: 2, yaw: 40, zoom: 1.18)),
    ]
    @State private var only: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("NFT Candidates — GlyphGuy × the Curve Library").gTitle(22, relativeTo: .title2).foregroundStyle(Color(hex: 0xf0ece2)).multilineTextAlignment(.center)
                Text("First pass, not a generator — one fixed character, flat color + camera angle as the variation. Lab route, nothing minted, nothing final.")
                    .font(.footnote).foregroundStyle(Color(hex: 0xf0ece2).opacity(0.55)).multilineTextAlignment(.center)
                ForEach(only == nil ? cards : cards.filter { $0.id == only }) { c in
                    ZStack {
                        AsyncImage(url: URL(string: LibraryData.shared.base(model) + "/nft-candidates/\(c.id).png")) { $0.resizable().scaledToFill() } placeholder: { Color(hex: 0x1a1610) }
                        GlyphCardScene(pose: c.pose)
                    }
                    .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 4)).overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(PLG.gold.opacity(0.25), lineWidth: 1) }
                    .onTapGesture { withAnimation(.snappy) { only = only == c.id ? nil : c.id } }
                    .accessibilityLabel("GlyphGuy card \(c.label). Tap to show alone.")
                    .overlay(alignment: .bottomLeading) { Text(c.label).gEyebrow(9).foregroundStyle(.white.opacity(0.6)).padding(8).allowsHitTesting(false) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 80)
        }
        .background(Color(hex: 0x0e0c08))
    }
}

struct GlyphCardPose { let azimuth: Double, elevation: Double, yaw: Double, zoom: Double }

/// One card's GlyphGuy: marble, framed as a bust against a bounding sphere, breathing a little. Several run at once, as on the page.
struct GlyphCardScene: View {
    let pose: GlyphCardPose
    @State private var figure = GlyphFigure()

    var body: some View {
        RealityView { content in
            let key = ThreeDModels.light(intensity: 3400, at: [2.5, 4, 5], look: .zero)
            let fill = ThreeDModels.light(intensity: 1200, at: [-4, 1, 3], look: .zero)
            let rim = ThreeDModels.light(intensity: 1600, at: [-2, 4, -5], look: .zero)
            content.add(key); content.add(fill); content.add(rim)
            guard await figure.load(height: 1.8, look: .marble) else { return }
            await figure.play(.idle)
            content.add(figure.root)
            let b = figure.root.visualBounds(relativeTo: nil)
            let r = max(0.1, b.boundingRadius)
            figure.root.position -= b.center
            let target = SIMD3<Float>(0, r * 0.32, 0)
            let fov: Float = 33
            let dist = (r * 0.52 / sin(fov * .pi / 360)) * 1.15 / Float(pose.zoom)
            let az = Float(pose.azimuth * .pi / 180), el = Float(pose.elevation * .pi / 180)
            let cam = Entity()
            cam.components.set(PerspectiveCameraComponent(near: 0.05, far: 100, fieldOfViewInDegrees: fov))
            let from = SIMD3<Float>(target.x + dist * sin(az) * cos(el), target.y + dist * sin(el), target.z + dist * cos(az) * cos(el))
            cam.look(at: target, from: from, relativeTo: nil)
            content.add(cam)
            figure.root.orientation = simd_quatf(angle: Float(pose.yaw * .pi / 180), axis: [0, 1, 0])
            let baseY = figure.root.position.y
            let yaw = figure.root.orientation
            let bob = r * 0.012
            Task { @MainActor in
                let t0 = Date()
                while figure.root.parent != nil {
                    let t = Float(Date().timeIntervalSince(t0)), breath = sin(t * 1.1)
                    figure.root.position.y = baseY + breath * bob
                    figure.root.orientation = yaw * simd_quatf(angle: breath * 0.012, axis: [0, 0, 1])
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The Curve Who: clay, stepped to 12 frames a second

enum LabTube {
    private static func cr(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, _ u: Float) -> SIMD3<Float> {
        let u2 = u * u, u3 = u2 * u
        let a: SIMD3<Float> = 2 * p1
        let b: SIMD3<Float> = (p2 - p0) * u
        let c: SIMD3<Float> = (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2
        let d: SIMD3<Float> = (3 * p1 - p0 - 3 * p2 + p3) * u3
        return (a + b + c + d) * 0.5
    }

    /// The point a fraction of the way along a Catmull-Rom spline through `pts` (the page's getPoint).
    static func point(_ pts: [SIMD3<Float>], _ t: Float) -> SIMD3<Float> {
        let n = pts.count - 1
        let f = min(Float(n) - 0.0001, max(0, t * Float(n)))
        let i = Int(f), u = f - Float(i)
        return cr(pts[max(0, i - 1)], pts[i], pts[min(n, i + 1)], pts[min(n, i + 2)], u)
    }

    /// A tube along a Catmull-Rom spline through `pts`, with a parallel-transported frame so it does not twist.
    static func mesh(_ pts: [SIMD3<Float>], radius: Float, samples: Int = 32, sides: Int = 8) -> MeshResource? {
        guard pts.count >= 2 else { return nil }
        var centers: [SIMD3<Float>] = []
        for s in 0...samples { centers.append(point(pts, Float(s) / Float(samples))) }
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], idx: [UInt32] = []
        var prevN = SIMD3<Float>(0, 0, 1)
        for (s, c) in centers.enumerated() {
            let ahead = s < centers.count - 1 ? centers[s + 1] : c
            let behind = s > 0 ? centers[s - 1] : c
            let tan = simd_normalize(ahead - behind)
            var n = prevN - simd_dot(prevN, tan) * tan
            if simd_length(n) < 1e-4 { n = abs(tan.x) < 0.9 ? simd_cross(tan, SIMD3<Float>(1, 0, 0)) : simd_cross(tan, SIMD3<Float>(0, 1, 0)) }
            n = simd_normalize(n)
            prevN = n
            let b = simd_cross(tan, n)
            for k in 0...sides {
                let a = Float(k) / Float(sides) * 2 * .pi
                let dir = n * cos(a) + b * sin(a)
                positions.append(c + dir * radius); normals.append(dir)
                uvs.append(SIMD2<Float>(Float(s) / Float(samples) * 4, Float(k) / Float(sides) * 2))
            }
        }
        let ring = UInt32(sides + 1)
        for s in 0..<samples { for k in 0..<sides {
            let a = UInt32(s) * ring + UInt32(k), b = a + ring
            idx += [a, b, a + 1, a + 1, b, b + 1]
        } }
        var d = MeshDescriptor(name: "tube")
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}

struct LabCurveWhoView: View {
    var body: some View {
        ZStack {
            Color(hex: 0xeceef4).ignoresSafeArea()
            OrbitStage(distance: 10.8, height: 0.6, autoSpin: true) { pivot in
                let bump = await Self.dimples()
                func clay(_ rgb: UInt32) -> PhysicallyBasedMaterial {
                    var m = PhysicallyBasedMaterial()
                    m.baseColor = .init(tint: UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1))
                    m.roughness = .init(floatLiteral: 0.95); m.metallic = .init(floatLiteral: 0)
                    if let bump { m.normal = .init(texture: .init(bump)) }
                    return m
                }
                // warm studio: key, cool fill, rim
                pivot.addChild(ThreeDModels.light(intensity: 3600, at: [4, 6, 5], look: .zero))
                pivot.addChild(ThreeDModels.light(intensity: 900, at: [-5, 1, 3], look: .zero))
                pivot.addChild(ThreeDModels.light(intensity: 1400, at: [0, 3, -6], look: .zero))

                let rig = Entity(), being = Entity()
                rig.addChild(being); pivot.addChild(rig)

                // the head: a squashed clay capsule
                let yellow = clay(0xe6c341)
                let head = Entity()
                head.addChild(ModelEntity(mesh: .generateCylinder(height: 1.5, radius: 1.15), materials: [yellow]))
                for sy: Float in [-0.75, 0.75] { let s = ModelEntity(mesh: .generateSphere(radius: 1.15), materials: [yellow]); s.position.y = sy; head.addChild(s) }
                head.scale = [1.05, 1.0, 0.9]
                being.addChild(head)

                // eyes: black clay ovals with a white glint
                let black = clay(0x0d0b0a)
                for x: Float in [-0.52, 0.52] {
                    let e = ModelEntity(mesh: .generateSphere(radius: 0.34), materials: [black])
                    e.scale = [0.82, 1.15, 0.6]; e.position = [x, 0.55, 1.02]; being.addChild(e)
                    let glint = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [UnlitMaterial(color: .white)])
                    glint.position = [x - 0.08, 0.7, 1.28]; being.addChild(glint)
                }
                // grin and teeth
                let grin: [SIMD3<Float>] = [[-0.75, -0.25, 1.0], [-0.35, -0.5, 1.15], [0.35, -0.5, 1.15], [0.75, -0.25, 1.0]]
                if let gm = LabTube.mesh(grin, radius: 0.11, samples: 24) { being.addChild(ModelEntity(mesh: gm, materials: [clay(0x8a6a2e)])) }
                let teeth = clay(0xf2ede0)
                for i in 0..<6 {
                    let p = LabTube.point(grin, 0.12 + Float(i) / 5 * 0.76)
                    let t = ModelEntity(mesh: .generateBox(width: 0.13, height: 0.16, depth: 0.06), materials: [teeth])
                    t.position = [p.x, p.y + 0.12, p.z + 0.02]; being.addChild(t)
                }
                // the Totem orb at the base, with a gold curve-glyph
                let totem = Entity(); totem.position = [0, -2.35, 0.7]; being.addChild(totem)
                totem.addChild(ModelEntity(mesh: .generateSphere(radius: 0.42), materials: [clay(0x0d0b0a)]))
                let glyph: [SIMD3<Float>] = [[-0.12, 0.28, 0.34], [0.06, 0.05, 0.42], [-0.05, -0.15, 0.4], [0.12, -0.3, 0.3]]
                if let gl = LabTube.mesh(glyph, radius: 0.05, samples: 20, sides: 6) {
                    totem.addChild(ModelEntity(mesh: gl, materials: [SimpleMaterial(color: ThreeDHouse.gold, roughness: 0.5, isMetallic: true)]))
                }
                // the Curve: brown clay noodles writhing off the head
                let curveMat = clay(0x94743a)
                let noodles: [(ModelEntity, Float, Float)] = (0..<7).map { i in
                    let e = ModelEntity(); being.addChild(e)
                    return (e, Float(i) * 1.7, (Float(i) / 6 - 0.5) * 1.8)
                }
                func noodle(_ baseX: Float, _ seed: Float, _ tt: Float) -> MeshResource? {
                    var pts: [SIMD3<Float>] = []
                    for k in 0..<7 {
                        let u = Float(k) / 6
                        let sway = sin(tt * 1.3 + seed + u * 3.2) * (0.35 + u * 0.7), swayZ = cos(tt * 1.1 + seed * 1.4 + u * 2.6) * (0.25 + u * 0.6)
                        pts.append([baseX * (1 - u * 0.3) + sway, 1.4 + u * 3.0 + sin(tt + seed) * 0.15, swayZ])
                    }
                    return LabTube.mesh(pts, radius: 0.17)
                }
                // stop motion: hold each pose for 1/12 s, jitter the whole rig per step
                let reduce = UIAccessibility.isReduceMotionEnabled
                Task { @MainActor in
                    var poseT: Float = 0
                    while rig.parent != nil {
                        for (e, seed, bx) in noodles { if let m = noodle(bx, seed, poseT) { e.model = ModelComponent(mesh: m, materials: [curveMat]) } }
                        being.orientation = simd_quatf(angle: sin(poseT * 0.9) * 0.04, axis: [0, 0, 1])
                        being.position.y = sin(poseT * 1.4) * 0.06
                        let breath = 1 + sin(poseT * 1.4) * 0.015
                        head.scale = [1.05 * breath, breath, 0.9 * breath]
                        totem.orientation = simd_quatf(angle: poseT * 0.6, axis: [0, 1, 0])
                        rig.position = [Float.random(in: -0.006...0.006), Float.random(in: -0.006...0.006), 0]
                        rig.orientation = simd_quatf(angle: Float.random(in: -0.003...0.003), axis: [0, 0, 1])
                        if reduce { return }
                        try? await Task.sleep(for: .milliseconds(83))
                        poseT += 1.0 / 12
                    }
                }
            }
            LabCaption(title: "The Curve Who · Birth", line: "claymation study · stop-motion · drag to orbit", tint: Color(red: 40 / 255, green: 32 / 255, blue: 20 / 255))
        }
        .accessibilityLabel("The Curve Who at birth. A yellow clay figure with brown clay noodles for hair, moved in stop-motion. Drag to orbit.")
    }

    /// The clay's fingerprinted dimples as a normal map: 900 soft pits in a 256 px tile.
    static func dimples() async -> TextureResource? {
        let n = 256
        var h = [Float](repeating: 0.5, count: n * n)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<900 {
            let cx = Int.random(in: 0..<n, using: &rng), cy = Int.random(in: 0..<n, using: &rng), r = 2 + Int.random(in: 0..<7, using: &rng)
            let depth = Float.random(in: 0.35...0.7, using: &rng)
            for dy in -r...r { for dx in -r...r {
                let d = Float(dx * dx + dy * dy).squareRoot() / Float(r)
                if d <= 1 { let x = (cx + dx + n) % n, y = (cy + dy + n) % n; h[y * n + x] = min(h[y * n + x], 0.5 - (1 - d) * depth * 0.5) }
            } }
        }
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.genericRGBLinear)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { return nil }
        let px = raw.assumingMemoryBound(to: UInt8.self)
        for y in 0..<n { for x in 0..<n {
            let l = h[y * n + (x + n - 1) % n], r = h[y * n + (x + 1) % n], u = h[((y + n - 1) % n) * n + x], d = h[((y + 1) % n) * n + x]
            let v = simd_normalize(SIMD3<Float>((l - r) * 3, (u - d) * 3, 1))
            let o = (y * n + x) * 4
            px[o] = UInt8((v.x * 0.5 + 0.5) * 255); px[o + 1] = UInt8((v.y * 0.5 + 0.5) * 255); px[o + 2] = UInt8((v.z * 0.5 + 0.5) * 255); px[o + 3] = 255
        } }
        guard let cg = ctx.makeImage() else { return nil }
        return try? await TextureResource(image: cg, options: .init(semantic: .normal))
    }
}
