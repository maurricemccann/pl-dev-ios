import RealityKit
import UIKit
import simd

/// Room 1's surfaces: baked stone sets (albedo, normal, roughness; his tile engraved into the grooves), gold, glows. One shared instance per room load.
@MainActor final class P1Materials {
    enum Failure: Error { case missing(String) }

    var rock = PhysicallyBasedMaterial(), floor = PhysicallyBasedMaterial(), yellow = PhysicallyBasedMaterial(), cream = PhysicallyBasedMaterial()
    var sand = PhysicallyBasedMaterial(), tunnel = PhysicallyBasedMaterial(), tier = PhysicallyBasedMaterial()
    var gold = PhysicallyBasedMaterial(), polished = PhysicallyBasedMaterial(), face = PhysicallyBasedMaterial(), water = PhysicallyBasedMaterial()
    var orb = PhysicallyBasedMaterial(), halo = UnlitMaterial(), shaft = UnlitMaterial()
    /// Warm tints the look's saturation scales (stone sets and their base tint).
    var tints: [(ReferenceWritableKeyPath<P1Materials, PhysicallyBasedMaterial>, SIMD3<Float>)] = []

    static func load(_ name: String, _ ext: String, _ semantic: TextureResource.Semantic) async throws -> TextureResource {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { throw Failure.missing(name) }
        return try await TextureResource(contentsOf: url, options: .init(semantic: semantic, mipmapsMode: .allocateAndGenerateAll))
    }

    private func stone(_ set: String, tint: SIMD3<Float>) async throws -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Self.ui(tint), texture: .init(try await Self.load("plw-p1-\(set)-albedo", "jpg", .color)))
        m.normal = .init(texture: .init(try await Self.load("plw-p1-\(set)-normal", "jpg", .normal)))
        m.roughness = .init(scale: 1, texture: .init(try await Self.load("plw-p1-\(set)-rough", "jpg", .raw)))
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    static func ui(_ c: SIMD3<Float>) -> UIColor { UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1) }

    func load() async throws {
        let rockTint: SIMD3<Float> = [1.0, 0.95, 0.86], floorTint: SIMD3<Float> = [1.0, 0.96, 0.88], sandTint: SIMD3<Float> = [1.0, 0.92, 0.8]
        rock = try await stone("rock", tint: rockTint); floor = try await stone("floor", tint: floorTint)
        yellow = try await stone("yellow", tint: [1, 1, 1]); cream = try await stone("cream", tint: [1, 0.98, 0.94])
        sand = try await stone("sand", tint: sandTint)
        tunnel = try await stone("rock", tint: [1.0, 0.62, 0.3])      // the way on is orange (his tunnel colour), the next tunnel shifts it
        tunnel.emissiveColor = .init(color: Self.ui([0.22, 0.09, 0.02])); tunnel.emissiveIntensity = 0.6
        tints = [(\.rock, rockTint), (\.floor, floorTint), (\.sand, sandTint)]

        tier = cream
        tier.baseColor = .init(tint: .white, texture: .init(try await Self.load("plw-p1-tiletier-albedo", "jpg", .color)))
        yellow.roughness = .init(scale: 0.9, texture: yellow.roughness.texture)

        polished.baseColor = .init(tint: Self.ui([1.0, 0.77, 0.33])); polished.metallic = .init(floatLiteral: 0.9); polished.roughness = .init(floatLiteral: 0.32)
        polished.emissiveColor = .init(color: Self.ui([0.32, 0.22, 0.06])); polished.emissiveIntensity = 1   // a warm self-light so gold never reads black in the cave
        polished.faceCulling = .none
        gold = polished; gold.roughness = .init(floatLiteral: 0.5)

        face.baseColor = .init(tint: .white, texture: .init(try await Self.load("plw-p1-face", "png", .color)))
        face.normal = .init(texture: .init(try await Self.load("plw-p1-face-normal", "jpg", .normal)))
        face.roughness = .init(floatLiteral: 0.8); face.metallic = .init(floatLiteral: 0)
        face.blending = .transparent(opacity: .init(floatLiteral: 1)); face.opacityThreshold = 0.4

        water.baseColor = .init(tint: Self.ui([0.05, 0.08, 0.09])); water.roughness = .init(floatLiteral: 0.05); water.metallic = .init(floatLiteral: 0.2)
        water.emissiveColor = .init(color: Self.ui([0.55, 0.36, 0.1])); water.emissiveIntensity = 0.7

        orb.baseColor = .init(tint: Self.ui([0.1, 0.09, 0.08]))
        orb.emissiveColor = .init(color: Self.ui([1, 0.85, 0.5]), texture: .init(try await Self.load("plw-p1-tiletier-albedo", "jpg", .color)))
        orb.emissiveIntensity = 2.4; orb.roughness = .init(floatLiteral: 0.4)

        let h = try await Self.load("plw-p1-halo", "png", .color)
        halo.color = .init(tint: .white, texture: .init(h)); halo.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let s = try await Self.load("plw-p1-shaft", "png", .color)
        shaft.color = .init(tint: .white, texture: .init(s)); shaft.blending = .transparent(opacity: .init(floatLiteral: 0.32)); shaft.faceCulling = .none
    }

    /// The look's saturation on the warm stone tints (never toward black: only the chroma moves).
    func apply(saturation s: Float) {
        for (path, base) in tints {
            let l = simd_dot(base, [0.2126, 0.7152, 0.0722]), c = SIMD3<Float>(repeating: l) + (base - SIMD3<Float>(repeating: l)) * s
            self[keyPath: path].baseColor.tint = Self.ui(simd_clamp(c, .zero, SIMD3<Float>(repeating: 1)))
        }
    }
}
