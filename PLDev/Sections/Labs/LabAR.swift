import ARKit
import AVFoundation
import CoreMotion
import RealityKit
import ReplayKit
import SwiftUI

// AR curves: "wrap the world in curves" (app/lab/ar/page.tsx, app/lab/ar-surface/page.tsx).
// Two ways in, as the site has them: WRAP THE VIEW (the camera behind, his curve tile over it, anchored to the phone's motion), and WRAP THE ROOM
// (real world tracking: tap a floor or table and the tile is anchored there, ARKit through RealityKit). The tile is his curve marks only,
// solid black on real transparency, from the gallery (patterns/ar-curve-tile.png). With no camera it shows the same overlay on a dark ground.

// MARK: - the camera behind

private final class LabCameraView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct LabCameraBackdrop: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> LabCameraView {
        let v = LabCameraView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: LabCameraView, context: Context) {}
}

/// The capture session crosses to a background thread to start and stop, as Apple asks.
final class LabSessionBox: @unchecked Sendable { let session = AVCaptureSession() }

@MainActor @Observable final class LabARModel {
    enum Mode { case idle, camera, preview, room }
    var mode = Mode.idle
    var note = ""
    var tile: UIImage?
    // the overlay's smoothed inputs
    @ObservationIgnored var offX = 0.0
    @ObservationIgnored var offY = 0.0
    @ObservationIgnored var rot = 0.0
    @ObservationIgnored var tOffX = 0.0
    @ObservationIgnored var tOffY = 0.0
    @ObservationIgnored var tRot = 0.0
    let box = LabSessionBox()
    var session: AVCaptureSession { box.session }
    private let motion = CMMotionManager()
    @ObservationIgnored private var configured = false
    let start = Date()

    func loadTile(model: AppModel) async {
        guard tile == nil, let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "patterns/ar-curve-tile.png"), timeout: 40), let img = UIImage(data: d) else { return }
        tile = img
    }

    func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            // the page's deviceorientation: gamma is the left-right tilt, beta the front-back tilt (45 degrees held neutral), alpha the heading
            self.tOffX = a.roll * 180 / .pi * 4
            self.tOffY = (a.pitch * 180 / .pi - 45) * 4
            self.tRot = a.yaw * 0.15
        }
    }
    func stopMotion() { motion.stopDeviceMotionUpdates() }

    func openCamera() async {
        let ok = await AVCaptureDevice.requestAccess(for: .video)
        guard ok else { preview("Camera unavailable — showing preview. Grant camera access to wrap the live view."); return }
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .high
            if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            configured = true
        }
        guard !session.inputs.isEmpty else { preview("Camera unavailable — showing preview. Grant camera access to wrap the live view."); return }
        let b = box
        Task.detached { b.session.startRunning() }
        startMotion()
        mode = .camera; note = ""
    }

    func preview(_ why: String? = nil) {
        mode = .preview
        note = why ?? "Preview — drag to shift the pattern."
        startMotion()
    }

    func openRoom() {
        guard ARWorldTrackingConfiguration.isSupported else { preview("This phone cannot track a room. Showing the view overlay instead."); return }
        let b = box
        Task.detached { b.session.stopRunning() }
        stopMotion()
        mode = .room; note = "Move the phone slowly, then tap a floor or a table."
    }

    func leave() { let b = box; Task.detached { b.session.stopRunning() }; stopMotion(); mode = .idle }
}

// MARK: - the screen

