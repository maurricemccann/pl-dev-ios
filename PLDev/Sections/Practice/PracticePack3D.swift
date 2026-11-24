import CoreMotion
import RealityKit
import SwiftUI

// The pack in real 3D (his ruling 11-15, "Real 3D in the app"; his verdict on the 2D pack: "They didn't look real enough they didn't
// look like the reference"). RealityKit on a virtual camera: a gold foil pack with metallic light from a generated studio environment
// that shifts as the phone tilts; tap, the top strip tears off with sparks; the cards rise out of the pack, part, each spins with a
// real edge, squares up, and its glyph-field cover burns away in patches to the face of the card actually dealt (alpha cut by noise).
// Mechanic from his reference (a TCG pack app, and youtu.be/rldgvunw8fs), never its look: the cover is his glyph field.

@MainActor final class PackScene {
    let root = Entity()
    private let pack = Entity(), strip = Entity()
    private var cards: [(e: Entity, cover: ModelEntity, mat: PhysicallyBasedMaterial)] = []
    private let motion = CMMotionManager()
    private var start: Date?
    private(set) var finished = false
    var subscription: EventSubscription?
    var handedBack = false
    private let count: Int

    init(count: Int) { self.count = max(1, count) }

    var stops: [Double] { (0..<count).map { 4.4 + Double($0) * 1.3 } }
    var end: Double { (stops.last ?? 4.4) + 1.8 }

