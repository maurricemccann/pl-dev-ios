import SwiftUI
import RealityKit
import UIKit

/// The shared parts of every 3D room: his USDZ models (converted from his GLBs by `scripts/glb_to_usdz.py`, never redrawn),
/// the house materials, an orbit stage for single objects, and a fly rig for the walk-through worlds.
enum ThreeDHouse {
    static let gold = UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1)        // #c9a84c
    static let darkGold = UIColor(red: 0.541, green: 0.416, blue: 0.133, alpha: 1)    // #8a6a22
    static let obsidian = UIColor(red: 0.027, green: 0.027, blue: 0.027, alpha: 1)    // #070707
    static let ground = UIColor(red: 0.055, green: 0.047, blue: 0.031, alpha: 1)      // #0e0c08
}

@MainActor enum ThreeDModels {
    /// A converted model from the app bundle, by file name without the extension.
    static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "usdz") ?? Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Models")
    }

    static func load(_ name: String) async -> Entity? {
        guard let u = url(name) else { return nil }
        return try? await Entity(contentsOf: u)
    }

    /// Scales the model so its longest side is `longest` metres, centres it on x and z and seats it on y = 0.
    static func fitted(_ e: Entity, longest: Float) -> Entity {
        let holder = Entity()
        holder.addChild(e)
        var b = e.visualBounds(relativeTo: holder)
        let m = max(b.extents.x, b.extents.y, b.extents.z)
        if m > 0 { e.scale = SIMD3<Float>(repeating: longest / m) }
        b = e.visualBounds(relativeTo: holder)
        e.position += SIMD3<Float>(-b.center.x, -b.min.y, -b.center.z)
        return holder
    }

    /// Every mesh under the entity gets this one material (the house gold, obsidian, marble).
    static func paint(_ e: Entity, _ material: RealityKit.Material) {
        if var mc = e.components[ModelComponent.self] {
            mc.materials = Array(repeating: material, count: max(1, mc.materials.count))
            e.components.set(mc)
        }
        for c in e.children { paint(c, material) }
    }

    static func goldMaterial(rough: Float = 0.32) -> SimpleMaterial { SimpleMaterial(color: ThreeDHouse.gold, roughness: .init(floatLiteral: rough), isMetallic: true) }

    static func unlit(_ c: UIColor) -> UnlitMaterial { UnlitMaterial(color: c) }

    static func light(intensity: Float = 3000, at p: SIMD3<Float>, look: SIMD3<Float> = .zero) -> Entity {
        let e = Entity()
        var l = DirectionalLightComponent(); l.intensity = intensity; l.color = UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 1)
        e.components.set(l)
        e.position = p; e.look(at: look, from: p, relativeTo: nil)
        return e
    }

    static func camera(fov: Float = 42) -> Entity {
        let c = Entity()
        c.components.set(PerspectiveCameraComponent(near: 0.05, far: 400, fieldOfViewInDegrees: fov))
        return c
    }
}

/// A texture from a picture on the web (the archive thumbnails are public images).
enum ThreeDPictures {
    @MainActor static var cache: [URL: TextureResource] = [:]

    @MainActor static func texture(_ url: URL) async -> TextureResource? {
        if let t = cache[url] { return t }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let cg = UIImage(data: data)?.cgImage,
              let t = try? await TextureResource(image: cg, options: .init(semantic: .color)) else { return nil }
        cache[url] = t
        return t
    }

    @MainActor static func framed(_ url: URL?, width: Float, height: Float, tint: UIColor = ThreeDHouse.darkGold) async -> ModelEntity {
        var m = UnlitMaterial(color: tint)
        if let url, let t = await texture(url) { m = UnlitMaterial(); m.color = .init(tint: .white, texture: .init(t)) }
        let e = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [m])
        return e
    }
}

// MARK: - The archive list (his real works), shared by the Haul, the Weight and the archive space

struct ThreeDArchiveWork: Decodable, Identifiable, Hashable, Sendable {
    let cr: String
    let thumb: String?
    let title: String?
    let cat: String?
    let n: Int?
    var id: String { cr }
    var thumbURL: URL? { thumb.flatMap { URL(string: $0) } }
}

@MainActor @Observable final class ArchiveList {
    static let shared = ArchiveList()
    private(set) var works: [ThreeDArchiveWork] = []
    private(set) var failed = false

