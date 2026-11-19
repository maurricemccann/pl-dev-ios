import RealityKit
import UIKit
import simd

/// Page 1, THE BIRTH (yellow). A closed limestone cavern 48 m across, 34 m high: a 10 m carved statue of the Curve Who on a three-tier plinth,
/// eleven gold buttresses arcing from its hollow head, the well in front, one honey shaft through the oculus. The gift: hold still (or hold ACT)
/// at the well and the dream rises into his hands. Numbers are the web build's (`room1.js`); local frame, metres, -Z forward.
/// Unproven (nothing here runs on a Mac or device yet): light intensities, UV orientation of the face decal, collision feel. All tunables are in `Tune`.
@MainActor final class PLWRoomP1: PLWRoom {
    enum Tune {
        static let caveR: Float = 24, caveH: Float = 34, tunnelR: Float = 6, tunnelLen: Float = 8
        static let statueZ: Float = -2, wellZ: Float = 8, wellRadius: Float = 3.6, holdSeconds: Float = 2.5
        static let shaftLumens: Float = 250_000, fillLumens: Float = 18_000, wellLumens: Float = 9_000
    }

    let id: PLWArea = .p1
    let root = Entity()
    private(set) var ports: [String: Transform] = [:]
    private(set) var route: [SIMD3<Float>] = []
    private(set) var triggers: [PLWTrigger] = []
    private(set) var glyphs: [PLWGlyphPlacement] = []

    private let mats = P1Materials()
    private let orb = Entity(), halo = Entity(), dust = Entity()
    private var keyEntities: [UInt8: Entity] = [:]
    private var lights: [(e: Entity, color: SIMD3<Float>, lumens: Float)] = []
    private var held: Float = 0, gift = Gift.waiting, flyT: Float = 0, elapsed: Float = 0, lastRise: Float = -1
    private var said: Set<String> = [], taken: Set<UInt8> = []
    private enum Gift { case waiting, flying, done }
    private var saved = PLWSave()   // restore may arrive before or after load

