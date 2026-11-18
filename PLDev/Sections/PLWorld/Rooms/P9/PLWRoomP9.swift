import Foundation
import RealityKit
import simd

/// Page 9, The Rising. Local frame: the way in is the doorway at the origin (the "start" port, facing -Z), the way out is the doorway at z = -64 (the "exit" port).
/// A crater of pale stone in the page hue round HIS hill (dark indigo skin, his white curve lines). A dim gold line climbs the slope to the summit stone; standing there
/// lifts the dream, the camera pulls back and the paradise valley (a view, not a place) goes from grey to colour. That is the moment. No path leads into the valley.
/// Numbers are the web room's (room9.js): crater 32, hill 22 x 12, summit stone 2.4, rim 20. The hill profile is eased so its steepest slope is about 36 degrees.
@MainActor final class PLWRoomP9: PLWEBaseRoom {
    static let RR: Float = 32, HR: Float = 22, HH: Float = 12, TOP: Float = 2.4, RIMH: Float = 20
    /// Steepest walkable slope in this room, in degrees (the integrator's slope limit must allow it).
    static let steepestSlopeDegrees: Float = 36
    private let K = PLWEV3(0, 0, -PLWRoomP9.RR)
    private var valleyIdx: Int?, secretIdx: Int?
    private var revealT: Float = -1, secretFoundT: Float = -1, sentStart = false, done = false, liftEnded = false, secretFound = false, curled = false

    init() { super.init(area: .p9, defaultSaturation: 0.7) }

    /// Eased hill height at radius r from the hill's centre.
    static func hill(_ r: Float) -> Float {
        let t = simd_clamp((HR - r) / (HR - TOP), 0, 1)
        return HH * (0.6 * t + 0.4 * (t * t * (3 - 2 * t)))
    }

