import Foundation
import RealityKit
import simd

/// Page 11, The Embrace. Local frame: in at the origin (the "start" port, facing -Z); the pool is centred at z = -22. A golden-green grotto ringed by an earthen berm round a
/// cyan pool, a mossy stone pier running out over the water. At the pier's end he holds still: the dream leaves his hands and settles on the water, HIS golden ribbons rise
/// out of the pool and wrap it (the embrace), and the way on opens. Three round mouths in the far bank (green, blue, gold). Numbers are the web room's (room11.js).
/// Ports: "start", "exit" (the middle mouth, -Z), "forest" and "luxe" (the side mouths), each at the mouth and facing out of the room.
@MainActor final class PLWRoomP11: PLWEBaseRoom {
    static let RB: Float = 22, RP: Float = 11, BERMH: Float = 11
    /// Only the middle mouth opens at the embrace until the lead says the side mouths lead somewhere (they stay sealed and glowing).
    static let openSideMouths = false
    private let C = PLWEV3(0, 0, -22)
    private struct Mouth { let a: Float; let hw: Float; let hh: Float; let col: UInt32; let name: String }
    private let mouths = [Mouth(a: -.pi / 2 - 0.62, hw: 3.0, hh: 5.2, col: 0x3FAE5A, name: "forest"), Mouth(a: -.pi / 2, hw: 3.0, hh: 5.2, col: 0x3A55C8, name: "exit"),
                          Mouth(a: -.pi / 2 + 0.62, hw: 3.0, hh: 5.2, col: 0xE0B040, name: "luxe")]
    private var ribbonHub = Entity(), orb: ModelEntity?, seals: [ModelEntity] = [], sealMats: [(idx: Int, base: PLWEMat)] = [], dreamLight: Int?
    private var embraced = false, t: Float = -1, still: Float = 0, from = PLWEV3.zero, sentStart = false, done = false, hinted = false

    init() { super.init(area: .p11, defaultSaturation: 0.7) }

