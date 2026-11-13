import SwiftUI
import RealityKit

// The Haul, as `app/defiance/the-haul/page.tsx` builds it: an obsidian warehouse room (24 by 24 m, walls 6 m), twelve archive
// works in frames on the four walls, his loaded EYT2 pallets, blue pallets, three parked gold pallet jacks, four yellow totes,
// and his walking box figure in gold pacing the west side. The left thumb walks, the right thumb looks; a work shows its
// title and year when you stand near it.

@MainActor final class HaulScene {
    private struct Art { let pos: SIMD3<Float>; var title: String; var year: String }
    private var arts: [Art] = []
    private var guy: Entity?
    private var guyZ: Float = 8
    private var guyDir: Float = -1

    private static let half: Float = 12
    private static let slots: [(x: Float, z: Float, ry: Float)] = {
        let h: Float = 12 - 0.1
        return [(-6, -h, 0), (0, -h, 0), (6, -h, 0),
                (-6, h, .pi), (0, h, .pi), (6, h, .pi),
                (-h, -6, .pi / 2), (-h, 0, .pi / 2), (-h, 6, .pi / 2),
                (h, -6, -.pi / 2), (h, 0, -.pi / 2), (h, 6, -.pi / 2)]
    }()
    private static let archiveIndices = [12, 80, 777, 964, 771, 333, 501, 88, 642, 910, 145, 420]

    func build(engine: WorldEngine, pieces: [WorldPiece]) async {
        let root = Entity(); engine.add(root)
        let pool = UIColor.world(0xffd79a)
        // a few warm pools over the floor, and a low lift so the walls are not lost
        for p in [(0, 0), (-5, -5), (5, 5), (5, -5), (-5, 5)] as [(Float, Float)] {
            root.addChild(WorldLight.point(60_000, radius: 11, at: [p.0, 4.2, p.1], color: pool))
        }
        root.addChild(WorldLight.directional(260, from: [0, 8, 3], color: UIColor.world(0x2a2212).worldDim(3)))
        root.addChild(WorldLight.directional(160, from: [0, 8, -3], color: UIColor.world(0x2a2212).worldDim(3)))

        let half = Self.half
        let floor = ModelEntity(mesh: .generatePlane(width: half * 2, depth: half * 2),
                                materials: [SimpleMaterial(color: UIColor.world(0x070707), roughness: 0.55, isMetallic: false)])
        root.addChild(floor)
        let wallMat = SimpleMaterial(color: UIColor.world(0x0b0b0b), roughness: 1, isMetallic: false)
        for (x, z, ry) in [(0, -half, 0), (0, half, 0), (-half, 0, Float.pi / 2), (half, 0, Float.pi / 2)] as [(Float, Float, Float)] {
            let wall = ModelEntity(mesh: .generateBox(width: half * 2, height: 6, depth: 0.3), materials: [wallMat])
            wall.position = [x, 3, z]; wall.orientation = simd_quatf(angle: ry, axis: [0, 1, 0])
            root.addChild(wall)
        }

        // his archive on the walls
        let frameMat = SimpleMaterial(color: UIColor.world(0x0d0d0d), roughness: 0.8, isMetallic: false)
        let frameMesh = MeshResource.generateBox(width: 1.6, height: 1.2, depth: 0.06)
        let artMesh = MeshResource.generatePlane(width: 1.4, height: 1.0)
        var made: [Art] = []
        for (i, s) in Self.slots.enumerated() {
            let frame = ModelEntity(mesh: frameMesh, materials: [frameMat])
            frame.position = [s.x, 1.85, s.z]; frame.orientation = simd_quatf(angle: s.ry, axis: [0, 1, 0])
            root.addChild(frame)

            let piece = pieces.isEmpty ? nil : pieces[Self.archiveIndices[i] % pieces.count]
            let pic = WorldPicture(mesh: artMesh, base: ThreeDHouse.gold.worldDim(0.28), doubleSided: false)
            pic.root.position = [s.x + sin(s.ry) * 0.04, 1.85, s.z + cos(s.ry) * 0.04]
            pic.root.orientation = simd_quatf(angle: s.ry, axis: [0, 1, 0])
            root.addChild(pic.root)
            made.append(Art(pos: [s.x, 1.85, s.z], title: piece?.title ?? piece?.cr ?? "", year: piece?.year ?? ""))
            if let url = piece?.thumbURL {
                Task { @MainActor in if let t = await WorldTextures.load(url) { pic.set(texture: t) } }
            }
        }
        arts = made

        // his loaded pallets, blue pallets, parked jacks and totes
        func proto(_ name: String, long: Float) async -> Entity? {
            guard let e = await ThreeDModels.load(name) else { return nil }
            return ThreeDModels.fitted(e, longest: long)
        }
        func place(_ p: Entity?, _ x: Float, _ z: Float, _ ry: Float) {
            guard let p else { return }
            let c = p.clone(recursive: true)
            c.position = [x, 0, z]; c.orientation = simd_quatf(angle: ry, axis: [0, 1, 0])
            root.addChild(c)
        }
        let eyt = await proto("eyt2", long: 1.7)
        for (x, z, ry) in [(-7.5, -7.5, 0.3), (7.0, -6.5, -1.1), (-6.5, 6.5, 1.7), (7.5, 7.0, 2.6)] as [(Float, Float, Float)] { place(eyt, x, z, ry) }
        let pallet = await proto("blue-pallet", long: 1.3)
        for (x, z, ry) in [(-2.5, -8.0, 0.2), (3.5, 8.5, -0.6)] as [(Float, Float, Float)] { place(pallet, x, z, ry) }
        if let jack = await proto("pallet-jack", long: 1.1) {
            Self.recolorJack(jack)
            for (x, z, ry) in [(-3.5, -2.0, 0.4), (4.0, 3.0, -0.8), (1.0, 6.5, 2.2)] as [(Float, Float, Float)] { place(jack, x, z, ry) }
        }
        let tote = await proto("yellow-tote", long: 0.55)
        for (i, p) in [(-9.0, 0.0), (9.0, -1.0), (0.0, 9.5), (-1.0, -9.5)].enumerated() { place(tote, Float(p.0), Float(p.1), Float(i) * 1.3) }

        // his walking box figure, gold, pacing the west side
        if let g = await ThreeDModels.load("walking-box") {
            ThreeDModels.paint(g, ThreeDModels.unlit(ThreeDHouse.gold))
            let anim = g.availableAnimations.first
            let holder = WorldFit.height(g, 1.8)
            holder.position = [-8.5, 0, guyZ]
            root.addChild(holder)
            if let anim { g.playAnimation(anim.repeat(), transitionDuration: 0, startsPaused: false) }
            guy = holder
        }
    }

