import SwiftUI

/// The vault's note graph on the Backend page (his ask 11-14): one dot per note, one line per link, the way Obsidian draws it.
/// The PC lays it out and serves it over Tailscale (PL Call's `vaultgraph`, keyed); this view only draws. No note name lives in
/// this code. Pinch to zoom, drag to move, tap a dot for its name, double tap to reset.
struct BackendGraph: View {
    let model: AppModel

    struct Graph: Decodable {
        struct Node: Decodable { let name: String; let group: Int; let degree: Int; let x: Double; let y: Double }
        let building: Bool?
        let notes_total: Int?; let links_total: Int?
        let groups: [String]; let nodes: [Node]; let links: [[Int]]
    }

    @State private var graph: Graph?
    @State private var failed = false
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero
    @State private var picked: Int?

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
                    if let g = graph, !g.nodes.isEmpty {
                        canvas(g, size: geo.size)
                        if let i = picked, g.nodes.indices.contains(i) {
                            let n = g.nodes[i]
                            Text("\(n.name) · \(n.degree) links\(g.groups.indices.contains(n.group) && !g.groups[n.group].isEmpty ? " · " + g.groups[n.group] : "")")
                                .font(.caption).foregroundStyle(.white).lineLimit(2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(8)
                        }
                    } else {
                        Text(failed ? "Could not reach the PC (Tailscale may be off)." : (graph?.building == true ? "The PC is drawing the graph. Pull down in a few seconds." : "Reading the graph\u{2026}"))
                            .font(.footnote).foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 380)
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func point(_ n: Graph.Node, _ size: CGSize) -> CGPoint {
        let pad: CGFloat = 16
        let x = pad + CGFloat(n.x) * (size.width - pad * 2), y = pad + CGFloat(n.y) * (size.height - pad * 2)
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: cx + (x - cx) * zoom + offset.width, y: cy + (y - cy) * zoom + offset.height)
    }

    /// One steady colour per top folder, spread round the wheel.
    private func tone(_ group: Int, of count: Int) -> Color {
        Color(hue: Double(group) / Double(max(count, 1)), saturation: 0.55, brightness: 0.95)
    }

    private func canvas(_ g: Graph, size: CGSize) -> some View {
        let named = Set(g.nodes.indices.sorted { g.nodes[$0].degree > g.nodes[$1].degree }.prefix(zoom > 2 ? 40 : 10))
        return Canvas { ctx, _ in
            var lines = Path()
            for l in g.links where l.count == 2 && g.nodes.indices.contains(l[0]) && g.nodes.indices.contains(l[1]) {
                lines.move(to: point(g.nodes[l[0]], size)); lines.addLine(to: point(g.nodes[l[1]], size))
            }
            ctx.stroke(lines, with: .color(.white.opacity(0.13)), lineWidth: 0.5)
            if let i = picked {   // the picked note's own links, brighter
                var mine = Path()
                for l in g.links where l.count == 2 && (l[0] == i || l[1] == i) && g.nodes.indices.contains(l[0]) && g.nodes.indices.contains(l[1]) {
                    mine.move(to: point(g.nodes[l[0]], size)); mine.addLine(to: point(g.nodes[l[1]], size))
                }
                ctx.stroke(mine, with: .color(.white.opacity(0.85)), lineWidth: 1)
            }
            for (i, n) in g.nodes.enumerated() {
                let p = point(n, size)
                let r = min(2 + CGFloat(n.degree).squareRoot() * 0.55, 11) * min(max(zoom, 0.8), 1.8)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(tone(n.group, of: g.groups.count).opacity(i == picked ? 1 : 0.85)))
                if named.contains(i) || i == picked {
                    ctx.draw(Text(n.name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: p.x, y: p.y + r + 7))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onChanged { zoom = min(max(zoomStart * $0.magnification, 0.6), 6) }
                .onEnded { _ in zoomStart = zoom }
                .simultaneously(with: DragGesture(minimumDistance: 8)
                    .onChanged { offset = CGSize(width: offsetStart.width + $0.translation.width, height: offsetStart.height + $0.translation.height) }
                    .onEnded { _ in offsetStart = offset })
        )
        .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = 1; zoomStart = 1; offset = .zero; offsetStart = .zero; picked = nil } }
        .onTapGesture { at in
            var best: Int?; var bestD = CGFloat(28 * 28)   // a finger, not a pixel
            for (i, n) in g.nodes.enumerated() {
                let p = point(n, size); let d = (p.x - at.x) * (p.x - at.x) + (p.y - at.y) * (p.y - at.y)
                if d < bestD { bestD = d; best = i }
            }
            picked = best
        }
        .accessibilityLabel("Graph of \(g.nodes.count) notes and their links")
    }

    private func load() async {
        guard let http = model.http, let key = model.config?.key("call"), !key.isEmpty else { failed = true; return }
        do {
            let d = try await http.send(RequestPlan(origin: "call", path: "vaultgraph"), extraHeaders: ["X-Call-Key": key], timeout: 20, cache: false)
            graph = try JSONDecoder().decode(Graph.self, from: d); failed = false
        } catch { failed = graph == nil }
    }
}
