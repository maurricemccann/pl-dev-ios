import RealityKit
import UIKit

/// The hero in the world: his GlyphGuy v4 (the world USDZ, never redrawn) or GlyphGirl (derived from it by the `buildHer` recipe, same rig, same clips).
/// The clip pack in `Models/Clips` is retargeted by joint names, so both heroes play the same animations. Feet sit on y = 0 of `root`.
@MainActor final class PLWHeroFigure {
    enum Pose { case idle, walking, jump }

    let root = Entity()
    private(set) var model: Entity?
    private var anims: [Pose: AnimationResource] = [:]
    private var playing: Pose?
    private(set) var missing = false
    private var armature: Entity?, bind = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), checked = 0

    /// The bundled model for a hero, or nil when the file is not in this build (GlyphGirl until her file is added).
    static func modelURL(_ hero: PLWHero) -> URL? {
        let name = hero == .glyphGuy ? "glyphguy-v4-world" : "glyphgirl-v4-world"
        return Bundle.main.url(forResource: name, withExtension: "usdz")
            ?? Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Models")
            ?? Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "PLWorld/Hero")
    }
    static func available(_ hero: PLWHero) -> Bool { modelURL(hero) != nil }

    private static func clipURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: "clip-\(name)", withExtension: "usdz")
            ?? Bundle.main.url(forResource: "clip-\(name)", withExtension: "usdz", subdirectory: "Models")
            ?? Bundle.main.url(forResource: "clip-\(name)", withExtension: "usdz", subdirectory: "Models/Clips")
    }

    /// Loads the model, scaled to `height` metres (his GlyphGuy is fitted by its longest side, as the labs do), and the three clips the runtime needs.
    func load(_ hero: PLWHero, height: Float) async {
        guard let url = Self.modelURL(hero) else { PLWLog.note("FAILED hero model: \(hero) has no usdz in the app"); missing = true; return }
        guard let e = await PLWLog.entity(contentsOf: url) else { missing = true; return }
        let fit = ThreeDModels.fitted(e, longest: height)
        root.addChild(fit)
        model = e
        armature = e.findEntity(named: "Armature"); bind = armature?.orientation ?? bind
        for (pose, name) in [(Pose.idle, "idle"), (Pose.walking, "walking"), (Pose.jump, "jump")] {
            if let u = Self.clipURL(name), let ce = await PLWLog.entity(contentsOf: u), let a = ce.availableAnimations.first { anims[pose] = a }
        }
        play(.idle)
    }

    /// Switches the clip; the engine blends over 0.2 s.
    func play(_ p: Pose) {
        guard p != playing, let model, let a = anims[p] else { return }
        playing = p
        model.playAnimation(p == .jump ? a : a.repeat(), transitionDuration: 0.2, startsPaused: false)
    }

    /// S350 (his "facing down like a stiff board"): the clip files' rig is turned 90 degrees from the model's (measured in Blender:
    /// the model's Armature prim carries +90 deg X, every clip's carries none). If a clip drives that prim, counter-rotate the model
    /// so his rig keeps its bind orientation. Called every frame; logs once what it found, so his device log settles the cause.
    func hold() {
        guard let model, let arm = armature else { return }
        let now = arm.orientation
        model.orientation = bind * now.inverse
        checked += 1
        if checked == 60 {
            let off = 2 * acos(min(1, abs(simd_dot(bind.vector, now.vector)))) * 180 / .pi
            PLWLog.note("hero rig: clip turns the Armature \(Int(off)) deg from the model's bind\(off > 5 ? "; corrected" : "; not the cause")")
        }
    }

    func setVisible(_ on: Bool) { root.isEnabled = on }
}
