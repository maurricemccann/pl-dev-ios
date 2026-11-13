import ARKit
import AVFoundation
import CoreMotion
import RealityKit
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

    var body: some View {
        ZStack {
            Color(hex: 0x0e0c08).ignoresSafeArea()
            switch ar.mode {
            case .idle: gate
            case .room: LabARRoomView(tile: ar.tile) { ar.note = $0 }.ignoresSafeArea()
            case .camera, .preview:
                if ar.mode == .camera { LabCameraBackdrop(session: ar.session).ignoresSafeArea() }
                else { RadialGradient(colors: [Color(hex: 0x151109), Color(hex: 0x0e0c08)], center: .center, startRadius: 0, endRadius: 400).ignoresSafeArea() }
                overlay
            }
            if !ar.note.isEmpty && ar.mode != .idle {
                VStack { Spacer()
                    Text(ar.note).font(.system(size: 11)).tracking(0.9).foregroundStyle(PLG.gold.opacity(0.8)).multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0e0c08).opacity(0.7)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(PLG.gold.opacity(0.27), lineWidth: 1) })
                        .padding(.bottom, 24).padding(.horizontal, 30) }
                .allowsHitTesting(false)
            }
            if ar.mode != .idle {
                VStack { HStack { Spacer()
                    Picker("Mode", selection: Binding(get: { ar.mode == .room ? 1 : 0 }, set: { v in if v == 1 { ar.openRoom() } else { Task { await ar.openCamera() } } })) {
                        Text("The view").tag(0); Text("The room").tag(1)
                    }.pickerStyle(.segmented).frame(width: 190).padding(.trailing, 14) }
                    .padding(.top, 56); Spacer() }
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
                let phase = tl.date.timeIntervalSince(ar.start) * 0.6
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

// MARK: - the room: ARKit world tracking, tap to anchor

private struct LabARRoomView: UIViewRepresentable {
    let tile: UIImage?
    let say: (String) -> Void

    func makeCoordinator() -> Coord { Coord(tile: tile, say: say) }
    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero)
        v.automaticallyConfigureSession = false
        let cfg = ARWorldTrackingConfiguration()
        cfg.planeDetection = [.horizontal]
        v.session.run(cfg)
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.tapped(_:))))
        context.coordinator.view = v
        return v
    }
    func updateUIView(_ v: ARView, context: Context) { context.coordinator.tile = tile }
    static func dismantleUIView(_ v: ARView, coordinator: Coord) { v.session.pause() }

    @MainActor final class Coord: NSObject {
        var tile: UIImage?
        let say: (String) -> Void
        weak var view: ARView?
        init(tile: UIImage?, say: @escaping (String) -> Void) { self.tile = tile; self.say = say }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view, let cg = tile?.cgImage else { say("The pattern is still loading. Try again in a moment."); return }
            let p = g.location(in: view)
            guard let hit = view.raycast(from: p, allowing: .estimatedPlane, alignment: .horizontal).first else { say("No surface there yet. Move the phone slowly over the floor or table."); return }
            Task { @MainActor in
                guard let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) else { return }
                var m = UnlitMaterial()
                m.color = .init(tint: .white, texture: .init(tex))
                m.blending = .transparent(opacity: 0.94)
                let plane = ModelEntity(mesh: .generatePlane(width: 1.2, depth: 1.2), materials: [m])
                let anchor = AnchorEntity(raycastResult: hit)
                anchor.addChild(plane)
                view.scene.addAnchor(anchor)
                say("Anchored. Tap again to add another.")
            }
        }
    }
}
