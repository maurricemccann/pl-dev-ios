import RealityKit
import UIKit
import simd

/// The built-in test room: a plain grey ground with a step, a ramp, two platforms, a tunnel, a well and three keys, so the whole runtime
/// (walk, run, jump, double jump, slope, step, triggers, keys, camera, first-person tunnel, save) runs with no room lane merged.
/// It also stands in for any area whose room is not registered yet. It is greybox on purpose; the real rooms replace it.
@MainActor final class PLWRoomGreybox: PLWRoom {
    let id: PLWArea
    let root = Entity()
    private(set) var ports: [String: Transform] = [:]
    private(set) var route: [SIMD3<Float>] = [[0, 0, 8], [0, 0, -4], [0, 0, -22]]
    let triggers: [PLWTrigger] = [
        PLWTrigger(id: "grey.well", center: [0, 1.2, -24], yaw: 0, halfExtents: [3, 1.5, 3]),
        PLWTrigger(id: "tunnel.grey", center: [-12, 1.5, -10], yaw: 0, halfExtents: [1.9, 1.5, 6]),
    ]
    let glyphs: [PLWGlyphPlacement]
    private var tinted: [(ModelEntity, Float)] = []     // entity and how light its share of the page colour is
    private var inWell = false, hold: Float = 0, lastRise: Float = -1

    init(area: PLWArea) {
        id = area
        glyphs = [
            PLWGlyphPlacement(key: PLWKey(page: area, slot: 0), glyph: .glyphGuy, position: [3, 0.9, 2]),
            PLWGlyphPlacement(key: PLWKey(page: area, slot: 1), glyph: .loveYourself, position: [6, 2.3, -6]),
            PLWGlyphPlacement(key: PLWKey(page: area, slot: 2), glyph: .smiley, position: [-12, 0.9, -10]),
        ]
        ports["start"] = Transform(translation: [0, 0, 8])
        ports["exit"] = Transform(translation: [0, 0, -27])
    }

    convenience init() { self.init(area: .p1) }

    private func solid(_ size: SIMD3<Float>, at p: SIMD3<Float>, pitch: Float = 0, shade: Float = 0.5) {
        let e = ModelEntity(mesh: .generateBox(size: size), materials: [SimpleMaterial(color: .gray, roughness: 0.9, isMetallic: false)])
        e.position = p
        e.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0])
        e.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        root.addChild(e)
        tinted.append((e, shade))
    }

    func load() async throws {
        solid([40, 0.4, 70], at: [0, -0.2, -14], shade: 0.35)                      // the ground, top at y = 0
        solid([40, 3, 0.4], at: [0, 1.5, -49.2]); solid([40, 3, 0.4], at: [0, 1.5, 21.2])
        solid([0.4, 3, 70], at: [-20.2, 1.5, -14]); solid([0.4, 3, 70], at: [20.2, 1.5, -14])
        solid([4, 0.3, 3], at: [0, 0.15, 0], shade: 0.7)                           // a 0.3 m step
        solid([4, 0.3, 8], at: [0, 0.55, -8], pitch: 0.32, shade: 0.7)             // a ramp, about 18 degrees
        solid([4, 1.4, 4], at: [6, 0.7, -6], shade: 0.8)                           // one jump
        solid([4, 2.6, 4], at: [10, 1.3, -10], shade: 0.9)                         // jump then double jump
        solid([1, 2, 1], at: [-4, 1, -2], shade: 0.6); solid([1, 2, 1], at: [4, 1, -14], shade: 0.6)
        solid([2.4, 0.8, 2.4], at: [0, 0.4, -24], shade: 0.95)                     // the well
        solid([0.4, 3, 12], at: [-14.2, 1.5, -10]); solid([0.4, 3, 12], at: [-9.8, 1.5, -10]); solid([4.8, 0.4, 12], at: [-12, 3.2, -10])   // the tunnel
        root.addChild(WorldLight.directional(2600, from: [14, 22, 10], look: [0, 0, -12]))
        root.addChild(WorldLight.directional(900, from: [-12, 10, -18], look: [0, 0, -12], color: WorldLight.warm))
    }

    func restore(_ save: PLWSave) { hold = save.completed.contains(id) ? 1 : 0; lastRise = -1 }

    func step(_ f: PLWFrame) -> [PLWCommand] {
        guard inWell, !f.save.completed.contains(id) else { return [] }
        hold = f.actHeld ? min(1, hold + f.dt / 2) : max(0, hold - f.dt * 0.5)
        var out: [PLWCommand] = []
        if abs(hold - lastRise) > 0.01 { lastRise = hold; out.append(.raiseDream(hold)) }
        if hold >= 1 { out += [.dream(.carried), .completeMoment(id), .caption("Held still. The dream rises.")] }
        return out
    }

    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] {
        guard event.id == "grey.well" else { return [] }
        inWell = event.phase != .exited
        return event.phase == .entered && !hasFinished ? [.caption("Hold ACT here.")] : []
    }
    private var hasFinished: Bool { hold >= 1 }

    func apply(_ look: PLWLook) {
        let c = PLWPalette.saturate(look.pageRGB, look.saturation)
        for (e, shade) in tinted {
            let k = 0.55 + 0.45 * shade
            let m = SimpleMaterial(color: UIColor(red: CGFloat(c.x * k), green: CGFloat(c.y * k), blue: CGFloat(c.z * k), alpha: 1), roughness: 0.9, isMetallic: false)
            e.model?.materials = [m]
        }
    }

    func unload() { root.removeFromParent() }
}
