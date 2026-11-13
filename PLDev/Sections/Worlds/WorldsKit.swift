import SwiftUI
import RealityKit
import Combine
import UIKit

// The Defiance worlds and the walk-through archive, native (wave 4). Ported from pl-curves-gallery
// `app/defiance/*` (Babylon / Three.js) and `app/archive/space`; his models are the converted USDZ files (never redrawn).
// This file is the shared kit: the engine (a non-AR RealityKit view, the pattern GlyphBot's stage already compiles with),
// lights, pictures with fog, the archive loader with its offline copy, the two-thumb controls and the caption.

// MARK: - Engine

/// One scene: a world-origin anchor, a camera and a per-frame callback. The view owns it; the rooms drive it.
@MainActor final class WorldEngine {
    let anchor = AnchorEntity(world: .zero)
    let camera = PerspectiveCamera()
    var onFrame: @MainActor (Float) -> Void = { _ in }
    private(set) weak var view: ARView?
    private var updates: Cancellable?

    init(fov: Float, far: Float = 300) {
        camera.camera.fieldOfViewInDegrees = fov
        camera.camera.near = 0.05
        camera.camera.far = far
        anchor.addChild(camera)
    }

    func add(_ e: Entity) { anchor.addChild(e) }

    fileprivate func attach(_ v: ARView) {
        view = v
        updates = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
            let dt = Float(e.deltaTime)
            MainActor.assumeIsolated { self?.onFrame(min(dt, 0.1)) }
        }
    }

    /// The view's aspect (width over height), 0.46 (a phone upright) until it has a size.
    var aspect: Float {
        guard let b = view?.bounds, b.height > 1 else { return 0.46 }
        return Float(b.width / b.height)
    }
    var viewSize: CGSize { view?.bounds.size ?? CGSize(width: 430, height: 932) }
}

/// A RealityKit view with no AR session and an opaque ground colour.
struct WorldView: UIViewRepresentable {
    let engine: WorldEngine
    var background: UIColor = ThreeDHouse.obsidian
    let setup: @MainActor (WorldEngine) async -> Void

    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        v.environment.background = .color(background)
        v.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disableGroundingShadows]
        v.scene.addAnchor(engine.anchor)
        engine.attach(v)
        let run = setup
        let eng = engine
        Task { @MainActor in await run(eng) }
        return v
    }

    func updateUIView(_ v: ARView, context: Context) {}
}

// MARK: - Lights

enum WorldLight {
    static let warm = UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 1)

    static func directional(_ intensity: Float, from p: SIMD3<Float>, look: SIMD3<Float> = .zero, color: UIColor = warm) -> Entity {
        let e = Entity()
        var l = DirectionalLightComponent(); l.intensity = intensity; l.color = color
        e.components.set(l); e.look(at: look, from: p, relativeTo: nil)
        return e
    }

    static func point(_ intensity: Float, radius: Float, at p: SIMD3<Float>, color: UIColor = warm) -> Entity {
        let e = Entity()
        var l = PointLightComponent(); l.intensity = intensity; l.color = color; l.attenuationRadius = radius
        e.components.set(l); e.position = p
        return e
    }

    static func spot(_ intensity: Float, radius: Float, from p: SIMD3<Float>, look: SIMD3<Float>, inner: Float = 24, outer: Float = 40, color: UIColor = warm) -> Entity {
        let e = Entity()
        var l = SpotLightComponent(); l.intensity = intensity; l.color = color; l.attenuationRadius = radius
        l.innerAngleInDegrees = inner; l.outerAngleInDegrees = outer
        e.components.set(l); e.look(at: look, from: p, relativeTo: nil)
        return e
    }
}

// MARK: - Small helpers

extension UIColor {
    /// A hex like 0xc9a84c.
    static func world(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    /// The colour scaled toward black (fog and dimming); alpha stays 1.
    func worldDim(_ f: Float) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = CGFloat(max(0, min(1, f)))
        return UIColor(red: r * k, green: g * k, blue: b * k, alpha: 1)
    }
}

/// The web's exponential-squared fog as a 0...1 visibility at a distance: pictures are self-lit, so fog is a tint.
func worldFog(_ distance: Float, density: Float) -> Float { exp(-pow(density * distance, 2)) }

/// A deterministic spread in -1...1, the same hash the archive page uses.
func worldSeeded(_ n: Int, _ salt: Int) -> Float {
    let x = sin(Double(n) * 127.1 + Double(salt) * 311.7) * 43758.5453123
    return Float((x - x.rounded(.down)) * 2 - 1)
}