    /// Warehouse red becomes the house register: the upper parts obsidian, the body gold (the page's fork).
    private static func recolorJack(_ holder: Entity) {
        let top = holder.visualBounds(relativeTo: holder).max.y
        let gold = SimpleMaterial(color: ThreeDHouse.gold, roughness: 0.4, isMetallic: false)
        let dark = SimpleMaterial(color: UIColor.world(0x0e0c08), roughness: 0.7, isMetallic: false)
        func walk(_ e: Entity) {
            if let m = e as? ModelEntity, m.model != nil {
                let c = m.visualBounds(relativeTo: holder).center.y
                m.model?.materials = [c > top * 0.42 ? dark : gold]
            }
            for child in e.children { walk(child) }
        }
        walk(holder)
    }

    func step(_ dt: Float) {
        guard let guy else { return }
        guyZ += guyDir * 0.72 * dt
        if guyZ < -8 { guyDir = 1 }
        if guyZ > 8 { guyDir = -1 }
        guy.position = [-8.5, 0, guyZ]
        guy.orientation = simd_quatf(angle: guyDir < 0 ? .pi : 0, axis: [0, 1, 0])
    }

    /// The nearest work within 3.2 m of where he stands.
    func caption(near p: SIMD3<Float>) -> WorldCaptionData? {
        var best: Art?, d: Float = 3.2
        for a in arts {
            let dd = hypot(a.pos.x - p.x, a.pos.z - p.z)
            if dd < d { d = dd; best = a }
        }
        return best.map { WorldCaptionData(title: $0.title, year: $0.year) }
    }
}

struct HaulWorld: View {
    let model: AppModel
    @State private var archive = WorldArchive.shared
    @State private var engine = WorldEngine(fov: 50, far: 80)
    @State private var rig = FlyRig()
    @State private var scene = HaulScene()
    @State private var caption: WorldCaptionData?
    @State private var clock: Float = 0

    var body: some View {
        ZStack {
            WorldView(engine: engine, background: ThreeDHouse.obsidian) { eng in
                rig.position = [0, 1.62, 10]; rig.bounds = 11.4; rig.flying = false; rig.speed = 2.7
                await archive.load(model: model)
                await scene.build(engine: eng, pieces: archive.pieces)
            }
            .ignoresSafeArea()
            WorldControls(rig: rig, pitchLimit: 1.2)
            WorldCaption(data: caption)
            WorldArchiveNotice(archive: archive, model: model)
            WorldTipLine(tip: WorldMoveTip())
        }
        .background(Color.black)
        .navigationTitle("The Haul").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            let rig = rig, scene = scene, engine = engine
            engine.onFrame = { dt in
                rig.step(dt); rig.apply(to: engine.camera); scene.step(dt)
                clock += dt
                if clock > 0.12 {
                    clock = 0
                    let c = scene.caption(near: rig.position)
                    if c != caption { caption = c }
                }
            }
        }
    }
}
