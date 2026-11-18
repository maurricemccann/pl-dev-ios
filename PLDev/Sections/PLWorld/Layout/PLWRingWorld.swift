import Foundation
import RealityKit
import UIKit
import simd

// The ring itself (lane B): eleven sector grounds in their page hues, the green entrance wedge and the outer band, the twelve boundary ridges (cut by
// a tunnel each), the outer ridge, and all 23 tunnels. No divider planes: every ridge is solid land with a walked passage through it. Rooms are NOT built
// here; the runtime loads each room and calls `PLWLayout.place(room, under: ring.root)`. The hub room owns the disc, the moat and the inner ridge.

@MainActor final class PLWRingWorld {
    let root = Entity()
    let tints = PLWTintBook()
    let tunnels: PLWTunnels
    private(set) var loaded = false
    private static let ridgeHeight: Float = 10
    private static let stone = SIMD3<Float>(0.52, 0.48, 0.42)

    init() { tunnels = PLWTunnels(tints: tints); root.name = "plw.ring" }

    func load() async {
        guard !loaded else { return }
        loaded = true
        tints.tile = await PLWTintBook.loadTile()
        await grounds()
        await ridges()
        await tunnels.build()
        root.addChild(tunnels.root)
    }

    /// Vividness for the ring's page hues (the palette owner's number); the ridge stone and the greens keep their own colour.
    func apply(saturation: Float) { tints.retint(saturation) }
    func sync(_ save: PLWSave) { tunnels.sync(save) }

    private func piece(_ b: PLWMeshBuilder, name: String, rgb: SIMD3<Float>, fixed: Bool = false, collide: Bool = true) async {
        guard let mesh = b.mesh(name) else { return }
        let e = tints.make(mesh, rgb: rgb, rough: 0.95, fixed: fixed, name: name)
        if collide { if let s = await PLWSolid.mesh(mesh) { PLWSolid.make(e, shapes: [s]) } }
        root.addChild(e)
    }

    private func grounds() async {
        for p in 1...11 {                                                        // page sector floors, 195 + 30 (p - 1) ... +30
            let a0 = 195 + 30 * Float(p - 1)
            await piece(PLWMeshBuilder.revolve([SIMD2(390, 0), SIMD2(976, 0)], from: a0, to: a0 + 30, metres: 8),
                        name: "plw.ground.p\(p)", rgb: PLWMath.rgb(PLWLayout.pageHex(p)))
        }
        let green = PLWMath.rgb(PLWLayout.greenHex)
        await piece(PLWMeshBuilder.revolve([SIMD2(366, 0), SIMD2(976, 0)], from: 165, to: 195, metres: 8), name: "plw.ground.gap", rgb: green, fixed: true)
        await piece(PLWMeshBuilder.revolve([SIMD2(976, 0), SIMD2(1150, 0)], from: 0, to: 360, metres: 8), name: "plw.ground.band", rgb: green, fixed: true)
    }

    private func ridges() async {
        let h = Self.ridgeHeight
        // the outer ridge closes the page ring everywhere but the entrance gap: the outer band is no back door into unfinished pages
        await piece(PLWMeshBuilder.revolve([SIMD2(976, 0), SIMD2(976, h), SIMD2(1000, h), SIMD2(1000, 0)], from: 195, to: 525, metres: 6),
                    name: "plw.ridge.outer", rgb: Self.stone, fixed: true)
        // the twelve boundary ridges (ten page boundaries and the two entrance walls), each cut by its tunnel at r = 680
        let gap: Float = 3.6
        let t = PLWLayout.ridgeThickness
        for l in PLWLayout.links where l.kind != .hubDoor {
            let b = PLWLayout.compass(l.center)
            let spans: [(Float, Float)] = [(390, PLWLayout.tunnelRadius - gap), (PLWLayout.tunnelRadius + gap, 976)]
            for (r0, r1) in spans { box(t, h, r1 - r0, centre: (r0 + r1) / 2, angle: b, y: h / 2, name: "plw.ridge.\(l.id).\(Int(r0))") }
            let top: Float = l.clearHeight + 0.7                                   // the lintel stays clear of the crown (collision 0.5 over the clear height)
            box(t, h - top, 2 * gap + 0.2, centre: PLWLayout.tunnelRadius, angle: b, y: top + (h - top) / 2, name: "plw.ridge.\(l.id).lintel")
        }
    }

    private func box(_ thick: Float, _ height: Float, _ radial: Float, centre r: Float, angle b: Float, y: Float, name: String) {
        let size = SIMD3<Float>(thick, height, radial)
        let e = tints.make(MeshResource.generateBox(size: size), rgb: Self.stone, rough: 0.95, fixed: true, name: name)
        e.position = PLWMath.world(r, b, y: y)
        e.orientation = PLWMath.rot(-b * .pi / 180)                                // local x along the clockwise tangent, local z along the radius
        PLWSolid.make(e, shapes: [ShapeResource.generateBox(size: size)])
        root.addChild(e)
    }
}
