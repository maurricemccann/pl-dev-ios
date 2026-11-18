import Foundation
import RealityKit
import UIKit
import simd

// All 23 tunnels (lane B). One arched tube per link: floor, side stone and crown share a single longitudinal wash (source colour holds 15 percent,
// eases through the mix, holds the destination colour for the last 15), his curve tile on the walls, one soft light at the middle. The runtime
// switches to first person when `PLWLayout.link(containing:)` says the player is inside one.

@MainActor final class PLWTunnels {
    let root = Entity()
    let tints: PLWTintBook
    private(set) var byID: [String: Entity] = [:]
    private var seals: [String: Entity] = [:]
    private static let slices = 10

    init(tints: PLWTintBook) { self.tints = tints; root.name = "plw.tunnels" }

    /// The cross-section: floor, right wall, crown arch, left wall, with inward-facing normals. Returned as runs of (x, y, normal) so corners stay hard.
    private static func section(width w: Float, wall: Float) -> [[(SIMD2<Float>, SIMD2<Float>)]] {
        let h = w / 2, steps = 12
        var arc: [(SIMD2<Float>, SIMD2<Float>)] = []
        for k in 0...steps {
            let a = Float.pi * Float(k) / Float(steps)
            arc.append((SIMD2<Float>(cos(a) * h, wall + sin(a) * h), SIMD2<Float>(-cos(a), -sin(a))))
        }
        return [
            [(SIMD2<Float>(-h, 0), SIMD2<Float>(0, 1)), (SIMD2<Float>(h, 0), SIMD2<Float>(0, 1))],
            [(SIMD2<Float>(h, 0), SIMD2<Float>(-1, 0)), (SIMD2<Float>(h, wall), SIMD2<Float>(-1, 0))],
            arc,
            [(SIMD2<Float>(-h, wall), SIMD2<Float>(1, 0)), (SIMD2<Float>(-h, 0), SIMD2<Float>(1, 0))],
        ]
    }

    /// One slice of tunnel, centred on the origin, 3 m per tile repeat. Shared by every tunnel of the same size.
    private static func sliceMesh(width: Float, wall: Float, length: Float, name: String) -> MeshResource? {
        var b = PLWMeshBuilder()
        let z0 = -length / 2, z1 = length / 2
        var run: Float = 0
        for pts in section(width: width, wall: wall) {
            for i in 0..<(pts.count - 1) {
                let (p, np) = pts[i], (q, nq) = pts[i + 1]
                let seg = simd_length(q - p)
                let u0 = run / 3, u1 = (run + seg) / 3
                let n0 = SIMD3<Float>(np.x, np.y, 0), n1 = SIMD3<Float>(nq.x, nq.y, 0)
                b.quad(SIMD3<Float>(p.x, p.y, z0), SIMD3<Float>(q.x, q.y, z0), SIMD3<Float>(q.x, q.y, z1), SIMD3<Float>(p.x, p.y, z1),
                       normals: [n0, n1, n1, n0],
                       uvs: [SIMD2<Float>(u0, z0 / 3), SIMD2<Float>(u1, z0 / 3), SIMD2<Float>(u1, z1 / 3), SIMD2<Float>(u0, z1 / 3)])
                run += seg
            }
        }
        return b.mesh(name)
    }

