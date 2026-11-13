import SwiftUI
import RealityKit

// The Weight, as `app/defiance/the-weight/page.tsx` builds it: 54 of his archive works floating in the dark, laid out by the
// page's own seeded generator (mulberry32, seed 20260620) so the field is the same field. Free flight, no floor, no walls:
// the left thumb moves along the view (looking up lifts you), the right thumb looks. Pieces drift and turn slowly, fog takes
// the far ones, and a work shows its PL number when you come within 4 m.

@MainActor final class WeightScene {
    @MainActor private final class Piece {
        let picture: WorldPicture
        let tilt: Float
        let baseY: Float
        let phase: Float
        var yaw: Float
        let title: String
        init(picture: WorldPicture, tilt: Float, baseY: Float, phase: Float, yaw: Float, title: String) {
            self.picture = picture; self.tilt = tilt; self.baseY = baseY; self.phase = phase; self.yaw = yaw; self.title = title
        }
    }
    private var pieces: [Piece] = []
    private var t: Float = 0
    private var fogClock: Float = 0

    private static let count = 54
    private static let fieldR: Float = 20
    private static let yLow: Float = -7
    private static let yHigh: Float = 15

    func build(engine: WorldEngine, works: [WorldPiece]) {
        let root = Entity(); engine.add(root)
        var rnd = WorldRNG(seed: 20260620)
        let step = works.isEmpty ? 1 : max(1, works.count / Self.count)
        var made: [Piece] = []
        for i in 0..<Self.count {
            let ang = rnd.next() * .pi * 2
            let rad = 4 + rnd.next() * Self.fieldR
            let y = Self.yLow + rnd.next() * (Self.yHigh - Self.yLow)
            let scale = 0.9 + rnd.next() * 1.8
            let item = works.isEmpty ? nil : works[(i * step) % works.count]
            let ph = 1.2 * scale, pw = ph * 0.8              // archive thumbs are about 400 by 500, portrait
            let yaw = rnd.next() * .pi * 2
            let tilt = (rnd.next() - 0.5) * 0.3
            let phase = rnd.next() * .pi * 2

            let pic = WorldPicture(mesh: .generatePlane(width: pw, height: ph), base: ThreeDHouse.gold.worldDim(0.22), doubleSided: true)
            pic.root.position = [cos(ang) * rad, y, sin(ang) * rad]
            root.addChild(pic.root)
            let p = Piece(picture: pic, tilt: tilt, baseY: y, phase: phase, yaw: yaw, title: item?.cr ?? "")
            made.append(p)
            if let url = item?.thumbURL {
                Task { @MainActor in if let tex = await WorldTextures.load(url) { pic.set(texture: tex) } }
            }
        }
        pieces = made
        place()
    }

    private func place() {
        for p in pieces {
            p.picture.root.position.y = p.baseY + sin(t * 0.4 + p.phase) * 0.18
            p.picture.root.orientation = simd_quatf(angle: p.yaw, axis: [0, 1, 0]) * simd_quatf(angle: p.tilt, axis: [1, 0, 0])
        }
    }

    /// The gentle drift of the field (off when the phone asks for less motion), and fog on the far works.
    func step(_ dt: Float, camera: SIMD3<Float>, drift: Bool) {
        if drift {
            t += dt
            for p in pieces { p.yaw += 0.036 * dt }
            place()
        }
        fogClock += dt
        if fogClock > 0.15 {
            fogClock = 0
            for p in pieces { p.picture.fog(worldFog(simd_distance(p.picture.root.position, camera), density: 0.028)) }
        }
    }

    func caption(near c: SIMD3<Float>) -> WorldCaptionData? {
        var best: Piece?, d: Float = 4.0
        for p in pieces {
            let dd = simd_distance(p.picture.root.position, c)
            if dd < d { d = dd; best = p }
        }
        guard let best, !best.title.isEmpty else { return nil }
        return WorldCaptionData(title: best.title, year: "")
    }
}

struct WeightWorld: View {
    let model: AppModel
    @State private var archive = WorldArchive.shared
    @State private var engine = WorldEngine(fov: 52, far: 120)
    @State private var rig = FlyRig()
    @State private var scene = WeightScene()
    @State private var caption: WorldCaptionData?
    @State private var clock: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WorldView(engine: engine, background: ThreeDHouse.obsidian) { eng in
                rig.position = [0, 2, 24]; rig.flying = true; rig.bounds = nil; rig.speed = 3
                await archive.load(model: model)
                scene.build(engine: eng, works: archive.pieces)
            }
            .ignoresSafeArea()
            WorldControls(rig: rig, pitchLimit: 1.45)
            WorldCaption(data: caption)
            WorldArchiveNotice(archive: archive, model: model)
            WorldTipLine(tip: WorldMoveTip())
        }
        .background(Color.black)
        .navigationTitle("The Weight").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            let rig = rig, scene = scene, engine = engine, drift = !reduceMotion
            engine.onFrame = { dt in
                rig.step(dt); rig.apply(to: engine.camera)
                scene.step(dt, camera: rig.position, drift: drift)
                clock += dt
                if clock > 0.14 {
                    clock = 0
                    let c = scene.caption(near: rig.position)
                    if c != caption { caption = c }
                }
            }
        }
    }
}
