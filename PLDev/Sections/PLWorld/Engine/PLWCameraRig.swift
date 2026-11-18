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
    private var smoothed: SIMD3<Float>?

    func forward() -> SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    func snap() { smoothed = nil }

    func update(dt: Float, hero: SIMD3<Float>, camera: Entity, scene: RealityKit.Scene?) {
        pitch = firstPerson ? max(-1.2, min(1.2, pitch)) : max(-0.6, min(0.08, pitch))
        let f = forward()
        let head = hero + SIMD3(0, firstPerson ? 0.7 : 0.55, 0)   // `hero` is the capsule centre; the eye line is a little above it
        var pos: SIMD3<Float>, aim: SIMD3<Float>
        if firstPerson {
            pos = head; aim = head + f
        } else {
            let pivot = hero + SIMD3(0, 0.45, 0)
            var want = pivot - f * distance
            if let scene {
                let ahead = want - pivot
                let hit = scene.raycast(from: pivot, to: want + simd_normalize(ahead) * 0.3).first { !$0.entity.name.hasPrefix("plw.") }
                if let hit { want = hit.position + simd_normalize(pivot - want) * 0.35 }
            }
            let k = 1 - exp(-dt * 7)                               // slow: it eases toward where it wants to be
            smoothed = smoothed.map { $0 + (want - $0) * k } ?? want
            pos = smoothed!; aim = pivot + f * 3
        }
        if firstPerson { smoothed = nil }
        if let lean, lean.weight > 0 {
            let w = min(1, lean.weight)
            pos = pos + (lean.position - pos) * w; aim = aim + (lean.target - aim) * w
        }
        camera.look(at: aim, from: pos, relativeTo: nil)
    }
}
