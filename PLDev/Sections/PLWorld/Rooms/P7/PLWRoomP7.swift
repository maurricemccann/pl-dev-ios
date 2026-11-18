import RealityKit
import UIKit
import simd

// Page 7, The Transcendence (gemini-s340/07-the-transcendence-spec.md, web room7.js). A mauve-slate amphitheatre; a terraced teal hill against the back cliff with his curve tile
// switching back up its face. Three doubters stand as carved stelae of stick figures; as he passes, a mauve X draws itself over each. A stone arch carries his plate 7 bubble,
// lit as he passes under. At the summit a cyan ring forms round the dream, its first. Local frame: start at the origin facing -Z; the hill's summit gate is the exit at z = -47.1.
// His art here: stick figures lifted from plate 3 and the X marks from plate 7 of the Curve Who (small crops, his line kept exactly; see LANES-plw-d.md).

@MainActor final class PLWRoomP7: PLWDRoom {
    private let re: Float = 24, cliff: Float = 26, hh: Float = 12
    private let centre: V3 = [0, 0, -24], summit: V3 = [0, 12, -42]
    private var path: [V3] = [], run: [Float] = []
    private var arch: V3 = .zero, archSide: V3 = [1, 0, 0], studyPos: V3 = .zero
    private var stelae: [(holder: Entity, x: ModelEntity, xTex: TextureResource?, t: Float, base: V3)] = []
    private var bubble: ModelEntity?, bubbleTex: TextureResource?, bubbleLight = Entity(), ringLight = Entity()
    private var ring: ModelEntity?, study: ModelEntity?, studyArt: TextureResource?
    private var under: Float = 0, bubT: Float = 0, crestT: Float = -1, ringOn = false, nearStudy = false, studyFound = false, onSummit = false, inArch = false, said = ""

    init() { super.init(.p7) }

    private func along(_ f: Float) -> Int { let t = f * run[run.count - 1]; var i = 1; while i < run.count - 1, run[i] < t { i += 1 }; return i }
    private func sideAt(_ i: Int) -> V3 {
        let a = path[max(0, i - 1)], b = path[min(path.count - 1, i + 1)], t = V3(b.x - a.x, 0, b.z - a.z), l = max(simd_length(t), 1e-6)
        return [t.z / l, 0, -t.x / l]
    }