    override func load() async throws {
        let RR = Self.RR, HR = Self.HR, HH = Self.HH, TOP = Self.TOP, RIMH = Self.RIMH
        ports["start"] = Transform(translation: [0, 0, 0])
        ports["exit"] = Transform(translation: [0, 0, -2 * RR])

        // The crater rim: pale stone in the page hue, 20 m high, dropping to a low parapet on the +x side where the valley shows. Doorways at +z (in) and -z (out).
        let stone = PLWEMat(page: 0.45, dim: 1.0, rough: 0.85)
        let doorAngles: [Float] = [.pi / 2, -.pi / 2], doorHalf: Float = 0.1
        func nearDoor(_ a: Float) -> Bool { doorAngles.contains { abs(atan2(sin(a - $0), cos(a - $0))) < doorHalf } }
        func topAt(_ a: Float) -> Float { let d = atan2(sin(a), cos(a)); return RIMH - (RIMH - 1.2) * exp(-(d * d) / (2 * 0.32 * 0.32)) }
        var segs = [[Float]](), cur = [Float](); let N = 200
        for i in 0...N { let a = Float(i) / Float(N) * 2 * .pi
            if nearDoor(a) { if !cur.isEmpty { segs.append(cur); cur = [] } } else { cur.append(a) } }
        if !cur.isEmpty { segs.append(cur) }
        for (s, seg) in segs.enumerated() where seg.count > 1 {
            let rows = 14
            let g: [[PLWEV3]] = (0..<rows).map { r in
                let f = Float(r) / Float(rows - 1)
                return seg.map { a in
                    let y = -16 + f * (topAt(a) + 16), rr = RR - 1.6 * pow(max(0, y / RIMH), 2) + 0.5 * sin(a * 23 + y * 0.7)
                    return K + PLWEV3(cos(a) * rr, y, sin(a) * rr)
                }
            }
            let mesh = PLWEKit.grid(g) { p, _, c in SIMD2(seg[c] * RR / 4, p.y / 4) }
            await piece(mesh, stone, name: "craterRim\(s)", solid: true)
        }
        let doorHW = RR * sin(doorHalf) + 0.6
        for (i, a) in doorAngles.enumerated() {
            let dir = PLWEV3(cos(a), 0, sin(a)), right = PLWEV3(-sin(a), 0, cos(a))
            await piece(PLWEKit.doorWall(at: K + dir * RR, right: right, mouthHalfW: 2.25, mouthH: 4.5, wallHalfW: doorHW, wallTop: topAt(a)), stone, name: "rimDoor\(i)", solid: true)
        }

        // The floor: deep page hue, never black.
        await piece(PLWEKit.polar(radius: RR + 0.6, rings: 24, segs: 96, centre: K, uvScale: 0.25) { x, z in 0.04 * sin(x * 0.4) * cos(z * 0.35) },
                    PLWEMat(page: 0.0, dim: 0.55, rough: 0.9), name: "craterFloor", solid: true)

        // HIS hill: dark indigo dome skinned in his white curve lines, a flat stone at the top.
        let prof: [(r: Float, y: Float)] = (0...60).map { i in let r = Float(i) / 60 * HR; return (r, r <= TOP ? HH : Self.hill(r)) }
        var hillMat = PLWEMat(0x181038, rough: 0.55); hillMat.curve = (PLWEKit.rgb(0xF2F0F8), PLWEKit.rgb(0x181038))
        await piece(PLWEKit.lathe(prof, segs: 120, centre: K, uvScale: 1.0 / 7), hillMat, name: "risingHill", solid: true)
        let sum = K + PLWEV3(0, HH, 0)
        await piece(try? MeshResource.generate(from: [PLWEKit.cylinderDescriptor(radius: TOP + 0.15, height: 0.5, sides: 48)]), PLWEMat(0xA0A6B2, rough: 0.75), name: "summitStone", solid: true, at: sum + [0, 0.05, 0])
        var inlay = PLWEMat(0xA0A6B2, rough: 0.6); inlay.curve = (PLWEKit.rgb(0xFFD700), PLWEKit.rgb(0xA0A6B2))
        await piece(PLWEKit.polar(radius: TOP, rings: 6, segs: 48, centre: sum + [0, 0.31, 0], uvScale: 0.7) { _, _ in 0 }, inlay, name: "summitInlay")

        // The dim gold line up the slope from the way in (an emissive ribbon, 0.3 m wide, laid just above the surface).
        let lineRows: [[PLWEV3]] = (0...50).map { i in let r = HR - Float(i) / 50 * (HR - TOP), y = Self.hill(r) + 0.05
            return [-0.15, 0.15].map { K + PLWEV3($0, y, r) } }
        var gold = PLWEMat(0x3A2A06, rough: 0.5); gold.emissive = PLWEKit.rgb(0xFFC000); gold.emissiveI = 1.2
        await piece(PLWEKit.grid(lineRows, uv: { _, r, c in SIMD2(Float(c), Float(r) * 0.2) }), gold, name: "goldLine")

        // The secret: his curve set into the summit stone's far face, gold when found.
        var sec = PLWEMat(0x2A2350, rough: 0.6); sec.curve = (PLWEKit.rgb(0xB8A060), PLWEKit.rgb(0x2A2350))
        let secEntity = await piece(MeshResource.generatePlane(width: 0.9, height: 0.42), sec, name: "summitSecret", at: sum + [-(TOP + 0.17), 0.05, 0])
        secEntity?.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]); secretIdx = paints.count - 1

        // The view: the paradise valley far below the notch, grey until the reveal. Visual only (no collision, nothing leads there), 40 m clear of the rim.
        let VY: Float = -15, VX = RR + 100
        func vh(_ x: Float, _ z: Float) -> Float { 2.2 * sin(x * 0.05 + 1) * cos(z * 0.04) + 1.2 * sin(z * 0.11 + x * 0.03) + max(0, (x - 40) * 0.12) }
        var valley = PLWEMat(0x4F8A3C, rough: 0.95); valley.rgb = PLWEKit.mix(PLWEKit.rgb(0x6B6E78), PLWEKit.rgb(0x4F8A3C), 0)
        await piece(PLWEKit.terrain(w: 120, d: 140, nx: 60, nz: 70, centre: [VX, VY, K.z], uvScale: 0.07) { x, z in vh(x + 0, z + 0) }, valley, name: "paradiseValley")
        valleyIdx = paints.count - 1
        let riverRows: [[PLWEV3]] = (0...60).map { i in let z = 70 - Float(i) / 60 * 140, x = 10 + 14 * sin(Float(i) * 0.11 * 2) + 7 * sin(Float(i) * 0.031 * 2 + 2)
            return [-2.4, 2.4].map { PLWEV3(VX + x + $0, VY + vh(x + $0, z) + 0.25, K.z + z) } }
        var river = PLWEMat(0x2F8FB8, rough: 0.12, metal: 0.1); river.emissive = PLWEKit.rgb(0x1D5F88); river.emissiveI = 0.4; river.alpha = 0.92
        await piece(PLWEKit.grid(riverRows, uv: { _, r, c in SIMD2(Float(c), Float(r) * 0.3) }), river, name: "paradiseRiver")
        var rng = PLWEKit.LCG(4141); var crowns = [(c: PLWEV3, rx: Float, ry: Float)]()
        for _ in 0..<60 { let x = -45 + rng.next() * 100, z = -60 + rng.next() * 120; if abs(x - 10) < 14 { continue }
            let s = 3 + rng.next() * 3; crowns.append((PLWEV3(VX + x, VY + vh(x, z) + s * 0.55, K.z + z), s, s * (1.1 + rng.next() * 0.4))) }
        await piece(PLWEKit.blobs(crowns), PLWEMat(0x2C5A2A, rough: 1), name: "valleyTrees")

        // The parapet holds him in (unseen).
        let guardEntity = Entity(); guardEntity.name = "notchGuard"; guardEntity.position = K + [RR - 0.8, 4, 0]
        PLWEKit.solidBox(guardEntity, size: [1, 8, 18]); root.addChild(guardEntity)

        // Light: the morning sun on the hill, a soft glow where the way out is. (Intensities are starting values, tuned on the device.)
        light(PLWEKit.sun(color: PLWEKit.rgb(0xFFF0C0), lux: 3200, dir: [-0.3, -0.6, -0.7]), base: 3200)
        light(PLWEKit.point(color: PLWEKit.rgb(PLWRing.pageHex[9]), lumens: 60000, radius: 14, at: [0, 2.6, -2 * RR + 3]), base: 60000)

        // The route: in, the foot of the hill, up the gold line, over the summit, down the far side, out.
        var path: [PLWEV3] = [[0, 0, 0], [0, 0, K.z + HR + 1]]
        for r in stride(from: HR - 1, through: TOP, by: -2.5) { path.append([0, Self.hill(r) + 0.1, K.z + r]) }
        path.append(sum + [0, 0.3, 0])
        for r in stride(from: TOP + 2, through: HR - 1, by: 2.5) { path.append([0, Self.hill(r) + 0.1, K.z - r]) }
        path.append([0, 0, -2 * RR]); route = path

        triggers = [PLWTrigger(id: "p9.summit", center: sum + [0, 1, 0], yaw: 0, halfExtents: [TOP, 1.4, TOP]),
                    PLWTrigger(id: "p9.secret", center: sum + [-(TOP + 0.5), 1, 0], yaw: 0, halfExtents: [1.6, 1.4, 1.6])]
        await addGlyphs([
            PLWGlyphPlacement(key: PLWKey(page: .p9, slot: 0), glyph: .glyphGuy, position: K + [6, 1.4, 20]),
            PLWGlyphPlacement(key: PLWKey(page: .p9, slot: 1), glyph: .money, position: K + [-1.4, Self.hill(13) + 1.3, 13]),
            PLWGlyphPlacement(key: PLWKey(page: .p9, slot: 2), glyph: .loveYourself, position: K + [1.6, Self.hill(12) + 1.3, -12])])
        apply(look); restoreRoom(save)
    }

    override func restoreRoom(_ s: PLWSave) {
        if s.completed.contains(.p9) { revealT = 99; done = true; liftEnded = true; setValley(1) }
        if s.marks.contains("p9.secret") { secretFound = true; setSecret(1) }
    }

    private func setValley(_ k: Float) {
        guard let i = valleyIdx else { return }
        paints[i].mat.rgb = PLWEKit.mix(PLWEKit.rgb(0x6B6E78), PLWEKit.rgb(0x4F8A3C), k)
        paints[i].entity.model?.materials = [PLWEKit.material(paints[i].mat, look: look, tex: nil)]
    }
    private func setSecret(_ k: Float) {
        guard let i = secretIdx, k > 0 else { return }
        let line = PLWEKit.saturate(PLWEKit.rgb(0xFFF2B0), look.saturation), ground = PLWEKit.saturate(PLWEKit.rgb(0x6A4E14), look.saturation)
        Task { @MainActor in   // found: his curve turns bright gold in the stone
            guard let t = await PLWEKit.curveTexture(tile: tile, line: line, ground: ground), i < paints.count else { return }
            curveTex[i] = t; paints[i].mat.curve = (PLWEKit.rgb(0xFFF2B0), PLWEKit.rgb(0x6A4E14))
            paints[i].entity.model?.materials = [PLWEKit.material(paints[i].mat, look: look, tex: t)]
        }
    }

    override func receive(_ e: PLWTriggerEvent) -> [PLWCommand] {
        if e.id == "p9.summit", e.phase == .entered, revealT < 0 { revealT = 0 }
        return []
    }

    override func stepRoom(_ f: PLWFrame) -> [PLWCommand] {
        var out = [PLWCommand]()
        if !sentStart { sentStart = true; out.append(.checkpoint(.p9, port: "start")) }
        let sum = K + PLWEV3(0, Self.HH, 0), p = f.position
        // On the slope he is the ball (his curl, as motion); on the flat or the summit stone he stands.
        let rr = hypot(p.x - K.x, p.z - K.z), onSlope = rr > Self.TOP + 0.1 && rr < Self.HR - 0.4 && p.y > 0.6
        if onSlope != curled { curled = onSlope; out.append(.heroPose(onSlope ? "curl" : "stand")) }
        // The summit: he stands on the stone, lifts the dream, the valley lights up below.
        if revealT < 0, hypot(p.x - sum.x, p.z - sum.z) < Self.TOP, p.y > sum.y - 0.5 { revealT = 0 }
        if revealT >= 0, revealT < 90 {
            revealT += f.dt
            let t = revealT, k = PLWEKit.smooth(0.2, 1.8, t)
            setValley(k)
            if t < 3.2 { out.append(.raiseDream(1)) } else if !liftEnded { liftEnded = true; out.append(.raiseDream(0)) }
            let w = PLWEKit.smooth(0, 0.8, t) * (1 - PLWEKit.smooth(3.8, 4.5, t))
            if w > 0.001 { out.append(.camera(position: sum + [-6, 3.2, 0], target: sum + [30, -6, 0], weight: w)) }   // behind him, his figure against the valley
            if t >= 4.5, !done { done = true; out += [.roomFlag(.p9, "viewed"), .completeMoment(.p9)] }
        }
        // The secret: ACT near the far face of the summit stone.
        let secretAt = sum + [-(Self.TOP + 0.17), 0.05, 0]
        if !secretFound, f.actPressed, simd_distance(p + [0, 1, 0], secretAt) < 2.2 {
            secretFound = true; secretFoundT = 3.5; setSecret(1); out += [.mark("p9.secret"), .caption("his curve, set in stone")]
        }
        if secretFoundT > 0 { secretFoundT -= f.dt }
        return out
    }
}

