import RealityKit
import UIKit
import simd

// Page 6, The Dwarfing (gemini-s340/06-the-dwarfing-spec.md, web room6.js). A forest bowl 34 m across, mostly grey, and his tree 28 m tall with his eyes (the pupils follow GlyphGuy)
// and plate 6's grin. Stand in the circle before the face: the camera climbs the trunk, an emerald wave follows it, the grin warms to gold and colour comes back.
// S341's tree-as-a-place: a root shelf ringing the trunk 9 m up and a green updraft that floats him to it (hold JUMP, the `.lift` command). Local frame: start at the origin facing -Z, exit at z = -34.2.

@MainActor final class PLWRoomP6: PLWDRoom {
    private let radius: Float = 17, wallH: Float = 16
    private let bowl: V3 = [0, 0, -17], tree: V3 = [0, 0, -19.5], lookAt: V3 = [0, 0, -7.5]
    private let faceY: Float = 8.6
    private var canopy: [ModelEntity] = [], turf: [ModelEntity] = [], bark: [ModelEntity] = []
    private var canopySkin = PLWDSkin(hex: 0x4F8A5A, rough: 0.85, pageMix: 0.1), turfSkin = PLWDSkin(hex: 0x243322, rough: 0.95, pageMix: 0.1), barkSkin = PLWDSkin(hex: 0x4A3B30, rough: 0.85)
    private var face: ModelEntity?, wave: ModelEntity?, carve: ModelEntity?
    private var grin = Entity(), faceTex: TextureResource?
    private var pupils: [(e: ModelEntity, c: V3, tg: V3, u: Float, v: Float)] = []
    private var lookT: Float = -1, colour: Float = 0, lastColour: Float = -1, inLook = false, nearCarve = false, carveFound = false, said = ""
    private var carvePos: V3 = .zero, updraft: V3 = .zero, taught = false
    private let shelfY: Float = 9, updraftH: Float = 10.6

    init() { super.init(.p6) }

