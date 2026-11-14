import RealityKit
import SwiftUI

/// The Room (`app/room/page.tsx`, `components/room/ScrollRoom.tsx`, `components/world/WorldGallery.tsx`) in RealityKit: the
/// obsidian gallery with gold structural lines, his heart mark lit high on the far wall (read from the site's own logo.svg and
/// extruded), six of his drawings framed in the side niches (the site's `/room-art/` set), GlyphGuy walking by the door, and the
/// door ajar with light from beyond. The camera glides the site's keyframed path on its own (the phone tour: 16 s, a hold, a
/// loop); a drag scrubs the same path, as the desktop scroll does. "Enter / the congregation" rises in, and ✕ leaves.
struct SiteRoomView: View {
    @State private var cam = PerspectiveCamera()
    @State private var fig = GlyphFigure()
    @State private var p: Double = 0
    @State private var scrubbing = false
    @State private var scrubFrom: Double = 0
    @State private var showEnter = false
    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let path: [(SIMD3<Float>, SIMD3<Float>)] = [
        ([0, 1.75, 6.8], [0, 1.6, -2]), ([-1.7, 1.6, 5.0], [-3.2, 1.6, 2.5]), ([-0.6, 1.5, 3.4], [2.0, 1.5, 1.2]),
        ([1.1, 1.5, 3.4], [0.2, 1.3, -1.6]), ([0.5, 1.5, 3.0], [0.05, 1.35, -1.9]), ([0.15, 1.55, 2.7], [0.0, 1.35, -1.95]),
    ]
    private static let art = ["PL-0533", "PL-0961", "PL-0258", "PL-0121", "PL-0274", "PL-0552"]
    private static let gold = UIColor(red: 0xc9 / 255, green: 0xa8 / 255, blue: 0x4c / 255, alpha: 1)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x0e0c08).ignoresSafeArea()
                RealityView { content in
                    let aspect = Double(geo.size.width / max(geo.size.height, 1))
                    let narrow: Double = min(1.0, max(0.0, (1.6 - aspect) / 1.2))
                    let fov: Double = aspect >= 1.6 ? 42.0 : 42.0 + narrow * 20.0
                    cam.camera.fieldOfViewInDegrees = Float(fov)
                    content.add(cam)
                    await build(&content)
                    place(reduce ? 1 : 0)
                    ready = true
                }
                .ignoresSafeArea()
                .gesture(DragGesture()
                    .onChanged { v in
                        if !scrubbing { scrubbing = true; scrubFrom = p }
                        p = min(1, max(0, scrubFrom - Double(v.translation.height + v.translation.width) / 900))
                        place(p)
                    }
                    .onEnded { _ in scrubbing = false })
                .accessibilityLabel("The Room: a dark gallery with gold lines, his drawings framed on the walls, GlyphGuy beside a door left open. Drag to move through it.")

                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .light)).foregroundStyle(Bone.gold.opacity(0.7))
                                .frame(width: 44, height: 44).overlay { Circle().strokeBorder(Bone.gold.opacity(0.2), lineWidth: 1) }
                        }
                        .accessibilityLabel("Leave the room")
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                    Spacer()
                    if showEnter {
                        Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: {
                            VStack(spacing: 10) {
                                Text("Enter").font(SiteFont.display(52, italic: true)).foregroundStyle(Bone.gold)
                                Text("the congregation").siteTag(11, Bone.goldDim)
                            }
                            .frame(minWidth: 160, minHeight: 100).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, geo.size.height * 0.08)
                    }
                }
                if !ready { PLLoader().tint(Bone.gold) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .task {
            try? await Task.sleep(for: .milliseconds(2800))
            withAnimation(.timingCurve(0.2, 0.1, 0.2, 1, duration: 1)) { showEnter = true }
        }
        .task { await tour() }
    }

    /// The auto-tour: the path in 16 s, a 2.5 s hold, again. A drag takes over; letting go resumes from where it was left.
    private func tour() async {
        guard !reduce else { return }
        var last = Date()
        while !Task.isCancelled {
            let now = Date(), dt = now.timeIntervalSince(last); last = now
            fig.tick(Float(dt))
            if ready && !scrubbing {
                p += dt / 16
                if p > 1 + 2.5 / 16 { p = 0 }
                place(min(1, p))
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func place(_ t: Double) {
        let e = Float(t * t * (3 - 2 * t))
        let pos = Self.catmull(Self.path.map(\.0), e), look = Self.catmull(Self.path.map(\.1), e)
        cam.look(at: look, from: pos, relativeTo: nil)
    }

    /// A centripetal-free uniform Catmull-Rom through the keyframes, as three.js's CatmullRomCurve3 default draws it.
    private static func catmull(_ pts: [SIMD3<Float>], _ u: Float) -> SIMD3<Float> {
        let n = pts.count - 1
        let x = u * Float(n), i = min(n - 1, Int(x)), t = x - Float(i)
        let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(n, i + 2)]
        let t2 = t * t, t3 = t2 * t
        let a: SIMD3<Float> = 2 * p1
        let b: SIMD3<Float> = (p2 - p0) * t
        let c: SIMD3<Float> = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let d: SIMD3<Float> = (3 * p1 - p0 - 3 * p2 + p3) * t3
        return 0.5 * (a + b + c + d)
    }

    // MARK: the room

    @MainActor private func build(_ content: inout RealityViewCameraContent) async {
        let wall = SimpleMaterial(color: UIColor(red: 0x17 / 255, green: 0x13 / 255, blue: 0x10 / 255, alpha: 1), roughness: 0.88, isMetallic: false)
        let goldMat = SimpleMaterial(color: Self.gold, roughness: 0.35, isMetallic: true)
        func add(_ mesh: MeshResource, _ m: RealityKit.Material, _ pos: SIMD3<Float>, ry: Float = 0, rx: Float = 0) {
            let e = ModelEntity(mesh: mesh, materials: [m]); e.position = pos
            e.orientation = simd_quatf(angle: ry, axis: [0, 1, 0]) * simd_quatf(angle: rx, axis: [1, 0, 0])
            content.add(e)
        }
        add(.generatePlane(width: 10, height: 4.5), wall, [0, 2.25, -2])                       // back wall
        add(.generatePlane(width: 9, height: 4.5), wall, [-5, 2.25, 2.5], ry: .pi / 2)         // left
        add(.generatePlane(width: 9, height: 4.5), wall, [5, 2.25, 2.5], ry: -.pi / 2)         // right
        add(.generatePlane(width: 10, height: 9), wall, [0, 4.5, 2.5], rx: .pi / 2)            // ceiling
        add(.generatePlane(width: 40, depth: 40), SimpleMaterial(color: UIColor(red: 0x1c / 255, green: 0x17 / 255, blue: 0x0e / 255, alpha: 1), roughness: 0.08, isMetallic: true), [0, 0, 0])   // the polished floor
        add(.generateBox(size: [10, 0.05, 0.05]), goldMat, [0, 0.025, -1.98])
        for sx: Float in [-1, 1] { add(.generateBox(size: [0.05, 0.05, 9]), goldMat, [sx * 4.98, 0.025, 2.5]) }

        // the door: light from beyond, gold jambs and lintel, the panel swung open
        let dz: Float = -1.95, dw: Float = 1.2, dh: Float = 2.5
        add(.generatePlane(width: dw, height: dh), UnlitMaterial(color: UIColor(red: 1, green: 0xea / 255, blue: 0xc2 / 255, alpha: 1)), [0, dh / 2, dz - 0.04])
        add(.generateBox(size: [dw + 0.2, 0.1, 0.1]), goldMat, [0, dh + 0.05, dz])
        add(.generateBox(size: [0.1, dh + 0.15, 0.1]), goldMat, [-(dw / 2 + 0.05), dh / 2, dz])
        add(.generateBox(size: [0.1, dh + 0.15, 0.1]), goldMat, [dw / 2 + 0.05, dh / 2, dz])
        let hinge = Entity(); hinge.position = [dw / 2 + 0.05, dh / 2, dz + 0.06]; hinge.orientation = simd_quatf(angle: 1.15, axis: [0, 1, 0])
        let panel = ModelEntity(mesh: .generateBox(size: [dw, dh, 0.06]), materials: [SimpleMaterial(color: UIColor(red: 0x14 / 255, green: 0x11 / 255, blue: 0x0b / 255, alpha: 1), roughness: 0.5, isMetallic: true)])
        panel.position = [-dw / 2, 0, 0]; hinge.addChild(panel); content.add(hinge)

        // the lights: the spill from the door, the key, the fill, the wall washes, three spots on the niches
        func light(_ e: Entity, _ pos: SIMD3<Float>) { e.position = pos; content.add(e) }
        let spill = Entity(); spill.components.set(PointLightComponent(color: UIColor(red: 1, green: 0xd9 / 255, blue: 0xa0 / 255, alpha: 1), intensity: 16000, attenuationRadius: 10)); light(spill, [0, 1.4, -1.0])
        let fill = Entity(); fill.components.set(PointLightComponent(color: UIColor(red: 1, green: 0.94, blue: 0.82, alpha: 1), intensity: 12000, attenuationRadius: 24)); light(fill, [0, 3.6, 3.8])
        for wx: Float in [-4.4, 4.4] { let w = Entity(); w.components.set(PointLightComponent(color: UIColor(red: 1, green: 0.91, blue: 0.75, alpha: 1), intensity: 6000, attenuationRadius: 13)); light(w, [wx, 2.4, 3]) }
        let key = Entity(); var dl = DirectionalLightComponent(); dl.intensity = 1200; dl.color = UIColor(red: 1, green: 0.94, blue: 0.81, alpha: 1); key.components.set(dl)
        key.look(at: [0, 0, 0], from: [2, 6, 5], relativeTo: nil); content.add(key)

        // his heart mark, high above the door
        if let mark = await SiteLogo.path(), let mesh = try? await MeshResource(extruding: mark.applying(CGAffineTransform(scaleX: 1, y: -1)), extrusionOptions: .init()) {
            let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: Self.gold)])
            let b = e.visualBounds(relativeTo: nil), s = 1.25 / max(b.extents.x, b.extents.y, 0.001)
            e.scale = [s, s, 0.01 * s]
            let b2 = e.visualBounds(relativeTo: nil)
            e.position = [-b2.center.x, 3.5 - b2.center.y, -1.95]
            content.add(e)
        }

        // the niches: his drawings, in ink on bone, gold-framed, three a side
        var textures: [TextureResource] = []
        for cr in Self.art {
            if let tex = await Self.texture(cr) { textures.append(tex) }
        }
        if !textures.isEmpty {
            var gi = 0
            for nz: Float in [-0.4, 1.7, 3.8] {
                for (x, ry) in [(Float(-4.92), Float.pi / 2), (4.92, -Float.pi / 2)] {
                    let tex = textures[gi % textures.count]; gi += 1
                    let grp = Entity(); grp.position = [x, 1.65, nz]; grp.orientation = simd_quatf(angle: ry, axis: [0, 1, 0])
                    grp.addChild(ModelEntity(mesh: .generatePlane(width: 1.0, height: 1.32), materials: [goldMat]))
                    let paper = ModelEntity(mesh: .generatePlane(width: 0.92, height: 1.24), materials: [UnlitMaterial(color: UIColor(red: 0xf4 / 255, green: 0xf1 / 255, blue: 0xea / 255, alpha: 1))])
                    paper.position.z = 0.012; grp.addChild(paper)
                    let ar = Float(tex.width) / Float(max(tex.height, 1)), s = min(0.92 * 0.84 / ar, 1.24 * 0.84)
                    var ink = UnlitMaterial(); ink.color = .init(tint: UIColor(white: 0.07, alpha: 1), texture: .init(tex)); ink.blending = .transparent(opacity: .init(floatLiteral: 1))
                    let art = ModelEntity(mesh: .generatePlane(width: s * ar, height: s), materials: [ink]); art.position.z = 0.02; grp.addChild(art)
                    content.add(grp)
                }
            }
        }

        // the inhabitant
        if await fig.load(height: 1.9, look: .gold, world: true) {
            let inhab = Entity(); inhab.position = [0.95, 0, -0.2]; inhab.orientation = simd_quatf(angle: -2.3, axis: [0, 1, 0])
            inhab.addChild(fig.root); content.add(inhab)
            if !reduce { await fig.play(.walking) }
        }
    }

    /// A room drawing from the site (`/room-art/<cr>.png`), downloaded once and kept in Caches.
    private static func texture(_ cr: String) async -> TextureResource? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RoomArt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(cr + ".png")
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let u = await Site.page("room-art/\(cr).png"), let (d, r) = try? await URLSession.shared.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? d.write(to: file)
        }
        return try? await TextureResource(contentsOf: file)
    }
}