    override func build() async {
        bubbleTex = await PLWD.texture("plw-bubble7", "P7")
        let tile = await PLWD.texture("plw-tile", "P5")
        // the path: switchbacks up the hill's face, a steady 15 % climb
        let legs: [SIMD2<Float>] = [[0, 22], [-11, 18], [11, 13], [-10, 8.5], [6, 5.5], [0, 3.6], [0, 0]]
        path = [V3(summit.x + legs[0].x, 0, summit.z + legs[0].y)]
        for i in 1..<legs.count {
            let a = path.last!, b = V3(summit.x + legs[i].x, 0, summit.z + legs[i].y), n = Int((simd_distance(a, b) / 0.4).rounded(.up))
            for k in 1...n { path.append(simd_mix(a, b, V3(repeating: Float(k) / Float(n)))) }
        }
        run = [0]; for i in 1..<path.count { run.append(run[i - 1] + simd_distance(path[i], path[i - 1])) }
        let climb = run[run.count - 1] - 3.6
        for i in path.indices { path[i].y = hh * min(1, run[i] / climb) }

        // the hill: a cone against the back cliff, terraced where the path runs (flat across the path, banks between the turns)
        func cone(_ x: Float, _ z: Float) -> Float {
            let d = hypot(x - summit.x, z - summit.z)
            var h = hh * max(0, min(1, 1 - (d - 4) / 17))
            if z < summit.z { h = max(h, hh * max(0, min(1, 1 - (abs(x - summit.x) - 6) / 10))) }
            return h
        }
        let n = 90, w = 2 * re + 4
        var rows: [[V3]] = []
        for j in 0...n {
            var row: [V3] = []
            for i in 0...n {
                let x = centre.x - w / 2 + Float(i) / Float(n) * w, z = centre.z - w / 2 + Float(j) / Float(n) * w
                var h = cone(x, z), best: Float = 1e9, bh: Float = 0
                for k in stride(from: 0, to: path.count, by: 2) { let d = hypot(x - path[k].x, z - path[k].z); if d < best { best = d; bh = path[k].y } }
                let wt = 1 - PLWD.smooth(2.1, 4.3, best)
                h = h * (1 - wt) + bh * wt - (best < 2.1 ? 0.02 : 0)
                row.append([x, h, z])
            }
            rows.append(row)
        }
        let grass = await PLWD.drawn(512) { g in
            var rng = WorldRNG(seed: 77)
            g.setFillColor(UIColor.world(0x1B8F80).cgColor); g.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            for _ in 0..<9000 {
                let dark = rng.next() < 0.5
                g.setStrokeColor((dark ? UIColor(red: 0.04, green: 0.27, blue: 0.23, alpha: CGFloat(0.35 * rng.next())) : UIColor(red: 0.31, green: 0.86, blue: 0.75, alpha: CGFloat(0.3 * rng.next()))).cgColor)
                g.setLineWidth(CGFloat(1 + rng.next())); let x = CGFloat(rng.next() * 512), y = CGFloat(rng.next() * 512)
                g.move(to: CGPoint(x: x, y: y)); g.addLine(to: CGPoint(x: x + CGFloat(rng.next() - 0.5) * 4, y: y - 3 - CGFloat(rng.next() * 7))); g.strokePath()
            }
        }
        await solidMesh(await PLWD.ribbon(rows, metresPerUV: 6), PLWDSkin(hex: 0x1B8F80, rough: 0.9, tex: grass, pageMix: 0.2, twoSided: true))
        // his curve tile on the path
        let left: [V3] = path.indices.map { path[$0] + sideAt($0) * 1.75 + [0, 0.03, 0] }, right: [V3] = path.indices.map { path[$0] - sideAt($0) * 1.75 + [0, 0.03, 0] }
        add(await PLWD.ribbon([right, left], metresPerUV: 3.5), PLWDSkin(hex: 0xE8E2EA, rough: 0.6, tex: tile, twoSided: true))

        // the amphitheatre: a towering mauve-slate cliff all round, a gap in from the tunnel and the summit's gate cut into the back
        let slate = PLWDSkin(hex: 0x6E5878, rough: 0.85, pageMix: 0.1, twoSided: true)
        let gIn = asin(2.4 / re), gOut = asin(2.7 / re)
        for half in 0...1 {
            let lo = half == 0 ? gIn : Float.pi + gOut, hi = half == 0 ? Float.pi - gOut : 2 * .pi - gIn
            let ang = (0...60).map { lo + Float($0) / 60 * (hi - lo) }
            let wall: [[V3]] = (0..<14).map { r in
                let y = Float(r) / 13 * cliff
                return ang.map { a in let d = re + 0.3 + 0.6 * sin(a * 7 + y * 0.5) - 0.05 * y; return centre + [sin(a) * d, y - 1, cos(a) * d] }
            }
            await solidMesh(await PLWD.ribbon(wall, metresPerUV: 3), slate)
        }
        let back = centre.z - re + 0.9
        let gate = await PLWD.holedWall(hole: PLWD.arch(halfWidth: 2.25, base: 0, spring: 0, rise: 4.5, n: 28), outer: [[3.4, -0.5], [3.4, cliff - hh], [-3.4, cliff - hh], [-3.4, -0.5]], centre: [0, 2], at: back, origin: [summit.x, summit.y, 0])
        await solidMesh(gate, slate)

        // the doubters: three stelae carrying his own stick figures (lifted from plate 3 of the Curve Who) on pale limestone; his mauve X (lifted from plate 7) lights in over each as he passes
        let tablet = PLWDSkin(hex: 0xD4D2DC, rough: 0.8, pageMix: 0.05), plinth = PLWDSkin(hex: 0x3A2E40, rough: 0.7)
        let figAspect: [Float] = [262.0 / 360, 301.0 / 352, 360.0 / 330], xAspect: [Float] = [350.0 / 360, 235.0 / 360, 223.0 / 360]
        for (idx, (f, sd)) in [(Float(0.12), Float(1)), (0.42, -1), (0.7, 1)].enumerated() {
            let i = along(f), base = path[i] + sideAt(i) * (sd * 3.4), face = simd_normalize(V3(path[i].x - base.x, 0, path[i].z - base.z)), yaw = atan2(face.x, face.z)
            let holder = Entity(); holder.position = base; holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); root.addChild(holder)
            let hgt: Float = 2.1
            box([1.5, 0.6, 1.2], plinth, at: [0, 0.3, 0], to: holder)
            let slab = ModelEntity(mesh: .generateBox(size: [1.7, hgt + 0.35, 0.28], cornerRadius: 0.02), materials: []); slab.position = [0, 0.6 + (hgt + 0.35) / 2, -0.2]; holder.addChild(slab)
            slab.components.set(CollisionComponent(shapes: [.generateBox(size: [1.7, hgt + 0.35, 0.28])], isStatic: true)); reskin(slab, tablet)
            let figTex = await PLWD.texture("plw-fig-\(idx + 1)", "P7"), xTex = await PLWD.texture("plw-x-\(idx + 1)", "P7")
            let fp = ModelEntity(mesh: await PLWD.quad(hgt * 0.95 * figAspect[idx], hgt * 0.95), materials: []); fp.position = [0, 0.6 + hgt / 2, -0.04]; holder.addChild(fp); setPicture(fp, figTex, tint: .white, opacity: 1)
            let xp = ModelEntity(mesh: await PLWD.quad(hgt * 1.05 * xAspect[idx], hgt * 1.05), materials: []); xp.position = [0, 0.6 + hgt / 2, -0.02]; holder.addChild(xp); setPicture(xp, xTex, tint: .white, opacity: 0)
            stelae.append((holder, xp, xTex, -1, base))
            triggers.append(PLWTrigger(id: "p7.d\(idx)", center: base + [0, 1.5, 0], yaw: 0, halfExtents: [3.6, 3, 3.6]))
        }

