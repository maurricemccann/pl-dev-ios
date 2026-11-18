import RealityKit
import UIKit
import simd

/// Page 4, THE HIDING (grey). Out of room 3's purple tunnel: a 16 m stone passage curves down 1.5 m while the purple drains to grey; it opens into a round ash
/// grove 28 m across where his tree stands 14 m tall, its two eyes and grin from his plate 4 (the pupils follow him), a crown of swelling branches with flat ends,
/// roots seated in stone sockets, dead leaves over his curve tile. Step up to the hollow at its foot: the dream floats in, its gold goes out, one branch bends over
/// the hollow like a guard. His carving lies under the left root; the grey-blue exit is through petrified roots beyond. Numbers are the web build's (`room4.js`).
/// Origin: where room 3's purple tunnel ends; the passage runs toward -Z. Unproven: lumens (`Tune`), the passage's purple-to-grey drain (four tinted segments, no vertex
/// colour in RealityKit), pupil travel limits, camera framing, whether the moment should require the carried dream (it runs either way so the room can be tested).
@MainActor final class PLWRoomP4: PLWRoom {
    enum Tune {
        static let passW: Float = 2.5, passH: Float = 7, drop: Float = 1.5, groveR: Float = 14, groveH: Float = 12, zone: Float = 2
        static let moonLux: Float = 1_500, eyeLumens: Float = 6_000, hollowLumens: Float = 9_000, exitLumens: Float = 8_000
    }
    typealias V = SIMD3<Float>

    let id: PLWArea = .p4
    let root = Entity()
    private(set) var ports: [String: Transform] = [:]
    private(set) var route: [V] = []
    private(set) var triggers: [PLWTrigger] = []
    private(set) var glyphs: [PLWGlyphPlacement] = []

    private var path: [V] = [], arc: [Float] = []
    private var grove: V = .zero, tree: V = .zero, front: V = .zero, hollowRest: V = .zero, secretAt: V = .zero
    private let orb = ModelEntity(), guardPivot = Entity(), holeLight = Entity()
    private var pupils: [(e: Entity, centre: V, tangent: V)] = []
    private var keyEntities: [UInt8: Entity] = [:], lights: [(e: Entity, color: V, lumens: Float)] = []
    private var orbMat = PhysicallyBasedMaterial()
    private enum Phase { case waiting, hiding, done }
    private var phase = Phase.waiting, t: Float = 0, handsAt: V = .zero, cameraOn = false, elapsed: Float = 0
    private var said: Set<String> = [], taken: Set<UInt8> = [], saved = PLWSave()

    private static func sm(_ a: Float, _ b: Float, _ x: Float) -> Float { let k = min(max((x - a) / (b - a), 0), 1); return k * k * (3 - 2 * k) }
    private static let trunkProfile: [SIMD2<Float>] = [[4, 0], [3.1, 1], [2.5, 3], [2.25, 6], [2.4, 8.5], [2.6, 10], [2.1, 11.6], [0.01, 11.7]]
    private func trunkRadius(_ y: Float) -> Float {
        let p = Self.trunkProfile
        for k in 0..<(p.count - 2) where y <= p[k + 1].y { let f = (y - p[k].y) / (p[k + 1].y - p[k].y); return p[k].x + (p[k + 1].x - p[k].x) * f }
        return p[p.count - 2].x
    }

