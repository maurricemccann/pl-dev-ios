import Foundation
import RealityKit
import UIKit
import simd

// PLWRoomHub: the Paradise hub (lane B). A green disc of radius 330 m with his curve strokes as the water-dark lines on it, a moat to 366, an inner ridge
// to 390 cut by eleven roofed doors (the tunnels themselves belong to PLWRingWorld), a 36 m green causeway over the moat at the south entrance, one page-coloured
// spoke per door, and the Heart (his gold heart mark) over a gold pedestal. Local frame = world frame: the hub sits at the origin, never moved by the layout.
// His ruling: strokes OR clearance, never both, so the disc carries only the solid strokes. Everything walkable has static collision.

@MainActor final class PLWRoomHub: PLWRoom {
    let id: PLWArea = .hub
    let root = Entity()
    private(set) var ports: [String: Transform] = [:]
    private(set) var route: [SIMD3<Float>] = []
    private(set) var triggers: [PLWTrigger] = []
    let glyphs: [PLWGlyphPlacement] = []

    /// Metres of ground per repeat of his curve tile on the disc (tunable: the strokes read as a river system at this size; his drawing shows about 3 repeats across).
    static let strokeMetres: Float = 110
    static let innerRidgeHeight: Float = 9
    private static let doorHalfAngle: Float = 0.8          // degrees at r = 378: 5 m, half of the 10 m door opening
    private static let causewayHalf: Float = 2.96          // degrees at r = 348: 18 m, half of the 36 m causeway

    private let tints = PLWTintBook()
    private var heart: Entity?
    private var spokes: [Int: Entity] = [:]
    private var loaded = false

    init() {
        root.name = "plw.hub"
        ports["start"] = Transform(scale: .one, rotation: PLWMath.rot(0), translation: PLWMath.world(372, 180))
        ports["gap"] = ports["start"]
        ports["exit"] = Transform(scale: .one, rotation: PLWMath.rot(0), translation: SIMD3<Float>(0, 0, 16))
        for p in 1...11 {
            let th = PLWRing.centerAngle(page: p)
            ports["door\(p)"] = Transform(scale: .one, rotation: PLWMath.rot(PLWMath.yaw(facing: -PLWMath.world(1, th))), translation: PLWMath.world(300, th))
        }
        route = [PLWMath.world(372, 180), PLWMath.world(300, 180), PLWMath.world(150, 180), SIMD3<Float>(0, 0, 20)]
        triggers = [PLWTrigger(id: "hub.arrive", center: PLWMath.world(350, 180, y: 1.5), yaw: 0, halfExtents: SIMD3<Float>(20, 3, 20))]
        for p in 1...11 {
            let th = PLWRing.centerAngle(page: p)
            triggers.append(PLWTrigger(id: "hub.door.\(p)", center: PLWMath.world(318, th, y: 1.5), yaw: PLWMath.yaw(facing: PLWMath.world(1, th)), halfExtents: SIMD3<Float>(5, 3, 6)))
        }
    }

    // MARK: PLWRoom

    func load() async throws {
        guard !loaded else { return }
        loaded = true
        tints.tile = await PLWTintBook.loadTile()
        await disc()
        await moat()
        await innerRidge()
        spokesAndMats()
        await plaza()
    }

    func restore(_ save: PLWSave) {
        for (p, e) in spokes { e.isEnabled = !PLWGating.enforced || p == 1 || save.reached.contains(PLWLayout.area(p)) }
    }