    override func load() async throws {
        let RB = Self.RB, RP = Self.RP, BERMH = Self.BERMH
        let PE = C + [0, 0, 4.5]
        ports["start"] = Transform(translation: [0, 0, 0])
        for m in mouths { ports[m.name] = Transform(rotation: simd_quatf(from: [0, 0, -1], to: [cos(m.a), 0, sin(m.a)]), translation: C + PLWEV3(cos(m.a), 0, sin(m.a)) * RB) }
        func topAt(_ a: Float) -> Float { BERMH + 0.8 * sin(a * 6) + 0.5 * sin(a * 13 + 2) }

        // The berm: a grassy earthen ring (the page gold, dimmed, never black), the way in at +z, three round mouths in the far bank.
        let earth = PLWEMat(page: 0.1, dim: 0.62, rough: 0.95), stone = PLWEMat(0xDDE2CC, rough: 0.85)
        var doors: [(a: Float, hw: Float, hh: Float)] = [(.pi / 2, 2.25, 4.5)]
        doors += mouths.map { ($0.a, $0.hw, $0.hh) }
        let runs = PLWEKit.angleRuns(doors: doors.map { ($0.a, asin(($0.hw + 0.9) / RB)) }, n: 260)
        for (s, seg) in runs.enumerated() {
            let rows = 10
            let g: [[PLWEV3]] = (0..<rows).map { r in
                let f = Float(r) / Float(rows - 1)
                return seg.map { a in
                    let y = -1.5 + f * (topAt(a) + 1.5), rr = RB + 2.5 * f * f + 0.3 * sin(a * 19 + y)
                    return C + PLWEV3(cos(a) * rr, y, sin(a) * rr)
                }
            }
            await piece(PLWEKit.grid(g) { p, _, c in SIMD2(seg[c] * RB / 3, p.y / 3) }, earth, name: "grottoBerm\(s)", solid: true)
        }
        for (i, d) in doors.enumerated() {
            let dir = PLWEV3(cos(d.a), 0, sin(d.a)), right = PLWEV3(-dir.z, 0, dir.x), c = C + dir * RB
            await piece(PLWEKit.doorWall(at: c, right: right, mouthHalfW: d.hw, mouthH: d.hh, wallHalfW: d.hw + 1.1, wallTop: topAt(d.a)), earth, name: "grottoMouth\(i)", solid: true)
            await piece(PLWEKit.tube(PLWEKit.arch(at: c, right: right, halfW: d.hw, h: d.hh, n: 40), sides: 12) { _ in 0.35 }, stone, name: "mouthRing\(i)")   // a dressed stone ring round each mouth
        }

        // The ground: grass round a stone-rimmed basin; the pool is shallow enough to wade.
        func depth(_ r: Float) -> Float { r < RP ? -1.3 * PLWEKit.smooth(RP, RP - 3, r) : 0 }
        await piece(PLWEKit.polar(radius: RB + 2, rings: 44, segs: 96, centre: C, uvScale: 0.1) { x, z in
            let r = hypot(x, z); return depth(r) + (r > RP + 1 ? 0.06 * sin(x * 0.6) * cos(z * 0.5) : 0) }, PLWEMat(0x86A63C, rough: 0.95), name: "grottoGround", solid: true)
        let ringPts: [PLWEV3] = (0...64).map { i in let a = Float(i) / 64 * 2 * .pi; return C + PLWEV3(cos(a) * (RP + 0.2), 0.05, sin(a) * (RP + 0.2)) }
        await piece(PLWEKit.tube(ringPts, sides: 12) { _ in 0.35 }, stone, name: "poolCurb", solid: true)
        var water = PLWEMat(0x1FB8D6, rough: 0.08, metal: 0.15); water.alpha = 0.85; water.emissive = PLWEKit.rgb(0x40505A); water.emissiveI = 0.4
        await piece(PLWEKit.polar(radius: RP + 0.1, rings: 12, segs: 64, centre: C + [0, -0.22, 0], uvScale: 0.2) { _, _ in 0 }, water, name: "embracePool")

        // The pier: a mossy stone slab from the near bank out over the water.
        let pierLen = RP + 2 - 4.5
        let pier = ModelEntity(mesh: .generateBox(width: 3.2, height: 1.6, depth: pierLen), materials: [PLWEKit.material(PLWEMat(0xB4BAA2, rough: 0.9), look: look, tex: nil)])
        pier.name = "embracePier"; pier.position = C + [0, -0.55, (RP + 2 + 4.5) / 2]; root.addChild(pier); paints.append(PLWEPaint(entity: pier, mat: PLWEMat(0xB4BAA2, rough: 0.9)))
        PLWEKit.solidBox(pier, size: [3.2, 1.6, pierLen])
        var moss = PLWEMat(0x8F9A7A, rough: 0.9); moss.curve = (PLWEKit.rgb(0x3C5A2A), PLWEKit.rgb(0x8F9A7A))
        await piece(PLWEKit.terrain(w: 3.0, d: pierLen - 0.1, nx: 2, nz: 4, centre: pier.position + [0, 0.81, 0], uvScale: 0.33) { _, _ in 0 }, moss, name: "pierMoss")

        // HIS ribbons: wide golden bands that rise out of the pool and wrap the dream, hidden until the embrace.
        ribbonHub = Entity(); ribbonHub.name = "embraceHub"; ribbonHub.position = C + [0, 0.05, 0]; root.addChild(ribbonHub)
        var gold = PLWEMat(page: 0.1, dim: 1, rough: 0.45, metal: 0.2); gold.emissive = PLWEKit.rgb(0xE8B21A); gold.emissiveI = 0.25; gold.twoSided = true
        var rng = PLWEKit.LCG(1414)
        for k in 0..<7 {
            let ph = Float(k) / 7 * 2 * .pi + rng.next() * 0.4, up = 0.5 + rng.next() * 0.9, sgn: Float = rng.next() < 0.5 ? 1 : -1
            let ctrl: [(Float, Float, Float)] = [(5.2, ph, -1.2), (3.4, ph + 0.5 * sgn, 0.3), (2.0, ph + 1.1 * sgn, up), (1.4, ph + 1.9 * sgn, up * 0.9), (1.7, ph + 2.6 * sgn, 0.25), (3.2, ph + 3.2 * sgn, -0.3), (4.8, ph + 3.6 * sgn, -1.3)]   // they circle the dream and leave it seen
            let pts = PLWEKit.spline(ctrl.map { PLWEV3(cos($0.1) * $0.0, $0.2, sin($0.1) * $0.0) }, per: 10)
            let rows: [[PLWEV3]] = pts.enumerated().map { i, p in
                let tg = simd_normalize(pts[min(i + 1, pts.count - 1)] - pts[max(i - 1, 0)]), side = simd_normalize(simd_cross(tg, PLWEV3(0, 1, 0)) + PLWEV3(0, 0.0001, 0))
                return [p - side * 0.3, p + side * 0.3]
            }
            if let r = await piece(PLWEKit.grid(rows, double: true, uv: { _, r, c in SIMD2(Float(c), Float(r) * 0.1) }), gold, name: "embraceRibbon\(k)", to: ribbonHub) { r.scale = PLWEV3(repeating: 0.001) }
        }
        // The dream at rest (the integrator carries it before this; this is the pearl that settles on the water).
        var pearl = PLWEMat(0xF5C518, rough: 0.3, metal: 0.6); pearl.emissive = PLWEKit.rgb(0xFFC83A); pearl.emissiveI = 0.8
        orb = await piece(MeshResource.generateSphere(radius: 0.28), pearl, name: "dreamPearl", at: C + [0, 0.25, 0]); orb?.isEnabled = false

        // The mouths' seals: a glowing half-disc in each, in its district's colour (the middle one opens at the embrace).
        for m in mouths {
            let dir = PLWEV3(cos(m.a), 0, sin(m.a)), right = PLWEV3(-dir.z, 0, dir.x), c = C + dir * (RB + 0.4)
            let arc = PLWEKit.arch(at: c, right: right, halfW: m.hw, h: m.hh, n: 30)
            var sm = PLWEMat(m.col, rough: 0.8); sm.emissive = PLWEKit.rgb(m.col); sm.emissiveI = 0.9; sm.alpha = 0.92; sm.twoSided = true
            if let e = await piece(PLWEKit.grid([arc, arc.map { _ in c }], double: true, uv: { _, _, _ in .zero }), sm, name: "mouthSeal_\(m.name)", solid: true) { seals.append(e); sealMats.append((paints.count - 1, sm)) }
        }

        // Light: a low warm sun, the pool's cyan, the dream's gold once it rests. (Starting values, tuned on the device.)
        light(PLWEKit.sun(color: PLWEKit.rgb(0xFFD9A0), lux: 2400, dir: [0.3, -0.55, -0.75]), base: 2400)
        light(PLWEKit.point(color: PLWEKit.rgb(0x40D8F0), lumens: 50000, radius: 14, at: C + [0, 1.2, 0]), base: 50000)
        light(PLWEKit.point(color: PLWEKit.rgb(0xFFD040), lumens: 0, radius: 9, at: C + [0, 0.8, 0]), base: 0); dreamLight = lights.count - 1

        route = [[0, 0, 0], [0, 0, C.z + RP + 1], PE + [0, 0.3, 0], [-RP - 2, 0, C.z + 2], [-RP - 1, 0, C.z - 8], [0, 0, C.z - RB + 4], [0, 0, C.z - RB]]
        triggers = [PLWTrigger(id: "p11.pierEnd", center: PE + [0, 1, 0], yaw: 0, halfExtents: [1.8, 1.5, 1.8])]
        await addGlyphs([
            PLWGlyphPlacement(key: PLWKey(page: .p11, slot: 0), glyph: .loveYourself, position: [6, 1.4, -8]),
            PLWGlyphPlacement(key: PLWKey(page: .p11, slot: 1), glyph: .glyphGuy, position: C + [-15, 1.4, 6]),
            PLWGlyphPlacement(key: PLWKey(page: .p11, slot: 2), glyph: .smiley, position: C + [5, 1.4, -16])])
        apply(look); restoreRoom(save)
        if embraced { settle(7) }   // restore() may have come before the pieces existed
    }