    override func build() async {
        let tile = await PLWD.texture("plw-tile", "P5"), face6 = await PLWD.texture("plw-treeface6", "P6"), pupilTex = await PLWD.texture("plw-pupil", "P5")
        faceTex = face6
        let rock = PLWDSkin(hex: 0x6A7A6A, rough: 0.9, pageMix: 0.25, twoSided: true)
        turfSkin.grey = 0.8; canopySkin.grey = 1; barkSkin.grey = 0.4
        // the bowl: high mossy rock all round, a gap in from the tunnel and one out under the far root
        let gIn = asin(2.8 / radius), gOut = asin(2.4 / radius)
        var angles: [Float] = []
        for i in 0...110 { let a = gIn + Float(i) / 110 * (2 * .pi - 2 * gIn); if abs(a - .pi) > gOut { angles.append(a) } }
        var runs: [[Float]] = [[]]
        for a in angles { if let l = runs[runs.count - 1].last, a - l > 0.2 { runs.append([a]) } else { runs[runs.count - 1].append(a) } }
        for (k, run) in runs.enumerated() where run.count > 1 {
            let rows: [[V3]] = (0..<13).map { r in
                let y = Float(r) / 12 * wallH
                return run.map { a in let d = radius + 0.4 + 0.5 * sin(a * 9 + y * 0.7 + Float(k)) + 0.06 * y; return bowl + [sin(a) * d, y, cos(a) * d] }
            }
            await solidMesh(await PLWD.ribbon(rows, metresPerUV: 3), rock)
        }
        let ground = add(.generateCylinder(height: 0.2, radius: radius + 1.2), turfSkin, at: bowl + [0, -0.1, 0], shape: .generateBox(size: [(radius + 1.2) * 2, 0.2, (radius + 1.2) * 2]))
        turf.append(ground)
        // the 3.5 m loop of his curve tile round the tree, and the spur in from the tunnel
        let tileSkin = PLWDSkin(hex: 0xD8DCCF, rough: 0.65, tex: tile, uv: [1, 1])
        let inner: [V3] = (0...96).map { i in let a = Float(i) / 96 * 2 * .pi; return tree + [sin(a) * 9.25, 0.015, cos(a) * 9.25] }
        let outer: [V3] = (0...96).map { i in let a = Float(i) / 96 * 2 * .pi; return tree + [sin(a) * 12.75, 0.015, cos(a) * 12.75] }
        add(await PLWD.ribbon([inner, outer], metresPerUV: 3.5), tileSkin)
        let spurL: [V3] = [[-1.75, 0.016, -0.5], [-1.75, 0.016, tree.z + 11]], spurR: [V3] = [[1.75, 0.016, -0.5], [1.75, 0.016, tree.z + 11]]
        add(await PLWD.ribbon([spurL, spurR], metresPerUV: 3.5), tileSkin)

        // the tree: a 28 m trunk, 9 m at the foot, roots into the earth, a crown of swelling masses
        let profile: [(r: Float, y: Float)] = [(6.2, 0), (5.1, 0.8), (4.6, 2.5), (4.6, 6), (4.5, 11), (4.0, 15), (3.4, 19), (3.8, 21.5), (2.6, 23), (0.01, 23.2)]
        let trunk = await solidMesh(await PLWD.lathe(profile, segments: 48), barkSkin.twoSidedCopy(), at: tree); bark.append(trunk)
        var backRoot: V3 = tree + [0, 2, 7.2]
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + 0.2, c = sin(a), s = cos(a)
            if abs(atan2(c, s)) < 0.35 { continue }                                   // the front stays open to the face
            let reach: [(r: Float, y: Float)] = [(4.4, 2.2), (6.5, 1.5), (8.6, 0.6), (9.6, -0.6)]
            let pts: [V3] = reach.map { tree + V3(c * $0.r, $0.y, s * $0.r) }
            let m = await PLWD.tube(PLWD.spline(pts, per: 6), radius: { 1.25 - 0.65 * $0 }, sides: 10)
            bark.append(await solidMesh(m, barkSkin.twoSidedCopy()))
            if abs(abs(atan2(c, s)) - .pi) < 0.4 { backRoot = tree + [c * 7.2, 2.0, s * 7.2] }
        }
        var rng = WorldRNG(seed: 606)
        for k in 0..<12 {
            let a = Float(k) / 12 * 2 * .pi + rng.next() * 0.4, c = sin(a), s = cos(a), r = 5 + rng.next() * 6, y = 21 + rng.next() * 6
            let limb: [V3] = [tree + V3(c * 1.5, 19.5, s * 1.5), tree + V3(c * r * 0.6, y - 1, s * r * 0.6), tree + V3(c * r, y, s * r)]
            bark.append(add(await PLWD.tube(PLWD.spline(limb, per: 6), radius: { 0.9 - 0.35 * $0 }, sides: 10), barkSkin.twoSidedCopy()))
            let mass = add(.generateSphere(radius: 1), canopySkin, at: tree + [c * r, y + 1.2, s * r]); mass.scale = [(9 + rng.next() * 4) / 2, (4.5 + rng.next() * 2) / 2, (8 + rng.next() * 4) / 2]
            canopy.append(mass)
        }
        // his face: his eye twice and plate 6's grin; the pupils turn toward GlyphGuy
        let fw: Float = 5.4, fh = fw * 1403 / 1238, fs = fw / 1238
        face = picture(face6, await PLWD.quad(fw, fh), at: tree + [0, faceY, 6.0])
        for ex in [Float(243), 995] {
            let x = (ex - 619) * fs, y = faceY + (701.5 - 347) * fs, z = (4.55 * 4.55 - x * x).squareRoot(), n = simd_normalize(V3(x, 0, z))
            let c = tree + [x, y, z] + n * 1.5
            let e = picture(pupilTex, await PLWD.quad(123 * fs, 256 * fs), tint: .black, at: c, yaw: atan2(n.x, n.z))
            pupils.append((e, c, simd_normalize(simd_cross([0, 1, 0], n)), 0, 0))
        }
        // the root shelf ringing the trunk 9 m up (round the sides and back, never over his face), and the green updraft on the east that floats him up to it
        let ringPts: [V3] = (0...22).map { k in let a = 1.0 + Float(k) / 22 * (2 * .pi - 2.0); return tree + V3(sin(a) * 5.9, shelfY - 0.65, cos(a) * 5.9) }
        for k in 0..<22 {
            let a = ringPts[k], b = ringPts[k + 1], m = (a + b) / 2, d = b - a
            bark.append(box([simd_length(d) + 0.15, 1.3, 3.4], barkSkin.twoSidedCopy(), at: m, yaw: atan2(-d.z, d.x), round: 0.1))
        }
        updraft = tree + V3(sin(1.75) * 10.2, 0, cos(1.75) * 10.2)
        let col = ModelEntity(mesh: .generateCylinder(height: updraftH, radius: 2), materials: [])
        var um = UnlitMaterial(color: UIColor.world(0x2EE676)); um.blending = .transparent(opacity: 0.25); um.faceCulling = .none; col.model?.materials = [um]
        col.position = updraft + [0, updraftH / 2, 0]; root.addChild(col)
        // the emerald wave that climbs the trunk
        var wm = UnlitMaterial(color: UIColor.world(0x2EE676)); wm.blending = .transparent(opacity: 0.45)
        let w = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 5.2), materials: [wm]); w.position = tree + [0, 1, 0]; w.isEnabled = false; root.addChild(w); wave = w
        // the secret: his curve carved into the thick root behind the trunk (the plaque stands in until his curve art is rasterised)
        carvePos = backRoot
        carve = add(.generateBox(size: [0.9, 0.1, 1.2], cornerRadius: 0.02), PLWDSkin(hex: 0x2A211B, rough: 0.9, glow: 0xC8D8A8, glowK: 0), at: backRoot + [0, 0.5, 0])

        // the way out: an arch of root under the far wall
        let x0: V3 = [0, 0, bowl.z - radius - 0.2]
        let archPts: [V3] = [[-4.6, -0.5, 1.2], [-3.0, 4.2, 0.4], [0, 5.9, 0], [3.0, 4.2, 0.4], [4.6, -0.5, 1.2]]
        let arch = PLWD.spline(archPts.map { x0 + $0 }, per: 8)
        bark.append(await solidMesh(await PLWD.tube(arch, radius: { _ in 1.1 }, sides: 10), barkSkin.twoSidedCopy()))

        // light: the canopy sun, the bowl's fill, the gold in the grin (dark until he looks up), the next page's colour at the way out
        sun(480, from: bowl + [10, 50, -15], toward: bowl, color: 0x85D685)
        sun(140, from: bowl + [-6, 12, 20], toward: bowl, color: 0x78A878)
        grin = point(60_000, radius: 10, at: tree + [0, faceY - 1.6, 6.5], color: 0xFFD700); level(grin, 0.07)
        point(50_000, radius: 8, at: x0 + [0, 1.6, 1], color: PLWRing.pageHex[6])

        key(0, .money, at: [7.5, 1.0, -10]); key(1, .smiley, at: [-9.5, 1.0, -26]); key(2, .loveYourself, at: backRoot + [2.6, 0.9, 0.5])
        port("start", at: [0, 0, -0.5]); port("exit", at: x0)
        route = [[0, 0, -0.5], lookAt, tree + [11, 0, 0], tree + [0, 0, -11], x0]
        triggers = [
            PLWTrigger(id: "p6.look", center: lookAt + [0, 1, 0], yaw: 0, halfExtents: [3, 2, 3]),
            PLWTrigger(id: "p6.carving", center: backRoot + [0, 1, 0], yaw: 0, halfExtents: [3.2, 2, 3.2]),
        ]
        if momentDone { lookT = 6; colour = 1 }
        paint()
    }

    override func restore(_ save: PLWSave) { super.restore(save); if momentDone { lookT = 6; colour = 1; paint() } }

    override func trigger(_ e: PLWTriggerEvent) -> [PLWCommand] {
        let inside = e.phase != .exited
        if e.id == "p6.look" { inLook = inside; if inside, lookT < 0 { lookT = 0 } }
        if e.id == "p6.carving" { nearCarve = inside }
        return []
    }

    /// Colour returning: grey falls away from the crown, the turf and the bark (re-skinned in coarse steps).
    private func paint() {
        guard abs(colour - lastColour) > 0.04 || colour >= 1 && lastColour < 1 else { return }
        lastColour = colour
        canopySkin.grey = 1 - colour; turfSkin.grey = 0.8 * (1 - colour); barkSkin.grey = 0.4 * (1 - colour)
        reskinAll(canopy, canopySkin); reskinAll(turf, turfSkin); reskinAll(bark, barkSkin.twoSidedCopy())
        if let f = face { setPicture(f, faceTex, tint: UIColor(red: 1, green: CGFloat(0.9 + 0.1 * colour), blue: CGFloat(0.8 - 0.3 * colour), alpha: 1), opacity: 1) }
    }

    private func say(_ s: String) -> [PLWCommand] { guard s != said else { return [] }; said = s; return s.isEmpty ? [] : [.caption(s)] }

    override func tick(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        let dt = f.dt, p = f.position
        if lookT >= 0, lookT < 5.4, !momentDone { lookT += dt }
        else if lookT >= 5.4, !momentDone { out += finish() }
        if lookT >= 0, lookT < 5.4 {
            // low behind him, the aim climbing from him up the trunk to the crown (about 65 degrees)
            let away = simd_normalize(V3(p.x - tree.x, 0, p.z - tree.z)), up = PLWD.smooth(0.5, 2.5, lookT)
            let w = PLWD.smooth(0.3, 1.0, lookT) * (1 - PLWD.smooth(4.5, 5.4, lookT))
            out.append(.camera(position: p + away * 4.2 + [0, 0.6, 0], target: simd_mix(p + [0, 1.2, 0], tree + [0, 19, 0], V3(repeating: up)), weight: w))
            let wv = PLWD.smooth(2.5, 4.0, lookT)
            wave?.isEnabled = wv > 0 && wv < 1
            wave?.position = tree + [0, 1 + 21 * wv, 0]; let r = (4.6 - 0.8 * wv) / 5.2; wave?.scale = [r, 1, r]
            colour = PLWD.smooth(2.8, 4.4, lookT)
            level(grin, 0.07 + 0.93 * PLWD.smooth(3.8, 4.2, lookT))
        } else { wave?.isEnabled = false; level(grin, momentDone ? 1 : 0.07) }
        paint()
        // the updraft: hold JUMP inside the green column and the integrator lifts him (it clamps the acceleration)
        let inDraft = flat(p, updraft) < 2.1 && p.y < updraftH
        if inDraft, f.jumpHeld { out.append(.lift(22)) }
        if !taught, flat(p, updraft) < 6, lookT >= 5.4 || momentDone { taught = true; out += say("hold JUMP in the green updraft to float") }
        if lookT < 0, flat(p, lookAt) < 7 { out += say("look up") } else if said == "look up" { _ = say("") }
        for i in pupils.indices {
            let d = p + [0, 0.6, 0] - pupils[i].c, l = max(simd_length(d), 0.001)
            var u = simd_dot(d, pupils[i].tg) / l * 0.7, v = d.y / l * 1.2
            let k = hypot(u / 0.38, v / 0.72); if k > 1 { u /= k; v /= k }
            pupils[i].u += (u - pupils[i].u) * min(1, dt * 3); pupils[i].v += (v - pupils[i].v) * min(1, dt * 3)
            pupils[i].e.position = pupils[i].c + pupils[i].tg * pupils[i].u + [0, pupils[i].v, 0]
        }
        if !carveFound, nearCarve, f.actPressed {
            carveFound = true; out.append(.mark("p6.carving")); out += say("his curve, carved in the root")
            if let c = carve { reskin(c, PLWDSkin(hex: 0x2A211B, rough: 0.9, glow: 0xC8D8A8, glowK: 0.6)) }
        }
        return out
    }
}