    /// Static collision for a tunnel in its own frame: floor, two walls, and the crown as eight chord boxes. Keeps the player in; the ridge lintel keeps the rest out.
    private static func shapes(width w: Float, wall: Float, length l: Float) -> [ShapeResource] {
        let h = w / 2, t: Float = 0.5
        var s: [ShapeResource] = [
            PLWSolid.box(SIMD3<Float>(w + 2 * t, t, l), at: SIMD3<Float>(0, -t / 2, 0)),
            PLWSolid.box(SIMD3<Float>(t, wall, l), at: SIMD3<Float>(h + t / 2, wall / 2, 0)),
            PLWSolid.box(SIMD3<Float>(t, wall, l), at: SIMD3<Float>(-h - t / 2, wall / 2, 0)),
        ]
        let n = 8
        for k in 0..<n {
            let a0 = Float.pi * Float(k) / Float(n), a1 = Float.pi * Float(k + 1) / Float(n), am = (a0 + a1) / 2
            let chord = 2 * (h + t) * sin((a1 - a0) / 2) * 1.02          // a hair long so neighbours overlap
            let c = SIMD3<Float>(cos(am) * (h + t / 2), wall + sin(am) * (h + t / 2), 0)
            s.append(PLWSolid.box(SIMD3<Float>(chord, t, l), at: c, roll: am + .pi / 2))
        }
        return s
    }

    private func colour(_ link: PLWLink, _ t: Float) -> SIMD3<Float> {
        simd_mix(PLWMath.rgb(link.fromHex), PLWMath.rgb(link.toHex), SIMD3<Float>(repeating: PLWMath.wash(t)))
    }

    /// Builds all 23. Call once, then add `root` to the ring.
    func build() async {
        var meshes: [String: MeshResource] = [:]
        for l in PLWLayout.links {
            let key = "\(l.width)x\(l.length)"
            if meshes[key] == nil, let m = Self.sliceMesh(width: l.width, wall: l.wallHeight, length: l.length / Float(Self.slices), name: "plw.tunnel.\(key)") { meshes[key] = m }
            guard let slice = meshes[key] else { continue }
            let e = Entity(); e.name = "plw.tunnel.\(l.id)"; e.transform = l.transform
            let n = Self.slices, ls = l.length / Float(n)
            for k in 0..<n {
                let t = (Float(k) + 0.5) / Float(n)
                let seg = tints.make(slice, rgb: colour(l, t), textured: true, rough: 0.85, glow: 0.18, name: "plw.tunnel.\(l.id).\(k)")
                seg.position = SIMD3<Float>(0, 0, l.length / 2 - (Float(k) + 0.5) * ls)       // source end is +Z
                e.addChild(seg)
            }
            // collision on a child so the compound shape is one body per tunnel
            let body = Entity(); body.name = "plw.tunnel.\(l.id).body"
            PLWSolid.make(body, shapes: Self.shapes(width: l.width, wall: l.wallHeight, length: l.length))
            e.addChild(body)
            // one soft light at the middle, in the wash colour of the middle
            let lamp = Entity(); lamp.position = SIMD3<Float>(0, l.wallHeight + l.width / 2 - 0.6, 0)
            lamp.components.set(PointLightComponent(color: PLWMath.ui(colour(l, 0.5)), intensity: 9000, attenuationRadius: l.length * 0.6))
            e.addChild(lamp)
            // the seal: a quiet disc across the destination mouth plus a blocker, on only while the gate is closed
            let seal = Entity(); seal.name = "plw.tunnel.\(l.id).seal"; seal.position = SIMD3<Float>(0, 0, -l.length / 2 + 0.6)
            PLWSolid.make(seal, shapes: [PLWSolid.box(SIMD3<Float>(l.width + 1, l.clearHeight + 1, 0.6), at: SIMD3<Float>(0, (l.clearHeight + 1) / 2, 0))])
            seal.isEnabled = false
            e.addChild(seal)
            seals[l.id] = seal; byID[l.id] = e; root.addChild(e)
        }
    }

    /// Re-reads the save: a tunnel's seal is on only when its gate is shut (never, while `PLWGating.enforced` is false).
    func sync(_ save: PLWSave) {
        for l in PLWLayout.links { seals[l.id]?.isEnabled = !l.gate.isOpen(save) }
    }

    /// Streaming: only tunnels within `radius` metres of the player are enabled (23 lights and 230 slices never all draw at once).
    func stream(around p: SIMD3<Float>, radius: Float = 420) {
        for l in PLWLayout.links { byID[l.id]?.isEnabled = simd_distance(l.center, p) < radius + l.length }
    }
}