    override func restoreRoom(_ s: PLWSave) {
        guard s.completed.contains(.p11), !embraced else { return }
        embraced = true; t = 99; done = true; settle(7)
    }

    /// Everything the embrace changes, at time `t` seconds into it.
    private func settle(_ t: Float) {
        for (i, r) in ribbonHub.children.enumerated() { r.scale = PLWEV3(repeating: max(0.001, PLWEKit.smooth(1.6 + Float(i) * 0.12, 3.6 + Float(i) * 0.12, t))) }
        if let d = dreamLight { lights[d].base = 60000 * PLWEKit.smooth(1.8, 3.5, t); if var p = lights[d].entity.components[PointLightComponent.self] { p.intensity = lights[d].base * look.exposure; lights[d].entity.components.set(p) } }
        for (n, s) in seals.enumerated() {
            let m = sealMats[n], isMiddle = mouths[n].name == "exit"
            guard isMiddle || Self.openSideMouths else { continue }
            var mat = m.base; mat.alpha = 0.92 * (1 - PLWEKit.smooth(4, 6, t))
            paints[m.idx].mat = mat; s.model?.materials = [PLWEKit.material(mat, look: look, tex: nil)]
            if t > 5.8 { s.isEnabled = false }
        }
        if t >= 7 { orb?.isEnabled = true; orb?.position = C + [0, 0.25, 0] }
    }

