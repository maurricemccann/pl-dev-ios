import Foundation
import RealityKit
import UIKit
import simd

// Lane E's shared helpers for rooms 9 to 11 (own copy: no cross-lane imports). Meshes are built in code with MeshDescriptor, materials are PhysicallyBasedMaterial,
// collision is a static mesh shape. Metres, Y up, local -Z forward. Nothing here has run on a device: see LANES-plw-e.md for what is unproven.

typealias PLWEV3 = SIMD3<Float>

/// How one surface is painted. `page` colours follow the look's page hue; fixed colours do not. Saturation always follows the look.
struct PLWEMat {
    var rgb: PLWEV3 = [0.7, 0.7, 0.7]
    var page: (lift: Float, dim: Float)? = nil          // mix(pageRGB, white, lift) * dim, replaces rgb
    var rough: Float = 0.7
    var metal: Float = 0
    var emissive: PLWEV3? = nil
    var emissiveI: Float = 1
    var alpha: Float = 1
    var curve: (line: PLWEV3, ground: PLWEV3)? = nil     // his curve tile recoloured; replaces the tint
    var curveRepeat: Float = 1
    var twoSided = false

    init(_ hex: UInt32, rough: Float = 0.7, metal: Float = 0) { rgb = PLWEKit.rgb(hex); self.rough = rough; self.metal = metal }
    init(page lift: Float, dim: Float = 1, rough: Float = 0.7, metal: Float = 0) { page = (lift, dim); self.rough = rough; self.metal = metal }
}

struct PLWEPaint { let entity: ModelEntity; var mat: PLWEMat }

