import Foundation
import RealityKit
import UIKit
import simd

// Lane B helpers: ring maths, a small mesh builder, the one tinted-material book. Everything here is local to lane B (blueprint rule 4: copy, never cross-import).
// World frame: x = map east (u), z = -map north (v), y up. A compass angle runs clockwise from north (PLWRing.point).

enum PLWMath {
    /// World position at ring radius r and compass angle theta (degrees).
    static func world(_ r: Float, _ thetaDeg: Float, y: Float = 0) -> SIMD3<Float> {
        let p = PLWRing.point(radius: r, angleDegrees: thetaDeg)
        return SIMD3<Float>(p.x, y, -p.y)
    }
    /// Yaw about Y that turns local -Z onto horizontal direction d (derived from -Z rotated by phi = (-sin phi, -cos phi)).
    static func yaw(facing d: SIMD3<Float>) -> Float { atan2(-d.x, -d.z) }
    static func rot(_ yaw: Float) -> simd_quatf { simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) }
    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3<Float>(Float((hex >> 16) & 255), Float((hex >> 8) & 255), Float(hex & 255)) / 255
    }
    /// Vividness is a saturation factor around the colour's own luma, never a multiply toward black (blueprint rule 5).
    static func saturate(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let l = c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722
        return simd_clamp(SIMD3<Float>(repeating: l) + (c - SIMD3<Float>(repeating: l)) * s, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }
    static func ui(_ c: SIMD3<Float>) -> UIColor { UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1) }
    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = simd_clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) }
    /// The tunnel wash (RING-DESIGN): source colour holds to 15 percent, eases to the destination by 85, holds.
    static func wash(_ t: Float) -> Float { smooth(0.15, 0.85, t) }
}

/// Triangles with per-vertex normals; each quad is wound to agree with its normals, so a profile mistake can never turn a face inside out.
struct PLWMeshBuilder {
    var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       normals n: [SIMD3<Float>], uvs t: [SIMD2<Float>]) {
        let base = UInt32(pos.count)
        pos += [a, b, c, d]; nor += n.map { simd_normalize($0) }; uv += t
        let g = simd_cross(b - a, c - a)
        let want = n[0] + n[1] + n[2] + n[3]
        if simd_dot(g, want) >= 0 { idx += [base, base + 1, base + 2, base, base + 2, base + 3] }
        else { idx += [base, base + 2, base + 1, base, base + 3, base + 2] }
    }

    func mesh(_ name: String) -> MeshResource? {
        guard !pos.isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nor)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    /// A profile (radius, height) swept round the origin from a0 to a1 degrees. The solid lies to the RIGHT of travel, so the visible face is on the LEFT:
    /// ground tops run outward in r, a ridge goes up its inner face, across the top, down its outer face. UVs are planar in world x/z over `metres` per repeat.
    static func revolve(_ profile: [SIMD2<Float>], from a0: Float, to a1: Float, stepDeg: Float = 1, metres: Float = 3) -> PLWMeshBuilder {
        var m = PLWMeshBuilder()
        guard a1 > a0, profile.count > 1 else { return m }
        let steps = max(1, Int(ceil((a1 - a0) / stepDeg)))
        for i in 0..<steps {
            let t0 = a0 + (a1 - a0) * Float(i) / Float(steps), t1 = a0 + (a1 - a0) * Float(i + 1) / Float(steps)
            for j in 0..<(profile.count - 1) {
                let p = profile[j], q = profile[j + 1]
                let n2 = SIMD2<Float>(-(q.y - p.y), q.x - p.x)
                func at(_ s: SIMD2<Float>, _ th: Float) -> SIMD3<Float> { PLWMath.world(s.x, th, y: s.y) }
                func nrm(_ th: Float) -> SIMD3<Float> { PLWMath.world(1, th) * n2.x + SIMD3<Float>(0, n2.y, 0) }   // radial unit * n2.x + up * n2.y
                let v = [at(p, t0), at(q, t0), at(q, t1), at(p, t1)]
                let ths = [t0, t0, t1, t1]
                m.quad(v[0], v[1], v[2], v[3], normals: ths.map { nrm($0) },
                       uvs: v.map { SIMD2<Float>($0.x, $0.z) / metres })
            }
        }
        return m
    }
}

