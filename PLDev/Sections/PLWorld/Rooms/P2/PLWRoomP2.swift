import RealityKit
import UIKit
import simd

/// Page 2, THE LOOK (ochre and copper). An S-curve slot canyon: 18 m copper sandstone walls carved with his curve as colossal swirl relief that follows the
/// strata, his woven tile laid as the path, a round clearing where holding ACT turns the camera over the shoulder and spreads the white-on-indigo Curve ground
/// out from his feet, and a tunnel whose lining turns red toward room 3. Numbers are the web build's (`room2.js`); the room starts at the origin where room 1's
/// tunnel arrives and runs south (-Z). Reuses lane C's `P1Mesh` and `P1Materials.load` (same lane, no cross-lane import).
/// Left out on purpose: the web's light-rail ride (the contract has no ride verb; the floor is always the way).
/// Unproven: lumens (`Tune`), wall relief reading at phone scale, camera blend, collision on the carved walls.
@MainActor final class PLWRoomP2: PLWRoom {
    enum Tune {
        static let wallH: Float = 18, halfPath: Float = 2.25, clearingR: Float = 10, lookSeconds: Float = 3, lookRadius: Float = 18
        static let sunLux: Float = 9_000, fillLumens: Float = 30_000
    }
    typealias V = SIMD3<Float>

    let id: PLWArea = .p2
    let root = Entity()
    private(set) var ports: [String: Transform] = [:]
    private(set) var route: [V] = []
    private(set) var triggers: [PLWTrigger] = []
    private(set) var glyphs: [PLWGlyphPlacement] = []

    // the centreline, resampled to even arclength
    private var pts: [V] = [], arc: [Float] = []
    private var clearS: Float = 0, clearC: V = .zero, endS: Float = 0
    private var rings: [Entity] = [], edge = Entity(), keyEntities: [UInt8: Entity] = [:]
    private var lights: [(e: Entity, color: V, lumens: Float)] = []
    private var tinted: [(e: ModelEntity, m: PhysicallyBasedMaterial, tint: V)] = []
    private var lookT: Float = 0, radius: Float = 0, done = false, cameraOn = false, elapsed: Float = 0
    private var said: Set<String> = [], taken: Set<UInt8> = [], saved = PLWSave()

