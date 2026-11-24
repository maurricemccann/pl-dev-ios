import ARKit
import AVFoundation
import Combine
import Metal
import RealityKit
import ReplayKit
import SwiftUI

// The room, wrapped by itself. ARView + an ARSession delegate, because ARKit's ARPlaneAnchor is the only door that hands over each detected plane
// WITH its extent and centre (developer.apple.com/documentation/arkit/arplaneanchor: planeExtent, center, alignment); SpatialTrackingSession only
// anchors content to "a plane" (AnchorEntity(.plane), docs: realitykit/anchorentity) and never says how big it is, so it cannot size a wrap.
// Every floor and wall the phone finds gets his art (tile, or The Direction) at one metre per repeat, grown as the plane grows. Tap stays as an extra.
// His art is decoded and uploaded ONCE per art; a plane is one shared unit mesh, scaled; nothing is rebuilt per frame (the 11-15 CPU report: 65 % for 138 s).

// MARK: - what the debugger shows

struct LabWrapStats: Equatable {
    var tracking = "starting"
    var horizontal = 0, vertical = 0, meshes = 0
    var renderFPS = 0, cameraFPS = 0
    var work = "idle"
    var error = "none"
    var lidar = false
}

/// A plane as plain numbers, made in the delegate and handed to the main actor.
private struct LabPlaneInfo: Sendable {
    let id: UUID
    let transform: simd_float4x4
    let center: SIMD3<Float>
    let width: Float, depth: Float, rotation: Float
    let vertical: Bool
    init(_ a: ARPlaneAnchor) {
        id = a.identifier; transform = a.transform; center = a.center
        width = a.planeExtent.width; depth = a.planeExtent.height; rotation = a.planeExtent.rotationOnYAxis
        vertical = a.alignment == .vertical
    }
}