@MainActor enum PLWEKit {
    // MARK: colour
    nonisolated static func rgb(_ h: UInt32) -> PLWEV3 { PLWEV3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255 }
    nonisolated static func mix(_ a: PLWEV3, _ b: PLWEV3, _ t: Float) -> PLWEV3 { a + (b - a) * t }
    /// Vividness is a saturation factor, never a multiply toward black.
    nonisolated static func saturate(_ c: PLWEV3, _ s: Float) -> PLWEV3 {
        let l = simd_dot(c, PLWEV3(0.2126, 0.7152, 0.0722))
        return simd_clamp(PLWEV3(repeating: l) + (c - PLWEV3(repeating: l)) * s, PLWEV3(repeating: 0), PLWEV3(repeating: 1))
    }
    nonisolated static func ui(_ c: PLWEV3, alpha: CGFloat = 1) -> UIColor { UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: alpha) }
    nonisolated static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = simd_clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) }
    /// Small deterministic noise so cliffs and ground are not clean maths (a seeded LCG, same on every device).
    struct LCG { var s: UInt64; init(_ seed: UInt64) { s = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 33) & 0xFFFFFF) / Float(0xFFFFFF) } }

    // MARK: textures (his curve tile, recoloured on the CPU once per saturation step; 512 px, the file is 1024)
    static func tileImage(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = UIImage(contentsOfFile: url.path) else { return nil }
        return img.cgImage
    }
    /// Black strokes of the tile painted `line`, the white ground painted `ground`. Built with a gray mask, so no pixel loop.
    static func curveTexture(tile: String, line: PLWEV3, ground: PLWEV3) async -> TextureResource? {
        guard let src = tileImage(tile) else { return nil }
        let n = 512, rect = CGRect(x: 0, y: 0, width: n, height: n)
        guard let grayCtx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        grayCtx.draw(src, in: rect)
        guard let gray = grayCtx.makeImage() else { return nil }
        let space = CGColorSpaceCreateDeviceRGB(), info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let lineCtx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        lineCtx.setFillColor(ui(line).cgColor); lineCtx.fill(rect)
        guard let solid = lineCtx.makeImage(), let strokes = solid.masking(gray), let out = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        out.setFillColor(ui(ground).cgColor); out.fill(rect)
        out.draw(strokes, in: rect)
        guard let done = out.makeImage() else { return nil }
        return try? await TextureResource(image: done, options: .init(semantic: .color))
    }
    /// His glyph silhouette (`plwe-glyph-<name>.png`) recoloured gold, alpha kept.
    static func glyphArt(_ name: String) async -> (tex: TextureResource, aspect: Float)? {
        guard let src = tileImage("plwe-glyph-" + name) else { return nil }
        let w = src.width, h = src.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(src, in: r); ctx.setBlendMode(.sourceIn); ctx.setFillColor(ui(rgb(0xFFC83A)).cgColor); ctx.fill(r)
        guard let img = ctx.makeImage(), let tex = try? await TextureResource(image: img, options: .init(semantic: .color)) else { return nil }
        return (tex, Float(w) / Float(h))
    }
    static func plainTexture(_ name: String) async -> TextureResource? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return try? await TextureResource(contentsOf: url, options: .init(semantic: .color))
    }

    // MARK: materials and lights
    static func material(_ m: PLWEMat, look: PLWLook, tex: TextureResource?) -> PhysicallyBasedMaterial {
        var p = PhysicallyBasedMaterial()
        let base = m.page.map { mix(look.pageRGB, PLWEV3(repeating: 1), $0.lift) * $0.dim } ?? m.rgb
        if let tex { p.baseColor = .init(tint: .white, texture: .init(tex)) } else { p.baseColor = .init(tint: ui(saturate(base, look.saturation))) }
        p.roughness = .init(floatLiteral: m.rough); p.metallic = .init(floatLiteral: m.metal)
        if let e = m.emissive { p.emissiveColor = .init(color: ui(saturate(e, look.saturation))); p.emissiveIntensity = m.emissiveI }
        if m.alpha < 1 { p.blending = .transparent(opacity: .init(floatLiteral: m.alpha)) }
        if m.twoSided { p.faceCulling = .none }
        return p
    }
    /// A sun shining along `dir` (RealityKit lights shine down their own -Z).
    static func sun(color: PLWEV3, lux: Float, dir: PLWEV3, shadowM: Float = 60) -> Entity {
        let e = Entity()
        e.components.set(DirectionalLightComponent(color: ui(color), intensity: lux))
        e.components.set(DirectionalLightComponent.Shadow(maximumDistance: shadowM, depthBias: 2))
        e.orientation = simd_quatf(from: [0, 0, -1], to: simd_normalize(dir))
        return e
    }
    static func point(color: PLWEV3, lumens: Float, radius: Float, at p: PLWEV3) -> Entity {
        let e = Entity(); e.position = p
        e.components.set(PointLightComponent(color: ui(color), intensity: lumens, attenuationRadius: radius))
        return e
    }

    // MARK: meshes
    /// A rows x cols grid of points. `flip` reverses the facing. `double` also draws the back (for thin shells). `closed` averages the seam normals.
    static func grid(_ g: [[PLWEV3]], flip: Bool = false, double: Bool = false, closed: Bool = false, uv: (PLWEV3, Int, Int) -> SIMD2<Float>) -> MeshResource? {
        guard g.count > 1, let cols = g.first?.count, cols > 1, g.allSatisfy({ $0.count == cols }) else { return nil }
        let rows = g.count
        var pos: [PLWEV3] = [], uvs: [SIMD2<Float>] = [], idx: [UInt32] = []
        pos.reserveCapacity(rows * cols); uvs.reserveCapacity(rows * cols)
        for r in 0..<rows { for c in 0..<cols { pos.append(g[r][c]); uvs.append(uv(g[r][c], r, c)) } }
        var nrm = [PLWEV3](repeating: .zero, count: pos.count)
        for r in 0..<(rows - 1) { for c in 0..<(cols - 1) {
            let a = UInt32(r * cols + c), b = a + 1, d = UInt32((r + 1) * cols + c), e = d + 1
            let tris: [UInt32] = flip ? [a, d, b, b, d, e] : [a, b, d, b, e, d]
            idx += tris
            for t in stride(from: 0, to: 6, by: 3) {
                let i0 = Int(tris[t]), i1 = Int(tris[t + 1]), i2 = Int(tris[t + 2])
                let n = simd_cross(pos[i1] - pos[i0], pos[i2] - pos[i0])
                nrm[i0] += n; nrm[i1] += n; nrm[i2] += n
            }
        } }
        if closed { for r in 0..<rows { let s = nrm[r * cols] + nrm[r * cols + cols - 1]; nrm[r * cols] = s; nrm[r * cols + cols - 1] = s } }
        nrm = nrm.map { simd_length($0) > 1e-12 ? simd_normalize($0) : PLWEV3(0, 1, 0) }
        if double {
            let base = UInt32(pos.count)
            pos += pos; uvs += uvs; nrm += nrm.map { -$0 }
            var back = [UInt32](); back.reserveCapacity(idx.count)
            for t in stride(from: 0, to: idx.count, by: 3) { back += [idx[t] + base, idx[t + 2] + base, idx[t + 1] + base] }
            idx += back
        }
        var d = MeshDescriptor(name: "plwe")
        d.positions = MeshBuffers.Positions(pos); d.normals = MeshBuffers.Normals(nrm); d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    /// A round disc or dome: `height(x, z)` gives the surface, rings from the centre out. Faces up.
    static func polar(radius: Float, rings: Int, segs: Int, centre: PLWEV3 = .zero, uvScale: Float = 0.15, height: (Float, Float) -> Float) -> MeshResource? {
        var g = [[PLWEV3]]()
        for i in 0...rings { let r = radius * Float(i) / Float(rings); var row = [PLWEV3]()
            for k in 0...segs { let a = Float(k) / Float(segs) * 2 * .pi; let x = r * cos(a), z = r * sin(a); row.append(centre + PLWEV3(x, height(x, z), z)) }
            g.append(row) }
        return grid(g, closed: true) { p, _, _ in SIMD2(p.x - centre.x, p.z - centre.z) * uvScale }
    }
    /// A rectangle of ground (x from -w/2 to w/2, z from -d/2 to d/2) with a height function. Faces up.
    static func terrain(w: Float, d: Float, nx: Int, nz: Int, centre: PLWEV3 = .zero, uvScale: Float = 0.15, height: (Float, Float) -> Float) -> MeshResource? {
        var g = [[PLWEV3]]()
        for j in 0...nz { let z = -d / 2 + d * Float(j) / Float(nz); var row = [PLWEV3]()
            for i in 0...nx { let x = -w / 2 + w * Float(i) / Float(nx); row.append(centre + PLWEV3(x, height(x, z), z)) }
            g.append(row) }
        return grid(g, flip: true) { p, _, _ in SIMD2(p.x - centre.x, p.z - centre.z) * uvScale }
    }
    /// Solid of revolution round the Y axis. `profile` runs from the centre outward (r, y). Faces outward and up.
    static func lathe(_ profile: [(r: Float, y: Float)], segs: Int, centre: PLWEV3, uvScale: Float) -> MeshResource? {
        let g: [[PLWEV3]] = profile.map { p in (0...segs).map { k in let a = Float(k) / Float(segs) * 2 * .pi; return centre + PLWEV3(p.r * cos(a), p.y, p.r * sin(a)) } }
        return grid(g, closed: true) { p, _, _ in SIMD2(p.x - centre.x, p.z - centre.z) * uvScale }
    }
    /// A tube along a path with a radius per point (0...1 along). Parallel-transport frames, no end caps (ends are buried or closed loops).
    static func tube(_ path: [PLWEV3], sides: Int = 18, uvAlong: Float = 0.5, radius: (Float) -> Float) -> MeshResource? {
        guard path.count > 1 else { return nil }
        var tangents = [PLWEV3]()
        for i in 0..<path.count { let a = path[max(i - 1, 0)], b = path[min(i + 1, path.count - 1)]; tangents.append(simd_normalize(b - a)) }
        var n = simd_cross(tangents[0], abs(tangents[0].y) < 0.9 ? PLWEV3(0, 1, 0) : PLWEV3(1, 0, 0)); n = simd_normalize(n)
        var rows = [[PLWEV3]]()
        for i in 0..<path.count {
            let t = tangents[i]
            n = n - simd_dot(n, t) * t
            n = simd_length(n) < 1e-4 ? simd_normalize(simd_cross(t, PLWEV3(1, 0, 0))) : simd_normalize(n)
            let b = simd_cross(t, n), r = radius(Float(i) / Float(path.count - 1))
            rows.append((0...sides).map { k in let a = Float(k) / Float(sides) * 2 * .pi; return path[i] + (n * cos(a) + b * sin(a)) * r })
        }
        var lens = [Float](), acc: Float = 0
        for i in 0..<path.count { if i > 0 { acc += simd_length(path[i] - path[i - 1]) }; lens.append(acc) }
        return grid(rows, closed: true) { _, r, c in SIMD2(Float(c) / Float(sides) * 2, lens[r] * uvAlong) }
    }
    /// Catmull-Rom through control points (a smooth curve for the beings and ribbons).
    static func spline(_ pts: [PLWEV3], per: Int = 12) -> [PLWEV3] {
        guard pts.count > 3 else { return pts }
        var out = [PLWEV3]()
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            for s in 0..<per { let t = Float(s) / Float(per), t2 = t * t, t3 = t2 * t
                out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)) }
        }
        out.append(pts[pts.count - 1]); return out
    }
    /// An arched doorway: the wall piece between a half-ellipse mouth (halfW x height) and a rectangular outline. `at` is the sill centre, `right` the along-wall unit.
    static func doorWall(at c: PLWEV3, right R: PLWEV3, mouthHalfW: Float, mouthH: Float, wallHalfW: Float, wallTop: Float) -> MeshResource? {
        var arc = [PLWEV3](), rim = [PLWEV3](); let n = 36
        for i in 0...n { let th = Float(i) / Float(n) * .pi, dx = cos(th), dy = sin(th)
            arc.append(c + R * (dx * mouthHalfW) + PLWEV3(0, dy * mouthH, 0))
            let k = min(abs(dx) < 1e-6 ? 1e9 : wallHalfW / abs(dx), dy < 1e-6 ? 1e9 : wallTop / dy)
            rim.append(c + R * (dx * k) + PLWEV3(0, min(wallTop, dy * k), 0)) }
        return grid([arc, rim], double: true) { p, _, _ in SIMD2(p.x + p.z, p.y) * 0.3 }
    }

    /// Many ellipsoids merged into one mesh (shrubs, tree crowns, stones): one draw call. Each is (centre, radiusXZ, radiusY).
    static func blobs(_ list: [(c: PLWEV3, rx: Float, ry: Float)], lon: Int = 9, lat: Int = 6, uvScale: Float = 0.3) -> MeshResource? {
        var pos = [PLWEV3](), nrm = [PLWEV3](), uv = [SIMD2<Float>](), idx = [UInt32]()
        for b in list {
            let base = UInt32(pos.count)
            for j in 0...lat { let v = Float(j) / Float(lat), phi = v * .pi
                for i in 0...lon { let th = Float(i) / Float(lon) * 2 * .pi
                    let d = PLWEV3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
                    pos.append(b.c + PLWEV3(d.x * b.rx, d.y * b.ry, d.z * b.rx))
                    nrm.append(simd_normalize(PLWEV3(d.x / b.rx, d.y / b.ry, d.z / b.rx))); uv.append(SIMD2(Float(i) / Float(lon), v) * uvScale * 4) } }
            let w = UInt32(lon + 1)
            for j in 0..<lat { for i in 0..<lon { let a = base + UInt32(j) * w + UInt32(i), b2 = a + 1, c = a + w, d = c + 1; idx += [a, b2, c, b2, d, c] } }
        }
        var d = MeshDescriptor(name: "blobs")
        d.positions = MeshBuffers.Positions(pos); d.normals = MeshBuffers.Normals(nrm); d.textureCoordinates = MeshBuffers.TextureCoordinates(uv); d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    /// Runs of angles round a full circle with the door gaps left out (each run becomes one wall mesh).
    static func angleRuns(doors: [Float], doorHalf: Float, n: Int) -> [[Float]] {
        var runs = [[Float]](), cur = [Float]()
        for i in 0...n { let a = Float(i) / Float(n) * 2 * .pi
            if doors.contains(where: { abs(atan2(sin(a - $0), cos(a - $0))) < doorHalf }) { if !cur.isEmpty { runs.append(cur); cur = [] } } else { cur.append(a) } }
        if !cur.isEmpty { runs.append(cur) }
        return runs.filter { $0.count > 1 }
    }

    /// The same, with a different gap half-angle per door.
    static func angleRuns(doors: [(a: Float, half: Float)], n: Int) -> [[Float]] {
        var runs = [[Float]](), cur = [Float]()
        for i in 0...n { let a = Float(i) / Float(n) * 2 * .pi
            if doors.contains(where: { abs(atan2(sin(a - $0.a), cos(a - $0.a))) < $0.half }) { if !cur.isEmpty { runs.append(cur); cur = [] } } else { cur.append(a) } }
        if !cur.isEmpty { runs.append(cur) }
        return runs.filter { $0.count > 1 }
    }
    /// Half-ellipse arch points (mouth) round `c`, `right` along the wall.
    static func arch(at c: PLWEV3, right R: PLWEV3, halfW: Float, h: Float, n: Int = 36) -> [PLWEV3] {
        (0...n).map { i in let th = Float(i) / Float(n) * .pi; return c + R * (cos(th) * halfW) + PLWEV3(0, sin(th) * h, 0) }
    }

    // MARK: collision
    /// Static collision for a solid piece (a static mesh shape needs the static physics body mode as well).
    static func solid(_ e: ModelEntity) async {
        guard let mesh = e.model?.mesh, let shape = try? await ShapeResource.generateStaticMesh(from: mesh) else { return }
        e.components.set(CollisionComponent(shapes: [shape]))
        e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
    }
    static func solidBox(_ e: Entity, size: PLWEV3, at offset: PLWEV3 = .zero) {
        e.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: offset)]))
        e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
    }
}

