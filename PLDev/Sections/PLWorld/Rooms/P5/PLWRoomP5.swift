import RealityKit
import UIKit
import simd

// Page 5, The Equation (build spec: gemini-s340/05-the-equation-spec.md, web room5.js). A whitewashed barrel-vaulted cottage, a stone table before a great arched window,
// his tree beyond the glass. Step up to the table and the tree's thought lights in the glass part by part (his own bubble, never redrawn). A moonbeam then finds a patch of
// earth in the walled garden: hold ACT there and the dream he buried in page 4 rises into his hands. Local frame: start at the origin facing -Z, exit at z = -24.

@MainActor final class PLWRoomP5: PLWDRoom {
    private let cl: Float = 12, cw: Float = 4.5, wall: Float = 3.2, vault: Float = 1.8, gr: Float = 12, gwh: Float = 5.4
    private let soil: V3 = [1.4, 0, -18.5], table: V3 = [0, 0, -6.5], tree: V3 = [-3.6, 0, -21.6]
    private var bubble = Entity(), bubbleFull: ModelEntity?, bubbleParts: [(ModelEntity, Float)] = []
    private var mound: ModelEntity?, orb: ModelEntity?, seed: ModelEntity?
    private var beam = Entity(), gold = Entity(), windowGlow = Entity()
    private var pupils: [(e: ModelEntity, c: V3, u: Float, v: Float)] = []
    private var toHouse: V3 = [0, 0, 1], side: V3 = [1, 0, 0]
    private var tex: (bubble: TextureResource?, pupil: TextureResource?) = (nil, nil)
    private var eqT: Float = -1, digT: Float = -1, nearTable = false, onPatch = false, onSeed = false
    private var seedFound = false, seedLit = false, said = "", recovered = false

    init() { super.init(.p5) }

    override func build() async {
        let tile = await PLWD.texture("plw-tile", "P5"), bubbleTex = await PLWD.texture("plw-bubble5", "P5")
        let faceTex = await PLWD.texture("plw-treeface5", "P5"), pupilTex = await PLWD.texture("plw-pupil", "P5")
        tex = (bubbleTex, pupilTex)
        let plaster = PLWDSkin(hex: 0xD6DAE0, rough: 0.85, pageMix: 0.12, twoSided: true)
        let oak = PLWDSkin(hex: 0x2C1F18, rough: 0.55)
        let stone = PLWDSkin(hex: 0xA8A090, rough: 0.8, pageMix: 0.1)
        let garden = PLWDSkin(hex: 0x8C96A0, rough: 0.9, pageMix: 0.15)

        // the cottage shell: a barrel vault, 12 m long, 9 m wide, 5 m under the crown
        var section: [V3] = [[cw, 0, 0], [cw, wall, 0]]
        for i in 1..<20 { let a = Float(i) / 20 * .pi; section.append([cos(a) * cw, wall + sin(a) * vault, 0]) }
        section += [[-cw, wall, 0], [-cw, 0, 0]]
        let near = section.map { V3($0.x, $0.y, 0) }, far = section.map { V3($0.x, $0.y, -cl) }
        await solidMesh(await PLWD.ribbon([near, far], metresPerUV: 2.5), plaster)
        let outline = section.map { SIMD2<Float>($0.x, $0.y) }
        await solidMesh(await PLWD.holedWall(hole: PLWD.arch(halfWidth: 2.1, base: 0, spring: 3.0, rise: 1.68), outer: outline, centre: [0, 1.5], at: 0), plaster)
        let win = PLWD.arch(halfWidth: 2.25, base: 0, spring: 2.6, rise: 1.8)
        await solidMesh(await PLWD.holedWall(hole: win, outer: outline, centre: [0, 1.6], at: -cl), plaster)
        // the window's dark oak frame, swelling, and one mullion splitting the fixed glass (left) from the open light (right, the way into the garden)
        let frameOuter = PLWD.arch(halfWidth: 2.5, base: 0, spring: 2.6, rise: 2.0)
        add(await PLWD.holedWall(hole: win, outer: frameOuter, centre: [0, 1.6], at: -cl + 0.06), oak)
        box([0.24, 3.6, 0.24], oak, at: [0.55, 1.8, -cl + 0.06], round: 0.1)
        let glass = ModelEntity(mesh: .generateBox(size: [2.75, 3.4, 0.02]), materials: [])
        glass.position = [-0.85, 1.75, -cl + 0.02]; root.addChild(glass)
        var gm = UnlitMaterial(); gm.color = .init(tint: UIColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1)); gm.blending = .transparent(opacity: 0.22); glass.model?.materials = [gm]

