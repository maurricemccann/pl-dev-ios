import RealityKit
import UIKit
import simd

/// Page 3, THE CROWD (purple, red brick): the maze of the doubters. A 60 x 40 m brick maze on a 5 m grid that rides a smooth wave so every lane sweeps; his curve
/// tile laid only on the true way; the curve hero engraved into every wall; his stick people packing the dead ends and standing across the true way at two gates
/// that open only when he holds ACT to raise the dream (they step to the walls); his folded drawing under a mossy bench in the deepest dead end; a purple tunnel on.
/// Numbers and the maze seed are the web build's (`room3.js`). The room's origin is where room 2's tunnel arrives; rows run toward -Z.
/// Left out: the web's low arch and wall walk (the controller has no crouch or climb verb), the carved silhouette slices behind each figure.
/// Unproven: lumens (`Tune`), kinematic feel at the gates, how the unlit paper-white faces read in the dark maze, wall collision cost (one static mesh).
@MainActor final class PLWRoomP3: PLWRoom {
    enum Tune {
        static let cell: Float = 5, wt: Float = 1, wh: Float = 9, partSeconds: Float = 1.8, partReach: Float = 9
        static let sunLux: Float = 2_500, guideLumens: Float = 14_000, gateLumens: Float = 20_000
    }
    typealias V = SIMD3<Float>
    private struct Doubter { let e: Entity, home: V, out: V, gate: Int, phase: Float }

    let id: PLWArea = .p3
    let root = Entity()
    private(set) var ports: [String: Transform] = [:]
    private(set) var route: [V] = []
    private(set) var triggers: [PLWTrigger] = []
    private(set) var glyphs: [PLWGlyphPlacement] = []

    private let maze = P3Maze()
    private var crowd: [Doubter] = []
    private var blockers: [Entity] = []
    private var gateCentre: [V] = []
    private var progress: [Float] = [0, 0], opened = [false, false], raiseSent: Float = -1
    private var keyEntities: [UInt8: Entity] = [:], lights: [(e: Entity, color: V, lumens: Float)] = []
    private var tinted: [(e: ModelEntity, m: PhysicallyBasedMaterial, tint: V)] = []
    private var elapsed: Float = 0, said: Set<String> = [], taken: Set<UInt8> = [], saved = PLWSave()

    // MARK: geometry of the bent grid

    private func cx(_ i: Int) -> Float { Float(i - P3Maze.entry) * Tune.cell }
    private func cz(_ j: Int) -> Float { -Tune.cell / 2 - Float(j) * Tune.cell }
    private static func sm(_ a: Float, _ b: Float, _ x: Float) -> Float { let k = min(max((x - a) / (b - a), 0), 1); return k * k * (3 - 2 * k) }
    /// The whole grid rides a wave (his ruling "the walls should be curved"); it fades out at the entry and exit rows.
    private func warp(_ x: Float, _ z: Float) -> V {
        let d = -z, f = 1.25 * Self.sm(0, 9, d) * Self.sm(0, 9, Float(P3Maze.nz) * Tune.cell - d)
        return [x + f * sin(z * 0.24 + 1.3), 0, z + f * sin(x * 0.24 + 0.4)]
    }
    private func cellCentre(_ i: Int, _ j: Int) -> V { warp(cx(i), cz(j)) }

