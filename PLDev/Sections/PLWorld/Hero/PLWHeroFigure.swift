import RealityKit
import UIKit

/// The hero in the world: his GlyphGuy v4 (the world USDZ, never redrawn) or GlyphGirl (derived from it by the `buildHer` recipe, same rig, same clips).
/// The clip pack in `Models/Clips` is retargeted by joint names, so both heroes play the same animations. Feet sit on y = 0 of `root`.
@MainActor final class PLWHeroFigure {
    enum Pose { case idle, walking, jump }

    let root = Entity()
    private(set) var model: Entity?
    private var anims: [Pose: AnimationResource] = [:]
    private var fitted: [Pose: AnimationResource] = [:]   // the same clips re-fitted onto his own rig by RealityKit (played on the skinned mesh)
    private var playing: Pose?
    private(set) var missing = false
    private var armature: Entity?, bind = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), checked = 0
    private let upright = Entity()   // the rig correction lives here: no clip animates this entity
    private var fit: Entity?
    private var skin: ModelEntity?, hipsBind = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

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
        root.addChild(upright); upright.addChild(fit); self.fit = fit
        ThreeDModels.paint(e, ThreeDModels.goldMaterial())   // the house gold, as his GlyphGuy room shows him (the file's own colour reads grey)
        model = e
        armature = e.findEntity(named: "Armature"); bind = armature?.orientation(relativeTo: fit) ?? bind
        skin = Self.firstSkinned(e); hipsBind = skin?.jointTransforms.first?.rotation ?? hipsBind
        for (pose, name) in [(Pose.idle, "idle"), (Pose.walking, "walking"), (Pose.jump, "jump")] {
            if let u = Self.clipURL(name), let ce = await PLWLog.entity(contentsOf: u), let a = ce.availableAnimations.first {
                anims[pose] = a
                if let r = retarget(a, from: ce, name, model: e) { fitted[pose] = r }
            }
        }
        PLWLog.note("hero moves: \(fitted.count) of \(anims.count) re-fitted onto his rig by RealityKit\(fitted.count == anims.count ? "" : "; the rest play with the holder correction")")
        play(.idle)
    }

    /// Switches the clip; the engine blends over 0.2 s.
    func play(_ p: Pose) {
        guard p != playing, let model, let a = anims[p] else { return }
        playing = p
        if let r = fitted[p], let skin {     // Apple's retargeting: joints only, so nothing tips the rig over
            skin.playAnimation(p == .jump ? r : r.repeat(), transitionDuration: 0.2, startsPaused: false)
        } else {
            model.playAnimation(p == .jump ? a : a.repeat(), transitionDuration: 0.2, startsPaused: false)
        }
    }

    /// S350 (his "facing down like a stiff board"): the clip files' rig is turned 90 degrees from the model's (measured in Blender:
    /// the model's Armature prim carries +90 deg X, every clip's carries none). If a clip drives that prim (or the model above it), counter-rotate a holder no clip touches
    /// so his rig keeps its bind orientation. Called every frame; logs once what it found, so his device log settles the cause.
    func hold() {
        guard let fit, let arm = armature else { return }
        let now = arm.orientation(relativeTo: fit)          // whatever the clip did to the rig and everything above it inside the model
        let r = bind * now.inverse, pivot = arm.position(relativeTo: fit)
        upright.orientation = r
        upright.position = pivot - r.act(pivot)              // turn about the rig's own origin, not the feet
        checked += 1
        if checked == 60 {
            let off = 2 * acos(min(1, abs(simd_dot(bind.vector, now.vector)))) * 180 / .pi
            let up = arm.convert(direction: [0, 1, 0], to: root)
            let hips = skin?.jointTransforms.first?.rotation ?? hipsBind
            let hipOff = 2 * acos(min(1, abs(simd_dot(hipsBind.vector, hips.vector)))) * 180 / .pi
            PLWLog.note("hero hips (\(skin?.jointNames.first ?? "none")): clip turns them \(Int(hipOff)) deg from bind")
            PLWLog.note("hero rig v2: clip turns the rig \(Int(off)) deg; after correction rig up = \(String(format: "%.2f %.2f %.2f", up.x, up.y, up.z)) (bind up = \(String(format: "%.2f %.2f %.2f", bind.act([0, 1, 0]).x, bind.act([0, 1, 0]).y, bind.act([0, 1, 0]).z)))")
        }
    }

    /// Apple's own fix for a clip made on a rig that faces another way (RealityKit `RetargetingConfiguration.automatchBiped`, whose two
    /// root transforms exist "when characters are positioned or oriented differently in their bind poses"). Nil, with a log line, when
    /// anything is missing; the clip then plays as before under the holder correction in `hold()`.
    private func retarget(_ a: AnimationResource, from ce: Entity, _ name: String, model e: Entity) -> AnimationResource? {
        guard #available(iOS 27.0, *) else { return nil }   // shortcut: assumed iOS 27 SDK API; older iOS keeps the holder correction
        guard let srcSkin = Self.firstSkinned(ce), let src = srcSkin.model?.mesh.contents.skeletons.first,
              let dst = skin?.model?.mesh.contents.skeletons.first else { PLWLog.note("hero retarget \(name): no skeleton in the clip or the model"); return nil }
        let def = a.definition
        let sampled = (def as? SampledAnimation<JointTransforms>)
            ?? (def as? AnimationGroup)?.group.compactMap { $0 as? SampledAnimation<JointTransforms> }.first
        guard let sampled else { PLWLog.note("hero retarget \(name): clip is \(type(of: def)), not sampled joints"); return nil }
        do {
            let srcRot = ce.findEntity(named: "Armature")?.orientation(relativeTo: ce) ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let dstRot = e.findEntity(named: "Armature")?.orientation(relativeTo: e) ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let cfg = try RetargetingConfiguration.automatchBiped(try SkeletonResource(from: src), sourceTransform: Transform(rotation: srcRot),
                                                                   to: try SkeletonResource(from: dst), targetTransform: Transform(rotation: dstRot))
            return try AnimationResource.generate(with: try sampled.processAndCreateAnimation(retargeting: cfg))
        } catch { PLWLog.fail("hero retarget \(name)", error); return nil }
    }

    private static func firstSkinned(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
        for c in e.children { if let m = firstSkinned(c) { return m } }
        return nil
    }

    func setVisible(_ on: Bool) { root.isEnabled = on }
}