        // the bubble arch: a stone arch spanning the path below the summit, his plate 7 bubble popping up over his head as he walks under
        let ai = along(0.88); arch = path[ai]; archSide = sideAt(ai)
        let ayaw = atan2(-archSide.z, archSide.x), archStone = PLWDSkin(hex: 0xA4B3C6, rough: 0.7, pageMix: 0.05)
        for sx in [Float(1), -1] { box([0.9, 4.6, 0.9], archStone, at: arch + archSide * (sx * 2.6) + [0, 2.3, 0], yaw: ayaw) }
        box([6.4, 1.1, 0.9], archStone, at: arch + [0, 5.15, 0], yaw: ayaw, solid: false)
        let bw: Float = 3.4
        let b = picture(bubbleTex, await PLWD.quad(bw, bw * 455 / 660), at: arch + [0, 3, 0]); b.scale = .zero; bubble = b
        triggers.append(PLWTrigger(id: "p7.arch", center: arch + [0, 1.5, 0], yaw: 0, halfExtents: [3.2, 3, 3.2]))
        // the secret: his mauve study on a stone tablet in an alcove at the last turn
        let si = along(0.83); studyPos = path[si] - sideAt(si) * 3.1
        box([1.0, 1.2, 0.35], PLWDSkin(hex: 0xC8C4CC, rough: 0.8), at: studyPos + [0, 0.6, 0])
        let sface = simd_normalize(V3(path[si].x - studyPos.x, 0, path[si].z - studyPos.z)), studyTex = await PLWD.texture("plw-x-2", "P7")
        study = picture(studyTex, await PLWD.quad(0.55, 0.85), tint: UIColor(white: 0.5, alpha: 1), at: studyPos + [0, 0.6, 0] + sface * 0.19, yaw: atan2(sface.x, sface.z))
        studyArt = studyTex
        triggers.append(PLWTrigger(id: "p7.study", center: studyPos + [0, 1, 0], yaw: 0, halfExtents: [2.2, 2, 2.2]))
        triggers.append(PLWTrigger(id: "p7.summit", center: summit + [0, 1, 0], yaw: 0, halfExtents: [3, 3, 3]))
        // the first ring: a thin cyan ring that orbits the dream, kept once earned
        let r = ModelEntity(mesh: await PLWD.tube((0...36).map { let a = Float($0) / 36 * 2 * .pi; return V3(cos(a) * 0.39, 0, sin(a) * 0.39) }, radius: { _ in 0.025 }, sides: 8), materials: [])
        r.isEnabled = false; root.addChild(r); ring = r; reskin(r, PLWDSkin(hex: 0x18F0D0, rough: 0.3, glow: 0x18F0D0, glowK: 2))

        // light: the warm mauve daylight, a fill, the bubble's glow, the indigo at the way out, the ring's own cyan
        sun(650, from: centre + [20, 35, 25], toward: centre, color: 0xF0C0D8)
        sun(110, from: centre + [-10, 20, -5], toward: centre, color: 0x6B5A7A)
        bubbleLight = point(90_000, radius: 9, at: arch + [0, 6.8, 0], color: 0xC0D8FF); level(bubbleLight, 0)
        point(60_000, radius: 9, at: summit + [0, 2, back - summit.z + 1.5], color: 0x3D1EA8)
        ringLight = point(80_000, radius: 7, at: summit, color: 0x18F0D0); level(ringLight, 0)

