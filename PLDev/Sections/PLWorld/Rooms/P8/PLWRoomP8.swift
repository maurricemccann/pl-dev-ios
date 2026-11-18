import RealityKit
import UIKit
import simd

// Page 8, The Launch (gemini-s340/08-the-launch-spec.md, web room8.js). A storm gorge of indigo basalt, cliffs leaning in overhead, a wet slate floor with his curve tile down the middle,
// his two clouds from plate 8 spanning the gap (gold over the test, blue beyond) and a veil of rain. Halfway a gold mark lights: hold still on it and a gold dome of his curves forms round
// him; his bolt falls from the gold cloud, meets the dome and bends away into the rock. S341's zip: hold ACT at either end of the gold curve between the bays and the integrator carries him along it (`.rail`).
// Local frame: start at the origin facing -Z, the gorge runs 30 m to the exit at z = -30.

@MainActor final class PLWRoomP8: PLWDRoom {
    private let gl: Float = 30, hw: Float = 6, ch: Float = 22, lean: Float = 2.2
    private var pts: [V3] = [], run: [Float] = []
    private var test: V3 = .zero, testSide: V3 = [1, 0, 0], studyPos: V3 = .zero
    private var goldCloud: (e: [ModelEntity], pos: V3, glow: V3)?, blueCloud: (e: [ModelEntity], pos: V3, glow: V3)?
    private var cloudTex: (a: TextureResource?, b: TextureResource?) = (nil, nil), boltTex: TextureResource?, domeTile: TextureResource?
    private var rain: ModelEntity?, rainTex: TextureResource?, rainV: Float = 0
    private var mark: ModelEntity?, dome: ModelEntity?, bolt: ModelEntity?, glance: ModelEntity?, study: ModelEntity?
    private var strikeLight = Entity(), shieldLight = Entity()
    private var still: Float = 0, strikeT: Float = -1, done = false, nearTest = false, nearStudy = false, studyFound = false
    private var zipPts: [V3] = [], railCool: Float = 0, taught = false
    private var markA: Float = 0, domeA: Float = 0, lastFlash: Float = -1, said = ""

    init() { super.init(.p8) }