/// One material book per lane-B scene: remembers each entity's colour so a saturation change re-tints them all.
@MainActor final class PLWTintBook {
    struct Item { let entity: ModelEntity; let rgb: SIMD3<Float>; let textured: Bool; let rough: Float; let metal: Float; let glow: Float; let opacity: Float; let fixed: Bool }
    private(set) var items: [Item] = []
    private(set) var saturation: Float = 1
    var tile: TextureResource?

    static let sampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat; d.tAddressMode = .repeat
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear; d.maxAnisotropy = 4
        return .init(d)
    }()

    /// His curve tile, 1024 px, black strokes on white: tinted, the white becomes the page colour and the strokes stay black.
    static func loadTile() async -> TextureResource? {
        guard let url = Bundle.main.url(forResource: "plw-hub-tile", withExtension: "png"),
              let cg = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        return try? await TextureResource(image: cg, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
    }

    func material(rgb: SIMD3<Float>, textured: Bool, rough: Float, metal: Float, glow: Float, opacity: Float, fixed: Bool) -> PhysicallyBasedMaterial {
        let c = PLWMath.ui(fixed ? rgb : PLWMath.saturate(rgb, saturation))
        var m = PhysicallyBasedMaterial()
        if textured, let tile { m.baseColor = .init(tint: c, texture: .init(tile, sampler: Self.sampler)) } else { m.baseColor = .init(tint: c) }
        m.roughness = .init(floatLiteral: rough); m.metallic = .init(floatLiteral: metal)
        if glow > 0 { m.emissiveColor = .init(color: c); m.emissiveIntensity = glow }
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }

    /// Makes a ModelEntity and files it in the book.
    func make(_ mesh: MeshResource, rgb: SIMD3<Float>, textured: Bool = false, rough: Float = 0.9, metal: Float = 0, glow: Float = 0,
              opacity: Float = 1, fixed: Bool = false, name: String = "") -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material(rgb: rgb, textured: textured, rough: rough, metal: metal, glow: glow, opacity: opacity, fixed: fixed)])
        e.name = name
        items.append(Item(entity: e, rgb: rgb, textured: textured, rough: rough, metal: metal, glow: glow, opacity: opacity, fixed: fixed))
        return e
    }

    func retint(_ s: Float) {
        guard abs(s - saturation) > 0.001 else { return }
        saturation = s
        for i in items where !i.fixed {
            i.entity.model?.materials = [material(rgb: i.rgb, textured: i.textured, rough: i.rough, metal: i.metal, glow: i.glow, opacity: i.opacity, fixed: false)]
        }
    }
}

enum PLWSolid {
    /// Static collision the integrator's character controller walks on (blueprint: every solid piece carries one inside the room root).
    static func make(_ e: Entity, shapes: [ShapeResource]) {
        guard !shapes.isEmpty else { return }
        e.components.set(CollisionComponent(shapes: shapes))
        e.components.set(PhysicsBodyComponent(shapes: shapes, mass: 1, mode: .static))
    }
    static func box(_ size: SIMD3<Float>, at p: SIMD3<Float> = .zero, roll: Float = 0) -> ShapeResource {
        ShapeResource.generateBox(size: size).offsetBy(rotation: simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1)), translation: p)
    }
    /// A triangle-mesh shape for a revolved piece; nil if RealityKit refuses it (the piece then renders but does not block: logged by the caller).
    static func mesh(_ m: MeshResource) async -> ShapeResource? { try? await ShapeResource.generateStaticMesh(from: m) }
}
