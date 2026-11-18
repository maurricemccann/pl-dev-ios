import RealityKit
import simd

/// Room 1's mesh builder: indexed triangles with world-scale UVs (metres per texture repeat), smooth normals from the faces.
/// Winding is decided per triangle from a direction the front must face, so no hand-checked handedness (the web build was left-handed).
struct P1Mesh {
    typealias V = SIMD3<Float>
    var p: [V] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []

    @discardableResult mutating func vert(_ q: V, _ t: SIMD2<Float>) -> UInt32 { p.append(q); uv.append(t); return UInt32(p.count - 1) }

    /// One triangle, flipped when its winding disagrees with `dir` (the way its front must look).
    mutating func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32, dir: V) {
        let n = simd_cross(p[Int(b)] - p[Int(a)], p[Int(c)] - p[Int(a)])
        if simd_dot(n, dir) < 0 { idx += [a, c, b] } else { idx += [a, b, c] }
    }

    /// A (nr+1) x (nc+1) vertex lattice, one quad per cell. `facing` gets the row, column and cell centre and returns the direction the front looks.
    mutating func grid(_ nr: Int, _ nc: Int, facing: (Int, Int, V) -> V, skip: (Int, Int) -> Bool = { _, _ in false }, _ f: (Int, Int) -> (V, SIMD2<Float>)) {
        let base = UInt32(p.count), w = UInt32(nc + 1)
        for j in 0...nr { for i in 0...nc { let (q, t) = f(j, i); vert(q, t) } }
        for j in 0..<nr { for i in 0..<nc {
            if skip(j, i) { continue }
            let a = base + UInt32(j) * w + UInt32(i), b = a + 1, c = a + w, d = c + 1
            let dir = facing(j, i, (p[Int(a)] + p[Int(d)]) * 0.5)
            tri(a, b, c, dir: dir); tri(b, d, c, dir: dir)
        } }
    }

    mutating func face(_ c: V, n: V, u: V, v: V, hu: Float, hv: Float, metres: Float) {
        let a = vert(c - u * hu - v * hv, [0, 0]), b = vert(c + u * hu - v * hv, [2 * hu / metres, 0])
        let d = vert(c - u * hu + v * hv, [0, 2 * hv / metres]), e = vert(c + u * hu + v * hv, [2 * hu / metres, 2 * hv / metres])
        tri(a, b, d, dir: n); tri(b, e, d, dir: n)
    }

    /// An axis-aligned box with flat faces, UVs at `metres` per repeat.
    static func box(_ size: V, at c: V = .zero, metres: Float = 3) -> P1Mesh {
        var m = P1Mesh(); let h = size / 2
        for s: Float in [-1, 1] {
            m.face(c + [s * h.x, 0, 0], n: [s, 0, 0], u: [0, 0, 1], v: [0, 1, 0], hu: h.z, hv: h.y, metres: metres)
            m.face(c + [0, s * h.y, 0], n: [0, s, 0], u: [1, 0, 0], v: [0, 0, 1], hu: h.x, hv: h.z, metres: metres)
            m.face(c + [0, 0, s * h.z], n: [0, 0, s], u: [1, 0, 0], v: [0, 1, 0], hu: h.x, hv: h.y, metres: metres)
        }
        return m
    }

    /// A surface of revolution round the Y axis. `profile` is (radius, y), traced so that the solid is on the left of the travel
    /// (up the outside, over the rim, down the inside); fronts look to the right of the travel.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int, at c: V = .zero, metres: Float = 3) -> P1Mesh {
        var m = P1Mesh()
        var run: [Float] = [0]
        for k in 1..<profile.count { run.append(run[k - 1] + simd_length(profile[k] - profile[k - 1])) }
        let rmax = profile.map { $0.x }.max() ?? 1
        m.grid(profile.count - 1, segments, facing: { j, _, ctr in
            let t = profile[j + 1] - profile[j], n2 = SIMD2<Float>(t.y, -t.x)
            let rad = simd_normalize(V(ctr.x - c.x, 0, ctr.z - c.z) + [1e-5, 0, 0])
            return rad * n2.x + V(0, 1, 0) * n2.y
        }) { j, i in
            let a = Float(i) / Float(segments) * 2 * .pi, r = profile[j].x
            return (c + V(sin(a) * r, profile[j].y, cos(a) * r), [Float(i) / Float(segments) * 2 * .pi * rmax / metres, run[j] / metres])
        }
        return m
    }

    /// A closed section swept along a path. Section points are (side, up) offsets scaled by `scale(row)`; the fronts look away from the path.
    static func sweep(_ path: [V], section: [SIMD2<Float>], scale: (Int) -> SIMD2<Float>, side fixed: V? = nil, metres: Float = 3) -> P1Mesh {
        var m = P1Mesh(), len: [Float] = [0]
        for k in 1..<path.count { len.append(len[k - 1] + simd_length(path[k] - path[k - 1])) }
        var frames: [(V, V)] = []
        for k in path.indices {
            let t = simd_normalize(path[min(k + 1, path.count - 1)] - path[max(k - 1, 0)])
            let s = fixed ?? simd_normalize(simd_cross(t, V(0, 1, 0)))
            frames.append((s, simd_normalize(simd_cross(s, t))))
        }
        let n = section.count
        m.grid(path.count - 1, n, facing: { j, _, ctr in ctr - path[j] }) { j, i in
            let o = section[i % n] * scale(j), (s, u) = frames[j]
            return (path[j] + s * o.x + u * o.y, [Float(i) / Float(n) * 2 * .pi * (scale(j).x + scale(j).y) / metres, len[j] / metres])
        }
        return m
    }

    static func circle(_ n: Int) -> [SIMD2<Float>] { (0..<n).map { let a = Float($0) / Float(n) * 2 * .pi; return [cos(a), sin(a)] } }
    /// A rounded rectangle section, half-extents 1.
    static let slab: [SIMD2<Float>] = [[1, 0.6], [0.6, 1], [-0.6, 1], [-1, 0.6], [-1, -0.6], [-0.6, -1], [0.6, -1], [1, -0.6]]

    static func spline(_ c: [V], per: Int) -> [V] {
        let e = [c[0]] + c + [c[c.count - 1]]
        var out: [V] = []
        for s in 0..<(c.count - 1) {
            let p0 = e[s], p1 = e[s + 1], p2 = e[s + 2], p3 = e[s + 3]
            for k in 0..<per {
                let t = Float(k) / Float(per), t2 = t * t, t3 = t2 * t
                out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
            }
        }
        out.append(c[c.count - 1]); return out
    }

    mutating func merge(_ o: P1Mesh) {
        let b = UInt32(p.count); p += o.p; uv += o.uv; idx += o.idx.map { $0 + b }
    }

    func resource() -> MeshResource? {
        var nn = [V](repeating: .zero, count: p.count)
        for t in stride(from: 0, to: idx.count, by: 3) {
            let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2]), f = simd_cross(p[b] - p[a], p[c] - p[a])
            nn[a] += f; nn[b] += f; nn[c] += f
        }
        nn = nn.map { simd_length($0) > 1e-9 ? simd_normalize($0) : V(0, 1, 0) }
        var d = MeshDescriptor(name: "plw-p1")
        d.positions = MeshBuffers.Positions(p)
        d.normals = MeshBuffers.Normals(nn)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv.map { SIMD2<Float>($0.x, 1 - $0.y) })   // RealityKit's V runs down the image
        d.primitives = .triangles(idx)
        return PLWLog.mesh(from: [d])
    }
}
