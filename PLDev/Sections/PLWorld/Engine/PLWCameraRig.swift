import RealityKit
import simd

/// The camera: low, behind, slow, locked to the hero (his word), with no shake and no strobe. The right thumb turns it round him a little; it never
/// leaves the hero's side of a wall (a ray from his head, pulled in on a hit). In a tunnel it is first person. A room can lean it with the
/// `.camera` command for a beat (weight 0...1), and the lean ends when the room unloads.
@MainActor final class PLWCameraRig {
    struct Lean { var position: SIMD3<Float>; var target: SIMD3<Float>; var weight: Float }

    var yaw: Float = 0
    var pitch: Float = -0.14                 // view pitch: negative looks down at him from a little above
    var distance: Float = 4.0
    var firstPerson = false { didSet { if firstPerson != oldValue { pitch = firstPerson ? 0 : -0.14 } } }
    var lean: Lean?
    private var follow: SIMD3<Float>?           // the eased point the camera orbits; position and aim both hang off it, so nothing swings
    private var reach: Float = 4.0                // how far out the camera is now: snaps in on a wall, eases back out
    private(set) var tooClose = false             // pulled in so near that his body would fill the view; the runtime hides him

    func forward() -> SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    func snap() { follow = nil; reach = distance }

    /// `travel` is his ground velocity; `steer` (0...1) is how much the camera may come round behind him this frame (the runtime
    /// gives 0 while the right thumb is looking, strafing, or he runs toward the camera).
    func update(dt: Float, hero: SIMD3<Float>, travel: SIMD3<Float>, steer: Float, camera: Entity, scene: RealityKit.Scene?) {
        pitch = firstPerson ? max(-1.2, min(1.2, pitch)) : max(-0.6, min(0.08, pitch))
        let head = hero + SIMD3(0, firstPerson ? 0.7 : 0.55, 0)   // `hero` is the capsule centre; the eye line is a little above it
        var pos: SIMD3<Float>, aim: SIMD3<Float>
        if firstPerson {
            pos = head; aim = head + forward()
            follow = nil; tooClose = false
        } else {
            // behind him: while he travels, ease the yaw toward his direction of travel, slowly (about 1.5 s to come round)
            let flat = SIMD2(travel.x, travel.z)
            if steer > 0, simd_length(flat) > 1 {
                var d = atan2(-flat.x, -flat.y) - yaw; d = atan2(sin(d), cos(d))
                yaw += d * min(1, dt * 1.5 * steer)
            }
            let target = hero + SIMD3(0, 0.45, 0)
            var f0 = follow ?? target
            let kx = 1 - exp(-dt * 12), ky = 1 - exp(-dt * 5)       // tight across the ground, softer up and down so a jump does not yank the view
            f0.x += (target.x - f0.x) * kx; f0.z += (target.z - f0.z) * kx; f0.y += (target.y - f0.y) * ky
            follow = f0
            let f = forward()
            var limit = distance
            if let scene {                                           // never the far side of a wall: snap in at once, ease back out
                let hit = scene.raycast(from: f0, to: f0 - f * (distance + 0.3)).first { !($0.entity.name == "plw.player" || $0.entity.name.hasPrefix("plw.trigger.")) }
                if let hit { limit = max(0.2, simd_distance(f0, hit.position) - 0.35) }
            }
            reach = limit < reach ? limit : min(limit, reach + dt * 3)
            tooClose = reach < 1.0
            pos = f0 - f * reach; aim = f0 + f * 3
        }
        if let lean, lean.weight > 0 {
            let w = min(1, lean.weight)
            pos = pos + (lean.position - pos) * w; aim = aim + (lean.target - aim) * w
        }
        camera.look(at: aim, from: pos, relativeTo: nil)
    }
}
