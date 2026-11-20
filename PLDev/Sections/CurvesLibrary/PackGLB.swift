import Foundation
import Metal
import RealityKit

/// His `pack.glb`, read as the page's GLTFLoader reads it, straight from the gallery (no conversion step, so the file the web
/// shows is the file the phone shows). Only what the pack uses: float positions, normals and uvs, 8/16/32-bit indices, one mesh
/// per named node. shortcut: pack.glb's nodes carry no transform (read 11-19); a GLB with node transforms would need them applied here.
struct PackGLB: Sendable {
    struct Prim: Sendable {
        var positions: [Float]   // xyz
        var normals: [Float]     // xyz
        var uvs: [Float]         // uv, glTF's v (0 = image top)
        var indices: [UInt32]
        var material: String
    }
    var nodes: [String: [Prim]]

    struct Failure: Error, CustomStringConvertible { let description: String }

    private struct Doc: Decodable {
        struct Node: Decodable { let name: String?; let mesh: Int? }
        struct Mesh: Decodable { let primitives: [P]; struct P: Decodable { let attributes: [String: Int]; let indices: Int?; let material: Int? } }
        struct Acc: Decodable { let bufferView: Int?; let byteOffset: Int?; let componentType: Int; let count: Int; let type: String }
        struct View: Decodable { let byteOffset: Int?; let byteLength: Int; let byteStride: Int? }
        struct Mat: Decodable { let name: String? }
        let nodes: [Node]; let meshes: [Mesh]; let accessors: [Acc]; let bufferViews: [View]; let materials: [Mat]?
    }

    static func parse(_ data: Data) throws -> PackGLB {
        let b = [UInt8](data)
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        guard b.count >= 28, u32(0) == 0x4654_6C67, u32(4) == 2 else { throw Failure(description: "pack.glb is not a glTF 2 binary") }
        let jsonLen = u32(12)
        guard u32(16) == 0x4E4F_534A, 20 + jsonLen + 8 <= b.count else { throw Failure(description: "pack.glb has no JSON chunk") }
        let binAt = 20 + jsonLen
        let binLen = u32(binAt), bin0 = binAt + 8
        guard u32(binAt + 4) == 0x004E_4942, bin0 + binLen <= b.count else { throw Failure(description: "pack.glb has no binary chunk") }
        let doc = try JSONDecoder().decode(Doc.self, from: Data(b[20..<(20 + jsonLen)]))

        func span(_ i: Int, comps: Int, size: Int) throws -> (start: Int, stride: Int, count: Int, type: Int) {
            guard doc.accessors.indices.contains(i), let vi = doc.accessors[i].bufferView, doc.bufferViews.indices.contains(vi) else { throw Failure(description: "pack.glb accessor \(i) is missing") }
            let a = doc.accessors[i], v = doc.bufferViews[vi]
            let start = bin0 + (v.byteOffset ?? 0) + (a.byteOffset ?? 0), stride = v.byteStride ?? comps * size
            guard a.count > 0, start + (a.count - 1) * stride + comps * size <= bin0 + binLen else { throw Failure(description: "pack.glb accessor \(i) runs past its buffer") }
            return (start, stride, a.count, a.componentType)
        }
        func floats(_ i: Int, _ comps: Int) throws -> [Float] {
            let s = try span(i, comps: comps, size: 4)
            guard s.type == 5126 else { throw Failure(description: "pack.glb accessor \(i) is not float") }
            var out = [Float](repeating: 0, count: s.count * comps)
            b.withUnsafeBytes { raw in
                for k in 0..<s.count { for c in 0..<comps { out[k * comps + c] = raw.loadUnaligned(fromByteOffset: s.start + k * s.stride + c * 4, as: Float.self) } }
            }
            return out
        }
        func indices(_ i: Int) throws -> [UInt32] {
            let t = doc.accessors.indices.contains(i) ? doc.accessors[i].componentType : 0
            let size = t == 5121 ? 1 : t == 5123 ? 2 : t == 5125 ? 4 : 0
            guard size > 0 else { throw Failure(description: "pack.glb accessor \(i) is not an index list") }
            let s = try span(i, comps: 1, size: size)
            return b.withUnsafeBytes { raw in
                (0..<s.count).map { k in
                    let o = s.start + k * s.stride
                    return size == 1 ? UInt32(raw[o]) : size == 2 ? UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)) : raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)
                }
            }
        }

        var nodes: [String: [Prim]] = [:]
        for n in doc.nodes {
            guard let name = n.name, let mi = n.mesh, doc.meshes.indices.contains(mi) else { continue }
            nodes[name] = try doc.meshes[mi].primitives.map { p in
                guard let pi = p.attributes["POSITION"] else { throw Failure(description: "pack.glb node \(name) has no positions") }
                let pos = try floats(pi, 3), count = pos.count / 3
                let nrm = try p.attributes["NORMAL"].map { try floats($0, 3) } ?? [Float](repeating: 0, count: pos.count)
                let uv = try p.attributes["TEXCOORD_0"].map { try floats($0, 2) } ?? [Float](repeating: 0, count: count * 2)
                let idx = try p.indices.map(indices) ?? (0..<UInt32(count)).map { $0 }
                guard nrm.count == pos.count, uv.count == count * 2, idx.allSatisfy({ Int($0) < count }) else { throw Failure(description: "pack.glb node \(name) has mismatched attributes") }
                let mat = p.material.flatMap { doc.materials?.indices.contains($0) == true ? doc.materials?[$0].name : nil } ?? ""
                return Prim(positions: pos, normals: nrm, uvs: uv, indices: idx, material: mat)
            }
        }
        return PackGLB(nodes: nodes)
    }
}