    init() {
        let w = Tune.wellZ
        ports = [
            "start": Transform(translation: [0, 0, 16]),
            "well": Transform(translation: [0, 0, w + 3]),
            "exit": Transform(translation: [0, 0, -(Tune.caveR + Tune.tunnelLen)]),                              // south tunnel end, faces -Z (out)
            "entry": Transform(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]), translation: [0, 0, Tune.caveR + Tune.tunnelLen]),   // north tunnel end, faces +Z (out)
        ]
        route = [[0, 0, 16], [0, 0, 11], [6, 0, 9], [9.5, 0, 2], [9.5, 0, -8], [4, 0, -16], [0, 0, -24], [0, 0, -(Tune.caveR + Tune.tunnelLen)]]
        let ramp = Self.rampPoint(0.97)
        glyphs = [
            PLWGlyphPlacement(key: PLWKey(page: .p1, slot: 0), glyph: .glyphGuy, position: [-8.3, 1.3, -5.5]),
            PLWGlyphPlacement(key: PLWKey(page: .p1, slot: 1), glyph: .loveYourself, position: [8.3, 1.3, -5.5]),
            PLWGlyphPlacement(key: PLWKey(page: .p1, slot: 2), glyph: .money, position: [ramp.x, ramp.y + 1.3, ramp.z]),
        ]
        triggers = [PLWTrigger(id: "p1.well", center: [0, 1, w], yaw: 0, halfExtents: [Tune.wellRadius, 2, Tune.wellRadius])]
            + glyphs.map { PLWTrigger(id: "p1.key\($0.key.slot)", center: $0.position, yaw: 0, halfExtents: [1.4, 1.6, 1.4]) }
    }

    // MARK: the west ramp (his curve shelves, made one walkable sweep: the controller has no mantle) up to a viewing balcony that faces the statue

    private static let rampR: Float = 19.5, rampW: Float = 3.6, rampTop: Float = 6, rampA0: Float = -0.7, rampA1: Float = -2.45, balconyA1: Float = -3.0
    static func rampPoint(_ u: Float) -> SIMD3<Float> {   // u 0...1 along the whole sweep including the balcony
        let a = rampA0 + (balconyA1 - rampA0) * u, climb = min(1, u / 0.78)
        return [sin(a) * rampR, rampTop * climb * climb * (3 - 2 * climb), cos(a) * rampR]
    }

    // MARK: load

    func load() async throws {
        try await mats.load()
        let T = Tune.self, zS = T.statueZ
        root.name = "plw-p1"

        func add(_ mesh: P1Mesh, _ m: any Material, shape: ShapeResource? = nil, name: String) throws {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing(name) }
            let e = ModelEntity(mesh: r, materials: [m]); e.name = name
            if let shape {
                e.components.set(CollisionComponent(shapes: [shape]))
                e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
            }
            root.addChild(e)
        }
        func staticShape(_ mesh: P1Mesh) async throws -> ShapeResource {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing("shape") }
            return try await ShapeResource.generateStaticMesh(from: r)
        }

        // the cavern: a dome with the tunnel mouths and the oculus cut as real holes; the rock bulges and folds above the true lower wall
        var cave = P1Mesh()
        let na = 200, ne = 70
        let ph: [Float] = [0.7, 2.1, 3.4, 4.9, 1.3, 5.6]
        func sm(_ a: Float, _ b: Float, _ x: Float) -> Float { let k = min(max((x - a) / (b - a), 0), 1); return k * k * (3 - 2 * k) }
        func rockPoint(_ j: Int, _ i: Int) -> (SIMD3<Float>, Float, Float) {
            let e = Float(j) / Float(ne) * .pi / 2, a = Float(i) / Float(na) * 2 * .pi, y = sin(e) * T.caveH
            let n = sin(a * 7 + ph[0]) * sin(e * 9 + ph[1]) * 1.3 + sin(a * 17 + ph[2]) * sin(e * 21 + ph[3]) * 0.5 + sin(a * 41 + ph[4]) * 0.18
            let k = 1 + n * sm(4, 10, y) / T.caveR
            return ([sin(a) * cos(e) * T.caveR * k, y, cos(a) * cos(e) * T.caveR * k], a, e)
        }
        cave.grid(ne, na, facing: { _, _, c in SIMD3<Float>(0, 5, 0) - c }, skip: { j, i in
            let e = (Float(j) + 0.5) / Float(ne) * .pi / 2, a = (Float(i) + 0.5) / Float(na) * 2 * .pi
            let cx = sin(a) * cos(e) * T.caveR, cz = cos(a) * cos(e) * T.caveR, cy = sin(e) * T.caveH
            if abs(cz) > T.caveR * 0.6 && cx * cx + cy * cy < T.tunnelR * T.tunnelR { return true }   // both tunnel mouths
            return cos(e) * T.caveR < 1.6                                                                // the oculus
        }) { j, i in
            let (q, a, e) = rockPoint(j, i), reps = max(1, (2 * Float.pi * T.caveR * cos(e) / 5).rounded())
            return (q, [a / (2 * .pi) * reps, e * T.caveH / 5])   // about 5 m a repeat
        }
        try add(cave, mats.rock, shape: try await staticShape(cave), name: "cavern")

        // floor (his flagstones, PL-0004 engraved) and the two tunnel stubs (orange; the layout lane continues them)
        try add(.box([52, 0.5, 52], at: [0, -0.25, 0], metres: 4), mats.floor, shape: .generateBox(size: [52, 0.5, 52]).offsetBy(translation: [0, -0.25, 0]), name: "floor")
        for s: Float in [-1, 1] {
            let z0 = s * (T.caveR - 0.5), z1 = s * (T.caveR + T.tunnelLen)
            var tube = P1Mesh()
            tube.grid(8, 40, facing: { _, _, c in SIMD3<Float>(0, 0, c.z) - c }) { j, i in
                let a = Float(i) / 40 * 2 * .pi
                return ([sin(a) * T.tunnelR, cos(a) * T.tunnelR, z0 + (z1 - z0) * Float(j) / 8], [Float(i) / 40 * 2 * .pi * T.tunnelR / 4, Float(j) / 8 * T.tunnelLen / 4])
            }
            try add(tube, mats.tunnel, shape: try await staticShape(tube), name: s < 0 ? "tunnelExit" : "tunnelEntry")
            // the stub floor starts where the 52 m room floor ends (26 m), not inside it: the old 2.5 m overlap was a second pair of same-height faces
            let len = T.caveR + T.tunnelLen - 26, sz: Float = s * (26 + len / 2)
            try add(.box([T.tunnelR * 2, 0.5, len], at: [0, -0.25, sz], metres: 4), mats.floor, shape: .generateBox(size: [T.tunnelR * 2, 0.5, len]).offsetBy(translation: [0, -0.25, sz]), name: "tunnelFloor")
        }

        // the statue: three plinth tiers (cream, his tile, cream) with gold trim, a yellow-marble barrel with a rolled rim and a hollow head
        let tiers: [(w: Float, d: Float, h: Float, y: Float)] = [(13, 10, 0.8, 0), (11.4, 8.6, 1.0, 0.8), (9.6, 7.4, 1.2, 1.8)]
        var trim = P1Mesh()
        for (k, t) in tiers.enumerated() {
            let size: SIMD3<Float> = [t.w, t.h, t.d], c: SIMD3<Float> = [0, t.y + t.h / 2, zS]
            try add(.box(size, at: c, metres: 2.4), k == 1 ? mats.tier : mats.cream, shape: .generateBox(size: size).offsetBy(translation: c), name: "tier\(k)")
            trim.merge(.box([t.w + 0.12, 0.12, t.d + 0.12], at: [0, t.y + t.h - 0.02, zS]))
        }
        let pb: Float = 3.0, r0: Float = 3.0
        let prof: [SIMD2<Float>] = [[r0, 0], [r0 + 0.25, 1.4], [r0 + 0.32, 3.3], [r0 + 0.22, 5.4], [r0 + 0.08, 6.5], [r0 + 0.36, 6.62], [r0 + 0.4, 6.82], [r0 + 0.3, 7.0],
                                    [r0 - 0.35, 7.0], [r0 - 0.45, 6.7], [r0 - 0.5, 4.4], [0.01, 4.4]]
        let barrel = P1Mesh.lathe(prof, segments: 96, at: [0, pb, zS], metres: 3)
        var barrelMat = mats.yellow; barrelMat.faceCulling = .back
        guard let barrelRes = barrel.resource() else { throw P1Materials.Failure.missing("barrel") }
        try add(barrel, barrelMat, shape: try await ShapeResource.generateConvex(from: barrelRes), name: "barrel")

        // his drawn face, carved into the barrel: a curved patch hugging the profile, grooves a shade darker, lit lower lip, teeth proud
        func barrelRadius(_ y: Float) -> Float {
            for k in 0..<4 where y <= prof[k + 1].y { let t = (y - prof[k].y) / (prof[k + 1].y - prof[k].y); return prof[k].x + (prof[k + 1].x - prof[k].x) * t }
            return prof[4].x
        }
        var faceMesh = P1Mesh()
        let half: Float = 0.62, y0: Float = 1.4, y1: Float = 6.0
        faceMesh.grid(24, 24, facing: { _, _, c in SIMD3<Float>(c.x, 0, c.z - zS) }) { j, i in
            let t = Float(j) / 24, y = y0 + (y1 - y0) * t, a = (Float(i) / 24 * 2 - 1) * half, r = barrelRadius(y) + 0.02
            return ([sin(a) * r, pb + y, zS + cos(a) * r], [Float(i) / 24, t])
        }
        try add(faceMesh, mats.face, name: "face")
        try add(trim, mats.polished, name: "trim")

        // the gold buttresses: roots in the hollow head, rising, then arcing out and down into stone sockets round the floor (the south stays clear)
        let hy = pb + 7.0, span: Float = 10.5
        var bands = P1Mesh(), sockets = P1Mesh()
        var seed: UInt32 = 41
        func rnd() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed >> 8) / Float(1 << 24) }
        for i in 0..<12 {
            let a = (Float(i) + 0.5) / 12 * 2 * .pi
            if abs(atan2(sin(a - .pi), cos(a - .pi))) < 0.32 { continue }
            let sx = sin(a), cz = cos(a), rr = rnd() * 1.6, x0 = sx * rr, z0 = cos(a) * rr + zS
            let ctrl: [(Float, Float)] = [(0, hy - 2.2), (0.04, hy + 0.4), (0.16, hy + 4.5), (0.42, T.caveH * 0.6), (0.7, T.caveH * 0.38), (0.88, T.caveH * 0.14), (0.94, 0.5)]
            let pts: [SIMD3<Float>] = ctrl.map { u, y in
                let jitter = (u > 0.1 && u < 0.9) ? (rnd() - 0.5) * 1.2 : 0
                return [x0 * (1 - u) + sx * span * u / 0.94, y + jitter, z0 * (1 - u) + (zS + cz * span) * u / 0.94 - zS * u]
            }
            let path = P1Mesh.spline(pts, per: 18), n = path.count, base = 0.42 + rnd() * 0.12
            let side: SIMD3<Float> = [cos(a), 0, -sin(a)]
            bands.merge(.sweep(path, section: P1Mesh.slab, scale: { k in
                let w = (0.5 + 0.5 * sin(.pi * Float(k) / Float(n - 1))) * 0.5 + 0.12   // swells in the middle, ends flat
                return [w, base * 0.45]
            }, side: side, metres: 3))
            let foot = path[n - 1]
            sockets.merge(.lathe([[1.5, 0], [1.2, 0.9], [0.9, 0.9], [0.01, 0.9]], segments: 32, at: [foot.x, 0, foot.z], metres: 2))
            sockets.merge(.sweep((0...40).map { k in let t = Float(k) / 40 * 2 * .pi; return [foot.x + sin(t) * 1.05, 0.93, foot.z + cos(t) * 1.05] }, section: P1Mesh.circle(8), scale: { _ in [0.11, 0.11] }, metres: 1))
        }
        try add(bands, mats.polished, name: "buttresses")
        guard let sockRes = sockets.resource() else { throw P1Materials.Failure.missing("sockets") }
        try add(sockets, mats.cream, shape: try await ShapeResource.generateConvex(from: sockRes), name: "sockets")

        // gold inlaid into the floor, round the well and sweeping out (the reference painting)
        var inlay = P1Mesh()
        for (rr, w) in [(2.3, 0.14), (3.4, 0.14), (5.2, 0.09)] as [(Float, Float)] {
            inlay.merge(.sweep((0...96).map { k in let t = Float(k) / 96 * 2 * .pi; return [sin(t) * rr, 0.015, T.wellZ + cos(t) * rr] }, section: P1Mesh.slab, scale: { _ in [w / 2, 0.015] }, metres: 1))
        }
        for i in 0..<9 {
            let a0 = Float(i) / 9 * 2 * .pi + Float(i % 3) * 0.1
            let pts: [SIMD3<Float>] = (0...60).map { k in
                let u = Float(k) / 60, r3 = 5.4 + u * (T.caveR - 7), a = a0 + sin(u * 3.2 + Float(i)) * 0.35 * u
                return [sin(a) * r3, 0.015, T.wellZ * (1 - u) + cos(a) * r3]
            }
            inlay.merge(.sweep(pts, section: P1Mesh.slab, scale: { _ in [0.04 + 0.03 * abs(sin(Float(i))), 0.015] }, metres: 1))
        }
        try add(inlay, mats.polished, name: "inlay")

        // the well: the human-scale anchor
        let wc: SIMD3<Float> = [0, 0, T.wellZ]
        let wellRing = P1Mesh.lathe([[1.45, 0], [1.35, 1.2], [1.2, 1.2], [1.3, 0.0]], segments: 64, at: wc, metres: 2)
        guard let wellRes = wellRing.resource() else { throw P1Materials.Failure.missing("well") }
        try add(wellRing, mats.cream, shape: try await ShapeResource.generateConvex(from: wellRes), name: "well")
        try add(.sweep((0...64).map { k in let t = Float(k) / 64 * 2 * .pi; return [sin(t) * 1.375, 1.2, T.wellZ + cos(t) * 1.375] }, section: P1Mesh.circle(10), scale: { _ in [0.13, 0.13] }, metres: 1), mats.polished, name: "wellRim")
        try add(.lathe([[1.3, 0.85], [0.01, 0.85]], segments: 48, at: wc, metres: 2), mats.water, name: "water")

        // the west ramp and balcony: sweep up the cavern wall, framed by the rock (a quiet place to look back at the statue)
        var ramp = P1Mesh()
        let steps = 60, rin = Self.rampR - Self.rampW / 2, rout = Self.rampR + Self.rampW / 2
        func rp(_ k: Int) -> (a: Float, h: Float) { let u = Float(k) / Float(steps), p = Self.rampPoint(u); return (atan2(p.x, p.z), p.y) }
        func ringPt(_ k: Int, _ r: Float, _ y: Float) -> SIMD3<Float> { let q = rp(k); return [sin(q.a) * r, y, cos(q.a) * r] }
        ramp.grid(steps, 1, facing: { _, _, _ in [0, 1, 0] }) { k, i in (ringPt(k, i == 0 ? rin : rout, rp(k).h), [Float(i) * Self.rampW / 3, Float(k) * 0.6]) }
        ramp.grid(steps, 1, facing: { _, _, c in [c.x, 0, c.z] }) { k, i in (ringPt(k, rout, i == 0 ? rp(k).h : 0), [Float(i) * rp(k).h / 3, Float(k) * 0.6]) }
        ramp.grid(steps, 1, facing: { _, _, c in [-c.x, 0, -c.z] }) { k, i in (ringPt(k, rin, i == 0 ? rp(k).h : 0), [Float(i) * rp(k).h / 3, Float(k) * 0.6]) }
        try add(ramp, mats.sand, shape: try await staticShape(ramp), name: "ramp")

        // the gift's actors: the dream (a turning orb carrying his tile), its soft halo, a few motes in the shaft
        orb.components.set(ModelComponent(mesh: .generateSphere(radius: 0.21), materials: [mats.orb]))
        orb.position = [0, 0.9, T.wellZ]; orb.isEnabled = false
        halo.components.set(ModelComponent(mesh: .generatePlane(width: 1.7, height: 1.7), materials: [mats.halo]))
        halo.components.set(BillboardComponent())
        orb.addChild(halo); root.addChild(orb)
        var motes = ParticleEmitterComponent()
        motes.emitterShape = .box; motes.emitterShapeSize = [3, 11, 4]
        motes.mainEmitter.birthRate = 5; motes.mainEmitter.lifeSpan = 12; motes.mainEmitter.size = 0.03
        motes.mainEmitter.color = .constant(.single(UIColor(red: 0.95, green: 0.88, blue: 0.7, alpha: 0.3)))
        motes.speed = 0.02
        dust.components.set(motes); dust.position = [0, 6, 7]; root.addChild(dust)

        // the keys: his Glyph Field silhouettes in gold, standing upright over a soft halo, slowly turning (planes are double sided)
        let aspect: [PLWGlyph: Float] = [.glyphGuy: 256.0 / 640, .loveYourself: 593.0 / 640, .money: 484.0 / 640]
        for g in glyphs {
            var m = UnlitMaterial(); m.faceCulling = .none
            m.color = .init(tint: .white, texture: .init(try await P1Materials.load("plw-p1-key-\(g.glyph.rawValue)", "png", .color)))
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
            let h: Float = 0.9, k = Entity()
            k.components.set(ModelComponent(mesh: .generatePlane(width: h * (aspect[g.glyph] ?? 0.5), height: h), materials: [m]))
            let glow = Entity(); glow.components.set(ModelComponent(mesh: .generatePlane(width: 1.6, height: 1.6), materials: [mats.halo])); glow.components.set(BillboardComponent())
            let holder = Entity(); holder.position = g.position; holder.addChild(k); holder.addChild(glow)
            root.addChild(holder); keyEntities[g.key.slot] = holder
        }

        // light: one honey shaft through the oculus onto the well and the face (soft shadows), a cool fill from the tunnel, a warm glow at the well
        let shaft = Entity()
        var spot = SpotLightComponent(); spot.color = UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1); spot.intensity = T.shaftLumens
        spot.innerAngleInDegrees = 18; spot.outerAngleInDegrees = 36; spot.attenuationRadius = 80
        shaft.components.set(spot); shaft.components.set(SpotLightComponent.Shadow())
        shaft.look(at: [0, 0, 6], from: [0, T.caveH + 2, 4], relativeTo: nil); root.addChild(shaft)
        lights.append((shaft, [1, 0.75, 0.3], T.shaftLumens))
        for (p, c, l, r) in [([0, 4, -T.caveR - 4], [0.72, 0.78, 0.83], T.fillLumens, Float(30)), ([0, 1.6, T.wellZ], [0.96, 0.72, 0.31], T.wellLumens, Float(7)),
                             ([-12, 8, 8], [0.9, 0.78, 0.6], T.fillLumens, Float(26)), ([12, 8, 8], [0.9, 0.78, 0.6], T.fillLumens, Float(26))] as [(SIMD3<Float>, SIMD3<Float>, Float, Float)] {
            var pl = PointLightComponent(); pl.color = P1Materials.ui(c); pl.intensity = l; pl.attenuationRadius = r
            let e = Entity(); e.components.set(pl); e.position = p; root.addChild(e); lights.append((e, c, l))
        }
        // the visible shaft: three crossed, tapering planes with a soft gold gradient (no strobe, no flicker)
        var rays = P1Mesh()
        for k in 0..<3 {
            let yaw = Float(k) * .pi / 3, dirX: SIMD3<Float> = [cos(yaw), 0, -sin(yaw)]
            rays.grid(8, 1, facing: { _, _, _ in [0, 0, 1] }) { j, i in
                let t = Float(j) / 8, w = 1.6 + 5.6 * t, c: SIMD3<Float> = [0, T.caveH - t * (T.caveH - 0.2), 4 + t * 2]
                return (c + dirX * (Float(i) * 2 - 1) * w, [Float(i), 1 - t])
            }
        }
        try add(rays, mats.shaft, name: "shaft")
        restore(saved)
    }

    // MARK: runtime

    func restore(_ save: PLWSave) {
        saved = save
        let done = save.dream != .absent || save.completed.contains(.p1)
        gift = done ? .done : .waiting; held = done ? Tune.holdSeconds : 0; orb.isEnabled = false
        taken = Set(glyphs.filter { save.glyphs.contains($0.key) }.map { $0.key.slot })
        for (slot, e) in keyEntities { e.isEnabled = !taken.contains(slot) }
    }

    func step(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        elapsed += f.dt
        for e in keyEntities.values where e.isEnabled { e.orientation = e.orientation * simd_quatf(angle: f.dt * 0.9, axis: [0, 1, 0]) }
        func say(_ id: String, _ line: String) { if said.insert(id).inserted { out.append(.caption(line)) } }

        // keys: ACT within reach collects the nearest, once
        if f.actPressed, let g = glyphs.first(where: { !taken.contains($0.key.slot) && simd_length(SIMD2(f.position.x - $0.position.x, f.position.z - $0.position.z)) < 1.8 && abs(f.position.y + 1 - $0.position.y) < 2.4 }) {
            taken.insert(g.key.slot); keyEntities[g.key.slot]?.isEnabled = false; out.append(.collect(g.key))
        }

        let well = SIMD3<Float>(0, 0, Tune.wellZ), near = simd_length(SIMD2(f.position.x, f.position.z - Tune.wellZ)) < Tune.wellRadius
        switch gift {
        case .waiting:
            if elapsed > 1.5 { say("walk", "Walk to the well.") }
            let still = near && (f.actHeld || simd_length(f.velocity) < 0.15)
            held = still ? min(Tune.holdSeconds, held + f.dt) : max(0, held - f.dt * 1.5)
            if near { say("hold", "Hold ACT, or stand still.") }
            let k = held / Tune.holdSeconds
            orb.isEnabled = held > 0.05
            orb.position = well + [0, 0.9 + k * 1.3, 0]; orb.orientation = orb.orientation * simd_quatf(angle: f.dt * 0.6, axis: [0, 1, 0])
            if abs(k - lastRise) > 0.02 { lastRise = k; out.append(.raiseDream(k)) }
            if held >= Tune.holdSeconds { gift = .flying; flyT = 0 }
        case .flying:
            flyT = min(1, flyT + f.dt / 1.3)
            let e = flyT * flyT * (3 - 2 * flyT), hands = f.position + [0, 1.1, 0]
            orb.position = (well + [0, 2.2, 0]) * (1 - e) + hands * e; orb.scale = SIMD3(repeating: 1 - 0.4 * e)
            if flyT >= 1 {
                gift = .done; orb.isEnabled = false      // from here the hero carries the dream (lane A draws it)
                out += [.raiseDream(1), .dream(.carried), .completeMoment(.p1), .checkpoint(.p1, port: "start")]
                say("gift", "It is yours to carry.")
            }
        case .done: break
        }
        return out
    }

    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] { [] }   // all reactions are distance checks in `step`, so a missed trigger can never strand the gift

    func apply(_ look: PLWLook) {
        mats.apply(saturation: look.saturation)
        for l in lights {
            let g = simd_dot(l.color, [0.2126, 0.7152, 0.0722]), c = simd_clamp(SIMD3<Float>(repeating: g) + (l.color - SIMD3<Float>(repeating: g)) * look.saturation, .zero, SIMD3<Float>(repeating: 1))
            if var s = l.e.components[SpotLightComponent.self] { s.color = P1Materials.ui(c); s.intensity = l.lumens * look.exposure; l.e.components.set(s) }
            if var p = l.e.components[PointLightComponent.self] { p.color = P1Materials.ui(c); p.intensity = l.lumens * look.exposure; l.e.components.set(p) }
        }
        // shared materials were edited in place: push them onto the meshes that use them
        for case let m as ModelEntity in root.children {
            guard var model = m.model else { continue }
            switch m.name {
            case "cavern": model.materials = [mats.rock]
            case "floor": model.materials = [mats.floor]
            case "ramp": model.materials = [mats.sand]
            default: continue
            }
            m.model = model
        }
    }

    func unload() {
        root.children.removeAll(); keyEntities.removeAll(); lights.removeAll(); orb.children.removeAll(); orb.components.remove(ModelComponent.self)
        held = 0; gift = .waiting; said.removeAll(); taken.removeAll(); lastRise = -1; elapsed = 0
    }
}