struct LabARView: View {
    let model: AppModel
    @State private var ar = LabARModel()
    @State private var dragStart: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(hex: 0x0e0c08).ignoresSafeArea()
            switch ar.mode {
            case .idle: gate
            case .room: LabARRoomView(tile: ar.tile, say: { ar.note = $0 }, failed: { ar.preview($0) }).ignoresSafeArea()
            case .camera, .preview:
                if ar.mode == .camera { LabCameraBackdrop(session: ar.session).ignoresSafeArea() }
                else { RadialGradient(colors: [Color(hex: 0x151109), Color(hex: 0x0e0c08)], center: .center, startRadius: 0, endRadius: 400).ignoresSafeArea() }
                overlay
            }
            if !ar.note.isEmpty && ar.mode != .idle {
                VStack { Spacer()
                    Text(ar.note).font(.system(size: 11)).tracking(0.9).foregroundStyle(PLG.gold.opacity(0.8)).multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0e0c08).opacity(0.7)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(PLG.gold.opacity(0.27), lineWidth: 1) })
                        .padding(.bottom, ar.mode == .room ? 130 : 24).padding(.horizontal, 30) }
                .allowsHitTesting(false)
            }
            if ar.mode != .idle {
                VStack { HStack { Spacer()
                    Picker("Mode", selection: Binding(get: { ar.mode == .room ? 1 : 0 }, set: { v in if v == 1 { ar.openRoom() } else { Task { await ar.openCamera() } } })) {
                        Text("The view").tag(0); Text("The room").tag(1)
                    }.pickerStyle(.segmented).frame(width: 190).padding(.trailing, 14) }
                    .padding(.top, 12); Spacer() }
            }
        }
        .task { await ar.loadTile(model: model) }
        .onDisappear { ar.leave() }
        .sensoryFeedback(PLHaptic.select, trigger: ar.mode)
    }

    private var gate: some View {
        VStack(spacing: 22) {
            Text("Wrap the world in curves").font(.system(size: 13, weight: .light)).tracking(4.4).textCase(.uppercase).foregroundStyle(PLG.gold)
            Button { Task { await ar.openCamera() } } label: {
                Text("Open camera").font(.system(size: 12)).tracking(2.6).textCase(.uppercase).foregroundStyle(PLG.gold).padding(.horizontal, 30).frame(minHeight: 52)
                    .overlay { Capsule().strokeBorder(PLG.gold, lineWidth: 1) }
            }.buttonStyle(.plain)
            Button { ar.openRoom() } label: {
                Text("Wrap the room").font(.system(size: 12)).tracking(2.6).textCase(.uppercase).foregroundStyle(PLG.gold).padding(.horizontal, 30).frame(minHeight: 52)
                    .overlay { Capsule().strokeBorder(PLG.gold.opacity(0.55), lineWidth: 1) }
            }.buttonStyle(.plain)
            Button { ar.preview() } label: {
                Text("Preview without camera").font(.system(size: 10)).tracking(2).textCase(.uppercase).foregroundStyle(PLG.gold.opacity(0.53)).frame(minHeight: 44)
            }.buttonStyle(.plain)
            Text("Tap grants camera and motion access. Turn the phone — the curves hold to the world. The room mode tracks a floor or a table and keeps the pattern on it.")
                .font(.system(size: 10)).tracking(0.6).lineSpacing(4).foregroundStyle(PLG.gold.opacity(0.4)).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .padding(24)
    }

    /// His tile, repeated over the view; the phone's tilt shifts it, its heading turns it a little, and it drifts so it breathes when held still.
    private var overlay: some View {
        TimelineView(.animation) { tl in
            Canvas { gc, size in
                guard let tile = ar.tile else { return }
                ar.offX += (ar.tOffX - ar.offX) * 0.08; ar.offY += (ar.tOffY - ar.offY) * 0.08; ar.rot += (ar.tRot - ar.rot) * 0.08
                let phase = reduceMotion ? 0 : tl.date.timeIntervalSince(ar.start) * 0.6
                let side: CGFloat = 512   // one repeat is 512 CSS px on the page, so 512 points here
                let img = gc.resolve(Image(uiImage: tile))
                var c = gc
                c.translateBy(x: size.width / 2, y: size.height / 2)
                c.rotate(by: .radians(ar.rot))
                c.translateBy(x: -size.width / 2 + ar.offX, y: -size.height / 2 + ar.offY)
                c.opacity = 0.94
                let drift = phase * 6
                let margin = side
                var y = -margin + CGFloat(drift * 0.6).truncatingRemainder(dividingBy: side) - side
                while y < size.height + margin {
                    var x = -margin + CGFloat(drift).truncatingRemainder(dividingBy: side) - side
                    while x < size.width + margin { c.draw(img, in: CGRect(x: x, y: y, width: side, height: side)); x += side }
                    y += side
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in   // no motion sensor (the preview): a finger shifts the pattern
            if ar.mode == .preview { ar.tOffX = Double(v.translation.width) * 0.3; ar.tOffY = Double(v.translation.height) * 0.3 }
        })
        .ignoresSafeArea()
        .accessibilityLabel("His curves, held over the view. Tilt the phone to move them.")
    }
}

// MARK: - the room: RealityView + SpatialTrackingSession (planes, LiDAR collision + occlusion), tap to place, hold to draw, record

/// His art for the room. The tile is his gallery PNG; The Direction is rendered here from PracticeMapArt (his six strokes, his colour), transparent.
enum LabARArt: Int { case tile, direction }

enum LabARDirection {
    static let colour = UIColor(red: 0x5b / 255.0, green: 0x54 / 255.0, blue: 0xe6 / 255.0, alpha: 1)
    static func image(side: CGFloat = 1024) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.opaque = false; f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { ctx in
            let g = ctx.cgContext
            g.setStrokeColor(colour.cgColor); g.setLineWidth(PracticeMapArt.strokeWidth * side); g.setLineCap(.round); g.setLineJoin(.round)
            for s in PracticeMapArt.strokes where s.count > 1 {
                let p = s.map { CGPoint(x: $0.x * side, y: $0.y * side) }
                g.move(to: p[0])
                for i in 0..<(p.count - 1) {   // Catmull-Rom through his points, as The Direction draws them
                    let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
                    g.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6), control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
                }
                g.strokePath()
            }
        }
    }
}

