import Foundation

/// The numbers that decide how he moves. One place, adjustable live from the debug panel and kept on the device,
/// so his "too slow, laggy" feedback is measured and tuned, never guessed. Defaults: walk 6 and run 10.5 m/s (his ruling), jump peak 1.77 m.
@MainActor @Observable final class PLWTuning {
    static let shared = PLWTuning()
    private let d = UserDefaults.standard

    var walk: Float
    var run: Float
    var debug: Bool

    let gravity: Float = 18
    let jumpPeak: Float = 1.77, doubleJumpPeak: Float = 0.95
    let airControl: Float = 0.8                 // share of ground speed available in the air
    let groundAccel: Float = 45, airAccel: Float = 14
    let capsuleRadius: Float = 0.32, capsuleHeight: Float = 1.7
    let stepLimit: Float = 0.4, slopeLimitDegrees: Float = 50
    let orbSpeedFactor: Float = 3               // JUMP twice then ACT: he rolls as the dream orb at three times the speed

    private init() {
        walk = d.object(forKey: "plw.walk") as? Float ?? 6
        run = d.object(forKey: "plw.run") as? Float ?? 10.5
        debug = d.bool(forKey: "plw.debug")
    }

    func reset() { walk = 6; run = 10.5; persist() }
    /// Called by the debug panel after a change (the macro that makes this observable does not keep property observers).
    func persist() { d.set(walk, forKey: "plw.walk"); d.set(run, forKey: "plw.run"); d.set(debug, forKey: "plw.debug") }
}