extension PLWEKit {
    /// A closed cylinder standing on its centre (Y axis), with caps.
    static func cylinderDescriptor(radius: Float, height: Float, sides: Int) -> MeshDescriptor {
        var pos = [PLWEV3](), nrm = [PLWEV3](), uv = [SIMD2<Float>](), idx = [UInt32](); let h = height / 2
        for cap in [1, -1] as [Float] {
            let c = UInt32(pos.count); pos.append([0, cap * h, 0]); nrm.append([0, cap, 0]); uv.append([0.5, 0.5])
            for k in 0...sides { let a = Float(k) / Float(sides) * 2 * .pi; pos.append([radius * cos(a), cap * h, radius * sin(a)]); nrm.append([0, cap, 0]); uv.append([0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)]) }
            for k in 0..<sides { let a = c + 1 + UInt32(k); idx += cap > 0 ? [c, a + 1, a] : [c, a, a + 1] }
        }
        let s = UInt32(pos.count)
        for k in 0...sides { let a = Float(k) / Float(sides) * 2 * .pi, d = PLWEV3(cos(a), 0, sin(a))
            pos.append([radius * d.x, -h, radius * d.z]); nrm.append(d); uv.append([Float(k) / Float(sides) * 2, 0])
            pos.append([radius * d.x, h, radius * d.z]); nrm.append(d); uv.append([Float(k) / Float(sides) * 2, 0.3]) }
        for k in 0..<sides { let a = s + UInt32(k * 2); idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2] }
        var d = MeshDescriptor(name: "cylinder")
        d.positions = MeshBuffers.Positions(pos); d.normals = MeshBuffers.Normals(nrm); d.textureCoordinates = MeshBuffers.TextureCoordinates(uv); d.primitives = .triangles(idx)
        return d
    }
}