/// The part of a room every page shares: the look, the glyph keys, restore, unload. A room subclasses this and fills `root`, `ports`, `route`, `triggers`, `glyphs` in `build()`.
@MainActor class PLWEBaseRoom: PLWRoom {
    let id: PLWArea
    let root = Entity()
    var ports: [String: Transform] = [:]
    var route: [SIMD3<Float>] = []
    var triggers: [PLWTrigger] = []
    var glyphs: [PLWGlyphPlacement] = []
    var look: PLWLook
    var save = PLWSave()
    var paints: [PLWEPaint] = []
    var curveTex: [Int: TextureResource] = [:]        // by paint index, rebuilt when the saturation moves
    var bakedSat: Float
    var lights: [(entity: Entity, base: Float)] = []
    var glyphNodes: [PLWKey: Entity] = [:]
    var collected: Set<PLWKey> = []
    var spin: Float = 0
    let tile = "plwe-curve-tile"

    init(area: PLWArea, defaultSaturation: Float) {
        id = area
        let hex = PLWRing.pageHex[(area.page ?? 1) - 1], c = PLWEKit.rgb(hex)
        look = PLWLook(pageRGB: c, fogRGB: c, saturation: defaultSaturation, exposure: 1)
        bakedSat = defaultSaturation
        root.name = "plw-p\(area.page ?? 0)"
    }

