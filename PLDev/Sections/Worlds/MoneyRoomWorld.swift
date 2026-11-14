import SwiftUI
import RealityKit

// The Money Room (its page calls it "The Take"), as `app/defiance/the-money-room/page.tsx` builds it: GlyphGuy in gold, dancing
// the samba, in flowing cash. A dressed bed of bills fills the floor and rolls as slow waves; real rigid-body bills and coins fall
// on a drifting wind, pile, and are shoved aside by a capsule riding the dancer. The camera circles slowly. No green fluid sheet,
// just bills. The bed here is built as merged chunks that ride the same swell (one mesh per 1.4 m square), because a thousand
// separate entities would not hold the frame rate; its coins are left to the falling layer.

@MainActor final class MoneyScene {
    @MainActor private final class Bill {
        let e: ModelEntity
        var age: Float
        var life: Float
        init(e: ModelEntity) { self.e = e; age = 0; life = 8 }
    }
    private struct Chunk { let e: Entity; let x: Float; let z: Float }

    private var bills: [Bill] = []
    private var chunks: [Chunk] = []
    private let figure = GlyphFigure()
    private let holder = Entity()
    private let glint = Entity()
    private var t: Float = 0
    private var wind: Float = 0
    private(set) var ready = false

    private static let pen: Float = 4.4          // containment radius: the bills stay in this bowl
    private static let baseTop: Float = 0.44     // top of the dressed bed (about knee deep)
    private static let bedBills = 1900           // what the page draws on a phone
    private static let fallingBills = 210        // what the page runs on a phone
    private static let fallingCoins = 14
    private static let green = UIColor.world(0x3f7a4d)