    func build(faces: [CGImage]) async {
        // light: a studio of soft panels painted into an equirectangular image, for the foil to reflect
        if let env = try? await EnvironmentResource(equirectangular: Self.studio()) {
            root.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.6))
        }
        let tile = Packs.tile?.cgImage
        var foil: TextureResource?
        if let tile { foil = try? await TextureResource(image: tile, options: .init(semantic: .color)) }

        var gold = PhysicallyBasedMaterial()
        gold.baseColor = .init(tint: UIColor(red: 0.95, green: 0.74, blue: 0.32, alpha: 1), texture: foil.map { .init($0) })
        gold.metallic = .init(floatLiteral: 0.9); gold.roughness = .init(floatLiteral: 0.26); gold.clearcoat = .init(floatLiteral: 1); gold.clearcoatRoughness = .init(floatLiteral: 0.08)
        var dark = gold; dark.baseColor = .init(tint: UIColor(red: 0.62, green: 0.45, blue: 0.16, alpha: 1)); dark.roughness = .init(floatLiteral: 0.4)

        pack.addChild(ModelEntity(mesh: .generateBox(width: 0.09, height: 0.13, depth: 0.012, cornerRadius: 0.004), materials: [gold]))
        let bottom = ModelEntity(mesh: .generateBox(width: 0.094, height: 0.008, depth: 0.014, cornerRadius: 0.002), materials: [dark])
        bottom.position.y = -0.065; pack.addChild(bottom)
        strip.components.set(ModelComponent(mesh: .generateBox(width: 0.094, height: 0.008, depth: 0.014, cornerRadius: 0.002), materials: [dark]))
        strip.position.y = 0.065; pack.addChild(strip)
        pack.position = [0, -0.02, 0]
        root.addChild(pack)

        // the cards, inside the pack until it tears
        for i in 0..<count {
            let card = Entity()
            let w: Float = 0.063, h: Float = 0.088, t: Float = 0.0012
            var edgeMat = gold; edgeMat.roughness = .init(floatLiteral: 0.2)
            card.addChild(ModelEntity(mesh: .generateBox(width: w, height: h, depth: t, cornerRadius: 0.003), materials: [edgeMat]))
            var faceMat = UnlitMaterial()
            if i < faces.count, let tex = try? await TextureResource(image: faces[i], options: .init(semantic: .color)) {
                faceMat.color = .init(tint: .white, texture: .init(tex))
            } else { faceMat.color = .init(tint: .black) }
            let face = ModelEntity(mesh: .generatePlane(width: w * 0.94, height: h * 0.94, cornerRadius: 0.0025), materials: [faceMat])
            face.position.z = t / 2 + 0.0002; card.addChild(face)
            // the cover over the face: his glyph field in gold foil, its alpha a noise field, cut away by a rising threshold (the burn)
            var cover = gold
            if let noisy = Self.burnTexture(tile: tile, seed: UInt64(i) &+ 7), let tex = try? await TextureResource(image: noisy, options: .init(semantic: .color)) {
                cover.baseColor = .init(tint: UIColor(red: 0.95, green: 0.74, blue: 0.32, alpha: 1), texture: .init(tex))
            }
            cover.opacityThreshold = 0
            let coverEntity = ModelEntity(mesh: .generatePlane(width: w * 0.96, height: h * 0.96, cornerRadius: 0.0025), materials: [cover])
            coverEntity.position.z = t / 2 + 0.0004; card.addChild(coverEntity)
            let back = ModelEntity(mesh: .generatePlane(width: w * 0.96, height: h * 0.96, cornerRadius: 0.0025), materials: [gold])
            back.position.z = -t / 2 - 0.0002; back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]); card.addChild(back)
            card.position = [0, -0.02, -0.001]; card.scale = .init(repeating: 0.9)
            card.components.set(OpacityComponent(opacity: 0))
            root.addChild(card)
            cards.append((card, coverEntity, cover))
        }
        if motion.isDeviceMotionAvailable { motion.deviceMotionUpdateInterval = 1 / 60; motion.startDeviceMotionUpdates() }
    }

    func open() { if start == nil { start = .now; spark(at: [0, 0.045, 0.01]) } }
    func stop() { motion.stopDeviceMotionUpdates() }

    private func spark(at p: SIMD3<Float>) {
        let e = Entity()
        var s = ParticleEmitterComponent.Presets.sparks
        s.mainEmitter.color = .constant(.single(UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1)))
        s.emitterShapeSize = [0.06, 0.004, 0.004]
        s.burstCount = 160; s.isEmitting = false
        e.components.set(s); e.position = p; root.addChild(e)
        e.components[ParticleEmitterComponent.self]?.burst()
    }

    private static func ease(_ x: Double) -> Float { let c = min(1, max(0, x)); return Float(c * c * (3 - 2 * c)) }

    /// One frame of the opening; called by the scene's update event.
    func update() {
        // the phone's tilt turns the whole scene a little, so the foil catches the light
        if let a = motion.deviceMotion?.attitude {
            root.orientation = simd_quatf(angle: Float(max(-0.35, min(0.35, a.roll))) * 0.6, axis: [0, 1, 0]) * simd_quatf(angle: Float(max(-0.35, min(0.35, a.pitch - 0.6))) * 0.4, axis: [1, 0, 0])
        }
        guard let start else {
            pack.orientation = simd_quatf(angle: Float(sin(Date().timeIntervalSince1970 * 0.8)) * 0.12, axis: [0, 1, 0])
            return
        }
        let t = Date().timeIntervalSince(start)
        // the tear: the strip flies up and right, turning, and fades
        let k = Self.ease(t / 0.7)
        strip.position = [0.03 * k, 0.065 + 0.06 * k, 0.01 * k]
        strip.orientation = simd_quatf(angle: -0.9 * k, axis: [0, 0, 1])
        strip.components.set(OpacityComponent(opacity: 1 - k))
        // the pack sinks and fades as the cards rise out of it
        let sink = Self.ease((t - 0.6) / 1.4)
        pack.position = [0, -0.02 - 0.08 * sink, 0]
        pack.components.set(OpacityComponent(opacity: 1 - Self.ease((t - 1.2) / 0.8)))
        for (i, c) in cards.enumerated() {
            let rise = Self.ease((t - 0.6) / 1.6)
            let n = Float(cards.count), x = cards.count > 1 ? (Float(i) - (n - 1) / 2) * 0.072 * Self.ease((t - 3.0) / 0.6) : 0
            c.e.position = [x, -0.02 + 0.03 * rise, 0.02 * rise]
            c.e.scale = .init(repeating: 0.9 + 0.25 * rise)
            c.e.components.set(OpacityComponent(opacity: Self.ease((t - 0.5) / 0.3)))
            // the spin: each card at its own speed, then it squares up face-front at its stop
            let stop = stops[i], speed = 5.2 + 1.2 * Double(i)
            let a0 = (stop - 2.2) * speed, target = (a0 / (2 * .pi)).rounded(.up) * 2 * .pi
            let angle = t < 2.2 ? 0 : (t < stop ? (t - 2.2) * speed : a0 + (target - a0) * Double(Self.ease((t - stop) / 0.5)))
            c.e.orientation = simd_quatf(angle: Float(angle), axis: [0, 1, 0])
            // the burn: the cover's threshold climbs, cutting its noise away in patches
            let burn = Self.ease((t - (stop + 0.6)) / 0.9)
            var m = c.mat; m.opacityThreshold = burn * 1.02
            c.cover.model?.materials = [m]
            if burn > 0 && burn < 0.05 { spark(at: c.e.position + [0, 0, 0.01]) }
        }
        if t >= end { finished = true }
    }

    /// The studio the foil reflects: dark night with two soft warm panels and a cool rim, painted as a 1024x512 equirectangular map.
    static func studio() -> CGImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.04, green: 0.04, blue: 0.09, alpha: 1).cgColor); c.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            for (rect, col) in [(CGRect(x: 380, y: 90, width: 260, height: 120), UIColor(white: 1, alpha: 1)),
                                (CGRect(x: 120, y: 160, width: 160, height: 220), UIColor(red: 1, green: 0.82, blue: 0.5, alpha: 1)),
                                (CGRect(x: 760, y: 140, width: 120, height: 260), UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1))] {
                c.setFillColor(col.cgColor); c.fillEllipse(in: rect)
            }
        }.cgImage!
    }

    /// His glyph field with an alpha made of smooth value noise, so a rising threshold eats it away in patches.
    static func burnTexture(tile: CGImage?, seed: UInt64) -> CGImage? {
        let W = 256, H = 360
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(UIColor(red: 0.9, green: 0.7, blue: 0.3, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        if let tile { ctx.draw(tile, in: CGRect(x: 0, y: 0, width: W, height: H)) }
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var g = seed &* 6364136223846793005 &+ 1442695040888963407
        func rnd() -> Double { g = g &* 6364136223846793005 &+ 1442695040888963407; return Double(g >> 33) / Double(1 << 31) }
        let gw = 9, gh = 12
        let grid = (0..<(gw * gh)).map { _ in rnd() }
        for y in 0..<H {
            for x in 0..<W {
                let fx = Double(x) / Double(W - 1) * Double(gw - 1), fy = Double(y) / Double(H - 1) * Double(gh - 1)
                let x0 = min(gw - 2, Int(fx)), y0 = min(gh - 2, Int(fy)), u = fx - Double(x0), v = fy - Double(y0)
                let su = u * u * (3 - 2 * u), sv = v * v * (3 - 2 * v)
                let a = grid[y0 * gw + x0], b = grid[y0 * gw + x0 + 1], c = grid[(y0 + 1) * gw + x0], d = grid[(y0 + 1) * gw + x0 + 1]
                let n = (a + (b - a) * su) * (1 - sv) + (c + (d - c) * su) * sv
                let alpha = UInt8(max(4, min(255, n * 255)))
                let i = (y * W + x) * 4
                // premultiplied: scale colour with the new alpha
                for k in 0..<3 { data[i + k] = UInt8(Int(data[i + k]) * Int(alpha) / 255) }
                data[i + 3] = alpha
            }
        }
        return ctx.makeImage()
    }
}

/// The 3D stage: tap the pack to open; when the last card is revealed, `done` hands back to the 2D row (face up, readable).
struct Pack3DStage: View {
    let model: AppModel
    let cards: [PackCard]
    let done: () -> Void
    @State private var scene: PackScene?
    @State private var tapped = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RealityView { content in
                content.camera = .virtual
                let s = PackScene(count: cards.count)
                let faces = await Self.faces(cards, model: model)
                await s.build(faces: faces)
                let cam = Entity()
                cam.components.set(PerspectiveCameraComponent(near: 0.01, far: 5, fieldOfViewInDegrees: 38))
                cam.look(at: [0, 0.01, 0], from: [0, 0.02, 0.36], relativeTo: nil)
                content.add(cam)
                content.add(s.root)
                s.subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                    MainActor.assumeIsolated {
                        s.update()
                        if s.finished && !s.handedBack { s.handedBack = true; s.stop(); done() }
                    }
                }
                scene = s
            }
            .contentShape(Rectangle())
            .onTapGesture { tapped = true; scene?.open() }
            if !tapped { Text("Tap to open").font(Font.pl(size: 13)).foregroundStyle(Candle.ink.opacity(0.7)).padding(.bottom, 12) }
        }
        .onDisappear { scene?.stop() }
        .accessibilityElement().accessibilityLabel("A pack. Tap to open.").accessibilityAddTraits(.isButton)
        .accessibilityAction { tapped = true; scene?.open() }
    }

    /// Each card's face as an image: his art's still for an art card, the game's name on black for a game card.
    static func faces(_ cards: [PackCard], model: AppModel) async -> [CGImage] {
        var out: [CGImage] = []
        for c in cards {
            if let p = c.piece, let u = await PracticeCards.still(for: p, model: model),
               let (d, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: d)?.cgImage {
                out.append(Self.fit(img)); continue
            }
            let name = (c.game ?? "").replacingOccurrences(of: "-", with: " ").capitalized
            let r = ImageRenderer(content: VStack(spacing: 10) {
                Text("Game unlocked").font(Font.pl(size: 22)).textCase(.uppercase).tracking(2).foregroundStyle(Candle.gold)
                Text(name).plHand(44, relativeTo: .title).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
            }.padding(24).frame(width: 504, height: 720).background(Color.black))
            r.scale = 1
            if let img = r.cgImage { out.append(img) }
        }
        return out
    }

    /// His art letterboxed into the card's 0.7 shape on black, so it is never stretched.
    static func fit(_ img: CGImage) -> CGImage {
        let W = 504, H = 720
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.setFillColor(UIColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let s = min(Double(W) / Double(img.width), Double(H) / Double(img.height))
        let w = Double(img.width) * s, h = Double(img.height) * s
        ctx.draw(img, in: CGRect(x: (Double(W) - w) / 2, y: (Double(H) - h) / 2, width: w, height: h))
        return ctx.makeImage() ?? img
    }
}