        // inside: his curve tile with silver grout, the stone table, the slate with his seed under it
        box([cw * 2, 0.2, cl], PLWDSkin(hex: 0xC0C8D0, rough: 0.5, tex: tile, uv: [cw * 2 / 2.25, cl / 2.25]), at: [0, -0.1, -cl / 2], round: 0)
        box([2.0, 0.6, 1.0], stone, at: table + [0, 0.3, 0])
        let slate = box([0.7, 0.04, 0.7], PLWDSkin(hex: 0x3A3F47, rough: 0.8), at: table + [0.75, 0.02, 0.55], solid: false, round: 0)
        seed = add(.generateBox(size: [0.34, 0.012, 0.34], cornerRadius: 0.004), PLWDSkin(hex: 0x23262B, rough: 0.9, glow: 0xFFD27A, glowK: 0), at: [0, 0.026, 0], to: slate)

        // the walled garden: a half circle of 12 m behind the cottage, stone walls, pavers; the way out is a stone gate at its far end
        let ground = add(.generateCylinder(height: 0.2, radius: gr + 1.2), garden, at: [0, -0.11, -cl], shape: .generateBox(size: [(gr + 1.2) * 2, 0.2, (gr + 1.2) * 2]))
        _ = ground
        let gap = asin(2.4 / gr)
        var angles: [Float] = []; for i in 0...48 { let a = -Float.pi / 2 + Float(i) / 48 * .pi; if abs(a) > gap { angles.append(a) } }
        for run in [angles.filter { $0 < 0 }, angles.filter { $0 > 0 }] where run.count > 1 {
            let lo = run.map { V3(sin($0) * gr, 0, -cl - cos($0) * gr) }, hi = lo.map { $0 + [0, gwh, 0] }
            await solidMesh(await PLWD.ribbon([lo, hi], metresPerUV: 2), PLWDSkin(hex: 0x8C969F, rough: 0.9, pageMix: 0.12, twoSided: true))
        }
        for sx in [Float(1), -1] { box([gr - cw, gwh, 0.6], garden, at: [sx * (cw + (gr - cw) / 2), gwh / 2, -cl - 0.3]) }
        let gate = await PLWD.holedWall(hole: PLWD.arch(halfWidth: 2.25, base: 0, spring: 0, rise: 4.4, n: 28), outer: [[4.2, 0], [4.2, gwh + 0.6], [-4.2, gwh + 0.6], [-4.2, 0]], centre: [0, 1.8], at: -cl - gr)
        await solidMesh(gate, PLWDSkin(hex: 0x8C969F, rough: 0.9, pageMix: 0.12, twoSided: true))

