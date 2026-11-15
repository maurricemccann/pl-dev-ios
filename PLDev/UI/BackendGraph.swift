import SwiftUI

/// The vault's note graph on the Backend page (his ask 11-14): one dot per note, one line per link, the way Obsidian draws it.
/// The PC lays it out and serves it over Tailscale (PL Call's `vaultgraph`, keyed). It moves like Obsidian's (his ask 11-14, "graph
/// has no motion"): it blooms out from the middle when it opens, floats a little, and a note dragged with a finger pulls its linked
/// notes, which spring back home when it is let go. No note name lives in this code. Pinch to zoom, drag the space to move, drag a
/// note to pull it, tap a note for its name, double tap to reset.
struct BackendGraph: View {
    let model: AppModel

    struct Graph: Decodable {
        struct Node: Decodable { let name: String; let group: Int; let degree: Int; let x: Double; let y: Double }
        let building: Bool?
        let notes_total: Int?; let links_total: Int?
        let groups: [String]; let nodes: [Node]; let links: [[Int]]
    }

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var graph: Graph?
    @State private var sim: GraphSim?
    @State private var failed = false
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero
    @State private var picked: Int?
    @State private var dragging: Int?      // the note under the finger, while one is being pulled
    @State private var panning = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hive mind").plHand(20).foregroundStyle(.white)
                Spacer()
                if let g = graph, let n = g.notes_total, let l = g.links_total {
                    Text("\(n) notes · \(l) links").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    if let g = graph, let sim, !g.nodes.isEmpty {
                        TimelineView(.animation(paused: reduce && dragging == nil)) { tl in
                            canvas(g, sim: sim, size: geo.size, time: tl.date.timeIntervalSinceReferenceDate)
                        }
                        .contentShape(Rectangle())
                        .gesture(gestures(g, sim: sim, size: geo.size))
                        if let i = picked, g.nodes.indices.contains(i) {
                            let n = g.nodes[i]
                            Text("\(n.name) · \(n.degree) links\(g.groups.indices.contains(n.group) && !g.groups[n.group].isEmpty ? " · " + g.groups[n.group] : "")")
                                .font(.caption).foregroundStyle(.white).lineLimit(2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    } else {
                        Text(failed ? "Could not reach the PC (Tailscale may be off)." : (graph?.building == true ? "The PC is drawing the graph. Pull down in a few seconds." : "Reading the graph\u{2026}"))
                            .font(.footnote).foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 420)
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(graph.map { "Graph of \($0.nodes.count) notes and their links" } ?? "Graph of the notes")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: drawing

    private static let pad: CGFloat = 26

    private func screen(_ p: SIMD2<Double>, _ size: CGSize) -> CGPoint {
        let x = Self.pad + CGFloat(p.x) * (size.width - Self.pad * 2), y = Self.pad + CGFloat(p.y) * (size.height - Self.pad * 2)
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: cx + (x - cx) * zoom + offset.width, y: cy + (y - cy) * zoom + offset.height)
    }

    private func unit(_ s: CGPoint, _ size: CGSize) -> SIMD2<Double> {
        let cx = size.width / 2, cy = size.height / 2
        let x = (s.x - offset.width - cx) / zoom + cx, y = (s.y - offset.height - cy) / zoom + cy
        return SIMD2(Double((x - Self.pad) / (size.width - Self.pad * 2)), Double((y - Self.pad) / (size.height - Self.pad * 2)))
    }

    /// One steady colour per top folder, from his palettes (his ruling 11-14): the chosen palette's key and accent first, then the key and
    /// accent of each Design Kit palette, repeating when there are more folders than colours.
    private var houseColors: [Color] {
        let kit = HouseKit.shared
        var seen = Set<String>(), out: [Color] = []
        for p in [kit.palette] + kit.palettes { for hex in [p.key, p.accent] where seen.insert(hex.lowercased()).inserted { if let c = Color(hex: hex) { out.append(c) } } }
        return out.isEmpty ? [PLTone.accent] : out
    }

    private func canvas(_ g: Graph, sim: GraphSim, size: CGSize, time: Double) -> some View {
        sim.step(now: time, float: !reduce)
        let colors = houseColors
        let byDegree = g.nodes.indices.sorted { g.nodes[$0].degree > g.nodes[$1].degree }
        return Canvas { ctx, _ in
            let pts = sim.pos.map { screen($0, size) }
            var lines = Path()
            for l in g.links where l.count == 2 && pts.indices.contains(l[0]) && pts.indices.contains(l[1]) {
                lines.move(to: pts[l[0]]); lines.addLine(to: pts[l[1]])
            }
            ctx.stroke(lines, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            let focus = dragging ?? picked
            if let i = focus {   // the held or picked note's own links, brighter
                var mine = Path()
                for l in g.links where l.count == 2 && (l[0] == i || l[1] == i) && pts.indices.contains(l[0]) && pts.indices.contains(l[1]) {
                    mine.move(to: pts[l[0]]); mine.addLine(to: pts[l[1]])
                }
                ctx.stroke(mine, with: .color(.white.opacity(0.85)), lineWidth: 1)
            }
            for (i, n) in g.nodes.enumerated() where pts.indices.contains(i) {
                let p = pts[i]
                let r = radius(n)
                let c = colors[((n.group % colors.count) + colors.count) % colors.count]
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(c.opacity(i == focus ? 1 : 0.85)))
            }
            // names for the most-linked notes, never on top of one another (his screenshot 11-14: the middle was a pile of words)
            var placed: [CGRect] = []
            let wanted = zoom > 2.2 ? 30 : (zoom > 1.4 ? 14 : 7)
            for i in ([focus].compactMap { $0 } + byDegree.prefix(wanted)) where pts.indices.contains(i) {
                let n = g.nodes[i], p = pts[i]
                let w = CGFloat(min(n.name.count, 26)) * 5.4 + 8, rect = CGRect(x: p.x - w / 2, y: p.y + radius(n) + 2, width: w, height: 12)
                if placed.contains(where: { $0.intersects(rect) }) && i != focus { continue }
                placed.append(rect)
                let name = n.name.count > 26 ? String(n.name.prefix(25)) + "\u{2026}" : n.name
                ctx.draw(Text(name).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.9)), at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }

    private func radius(_ n: Graph.Node) -> CGFloat {
        min(2 + CGFloat(n.degree).squareRoot() * 0.55, 11) * min(max(zoom, 0.8), 1.8)
    }

    // MARK: touch

    private func nearest(_ at: CGPoint, sim: GraphSim, size: CGSize) -> Int? {
        var best: Int?, bestD = CGFloat(26 * 26)   // a finger, not a pixel
        for (i, q) in sim.pos.enumerated() {
            let p = screen(q, size), d = (p.x - at.x) * (p.x - at.x) + (p.y - at.y) * (p.y - at.y)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    private func gestures(_ g: Graph, sim: GraphSim, size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 4)
            .onChanged { v in
                if dragging == nil && !panning {   // the first move decides: a note under the finger is pulled, otherwise the view pans
                    if let i = nearest(v.startLocation, sim: sim, size: size) { dragging = i; picked = i } else { panning = true }
                }
                if let i = dragging { sim.hold(i, at: unit(v.location, size)) }
                else { offset = CGSize(width: offsetStart.width + v.translation.width, height: offsetStart.height + v.translation.height) }
            }
            .onEnded { _ in
                if dragging != nil { sim.release() }
                dragging = nil; panning = false; offsetStart = offset
            }
        let pinch = MagnifyGesture()
            .onChanged { zoom = min(max(zoomStart * $0.magnification, 0.6), 6) }
            .onEnded { _ in zoomStart = zoom }
        let reset = TapGesture(count: 2).onEnded {
            withAnimation(.snappy) { zoom = 1; zoomStart = 1; offset = .zero; offsetStart = .zero; picked = nil }
            sim.bloom()
        }
        let tap = SpatialTapGesture().onEnded { v in picked = nearest(v.location, sim: sim, size: size) }
        return pinch.simultaneously(with: drag).exclusively(before: reset.exclusively(before: tap))
    }

    private func load() async {
        guard let http = model.http, let key = model.config?.key("call"), !key.isEmpty else { failed = true; return }
        do {
            let d = try await http.send(RequestPlan(origin: "call", path: "vaultgraph"), extraHeaders: ["X-Call-Key": key], timeout: 20, cache: false)
            let g = try JSONDecoder().decode(Graph.self, from: d)
            graph = g; failed = false
            if !g.nodes.isEmpty { sim = GraphSim(g, bloom: !reduce) }
        } catch { failed = graph == nil }
    }
}

/// The motion: every note is tied to its home (the PC's layout) by a spring, and every link is a spring at its home length, so the graph
/// always comes to rest exactly as the PC drew it. Pulling one note stretches its links, the neighbours follow, and on release everything
/// settles back with a little overshoot. Idle notes drift a few pixels around home. A plain class, stepped by the view's timeline, so
/// moving notes never re-renders the page around it.
final class GraphSim {
    private(set) var pos: [SIMD2<Double>]
    private var vel: [SIMD2<Double>]
    private let home: [SIMD2<Double>]
    private let links: [(Int, Int, Double)]   // a, b, rest length
    private let phase: [Double]
    private var held: (Int, SIMD2<Double>)?
    private var last: Double?

    init(_ g: BackendGraph.Graph, bloom: Bool) {
        home = g.nodes.map { SIMD2($0.x, $0.y) }
        links = g.links.compactMap { l in
            guard l.count == 2, l[0] != l[1], g.nodes.indices.contains(l[0]), g.nodes.indices.contains(l[1]) else { return nil }
            let a = SIMD2(g.nodes[l[0]].x, g.nodes[l[0]].y), b = SIMD2(g.nodes[l[1]].x, g.nodes[l[1]].y)
            return (l[0], l[1], ((a - b) * (a - b)).sum().squareRoot())
        }
        phase = home.indices.map { Double($0) * 2.399963 }   // golden angle: neighbours never drift in step
        vel = Array(repeating: .zero, count: home.count)
        pos = home
        if bloom { self.bloom() }
    }

    /// Gather every note near the middle, so the springs throw the graph open (the opening flourish and the double-tap reset).
    func bloom() {
        for i in pos.indices { pos[i] = SIMD2(0.5, 0.5) + (home[i] - SIMD2(0.5, 0.5)) * 0.08; vel[i] = .zero }
    }

    func hold(_ i: Int, at p: SIMD2<Double>) { held = (i, p) }
    func release() { held = nil }

    /// Advance to `now`. Fixed small steps, so a dropped frame never makes the springs explode.
    func step(now: Double, float: Bool) {
        let dt = min(max(now - (last ?? now), 0), 0.05)
        last = now
        var left = dt
        while left > 0.0001 {
            let h = min(left, 1.0 / 120)
            tick(h, t: now - left, float: float)
            left -= h
        }
    }

    private func tick(_ h: Double, t: Double, float: Bool) {
        let kHome = 14.0, kLink = 40.0, damp = 7.0
        var force = [SIMD2<Double>](repeating: .zero, count: pos.count)
        for i in pos.indices {
            var target = home[i]
            if float { target += SIMD2(sin(t * 0.55 + phase[i]), cos(t * 0.47 + phase[i] * 1.3)) * 0.008 }   // about three points either way
            force[i] += (target - pos[i]) * kHome
        }
        for (a, b, rest) in links {
            let d = pos[b] - pos[a], len = max((d * d).sum().squareRoot(), 1e-6)
            let f = d / len * ((len - rest) * kLink)
            force[a] += f; force[b] -= f
        }
        for i in pos.indices {
            if let hd = held, hd.0 == i { pos[i] = hd.1; vel[i] = .zero; continue }
            vel[i] += (force[i] - vel[i] * damp) * h
            pos[i] += vel[i] * h
        }
    }
}