    init() {
        let m = maze, nz = Float(P3Maze.nz), c = Tune.cell
        let xx = cx(P3Maze.exit), xz = -nz * c
        ports = ["start": Transform(translation: [0, 0, -3]), "entry": Transform(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]), translation: .zero),
                 "exit": Transform(translation: [xx, 0, xz - 10])]
        route = m.path.map { cellCentre($0.i, $0.j) } + [[xx, 0, xz - 10]]
        gateCentre = m.gates.map { cellCentre(m.path[$0].i, m.path[$0].j) }
        if gateCentre.count == 2 { ports["gate1"] = Transform(translation: gateCentre[0] + straightBack(m.gates[0])) }
        let s = m.secret
        glyphs = [PLWGlyphPlacement(key: PLWKey(page: .p3, slot: 0), glyph: .loveYourself, position: cellCentre(2, 3) + [0, 1.2, 0]),
                  PLWGlyphPlacement(key: PLWKey(page: .p3, slot: 1), glyph: .povertyToLuxury, position: cellCentre(7, 4) + [0, 1.2, 0]),
                  PLWGlyphPlacement(key: PLWKey(page: .p3, slot: 2), glyph: .money, position: cellCentre(s.i, s.j) + [0, 1.2, 0])]
        triggers = gateCentre.enumerated().map { PLWTrigger(id: "p3.gate\($0.offset)", center: $0.element + [0, 1, 0], yaw: 0, halfExtents: [Tune.partReach, 2, Tune.partReach]) }
            + glyphs.map { PLWTrigger(id: "p3.key\($0.key.slot)", center: $0.position, yaw: 0, halfExtents: [1.4, 1.6, 1.4]) }
    }
    /// A step back along the true way from gate k (so a checkpoint never lands inside the crowd).
    private func straightBack(_ k: Int) -> V {
        let a = maze.path[max(0, k - 2)], b = maze.path[k]
        return cellCentre(a.i, a.j) - cellCentre(b.i, b.j)
    }

    // MARK: load

    func load() async throws {
        let T = Tune.self, m = maze
        func tex(_ n: String, _ e: String, _ s: TextureResource.Semantic) async throws -> TextureResource { try await P1Materials.load(n, e, s) }
        func stone(_ prefix: String, _ set: String, tint: V, rough: Bool = true) async throws -> PhysicallyBasedMaterial {
            var mt = PhysicallyBasedMaterial()
            mt.baseColor = .init(tint: P1Materials.ui(tint), texture: P1Materials.tx(try await tex("plw-\(prefix)-\(set)-albedo", "jpg", .color)))
            mt.normal = .init(texture: P1Materials.tx(try await tex("plw-\(prefix)-\(set)-normal", "jpg", .normal)))
            if rough { mt.roughness = .init(scale: 1, texture: P1Materials.tx(try await tex("plw-\(prefix)-\(set)-rough", "jpg", .raw))) } else { mt.roughness = .init(floatLiteral: 0.6) }
            mt.metallic = .init(floatLiteral: 0)
            return mt
        }
        let brick = try await stone("p3", "brick", tint: [1.05, 0.95, 0.9]), cobble = try await stone("p3", "cobble", tint: [1, 1, 1])
        let woven = try await stone("p2", "woven", tint: [1, 1, 1], rough: false), moss = try await stone("p2", "sand", tint: [0.5, 0.62, 0.4])
        var hero = PhysicallyBasedMaterial()   // the curve hero: soot-dark cuts, alpha-tested, a hair proud of the brick
        hero.baseColor = .init(tint: .white, texture: P1Materials.tx(try await tex("plw-p3-hero", "png", .color)))
        hero.normal = .init(texture: P1Materials.tx(try await tex("plw-p3-hero-normal", "jpg", .normal)))
        hero.roughness = .init(floatLiteral: 0.92); hero.metallic = .init(floatLiteral: 0)
        hero.blending = .transparent(opacity: .init(floatLiteral: 1)); hero.opacityThreshold = 0.4; hero.faceCulling = .none

        func add(_ mesh: P1Mesh, _ mt: PhysicallyBasedMaterial, shape: ShapeResource? = nil, name: String, tint: V? = nil) async throws -> ModelEntity {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing(name) }
            let e = ModelEntity(mesh: r, materials: [mt]); e.name = name
            if let shape { e.components.set(CollisionComponent(shapes: [shape])); e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static)) }
            if let tint { tinted.append((e, mt, tint)) }
            root.addChild(e); return e
        }
        func staticShape(_ mesh: P1Mesh) async throws -> ShapeResource {
            guard let r = mesh.resource() else { throw P1Materials.Failure.missing("shape") }
            return try await ShapeResource.generateStaticMesh(from: r)
        }
        func solidBox(_ size: V, at c: V, name: String) -> Entity {   // an invisible static block
            let e = Entity(); e.name = name; e.position = c
            e.components.set(CollisionComponent(shapes: [.generateBox(size: size)])); e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
            root.addChild(e); return e
        }

        // the walls: curved brick 1 m thick and 9 m tall along every closed edge of the bent grid, a coping too steep to stand on, the hero engraved into both faces
        var walls = P1Mesh(), cuts = P1Mesh(), rl = P3Maze.LCG(s: 167)
        func wall(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
            let len = ((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0)).squareRoot(), ux = (x1 - x0) / len, uz = (z1 - z0) / len
            let n = max(2, Int(((len + T.wt) / 0.5).rounded(.up))), s0 = Float(rl.next()) * 9
            let pts: [V] = (0...n).map { k in let t = -T.wt / 2 + (len + T.wt) * Float(k) / Float(n); return warp(x0 + ux * t, z0 + uz * t) }
            let tg: [V] = pts.indices.map { k in let d = pts[min(n, k + 1)] - pts[max(0, k - 1)]; return simd_normalize(d + [1e-6, 0, 0]) }
            let nr: [V] = tg.map { [$0.z, 0, -$0.x] }
            var arc: [Float] = [0]; for k in 1...n { arc.append(arc[k - 1] + simd_distance(pts[k], pts[k - 1])) }
            func at(_ k: Int, _ side: Float, _ y: Float, _ push: Float = 0) -> V { pts[k] + nr[k] * (side * (T.wt / 2 + push)) + [0, y, 0] }
            for side: Float in [1, -1] {
                walls.grid(n, 1, facing: { k, _, _ in nr[k] * side }) { k, i in (at(k, side, i == 0 ? 0 : T.wh), [arc[k] / 1.5, i == 0 ? 0 : T.wh / 1.5]) }
                cuts.grid(n, 1, facing: { k, _, _ in nr[k] * side }) { k, i in (at(k, side, i == 0 ? 0 : T.wh, 0.015), [s0 + arc[k] / 9, i == 0 ? 0 : 1]) }
                walls.grid(n, 1, facing: { k, _, _ in V(0, 1, 0) + nr[k] * side }) { k, i in    // the coping: a ridge 1 m over the wall top
                    (i == 0 ? at(k, side, T.wh) : pts[k] + [0, T.wh + 1, 0], [arc[k] / 1.5, i == 0 ? 0 : 0.75])
                }
            }
            for (k, sgn) in [(0, Float(-1)), (n, Float(1))] {   // the ends
                walls.grid(1, 1, facing: { _, _, _ in tg[k] * sgn }) { j, i in (at(k, i == 0 ? -1 : 1, j == 0 ? 0 : T.wh), [Float(i) * T.wt / 1.5, j == 0 ? 0 : T.wh / 1.5]) }
            }
        }
        let nx = P3Maze.nx, nz = P3Maze.nz, ie = P3Maze.entry, c = T.cell
        for i in 0..<nx { for j in 0..<nz {
            let X = cx(i), Z = cz(j)
            if i < nx - 1 && !m.east[i][j] { wall(X + c / 2, Z + c / 2, X + c / 2, Z - c / 2) }
            if j < nz - 1 && !m.south[i][j] { wall(X - c / 2, Z - c / 2, X + c / 2, Z - c / 2) }
            if j == 0 && abs(i - ie) > 1 { wall(X - c / 2, 0, X + c / 2, 0) }                    // the near edge, except the plaza (its wall carries the tunnel mouth)
            if j == nz - 1 && i != P3Maze.exit { wall(X - c / 2, Z - c / 2, X + c / 2, Z - c / 2) }
        } }
        for j in 0..<nz { wall(cx(0) - c / 2, cz(j) + c / 2, cx(0) - c / 2, cz(j) - c / 2); wall(cx(nx - 1) + c / 2, cz(j) + c / 2, cx(nx - 1) + c / 2, cz(j) - c / 2) }
        _ = try await add(walls, brick, shape: try await staticShape(walls), name: "mazeWalls", tint: [1.05, 0.95, 0.9])
        _ = try await add(cuts, hero, name: "curveHero")

        // the floor: wet cobble everywhere, his curve tile only on the true way (dead ends stay bare and fall into shadow)
        let fw = Float(nx) * c + 4, fd = Float(nz) * c + 4
        let floorC: V = [(cx(0) + cx(nx - 1)) / 2, -0.25, -Float(nz) * c / 2]
        _ = try await add(.box([fw, 0.5, fd], at: floorC, metres: 2), cobble, shape: .generateBox(size: [fw, 0.5, fd]).offsetBy(translation: floorC), name: "mazeFloor")
        var tiles = P1Mesh()
        for p in m.path {
            tiles.grid(8, 8, facing: { _, _, _ in [0, 1, 0] }) { a, b in
                let q = self.warp(self.cx(p.i) - c / 2 + c * Float(b) / 8, self.cz(p.j) + c / 2 - c * Float(a) / 8)
                return ([q.x, 0.012, q.z], [q.x / 2.5, q.z / 2.5])
            }
        }
        _ = try await add(tiles, woven, name: "trueWay")

        // brick arches over the true way on its straight runs, sprung from the walls at 4.2 m
        var arches = P1Mesh()
        for (k, p) in m.path.enumerated() {
            guard let dir = m.straight(k), k % 3 == 0, !m.gates.contains(k) else { continue }
            let ctr = cellCentre(p.i, p.j), along: V = dir == "z" ? [0, 0, 1] : [1, 0, 0], across: V = dir == "z" ? [1, 0, 0] : [0, 0, 1], r0 = c / 2 - T.wt / 2 + 0.3
            let arc: [V] = (0...16).map { n in let a = Float.pi * Float(n) / 16; return ctr + across * (cos(a) * r0) + [0, 4.2 + sin(a) * r0, 0] }
            arches.merge(.sweep(arc, section: P1Mesh.slab, scale: { _ in [0.45, 0.3] }, side: along, metres: 1.5))
        }
        _ = try await add(arches, brick, name: "arches", tint: [1.05, 0.95, 0.9])

        // the two ends: room 2's tunnel mouth (10 x 8 m) through the plaza wall; a 4 x 5 m throat and the purple tunnel on the far row
        func holeWall(_ x0: Float, _ z: Float, _ hw: Float, _ hh: Float, _ w: Float, facing: V, name: String) async throws {
            var mm = P1Mesh()
            mm.grid(1, 40, facing: { _, _, _ in facing }) { j, i in
                let th = Float(i) / 40 * .pi, dx = cos(th), dy = sin(th)
                if j == 0 { return ([x0 + dx * hw, dy * hh, z], [(x0 + dx * hw) / 1.5, dy * hh / 1.5]) }
                let tx = abs(dx) < 1e-4 ? 1e9 : w / abs(dx), ty = dy < 1e-4 ? 1e9 : T.wh / dy, t = min(tx, ty), y = min(T.wh, dy * t)
                return ([x0 + dx * t, y, z], [(x0 + dx * t) / 1.5, y / 1.5])
            }
            _ = try await add(mm, brick, shape: try await staticShape(mm), name: name, tint: [1.05, 0.95, 0.9])
        }
        try await holeWall(0, 0, 4.93, 7.93, c * 1.5, facing: [0, 0, -1], name: "mazeEntry")
        let xx = cx(P3Maze.exit), xz = -Float(nz) * c
        try await holeWall(xx, xz, 1.95, 4.95, c / 2, facing: [0, 0, 1], name: "mazeThroat")
        let plum: V = [0.18, 0.03, 0.33], brickC: V = [1, 0.8, 0.7]
        for seg in 0..<4 {   // brick to matte deep purple plaster over 10 m
            var tm = P1Mesh(); let z0 = xz - Float(seg) * 2.5, z1 = z0 - 2.5
            tm.grid(5, 32, facing: { _, _, ctr in [xx - ctr.x, 2.5 - ctr.y, 0] }) { j, i in
                let th = Float(i) / 32 * .pi, z = z0 + (z1 - z0) * Float(j) / 5
                return ([xx + cos(th) * 2, sin(th) * 5, z], [Float(i) / 32 * 11 / 1.5, (xz - z) / 1.5])
            }
            let k = Self.sm(1, 8, Float(seg) * 2.5 + 1.25), col = brickC + (plum * 2.2 - brickC) * k
            var lm = brick; lm.baseColor.tint = P1Materials.ui(simd_clamp(col, .zero, [1, 1, 1]))
            _ = try await add(tm, lm, shape: try await staticShape(tm), name: "purpleTunnel\(seg)")
        }
        let tf = P1Mesh.box([4, 0.5, 10.5], at: [xx, -0.25, xz - 5], metres: 2)
        _ = try await add(tf, cobble, shape: .generateBox(size: [4, 0.5, 10.5]).offsetBy(translation: [xx, -0.25, xz - 5]), name: "purpleFloor")

        // a dark lid and skirt over the maze so no sky shows from the lanes (unlit, copper-dark)
        var lid = P1Mesh(); let lw = fw + 26, ly: Float = 16, lc: V = [floorC.x + 2.5, 0, floorC.z]
        lid.merge(.box([lw, 0.2, fd], at: [lc.x, ly, lc.z]))
        for (sz, off) in [(Float(1), fd / 2), (-1, -fd / 2)] { lid.merge(.box([lw, ly - T.wh, 0.2], at: [lc.x, (ly + T.wh) / 2, lc.z + off + sz * 0.1])) }
        for sx: Float in [-1, 1] { lid.merge(.box([0.2, ly - T.wh, fd], at: [lc.x + sx * lw / 2, (ly + T.wh) / 2, lc.z])) }
        var lm = UnlitMaterial(color: UIColor(red: 0.46, green: 0.19, blue: 0.13, alpha: 1)); lm.faceCulling = .none
        if let r = lid.resource() { let e = ModelEntity(mesh: r, materials: [lm]); e.name = "lid"; root.addChild(e) }

        // the secret: a mossy stone bench against the back wall of the deepest dead end, his folded drawing beneath it, catching a glint
        let sx = m.secret.i, sj = m.secret.j, bx = Float(-(m.secretOpening.i - sx)), bz = Float(m.secretOpening.j - sj)   // away from the opening (rows run toward -z)
        let B = warp(cx(sx) + bx * 1.35, cz(sj) + bz * 1.35), along = bx != 0
        var bench = P1Mesh.box(along ? [0.6, 0.14, 1.8] : [1.8, 0.14, 0.6], at: B + [0, 0.43, 0], metres: 1.5)
        for t: Float in [-0.7, 0.7] { bench.merge(.box(along ? [0.5, 0.36, 0.22] : [0.22, 0.36, 0.5], at: B + [along ? 0 : t, 0.18, along ? t : 0], metres: 1.5)) }
        _ = try await add(bench, moss, shape: .generateBox(size: along ? [0.6, 0.5, 1.8] : [1.8, 0.5, 0.6]).offsetBy(translation: B + [0, 0.25, 0]), name: "bench", tint: [0.5, 0.62, 0.4])
        var paper = PhysicallyBasedMaterial()
        paper.baseColor = .init(tint: .white, texture: .init(try await tex("plw-p3-paper", "jpg", .color))); paper.roughness = .init(floatLiteral: 0.9); paper.metallic = .init(floatLiteral: 0)
        paper.emissiveColor = .init(color: P1Materials.ui([0.08, 0.06, 0.03])); paper.emissiveIntensity = 1; paper.faceCulling = .none
        let pe = ModelEntity(mesh: .generatePlane(width: 0.3, depth: 0.21), materials: [paper]); pe.name = "foldedDrawing"
        pe.position = B + [0.05, 0.02, 0.1]; pe.orientation = simd_quatf(angle: 0.4, axis: [0, 1, 0]); root.addChild(pe)

        // the doubters: HIS stick people from plate 3 (never redrawn), billboards that face him; nine across each gate, six packed into each dead end
        let aspects: [Float] = [436 / 628, 530 / 623, 491 / 608, 361 / 587, 679 / 612, 760 / 640, 927 / 612]
        var folk: [UnlitMaterial] = []
        for k in 0..<7 { var fm = UnlitMaterial(); fm.color = .init(tint: .white, texture: .init(try await tex("plw-p3-folk\(k + 1)", "png", .color))); fm.blending = .transparent(opacity: .init(floatLiteral: 1)); fm.faceCulling = .none; folk.append(fm) }
        var rc = P3Maze.LCG(s: 303)
        func person(_ gx: Float, _ gz: Float, _ ox: Float, _ oz: Float, gate: Int) {
            let hp = warp(gx, gz), op = warp(ox, oz), k = (crowd.count * 3 + Int(rc.next() * 7)) % 7, h = Float(2.1 + rc.next() * 0.5) * 0.8
            let e = Entity(), body = ModelEntity(mesh: .generatePlane(width: h * aspects[k] * 1.25, height: h), materials: [folk[k]])
            body.position = [0, h / 2, 0]; e.addChild(body); e.position = hp; root.addChild(e)
            crowd.append(Doubter(e: e, home: hp, out: op, gate: gate, phase: Float(rc.next() * 6.28)))
        }
        for (g, k) in m.gates.enumerated() {
            let p = m.path[k], dir = m.straight(k) ?? "z", X = cx(p.i), Z = cz(p.j)
            for a: Float in [-1.3, 0, 1.3] { for b: Float in [-1.25, 0, 1.25] {
                let jb = b + Float(rc.next() - 0.5) * 0.25, ja = a + Float(rc.next() - 0.5) * 0.3, side: Float = b == 0 ? (crowd.count % 2 == 1 ? 1 : -1) : (b < 0 ? -1 : 1), ob = side * 1.55
                if dir == "z" { person(X + jb, Z + ja, X + ob, Z + ja, gate: g) } else { person(X + ja, Z + jb, X + ja, Z + ob, gate: g) }
            } }
            // the gate: an invisible block across the lane that opens with the crowd
            let across: V = dir == "z" ? [4.6, 3, 3.6] : [3.6, 3, 4.6]
            blockers.append(solidBox(across, at: cellCentre(p.i, p.j) + [0, 1.5, 0], name: "gate\(g)"))
            var pl = PointLightComponent(); pl.color = UIColor(red: 0.5, green: 0.12, blue: 0.08, alpha: 1); pl.intensity = T.gateLumens; pl.attenuationRadius = 11
            let le = Entity(); le.components.set(pl); le.position = cellCentre(p.i, p.j) + [0, 3.2, 0]; root.addChild(le); lights.append((le, [0.5, 0.12, 0.08], T.gateLumens))
        }
        for end in m.crowdEnds {
            let X = cx(end.i), Z = cz(end.j)
            for n in 0..<6 {
                let x = X + Float(n % 3 - 1) * 1.15 + Float(rc.next() - 0.5) * 0.3, z = Z + Float(n / 3) * 1.3 - 0.65 + Float(rc.next() - 0.5) * 0.3
                person(x, z, x, z, gate: -1)
            }
            _ = solidBox([4.4, 3, 4.4], at: cellCentre(end.i, end.j) + [0, 1.5, 0], name: "deadEnd")   // packed solid: no way in
        }

        // the keys: his glyph silhouettes in gold, upright over a soft halo
        var halo = UnlitMaterial(); halo.color = .init(tint: .white, texture: .init(try await tex("plw-p1-halo", "png", .color))); halo.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let ga: [PLWGlyph: Float] = [.loveYourself: 593.0 / 640, .money: 484.0 / 640, .povertyToLuxury: 0.8]
        for g in glyphs {
            var km = UnlitMaterial(); km.faceCulling = .none
            km.color = .init(tint: .white, texture: .init(try await tex(g.glyph == .povertyToLuxury ? "plw-p1-key-love-yourself" : "plw-p1-key-\(g.glyph.rawValue)", "png", .color)))
            km.blending = .transparent(opacity: .init(floatLiteral: 1))
            let k = Entity(), h: Float = 0.9
            k.components.set(ModelComponent(mesh: .generatePlane(width: h * (ga[g.glyph] ?? 0.7), height: h), materials: [km]))
            let glow = Entity(); glow.components.set(ModelComponent(mesh: .generatePlane(width: 1.6, height: 1.6), materials: [halo])); glow.components.set(BillboardComponent())
            let holder = Entity(); holder.position = g.position; holder.addChild(k); holder.addChild(glow)
            root.addChild(holder); keyEntities[g.key.slot] = holder
        }

        // light: a dim crimson key, the gold-pink guide along the true way (the maze's reading: follow the light), the gates' own red glow
        let sun = Entity(); var dl = DirectionalLightComponent(); dl.color = UIColor(red: 0.55, green: 0.11, blue: 0, alpha: 1); dl.intensity = T.sunLux
        sun.components.set(dl); sun.components.set(DirectionalLightComponent.Shadow()); sun.look(at: [0.1, -0.9, 0.3], from: .zero, relativeTo: nil); root.addChild(sun); lights.append((sun, [0.55, 0.11, 0], T.sunLux))
        for k in stride(from: 1, to: m.path.count - 1, by: 4) {
            var pl = PointLightComponent(); pl.color = UIColor(red: 1, green: 0.62, blue: 0.45, alpha: 1); pl.intensity = T.guideLumens; pl.attenuationRadius = 12
            let le = Entity(); le.components.set(pl); le.position = cellCentre(m.path[k].i, m.path[k].j) + [0, 3.5, 0]; root.addChild(le); lights.append((le, [1, 0.62, 0.45], T.guideLumens))
        }
        restore(saved)
    }

    // MARK: runtime

    func restore(_ save: PLWSave) {
        saved = save
        let flags = save.roomFlags[PLWArea.p3.rawValue] ?? [], all = save.completed.contains(.p3)
        opened = [all || flags.contains("gate0"), all || flags.contains("gate1")]; progress = opened.map { $0 ? 1 : 0 }
        for (g, b) in blockers.enumerated() where opened[g] { b.components.remove(CollisionComponent.self); b.components.remove(PhysicsBodyComponent.self) }
        taken = Set(glyphs.filter { save.glyphs.contains($0.key) }.map { $0.key.slot })
        for (slot, e) in keyEntities { e.isEnabled = !taken.contains(slot) }
        place(0)
    }

    private func place(_ t: Float) {
        for d in crowd {
            let p = d.gate >= 0 ? progress[d.gate] : 0, e = p * p * (3 - 2 * p)
            d.e.position = d.home + (d.out - d.home) * e
            _ = t
        }
    }

    func step(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        elapsed += f.dt
        for e in keyEntities.values where e.isEnabled { e.orientation = e.orientation * simd_quatf(angle: f.dt * 0.9, axis: [0, 1, 0]) }
        func say(_ id: String, _ line: String) { if said.insert(id).inserted { out.append(.caption(line)) } }
        if elapsed > 1.5 { say("way", "Find the way through.") }

        if f.actPressed, let g = glyphs.first(where: { !taken.contains($0.key.slot) && simd_length(SIMD2(f.position.x - $0.position.x, f.position.z - $0.position.z)) < 1.8 && abs(f.position.y + 1 - $0.position.y) < 2.4 }) {
            taken.insert(g.key.slot); keyEntities[g.key.slot]?.isEnabled = false; out.append(.collect(g.key))
        }

        // raising the dream at a gate: hold ACT within reach and the crowd leans back and steps to the walls
        var raise: Float = 0
        for g in 0..<min(2, gateCentre.count) where !opened[g] {
            let d = simd_length(SIMD2(f.position.x - gateCentre[g].x, f.position.z - gateCentre[g].z))
            if d < Tune.partReach { say("raise", "Hold ACT and raise the dream.") }
            if d < Tune.partReach && f.actHeld { progress[g] = min(1, progress[g] + f.dt / Tune.partSeconds); raise = max(raise, progress[g]) }
            else { progress[g] = max(0, progress[g] - f.dt * 0.8) }
            if progress[g] >= 1 {
                opened[g] = true; blockers[g].components.remove(CollisionComponent.self); blockers[g].components.remove(PhysicsBodyComponent.self)
                out.append(.roomFlag(.p3, "gate\(g)")); say("part\(g)", "The crowd steps back.")
                if g == 0 { out.append(.checkpoint(.p3, port: "gate1")) }
                if g == 1 { out += [.completeMoment(.p3), .checkpoint(.p3, port: "exit")] }
            }
        }
        if abs(raise - raiseSent) > 0.02 { raiseSent = raise; out.append(.raiseDream(raise)) }

        for d in crowd {   // sway, and face him (yaw only)
            let p = d.gate >= 0 ? progress[d.gate] : 0, e = p * p * (3 - 2 * p)
            d.e.position = d.home + (d.out - d.home) * e
            let to = f.position - d.e.position, yaw = atan2(to.x, to.z), roll = sin(elapsed * 2 * .pi * 0.8 + d.phase) * 0.05
            d.e.orientation = simd_quatf(angle: yaw + (d.gate >= 0 ? e * 0.26 : 0), axis: [0, 1, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1])
        }
        return out
    }

    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] { [] }   // reactions are distance checks in `step`

    func apply(_ look: PLWLook) {
        for l in lights {
            let g = simd_dot(l.color, [0.2126, 0.7152, 0.0722]), c = simd_clamp(V(repeating: g) + (l.color - V(repeating: g)) * look.saturation, .zero, V(repeating: 1))
            if var s = l.e.components[DirectionalLightComponent.self] { s.color = P1Materials.ui(c); s.intensity = l.lumens * look.exposure; l.e.components.set(s) }
            if var p = l.e.components[PointLightComponent.self] { p.color = P1Materials.ui(c); p.intensity = l.lumens * look.exposure; l.e.components.set(p) }
        }
        for t in tinted {
            let g = simd_dot(t.tint, [0.2126, 0.7152, 0.0722]), c = V(repeating: g) + (t.tint - V(repeating: g)) * look.saturation
            var mt = t.m; mt.baseColor.tint = P1Materials.ui(simd_clamp(c, .zero, V(repeating: 1)))
            if var model = t.e.model { model.materials = [mt]; t.e.model = model }
        }
    }

    func unload() {
        root.children.removeAll(); crowd.removeAll(); blockers.removeAll(); keyEntities.removeAll(); lights.removeAll(); tinted.removeAll()
        progress = [0, 0]; opened = [false, false]; raiseSent = -1; elapsed = 0; said.removeAll(); taken.removeAll()
    }
}
