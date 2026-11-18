import Foundation
import RealityKit
import simd

/// Page 10, The Homeland. Local frame: in at the origin (the "start" port, facing -Z), out at z = -42 (the "exit" port). An oval garden walled by cliffs in the page blue,
/// HIS curve-beings standing about (swelling gold tubes, a loop at the head, the big one with rungs), a lazy river across the middle under a low stone bridge, his grinning sun
/// high over the far wall. The moment: on the bridge his sun brightens and every being turns to him at once. Numbers are the web room's (room10.js).
@MainActor final class PLWRoomP10: PLWEBaseRoom {
    static let HL: Float = 21, HW: Float = 15, WALLH: Float = 16, GAP: Float = 0.19
    private let G = PLWEV3(0, 0, -21)
    private var ZR: Float { G.z + 1 }
    private struct Being { let anchor: Entity, body: ModelEntity, at: PLWEV3, yaw: Float, paint: Int; var tilt: Float = 0 }
    private var beings: [Being] = []
    private var sunEntity: ModelEntity?, sunMat: UnlitMaterial?, secretIdx: Int?
    private var lastSunB: Float = 0, greetT: Float = -1, sentStart = false, done = false, secretFound = false

    init() { super.init(area: .p10, defaultSaturation: 0.7) }

    private func pathX(_ z: Float) -> PLWEV3.Scalar { 2.2 * sin((z - G.z) * 0.16) }
    private func chan(_ z: Float) -> Float { 0.9 * exp(-pow(z - ZR, 2) / (2 * 1.3 * 1.3)) }

