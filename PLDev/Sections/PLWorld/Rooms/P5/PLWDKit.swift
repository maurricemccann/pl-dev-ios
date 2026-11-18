import RealityKit
import UIKit
import Metal
import simd

// Lane D's shared kit (rooms 5 to 8). Copied patterns, no cross-lane imports: its own mesh builders, skins that re-saturate with the page look,
// a room base class that does the glyph keys, the moment and the look, so each room file only holds its own place and its one verb.

typealias V3 = SIMD3<Float>

/// A material recipe kept beside its entity so `apply(_ look:)` can rebuild it at the new saturation and exposure.
struct PLWDSkin {
    var hex: UInt32
    var rough: Float = 0.8
    var metal: Float = 0
    var glow: UInt32? = nil
    var glowK: Float = 0
    var tex: TextureResource? = nil
    var uv: SIMD2<Float> = [1, 1]
    var pageMix: Float = 0              // 0...1 toward the page hue
    var grey: Float = 0                 // 0...1 toward its own grey (colour that returns later)
    var twoSided = false
}

extension PLWDSkin { func twoSidedCopy() -> PLWDSkin { var s = self; s.twoSided = true; return s } }

@MainActor enum PLWD {
    static let sampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat; d.tAddressMode = .repeat
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear; d.maxAnisotropy = 8
        return .init(d)
    }()

    static func rgb(_ hex: UInt32) -> V3 { V3(Float((hex >> 16) & 0xff), Float((hex >> 8) & 0xff), Float(hex & 0xff)) / 255 }

    /// Saturation is a factor on the colour's own saturation, never a multiply toward black.
    static func color(_ c: V3, sat: Float) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(1, s * CGFloat(sat)), brightness: b, alpha: 1)
    }

    static func texture(_ name: String, _ folder: String) async -> TextureResource? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "PLWorld/\(folder)") else { return nil }
        guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        return await PLWLog.texture(image: cg, options: .init(semantic: .color))
    }

    /// A texture drawn in code (grass, plaster): the closure paints a size x size square, seeded so it is the same every run.
    static func drawn(_ size: Int, opaque: Bool = true, _ paint: (CGContext) -> Void) async -> TextureResource? {
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = opaque; return f }())
        let img = r.image { paint($0.cgContext) }
        guard let cg = img.cgImage else { return nil }
        return await PLWLog.texture(image: cg, options: .init(semantic: .color))
    }

    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

    // MARK: meshes

    static func mesh(_ pos: [V3], _ uv: [SIMD2<Float>], _ idx: [UInt32]) async -> MeshResource {
        var nor = [V3](repeating: .zero, count: pos.count)
        for i in stride(from: 0, to: idx.count, by: 3) {
            let a = Int(idx[i]), b = Int(idx[i + 1]), c = Int(idx[i + 2])
            let n = simd_cross(pos[b] - pos[a], pos[c] - pos[a])
            nor[a] += n; nor[b] += n; nor[c] += n
        }
        var d = MeshDescriptor(name: "plwd")
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nor.map { simd_length($0) > 1e-9 ? simd_normalize($0) : [0, 1, 0] })
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return (try? await MeshResource.generate(from: [d])) ?? .generateBox(size: 0.01)
    }

    /// A grid of rows (each row a list of points) skinned into one mesh. uv = metres along and across over `metresPerUV`.
    static func ribbon(_ rows: [[V3]], metresPerUV: Float = 3) async -> MeshResource {
        guard rows.count > 1, let cols = rows.first?.count, cols > 1 else { return .generateBox(size: 0.01) }
        var pos: [V3] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for (r, row) in rows.enumerated() {
            var run: Float = 0
            for (c, p) in row.enumerated() {
                if c > 0 { run += simd_distance(p, row[c - 1]) }
                pos.append(p); uv.append([run / metresPerUV, Float(r) / metresPerUV])
            }
        }
        for r in 0..<(rows.count - 1) { for c in 0..<(cols - 1) {
            let a = UInt32(r * cols + c), b = a + UInt32(cols)
            idx += [a, b, a + 1, a + 1, b, b + 1]
        } }
        return await mesh(pos, uv, idx)
    }

    /// A body of revolution round the y axis (trunks, columns).
    static func lathe(_ profile: [(r: Float, y: Float)], segments: Int = 40) async -> MeshResource {
        let rows = profile.map { p in (0...segments).map { i -> V3 in let a = Float(i) / Float(segments) * 2 * .pi; return [cos(a) * p.r, p.y, sin(a) * p.r] } }
        return await ribbon(rows, metresPerUV: 3)
    }

    /// A quad in the XY plane facing +Z, with a sub-rectangle of the picture (u0, v0, u1, v1 in 0...1, v down).
    static func quad(_ w: Float, _ h: Float, uv r: SIMD4<Float> = [0, 0, 1, 1]) async -> MeshResource {
        let x = w / 2, y = h / 2
        return await mesh([[-x, -y, 0], [x, -y, 0], [x, y, 0], [-x, y, 0]], [[r.x, r.w], [r.z, r.w], [r.z, r.y], [r.x, r.y]], [0, 1, 2, 0, 2, 3])
    }

    /// A flat wall with a hole: rays from a centre inside the hole meet the hole's outline and the wall's outline; the ribbon spans between them.
    static func holedWall(hole: [SIMD2<Float>], outer: [SIMD2<Float>], centre: SIMD2<Float>, at z: Float, origin: V3 = .zero, steps: Int = 96) async -> MeshResource {
        func hit(_ d: SIMD2<Float>, _ loop: [SIMD2<Float>]) -> Float {
            var best: Float = 1e9
            for i in 0..<loop.count {
                let a = loop[i], b = loop[(i + 1) % loop.count], e = b - a
                let den = d.x * e.y - d.y * e.x
                if abs(den) < 1e-9 { continue }
                let t = ((a.x - centre.x) * e.y - (a.y - centre.y) * e.x) / den
                let u = ((a.x - centre.x) * d.y - (a.y - centre.y) * d.x) / den
                if t > 1e-6, u >= -1e-6, u <= 1 + 1e-6, t < best { best = t }
            }
            return best
        }
        var inner: [V3] = [], out: [V3] = []
        for i in 0...steps {
            let a = Float(i) / Float(steps) * 2 * .pi, d = SIMD2<Float>(cos(a), sin(a)), th = hit(d, hole), to = hit(d, outer), k = min(th, to)
            guard k < 1e8, to < 1e8 else { continue }
            inner.append(origin + [centre.x + d.x * k, centre.y + d.y * k, z]); out.append(origin + [centre.x + d.x * to, centre.y + d.y * to, z])
        }
        return await ribbon([inner, out], metresPerUV: 2.5)
    }

    /// An arch outline: straight jambs from y0, a round head from y0 + straight up.
    static func arch(halfWidth hw: Float, base y0: Float, spring ys: Float, rise: Float, n: Int = 24) -> [SIMD2<Float>] {
        var p: [SIMD2<Float>] = [[hw, y0]]
        for i in 0...n { let a = Float(i) / Float(n) * .pi; p.append([cos(a) * hw, ys + sin(a) * rise]) }
        p.append([-hw, y0]); return p
    }

    /// Catmull-Rom through the points, `per` samples per span.
    static func spline(_ p: [V3], per: Int = 8) -> [V3] {
        guard p.count > 2 else { return p }
        var out: [V3] = []
        for i in 0..<(p.count - 1) {
            let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
            for k in 0..<per {
                let t = Float(k) / Float(per), t2 = t * t, t3 = t2 * t
                out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
            }
        }
        out.append(p[p.count - 1]); return out
    }

    /// A swelling tube along a path, radius as a function of 0...1 along it.
    static func tube(_ path: [V3], radius: (Float) -> Float, sides: Int = 12) async -> MeshResource {
        var rows: [[V3]] = []
        for (i, c) in path.enumerated() {
            let t = simd_normalize(path[min(path.count - 1, i + 1)] - path[max(0, i - 1)])
            let up: V3 = abs(t.y) > 0.9 ? [1, 0, 0] : [0, 1, 0]
            let n = simd_normalize(simd_cross(t, up)), b = simd_cross(t, n), r = radius(Float(i) / Float(path.count - 1))
            rows.append((0...sides).map { k in let a = Float(k) / Float(sides) * 2 * .pi; return c + n * (cos(a) * r) + b * (sin(a) * r) })
        }
        return await ribbon(rows, metresPerUV: 3)
    }

    static func shape(_ m: MeshResource) async -> ShapeResource? { await PLWLog.staticMesh(from: m) }
}

