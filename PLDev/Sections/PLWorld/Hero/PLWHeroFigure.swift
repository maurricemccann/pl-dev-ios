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
        guard let url = Self.modelURL(hero), let e = try? await Entity(contentsOf: url) else { missing = true; return }
        let fit = ThreeDModels.fitted(e, longest: height)
        root.addChild(fit)
        model = e
        for (pose, name) in [(Pose.idle, "idle"), (Pose.walking, "walking"), (Pose.jump, "jump")] {
            if let u = Self.clipURL(name), let ce = try? await Entity(contentsOf: u), let a = ce.availableAnimations.first { anims[pose] = a }
        }
        play(.idle)
    }

    /// Switches the clip; the engine blends over 0.2 s.
    func play(_ p: Pose) {
        guard p != playing, let model, let a = anims[p] else { return }
        playing = p
        model.playAnimation(p == .jump ? a : a.repeat(), transitionDuration: 0.2, startsPaused: false)
    }

    func setVisible(_ on: Bool) { root.isEnabled = on }
}