    private static func swell(_ x: Float, _ z: Float, _ t: Float) -> Float {
        0.05 * sin(0.55 * x + t * 0.9) + 0.045 * sin(0.48 * z - t * 0.7) + 0.035 * sin(0.32 * (x + z) + t * 1.25)
    }
    private static func bedHeight(_ r: Float) -> Float { 0.04 + (baseTop - 0.04) * pow(max(0, 1 - r / (pen + 1)), 1.1) }
    private static func randomQuat() -> simd_quatf {
        var v = SIMD4<Float>(Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5))
        let m = max(0.0001, simd_length(v)); v /= m
        return simd_quatf(ix: v.x, iy: v.y, iz: v.z, r: v.w)
    }

    func build(engine: WorldEngine) async {
        let root = Entity(); engine.add(root)
        let gold = UIColor.world(0xc9a84c), darkGold = UIColor.world(0x8a6a22)

        // lights: a key from above, gold fill, a dark-gold rim, a glint that wanders, and two on the dancer
        root.addChild(WorldLight.directional(300, from: [0, 9, 3], color: gold.worldDim(0.8)))
        root.addChild(WorldLight.spot(420_000, radius: 28, from: [0, 10, 4], look: [0, 0, 0], inner: 24, outer: 42, color: UIColor.world(0xfff4d6)))
        root.addChild(WorldLight.point(70_000, radius: 18, at: [-4, 2.6, 3], color: gold))
        root.addChild(WorldLight.point(45_000, radius: 14, at: [4, 3.2, -3], color: darkGold))
        var glintLight = PointLightComponent()
        glintLight.intensity = 90_000; glintLight.color = UIColor.world(0xffe9b0); glintLight.attenuationRadius = 11
        glint.components.set(glintLight)
        glint.position = [0, 1.6, 0]; root.addChild(glint)
        root.addChild(WorldLight.spot(320_000, radius: 18, from: [1.5, 5.5, 4], look: [0, 1, 0], inner: 20, outer: 36, color: UIColor.world(0xfff6e0)))
        root.addChild(WorldLight.point(50_000, radius: 7, at: [-1.6, 2.6, -1.4], color: UIColor.world(0xffe7a8)))

        // the floor
        let floor = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: Self.pen + 2.5),
                                materials: [SimpleMaterial(color: UIColor.world(0x0a0806), roughness: 0.95, isMetallic: false)])
        floor.position.y = -0.01
        root.addChild(floor)

        // physics: ground at the top of the bed so falling cash settles on the piles, and four invisible walls
        let groundShape = ShapeResource.generateBox(size: [Self.pen * 2 + 3, 0.2, Self.pen * 2 + 3])
        let ground = Entity(); ground.position = [0, Self.baseTop - 0.1, 0]
        ground.components.set(CollisionComponent(shapes: [groundShape]))
        ground.components.set(PhysicsBodyComponent(shapes: [groundShape], mass: 1, mode: .static))
        root.addChild(ground)
        for k in 0..<4 {
            let ang = Float(k) / 4 * .pi * 2
            let s = ShapeResource.generateBox(size: [0.4, 3.2, Self.pen * 2 + 0.8])
            let w = Entity(); w.position = [cos(ang) * Self.pen, 1.4, sin(ang) * Self.pen]
            w.orientation = simd_quatf(angle: -ang, axis: [0, 1, 0])
            w.components.set(CollisionComponent(shapes: [s]))
            w.components.set(PhysicsBodyComponent(shapes: [s], mass: 1, mode: .static))
            root.addChild(w)
        }

        await buildBed(into: root)
        buildFalling(into: root)

        // GlyphGuy v4 in gold, samba, with the capsule that shoves the cash
        if await figure.load(height: 1.8, look: .gold) {
            holder.addChild(figure.root)
            let cap = ShapeResource.generateCapsule(height: 1.94, radius: 0.42).offsetBy(translation: [0, 0.9, 0])
            holder.components.set(CollisionComponent(shapes: [cap]))
            holder.components.set(PhysicsBodyComponent(shapes: [cap], mass: 50, mode: .kinematic))
            root.addChild(holder)
            await figure.play(.samba)
        }
        ready = true
    }

    /// The dressed bed: bills lying at random angles, merged into one mesh per 1.4 m square so the whole bed can roll.
    private func buildBed(into root: Entity) async {
        let cell: Float = 1.4, origin: Float = -6
        var cells: [Int: [(SIMD3<Float>, simd_quatf)]] = [:]
        for _ in 0..<Self.bedBills {
            let r = (Self.pen + 1) * sqrt(Float.random(in: 0...1)), a = Float.random(in: 0..<(.pi * 2))
            let x = cos(a) * r, z = sin(a) * r
            let y = Float.random(in: 0...1) * Self.bedHeight(r) + 0.01
            let q = simd_quatf(angle: Float.random(in: 0..<(.pi * 2)), axis: [0, 1, 0])
                * simd_quatf(angle: Float.random(in: -0.45...0.45), axis: [1, 0, 0])
                * simd_quatf(angle: Float.random(in: -0.45...0.45), axis: [0, 0, 1])
            let ix = Int(floor((x - origin) / cell)), iz = Int(floor((z - origin) / cell))
            cells[ix * 100 + iz, default: []].append(([x, y, z], q))
        }
        let mat = SimpleMaterial(color: Self.green, roughness: 0.66, isMetallic: false)
        let hx: Float = 0.1, hz: Float = 0.045
        let corners: [SIMD3<Float>] = [[-hx, 0, -hz], [hx, 0, -hz], [hx, 0, hz], [-hx, 0, hz]]
        for (key, list) in cells {
            let ix = key / 100, iz = key % 100
            let cx = origin + (Float(ix) + 0.5) * cell, cz = origin + (Float(iz) + 0.5) * cell
            var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], idx: [UInt32] = []
            for (p, q) in list {
                let n = q.act([0, 1, 0])
                let base = UInt32(pos.count)
                for c in corners { pos.append(q.act(c) + p - [cx, 0, cz]); nor.append(n) }       // top
                for c in corners { pos.append(q.act(c) + p - [cx, 0, cz]); nor.append(-n) }      // underside
                idx += [base, base + 3, base + 2, base, base + 2, base + 1]
                idx += [base + 4, base + 5, base + 6, base + 4, base + 6, base + 7]
            }
            var d = MeshDescriptor(name: "bed")
            d.positions = MeshBuffers.Positions(pos)
            d.normals = MeshBuffers.Normals(nor)
            d.primitives = .triangles(idx)
            guard let mesh = try? await MeshResource.generate(from: [d]) else { continue }
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.position = [cx, Self.swell(cx, cz, 0), cz]
            root.addChild(e)
            chunks.append(Chunk(e: e, x: cx, z: cz))
        }
    }

    /// The flowing cash: real rigid bodies that fall on the wind, pile on the bed, and are recycled from the top.
    private func buildFalling(into root: Entity) {
        let billMesh = MeshResource.generateBox(size: [0.2, 0.008, 0.09])
        let coinMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.075)
        let billMat = SimpleMaterial(color: Self.green, roughness: 0.66, isMetallic: false)
        let coinMat = SimpleMaterial(color: UIColor.world(0xc9a84c), roughness: 0.24, isMetallic: true)
        let billShape = ShapeResource.generateBox(size: [0.14, 0.024, 0.10])
        let coinShape = ShapeResource.generateBox(size: [0.15, 0.022, 0.15])
        let friction = PhysicsMaterialResource.generate(friction: 0.7, restitution: 0.02)
        for i in 0..<(Self.fallingBills + Self.fallingCoins) {
            let coin = i >= Self.fallingBills
            let e = ModelEntity(mesh: coin ? coinMesh : billMesh, materials: [coin ? coinMat : billMat])
            let shape = coin ? coinShape : billShape
            e.components.set(CollisionComponent(shapes: [shape]))
            var body = PhysicsBodyComponent(shapes: [shape], mass: 0.03, material: friction, mode: .dynamic)
            body.linearDamping = 0.6; body.angularDamping = 0.85
            body.isContinuousCollisionDetectionEnabled = true
            e.components.set(body)
            root.addChild(e)
            let b = Bill(e: e)
            launch(b)
            b.age = Float.random(in: 0...b.life)      // staggered, so the cash is already falling
            bills.append(b)
        }
    }

    private func launch(_ b: Bill) {
        let r = Self.pen * 0.9 * sqrt(Float.random(in: 0...1)), a = Float.random(in: 0..<(.pi * 2))
        b.e.position = [cos(a) * r, Self.baseTop + 1.6 + Float.random(in: 0...3.2), sin(a) * r]
        b.e.orientation = Self.randomQuat()
        b.e.components.set(PhysicsMotionComponent(
            linearVelocity: [cos(wind) * 1.4, -0.5, sin(wind) * 1.4],
            angularVelocity: [Float.random(in: -3...3), Float.random(in: -3...3), Float.random(in: -3...3)]))
        b.age = 0; b.life = Float.random(in: 5...11)
    }

    func step(_ dt: Float, engine: WorldEngine, motion: Bool) {
        t += dt
        figure.tick(dt)
        let sway: SIMD3<Float> = motion ? [sin(t * 1.6) * 0.18, 0, cos(t * 1.1) * 0.12] : .zero
        holder.position = sway
        if motion { for c in chunks { c.e.position.y = Self.swell(c.x, c.z, t) } }

        wind += dt * 0.25                              // the flow direction drifts
        for b in bills {
            b.age += dt
            let p = b.e.position
            if b.age > b.life || p.y < -2 || hypot(p.x, p.z) > Self.pen + 1.2 { launch(b) }
        }
        glint.position = [sin(t * 0.5) * 3, 1.7, cos(t * 0.5) * 3]

        // the camera circles; on a tall phone it pulls back, as the page's own framing does
        let aspect = max(0.3, engine.aspect)
        let pull: Float = aspect < 1 ? (1 / aspect - 1) * 2.6 : 0
        let radius = 5.4 + pull, camY = 2.2 + pull * 0.35
        let o: Float = motion ? t : 0
        let pos: SIMD3<Float> = [sin(o * 0.15) * radius, camY + sin(o * 0.07) * 0.3, cos(o * 0.15) * radius + 0.6]
        engine.camera.look(at: [0, 1.05, 0], from: pos, relativeTo: nil)
    }
}

struct MoneyRoomWorld: View {
    @State private var engine = WorldEngine(fov: 42, far: 200)
    @State private var scene = MoneyScene()
    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WorldView(engine: engine, background: ThreeDHouse.ground) { eng in
                await scene.build(engine: eng)
                ready = true
            }
            .ignoresSafeArea()
            if !ready { PLLoader().tint(PLG.gold) }
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Take").font(.system(.title, design: .serif).italic()).foregroundStyle(PLG.gold.opacity(0.8))
                        Text("gold body \u{00B7} flowing cash").font(.system(size: 10)).tracking(2.2).textCase(.uppercase).foregroundStyle(PLG.gold.opacity(0.38))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 28)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
        .background(Color(uiColor: ThreeDHouse.ground))
        .navigationTitle("The Money Room").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            let scene = scene, engine = engine, motion = !reduceMotion
            engine.onFrame = { dt in scene.step(dt, engine: engine, motion: motion) }
        }
    }
}