    // MARK: building
    /// Make a model, paint it, add it, and (if `solid`) give it static collision.
    @discardableResult func piece(_ mesh: MeshResource?, _ mat: PLWEMat, name: String, to parent: Entity? = nil, solid: Bool = false, at p: PLWEV3 = .zero) async -> ModelEntity? {
        guard let mesh else { return nil }
        var tex: TextureResource? = nil
        if let c = mat.curve { tex = await PLWEKit.curveTexture(tile: tile, line: PLWEKit.saturate(c.line, look.saturation), ground: PLWEKit.saturate(c.ground, look.saturation)) }
        let e = ModelEntity(mesh: mesh, materials: [PLWEKit.material(mat, look: look, tex: tex)])
        e.name = name; e.position = p
        (parent ?? root).addChild(e)
        if solid { await PLWEKit.solid(e) }
        paints.append(PLWEPaint(entity: e, mat: mat))
        if let tex { curveTex[paints.count - 1] = tex }
        return e
    }
    func light(_ e: Entity, base: Float) { root.addChild(e); lights.append((e, base)) }

    /// A turning gold token for one glyph key. (Stand-in form until his Glyph Field art is wired: see LANES-plw-e.md.)
    func addGlyphs(_ list: [PLWGlyphPlacement]) async {
        glyphs = list
        let coin = try? MeshResource.generate(from: [PLWEKit.glyphTokenDescriptor()])
        var goldCoin = PLWEMat(0xE8B21A, rough: 0.28, metal: 0.9); goldCoin.emissive = PLWEKit.rgb(0xFFC83A); goldCoin.emissiveI = 0.35
        for g in list {
            let e: ModelEntity
            if let art = await PLWEKit.glyphArt(g.glyph.rawValue) {   // his own silhouette, in gold, turning (never redrawn)
                var m = PLWEKit.material({ var q = PLWEMat(0xFFFFFF, rough: 0.4); q.emissive = PLWEKit.rgb(0xFFC83A); q.emissiveI = 0.5; q.twoSided = true; return q }(), look: look, tex: art.tex)
                m.blending = .transparent(opacity: .init(floatLiteral: 1.0))
                e = ModelEntity(mesh: .generatePlane(width: 0.75 * art.aspect, height: 0.75), materials: [m])
            } else {   // no art for this glyph in the repo yet: a gold coin until it arrives
                e = ModelEntity(mesh: coin ?? .generateSphere(radius: 0.3), materials: [PLWEKit.material(goldCoin, look: look, tex: nil)])
            }
            e.name = "glyph-\(g.glyph.rawValue)-\(g.key.slot)"; e.position = g.position
            root.addChild(e); glyphNodes[g.key] = e
        }
    }