private func labTrackingText(_ s: ARCamera.TrackingState) -> String {
    switch s {
    case .normal: return "normal"
    case .notAvailable: return "not available"
    case .limited(let r):
        switch r {
        case .initializing: return "limited: initializing"
        case .excessiveMotion: return "limited: moving too fast"
        case .insufficientFeatures: return "limited: not enough detail"
        case .relocalizing: return "limited: relocalizing"
        @unknown default: return "limited"
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

// MARK: - the session and the scene

@MainActor @Observable final class LabWrapBox: NSObject, ARSessionDelegate {
    @ObservationIgnored let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private(set) var stats = LabWrapStats()
    @ObservationIgnored var showStats = false
    @ObservationIgnored var tile: UIImage? { didSet { if tile !== oldValue { Task { await prepare() } } } }
    @ObservationIgnored var direction: UIImage?
    @ObservationIgnored var art = LabARArt.tile { didSet { if art != oldValue { Task { await prepare() } ; restyle() } } }
    @ObservationIgnored var say: (String) -> Void = { _ in }
    @ObservationIgnored var found: (Bool) -> Void = { _ in }
    @ObservationIgnored var wrapOn = true { didSet { planeRoot.isEnabled = wrapOn } }
    @ObservationIgnored var drawing = false

    // decoded once, reused for every plane
    private var textures: [LabARArt: TextureResource] = [:]
    private static let unit = MeshResource.generatePlane(width: 1, depth: 1)
    private static let sampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat; d.tAddressMode = .repeat
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear; d.maxAnisotropy = 4
        return .init(d)
    }()

    @MainActor private final class Plane { let model = ModelEntity(); var info: LabPlaneInfo; init(_ i: LabPlaneInfo) { info = i } }
    private var planes: [UUID: Plane] = [:]
    private let planeRoot = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private let placedRoot = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private let airRoot = AnchorEntity(world: SIMD3<Float>(0, 0, 0))

    // the debugger's counters
    private var running = false
    private var frames = 0
    private var renders = 0
    private var meshAnchors = 0
    private var peakMs: [String: Double] = [:]
    private var inFlight: Set<String> = []
    private var lastStat = Date()
    private var lastSend = Date()
    private var updates: Cancellable?

    // the curve being drawn in the air, in chunks so no mesh grows long
    private var airPoints: [SIMD3<Float>] = []
    private var airEntity: ModelEntity?
    private var sinceMesh = 0
    private static let airChunk = 48

    var lidar: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    // MARK: start and stop

    func start() async -> String? {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return "Camera access is off, so the room cannot be tracked. Showing the view overlay instead." }
        guard ARWorldTrackingConfiguration.isSupported else { return "This phone cannot track a room. Showing the view overlay instead." }
        view.session.delegate = self
        view.session.delegateQueue = .main
        // the cheap render path: no person cut-out, blur, depth of field, grain, HDR or grounding shadows; the camera image and his art only
        view.renderOptions = [.disablePersonOcclusion, .disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disableHDR, .disableGroundingShadows, .disableAREnvironmentLighting, .disableFaceMesh]
        view.scene.addAnchor(planeRoot); view.scene.addAnchor(placedRoot); view.scene.addAnchor(airRoot)
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRender() }
        }
        let c = ARWorldTrackingConfiguration()
        c.planeDetection = [.horizontal, .vertical]
        c.environmentTexturing = .none
        if lidar {   // real things hide the curves; the depth mesh only feeds occlusion (collision and shadows are off: they cost frames)
            c.sceneReconstruction = .mesh
            view.environment.sceneUnderstanding.options = [.occlusion]
        } else {
            say("No LiDAR on this phone: flat floors and walls still wrap; real things will not hide the curves.")
        }
        // half the camera frames, half the work: the 30 fps video format at the best size the phone offers
        if let f = ARWorldTrackingConfiguration.supportedVideoFormats.filter({ $0.framesPerSecond <= 30 }).max(by: { $0.imageResolution.width < $1.imageResolution.width }) { c.videoFormat = f }
        running = true
        stats.lidar = lidar
        view.session.run(c)
        await prepare()
        return nil
    }

    func stop() {
        guard running else { return }
        running = false
        updates?.cancel(); updates = nil
        view.session.pause()
        view.scene.anchors.removeAll()
        planes = [:]
    }

    // MARK: the art, decoded once

    private func prepare() async {
        let key = art
        guard textures[key] == nil, let cg = (key == .direction ? direction : tile)?.cgImage else { return }
        inFlight.insert("texture"); defer { inFlight.remove("texture") }
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            textures[key] = try await TextureResource(image: cg, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        } catch { fail("texture: \(error.localizedDescription)"); return }
        mark("texture", t0)
        restyle()
    }

    private func material(_ scale: SIMD2<Float>) -> UnlitMaterial? {
        guard let tex = textures[art] else { return nil }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(tex, sampler: Self.sampler))
        m.blending = .transparent(opacity: 0.94)
        m.textureCoordinateTransform = .init(offset: .zero, scale: scale, rotation: 0)
        return m
    }

    /// The art changed or arrived: every plane takes it, no rebuild of a mesh or a texture.
    private func restyle() {
        for p in planes.values { if let m = material([p.info.width, p.info.depth]) { p.model.model?.materials = [m] } }
    }

    // MARK: planes

    private func apply(added: [LabPlaneInfo], removed: [UUID], meshDelta: Int) {
        let t0 = CFAbsoluteTimeGetCurrent()
        meshAnchors = max(0, meshAnchors + meshDelta)
        for id in removed { if let p = planes.removeValue(forKey: id) { p.model.removeFromParent() } }
        for i in added { place(i) }
        if !added.isEmpty || !removed.isEmpty {
            found(!planes.isEmpty)
            note("planes: \(planes.values.filter { !$0.info.vertical }.count) floor/table, \(planes.values.filter { $0.info.vertical }.count) wall")
            mark("planes", t0)
        }
    }

    /// New plane: one entity sharing the unit mesh. Known plane: only a real change (4 cm of size, 3 cm of move) touches it.
    private func place(_ i: LabPlaneInfo) {
        if let p = planes[i.id] {
            let moved = simd_distance(p.info.transform.columns.3, i.transform.columns.3) + simd_distance(p.info.center, i.center)
            guard abs(p.info.width - i.width) > 0.04 || abs(p.info.depth - i.depth) > 0.04 || moved > 0.03 || abs(p.info.rotation - i.rotation) > 0.05 else { return }
            p.info = i
            pose(p)
            if let m = material([i.width, i.depth]) { p.model.model?.materials = [m] }
        } else {
            let p = Plane(i)
            p.model.model = ModelComponent(mesh: Self.unit, materials: material([i.width, i.depth]).map { [$0] } ?? [])
            pose(p)
            planeRoot.addChild(p.model)
            planes[i.id] = p
        }
    }

    /// The anchor's pose, then the plane's own centre and turn, then its size; 3 mm off the surface so the art never fights the real thing.
    private func pose(_ p: Plane) {
        let i = p.info
        let local = Transform(scale: [max(i.width, 0.05), 1, max(i.depth, 0.05)], rotation: simd_quatf(angle: i.rotation, axis: [0, 1, 0]), translation: i.center + [0, 0.003, 0]).matrix
        p.model.transform = Transform(matrix: i.transform * local)
    }

    // MARK: ARSessionDelegate (main queue; plain numbers cross to the main actor)

    nonisolated func session(_ s: ARSession, didAdd anchors: [ARAnchor]) { handle(anchors, event: 0) }
    nonisolated func session(_ s: ARSession, didUpdate anchors: [ARAnchor]) { handle(anchors, event: 1) }
    nonisolated func session(_ s: ARSession, didRemove anchors: [ARAnchor]) { handle(anchors, event: 2) }

    /// event 0 added, 1 updated, 2 removed. A mesh anchor only counts on add and remove; a plane is made or resized on add and update.
    private nonisolated func handle(_ anchors: [ARAnchor], event: Int) {
        let infos = anchors.compactMap { ($0 as? ARPlaneAnchor).map(LabPlaneInfo.init) }
        let meshes = anchors.filter { $0 is ARMeshAnchor }.count
        let delta = event == 0 ? meshes : (event == 2 ? -meshes : 0)
        MainActor.assumeIsolated { self.apply(added: event == 2 ? [] : infos, removed: event == 2 ? infos.map(\.id) : [], meshDelta: delta) }
    }

    nonisolated func session(_ s: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { self.frames += 1 }
    }

    nonisolated func session(_ s: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let t = labTrackingText(camera.trackingState)
        MainActor.assumeIsolated { self.stats.tracking = t; self.note("tracking: \(t)") }
    }

    nonisolated func session(_ s: ARSession, didFailWithError error: any Error) {
        let m = error.localizedDescription
        MainActor.assumeIsolated { self.fail(m) }
    }

    nonisolated func sessionWasInterrupted(_ s: ARSession) { MainActor.assumeIsolated { self.stats.tracking = "interrupted"; self.note("interrupted") } }
    nonisolated func sessionInterruptionEnded(_ s: ARSession) { MainActor.assumeIsolated { self.stats.tracking = "resuming"; self.note("interruption ended") } }

    // MARK: the debugger's numbers (cheap: counters every frame, a snapshot twice a second, the wire every five seconds)

    private func mark(_ name: String, _ t0: CFAbsoluteTime) { peakMs[name] = max(peakMs[name] ?? 0, (CFAbsoluteTimeGetCurrent() - t0) * 1000) }

    private func fail(_ m: String) {
        stats.error = m
        note("error: \(m)")
    }

    /// An event line for the house debug channel: kept in the app's own list always, sent only while Debug is on (DebugLog gates that).
    private func note(_ line: String) { AppModel.shared.debug.note("ar", line) }

    private func onRender() {
        renders += 1
        if drawing { sampleAir() }
        let now = Date()
        let dt = now.timeIntervalSince(lastStat)
        guard dt >= 0.5 else { return }
        var s = stats
        s.renderFPS = Int((Double(renders) / dt).rounded()); s.cameraFPS = Int((Double(frames) / dt).rounded())
        renders = 0; frames = 0; lastStat = now
        s.horizontal = planes.values.filter { !$0.info.vertical }.count
        s.vertical = planes.values.filter { $0.info.vertical }.count
        s.meshes = meshAnchors
        var w = peakMs.filter { $0.value >= 1 }.sorted { $0.key < $1.key }.map { "\($0.key) \(Int($0.value)) ms" }
        w += inFlight.sorted().map { "\($0)…" }
        s.work = w.isEmpty ? "idle" : w.joined(separator: " · ")
        peakMs = [:]
        if showStats, s != stats { stats = s }
        if now.timeIntervalSince(lastSend) >= 5, UserDefaults.standard.bool(forKey: "pldev.debug") {
            lastSend = now
            note("fps \(s.renderFPS)/\(s.cameraFPS) · planes \(s.horizontal)+\(s.vertical) · mesh \(s.meshes) · \(s.tracking) · work \(s.work)")
        }
    }

    // MARK: tap: an extra patch where a finger lands

    func tapped(_ p: CGPoint) {
        guard let hit = view.raycast(from: p, allowing: .existingPlaneGeometry, alignment: .any).first ?? view.raycast(from: p, allowing: .estimatedPlane, alignment: .any).first else {
            say("No surface there yet. Move the phone slowly over the room."); return
        }
        guard let m = material([1, 1]) else { say("The art is still loading. Try again in a moment."); return }
        let e = ModelEntity(mesh: Self.unit, materials: [m])
        e.transform = Transform(matrix: hit.worldTransform * Transform(translation: [0, 0.006, 0]).matrix)
        placedRoot.addChild(e)
        say("Placed. Tap again to add another.")
    }

    // MARK: draw in the air: the camera's position while a finger is held, 35 cm in front of the lens

    func beginAir() { guard running else { return }; airPoints = []; sinceMesh = 0; newChunk(); drawing = true }
    func endAir() { drawing = false; rebuildAir(); airEntity = nil }

    private func newChunk() { let e = ModelEntity(); airRoot.addChild(e); airEntity = e }

    private func sampleAir() {
        guard let m = view.session.currentFrame?.camera.transform else { return }
        let fwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z) + fwd * 0.35
        if let l = airPoints.last, simd_distance(l, p) < 0.012 { return }
        airPoints.append(p); sinceMesh += 1
        if airPoints.count >= Self.airChunk { rebuildAir(); let tail = airPoints.last; airPoints = tail.map { [$0] } ?? []; newChunk(); sinceMesh = 0 }
        else if sinceMesh >= 4 { sinceMesh = 0; rebuildAir() }
    }

    private func rebuildAir() {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let e = airEntity, let mesh = labTubeMesh(airPoints, radius: 0.007) else { return }
        e.model = ModelComponent(mesh: mesh, materials: [UnlitMaterial(color: LabARDirection.colour)])
        mark("tube", t0)
    }

    func clear() {
        for c in Array(placedRoot.children) { c.removeFromParent() }
        for c in Array(airRoot.children) { c.removeFromParent() }
        airPoints = []; airEntity = nil
    }
}