    init() {
        let raw: [[Float]] = [[0, 0], [0, -6], [1.2, -12], [4.6, -18], [8.4, -23], [10, -28], [10, -42], [10, -54], [10, -66]]
        let ctrl: [V] = raw.map { V($0[0], 0, $0[1]) }
        let dense = P1Mesh.spline(ctrl, per: 60)
        pts = [dense[0]]; arc = [0]
        for q in dense.dropFirst() { let d = simd_distance(q, pts[pts.count - 1]); if d >= 0.05 { pts.append(q); arc.append(arc[arc.count - 1] + d) } }
        var best = 0, bd = Float.greatestFiniteMagnitude
        for i in pts.indices { let d = abs(pts[i].z + 54); if d < bd { bd = d; best = i } }
        clearS = arc[best]; clearC = pts[best]; endS = clearS + 9
        let end = at(endS)
        let exitZ = end.z - 12
        ports = ["start": Transform(translation: [0, 0, -1]), "entry": Transform(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]), translation: .zero),
                 "exit": Transform(translation: [end.x, 0, exitZ])]
        route = stride(from: Float(0), through: endS, by: 6).map { at($0) } + [[end.x, 0, exitZ]]
        func off(_ s: Float, _ o: Float) -> V { at(s) + normal(s) * o }
        glyphs = [PLWGlyphPlacement(key: PLWKey(page: .p2, slot: 0), glyph: .smiley, position: off(14, -1.6) + [0, 1.2, 0]),
                  PLWGlyphPlacement(key: PLWKey(page: .p2, slot: 1), glyph: .money, position: off(31, 1.4) + [0, 1.2, 0]),
                  PLWGlyphPlacement(key: PLWKey(page: .p2, slot: 2), glyph: .glyphGuy, position: clearC + [0, 1.2, -7])]
        triggers = [PLWTrigger(id: "p2.look", center: clearC + [0, 1, 0], yaw: 0, halfExtents: [3, 2, 3])]
            + glyphs.map { PLWTrigger(id: "p2.key\($0.key.slot)", center: $0.position, yaw: 0, halfExtents: [1.4, 1.6, 1.4]) }
    }

    // MARK: the centreline

    private func at(_ s: Float) -> V {
        var i = 1; while i < arc.count - 1 && arc[i] < s { i += 1 }
        let t = (s - arc[i - 1]) / max(arc[i] - arc[i - 1], 1e-4)
        return pts[i - 1] + (pts[i] - pts[i - 1]) * min(1, max(0, t))
    }
    private func tangent(_ s: Float) -> V { simd_normalize(at(min(arc[arc.count - 1], s + 0.3)) - at(max(0, s - 0.3))) }
    private func normal(_ s: Float) -> V { let t = tangent(s); return [t.z, 0, -t.x] }
    private static func sm(_ a: Float, _ b: Float, _ x: Float) -> Float { let k = min(max((x - a) / (b - a), 0), 1); return k * k * (3 - 2 * k) }
    private func half(_ s: Float) -> Float {   // 6 m at the tunnel, 3 m in the gorge, a 10 m circle in the clearing, 5 m at the exit arch
        var w: Float = 6 + (3.2 - 6) * Self.sm(0, 7, s)
        if s > 30 && s < clearS - 8 { w = 3.0 + 0.2 * sin(s * 0.5) }
        let d = s - clearS, cr = Tune.clearingR
        if abs(d) < cr { w = max(w, (cr * cr - d * d).squareRoot()) }
        if d > 8.6 { w = 5 }
        return w
    }

    // MARK: load

    func load() async throws {
        let T = Tune.self
        func tex(_ n: String, _ e: String, _ s: TextureResource.Semantic) async throws -> TextureResource { try await P1Materials.load(n, e, s) }
        func stone(_ set: String, tint: V) async throws -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: P1Materials.ui(tint), texture: P1Materials.tx(try await tex("plw-p2-\(set)-albedo", "jpg", .color)))
            m.normal = .init(texture: P1Materials.tx(try await tex("plw-p2-\(set)-normal", "jpg", .normal)))
            if set != "woven" && set != "ground" { m.roughness = .init(scale: 1, texture: P1Materials.tx(try await tex("plw-p2-\(set)-rough", "jpg", .raw))) } else { m.roughness = .init(floatLiteral: 0.62) }
            m.metallic = .init(floatLiteral: 0)
            return m
        }
        let copper: V = [1.15, 1.0, 0.9]
        var rock = try await stone("rock", tint: copper); rock.faceCulling = .none   // the walls are seen from inside, and a culled back face casts no shadow
        let sand = try await stone("sand", tint: [1, 0.96, 0.9]), woven = try await stone("woven", tint: [1, 1, 1])
        var ground = PhysicallyBasedMaterial()
        ground.baseColor = .init(tint: .white, texture: P1Materials.tx(try await tex("plw-p2-ground-albedo", "jpg", .color))); ground.roughness = .init(floatLiteral: 0.75); ground.metallic = .init(floatLiteral: 0)
        ground.blending = .transparent(opacity: .init(floatLiteral: 1))

        func add(_ mesh: P1Mesh, _ m: PhysicallyBasedMaterial, shape: ShapeResource? = nil, name: String, tint: V? = nil) async throws -> ModelEntity {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing(name) }
            let e = ModelEntity(mesh: r, materials: [m]); e.name = name
            if let shape { e.components.set(CollisionComponent(shapes: [shape])); e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static)) }
            if let tint { tinted.append((e, m, tint)) }
            root.addChild(e); return e
        }
        func staticShape(_ mesh: P1Mesh) async throws -> ShapeResource {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing("shape") }
            return try await ShapeResource.generateStaticMesh(from: r)
        }

        // his curve as the relief source (128 px, raw bytes); each 11 m panel shows a quarter of the tile so its strokes read as colossal bands
        guard let url = Bundle.main.url(forResource: "plw-p2-relief", withExtension: "bin") else { throw P1Materials.Failure.missing("plw-p2-relief") }
        let rel = [UInt8](try Data(contentsOf: url))
        guard rel.count == 128 * 128 else { throw P1Materials.Failure.missing("plw-p2-relief size") }
        func samp(_ x: Float, _ y: Float) -> Float {
            let fx = x - floor(x), fy = y - floor(y), px = fx * 128, py = fy * 128, x0 = Int(px) & 127, y0 = Int(py) & 127, x1 = (x0 + 1) & 127, y1 = (y0 + 1) & 127, ax = px - floor(px), ay = py - floor(py)
            func g(_ a: Int, _ b: Int) -> Float { Float(rel[b * 128 + a]) / 255 }
            return (g(x0, y0) * (1 - ax) + g(x1, y0) * ax) * (1 - ay) + (g(x0, y1) * (1 - ax) + g(x1, y1) * ax) * ay
        }
        let ph: Float = 11, pw: Float = ph * 210 / 297, py0: Float = 3.2, gap: Float = 0.8
        func relief(_ u: Float, _ y: Float, _ side: Float) -> Float {   // metres into the rock
            let slot = (u + side * 3.7) / (pw + gap), k = floor(slot), fu = (slot - k) * (pw + gap) / pw
            var carve: Float = 0
            if fu < 1 && y > py0 && y < py0 + ph {
                let h = (Int(k) &* 2654435761 &+ (side > 0 ? 7 : 0)) & 3, qx = Float(h & 1) * 0.5, qy = Float(h >> 1) * 0.5
                carve = 0.6 * samp(qx + fu * 0.5, qy + (1 - (y - py0) / ph) * 0.5) * Self.sm(py0, py0 + 0.6, y) * (1 - Self.sm(py0 + ph - 0.6, py0 + ph, y))
            }
            let strata = 0.2 * sin(y * 1.35 + 0.9 * sin(u * 0.07 + side)) + 0.08 * sin(y * 4.1 + 0.4 * sin(u * 0.23))
            let bulge = 0.3 * sin(u * 0.08 + 0.7 * sin(y * 0.29) + side) * (0.6 + 0.4 * sin(y * 0.17))
            return (carve + strata - bulge) * Self.sm(0, 0.8, y)
        }

        // the two walls: displaced grids; they lean in 1.5 m at the top to leave a slit of sky
        let len = endS, ds: Float = 0.35, nrows = Int(len / ds), ny = Int(T.wallH / 0.4), dy = T.wallH / Float(ny)
        for side: Float in [1, -1] {
            var m = P1Mesh()
            m.grid(nrows, ny, facing: { j, _, c in let p = self.at(Float(j) * ds); return [p.x - c.x, 0, p.z - c.z] }) { j, i in
                let s = Float(j) * ds, y = Float(i) * dy, p = self.at(s), n = self.normal(s) * side
                let lean = 1.5 * (y / T.wallH) * (y / T.wallH), d = relief(s, y, side)
                return (p + n * (self.half(s) + d - lean) + [0, y, 0], [s / 3, y / 3])
            }
            _ = try await add(m, rock, shape: try await staticShape(m), name: side > 0 ? "wallA" : "wallB", tint: copper)
        }

        // the floor: packed terracotta sand wall to wall, and his woven tile as the 4.5 m path down the middle
        let frows = Int(len / 0.5)
        func strip(_ w0: @escaping (Float) -> Float, y: Float, uv: @escaping (V, Float, Float) -> SIMD2<Float>) -> P1Mesh {
            var m = P1Mesh()
            m.grid(frows, 8, facing: { _, _, _ in [0, 1, 0] }) { j, i in
                let s = Float(j) * 0.5, f = Float(i) / 8, q = self.at(s) + self.normal(s) * (-w0(s) * (1 - f) + w0(s) * f) + [0, y, 0]
                return (q, uv(q, s, f))
            }
            return m
        }
        let floorM = strip({ self.half($0) + 0.8 }, y: 0, uv: { q, _, _ in [q.x / 2.5, q.z / 2.5] })
        _ = try await add(floorM, sand, shape: try await staticShape(floorM), name: "floor", tint: [1, 0.96, 0.9])
        _ = try await add(strip({ _ in T.halfPath }, y: 0.012, uv: { _, s, f in [f, s / (T.halfPath * 2)] }), woven, name: "path")

        // the two end walls: the tunnel from room 1 comes through a round hole; the exit is a 10 m by 8 m arch
        func holeWall(_ cx: Float, _ z: Float, _ hw: Float, _ hh: Float, _ w: Float, facing: V, name: String) async throws {
            var m = P1Mesh()
            m.grid(1, 48, facing: { _, _, _ in facing }) { j, i in
                let th = Float(i) / 48 * .pi, dx = cos(th), dy = sin(th)
                if j == 0 { return ([cx + dx * hw, dy * hh, z], [(cx + dx * hw) / 3, dy * hh / 3]) }
                let tx = abs(dx) < 1e-4 ? 1e9 : w / abs(dx), ty = dy < 1e-4 ? 1e9 : T.wallH / dy, t = min(tx, ty)
                return ([cx + dx * t, min(T.wallH, dy * t), z], [(cx + dx * t) / 3, min(T.wallH, dy * t) / 3])
            }
            _ = try await add(m, rock, shape: try await staticShape(m), name: name, tint: copper)
        }
        try await holeWall(0, 0, 6, 6, 6.6, facing: [0, 0, -1], name: "wallNorth")
        let end = at(endS)
        try await holeWall(end.x, end.z, 4.93, 7.93, 5.6, facing: [0, 0, 1], name: "wallSouth")

        // the exit tunnel: 12 m deep, the lining turning from copper sandstone to matte red brick (#8B2500) toward room 3
        let copperC: V = [0.78, 0.49, 0.28], red: V = [0.55, 0.145, 0]
        for seg in 0..<4 {
            var m = P1Mesh(); let z0 = end.z - Float(seg) * 3, z1 = z0 - 3
            m.grid(6, 40, facing: { _, _, c in [end.x - c.x, 4 - c.y, 0] }) { j, i in
                let th = Float(i) / 40 * .pi, z = z0 + (z1 - z0) * Float(j) / 6
                return ([end.x + cos(th) * 5, sin(th) * 8, z], [Float(i) / 40 * 20.9 / 3, abs(z - end.z) / 3])
            }
            let k = Self.sm(2, 11, Float(seg) * 3 + 1.5), c = copperC + (red - copperC) * k
            var lm = rock; lm.baseColor.tint = P1Materials.ui(simd_clamp(c * 1.5, .zero, [1, 1, 1]))
            _ = try await add(m, lm, shape: try await staticShape(m), name: "exitLining\(seg)")
        }
        let tfloor = P1Mesh.box([10, 0.5, 12.5], at: [end.x, -0.25, end.z - 6], metres: 2.5)
        _ = try await add(tfloor, sand, shape: .generateBox(size: [10, 0.5, 12.5]).offsetBy(translation: [end.x, -0.25, end.z - 6]), name: "exitFloor")

        // set pieces, all seated: his heart mark in gold on a sandstone stele three times along the walls; five fallen boulders bedded in sand
        var gold = PhysicallyBasedMaterial()
        gold.baseColor = .init(tint: P1Materials.ui([0.89, 0.65, 0.3]), texture: P1Materials.tx(try await tex("plw-p2-heart", "png", .color)))
        gold.metallic = .init(floatLiteral: 1); gold.roughness = .init(floatLiteral: 0.24)
        gold.blending = .transparent(opacity: .init(floatLiteral: 1)); gold.opacityThreshold = 0.5; gold.faceCulling = .none
        let hw: Float = 2.8, hh = hw / 1.232, sw = hw + 0.6, sh = hh + 0.7
        for (s, side) in [(Float(9), Float(1)), (24, -1), (38, 1)] {
            let nn = normal(s) * side, b = at(s) + nn * (half(s) - 0.55), holder = Entity()
            holder.position = b; holder.orientation = simd_quatf(from: [0, 0, 1], to: -nn)   // local +Z looks onto the path
            let baseM = P1Mesh.box([sw + 0.4, 0.45, 0.8], at: [0, 0.225, -0.1], metres: 3), steleM = P1Mesh.box([sw, sh, 0.32], at: [0, 0.45 + sh / 2, 0], metres: 3)
            for (mesh, size, c, nm) in [(baseM, V(sw + 0.4, 0.45, 0.8), V(0, 0.225, -0.1), "heartBase"), (steleM, V(sw, sh, 0.32), V(0, 0.45 + sh / 2, 0), "heartStele")] {
                guard let r = mesh.resource() else { throw P1Materials.Failure.missing(nm) }
                let e = ModelEntity(mesh: r, materials: [sand]); e.name = nm
                e.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: c)])); e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
                holder.addChild(e)
            }
            for k in 0..<3 {   // thin alpha-cut layers give the strokes their depth, 6 cm proud
                let pl = ModelEntity(mesh: .generatePlane(width: hw, height: hh), materials: [gold]); pl.position = [0, 0.45 + sh / 2, 0.16 + 0.005 + Float(k) * 0.02]; holder.addChild(pl)
            }
            root.addChild(holder)
        }
        var seed: UInt32 = 1234
        func rnd() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed >> 8) / Float(1 << 24) }
        for (s, side) in [(Float(14), Float(-1)), (17, 1), (27, 1), (33, -1), (45, -1)] {
            let sz = 0.8 + rnd() * 1.3, nn = normal(s) * side, b = at(s) + nn * (half(s) - sz * 0.45), ph1 = rnd() * 6
            let prof: [SIMD2<Float>] = (0...8).map { k in let t = Float(k) / 8; return [max(0.01, sz * 0.62 * sin(.pi * t) * (1 + 0.18 * sin(t * 9 + ph1))), t * sz * 0.9] }
            let rock3 = P1Mesh.lathe(prof, segments: 20, metres: 2)
            guard let rr = rock3.resource() else { throw P1Materials.Failure.missing("boulder") }
            let e = ModelEntity(mesh: rr, materials: [rock]); e.name = "boulder"
            e.position = [b.x, -sz * 0.3, b.z]; e.orientation = simd_quatf(angle: rnd() * 6, axis: [0, 1, 0])
            e.components.set(CollisionComponent(shapes: [try await ShapeResource.generateConvex(from: rr)])); e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
            root.addChild(e)
        }

        // the Curve ground: white on indigo, hidden until the Look, then spreading from his feet (one metre rings switched on as the radius grows)
        let nr = Int(T.lookRadius)
        for k in 0..<nr {
            var m = P1Mesh(); let r0 = max(Float(k), 0.001), r1 = Float(k + 1)
            m.grid(1, 96, facing: { _, _, _ in [0, 1, 0] }) { j, i in
                let a = Float(i) / 96 * 2 * .pi, r = j == 0 ? r0 : r1, x = sin(a) * r, z = cos(a) * r
                return ([x, 0, z], [(x + self.clearC.x) / 3, (z + self.clearC.z) / 3])
            }
            let e = ModelEntity(mesh: m.resource() ?? .generatePlane(width: 0.1, height: 0.1), materials: [ground]); e.name = "ground\(k)"
            e.position = clearC + [0, 0.03, 0]; e.isEnabled = false; e.components.set(OpacityComponent(opacity: 0))
            rings.append(e); root.addChild(e)
        }
        var em = UnlitMaterial(); em.color = .init(tint: UIColor(red: 0.79, green: 0.82, blue: 1, alpha: 1))
        edge.components.set(ModelComponent(mesh: P1Mesh.sweep((0...96).map { k in let t = Float(k) / 96 * 2 * .pi; return [sin(t), 0.04, cos(t)] }, section: P1Mesh.circle(6), scale: { _ in [0.06, 0.06] }).resource() ?? .generatePlane(width: 0.1, height: 0.1), materials: [em]))
        edge.position = clearC; edge.isEnabled = false; root.addChild(edge)

        // the keys: his glyph silhouettes in gold, upright over a soft halo
        var halo = UnlitMaterial(); halo.color = .init(tint: .white, texture: P1Materials.tx(try await tex("plw-p1-halo", "png", .color))); halo.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let aspect: [PLWGlyph: Float] = [.glyphGuy: 256.0 / 640, .money: 484.0 / 640, .smiley: 521.0 / 640]
        for g in glyphs {
            var m = UnlitMaterial(); m.faceCulling = .none
            let file = g.glyph == .smiley ? "plw-p2-key-smiley" : "plw-p1-key-\(g.glyph.rawValue)"
            m.color = .init(tint: .white, texture: P1Materials.tx(try await tex(file, "png", .color))); m.blending = .transparent(opacity: .init(floatLiteral: 1))
            let k = Entity(), h: Float = 0.9
            k.components.set(ModelComponent(mesh: .generatePlane(width: h * (aspect[g.glyph] ?? 0.5), height: h), materials: [m]))
            let glow = Entity(); glow.components.set(ModelComponent(mesh: .generatePlane(width: 1.6, height: 1.6), materials: [halo])); glow.components.set(BillboardComponent())
            let holder = Entity(); holder.position = g.position; holder.addChild(k); holder.addChild(glow)
            root.addChild(holder); keyEntities[g.key.slot] = holder
        }

        // light: golden-hour sun through the slit (soft shadows), a warm bounce along the canyon, copper haze is the integrator's fog
        let sun = Entity()
        var dl = DirectionalLightComponent(); dl.color = UIColor(red: 1, green: 0.69, blue: 0.4, alpha: 1); dl.intensity = T.sunLux
        sun.components.set(dl); sun.components.set(DirectionalLightComponent.Shadow())
        sun.look(at: clearC + [0.4, -0.8, -0.3], from: clearC, relativeTo: nil); root.addChild(sun); lights.append((sun, [1, 0.69, 0.4], T.sunLux))
        for s in stride(from: Float(8), through: endS, by: 14) {
            var pl = PointLightComponent(); pl.color = UIColor(red: 0.83, green: 0.55, blue: 0.33, alpha: 1); pl.intensity = T.fillLumens; pl.attenuationRadius = 22
            let e = Entity(); e.components.set(pl); e.position = at(s) + [0, 7, 0]; root.addChild(e); lights.append((e, [0.83, 0.55, 0.33], T.fillLumens))
        }
        restore(saved)
    }

    // MARK: runtime

    func restore(_ save: PLWSave) {
        saved = save; done = save.completed.contains(.p2); lookT = 0; radius = done ? Tune.lookRadius : 0
        taken = Set(glyphs.filter { save.glyphs.contains($0.key) }.map { $0.key.slot })
        for (slot, e) in keyEntities { e.isEnabled = !taken.contains(slot) }
        updateRings()
    }

    private func updateRings() {
        for (k, e) in rings.enumerated() {
            let f = min(1, max(0, radius - Float(k))); e.isEnabled = f > 0.001
            e.components.set(OpacityComponent(opacity: f))
        }
        edge.isEnabled = !done && radius > 1.01; edge.scale = [radius, 1, radius]
    }

    func step(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        elapsed += f.dt
        for e in keyEntities.values where e.isEnabled { e.orientation = e.orientation * simd_quatf(angle: f.dt * 0.9, axis: [0, 1, 0]) }
        func say(_ id: String, _ line: String) { if said.insert(id).inserted { out.append(.caption(line)) } }

        if f.actPressed, let g = glyphs.first(where: { !taken.contains($0.key.slot) && simd_length(SIMD2(f.position.x - $0.position.x, f.position.z - $0.position.z)) < 1.8 && abs(f.position.y + 1 - $0.position.y) < 2.4 }) {
            taken.insert(g.key.slot); keyEntities[g.key.slot]?.isEnabled = false; out.append(.collect(g.key))
        }

        let near = simd_length(SIMD2(f.position.x - clearC.x, f.position.z - clearC.z)) < 3
        if near && !done { say("look", "Hold ACT to look.") }
        let active = near && f.actHeld && !done
        lookT = active ? min(Tune.lookSeconds, lookT + f.dt) : max(0, lookT - f.dt * 1.5)
        let e = Self.sm(0, 1.5, lookT)
        if e > 0 && !done {   // over the shoulder: 3.5 m behind, 1.6 m up, a touch higher than the trailing view
            var fwd = V(f.lookDirection.x, 0, f.lookDirection.z); fwd = simd_length(fwd) > 1e-3 ? simd_normalize(fwd) : [0, 0, -1]
            out.append(.camera(position: f.position - fwd * 3.5 + [0, 1.6, 0], target: f.position + [0, 1.3, 0], weight: e)); cameraOn = true
        } else if cameraOn {
            out.append(.camera(position: f.position, target: f.position, weight: 0)); cameraOn = false
        }
        if active {
            radius = max(radius, 1 + (Tune.lookRadius - 1) * Self.sm(0, Tune.lookSeconds, lookT))
            updateRings()
            if radius >= Tune.lookRadius - 0.1 {
                done = true; radius = Tune.lookRadius; updateRings()
                out += [.completeMoment(.p2), .checkpoint(.p2, port: "start")]
                say("done", "The ground answered.")
            }
        }
        return out
    }

    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] { [] }   // all reactions are distance checks in `step`

    func apply(_ look: PLWLook) {
        for l in lights {
            let g = simd_dot(l.color, [0.2126, 0.7152, 0.0722]), c = simd_clamp(V(repeating: g) + (l.color - V(repeating: g)) * look.saturation, .zero, V(repeating: 1))
            if var s = l.e.components[DirectionalLightComponent.self] { s.color = P1Materials.ui(c); s.intensity = l.lumens * look.exposure; l.e.components.set(s) }
            if var p = l.e.components[PointLightComponent.self] { p.color = P1Materials.ui(c); p.intensity = l.lumens * look.exposure; l.e.components.set(p) }
        }
        for t in tinted {   // chroma of the stone tints follows the look's saturation, never toward black
            let g = simd_dot(t.tint, [0.2126, 0.7152, 0.0722]), c = V(repeating: g) + (t.tint - V(repeating: g)) * look.saturation
            var m = t.m; m.baseColor.tint = P1Materials.ui(simd_clamp(c, .zero, V(repeating: 1)))
            if var model = t.e.model { model.materials = [m]; t.e.model = model }
        }
    }

    func unload() {
        root.children.removeAll(); rings.removeAll(); keyEntities.removeAll(); lights.removeAll(); tinted.removeAll()
        lookT = 0; radius = 0; done = false; cameraOn = false; elapsed = 0; said.removeAll(); taken.removeAll()
        edge = Entity()
    }
}