    func step(_ frame: PLWFrame) -> [PLWCommand] {
        heart?.transform.rotation = simd_quatf(angle: frame.dt * 0.25, axis: SIMD3<Float>(0, 1, 0)) * (heart?.transform.rotation ?? simd_quatf())   // slow turn
        return []
    }

    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] {
        guard event.phase == .entered else { return [] }
        if event.id == "hub.arrive" { return [.checkpoint(.hub, port: "start")] }
        if event.id.hasPrefix("hub.door."), let n = Int(event.id.dropFirst(9)), (1...11).contains(n) { return [.checkpoint(.hub, port: "door\(n)")] }   // respawn at the door he came back through
        return []
    }

    func apply(_ look: PLWLook) { tints.retint(look.saturation) }

    func unload() {
        root.children.removeAll()
        heart = nil; spokes = [:]; loaded = false
    }

    // MARK: build

    private func add(_ b: PLWMeshBuilder, _ name: String, rgb: SIMD3<Float>, textured: Bool = false, rough: Float = 0.92, metal: Float = 0, glow: Float = 0,
                     opacity: Float = 1, fixed: Bool = false, collide: Bool = true) async {
        guard let mesh = b.mesh(name) else { return }
        let e = tints.make(mesh, rgb: rgb, textured: textured, rough: rough, metal: metal, glow: glow, opacity: opacity, fixed: fixed, name: name)
        if collide, let s = await PLWSolid.mesh(mesh) { PLWSolid.make(e, shapes: [s]) }
        root.addChild(e)
    }

    private func disc() async {
        await add(PLWMeshBuilder.revolve([SIMD2(0, 0), SIMD2(330, 0)], from: 0, to: 360, metres: Self.strokeMetres), "plw.hub.disc",
                  rgb: SIMD3<Float>(0.30, 0.64, 0.50), textured: true)
    }

    /// The moat: a bed that ramps down and up (he wades out, no lip), a water sheet over it, and the causeway filling the south crossing.
    private func moat() async {
        let c0 = 180 + Self.causewayHalf, c1 = 180 - Self.causewayHalf + 360
        await add(PLWMeshBuilder.revolve([SIMD2(330, 0), SIMD2(335, -1.1), SIMD2(361, -1.1), SIMD2(366, 0)], from: c0, to: c1, metres: 6), "plw.hub.moatbed",
                  rgb: SIMD3<Float>(0.20, 0.36, 0.34), fixed: true)
        await add(PLWMeshBuilder.revolve([SIMD2(330, -0.3), SIMD2(366, -0.3)], from: c0, to: c1, metres: 6), "plw.hub.water",
                  rgb: SIMD3<Float>(0.13, 0.70, 0.83), rough: 0.08, metal: 0.1, glow: 0.12, opacity: 0.82, fixed: true, collide: false)
        await add(PLWMeshBuilder.revolve([SIMD2(330, 0), SIMD2(366, 0)], from: 180 - Self.causewayHalf, to: c0, metres: 6), "plw.hub.causeway",
                  rgb: SIMD3<Float>(0.39, 0.64, 0.54), fixed: true)
    }

    /// The inner ridge, 366 to 390: solid land all round except the entrance gap (165 to 195) and the eleven door openings, each with a lintel over it.
    private func innerRidge() async {
        let (r0, r1, h) = (PLWLayout.innerRidge.lowerBound, PLWLayout.innerRidge.upperBound, Self.innerRidgeHeight)
        let stone = SIMD3<Float>(0.52, 0.48, 0.42)
        let doors = (1...11).map { p -> Float in let t = PLWRing.centerAngle(page: p); return t < 195 ? t + 360 : t }.sorted()
        var start: Float = 195
        let hw = Self.doorHalfAngle
        for d in doors {
            await add(PLWMeshBuilder.revolve([SIMD2(r0, 0), SIMD2(r0, h), SIMD2(r1, h), SIMD2(r1, 0)], from: start, to: d - hw, metres: 6), "plw.hub.ridge.\(Int(d))", rgb: stone, fixed: true)
            let top = PLWLayout.hubTunnel.wall + PLWLayout.hubTunnel.width / 2 + 0.7
            await add(PLWMeshBuilder.revolve([SIMD2(r0, top), SIMD2(r0, h), SIMD2(r1, h), SIMD2(r1, top), SIMD2(r0, top)], from: d - hw, to: d + hw, metres: 6), "plw.hub.lintel.\(Int(d))", rgb: stone, fixed: true)
            start = d + hw
        }
        await add(PLWMeshBuilder.revolve([SIMD2(r0, 0), SIMD2(r0, h), SIMD2(r1, h), SIMD2(r1, 0)], from: start, to: 525, metres: 6), "plw.hub.ridge.last", rgb: stone, fixed: true)
    }

    /// One page-coloured spoke from the plaza to each door's mouth, and a brighter mat where it meets the tunnel: the door ends in the hub on its colour.
    private func spokesAndMats() {
        for p in 1...11 {
            let th = PLWRing.centerAngle(page: p), rgb = PLWMath.rgb(PLWLayout.pageHex(p))
            let holder = Entity(); holder.name = "plw.hub.spoke.\(p)"
            holder.position = PLWMath.world(170, th, y: 0.03)
            holder.orientation = PLWMath.rot(-th * .pi / 180)
            let spoke = tints.make(MeshResource.generateBox(size: SIMD3<Float>(2.2, 0.04, 300)), rgb: rgb, rough: 0.7, glow: 0.3, name: "plw.hub.spokebar.\(p)")
            let mat = tints.make(MeshResource.generateBox(size: SIMD3<Float>(9, 0.05, 16)), rgb: rgb, rough: 0.6, glow: 0.55, name: "plw.hub.mat.\(p)")
            mat.position = SIMD3<Float>(0, 0.01, -152)                        // local z points inward, so the outer end (r = 322) is -z
            holder.addChild(spoke); holder.addChild(mat)
            root.addChild(holder); spokes[p] = holder
        }
    }

    /// The Heart: a gold pedestal and his heart1 model (about 6 m, turning), with one warm light. If the model is missing the pedestal still stands.
    private func plaza() async {
        await add(PLWMeshBuilder.revolve([SIMD2(0, 0.9), SIMD2(3.3, 0.9), SIMD2(3.6, 0.55), SIMD2(3.9, 0)], from: 0, to: 360, stepDeg: 6, metres: 2), "plw.hub.pedestal",
                  rgb: SIMD3<Float>(0.85, 0.65, 0.18), rough: 0.3, metal: 0.85, fixed: true)
        let holder = Entity(); holder.name = "plw.hub.heart"; holder.position = SIMD3<Float>(0, 0.9, 0)
        if let url = Bundle.main.url(forResource: "heart1", withExtension: "usdz"), let e = await PLWLog.entity(contentsOf: url) {
            var gold = PhysicallyBasedMaterial()
            gold.baseColor = .init(tint: UIColor(red: 0.91, green: 0.70, blue: 0.10, alpha: 1))
            gold.roughness = .init(floatLiteral: 0.28); gold.metallic = .init(floatLiteral: 1)
            ThreeDModels.paint(e, gold)
            holder.addChild(ThreeDModels.fitted(e, longest: 6))
            let pivot = Entity(); pivot.position = SIMD3<Float>(0, 2.6, 0)     // the turn is about the model's own middle
            pivot.addChild(holder); holder.position = SIMD3<Float>(0, -3, 0)
            heart = pivot
            let top = Entity(); top.position = SIMD3<Float>(0, 0.9, 0); top.addChild(pivot); root.addChild(top)
        }
        let lamp = Entity(); lamp.position = SIMD3<Float>(0, 5, 0)
        lamp.components.set(PointLightComponent(color: UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1), intensity: 60000, attenuationRadius: 28))
        root.addChild(lamp)
    }
}