    init() {
        let T0 = Tune.self
        let raw: [[Float]] = [[0, 0], [0, -3], [1.4, -7], [1.8, -11], [0.6, -14], [0, -16]]
        path = P1Mesh.spline(raw.map { V($0[0], 0, $0[1]) }, per: 40)
        arc = [0]; for i in 1..<path.count { arc.append(arc[i - 1] + simd_distance(path[i], path[i - 1])) }
        let len = arc[arc.count - 1]
        for i in path.indices { path[i].y = -T0.drop * Self.sm(0, len, arc[i]) }
        let e = path[path.count - 1]
        grove = [e.x, -T0.drop, e.z - T0.groveR]; tree = grove + [0, 0, -2.5]; front = tree + [0, 0, 4.6]; hollowRest = tree + [0, 0.9, 2.6]
        let x0: V = [grove.x, -T0.drop, grove.z - T0.groveR]
        ports = ["start": Transform(translation: [0, 0, -2]), "entry": Transform(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]), translation: .zero),
                 "grove": Transform(translation: tree + [0, 0, 7]), "exit": Transform(translation: x0 + [0, 0, -8])]
        route = stride(from: 0, to: path.count, by: 20).map { path[$0] } + [e, grove + [0, 0, -1], front, x0, x0 + [0, 0, -8]]
        secretAt = tree + [-5.6, 0, 6.6]
        glyphs = [PLWGlyphPlacement(key: PLWKey(page: .p4, slot: 0), glyph: .glyphGuy, position: path[path.count * 55 / 100] + [0.8, 1.2, 0]),
                  PLWGlyphPlacement(key: PLWKey(page: .p4, slot: 1), glyph: .smiley, position: grove + [-9, 1.2, 2]),
                  PLWGlyphPlacement(key: PLWKey(page: .p4, slot: 2), glyph: .loveYourself, position: secretAt + [1.5, 1.2, 0.5])]
        triggers = [PLWTrigger(id: "p4.hollow", center: front + [0, 1, 0], yaw: 0, halfExtents: [T0.zone, 2, T0.zone])]
            + glyphs.map { PLWTrigger(id: "p4.key\($0.key.slot)", center: $0.position, yaw: 0, halfExtents: [1.4, 1.6, 1.4]) }
    }

    private func nrm(_ i: Int) -> V {
        let a = path[max(0, i - 1)], b = path[min(path.count - 1, i + 1)], tx = b.x - a.x, tz = b.z - a.z, l = max((tx * tx + tz * tz).squareRoot(), 1e-5)
        return [tz / l, 0, -tx / l]
    }
    private func bump(_ s: Float, _ y: Float, _ k: Float) -> Float { 0.35 * sin(s * 1.3 + y * 0.9 + k) + 0.2 * sin(s * 3.1 - y * 1.7 + k * 2) }

    // MARK: load

    func load() async throws {
        let T0 = Tune.self
        func tex(_ n: String, _ e: String, _ s: TextureResource.Semantic) async throws -> TextureResource { try await P1Materials.load(n, e, s) }
        func stone(_ prefix: String, _ set: String, tint: V, rough: Bool = true) async throws -> PhysicallyBasedMaterial {
            var mt = PhysicallyBasedMaterial()
            mt.baseColor = .init(tint: P1Materials.ui(tint), texture: P1Materials.tx(try await tex("plw-\(prefix)-\(set)-albedo", "jpg", .color)))
            mt.normal = .init(texture: P1Materials.tx(try await tex("plw-\(prefix)-\(set)-normal", "jpg", .normal)))
            if rough { mt.roughness = .init(scale: 1, texture: P1Materials.tx(try await tex("plw-\(prefix)-\(set)-rough", "jpg", .raw))) } else { mt.roughness = .init(floatLiteral: 0.7) }
            mt.metallic = .init(floatLiteral: 0)
            return mt
        }
        let rock = try await stone("p4", "rock", tint: [1, 1, 1]), bark = try await stone("p4", "bark", tint: [1, 1, 1]), loam = try await stone("p4", "floor", tint: [1, 1, 1])
        let tile = try await stone("p2", "woven", tint: [0.85, 0.85, 0.88], rough: false)
        func add(_ mesh: P1Mesh, _ mt: PhysicallyBasedMaterial, shape: ShapeResource? = nil, name: String) async throws {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing(name) }
            let e = ModelEntity(mesh: r, materials: [mt]); e.name = name
            if let shape { e.components.set(CollisionComponent(shapes: [shape])); e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static)) }
            root.addChild(e)
        }
        func staticShape(_ mesh: P1Mesh) async throws -> ShapeResource {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing("shape") }
            return try await ShapeResource.generateStaticMesh(from: r)
        }

        // the passage: rock walls that lean in, the purple draining to grey along four tinted segments; a loam floor; a rock face round room 3's tunnel mouth
        let purple: V = [0.55, 0.3, 0.85], ash: V = [0.9, 0.9, 0.92], n4 = (path.count - 1) / 4
        for side: Float in [1, -1] {
            for seg in 0..<4 {
                let r0 = seg * n4, r1 = seg == 3 ? path.count - 1 : (seg + 1) * n4
                var w = P1Mesh()
                w.grid(r1 - r0, 14, facing: { j, _, c in [self.path[r0 + j].x - c.x, 0, self.path[r0 + j].z - c.z] }) { j, i in
                    let c = r0 + j, y = Float(i) * T0.passH / 14, d = T0.passW + 0.2 + self.bump(self.arc[c], y, side) - 0.12 * y
                    return (self.path[c] + self.nrm(c) * (side * d) + [0, y, 0], [self.arc[c] / 3, y / 3])
                }
                let k = Self.sm(0, 14, arc[(r0 + r1) / 2])
                var wm = rock; wm.baseColor.tint = P1Materials.ui(purple + (ash - purple) * k)
                try await add(w, wm, shape: try await staticShape(w), name: "passageWall")
            }
        }
        var pf = P1Mesh()
        pf.grid(path.count - 1, 1, facing: { _, _, _ in [0, 1, 0] }) { j, i in
            let q = self.path[j] + self.nrm(j) * (i == 0 ? T0.passW + 0.6 : -T0.passW - 0.6); return (q, [q.x / 4, q.z / 4])
        }
        try await add(pf, loam, shape: try await staticShape(pf), name: "passageFloor")
        var mouth = P1Mesh()
        mouth.grid(1, 30, facing: { _, _, _ in [0, 0, -1] }) { j, i in
            let th = Float(i) / 30 * .pi, dx = cos(th), dy = sin(th)
            if j == 0 { return ([dx * 2, dy * 5, 0], [dx * 2 / 3, dy * 5 / 3]) }
            let tx = abs(dx) < 1e-4 ? 1e9 : (T0.passW + 1) / abs(dx), ty = dy < 1e-4 ? 1e9 : T0.passH / dy, k = min(tx, ty), y = min(T0.passH, dy * k)
            return ([dx * k, y, 0], [dx * k / 3, y / 3])
        }
        try await add(mouth, rock, shape: try await staticShape(mouth), name: "passageMouth")

        // the grove: a round clearing with high natural walls, a gap in from the passage (angle 0 is the entry side) and a gap out through the roots
        let R = T0.groveR, gIn = asin((T0.passW + 0.3) / R), gOut = asin(2.3 / R)
        let arcs: [(Float, Float)] = [(gIn, Float.pi - gOut), (Float.pi + gOut, 2 * Float.pi - gIn)]
        for (k, ends) in arcs.enumerated() {
            let a0 = ends.0, a1 = ends.1
            var w = P1Mesh(); let cols = Int(((a1 - a0) / (2 * .pi) * 96).rounded(.up))
            w.grid(cols, 20, facing: { _, _, c in [self.grove.x - c.x, 0, self.grove.z - c.z] }) { j, i in
                let a = a0 + (a1 - a0) * Float(j) / Float(cols), y = Float(i) * T0.groveH / 20, d = R + 0.3 + self.bump(a * R, y, Float(k) + 3) + 0.08 * y
                return ([self.grove.x + sin(a) * d, self.grove.y + y, self.grove.z + cos(a) * d], [a * R / 3, y / 3])
            }
            try await add(w, rock, shape: try await staticShape(w), name: "groveWall")
        }
        var gf = P1Mesh()
        gf.grid(6, 64, facing: { _, _, _ in [0, 1, 0] }) { j, i in
            let a = Float(i) / 64 * 2 * .pi, r = max(0.01, (R + 0.8) * Float(j) / 6), x = self.grove.x + sin(a) * r, z = self.grove.z + cos(a) * r
            return ([x, self.grove.y, z], [x / 4, z / 4])
        }
        try await add(gf, loam, shape: .generateBox(size: [2 * R + 2, 0.5, 2 * R + 2]).offsetBy(translation: grove + [0, -0.25, 0]), name: "groveFloor")

        // his curve tile: a 3.5 m path from the passage to the hollow, half buried (the leaf layer is in the floor texture)
        let lastP = path[path.count - 1]
        let way: [V] = path + [V(lastP.x, -T0.drop, lastP.z - 3), V(tree.x, -T0.drop, tree.z + 5.5)]
        var run: [Float] = [0]; for i in 1..<way.count { run.append(run[i - 1] + simd_distance(way[i], way[i - 1])) }
        var tp = P1Mesh()
        tp.grid(way.count - 1, 1, facing: { _, _, _ in [0, 1, 0] }) { j, i in
            let a = way[max(0, j - 1)], b = way[min(way.count - 1, j + 1)], dx = b.x - a.x, dz = b.z - a.z, l = max((dx * dx + dz * dz).squareRoot(), 1e-5)
            let n: V = [dz / l, 0, -dx / l]
            return (way[j] + n * (i == 0 ? 1.75 : -1.75) + [0, 0.012, 0], [Float(i), run[j] / 3.5])
        }
        try await add(tp, tile, name: "tilePath")

        // the tree: a 14 m trunk 8 m across at the foot
        let trunk = P1Mesh.lathe(Self.trunkProfile, segments: 48, at: tree, metres: 3)
        guard let trunkRes = trunk.resource() else { throw P1Materials.Failure.missing("trunk") }
        try await add(trunk, bark, shape: try await ShapeResource.generateConvex(from: trunkRes), name: "trunk")
        func branch(_ pts: [V], _ r0: Float, _ r1: Float) -> P1Mesh {   // swelling through the middle, flat rounded ends (his curve rule)
            let bp = P1Mesh.spline(pts, per: 10), n = bp.count
            return P1Mesh.sweep(bp, section: P1Mesh.circle(16), scale: { k in let u = Float(k) / Float(n - 1), r = r0 + (r1 - r0) * u + 0.22 * sin(.pi * u) * (r0 + r1); return [r, r] }, metres: 3)
        }
        var crown = P1Mesh()
        for k in 0..<7 {
            let a = Float(k) / 7 * 2 * .pi + 0.3, c = cos(a), s = sin(a)
            func at(_ r: Float, _ y: Float) -> V { tree + [c * r, y, s * r] }
            crown.merge(branch([at(1.2, 10.2), at(3.6, 12.6), at(6.4, 13.4), at(8.4, 11.6), at(8.9, 9.6)], 0.95, 0.55))
        }
        try await add(crown, bark, name: "crown")
        var roots = P1Mesh()
        for a: Float in [0.5, 1.5, 2.6, 3.7, 4.6, 5.6] {
            if abs(atan2(sin(a - .pi / 2), cos(a - .pi / 2))) < 0.5 { continue }   // keep the front (the path and the hollow) clear
            let c = cos(a), s = sin(a)
            func at(_ r: Float, _ y: Float) -> V { tree + [c * r, y, s * r] }
            roots.merge(branch([at(2.8, 1.2), at(5, 1.0), at(7.2, 0.55), at(8.6, 0.3)], 0.85, 0.45))
            let sp = at(8.9, 0)
            roots.merge(.lathe([[1.0, 0], [0.75, 0.55], [0.01, 0.55]], segments: 20, at: [sp.x, grove.y, sp.z], metres: 2))
        }
        try await add(roots, rock, shape: try await staticShape(roots), name: "roots")
        // the concerned branch: from the trunk's right side, down and in over the hollow; it bends further over once the dream is hidden
        guardPivot.position = tree + [2.0, 4.4, 0.6]
        let gb = branch([[0, 0, 0], [1.4, 0.6, 1.4], [1.0, -0.2, 3.0], [-0.6, -1.0, 3.6], [-1.9, -1.4, 3.4]], 0.7, 0.42)
        if let r = gb.resource() { let e = ModelEntity(mesh: r, materials: [bark]); e.name = "guard"; guardPivot.addChild(e) }
        root.addChild(guardPivot)

        // his face from plate 4 (two eyes and the full grin), a curved patch hugging the trunk; his pupils slide inside the whites toward him
        var face = PhysicallyBasedMaterial()
        face.baseColor = .init(tint: .white, texture: .init(try await tex("plw-p4-face", "png", .color)))
        face.roughness = .init(floatLiteral: 0.75); face.metallic = .init(floatLiteral: 0)
        face.emissiveColor = .init(color: UIColor(white: 0.12, alpha: 1)); face.emissiveIntensity = 1
        face.blending = .transparent(opacity: .init(floatLiteral: 1)); face.opacityThreshold = 0.4
        func patch(_ y0: Float, _ y1: Float, _ half: Float, lift: Float) -> P1Mesh {
            var m = P1Mesh()
            m.grid(20, 20, facing: { _, _, c in [c.x - self.tree.x, 0, c.z - self.tree.z] }) { j, i in
                let u = Float(j) / 20, y = y0 + (y1 - y0) * u, a = (Float(i) / 20 * 2 - 1) * half, r = self.trunkRadius(y) + lift
                return (self.tree + [sin(a) * r, y, cos(a) * r], [Float(i) / 20, u])
            }
            return m
        }
        let fh: Float = 3.0 * 1367 / 1031
        try await add(patch(7.4 - fh / 2, 7.4 + fh / 2, 0.62, lift: 0.02), face, name: "treeFace")
        var hollow = UnlitMaterial(); hollow.color = .init(tint: .white, texture: .init(try await tex("plw-p4-hollow", "png", .color))); hollow.blending = .transparent(opacity: .init(floatLiteral: 1))
        if let r = patch(0.05, 2.3, 0.27, lift: 0.03).resource() { let e = ModelEntity(mesh: r, materials: [hollow]); e.name = "hollow"; root.addChild(e) }
        var pm = UnlitMaterial(); pm.color = .init(tint: UIColor(white: 0.02, alpha: 1), texture: .init(try await tex("plw-p4-pupil", "png", .color)))
        pm.blending = .transparent(opacity: .init(floatLiteral: 1)); pm.faceCulling = .none
        let fs: Float = 3.0 / 1031
        for sx: Float in [-1, 1] {
            let x = sx * (839 - 515.5) * fs, y = 7.4 + (683.5 - 347) * fs, r = trunkRadius(y) + 0.06, z = max(0.5, (r * r - x * x).squareRoot()), n = simd_normalize(V(x, 0, z))
            let e = Entity(); e.components.set(ModelComponent(mesh: .generatePlane(width: 123 * fs, height: 256 * fs), materials: [pm]))
            e.position = tree + [x, y, z]; e.orientation = simd_quatf(angle: atan2(n.x, n.z), axis: [0, 1, 0]); root.addChild(e)
            pupils.append((e, tree + [x, y, z], simd_normalize(simd_cross([0, 1, 0], n))))
        }

        // the secret: his carving on a flat stone socket under the left root, half hidden
        let sc = secretAt
        try await add(P1Mesh.box([1.2, 0.16, 0.9], at: [sc.x, grove.y + 0.08, sc.z], metres: 2), rock, shape: .generateBox(size: [1.2, 0.16, 0.9]).offsetBy(translation: [sc.x, grove.y + 0.08, sc.z]), name: "leafStone")
        var carve = PhysicallyBasedMaterial()
        carve.baseColor = .init(tint: .white, texture: .init(try await tex("plw-p4-carve", "png", .color))); carve.roughness = .init(floatLiteral: 0.9); carve.metallic = .init(floatLiteral: 0)
        carve.blending = .transparent(opacity: .init(floatLiteral: 1)); carve.opacityThreshold = 0.3
        let ce = ModelEntity(mesh: .generatePlane(width: 0.6, depth: 0.85), materials: [carve]); ce.position = [sc.x, grove.y + 0.165, sc.z]; root.addChild(ce)

        // the exit: a 4 m gap through petrified roots, then 8 m of lining from ash grey to silver-blue plaster, toward room 5
        let x0: V = [grove.x, -T0.drop, grove.z - R]
        var pet = P1Mesh()
        for sx: Float in [1, -1] { pet.merge(branch([x0 + [sx * 3.4, 0.2, 1.6], x0 + [sx * 2.6, 3.4, 0.6], x0 + [sx * 0.6, 5.0, 0], x0 + [-sx * 0.8, 5.2, -0.4]], 0.75, 0.5)) }
        try await add(pet, rock, shape: try await staticShape(pet), name: "petrified")
        let silver: V = [0.55, 0.72, 1.0]
        for seg in 0..<4 {
            var tm = P1Mesh(); let z0 = x0.z - Float(seg) * 2, z1 = z0 - 2
            tm.grid(4, 32, facing: { _, _, c in [x0.x - c.x, x0.y + 2 - c.y, 0] }) { j, i in
                let th = Float(i) / 32 * .pi, z = z0 + (z1 - z0) * Float(j) / 4
                return ([x0.x + cos(th) * 2, x0.y + sin(th) * 4.5, z], [Float(i) / 32 * 10 / 3, (x0.z - z) / 3])
            }
            let k = Self.sm(0, 8, Float(seg) * 2 + 1), tint = ash * 0.85 + (silver - ash * 0.85) * k
            var lm = rock; lm.baseColor.tint = P1Materials.ui(simd_clamp(tint, .zero, [1, 1, 1]))
            try await add(tm, lm, shape: try await staticShape(tm), name: "exitLining\(seg)")
        }
        try await add(P1Mesh.box([4.5, 0.5, 8.5], at: [x0.x, x0.y - 0.25, x0.z - 4], metres: 2), loam, shape: .generateBox(size: [4.5, 0.5, 8.5]).offsetBy(translation: [x0.x, x0.y - 0.25, x0.z - 4]), name: "exitFloor")

        // the dream, ready to float into the hollow
        orbMat.baseColor = .init(tint: UIColor(red: 0.1, green: 0.09, blue: 0.08, alpha: 1))
        orbMat.emissiveColor = .init(color: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), texture: P1Materials.tx(try await tex("plw-p1-tiletier-albedo", "jpg", .color)))
        orbMat.emissiveIntensity = 2.4; orbMat.roughness = .init(floatLiteral: 0.4)
        orb.model = ModelComponent(mesh: .generateSphere(radius: 0.21), materials: [orbMat]); orb.isEnabled = false; root.addChild(orb)

        // the keys: his glyph silhouettes in gold, upright over a soft halo
        var halo = UnlitMaterial(); halo.color = .init(tint: .white, texture: .init(try await tex("plw-p1-halo", "png", .color))); halo.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let ga: [PLWGlyph: Float] = [.glyphGuy: 256.0 / 640, .smiley: 521.0 / 640, .loveYourself: 593.0 / 640]
        for g in glyphs {
            var km = UnlitMaterial(); km.faceCulling = .none
            let file = g.glyph == .smiley ? "plw-p2-key-smiley" : "plw-p1-key-\(g.glyph.rawValue)"
            km.color = .init(tint: .white, texture: .init(try await tex(file, "png", .color))); km.blending = .transparent(opacity: .init(floatLiteral: 1))
            let k = Entity(), h: Float = 0.9
            k.components.set(ModelComponent(mesh: .generatePlane(width: h * (ga[g.glyph] ?? 0.7), height: h), materials: [km]))
            let glow = Entity(); glow.components.set(ModelComponent(mesh: .generatePlane(width: 1.6, height: 1.6), materials: [halo])); glow.components.set(BillboardComponent())
            let holder = Entity(); holder.position = g.position; holder.addChild(k); holder.addChild(glow)
            root.addChild(holder); keyEntities[g.key.slot] = holder
        }

        // light: a cold moon (soft shadows), a pale point at the eye, the hollow's gold (it goes to black), a grey-blue glow at the exit
        let moon = Entity(); var dl = DirectionalLightComponent(); dl.color = UIColor(red: 0.25, green: 0.27, blue: 0.31, alpha: 1); dl.intensity = T0.moonLux
        moon.components.set(dl); moon.components.set(DirectionalLightComponent.Shadow()); moon.look(at: [0.2, -0.95, -0.3], from: .zero, relativeTo: nil); root.addChild(moon)
        lights.append((moon, [0.25, 0.27, 0.31], T0.moonLux))
        func point(_ e: Entity, _ p: V, _ c: V, _ lumens: Float, _ radius: Float) {
            var pl = PointLightComponent(); pl.color = P1Materials.ui(c); pl.intensity = lumens; pl.attenuationRadius = radius
            e.components.set(pl); e.position = p; root.addChild(e); lights.append((e, c, lumens))
        }
        point(Entity(), tree + [0, 8.4, 4], [0.88, 0.9, 1], T0.eyeLumens, 14)
        point(holeLight, hollowRest + [0, 0.4, 0.8], [1, 0.75, 0.3], T0.hollowLumens, 8)
        point(Entity(), x0 + [0, 2, -3], [0.31, 0.35, 0.39], T0.exitLumens, 12)
        point(Entity(), grove + [0, 6, 3], [0.55, 0.6, 0.7], 12_000, 22)
        restore(saved)
    }

    // MARK: runtime

    func restore(_ save: PLWSave) {
        saved = save
        let hidden = save.dream == .buried || save.dream == .recovered || save.completed.contains(.p4)
        phase = hidden ? .done : .waiting; t = hidden ? 4.5 : 0
        orb.isEnabled = false; guardPivot.orientation = simd_quatf(angle: hidden ? 0.28 : 0, axis: [1, 0, 0])
        setHollowLight(hidden ? 0 : 1)
        taken = Set(glyphs.filter { save.glyphs.contains($0.key) }.map { $0.key.slot })
        for (slot, e) in keyEntities { e.isEnabled = !taken.contains(slot) }
    }

    private func setHollowLight(_ k: Float) {
        if var p = holeLight.components[PointLightComponent.self] { p.intensity = Tune.hollowLumens * k; holeLight.components.set(p) }
    }

    func step(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        elapsed += f.dt
        for e in keyEntities.values where e.isEnabled { e.orientation = e.orientation * simd_quatf(angle: f.dt * 0.9, axis: [0, 1, 0]) }
        func say(_ id: String, _ line: String) { if said.insert(id).inserted { out.append(.caption(line)) } }
        if elapsed > 1.5 { say("grove", "Follow the path to the tree.") }

        if f.actPressed, let g = glyphs.first(where: { !taken.contains($0.key.slot) && simd_length(SIMD2(f.position.x - $0.position.x, f.position.z - $0.position.z)) < 1.8 && abs(f.position.y + 1 - $0.position.y) < 2.4 }) {
            taken.insert(g.key.slot); keyEntities[g.key.slot]?.isEnabled = false; out.append(.collect(g.key))
        }

        for p in pupils {   // his pupils follow him, sliding inside the whites
            let to = f.position + [0, 1.2, 0] - p.centre, d = max(simd_length(to), 1e-3)
            p.e.position = p.centre + p.tangent * (simd_dot(to, p.tangent) / d * 0.12) + [0, to.y / d * 0.18, 0]
        }

        let near = simd_length(SIMD2(f.position.x - front.x, f.position.z - front.z)) < Tune.zone
        if near && phase == .waiting { say("hollow", "Give the dream to the hollow.") }
        if phase == .waiting && near {
            phase = .hiding; t = 0; handsAt = f.position + [0, 1.1, 0]; orb.isEnabled = true; orb.position = handsAt
            orbMat.emissiveIntensity = 2.4; orb.model?.materials = [orbMat]
            out.append(.dream(.buried))
        }
        if phase == .hiding {
            t += f.dt
            let fly = Self.sm(0, 1.2, t)
            orb.position = handsAt + (hollowRest - handsAt) * fly + [0, sin(fly * .pi) * 0.6, 0]
            orb.scale = SIMD3(repeating: 1 - 0.35 * fly)
            let fade = Self.sm(1.2, 2.0, t)               // the gold goes out: the dream dims to obsidian
            orbMat.emissiveIntensity = 2.4 * (1 - fade); orb.model?.materials = [orbMat]; setHollowLight(1 - fade)
            guardPivot.orientation = simd_quatf(angle: 0.28 * Self.sm(2, 4, t), axis: [1, 0, 0])
            let w = Self.sm(0, 1, t) * (1 - Self.sm(3, 4.5, t))   // the camera frames him, the eye and the hollow in one shot, looking down
            out.append(.camera(position: front + [0, 6.5, 8.5], target: tree + [0, 3.5, 2], weight: 0.9 * w)); cameraOn = true
            if t >= 3 {
                phase = .done; orb.isEnabled = false
                out += [.completeMoment(.p4), .roomFlag(.p4, "hidden"), .checkpoint(.p4, port: "grove")]
                say("done", "The dream is safe in the dark.")
            }
        } else if phase == .done && cameraOn {   // let the camera go over the next 1.5 s, then release it
            t += f.dt
            let w = 0.9 * (1 - Self.sm(3, 4.5, t))
            if t >= 4.5 { out.append(.camera(position: f.position, target: f.position, weight: 0)); cameraOn = false }
            else { out.append(.camera(position: front + [0, 6.5, 8.5], target: tree + [0, 3.5, 2], weight: w)) }
        }
        return out
    }

    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] { [] }   // reactions are distance checks in `step`

    func apply(_ look: PLWLook) {
        for l in lights {
            let g = simd_dot(l.color, [0.2126, 0.7152, 0.0722]), c = simd_clamp(V(repeating: g) + (l.color - V(repeating: g)) * look.saturation, .zero, V(repeating: 1))
            if var s = l.e.components[DirectionalLightComponent.self] { s.color = P1Materials.ui(c); s.intensity = l.lumens * look.exposure; l.e.components.set(s) }
            if var p = l.e.components[PointLightComponent.self] { p.color = P1Materials.ui(c); if l.e !== holeLight { p.intensity = l.lumens * look.exposure }; l.e.components.set(p) }
        }
    }

    func unload() {
        root.children.removeAll(); pupils.removeAll(); keyEntities.removeAll(); lights.removeAll()
        phase = .waiting; t = 0; cameraOn = false; elapsed = 0; said.removeAll(); taken.removeAll()
    }
}