        key(0, .povertyToLuxury, at: path[along(0.25)] + sideAt(along(0.25)) * 2.6 + [0, 1.0, 0]); key(1, .glyphGuy, at: studyPos + sideAt(si) * -1.2 + [0, 1.0, 0]); key(2, .loveYourself, at: summit + [3, 1.0, 2])
        port("start", at: [0, 0, -0.5]); port("exit", at: [summit.x, summit.y, back])
        var line: [V3] = [[0, 0, -0.5]]
        for k in stride(from: 0, to: path.count, by: 12) { line.append(path[k]) }
        route = line + [summit, [summit.x, summit.y, back]]
        if momentDone { ringOn = true }
    }

    override func restore(_ save: PLWSave) { super.restore(save); ringOn = momentDone || (save.roomFlags[PLWArea.p7.rawValue]?.contains("ring") ?? false) }

    override func trigger(_ e: PLWTriggerEvent) -> [PLWCommand] {
        let inside = e.phase != .exited
        if e.id.hasPrefix("p7.d"), let i = Int(e.id.dropFirst(4)), i < stelae.count, inside, stelae[i].t < 0 { stelae[i].t = 0 }
        switch e.id {
        case "p7.arch": inArch = inside
        case "p7.study": nearStudy = inside
        case "p7.summit": onSummit = inside; if inside, crestT < 0, !ringOn { crestT = 0 }
        default: break
        }
        return []
    }

    private func say(_ s: String) -> [PLWCommand] { guard s != said else { return [] }; said = s; return s.isEmpty ? [] : [.caption(s)] }

    override func tick(_ f: PLWFrame) -> [PLWCommand] {
        var out: [PLWCommand] = []
        let dt = f.dt, p = f.position
        // the doubters: his X draws itself over each figure (1.2 s), stroke by stroke, and the figure greys back into stone
        for i in stelae.indices where stelae[i].t >= 0 && stelae[i].t < 4 {
            stelae[i].t += dt
            let t = stelae[i].t
            setPicture(stelae[i].x, stelae[i].xTex, tint: .white, opacity: PLWD.smooth(0, 1.2, t))   // his X lit in (a fade; the stroke-by-stroke wipe is owed)
        }
        // the bubble: the thought appears over his head under the arch and stays 5 s after he leaves it
        if inArch { under = 5 } else { under = max(0, under - dt) }
        bubT = under > 0 ? min(1, bubT + dt / 0.45) : max(0, bubT - dt / 0.3)
        let pop = under > 0 ? 1 - pow(1 - bubT, 3) * (1 + 1.4 * (1 - bubT)) : bubT
        if let b = bubble {
            b.scale = V3(repeating: max(0.001, pop)); b.position = p + [0.6, 2.9, 0]
            let l = f.lookDirection; b.orientation = simd_quatf(angle: atan2(-l.x, -l.z), axis: [0, 1, 0])
            bubbleLight.position = b.position + [0, 0, 0]; level(bubbleLight, bubT)
        }
        // the summit: the ring forms round the dream (0.8-2 s), the camera drops and looks up to frame him
        if crestT >= 0, crestT < 4 {
            crestT += dt
            let k = PLWD.smooth(0.8, 2.0, crestT); ringOn = true
            ring?.scale = V3(repeating: max(0.02, k)); level(ringLight, k)
            let w = PLWD.smooth(0.2, 1.0, crestT) * (1 - PLWD.smooth(3.2, 4.0, crestT)), back = simd_normalize(V3(p.x - arch.x, 0, p.z - arch.z))
            out.append(.camera(position: p + back * -3.2 + [0, -0.2, 0], target: p + [0, 1.6, 0] + back * 1.5, weight: w))
            if crestT >= 3.9 { out.append(.roomFlag(.p7, "ring")); out += finish() }
        } else if ringOn { level(ringLight, 0.7) }
        if ringOn, let r = ring { r.isEnabled = true; r.position = p + [0, 1.2, 0]; r.orientation = simd_quatf(angle: clock * 1.5, axis: [0, 1, 0]) * simd_quatf(angle: 0.5 + 0.2 * sin(clock * 1.1), axis: [1, 0, 0]); ringLight.position = r.position }
        if !studyFound, nearStudy, f.actPressed {
            studyFound = true; out.append(.mark("p7.study")); out += say("his mauve study")
            if let s = study { setPicture(s, studyArt, tint: .white, opacity: 1) }
        }
        return out
    }
}