    // MARK: PLWRoom
    func load() async throws {}
    func restore(_ s: PLWSave) {
        save = s; collected = s.glyphs.filter { $0.page == id }
        for k in collected { glyphNodes[k]?.isEnabled = false }
        restoreRoom(s)
    }
    func restoreRoom(_ s: PLWSave) {}
    func step(_ f: PLWFrame) -> [PLWCommand] {
        spin += f.dt
        var out = [PLWCommand]()
        for g in glyphs where !collected.contains(g.key) {
            guard let n = glyphNodes[g.key] else { continue }
            n.orientation = simd_quatf(angle: spin * 1.1, axis: [0, 1, 0]); n.position.y = g.position.y + 0.06 * sin(spin * 1.6 + Float(g.key.slot))
            if f.actPressed && simd_distance(f.position + [0, 0.9, 0], g.position) < 2.1 { collected.insert(g.key); n.isEnabled = false; out.append(.collect(g.key)) }
        }
        return out + stepRoom(f)
    }
    func stepRoom(_ f: PLWFrame) -> [PLWCommand] { [] }
    func receive(_ e: PLWTriggerEvent) -> [PLWCommand] { [] }
    func apply(_ l: PLWLook) {
        look = l
        for (e, base) in lights {
            if var d = e.components[DirectionalLightComponent.self] { d.intensity = base * l.exposure; e.components.set(d) }
            if var p = e.components[PointLightComponent.self] { p.intensity = base * l.exposure; e.components.set(p) }
        }
        let rebake = abs(l.saturation - bakedSat) > 0.02
        if rebake { bakedSat = l.saturation }
        for (i, p) in paints.enumerated() where p.mat.curve == nil || !rebake {
            p.entity.model?.materials = [PLWEKit.material(p.mat, look: l, tex: curveTex[i])]
        }
        if rebake { Task { @MainActor in
            for (i, p) in paints.enumerated() { guard let c = p.mat.curve else { continue }
                let t = await PLWEKit.curveTexture(tile: tile, line: PLWEKit.saturate(c.line, bakedSat), ground: PLWEKit.saturate(c.ground, bakedSat))
                if let t { curveTex[i] = t; p.entity.model?.materials = [PLWEKit.material(p.mat, look: look, tex: t)] }
            } } }
    }
    func unload() { root.children.removeAll(); paints = []; curveTex = [:]; lights = []; glyphNodes = [:]; glyphs = []; triggers = [] }
}