/// A round tube along sampled points (parallel-transport frames), both windings so it shows from any side.
@MainActor private func labTubeMesh(_ pts: [SIMD3<Float>], radius: Float, sides: Int = 8) -> MeshResource? {
    guard pts.count >= 2 else { return nil }
    var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], idx: [UInt32] = []
    var prev: SIMD3<Float>?
    for i in pts.indices {
        let t = simd_normalize(pts[min(i + 1, pts.count - 1)] - pts[max(i - 1, 0)])
        var n = prev ?? (abs(t.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0))
        n = n - t * simd_dot(n, t)
        n = simd_length(n) < 1e-5 ? SIMD3<Float>(1, 0, 0) : simd_normalize(n)
        prev = n
        let b = simd_cross(t, n)
        for s in 0..<sides {
            let a = Float(s) / Float(sides) * 2 * .pi
            let d = n * cos(a) + b * sin(a)
            pos.append(pts[i] + d * radius); nor.append(d)
        }
    }
    for i in 0..<(pts.count - 1) {
        for s in 0..<sides {
            let a = UInt32(i * sides + s), b = UInt32(i * sides + (s + 1) % sides), c = UInt32((i + 1) * sides + s), d = UInt32((i + 1) * sides + (s + 1) % sides)
            idx += [a, c, b, b, c, d, a, b, c, b, d, c]
        }
    }
    var desc = MeshDescriptor(name: "air-curve")
    desc.positions = MeshBuffer(pos); desc.normals = MeshBuffer(nor); desc.primitives = .triangles(idx)
    return try? MeshResource.generate(from: [desc])
}

/// Holds the session and the scene for the room. With LiDAR the session adds collision and occlusion meshes of the real room, so a tap ray lands on
/// any real surface (a sofa arm, a table edge) and real things hide the curves. Without LiDAR a plane AnchorEntity probe (a thin collision slab) per
/// alignment is the fallback, as before.
@MainActor final class LabRoomBox {
    let session = SpatialTrackingSession()
    var content: RealityViewCameraContent?
    var tile: UIImage?
    var direction: UIImage?
    var art = LabARArt.tile
    var probes: [AnchorEntity] = []
    var aligns: [ObjectIdentifier: AnchoringComponent.Target.Alignment] = [:]
    var running = false
    var say: (String) -> Void = { _ in }
    var found: (Bool) -> Void = { _ in }
    // placed things, for Clear
    private var placed: [Entity] = []
    // the camera, and the curve being drawn in the air
    private let camera = AnchorEntity(.camera)
    private let airRoot = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private var airPoints: [SIMD3<Float>] = []
    private var airEntity: ModelEntity?
    var drawing = false
    private var sinceMesh = 0

    private func addProbe(_ alignment: AnchoringComponent.Target.Alignment) {
        guard let content else { return }
        let a = AnchorEntity(.plane(alignment, classification: .any, minimumBounds: [0.3, 0.3]))
        let slab = Entity()
        slab.components.set(CollisionComponent(shapes: [.generateBox(width: 6, height: 0.02, depth: 6)]))
        a.addChild(slab)
        if let scene = probes.first?.scene { scene.addAnchor(a) } else { content.add(a) }
        probes.append(a); aligns[ObjectIdentifier(a)] = alignment
    }