// MARK: - the screen

private struct LabARViewHost: UIViewRepresentable {
    let box: LabWrapBox
    func makeUIView(context: Context) -> ARView { box.view }
    func updateUIView(_ v: ARView, context: Context) {}
}

struct LabARRoomView: View {
    let tile: UIImage?
    let say: (String) -> Void
    let failed: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var box = LabWrapBox()
    @State private var found = false
    @State private var pulse = false
    @State private var art = LabARArt.tile
    @State private var drawMode = false
    @State private var wrapOn = true
    @State private var recording = false
    @State private var movie: URL?
    @State private var holding = false
    @AppStorage("pldev.ar.debugpanel") private var panel = false

    var body: some View {
        ZStack {
            LabARViewHost(box: box).ignoresSafeArea()
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if drawMode && !holding { holding = true; box.beginAir() } }
                    .onEnded { v in
                        if drawMode { holding = false; box.endAir() }
                        else if abs(v.translation.width) < 12 && abs(v.translation.height) < 12 { box.tapped(v.location) }
                    })
            if !found {   // no coaching overlay without an ARCoachingOverlayView session of its own, so the house draws the line
                Label("Finding the floor and walls. Move the phone slowly.", systemImage: "viewfinder")
                    .font(Font.pl(size: 12, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 44)
                    .glassEffect(.regular, in: Capsule())
                    .opacity(pulse ? 1 : 0.6)
                    .onAppear { if reduceMotion { pulse = true } else { withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true } } }
                    .accessibilityLabel("Finding the floor and walls. Move the phone slowly.")
                    .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { panel.toggle(); box.showStats = panel } label: { Image(systemName: panel ? "ladybug.fill" : "ladybug").font(Font.pl(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44) }
                        .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel(panel ? "Hide the debugger" : "Show the debugger")
                    Button { wrapOn.toggle(); box.wrapOn = wrapOn; say(wrapOn ? "Walls and floor wrapped." : "Wrap hidden. Tap a surface to place the art.") } label: { Image(systemName: wrapOn ? "square.grid.3x3.fill" : "square.grid.3x3").font(Font.pl(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44) }
                        .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel(wrapOn ? "Hide the wrap on floor and walls" : "Wrap the floor and walls")
                }
                if panel { debugPanel }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 14).padding(.top, 12)
            VStack { Spacer(); controls }
        }
        .task {
            box.showStats = panel
            box.tile = tile; box.direction = LabARDirection.image(); box.say = say; box.found = { if $0 != found { found = $0 } }
            if let why = await box.start() { failed(why) }
        }
        .onChange(of: tile) { _, t in box.tile = t }
        .onChange(of: art) { _, a in box.art = a }
        .onChange(of: drawMode) { _, d in say(d ? "Hold a finger down and move the phone to draw in the air." : "The floor and walls wrap by themselves. Tap to add a patch.") }
        .onDisappear {
            box.stop()
            if recording {
                let discard = FileManager.default.temporaryDirectory.appendingPathComponent("ar-discard.mov")
                try? FileManager.default.removeItem(at: discard)   // stopRecording fails if the file is already there
                RPScreenRecorder.shared().stopRecording(withOutput: discard, completionHandler: nil)
            }
        }
    }

    /// Tracking, planes, mesh, frame rates, the heavy work, the last error: monospaced 11 pt on glass, never in the way of a tap.
    private var debugPanel: some View {
        let s = box.stats
        return VStack(alignment: .leading, spacing: 2) {
            row("tracking", s.tracking)
            row("planes", "\(s.horizontal) floor/table · \(s.vertical) wall")
            row("mesh", s.lidar ? "\(s.meshes) anchors (LiDAR)" : "no LiDAR")
            row("fps", "render \(s.renderFPS) · camera \(s.cameraFPS)")
            row("work", s.work)
            row("error", s.error)
        }
        .font(Font.pl(size: 11, design: .monospaced)).foregroundStyle(.white)
        .padding(10).frame(maxWidth: 300, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14 * PLStyle.radius))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text(k).foregroundStyle(.white.opacity(0.6)).frame(width: 62, alignment: .leading); Text(v) }
    }

    /// Art, Place or Draw, Record, Clear: one glass row, 44 pt targets, above the home indicator.
    private var controls: some View {
        VStack(spacing: 8) {
            if let movie {
                HStack(spacing: 10) {
                    ShareLink(item: movie) { Label("Save or share the video", systemImage: "square.and.arrow.up").font(Font.pl(size: 13, weight: .medium)).padding(.horizontal, 14).frame(minHeight: 44) }
                        .glassEffect(.regular.interactive(), in: Capsule())
                    Button { self.movie = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Close")
                }
            }
            HStack(spacing: 8) {
                Picker("Art", selection: $art) { Text("Tile").tag(LabARArt.tile); Text("Direction").tag(LabARArt.direction) }
                    .pickerStyle(.segmented).frame(maxWidth: .infinity)
                Picker("Mode", selection: $drawMode) { Text("Place").tag(false); Text("Draw").tag(true) }
                    .pickerStyle(.segmented).frame(maxWidth: .infinity)
                Button { toggleRecord() } label: { Image(systemName: recording ? "stop.circle.fill" : "record.circle").font(Font.pl(size: 22)).foregroundStyle(recording ? .red : .white).frame(width: 44, height: 44) }
                    .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel(recording ? "Stop recording" : "Record")
                Button { box.clear() } label: { Image(systemName: "trash").font(Font.pl(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44) }
                    .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Clear the patches and curves placed")
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