    override func receive(_ e: PLWTriggerEvent) -> [PLWCommand] { [] }

    override func stepRoom(_ f: PLWFrame) -> [PLWCommand] {
        var out = [PLWCommand]()
        if !sentStart { sentStart = true; out.append(.checkpoint(.p11, port: "start")); if embraced { out.append(.dreamOrbVisible(false)) } }   // a restored embrace keeps only the pearl
        let p = f.position, PE = C + [0, 0, 4.5]
        if embraced { ribbonHub.orientation = simd_quatf(angle: spin * 0.08, axis: [0, 1, 0]); if let o = orb, t >= 2.2 { o.position.y = C.y + 0.25 + 0.05 * sin(spin * 1.1) } }
        // The embrace: at the pier's end, holding still (or ACT) lets the dream go.
        let atEnd = hypot(p.x - PE.x, p.z - PE.z) < 1.8 && p.y > 0.25 - 0.5
        still = atEnd && !embraced && (simd_length(f.velocity) < 0.25 || f.actPressed) ? still + f.dt : 0
        if atEnd, !embraced, !hinted { hinted = true; out.append(.caption("hold still")) } else if !atEnd { hinted = false }
        if !embraced, still > 1.0 {
            embraced = true; t = 0; from = PE + [0, 1.2, 0]; orb?.isEnabled = true; out += [.dream(.embraced), .dreamOrbVisible(false), .roomFlag(.p11, "embraced")]
        }
        if embraced, t >= 0, t < 7 {
            t += f.dt
            if let o = orb, t < 2.2 {
                let k = PLWEKit.smooth(0, 2.2, t), dst = C + [0, 0.25, 0], mid = PLWEKit.mix(from, dst, 0.5) + [0, 1.6, 0]   // it arcs out over the water
                o.position = PLWEKit.mix(PLWEKit.mix(from, mid, k), PLWEKit.mix(mid, dst, k), k)
            }
            settle(t)
            let w = PLWEKit.smooth(0, 0.8, t) * (1 - PLWEKit.smooth(6.2, 7, t))
            if w > 0.001 { out.append(.camera(position: C + [4, 4.5, 9], target: C + [0, 1, -2], weight: w)) }
            if t >= 6, !done { done = true; out.append(.completeMoment(.p11)) }
        }
        return out
    }
}