    func build(_ c: inout RealityViewCameraContent) {
        c.camera = .spatialTracking
        content = c
        c.add(camera); c.add(airRoot)
        addProbe(.horizontal); addProbe(.vertical)
        _ = c.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            guard let self else { return }
            self.found(self.running && (self.lidar || self.probes.contains { $0.isAnchored }))
            if self.drawing { self.sampleAir() }
        }
    }

    var lidar: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    /// Camera access first (a denial is a line and the preview, never a black screen), then the tracking session with scene understanding.
    func start() async -> String? {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return "Camera access is off, so the room cannot be tracked. Showing the view overlay instead." }
        let un = await session.run(.init(tracking: [.camera, .plane], sceneUnderstanding: [.occlusion, .collision, .shadow], camera: .back))
        if let un {
            if un.missingCameraAuthorization == true { return "Camera access is off, so the room cannot be tracked. Showing the view overlay instead." }
            if un.anchor.contains(.plane) { return "This phone cannot track a room. Showing the view overlay instead." }
        }
        running = true
        if !lidar { say("No LiDAR on this phone: flat floors and walls still work; real things will not hide the curves.") }
        return nil
    }

    func stop() { guard running else { return }; running = false; let s = session; Task { await s.stop() } }

    private func artImage() -> UIImage? { art == .direction ? direction : tile }

    /// A tap: the real room's mesh first (any surface, with its normal), else a detected plane.
    func tapped(_ p: CGPoint) async {
        guard let cg = artImage()?.cgImage else { say("The art is still loading. Try again in a moment."); return }
        guard let content, let ray = content.ray(through: p, in: .local, to: .scene), let scene = camera.scene ?? probes.first?.scene else { return }
        var pos: SIMD3<Float>?
        var normal = SIMD3<Float>(0, 1, 0)
        if let h = scene.raycast(origin: ray.origin, direction: ray.direction, length: 8, query: .nearest, mask: .sceneUnderstanding).first {
            pos = h.position; normal = simd_normalize(h.normal)
        } else if let h = scene.raycast(origin: ray.origin, direction: ray.direction).first(where: { h in probes.contains { h.entity.parent === $0 } }),
                  let anchor = probes.first(where: { h.entity.parent === $0 }) {
            pos = h.position
            normal = simd_normalize(anchor.convert(direction: SIMD3<Float>(0, 1, 0), to: nil))
            if let al = aligns[ObjectIdentifier(anchor)] { addProbe(al) }
        }
        guard let pos else { say("No surface there yet. Move the phone slowly over the room."); return }
        guard let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) else { return }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(tex))
        m.blending = .transparent(opacity: 0.94)
        // the plane mesh's local y is its normal: turn y onto the hit surface's normal and it lies flat on whatever was hit
        let q = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: normal)
        let anchor = AnchorEntity(world: Transform(rotation: q, translation: pos + normal * 0.003).matrix)
        anchor.addChild(ModelEntity(mesh: .generatePlane(width: 1.0, depth: 1.0), materials: [m]))
        scene.addAnchor(anchor)
        placed.append(anchor)
        say("Placed. Tap again to add another.")
    }

    // MARK: draw in the air: the camera's position while a finger is held, 35 cm in front of the lens

    func beginAir() {
        guard running else { return }
        airPoints = []; sinceMesh = 0
        let e = ModelEntity(); airRoot.addChild(e); airEntity = e; placed.append(e)
        drawing = true
    }

    func endAir() { drawing = false; rebuildAir(); airEntity = nil }

    private func sampleAir() {
        let m = camera.transformMatrix(relativeTo: nil)
        let fwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z) + fwd * 0.35
        if let l = airPoints.last, simd_distance(l, p) < 0.012 { return }
        airPoints.append(p); sinceMesh += 1
        if sinceMesh >= 3 { sinceMesh = 0; rebuildAir() }
    }

    private func rebuildAir() {
        guard let e = airEntity, let mesh = labTubeMesh(airPoints, radius: 0.007) else { return }
        e.model = ModelComponent(mesh: mesh, materials: [UnlitMaterial(color: LabARDirection.colour)])
    }

    func clear() { for e in placed { e.removeFromParent() }; placed = [] }
}