/// The web's mulberry32, so the Weight's field lays out exactly as the page lays it out.
struct WorldRNG {
    private var a: UInt32
    init(seed: UInt32) { a = seed }
    mutating func next() -> Float {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Float(Double(t ^ (t >> 14)) / 4294967296.0)
    }
}

@MainActor enum WorldFit {
    /// Scales the model so it stands `h` metres tall, centres it on x and z and seats it on y = 0.
    static func height(_ e: Entity, _ h: Float) -> Entity {
        let holder = Entity()
        holder.addChild(e)
        var b = e.visualBounds(relativeTo: holder)
        if b.extents.y > 0 { e.scale = SIMD3<Float>(repeating: h / b.extents.y) }
        b = e.visualBounds(relativeTo: holder)
        e.position += SIMD3<Float>(-b.center.x, -b.min.y, -b.center.z)
        return holder
    }
}

// MARK: - A picture on a plane (self-lit, so it only takes fog)

@MainActor final class WorldPicture {
    let root = Entity()
    private let front: ModelEntity
    private var back: ModelEntity?
    private(set) var texture: TextureResource?
    private let base: UIColor
    private var lastVisibility: Float = 1

    init(mesh: MeshResource, base: UIColor, doubleSided: Bool) {
        self.base = base
        front = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: base)])
        root.addChild(front)
        if doubleSided {
            let b = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: base)])
            b.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]); b.position.z = -0.003
            root.addChild(b); back = b
        }
    }

    func set(texture t: TextureResource?, visibility f: Float = 1) { texture = t; apply(f) }

    /// Re-tints for fog; ignores changes too small to see.
    func fog(_ f: Float) { if abs(f - lastVisibility) > 0.03 { apply(f) } }

    private func apply(_ f: Float) {
        lastVisibility = f
        let m = material(f)
        front.model?.materials = [m]
        back?.model?.materials = [m]
    }

    private func material(_ f: Float) -> UnlitMaterial {
        if let t = texture {
            var m = UnlitMaterial()
            m.color = .init(tint: UIColor(white: CGFloat(f), alpha: 1), texture: .init(t))
            return m
        }
        return UnlitMaterial(color: base.worldDim(f))
    }
}

// MARK: - The archive (his real works) with a copy kept for offline

struct WorldPiece: Decodable, Identifiable, Hashable, Sendable {
    let cr: String
    var title: String?
    var url: String?
    var thumb: String?
    var cat: String?
    var med: String?
    var year: String?
    var id: String { cr }

    /// The PL number: the page's `n` (1...1767). The manifest's own `n` is now a per-subject counter, so this reads the id.
    var number: Int { Int(cr.filter(\.isNumber)) ?? 1 }
    var thumbURL: URL? { thumb.flatMap { URL(string: $0) } }
    var fullURL: URL? { url.flatMap { URL(string: $0) } }

    private enum Keys: String, CodingKey { case cr, title, url, thumb, cat, med, year }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        cr = try c.decode(String.self, forKey: .cr)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        thumb = try? c.decodeIfPresent(String.self, forKey: .thumb)
        cat = try? c.decodeIfPresent(String.self, forKey: .cat)
        med = try? c.decodeIfPresent(String.self, forKey: .med)
        if let s = try? c.decodeIfPresent(String.self, forKey: .year) { year = s }
        else if let i = try? c.decodeIfPresent(Int.self, forKey: .year) { year = String(i) }
    }
}

@MainActor @Observable final class WorldArchive {
    static let shared = WorldArchive()
    private(set) var pieces: [WorldPiece] = []
    private(set) var failed = false
    private(set) var fromCopy = false
    private var loading = false

    private struct Manifest: Decodable { let pieces: [WorldPiece] }

    private static var copyURL: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("world-archive.json")
    }

    /// Loads once per launch. A failed fetch falls back to the copy kept from the last good one.
    func load(model: AppModel, force: Bool = false) async {
        if loading || (!pieces.isEmpty && !force) { return }
        loading = true; defer { loading = false }
        if let http = model.http, let data = try? await http.send(RequestPlan(origin: "gallery", path: "archive/manifest.json")),
           let m = try? JSONDecoder().decode(Manifest.self, from: data), !m.pieces.isEmpty {
            pieces = m.pieces.filter { $0.thumb != nil }
            failed = false; fromCopy = false
            try? data.write(to: Self.copyURL, options: .atomic)
            return
        }
        if let data = try? Data(contentsOf: Self.copyURL), let m = try? JSONDecoder().decode(Manifest.self, from: data), !m.pieces.isEmpty {
            pieces = m.pieces.filter { $0.thumb != nil }
            failed = false; fromCopy = true
            return
        }
        failed = true
    }
}