        // the soil patch, mossed round, the buried gold under it
        mound = add(.generateSphere(radius: 0.9), PLWDSkin(hex: 0x2A221C, rough: 1), at: soil + [0, 0.02, 0])
        mound?.scale = [1, 0.2, 1]
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi, r = 1.5 + Float(k % 3) * 0.35
            let m = add(.generateSphere(radius: 0.4), PLWDSkin(hex: 0x2A5A4A, rough: 1, glow: 0x0B241C, glowK: 0.3), at: soil + [cos(a) * r, 0.03, sin(a) * r]); m.scale = [1.1, 0.14, 0.9]
        }
        orb = add(.generateSphere(radius: 0.2), PLWDSkin(hex: 0xFFD700, rough: 0.2, metal: 0.4, glow: 0xFFD700, glowK: 1.4), at: soil + [0, 0.05, 0]); orb?.isEnabled = false

        // his tree beyond the window, by the garden's left wall: trunk, crown, his face with eyes that follow him
        let bark = PLWDSkin(hex: 0x6B5A4C, rough: 0.9, pageMix: 0.05, twoSided: true)
        let trunkProfile: [(r: Float, y: Float)] = [(2.4, 0), (1.8, 0.8), (1.4, 2.5), (1.3, 5), (1.45, 7.2), (1.2, 8.4), (0.01, 8.5)]
        await solidMesh(await PLWD.lathe(trunkProfile), bark, at: tree)
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi
            let m = add(.generateSphere(radius: 1.0), PLWDSkin(hex: 0x3F6A58, rough: 0.9, pageMix: 0.2), at: tree + [cos(a) * 2.8, 9.4 + Float(k % 2) * 0.6, sin(a) * 2.8]); m.scale = [2.4, 1.1, 2.2]
        }
        let dx = V3(0 - tree.x, 0, -cl + 3 - tree.z); toHouse = simd_normalize(dx); side = simd_normalize(simd_cross([0, 1, 0], toHouse))
        let yaw = atan2(toHouse.x, toHouse.z), fW: Float = 1.9, fs = fW / 1031
        _ = picture(faceTex, await PLWD.quad(fW, fW * 1367 / 1031), at: tree + [0, 5.6, 0] + toHouse * 1.42, yaw: yaw)
        for sx in [Float(-1), 1] {
            let off = sx * (839 - 515.5) * fs
            let c = tree + [0, 5.6 + (683.5 - 347) * fs, 0] + toHouse * 1.5 + side * off
            let e = picture(pupilTex, await PLWD.quad(123 * fs, 256 * fs), tint: .black, at: c, yaw: yaw)
            pupils.append((e, c, 0, 0))
        }
        // the moon: a pale crescent high over the garden wall, seen through the glass
        let moon = ModelEntity(mesh: .generateSphere(radius: 2.5), materials: [UnlitMaterial(color: UIColor.world(0xF0F4FF))]); moon.position = [-3, 16, -cl - 40]; root.addChild(moon)
        let bite = ModelEntity(mesh: .generateSphere(radius: 2.3), materials: [UnlitMaterial(color: UIColor.world(0x0B1020))]); bite.position = [-1.7, 16.7, -cl - 38.5]; root.addChild(bite)

        // the bubble, in the glass of the tree's thought: the outline faint, then him, then + the dream, then = and him holding it
        let bw: Float = 3.6, bh = bw * 640 / 623
        bubble = Entity(); bubble.scale = .zero; root.addChild(bubble)
        let full = ModelEntity(mesh: await PLWD.quad(bw, bh), materials: []); bubble.addChild(full); bubbleFull = full
        setPicture(full, bubbleTex, tint: .white, opacity: 0.18)
        for (r, from) in [(SIMD4<Float>(225, 60, 352, 260), Float(1.0)), (SIMD4<Float>(352, 140, 560, 260), 2.2), (SIMD4<Float>(260, 255, 560, 580), 3.4)] {
            let w = (r.z - r.x) / 623 * bw, h = (r.w - r.y) / 640 * bh
            let e = ModelEntity(mesh: await PLWD.quad(w, h, uv: [r.x / 623, r.y / 640, r.z / 623, r.w / 640]), materials: [])
            e.position = [((r.x + r.z) / 2 - 311.5) / 623 * bw, -((r.y + r.w) / 2 - 320) / 640 * bh, 0.01]
            bubble.addChild(e); setPicture(e, bubbleTex, tint: .white, opacity: 0); bubbleParts.append((e, from))
        }

        // light: the cool moon through the window, the room's own glow, the window's glow, the moonbeam onto the patch, the dream's gold under the soil
        sun(420, from: [12, 30, -cl - 30], toward: [0, 0, -cl], color: 0xA5C4F0)
        sun(90, from: [0, 20, 0], toward: [0, 0, -4], color: 0x8FA0C8)
        point(45_000, radius: 11, at: [0, 3.6, -4], color: 0x7E92B8)
        windowGlow = point(40_000, radius: 7, at: [-0.85, 2.2, -cl + 1.2], color: 0xB0D0FF)
        beam = spot(120_000, radius: 16, from: [-0.4, 4.2, -cl + 0.5], toward: soil, color: 0xD8E6FF)
        gold = point(60_000, radius: 6, at: soil + [0, 0.5, 0], color: 0xFFD700)
        level(beam, 0); level(gold, 0)
        level(windowGlow, 0.4)

        // keys, ports, the guiding path
        key(0, .glyphGuy, at: [-3.3, 1.0, -2.6]); key(1, .loveYourself, at: [6.5, 1.0, -cl - 4.5]); key(2, .smiley, at: [-6.8, 1.0, -cl - 10.6])
        port("start", at: [0, 0, -0.5]); port("exit", at: [0, 0, -cl - gr])
        route = [[0, 0, -0.5], [0, 0, -4.2], [1.4, 0, -cl + 0.2], soil + [0, 0, 2.2], [0, 0, -cl - gr + 3], [0, 0, -cl - gr]]
        triggers = [
            PLWTrigger(id: "p5.table", center: table + [0, 1, 0], yaw: 0, halfExtents: [2.6, 1.5, 2.6]),
            PLWTrigger(id: "p5.dig", center: soil + [0, 1, 0], yaw: 0, halfExtents: [1.4, 1.5, 1.4]),
            PLWTrigger(id: "p5.seed", center: table + [0.75, 0.5, 0.55], yaw: 0, halfExtents: [1.3, 1, 1.3]),
        ]
    }

    override func restore(_ save: PLWSave) {
        super.restore(save)
        recovered = save.dream == .recovered || save.dream == .embraced || save.completed.contains(.p5)
        if recovered { eqT = 6; digT = 3 }
    }

    override func trigger(_ e: PLWTriggerEvent) -> [PLWCommand] {
        let inside = e.phase != .exited
        switch e.id {
        case "p5.table": nearTable = inside; if inside, eqT < 0 { eqT = 0 }
        case "p5.dig": onPatch = inside
        case "p5.seed": onSeed = inside
        default: break
        }
        return []
    }

    private func say(_ s: String) -> [PLWCommand] { guard s != said else { return [] }; said = s; return s.isEmpty ? [] : [.caption(s)] }

    override func tick(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        let dt = f.dt, p = f.position
        if !recovered, eqT >= 0, eqT < 6 { eqT += dt }
        // the equation: the tree speaks in his bubble, part by part
        let k = min(1, max(0, eqT) / 0.45), pop = 1 - pow(1 - k, 3) * (1 + 1.4 * (1 - k))
        let bp = tree + toHouse * 4.6 + side * 1.2 + [0, 3.3, 0]
        bubble.position = bp
        bubble.scale = eqT < 0 ? .zero : V3(repeating: max(0.001, pop))
        let towards = p - bp; bubble.orientation = simd_quatf(angle: atan2(towards.x, towards.z), axis: [0, 1, 0])
        if let full = bubbleFull, eqT >= 0 { setPicture(full, tex.bubble, tint: .white, opacity: 0.18 + 0.82 * PLWD.smooth(4.4, 5.0, eqT)) }
        for (e, from) in bubbleParts where eqT >= 0 { setPicture(e, tex.bubble, tint: .white, opacity: PLWD.smooth(from, from + 1, eqT)) }
        level(windowGlow, 0.4 + 0.6 * PLWD.smooth(0, 5, max(0, eqT)))
        let ready = eqT >= 5
        level(beam, PLWD.smooth(5, 6, max(0, eqT)))
        if eqT >= 0, eqT < 6 { let w = PLWD.smooth(0, 0.6, eqT) * (1 - PLWD.smooth(5.2, 6, eqT)); out.append(.camera(position: p + [0, 0.5, 4.2], target: [-0.85, 3.2, -cl], weight: w)) }
        // the digging: kneel in the patch and hold ACT; the soil gives way, gold bleeds up, the dream rises into his hands
        if digT < 0, ready, onPatch, f.actHeld { digT = 0 }
        if digT >= 0, digT < 3 {
            digT += dt
            let brush = PLWD.smooth(0, 1.5, digT), lift = PLWD.smooth(1.5, 2.5, digT)
            mound?.scale = [1, 0.2 * (1 - 0.85 * brush), 1]; level(gold, brush)
            if digT > 1.5 { orb?.isEnabled = true; orb?.position = simd_mix(soil + [0, 0.05, 0], p + [0, 1.1, 0], V3(repeating: lift)); out.append(.raiseDream(lift)) }
            out.append(.camera(position: p + [0, 2.2, 3.8], target: p + [0, 0.4, 0], weight: 0.8))
            if digT >= 2.5, !recovered { recovered = true; out.append(.dream(.recovered)) }
            if digT >= 3 { orb?.isEnabled = false; out += finish() }
        } else if digT >= 3 {
            level(gold, 0.25); mound?.scale = [1, 0.03, 1]
        } else {
            level(gold, ready ? 0.12 + 0.04 * sin(clock * 2.5) : 0)
        }
        if ready, digT < 0, onPatch { out += say("hold ACT to dig") } else if said == "hold ACT to dig" { _ = say("") }
        // his tree's eyes follow him
        for i in pupils.indices {
            let d = p + [0, 0.6, 0] - pupils[i].c, l = max(simd_length(d), 0.001)
            var u = simd_dot(d, side) / l * 0.25, v = d.y / l * 0.45
            let kk = hypot(u / 0.14, v / 0.27); if kk > 1 { u /= kk; v /= kk }
            pupils[i].u += (u - pupils[i].u) * min(1, dt * 4); pupils[i].v += (v - pupils[i].v) * min(1, dt * 4)
            pupils[i].e.position = pupils[i].c + side * pupils[i].u + [0, pupils[i].v, 0]
        }
        // the secret: his seed curve under the table
        if !seedFound, onSeed, f.actPressed { seedFound = true; out.append(.mark("p5.seed")); out += say("his seed, carved in slate") }
        if !seedLit, seedFound || save.marks.contains("p5.seed"), let s = seed { seedLit = true; reskin(s, PLWDSkin(hex: 0x23262B, rough: 0.9, glow: 0xFFD27A, glowK: 0.7)) }
        return out
    }
}