extension PLWEKit {
    /// A small thick coin with a raised rim, standing on edge: the key token (22 sides).
    static func glyphTokenDescriptor() -> MeshDescriptor {
        var pos = [PLWEV3](), nrm = [PLWEV3](), uv = [SIMD2<Float>](), idx = [UInt32]()
        let n = 28, R: Float = 0.3, T: Float = 0.06
        for face in [-1, 1] as [Float] {                                   // two faces
            let c = UInt32(pos.count); pos.append([0, 0, face * T]); nrm.append([0, 0, face]); uv.append([0.5, 0.5])
            for k in 0...n { let a = Float(k) / Float(n) * 2 * .pi; pos.append([R * cos(a), R * sin(a), face * T]); nrm.append([0, 0, face]); uv.append([0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)]) }
            for k in 0..<n { let a = c + 1 + UInt32(k); idx += face > 0 ? [c, a, a + 1] : [c, a + 1, a] }
        }
        let s = UInt32(pos.count)                                           // the rim
        for k in 0...n { let a = Float(k) / Float(n) * 2 * .pi, d = PLWEV3(cos(a), sin(a), 0)
            pos.append([R * d.x, R * d.y, -T]); nrm.append(d); uv.append([Float(k) / Float(n), 0])
            pos.append([R * d.x, R * d.y, T]); nrm.append(d); uv.append([Float(k) / Float(n), 1]) }
        for k in 0..<n { let a = s + UInt32(k * 2); idx += [a, a + 2, a + 1, a + 1, a + 2, a + 3] }
        var d = MeshDescriptor(name: "glyphToken")
        d.positions = MeshBuffers.Positions(pos); d.normals = MeshBuffers.Normals(nrm); d.textureCoordinates = MeshBuffers.TextureCoordinates(uv); d.primitives = .triangles(idx)
        return d
    }
}