    override func load() async throws {
        let HL = Self.HL, HW = Self.HW, WALLH = Self.WALLH, GAP = Self.GAP
        ports["start"] = Transform(translation: [0, 0, 0])
        ports["exit"] = Transform(translation: [0, 0, -2 * HL])
        func topAt(_ a: Float) -> Float { WALLH + 1.5 * sin(a * 5) + 1.0 * sin(a * 11 + 1) }

        // The cliffs: pale stone leaning to the page blue, round an oval, a doorway at each end (+z in, -z out).
        let cliff = PLWEMat(page: 0.5, dim: 0.95, rough: 0.9)
        for (s, seg) in PLWEKit.angleRuns(doors: [.pi / 2, -.pi / 2], doorHalf: GAP, n: 200).enumerated() {
            let rows = 12
            let g: [[PLWEV3]] = (0..<rows).map { r in
                let f = Float(r) / Float(rows - 1)
                return seg.map { a in
                    let y = -1.5 + f * (topAt(a) + 1.5), k = 1 + 0.03 * sin(a * 17 + y * 0.6) - 0.06 * f * f
                    return G + PLWEV3(cos(a) * HW * k, y, sin(a) * HL * k)
                }
            }
            await piece(PLWEKit.grid(g) { p, _, c in SIMD2(seg[c] * HL / 3, p.y / 3) }, cliff, name: "gardenCliff\(s)", solid: true)
        }
        for (i, sz) in [Float(1), -1].enumerated() {
            let top = min(topAt(.pi / 2 * sz + GAP), topAt(.pi / 2 * sz - GAP))
            await piece(PLWEKit.doorWall(at: G + [0, 0, sz * HL], right: [1, 0, 0], mouthHalfW: 2.25, mouthH: 4.5, wallHalfW: 3.7, wallTop: top), cliff, name: "gardenDoor\(i)", solid: true)
        }

        // The ground: garden earth with a shallow river channel across the middle.
        await piece(PLWEKit.terrain(w: 2 * HW + 2, d: 2 * HL + 2, nx: 60, nz: 80, centre: G, uvScale: 0.12) { x, z in
            -self.chan(z + self.G.z) + 0.08 * sin(x * 0.7) * cos(z * 0.5) }, PLWEMat(0x8C9A3A, rough: 0.95), name: "gardenGround", solid: true)
        var river = PLWEMat(page: 0, dim: 1, rough: 0.08, metal: 0.2); river.alpha = 0.85; river.emissive = PLWEKit.rgb(0x0D3550); river.emissiveI = 0.5
        await piece(PLWEKit.terrain(w: 2 * HW + 2, d: 4.4, nx: 30, nz: 6, centre: [0, -0.42, ZR], uvScale: 0.2) { _, _ in 0 }, river, name: "lazyRiver")

        // The indigo curve mound where he lands.
        var moundMat = PLWEMat(0x181038, rough: 0.55); moundMat.curve = (PLWEKit.rgb(0xF2F0F8), PLWEKit.rgb(0x181038))
        let moundProfile: [(r: Float, y: Float)] = (0...24).map { i in let r = Float(i) / 24 * 5.5; return (r, 0.65 * (1 + cos(Float.pi * r / 5.5)) - 0.05) }
        await piece(PLWEKit.lathe(moundProfile, segs: 72, centre: G + [0, 0, HL - 6], uvScale: 0.25), moundMat, name: "landingMound", solid: true)

        // The path: his curve tile in a gentle S, and a low stone bridge over the river.
        var pathMat = PLWEMat(0xEFE2C0, rough: 0.6); pathMat.curve = (PLWEKit.rgb(0x7A5222), PLWEKit.rgb(0xEFE2C0)); pathMat.twoSided = true
        func strip(_ z0: Float, _ z1: Float) -> [[PLWEV3]] {
            (0...40).map { i in let z = z0 + Float(i) / 40 * (z1 - z0), x = pathX(z), y = -chan(z) + 0.015; return [PLWEV3(x - 1.4, y, z), PLWEV3(x + 1.4, y, z)] }
        }
        await piece(PLWEKit.grid(strip(G.z + HL - 11.5, ZR + 3.2), uv: { p, _, c in SIMD2(Float(c), -p.z / 3) }), pathMat, name: "gardenPathA")
        await piece(PLWEKit.grid(strip(ZR - 3.2, G.z - HL + 0.4), uv: { p, _, c in SIMD2(Float(c), -p.z / 3) }), pathMat, name: "gardenPathB")
        let stone = PLWEMat(0xB9A88A, rough: 0.85)
        func deck(_ side: Float) -> [PLWEV3] {
            (0...24).map { i in let t = Float(i) / 24, z = ZR + 3.4 - t * 6.8; return [pathX(z) + side, 0.02 + 0.75 * sin(Float.pi * t), z] }
        }
        await piece(PLWEKit.grid([deck(-1.7), deck(1.7)], flip: true, double: true, uv: { p, _, c in SIMD2(Float(c) * 0.5, p.z / 2) }), stone, name: "bridgeDeck", solid: true)
        for side in [Float(-1.75), 1.75] {
            let curb = deck(side).map { $0 + [0, 0.22, 0] }
            await piece(PLWEKit.tube(curb, sides: 12) { _ in 0.2 }, stone, name: "bridgeCurb", solid: true)
        }

        // HIS curve-beings.
        func being(_ at: PLWEV3, yaw: Float, h: Float, s: Float, R: Float, rungs: Int = 0, lean: Float = 0.25, seed: Float) async {
            let w = { (k: Float) in sin(seed * 3.1 + k * 2.3) }
            func P(_ x: Float, _ y: Float, _ z: Float) -> PLWEV3 { PLWEV3(x, y, z) }
            var c = [PLWEV3]()
            c.append(P(-s, -0.6, 0)); c.append(P(-s * 0.95 + w(1) * 0.3, h * 0.3, w(2) * 0.4)); c.append(P(-s * 0.55, h * 0.72, w(3) * 0.5)); c.append(P(-s * 0.2, h * 0.95, lean))
            c.append(P(s * 0.18, h * 1.02, lean * 1.6)); c.append(P(s * 0.3, h * 0.8, lean * 2.4)); c.append(P(s * 0.02, h * 0.82, lean * 2.2)); c.append(P(-s * 0.05, h * 0.98, lean * 1.2))
            c.append(P(s * 0.35, h * 0.95, 0)); c.append(P(s * 0.62, h * 0.7, w(4) * 0.5)); c.append(P(s * 0.95 + w(5) * 0.3, h * 0.3, w(6) * 0.4)); c.append(P(s, -0.6, 0))   // up one leg, a loop over the head, down the other
            let path = PLWEKit.spline(c, per: 8), n = path.count
            let anchor = Entity(); anchor.position = [at.x, -0.35, at.z]; root.addChild(anchor)
            let feet = Entity(); feet.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); anchor.addChild(feet)
            for sx in [-s, s] { let b = Entity(); b.position = [sx, 0.7, 0]; PLWEKit.solidBox(b, size: [2 * R + 0.2, 1.5, 2 * R + 0.2]); feet.addChild(b) }
            var m = PLWEMat(0xFFD28C, rough: 0.38, metal: 0.3); m.emissive = [0, 0, 0]
            let body = await piece(PLWEKit.tube(path, sides: 14, uvAlong: 0.3) { t in R * (0.82 + 0.3 * sin(Float.pi * t) + 0.08 * sin(t * Float(n) * 0.21 + seed)) }, m, name: "curveBeing", to: anchor)
            body?.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            for k in 0..<rungs {   // a rung from leg to leg, ends sunk inside each leg
                let f = 0.18 + Float(k) * 0.17, li = Int(f * Float(n - 1) * 0.42), ri = n - 1 - li, a = path[li], b = path[ri]
                let rpath: [PLWEV3] = (0...4).map { q in let t = Float(q) / 4; return PLWEKit.mix(a, b, t) + PLWEV3(0, 0.12 * sin(Float.pi * t), 0) }
                let rung = await piece(PLWEKit.tube(rpath, sides: 10) { _ in R * 0.45 }, m, name: "curveBeingRung", to: anchor)
                rung?.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            }
            if let body { beings.append(Being(anchor: anchor, body: body, at: at, yaw: yaw, paint: paints.firstIndex { $0.entity === body } ?? 0)) }
        }
        await being([8.5, 0, -10], yaw: 0.4, h: 6.5, s: 1.0, R: 0.42, rungs: 4, lean: 0.1, seed: 1)   // the ladder being
        await being([-8.5, 0, -13.5], yaw: -0.5, h: 5.2, s: 1.4, R: 0.5, seed: 2)
        await being([-10.5, 0, -17], yaw: 0.9, h: 6.0, s: 1.2, R: 0.55, lean: 0.4, seed: 3)
        await being([9.5, 0, -24], yaw: -0.8, h: 4.6, s: 1.5, R: 0.45, seed: 4)
        await being([pathX(-28), 0, -28], yaw: 0.05, h: 7.0, s: 3.4, R: 0.6, lean: 0.15, seed: 5)   // the overlook loop: an arch over the path, he walks between its feet
        await being([-6.5, 0, -34], yaw: 0.2, h: 4.5, s: 1.1, R: 0.42, seed: 6)
        await being([10.5, 0, -33], yaw: -0.3, h: 5.4, s: 1.3, R: 0.5, lean: 0.35, seed: 7)

