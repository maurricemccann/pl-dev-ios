import Foundation

/// Room 3's maze as data: the web build's seeded depth-first carve on a 12 x 8 grid (same generator and seed, so the same maze), the one true way,
/// the dead ends, the secret and the two gates. Rows grow toward -Z in the room's frame.
struct P3Maze {
    static let nx = 12, nz = 8, entry = 5, exit = 10

    struct LCG { var s: Int; mutating func next() -> Double { s = (s * 16807) % 2147483647; return Double(s) / 2147483647 } }

    var east = [[Bool]](repeating: [Bool](repeating: false, count: Self.nz), count: Self.nx)    // wall-free edge to the cell on the east
    var south = [[Bool]](repeating: [Bool](repeating: false, count: Self.nz), count: Self.nx)   // wall-free edge to the cell on the south
    var path: [(i: Int, j: Int)] = [], deadEnds: [(i: Int, j: Int)] = [], gates: [Int] = []
    var secret = (i: 0, j: 0), secretOpening = (i: 0, j: 0)
    var crowdEnds: [(i: Int, j: Int)] = []

    func open(_ i: Int, _ j: Int, _ di: Int, _ dj: Int) -> Bool {
        di == 1 ? east[i][j] : di == -1 ? (i > 0 && east[i - 1][j]) : dj == 1 ? south[i][j] : (j > 0 && south[i][j - 1])
    }
    func nbrs(_ i: Int, _ j: Int) -> [(Int, Int)] {
        [(1, 0), (-1, 0), (0, 1), (0, -1)].compactMap { di, dj in
            let a = i + di, b = j + dj
            return a >= 0 && b >= 0 && a < Self.nx && b < Self.nz && open(i, j, di, dj) ? (a, b) : nil
        }
    }
    /// The true way's run through path index k: "z" or "x" when the way goes straight, nil at a turn.
    func straight(_ k: Int) -> Character? {
        guard k > 0, k < path.count - 1 else { return nil }
        let a = path[k - 1], c = path[k + 1]
        return a.i == c.i ? "z" : a.j == c.j ? "x" : nil
    }

    init() {
        let nx = Self.nx, nz = Self.nz, ie = Self.entry
        var seen = [[Bool]](repeating: [Bool](repeating: false, count: nz), count: nx), r = LCG(s: 3303)
        var st = [(ie, 0)]; seen[ie][0] = true
        while let (i, j) = st.last {
            let nb = [(1, 0), (-1, 0), (0, 1), (0, -1)].map { (i + $0.0, j + $0.1, $0.0, $0.1) }.filter { a, b, _, _ in a >= 0 && b >= 0 && a < nx && b < nz && !seen[a][b] }
            if nb.isEmpty { st.removeLast(); continue }
            let (a, b, di, dj) = nb[min(nb.count - 1, Int(r.next() * Double(nb.count)))]
            if di == 1 { east[i][j] = true }; if di == -1 { east[a][b] = true }
            if dj == 1 { south[i][j] = true }; if dj == -1 { south[a][b] = true }
            seen[a][b] = true; st.append((a, b))
        }
        east[ie - 1][0] = true; east[ie][0] = true   // the entry plaza, three cells wide under room 2's tunnel mouth
        for (a, b) in [(2, 3), (7, 4)] { east[a][b] = true; east[a][b + 1] = true; south[a][b] = true; south[a + 1][b] = true }   // two small courtyards
        var dist = [[Int]](repeating: [Int](repeating: -1, count: nz), count: nx), prev: [Int: (Int, Int)] = [:], q = [(ie, 0)]
        dist[ie][0] = 0
        var h = 0
        while h < q.count {
            let (i, j) = q[h]; h += 1
            for (a, b) in nbrs(i, j) where dist[a][b] < 0 { dist[a][b] = dist[i][j] + 1; prev[a * 100 + b] = (i, j); q.append((a, b)) }
        }
        var c: (Int, Int)? = (Self.exit, nz - 1), p: [(i: Int, j: Int)] = []
        while let cur = c { p.insert((cur.0, cur.1), at: 0); c = prev[cur.0 * 100 + cur.1] }
        path = p
        let onPath = Set(p.map { $0.i * 100 + $0.j })
        var ends: [(i: Int, j: Int)] = []
        for i in 0..<nx { for j in 0..<nz where !onPath.contains(i * 100 + j) && nbrs(i, j).count == 1 && !(j == 0 && abs(i - ie) <= 1) { ends.append((i, j)) } }
        ends.sort { dist[$0.i][$0.j] != dist[$1.i][$1.j] ? dist[$0.i][$0.j] > dist[$1.i][$1.j] : ($0.i, $0.j) < ($1.i, $1.j) }
        secret = ends.first ?? (0, nz - 1)
        let o = nbrs(secret.i, secret.j).first ?? (secret.i, secret.j); secretOpening = (o.0, o.1)
        crowdEnds = Array(ends.dropFirst().prefix(8)); deadEnds = ends
        func gateAt(_ f: Double) -> Int {
            for d in 0..<p.count { for k in [Int((Double(p.count) * f).rounded()) + d, Int((Double(p.count) * f).rounded()) - d] where straight(k) != nil { return k } }
            return 2
        }
        gates = [gateAt(0.35), gateAt(0.72)]
    }
}