    private func idx(_ s: Float) -> Int { var i = 1; while i < run.count - 1, run[i] < s { i += 1 }; return i }
    private func nrm(_ i: Int) -> V3 {
        let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)], t = V3(b.x - a.x, 0, b.z - a.z), l = max(simd_length(t), 1e-6)
        return [t.z / l, 0, -t.x / l]
    }
    private func bay(_ s: Float, _ side: Float) -> Float {
        let bays: [(sd: Float, c: Float, hw: Float)] = [(-1, 8, 2.8), (-1, 24.5, 3.8)]
        return bays.reduce(0) { $0 + ($1.sd == side ? 4.5 * PLWD.smooth($1.c - $1.hw - 2.5, $1.c - $1.hw, s) * (1 - PLWD.smooth($1.c + $1.hw, $1.c + $1.hw + 2.5, s)) : 0) }
    }
    private func off(_ s: Float, _ o: Float, _ y: Float) -> V3 { let i = idx(s); return pts[i] + nrm(i) * o + [0, y, 0] }

    override func build() async {
        let tile = await PLWD.texture("plw-tile", "P5")
        cloudTex = (await PLWD.texture("plw-cloud8a", "P8"), await PLWD.texture("plw-cloud8b", "P8")); boltTex = await PLWD.texture("plw-bolt8", "P8"); domeTile = tile
        let centre: [V3] = [[0, 0, 0], [0, 0, -5], [1.6, 0, -11], [-1.4, 0, -19], [0.4, 0, -25], [0, 0, -gl]]
        pts = PLWD.spline(centre, per: 10)
        run = [0]; for i in 1..<pts.count { run.append(run[i - 1] + simd_distance(pts[i], pts[i - 1])) }
        let basalt = PLWDSkin(hex: 0x3C4466, rough: 0.35, metal: 0.2, pageMix: 0.2, twoSided: true), wet = PLWDSkin(hex: 0x3A3E5C, rough: 0.3, metal: 0.1, pageMix: 0.15, twoSided: true)

        // the gorge: cliffs either side lean in to an 8 m gap overhead; two sheltered bays bite 4.5 m into the left cliff
        for side in [Float(1), -1] {
            let wall: [[V3]] = (0..<23).map { r in
                let y = Float(r) / 22 * ch, f = y / ch
                return pts.indices.map { c in
                    let d = hw + 0.4 * sin(run[c] * 0.9 + y * 0.6 + side) + 0.25 * sin(run[c] * 2.3 - y * 1.4) - lean * f * f + bay(run[c], side)
                    var p = pts[c] + nrm(c) * (side * d); p.y = y - 0.5; return p
                }
            }
            await solidMesh(await PLWD.ribbon(wall, metresPerUV: 3), basalt)
        }
        let wide = hw + 5.5
        let fl: [V3] = pts.indices.map { pts[$0] - nrm($0) * wide }, fr: [V3] = pts.indices.map { pts[$0] + nrm($0) * wide }
        await solidMesh(await PLWD.ribbon([fl, fr], metresPerUV: 2.5), wet)
        let tl: [V3] = pts.indices.map { pts[$0] - nrm($0) * 2 + [0, 0.012, 0] }, tr: [V3] = pts.indices.map { pts[$0] + nrm($0) * 2 + [0, 0.012, 0] }
        add(await PLWD.ribbon([tl, tr], metresPerUV: 4), PLWDSkin(hex: 0xE6E6EE, rough: 0.3, tex: tile, twoSided: true))
        let outer: [SIMD2<Float>] = [[hw + 1, 0], [hw + 1, ch], [-(hw + 1), ch], [-(hw + 1), 0]]
        let mouth = PLWD.arch(halfWidth: 2.25, base: 0, spring: 0, rise: 4.5, n: 28)
        let end = pts[pts.count - 1]
        await solidMesh(await PLWD.holedWall(hole: mouth, outer: outer, centre: [0, 1.5], at: 0, origin: [pts[0].x, 0, 0]), basalt)
        await solidMesh(await PLWD.holedWall(hole: mouth, outer: outer, centre: [0, 1.5], at: end.z, origin: [end.x, 0, 0]), basalt)
        // terraces in each bay: three rock steps (0.85 m each, a jump apiece)
        for c in [Float(8), 24.5] {
            let steps: [(o: Float, y: Float, w: Float)] = [(7.3, 0.85, 1.7), (8.6, 1.7, 1.7), (9.9, 2.55, 2.0)]
            for s in steps {
                let i = idx(c), t = pts[min(pts.count - 1, i + 1)] - pts[max(0, i - 1)]
                box([6.4, s.y + 0.3, s.w], basalt, at: pts[i] + nrm(i) * (-s.o) + [0, (s.y + 0.3) / 2 - 0.3, 0], yaw: atan2(-t.z, t.x))
            }
        }

        // his clouds from plate 8: carved layers spanning the gap (the gold one at s = 18 over the test, the blue at 26)
        func cloud(_ s: Float, _ tex: TextureResource?, _ aspect: Float, _ glow: UInt32) async -> (e: [ModelEntity], pos: V3, glow: V3) {
            let i = idx(s), t = simd_normalize(pts[min(pts.count - 1, i + 1)] - pts[max(0, i - 1)]), w = 2 * (hw - lean) + 1.2, h = w / aspect, y = ch - h * 0.55
            let q = await PLWD.quad(w, h), yaw = atan2(-t.x, -t.z)
            var layers: [ModelEntity] = []
            for k in 0..<4 { layers.append(picture(tex, q, at: pts[i] + [0, y, 0] - t * (-0.6 + Float(k) * 0.24), yaw: yaw)) }
            return (layers, pts[i] + [0, y - h * 0.3, 0], PLWD.rgb(glow))
        }
        goldCloud = await cloud(18, cloudTex.a, 290 / 200, 0xFFB020); blueCloud = await cloud(26, cloudTex.b, 315 / 170, 0x4080FF)
        tintClouds(flash: 0)

        // the rain: one veil box over the gorge, his blue rain lines streaking down it
        rainTex = await PLWD.drawn(256, opaque: false) { g in
            var rng = WorldRNG(seed: 808)
            g.setStrokeColor(UIColor(red: 0.38, green: 0.63, blue: 1, alpha: 0.9).cgColor); g.setLineWidth(1.4)
            for _ in 0..<140 { let x = CGFloat(rng.next() * 256), y = CGFloat(rng.next() * 256), l = CGFloat(12 + rng.next() * 24); g.move(to: CGPoint(x: x, y: y)); g.addLine(to: CGPoint(x: x - 1, y: y + l)); g.strokePath() }
        }
        let veil = ModelEntity(mesh: .generateBox(size: [2 * hw - 1, ch - 2, gl - 2]), materials: []); veil.position = [0, (ch - 2) / 2, -gl / 2]; root.addChild(veil); rain = veil
        setRain()

        // the test at 18 m: a gold mark on the path; hold still and the dome forms, his bolt strikes and bends into the rock
        let ti = idx(18); test = pts[ti]; testSide = nrm(ti)
        var mm = UnlitMaterial(color: UIColor.world(0xFFC000)); mm.blending = .transparent(opacity: 0)
        let mk = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 1.3), materials: [mm]); mk.position = test + [0, 0.03, 0]; root.addChild(mk); mark = mk
        let dm = ModelEntity(mesh: .generateSphere(radius: 1.8), materials: []); dm.position = test; dm.isEnabled = false; root.addChild(dm); dome = dm
        setDome(0, hit: false)
        let bh = goldCloud!.pos.y - (test.y + 1.8)
        let bl = picture(boltTex, await PLWD.quad(bh * 210 / 305, bh), at: [test.x, test.y + 1.8 + bh / 2, test.z]); bl.isEnabled = false; bolt = bl
        let gq = picture(boltTex, await PLWD.quad(2.4, 4.2), at: test - testSide * 3.4 + [0, 2.6, 0])
        gq.orientation = simd_quatf(angle: atan2(testSide.x, testSide.z), axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2.4, axis: [0, 0, 1]); gq.isEnabled = false; glance = gq

        // the secret: his bolt study carved in a slab under a ledge in the left wall at 12 m
        let si = idx(12), sn = nrm(si); studyPos = pts[si] - sn * (hw - 1.0 + bay(run[si], -1))
        let syaw = atan2(-sn.x, -sn.z)
        box([1.4, 1.6, 0.4], wet, at: studyPos + [0, 0.8, 0], yaw: syaw)
        box([2.4, 0.4, 1.6], basalt, at: studyPos + [0, 2.3, 0] - sn * 0.2, yaw: syaw)
        study = picture(boltTex, await PLWD.quad(0.85, 1.24), tint: UIColor(white: 0.45, alpha: 1), at: studyPos + [0, 0.8, 0] + sn * 0.21, yaw: syaw + .pi)

        // the zip: a gold curve from one bay's top terrace over the gorge to the other's, thicker at its two anchors (it passes 7 m over the storm mark)
        zipPts = PLWD.spline([off(8, -9.4, 2.6), off(11.5, -6.2, 4.9), off(16.2, -2.2, 7.2), off(20.6, -5.6, 5.3), off(24.5, -9.4, 2.6)], per: 14)
        add(await PLWD.tube(zipPts.map { $0 + [0, -0.16, 0] }, radius: { 0.11 * (1 + 1.6 * pow(abs(2 * $0 - 1), 6)) }, sides: 8), PLWDSkin(hex: 0xF0C44C, rough: 0.3, metal: 0.5, glow: 0xF0C44C, glowK: 1.2))

        // light: a dim storm fill, the strike light at 18 m, the shield's gold, the gold behind his cloud, the next page's colour at the way out
        sun(150, from: [4, 20, 6], toward: [0, 0, -15], color: 0x6E83B0)
        sun(420, from: [-4, 22, 8], toward: [0, 0, -15], color: 0x4A5A80)
        strikeLight = point(50_000, radius: 16, at: test + [0, 5, 0], color: 0xFFE080); level(strikeLight, 0.1)
        shieldLight = point(40_000, radius: 6, at: test + [0, 1.4, 0], color: 0xFFD700); level(shieldLight, 0)
        point(60_000, radius: 12, at: goldCloud!.pos + [0, 1.5, 0], color: 0xFFB020)
        point(60_000, radius: 9, at: end + [0, 2, 1.5], color: PLWRing.pageHex[8])

        key(0, .loveYourself, at: off(7.2, -9.9, 3.55) + [0, 1, 0]); key(1, .smiley, at: off(25.6, -9.9, 3.55) + [0, 1, 0]); key(2, .moneyGrin, at: end + [0, 1, 2])
        port("start", at: [0, 0, -1]); port("exit", at: end)
        var line: [V3] = []; for k in stride(from: 0, to: pts.count, by: 8) { line.append(pts[k]) }
        route = line + [end]
        triggers = [
            PLWTrigger(id: "p8.test", center: test + [0, 2, 0], yaw: 0, halfExtents: [7, 4, 7]),
            PLWTrigger(id: "p8.study", center: studyPos + [0, 1, 0], yaw: 0, halfExtents: [2.4, 2, 2.4]),
        ]
        if momentDone { done = true; strikeT = 3.2 }
    }

    override func restore(_ save: PLWSave) { super.restore(save); if momentDone { done = true; strikeT = 3.2 } }

    override func trigger(_ e: PLWTriggerEvent) -> [PLWCommand] {
        let inside = e.phase != .exited
        if e.id == "p8.test" { nearTest = inside }
        if e.id == "p8.study" { nearStudy = inside }
        return []
    }

    private func tintClouds(flash: Float) {
        guard let g = goldCloud, let b = blueCloud else { return }
        func paint(_ c: (e: [ModelEntity], pos: V3, glow: V3), _ tex: TextureResource?, _ k: Float) {
            for (n, e) in c.e.enumerated() {
                let m = n == 0 ? k : 0.12 / Float(n)
                setPicture(e, tex, tint: UIColor(red: CGFloat(c.glow.x * m), green: CGFloat(c.glow.y * m), blue: CGFloat(c.glow.z * m), alpha: 1), opacity: 1)
            }
        }
        paint(g, cloudTex.a, 0.55 + 0.45 * flash); paint(b, cloudTex.b, 0.6)
    }

    private func setRain() {
        guard let r = rain else { return }
        var m = UnlitMaterial()
        let t = rainTex.map { MaterialParameters.Texture($0, sampler: PLWD.sampler) }
        m.color = .init(tint: UIColor.world(0x70A0FF), texture: t)
        m.blending = .transparent(opacity: .init(scale: 0.35, texture: t))
        m.textureCoordinateTransform = .init(offset: [0, rainV], scale: [6, 3], rotation: 0); m.faceCulling = .none
        r.model?.materials = [m]
    }

    private func setDome(_ a: Float, hit: Bool) {
        guard let d = dome else { return }
        var m = UnlitMaterial()
        m.color = .init(tint: UIColor.world(hit ? 0xFFE070 : 0xFFB000), texture: domeTile.map { MaterialParameters.Texture($0, sampler: PLWD.sampler) })
        m.blending = .transparent(opacity: .init(scale: 0.8 * a)); m.faceCulling = .none
        m.textureCoordinateTransform = .init(offset: .zero, scale: [3, 1.5], rotation: 0)
        d.model?.materials = [m]
    }

    private func setMark(_ a: Float) {
        guard let m = mark else { return }
        var u = UnlitMaterial(color: UIColor.world(0xFFC000)); u.blending = .transparent(opacity: .init(scale: a))
        m.model?.materials = [u]
    }

    private func say(_ s: String) -> [PLWCommand] { guard s != said else { return [] }; said = s; return s.isEmpty ? [] : [.caption(s)] }

    override func tick(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        let dt = f.dt, p = f.position
        rainV -= dt * 1.9; setRain()
        // the zip: hold ACT within reach of either end; the integrator carries him to the other and locks input until then
        railCool = max(0, railCool - dt)
        if let first = zipPts.first, let last = zipPts.last {
            let atFirst = simd_distance(p, first) < 2.2, atLast = simd_distance(p, last) < 2.2
            if f.actHeld, railCool == 0, atFirst != atLast {
                var len: Float = 0; for i in 1..<zipPts.count { len += simd_distance(zipPts[i], zipPts[i - 1]) }
                out.append(.rail(points: atFirst ? zipPts : zipPts.reversed(), speed: 9)); railCool = len / 9 + 1.5
            }
            if !taught, atFirst || atLast { taught = true; out += say("hold ACT and steer along the gold curve to zip") }
        }
        // a soft distant flash every 4 s (no strobe)
        let flash = 0.6 * max(0, 1 - clock.truncatingRemainder(dividingBy: 4) / 0.4)
        if abs(flash - lastFlash) > 0.03 { lastFlash = flash; tintClouds(flash: flash) }
        // the test: the mark lights as he nears; holding still 0.5 s on it (or ACT) curls him round the dream under the dome; then the bolt
        let dT = flat(p, test), nearMark = nearTest && !done
        let before = markA
        markA += ((nearMark ? 0.55 : 0) - markA) * min(1, dt * 3)
        if abs(markA - before) > 0.004 { setMark(markA) }
        let quiet = simd_length(f.velocity) < 0.25 || f.actHeld
        still = (dT < 1.6 && p.y < test.y + 3 && f.grounded && quiet) ? still + dt : 0
        let curl = still > 0.5 || (strikeT >= 0 && strikeT < 3.2)
        domeA += ((curl ? 1 : 0) - domeA) * min(1, dt * 4)
        dome?.isEnabled = domeA > 0.02; dome?.position = [p.x, test.y, p.z]
        if domeA > 0.02 { setDome(domeA, hit: strikeT > 0.3 && strikeT < 1.1) }
        level(shieldLight, domeA); shieldLight.position = p + [0, 1.4, 0]
        if curl, !done, strikeT < 0, still > 1.0 { strikeT = 0 }
        if strikeT >= 0, strikeT < 3.2 {
            strikeT += dt
            let hit = strikeT > 0.3 && strikeT < 1.1
            bolt?.isEnabled = strikeT < 0.9; glance?.isEnabled = strikeT > 0.3 && strikeT < 1.3
            level(strikeLight, 0.1 + 0.9 * (strikeT > 0.3 && strikeT < 0.45 ? PLWD.smooth(0.3, 0.45, strikeT) : hit ? 1 - PLWD.smooth(0.45, 1.1, strikeT) : 0))
            bolt?.position.x = p.x; bolt?.position.z = p.z
            let l = f.lookDirection; bolt?.orientation = simd_quatf(angle: atan2(-l.x, -l.z), axis: [0, 1, 0])
            let w = PLWD.smooth(0, 0.4, strikeT) * (1 - PLWD.smooth(2.6, 3.2, strikeT))
            out.append(.camera(position: p + V3(testSide.z, 0, -testSide.x) * 5.2 + [0, -0.4, 0], target: p + [0, 2.2, 0], weight: w))
            if strikeT >= 3.2 { done = true; bolt?.isEnabled = false; glance?.isEnabled = false; level(strikeLight, 0.1); out += finish() }
        }
        if nearMark, strikeT < 0, dT < 3 { out += say("hold still") } else if done || dT >= 3, said == "hold still" { _ = say("") }
        if !studyFound, nearStudy, f.actPressed {
            studyFound = true; out.append(.mark("p8.study")); out += say("his bolt, carved")
            if let s = study { setPicture(s, boltTex, tint: UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1), opacity: 1) }
        }
        return out
    }
}