    private struct Manifest: Decodable { let pieces: [ThreeDArchiveWork] }

    func load(model: AppModel) async {
        guard works.isEmpty, let http = model.http else { return }
        do {
            let m = try JSONDecoder().decode(Manifest.self, from: try await http.send(RequestPlan(origin: "gallery", path: "archive/manifest.json")))
            works = m.pieces.filter { $0.thumb != nil }
            failed = false
        } catch { failed = true }
    }
}

// MARK: - A stage for one object: orbit by drag, pinch to zoom, and it turns by itself until touched

struct OrbitStage: View {
    var distance: Float = 3.0
    var height: Float = 0.9
    var autoSpin: Bool = true
    var build: @MainActor (Entity) async -> Void
    @State private var pivot = Entity()
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var zoom: Float = 1
    @State private var touching = false
    @State private var last: CGSize = .zero
    @State private var cam = ThreeDModels.camera()

    var body: some View {
        RealityView { content in
            // the ground shows through: RealityView has no settable background on iOS
            content.add(ThreeDModels.light(intensity: 3200, at: [2, 4, 3], look: [0, 1, 0]))
            content.add(ThreeDModels.light(intensity: 1400, at: [-3, 2, -2], look: [0, 1, 0]))
            content.add(pivot)
            content.add(cam)
            await build(pivot)
        } update: { _ in
            cam.position = [0, height + 0.15, distance * zoom]
            cam.look(at: [0, height, 0], from: cam.position, relativeTo: nil)
            pivot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        }
        .gesture(DragGesture().onChanged { v in
            touching = true
            yaw += Float(v.translation.width - last.width) * 0.011
            pitch = max(-0.5, min(0.5, pitch + Float(v.translation.height - last.height) * 0.005))
            last = v.translation
        }.onEnded { _ in touching = false; last = .zero })
        .simultaneousGesture(MagnifyGesture().onChanged { v in zoom = max(0.5, min(2.5, 1 / Float(v.magnification))) })
        .task {
            while !Task.isCancelled {
                if autoSpin && !touching { yaw += 0.006 }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

// MARK: - A walk-through rig: left thumb moves, right drag looks (the web's two-thumb controls)

@MainActor @Observable final class FlyRig {
    var position: SIMD3<Float> = [0, 1.62, 8]
    var yaw: Float = 0
    var pitch: Float = 0
    var move: SIMD2<Float> = .zero      // x = strafe, y = forward, each -1...1
    var rise: Float = 0                 // -1...1 (free-fly worlds only)
    var flying = false
    var bounds: Float? = 11.5           // square room half-size; nil = open
    var speed: Float = 3.0              // metres per second

    func step(_ dt: Float) {
        let fwd = SIMD3<Float>(-sin(yaw) * cos(flying ? pitch : 0), flying ? sin(pitch) : 0, -cos(yaw) * cos(flying ? pitch : 0))
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        position += (fwd * move.y + right * move.x) * speed * dt
        if flying { position.y += rise * speed * dt }
        if let b = bounds { position.x = max(-b, min(b, position.x)); position.z = max(-b, min(b, position.z)) }
    }

    func apply(to cam: Entity) {
        cam.position = position
        cam.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }
}

struct FlyControls: View {
    let rig: FlyRig
    @State private var knob: CGSize = .zero
    @State private var lastLook: CGSize = .zero
    private let radius: CGFloat = 52

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                    rig.yaw -= Float(v.translation.width - lastLook.width) * 0.0042
                    rig.pitch = max(-1.2, min(1.2, rig.pitch - Float(v.translation.height - lastLook.height) * 0.0042))
                    lastLook = v.translation
                }.onEnded { _ in lastLook = .zero })
            Circle().fill(.ultraThinMaterial).frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().fill(.thinMaterial).frame(width: 44, height: 44).offset(knob))
                .padding(24)
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let d = CGSize(width: v.translation.width, height: v.translation.height)
                    let len = max(1, hypot(d.width, d.height))
                    let k = min(len, radius) / len
                    knob = CGSize(width: d.width * k, height: d.height * k)
                    rig.move = SIMD2(Float(knob.width / radius), Float(-knob.height / radius))
                }.onEnded { _ in knob = .zero; rig.move = .zero })
                .accessibilityLabel("Move")
        }
    }
}
