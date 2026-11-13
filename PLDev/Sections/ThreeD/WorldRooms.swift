import SwiftUI
import RealityKit

/// The walk-through worlds: the Haul and the Weight (Defiance), and the archive space. His models, his archive pictures.
/// Controls are the web's: the left thumb moves, a drag anywhere else looks.
struct WorldStage: View {
    let rig: FlyRig
    var sky: UIColor = ThreeDHouse.obsidian
    var fov: Float = 60
    var build: @MainActor (RealityViewCameraContent) async -> Void
    var tick: @MainActor (Float) -> Void = { _ in }
    @State private var cam = ThreeDModels.camera(fov: 60)

    var body: some View {
        ZStack {
            RealityView { content in
                content.environment.background = .color(Color(sky))
                cam.components.set(PerspectiveCameraComponent(near: 0.05, far: 300, fieldOfViewInDegrees: fov))
                content.add(cam)
                await build(content)
            }
            FlyControls(rig: rig)
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            var last = Date()
            while !Task.isCancelled {
                let now = Date(); let dt = Float(min(0.1, now.timeIntervalSince(last))); last = now
                rig.step(dt); rig.apply(to: cam); tick(dt)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

private struct LabelChip: View {
    let text: String?
    var body: some View {
        if let text {
            Text(text).font(.footnote.monospaced()).padding(.horizontal, 12).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule()).padding(.top, 8)
                .transition(.opacity)
        }
    }
}

private func seeded(_ n: Int, _ salt: Int) -> Float {
    let x = sin(Double(n) * 127.1 + Double(salt) * 311.7) * 43758.5453123
    return Float((x - x.rounded(.down)) * 2 - 1)
}

// MARK: - The Haul: a warehouse room of his archive on the walls, his pallets, totes and a pallet jack

struct HaulRoom: View {
    let model: AppModel
    @State private var archive = ArchiveList.shared
    @State private var rig = FlyRig()
    @State private var label: String?
    @State private var arts: [(pos: SIMD3<Float>, title: String)] = []
    @State private var guy = Entity()
    @State private var guyT: Float = 0

    private let half: Float = 12
    private let slots: [(Float, Float, Float)] = {
        let h: Float = 12 - 0.1
        return [(-6, -h, 0), (0, -h, 0), (6, -h, 0), (-6, h, .pi), (0, h, .pi), (6, h, .pi),
                (-h, -6, .pi / 2), (-h, 0, .pi / 2), (-h, 6, .pi / 2), (h, -6, -.pi / 2), (h, 0, -.pi / 2), (h, 6, -.pi / 2)]
    }()
    private let archiveIndices = [12, 80, 777, 964, 771, 333, 501, 88, 642, 910, 145, 420]

    var body: some View {
        WorldStage(rig: rig) { content in
            rig.position = [0, 1.62, half - 2]; rig.bounds = half - 0.6; rig.flying = false
            content.add(ThreeDModels.light(intensity: 2200, at: [0, 6, 0], look: .zero))
            let dark = SimpleMaterial(color: ThreeDHouse.ground, roughness: 0.95, isMetallic: false)
            let floor = ModelEntity(mesh: .generatePlane(width: half * 2, depth: half * 2), materials: [dark]); content.add(floor)
            let walls: [(Float, Float, Float)] = [(0, -half, 0), (0, half, .pi), (-half, 0, .pi / 2), (half, 0, -.pi / 2)]
            for (x, z, ry) in walls {
                let wall = ModelEntity(mesh: .generatePlane(width: half * 2, height: 6), materials: [SimpleMaterial(color: ThreeDHouse.obsidian, roughness: 1, isMetallic: false)])
                wall.position = [x, 3, z]; wall.orientation = simd_quatf(angle: ry, axis: [0, 1, 0]); content.add(wall)
            }
            // his archive on the walls
            let works = archive.works
            var found: [(SIMD3<Float>, String)] = []
            for (i, s) in slots.enumerated() {
                let w = works.isEmpty ? nil : works[archiveIndices[i] % works.count]
                let frame = await ThreeDPictures.framed(w?.thumbURL, width: 1.6, height: 2.0)
                frame.position = [s.0, 2.1, s.1]; frame.orientation = simd_quatf(angle: s.2, axis: [0, 1, 0])
                content.add(frame)
                found.append(([s.0, 1.6, s.1], w?.cr ?? ""))
            }
            arts = found
            // his props
            func place(_ name: String, long: Float, x: Float, z: Float, ry: Float, gold: Bool = false) async {
                guard let e = await ThreeDModels.load(name) else { return }
                if gold { ThreeDModels.paint(e, ThreeDModels.goldMaterial()) }
                let f = ThreeDModels.fitted(e, longest: long); f.position = [x, 0, z]; f.orientation = simd_quatf(angle: ry, axis: [0, 1, 0]); content.add(f)
            }
            for (x, z, ry) in [(-2.5, -8.0, 0.2), (3.5, 8.5, -0.6), (-7.5, -7.5, 0.3), (7.0, -6.5, -1.1), (-6.5, 6.5, 1.7), (7.5, 7.0, 2.6)] as [(Float, Float, Float)] { await place("blue-pallet", long: 1.3, x: x, z: z, ry: ry) }
            for (x, z, ry) in [(-3.5, -2.0, 0.4), (4.0, 3.0, -0.8), (1.0, 6.5, 2.2)] as [(Float, Float, Float)] { await place("pallet-jack", long: 1.1, x: x, z: z, ry: ry, gold: true) }
            for (i, p) in [(-9.0, 0.0), (9.0, -1.0), (0.0, 9.5), (-1.0, -9.5)].enumerated() { await place("yellow-tote", long: 0.55, x: Float(p.0), z: Float(p.1), ry: Float(i) * 1.3) }
            // his walking box figure, gold, on a slow loop
            if let g = await ThreeDModels.load("walking-box") {
                ThreeDModels.paint(g, ThreeDModels.goldMaterial())
                guy = ThreeDModels.fitted(g, longest: 1.8); guy.position = [9.8, 0, 8]; content.add(guy)
            }
        } tick: { dt in
            guyT += dt
            let span: Float = 16, period = span * 2, d = (guyT * 0.9).truncatingRemainder(dividingBy: period)
            let down = d < span
            guy.position = [9.8, 0, down ? 8 - d : -8 + (d - span)]
            guy.orientation = simd_quatf(angle: down ? .pi : 0, axis: [0, 1, 0])
            let me = rig.position
            let near = arts.min { simd_distance($0.pos, me) < simd_distance($1.pos, me) }
            let l = near.flatMap { simd_distance($0.pos, me) < 3.2 && !$0.title.isEmpty ? $0.title : nil }
            if l != label { label = l }
        }
        .overlay(alignment: .top) { LabelChip(text: label) }
        .background(Color.black)
        .navigationTitle("The Haul").navigationBarTitleDisplayMode(.inline)
        .task { await archive.load(model: model) }
    }
}

// MARK: - The Weight: his archive floating in the dark, free flight

struct WeightRoom: View {
    let model: AppModel
    @State private var archive = ArchiveList.shared
    @State private var rig = FlyRig()
    @State private var label: String?
    @State private var floaters: [(e: Entity, baseY: Float, phase: Float, title: String)] = []
    @State private var clock: Float = 0

    var body: some View {
        WorldStage(rig: rig, fov: 52) { content in
            rig.position = [0, 2, 24]; rig.flying = true; rig.bounds = nil; rig.speed = 4
            let works = archive.works
            let count = 54
            let step = works.isEmpty ? 1 : max(1, works.count / count)
            var made: [(Entity, Float, Float, String)] = []
            for i in 0..<count {
                let a = (seeded(i, 1) + 1) * .pi
                let r = 4 + (seeded(i, 2) + 1) / 2 * 20
                let y = -7 + (seeded(i, 3) + 1) / 2 * 22
                let scale = 0.9 + (seeded(i, 4) + 1) / 2 * 1.8
                let w = works.isEmpty ? nil : works[(i * step) % works.count]
                let e = await ThreeDPictures.framed(w?.thumbURL, width: 0.96 * scale, height: 1.2 * scale)
                e.position = [cos(a) * r, y, sin(a) * r]
                e.orientation = simd_quatf(angle: (seeded(i, 5) + 1) * .pi, axis: [0, 1, 0]) * simd_quatf(angle: seeded(i, 6) * 0.15, axis: [1, 0, 0])
                content.add(e)
                made.append((e, y, (seeded(i, 7) + 1) * .pi, w?.cr ?? ""))
            }
            floaters = made.map { (e: $0.0, baseY: $0.1, phase: $0.2, title: $0.3) }
        } tick: { dt in
            clock += dt
            for f in floaters { f.e.position.y = f.baseY + sin(clock * 0.4 + f.phase) * 0.25 }
            let me = rig.position
            if let n = floaters.min(by: { simd_distance($0.e.position, me) < simd_distance($1.e.position, me) }), simd_distance(n.e.position, me) < 4, !n.title.isEmpty {
                if label != n.title { label = n.title }
            } else if label != nil { label = nil }
        }
        .overlay(alignment: .top) { LabelChip(text: label) }
        .background(Color.black)
        .navigationTitle("The Weight").navigationBarTitleDisplayMode(.inline)
        .task { await archive.load(model: model) }
    }
}

// MARK: - The walk-through archive: six lanes by category, time running away down the hall

struct ArchiveSpaceRoom: View {
    let model: AppModel
    @State private var archive = ArchiveList.shared
    @State private var rig = FlyRig()
    @State private var label: String?
    @State private var root = Entity()
    @State private var live: [Int: Entity] = [:]
    @State private var loading = Set<Int>()
    @State private var clock: Float = 0

    private static let catX: [String: Float] = ["digital": -20, "drawing": -12, "painting": -4, "print": 4, "photo": 12, "mixed": 20]
    private static func place(_ w: ArchiveWork) -> SIMD3<Float> {
        let n = w.n ?? 1
        return [(catX[w.cat ?? ""] ?? 0) + seeded(n, 0) * 4, seeded(n, 1) * 8, (Float(n) / 1768 - 1) * 140]
    }
    private static func year(_ n: Int) -> String {
        let b = [1, 253, 505, 757, 1009, 1261, 1513, 1769], y = ["2019", "2020", "2021", "2022", "2023", "2024", "2025"]
        for i in 0..<7 where n >= b[i] && n < b[i + 1] { return y[i] }
        return "2025"
    }

    var body: some View {
        WorldStage(rig: rig, fov: 58) { content in
            rig.position = [0, 0, 6]; rig.flying = true; rig.bounds = nil; rig.speed = 6
            content.add(root)
        } tick: { dt in
            clock += dt
            guard clock > 0.4 else { return }
            clock = 0
            let me = rig.position
            let near = archive.works.filter { simd_distance(Self.place($0), me) < 38 }
            let keep = Set(near.compactMap { $0.n })
            for (n, e) in live where !keep.contains(n) { e.removeFromParent(); live[n] = nil }
            for w in near.prefix(70) {
                guard let n = w.n, live[n] == nil, !loading.contains(n) else { continue }
                loading.insert(n)
                Task { @MainActor in
                    let e = await ThreeDPictures.framed(w.thumbURL, width: 1.6, height: 2.0)
                    e.position = Self.place(w)
                    e.orientation = simd_quatf(angle: seeded(n, 2) * 0.35, axis: [0, 1, 0])
                    root.addChild(e); live[n] = e; loading.remove(n)
                }
            }
            if let nearest = near.min(by: { simd_distance(Self.place($0), me) < simd_distance(Self.place($1), me) }), simd_distance(Self.place(nearest), me) < 4 {
                let l = "\(nearest.cr) · \(Self.year(nearest.n ?? 1))"
                if label != l { label = l }
            } else if label != nil { label = nil }
        }
        .overlay(alignment: .top) { LabelChip(text: label) }
        .background(Color.black)
        .navigationTitle("The archive").navigationBarTitleDisplayMode(.inline)
        .task { await archive.load(model: model) }
    }
}

// MARK: - The money room: GlyphGuy, gold, dancing in cash that falls and piles and is shoved aside

struct MoneyRoom: View {
    @State private var figure = GlyphFigure()
    @State private var bills: [ModelEntity] = []
    @State private var clock: Float = 0
    @State private var ready = false

    var body: some View {
        OrbitStage(distance: 7.5, height: 1.4, autoSpin: true) { pivot in
            let floor = ModelEntity(mesh: .generateBox(size: [12, 0.2, 12]), materials: [SimpleMaterial(color: ThreeDHouse.ground, roughness: 0.9, isMetallic: false)])
            floor.position.y = -0.1
            floor.components.set(CollisionComponent(shapes: [.generateBox(size: [12, 0.2, 12])]))
            floor.components.set(PhysicsBodyComponent(shapes: [.generateBox(size: [12, 0.2, 12])], mass: 1, mode: .static))
            pivot.addChild(floor)
            // an invisible bowl so the cash stays in the pen
            let bowl: [(Float, Float, Float, Float)] = [(0, 4.6, 9.4, 0.2), (0, -4.6, 9.4, 0.2), (4.6, 0, 0.2, 9.4), (-4.6, 0, 0.2, 9.4)]
            for (x, z, sx, sz) in bowl {
                let w = Entity(); w.position = [x, 1.5, z]
                let s = ShapeResource.generateBox(size: [sx, 3, sz])
                w.components.set(CollisionComponent(shapes: [s])); w.components.set(PhysicsBodyComponent(shapes: [s], mass: 1, mode: .static))
                pivot.addChild(w)
            }
            if await figure.load(look: .gold) {
                let holder = Entity(); holder.position = [0, 0.44, 0]
                let cap = ShapeResource.generateCapsule(height: 1.6, radius: 0.35).offsetBy(translation: [0, 0.9, 0])
                holder.components.set(CollisionComponent(shapes: [cap]))
                holder.components.set(PhysicsBodyComponent(shapes: [cap], mass: 50, mode: .kinematic))
                holder.addChild(figure.root)
                pivot.addChild(holder)
                await figure.play(.samba)
            }
            // the cash: gold paper bills and a few coins (no green, no fluid sheet: just bills)
            let paper = SimpleMaterial(color: UIColor(red: 0.85, green: 0.74, blue: 0.42, alpha: 1), roughness: 0.6, isMetallic: false)
            let coin = ThreeDModels.goldMaterial(rough: 0.25)
            var made: [ModelEntity] = []
            for i in 0..<180 {
                let isCoin = i % 14 == 0
                let mesh: MeshResource = isCoin ? .generateCylinder(height: 0.012, radius: 0.05) : .generateBox(size: [0.16, 0.004, 0.07])
                let b = ModelEntity(mesh: mesh, materials: [isCoin ? coin : paper])
                let shape: ShapeResource = isCoin ? .generateBox(size: [0.1, 0.012, 0.1]) : .generateBox(size: [0.16, 0.012, 0.07])
                b.components.set(CollisionComponent(shapes: [shape]))
                b.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0.05, material: .generate(friction: 0.7, restitution: 0.1), mode: .dynamic))
                b.position = [seeded(i, 1) * 3.5, 1.5 + Float(i) * 0.06, seeded(i, 2) * 3.5]
                b.orientation = simd_quatf(angle: seeded(i, 3) * .pi, axis: simd_normalize(SIMD3<Float>(seeded(i, 4), 1, seeded(i, 5))))
                pivot.addChild(b); made.append(b)
            }
            bills = made
            ready = true
        }
        .task {
            var last = Date()
            while !Task.isCancelled {
                let now = Date(); let dt = Float(now.timeIntervalSince(last)); last = now
                figure.tick(dt)
                clock += dt
                if clock > 0.35, !bills.isEmpty {   // a settled bill goes back up so the cash keeps falling
                    clock = 0
                    let b = bills[Int.random(in: 0..<bills.count)]
                    b.position = [Float.random(in: -3...3), 4.5, Float.random(in: -3...3)]
                    b.components.set(PhysicsMotionComponent())
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .overlay { if !ready { ProgressView() } }
        .navigationTitle("The money room").navigationBarTitleDisplayMode(.inline)
    }
}