        // HIS sun, cut from his plate 10, high over the far wall (faces the way he walks).
        if let tex = await PLWEKit.plainTexture("plwe-sun") {
            var m = UnlitMaterial(); m.color = .init(tint: .white, texture: .init(tex)); m.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            let e = ModelEntity(mesh: .generatePlane(width: 13, height: 13 * 130 / 215), materials: [m]); e.name = "sun10"; e.position = G + [-2, WALLH + 15, -HL - 14]
            root.addChild(e); sunEntity = e; sunMat = m
        }

        // The secret: his curve set into the cliff behind the ladder being, gold when found.
        var sec = PLWEMat(0x4A3214, rough: 0.6); sec.curve = (PLWEKit.rgb(0xB8A060), PLWEKit.rgb(0x4A3214))
        let sz: Float = -9, sa = asin((sz - G.z) / HL), sx = HW * cos(sa) * 0.985
        let secEntity = await piece(MeshResource.generatePlane(width: 1.1, height: 0.8), sec, name: "homeSecret", at: [sx, 1.3, sz])
        secEntity?.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]); secretIdx = paints.count - 1

        // Light: his sun's warmth, the river's cool blue, a glow at the way out in the next page's hue. (Starting values, tuned on the device.)
        light(PLWEKit.sun(color: PLWEKit.rgb(0xFFF0B0), lux: 2600, dir: [0.05, -0.8, -0.6]), base: 2600)
        light(PLWEKit.point(color: PLWEKit.rgb(0x40A0FF), lumens: 40000, radius: 12, at: [0, 1.5, ZR]), base: 40000)
        light(PLWEKit.point(color: PLWEKit.rgb(PLWRing.pageHex[10]), lumens: 50000, radius: 12, at: [0, 2.4, -2 * HL + 3]), base: 50000)

        var path: [PLWEV3] = [[0, 0, 0], G + [0, 1.3, HL - 6]]
        for z in stride(from: G.z + HL - 11, through: ZR + 3.6, by: -3) { path.append([pathX(z), -chan(z), z]) }
        path.append([pathX(ZR), 0.77, ZR])
        for z in stride(from: ZR - 3.6, through: G.z - HL + 1, by: -3) { path.append([pathX(z), -chan(z), z]) }
        path.append([0, 0, -2 * HL]); route = path

        triggers = [PLWTrigger(id: "p10.bridge", center: [pathX(ZR), 1.2, ZR], yaw: 0, halfExtents: [2, 1.4, 2.6]),
                    PLWTrigger(id: "p10.secret", center: [sx - 1, 1.2, sz], yaw: 0, halfExtents: [2.4, 1.4, 2.4])]
        await addGlyphs([
            PLWGlyphPlacement(key: PLWKey(page: .p10, slot: 0), glyph: .povertyToLuxury, position: [6, 1.4, -11]),
            PLWGlyphPlacement(key: PLWKey(page: .p10, slot: 1), glyph: .smiley, position: [pathX(-24) + 3, 1.4, -24]),
            PLWGlyphPlacement(key: PLWKey(page: .p10, slot: 2), glyph: .moneyGrin, position: [-5, 1.4, -38])])
        apply(look); restoreRoom(save)
    }

    override func restoreRoom(_ s: PLWSave) {
        if s.completed.contains(.p10) { greetT = 99; done = true }
        if s.marks.contains("p10.secret") { secretFound = true }
    }

    override func receive(_ e: PLWTriggerEvent) -> [PLWCommand] {
        if e.id == "p10.bridge", e.phase == .entered, greetT < 0 { greetT = 0 }
        return []
    }

    override func stepRoom(_ f: PLWFrame) -> [PLWCommand] {
        var out = [PLWCommand]()
        if !sentStart { sentStart = true; out.append(.checkpoint(.p10, port: "start")) }
        let p = f.position
        // The bridge: his sun brightens, every being turns to him, the camera drops low for the hero shot.
        let onBridge = abs(p.z - ZR) < 2.6 && abs(p.x - pathX(p.z)) < 2 && p.y > -0.2
        if greetT < 0, onBridge { greetT = 0 }
        var greet: Float = 0
        if greetT >= 0, greetT < 90 {
            greetT += f.dt; let t = greetT
            greet = t < 4 ? sin(Float.pi * min(1, t / 4)) : 0
            let w = t < 4.6 ? PLWEKit.smooth(0, 0.8, t) * (1 - PLWEKit.smooth(3.8, 4.6, t)) : 0
            if w > 0.001 { out.append(.camera(position: p + [0.8, -0.1, 4.2], target: p + [-0.5, 4.5, -8], weight: w)) }   // low behind him, looking up past the beings to his sun
            if t >= 4, !done { done = true; out += [.roomFlag(.p10, "greeted"), .completeMoment(.p10)] }
        }
        if let e = sunEntity {
            e.scale = PLWEV3(repeating: 1 + 0.04 * sin(spin * .pi) + 0.08 * greet)
            if var m = sunMat, abs((0.9 + 0.1 * greet) - lastSunB) > 0.01 { let b = 0.9 + 0.1 * greet; lastSunB = b; m.color = .init(tint: PLWEKit.ui([b, b, b]), texture: m.color.texture); e.model?.materials = [m] }
        }
        // Beings: the nearest leans toward him and warms; on the bridge all do.
        var nearest = -1, nd: Float = 1e9
        for (i, b) in beings.enumerated() { let d = hypot(p.x - b.at.x, p.z - b.at.z); if d < nd { nd = d; nearest = i } }
        for i in beings.indices {
            let want: Float = max(greet, (i == nearest && nd < 5) ? 1 : 0)
            beings[i].tilt += (want - beings[i].tilt) * min(1, f.dt / 1.5 * 3)
            let b = beings[i], to = PLWEV3(p.x - b.at.x, 0, p.z - b.at.z)
            if simd_length_squared(to) > 0.01 {
                let n = simd_normalize(to), axis = PLWEV3(n.z, 0, -n.x)
                b.body.orientation = simd_quatf(angle: 0.12 * b.tilt, axis: axis) * simd_quatf(angle: b.yaw, axis: [0, 1, 0])
            }
            let k = 0.25 * b.tilt
            if abs(paints[b.paint].mat.emissiveI - k) > 0.02 {
                paints[b.paint].mat.emissive = [1, 0.68, 0]; paints[b.paint].mat.emissiveI = k
                b.body.model?.materials = [PLWEKit.material(paints[b.paint].mat, look: look, tex: nil)]
            }
        }
        let secretAt = PLWEV3(HW_secretX, 1.3, -9)
        if !secretFound, f.actPressed, hypot(p.x - secretAt.x, p.z - secretAt.z) < 2.4 {
            secretFound = true; out += [.mark("p10.secret"), .caption("his curve, at home")]
            if let i = secretIdx {
                Task { @MainActor in
                    guard let t = await PLWEKit.curveTexture(tile: tile, line: PLWEKit.saturate(PLWEKit.rgb(0xFFF2B0), look.saturation), ground: PLWEKit.saturate(PLWEKit.rgb(0x6A4E14), look.saturation)), i < paints.count else { return }
                    curveTex[i] = t; paints[i].mat.curve = (PLWEKit.rgb(0xFFF2B0), PLWEKit.rgb(0x6A4E14))
                    paints[i].entity.model?.materials = [PLWEKit.material(paints[i].mat, look: look, tex: t)]
                }
            }
        }
        return out
    }
    private var HW_secretX: Float { Self.HW * cos(asin((-9 - G.z) / Self.HL)) * 0.985 }
}