// MARK: - the room base

@MainActor class PLWDRoom: PLWRoom {
    let id: PLWArea
    let root = Entity()
    var ports: [String: Transform] = [:]
    var route: [V3] = []
    var triggers: [PLWTrigger] = []
    var glyphs: [PLWGlyphPlacement] = []
    var save = PLWSave()
    var lookNow = PLWLook(pageRGB: [0.5, 0.5, 0.5], fogRGB: [0.5, 0.5, 0.5], saturation: 0.7, exposure: 1)
    var clock: Float = 0
    var momentDone = false
    private var skins: [(ModelEntity, PLWDSkin)] = []
    private var lights: [(Entity, Float)] = []
    private var drive: [ObjectIdentifier: Float] = [:]      // a room-driven light's fraction (0 = off), kept across `apply`
    private var keyVisuals: [PLWKey: Entity] = [:]
    private var fetched = false

    init(_ id: PLWArea) { self.id = id }

    // overridden per room
    func build() async {}
    func tick(_ f: PLWFrame) -> [PLWCommand] { [] }
    func trigger(_ e: PLWTriggerEvent) -> [PLWCommand] { [] }

    func load() async throws {
        guard !fetched else { return }
        fetched = true
        await build()
        await place()
        apply(lookNow)
    }
    /// Seats the glyph keys the room listed: his Glyph Field glyph as a turning picture when its art is bundled, else a gold gem.
    private func place() async {
        let aspect: [PLWGlyph: Float] = [.glyphGuy: 0.4, .loveYourself: 0.93, .money: 0.76, .smiley: 0.81, .povertyToLuxury: 1.58, .moneyGrin: 0.71]
        for g in glyphs {
            let holder = Entity(); holder.position = g.position; root.addChild(holder)
            if let t = await PLWD.texture("plw-key-\(g.glyph.rawValue)", "P5") {
                let h: Float = 0.8, e = ModelEntity(mesh: await PLWD.quad(h * (aspect[g.glyph] ?? 0.8), h), materials: [])
                holder.addChild(e); setPicture(e, t, tint: .white, opacity: 1)
            } else {
                let gem = ModelEntity(mesh: .generateBox(size: [0.22, 0.34, 0.06], cornerRadius: 0.03), materials: [])
                gem.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1]); holder.addChild(gem)
                skins.append((gem, PLWDSkin(hex: 0xFFD25A, rough: 0.25, metal: 0.6, glow: 0xFFC83D, glowK: 0.9)))
            }
            let l = Entity(); var pl = PointLightComponent(); pl.intensity = 9_000; pl.color = .world(0xFFD25A); pl.attenuationRadius = 3; l.components.set(pl); holder.addChild(l)
            lights.append((l, 9_000)); keyVisuals[g.key] = holder
        }
    }

    func restore(_ save: PLWSave) { self.save = save; momentDone = save.completed.contains(id) }
    func receive(_ event: PLWTriggerEvent) -> [PLWCommand] { trigger(event) }
    func unload() { root.children.removeAll(); skins.removeAll(); lights.removeAll(); drive.removeAll(); keyVisuals.removeAll(); fetched = false; clock = 0 }

    func step(_ f: PLWFrame) -> [PLWCommand] {
        clock += f.dt; save = f.save
        var out: [PLWCommand] = []
        for g in glyphs {
            guard let v = keyVisuals[g.key] else { continue }
            let have = f.save.glyphs.contains(g.key)
            v.isEnabled = !have
            if have { continue }
            v.orientation = simd_quatf(angle: clock * 1.4, axis: [0, 1, 0])
            v.position.y = g.position.y + 0.06 * sin(clock * 2)
            if f.actPressed, simd_distance(f.position, g.position) < 1.8 { out.append(.collect(g.key)); v.isEnabled = false }
        }
        return out + tick(f)
    }

    /// The room's one moment, once: records it and keeps the rest of the room playable.
    func finish() -> [PLWCommand] {
        guard !momentDone else { return [] }
        momentDone = true
        return [.completeMoment(id)]
    }

    func apply(_ look: PLWLook) {
        lookNow = look
        for (e, s) in skins { e.model?.materials = [material(s)] }
        for (e, k) in lights { setLight(e, k * (drive[ObjectIdentifier(e)] ?? 1) * look.exposure) }
    }

    // MARK: builders for the rooms

    /// Adds an entity with a skin (re-skinned by `apply`) and, if given, a static collider.
    @discardableResult
    func add(_ mesh: MeshResource, _ skin: PLWDSkin, at p: V3 = .zero, yaw: Float = 0, shape: ShapeResource? = nil, to parent: Entity? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [])
        e.position = p; e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if let s = shape {
            e.components.set(CollisionComponent(shapes: [s], isStatic: true))
            e.components.set(PhysicsBodyComponent(shapes: [s], mass: 1, mode: .static))
        }
        (parent ?? root).addChild(e)
        skins.append((e, skin)); e.model?.materials = [material(skin)]
        return e
    }

    /// A solid box (collides) with a skin.
    @discardableResult
    func box(_ size: V3, _ skin: PLWDSkin, at p: V3, yaw: Float = 0, solid: Bool = true, round: Float = 0.02, to parent: Entity? = nil) -> ModelEntity {
        add(.generateBox(size: size, cornerRadius: round), skin, at: p, yaw: yaw, shape: solid ? .generateBox(size: size) : nil, to: parent)
    }

    func reskinAll(_ es: [ModelEntity], _ s: PLWDSkin) { for e in es { reskin(e, s) } }

    /// Swaps an entity's skin (and what `apply` will rebuild it from).
    func reskin(_ e: ModelEntity, _ s: PLWDSkin) {
        if let i = skins.firstIndex(where: { $0.0 === e }) { skins[i].1 = s } else { skins.append((e, s)) }
        e.model?.materials = [material(s)]
    }

    /// A lit mesh that collides as its own shape (walls, hills, cliffs).
    @discardableResult
    func solidMesh(_ mesh: MeshResource, _ skin: PLWDSkin, at p: V3 = .zero) async -> ModelEntity {
        add(mesh, skin, at: p, shape: await PLWD.shape(mesh))
    }

    /// A self-lit picture (his drawings): an unlit plane with the texture's own alpha. Opacity can be driven by `setOpacity`.
    func picture(_ tex: TextureResource?, _ mesh: MeshResource, tint: UIColor = .white, at p: V3, yaw: Float = 0) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [])
        e.position = p; e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(e); setPicture(e, tex, tint: tint, opacity: 1)
        return e
    }
    func setPicture(_ e: ModelEntity, _ tex: TextureResource?, tint: UIColor, opacity: Float) {
        var m = UnlitMaterial()
        if let tex { m.color = .init(tint: tint, texture: .init(tex, sampler: PLWD.sampler)) } else { m.color = .init(tint: tint) }
        m.blending = .transparent(opacity: .init(scale: opacity, texture: tex.map { MaterialParameters.Texture($0) }))
        m.faceCulling = .none
        e.model?.materials = [m]
    }

    /// A light that follows the exposure. Returns the entity so a room can drive its own intensity.
    @discardableResult
    func point(_ intensity: Float, radius: Float, at p: V3, color: UInt32, to parent: Entity? = nil) -> Entity {
        let e = WorldLight.point(intensity, radius: radius, at: p, color: .world(color))
        (parent ?? root).addChild(e); lights.append((e, intensity)); return e
    }
    @discardableResult
    func sun(_ intensity: Float, from p: V3, toward t: V3 = .zero, color: UInt32) -> Entity {
        let e = WorldLight.directional(intensity, from: p, look: t, color: .world(color))
        root.addChild(e); lights.append((e, intensity)); return e
    }
    @discardableResult
    func spot(_ intensity: Float, radius: Float, from p: V3, toward t: V3, color: UInt32) -> Entity {
        let e = WorldLight.spot(intensity, radius: radius, from: p, look: t, color: .world(color))
        root.addChild(e); lights.append((e, intensity)); return e
    }
    /// Drives a room light as a fraction (0...) of the intensity it was made with, still scaled by the exposure.
    func level(_ e: Entity, _ k: Float) { drive[ObjectIdentifier(e)] = k; if let b = lights.first(where: { $0.0 === e })?.1 { setLight(e, b * k * lookNow.exposure) } }
    func setLight(_ e: Entity, _ intensity: Float) {
        if var l = e.components[PointLightComponent.self] { l.intensity = intensity; e.components.set(l) }
        else if var l = e.components[DirectionalLightComponent.self] { l.intensity = intensity; e.components.set(l) }
        else if var l = e.components[SpotLightComponent.self] { l.intensity = intensity; e.components.set(l) }
    }

    func material(_ s: PLWDSkin) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let base = PLWD.rgb(s.hex), mixed = base + (lookNow.pageRGB - base) * s.pageMix
        let lum = simd_dot(mixed, V3(0.3, 0.59, 0.11)), c = PLWD.color(mixed + (V3(repeating: lum) - mixed) * s.grey, sat: lookNow.saturation)
        if let t = s.tex { m.baseColor = .init(tint: c, texture: .init(t, sampler: PLWD.sampler)) } else { m.baseColor = .init(tint: c) }
        m.roughness = .init(floatLiteral: s.rough); m.metallic = .init(floatLiteral: s.metal)
        if let g = s.glow { m.emissiveColor = .init(color: PLWD.color(PLWD.rgb(g), sat: lookNow.saturation)); m.emissiveIntensity = s.glowK * lookNow.exposure }
        if s.uv != [1, 1] { m.textureCoordinateTransform = .init(offset: .zero, scale: s.uv, rotation: 0) }
        if s.twoSided { m.faceCulling = .none }
        return m
    }

    /// A glyph key slot: listed for the integrator, shown by the base, collected by ACT.
    func key(_ slot: UInt8, _ glyph: PLWGlyph, at p: V3) { glyphs.append(PLWGlyphPlacement(key: PLWKey(page: id, slot: slot), glyph: glyph, position: p)) }

    func port(_ name: String, at p: V3, yaw: Float = 0) { ports[name] = Transform(rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: p) }

    /// A flat disc of the room's tiled floor and an optional second skin for the ground round it.
    func tileSkin(_ hex: UInt32, tex: TextureResource?, repeatEvery m: Float, area: SIMD2<Float>, rough: Float = 0.55) -> PLWDSkin {
        PLWDSkin(hex: hex, rough: rough, tex: tex, uv: [area.x / m, area.y / m])
    }

    /// Distance on the ground plane.
    func flat(_ a: V3, _ b: V3) -> Float { simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z)) }
}