@MainActor enum WorldTextures {
    /// A thumbnail as a texture, or nil when it will not load (the gold placeholder stays, as on the page).
    static func load(_ url: URL) async -> TextureResource? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let cg = UIImage(data: data)?.cgImage,
              let t = try? await TextureResource(image: cg, options: .init(semantic: .color)) else { return nil }
        return t
    }
}

// MARK: - The controls: the left thumb walks (a stick that appears where it lands), the right thumb looks

struct WorldControls: View {
    let rig: FlyRig
    var pitchLimit: Float = 1.2
    @State private var base: CGPoint?
    @State private var knob: CGSize = .zero
    @State private var lastLook: CGSize = .zero
    private let reach: CGFloat = 46

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: g.size.width * 0.45).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("worldpad"))
                            .onChanged { v in
                                if base == nil { base = v.startLocation }
                                let dx = v.location.x - v.startLocation.x, dy = v.location.y - v.startLocation.y
                                let mag = max(1, hypot(dx, dy)), k = min(mag, reach) / mag
                                knob = CGSize(width: dx * k, height: dy * k)
                                rig.move = SIMD2(Float(knob.width / reach), Float(-knob.height / reach))
                            }
                            .onEnded { _ in base = nil; knob = .zero; rig.move = .zero })
                        .accessibilityLabel("Walk")
                        .accessibilityHint("Drag with the left thumb")
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                rig.yaw -= Float(v.translation.width - lastLook.width) * 0.0042
                                rig.pitch = max(-pitchLimit, min(pitchLimit, rig.pitch - Float(v.translation.height - lastLook.height) * 0.0042))
                                lastLook = v.translation
                            }
                            .onEnded { _ in lastLook = .zero })
                        .accessibilityLabel("Look")
                        .accessibilityHint("Drag with the right thumb")
                }
                if let base {
                    ZStack {
                        Circle().fill(PLG.gold.opacity(0.06)).overlay(Circle().strokeBorder(PLG.gold.opacity(0.35), lineWidth: 1.5)).frame(width: 120, height: 120)
                        Circle().fill(PLG.gold.opacity(0.5)).frame(width: 48, height: 48).shadow(color: PLG.gold.opacity(0.4), radius: 8).offset(knob)
                    }
                    .position(base).allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "worldpad")
        }
    }
}

// MARK: - The caption near an artwork (his italic, gold, with the year under it)

struct WorldCaptionData: Equatable { var title: String; var year: String }

struct WorldCaption: View {
    let data: WorldCaptionData?
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 4) {
                Text(data?.title ?? " ").font(.system(.title, design: .serif).italic()).tracking(1.4).foregroundStyle(PLG.gold)
                    .multilineTextAlignment(.center).shadow(color: .black.opacity(0.9), radius: 6, y: 2)
                if let y = data?.year, !y.isEmpty {
                    Text(y).font(.system(size: 12)).tracking(2.6).foregroundStyle(PLG.gold.opacity(0.7))
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 110)
            .opacity(data == nil ? 0 : 1)
            .animation(.easeInOut(duration: 0.5), value: data)
        }
        .allowsHitTesting(false)
        .sensoryFeedback(PLHaptic.select, trigger: data?.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.map { [$0.title, $0.year].filter { !$0.isEmpty }.joined(separator: ", ") } ?? "")
    }
}

/// One plain line at the top when the archive did not load, with the way to try again.
struct WorldArchiveNotice: View {
    let archive: WorldArchive
    let model: AppModel
    var body: some View {
        VStack {
            if archive.failed {
                HStack(spacing: 10) {
                    Text("The archive did not load. The frames stay gold until it does.").font(.footnote)
                    Button("Try again") { Task { await archive.load(model: model, force: true) } }.font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule()).padding(.top, 6)
            } else if archive.fromCopy {
                Text("Offline. Showing the last copy of the archive.").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(.thinMaterial, in: Capsule()).padding(.top, 6)
            }
            Spacer()
        }
        .tint(PLG.gold)
    }
}