private struct LabARRoomView: View {
    let tile: UIImage?
    let say: (String) -> Void
    let failed: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var box = LabRoomBox()
    @State private var found = false
    @State private var pulse = false
    @State private var art = LabARArt.tile
    @State private var drawMode = false
    @State private var recording = false
    @State private var movie: URL?
    @State private var holding = false

    var body: some View {
        RealityView { content in box.build(&content) }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if drawMode && !holding { holding = true; box.beginAir() } }
                .onEnded { v in
                    if drawMode { holding = false; box.endAir() }
                    else if abs(v.translation.width) < 12 && abs(v.translation.height) < 12 { Task { await box.tapped(v.location) } }
                })
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if !found {   // RealityView has no coaching overlay of its own (that one needs an ARSession), so the house draws the line
                    Label("Finding a surface. Move the phone slowly.", systemImage: "viewfinder")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 44)
                        .glassEffect(.regular, in: Capsule())
                        .opacity(pulse ? 1 : 0.6).padding(.top, 64)
                        .onAppear { if reduceMotion { pulse = true } else { withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true } } }
                        .accessibilityLabel("Finding a surface. Move the phone slowly.")
                }
            }
            .overlay(alignment: .bottom) { controls }
            .task {
                box.tile = tile; box.direction = LabARDirection.image(); box.say = say; box.found = { if $0 != found { found = $0 } }
                if let why = await box.start() { failed(why) }
            }
            .onChange(of: tile) { _, t in box.tile = t }
            .onChange(of: art) { _, a in box.art = a }
            .onChange(of: drawMode) { _, d in say(d ? "Hold a finger down and move the phone to draw in the air." : "Tap a surface to place the art.") }
            .onDisappear {
                box.stop()
                if recording { RPScreenRecorder.shared().stopRecording(withOutput: FileManager.default.temporaryDirectory.appendingPathComponent("ar-discard.mov"), completionHandler: nil) }
            }
    }

    /// Art, Place or Draw, Record, Clear: one glass row, 44 pt targets, above the home indicator.
    private var controls: some View {
        VStack(spacing: 8) {
            if let movie {
                HStack(spacing: 10) {
                    ShareLink(item: movie) { Label("Save or share the video", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).frame(minHeight: 44) }
                        .glassEffect(.regular.interactive(), in: Capsule())
                    Button { self.movie = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Close")
                }
            }
            HStack(spacing: 8) {
                Picker("Art", selection: $art) { Text("Tile").tag(LabARArt.tile); Text("Direction").tag(LabARArt.direction) }
                    .pickerStyle(.segmented).frame(width: 150)
                Picker("Mode", selection: $drawMode) { Text("Place").tag(false); Text("Draw").tag(true) }
                    .pickerStyle(.segmented).frame(width: 130)
                Button { toggleRecord() } label: { Image(systemName: recording ? "stop.circle.fill" : "record.circle").font(.system(size: 22)).foregroundStyle(recording ? .red : .white).frame(width: 44, height: 44) }
                    .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel(recording ? "Stop recording" : "Record")
                Button { box.clear() } label: { Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44) }
                    .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Clear everything placed")
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
    }

    /// ReplayKit's screen recorder, no microphone, straight to a file; then the share sheet saves it to Photos.
    /// (Deprecated in iOS 27 in favour of ScreenCaptureKit; still works, kept until the phone pass shows otherwise.)
    private func toggleRecord() {
        let rec = RPScreenRecorder.shared()
        if recording {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pl-ar-\(Int(Date().timeIntervalSince1970)).mov")
            try? FileManager.default.removeItem(at: url)
            rec.stopRecording(withOutput: url) { err in
                Task { @MainActor in
                    recording = false
                    if let err { say("Recording failed: \(err.localizedDescription)") } else { movie = url; say("Recorded. Save or share it below.") }
                }
            }
        } else {
            guard rec.isAvailable else { say("Screen recording is not available right now."); return }
            rec.isMicrophoneEnabled = false
            rec.startRecording { err in
                Task { @MainActor in
                    if let err { say("Could not start recording: \(err.localizedDescription)") } else { recording = true; movie = nil; say("Recording. Tap stop when done.") }
                }
            }
        }
    }
}