/// One node of the pack as a RealityKit mesh whose vertices can be rewritten every frame (the tear deforms the pouch and the
/// strip, as the page's `deform` does). One part per glTF primitive, in order, so part i takes material i.
@MainActor final class PackMesh {
    let resource: MeshResource
    let rest: [Float]
    let materials: [String]
    private let mesh: LowLevelMesh
    private let indices: [UInt32]
    private let ranges: [(offset: Int, count: Int)]
    private let vertexCount: Int

    init(_ prims: [PackGLB.Prim]) async throws {
        var pos: [Float] = [], nrm: [Float] = [], uv: [Float] = [], idx: [UInt32] = [], ranges: [(offset: Int, count: Int)] = []
        for p in prims {
            let base = UInt32(pos.count / 3)
            ranges.append((offset: idx.count, count: p.indices.count))
            idx += p.indices.map { $0 + base }
            pos += p.positions; nrm += p.normals; uv += p.uvs
        }
        let n = pos.count / 3
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [.init(semantic: .position, format: .float3, offset: 0),
                              .init(semantic: .normal, format: .float3, offset: 12),
                              .init(semantic: .uv0, format: .float2, offset: 24)]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: 32)]
        d.vertexCapacity = n
        d.indexCapacity = idx.count
        d.indexType = .uint32
        let m = try LowLevelMesh(descriptor: d)
        m.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let f = raw.bindMemory(to: Float.self)
            for v in 0..<n {
                let o = v * 8
                f[o] = pos[v * 3]; f[o + 1] = pos[v * 3 + 1]; f[o + 2] = pos[v * 3 + 2]
                f[o + 3] = nrm[v * 3]; f[o + 4] = nrm[v * 3 + 1]; f[o + 5] = nrm[v * 3 + 2]
                f[o + 6] = uv[v * 2]; f[o + 7] = 1 - uv[v * 2 + 1]   // glTF's v runs down the image, RealityKit's up
            }
        }
        m.withUnsafeMutableIndices { raw in
            let t = raw.bindMemory(to: UInt32.self)
            for i in idx.indices { t[i] = idx[i] }
        }
        Self.setParts(m, ranges, Self.bounds(pos))
        rest = pos; indices = idx; self.ranges = ranges; materials = prims.map(\.material); vertexCount = n; mesh = m
        resource = try await MeshResource(from: m)
    }

    /// New positions (same order as `rest`); normals are recomputed from the faces, as three.js computeVertexNormals does.
    func write(_ p: [Float]) {
        var nrm = [Float](repeating: 0, count: p.count)
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[t]) * 3, b = Int(indices[t + 1]) * 3, c = Int(indices[t + 2]) * 3
            let e1x = p[b] - p[a], e1y = p[b + 1] - p[a + 1], e1z = p[b + 2] - p[a + 2]
            let e2x = p[c] - p[a], e2y = p[c + 1] - p[a + 1], e2z = p[c + 2] - p[a + 2]
            let nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x
            nrm[a] += nx; nrm[a + 1] += ny; nrm[a + 2] += nz
            nrm[b] += nx; nrm[b + 1] += ny; nrm[b + 2] += nz
            nrm[c] += nx; nrm[c + 1] += ny; nrm[c + 2] += nz
        }
        let n = vertexCount
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let f = raw.bindMemory(to: Float.self)
            for v in 0..<n {
                let o = v * 8, i = v * 3
                let l = (nrm[i] * nrm[i] + nrm[i + 1] * nrm[i + 1] + nrm[i + 2] * nrm[i + 2]).squareRoot()
                f[o] = p[i]; f[o + 1] = p[i + 1]; f[o + 2] = p[i + 2]
                if l > 0 { f[o + 3] = nrm[i] / l; f[o + 4] = nrm[i + 1] / l; f[o + 5] = nrm[i + 2] / l }
            }
        }
        Self.setParts(mesh, ranges, Self.bounds(p))
    }

    private static func setParts(_ mesh: LowLevelMesh, _ ranges: [(offset: Int, count: Int)], _ box: BoundingBox) {
        mesh.parts.replaceAll(ranges.enumerated().map { i, r in
            LowLevelMesh.Part(indexOffset: r.offset * 4, indexCount: r.count, topology: .triangle, materialIndex: i, bounds: box)
        })
    }

    private static func bounds(_ p: [Float]) -> BoundingBox {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for i in stride(from: 0, to: p.count - 2, by: 3) { let v = SIMD3(p[i], p[i + 1], p[i + 2]); lo = simd_min(lo, v); hi = simd_max(hi, v) }
        return lo.x <= hi.x ? BoundingBox(min: lo, max: hi) : BoundingBox(min: .zero, max: .zero)
    }
}
