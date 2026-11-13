import SwiftUI

// The graph canvas (components/GraphCanvas.tsx), native. One graph per shot: how that one shot gets made. The web draws it only on a
// desktop; the phone draws the same canvas and the same rules (typed sockets, one wire per input, no cycles) and writes the same
// operations into the shot. Drag from an output dot to an input dot to wire; every wire can also be made from the inspector, which is
// the way for VoiceOver and for a thumb that wants the exact port. The recessed ink well is the web's: the assets composited here
// are glowing linework on black, so a cream canvas would make every thumbnail lie.

struct ComposerGraphView: View {
    let model: AppModel
    let shotId: String
    @State private var store = ComposerPieces.shared
    @State private var lib = ComposerLibrary.shared

    @State private var nodes: [GNode] = []
    @State private var edges: [GEdge] = []
    @State private var ready = false
    @State private var selNode: String?
    @State private var selEdge: String?
    @State private var hint: String?
    @State private var pan: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var dragOrigin: [String: CGPoint] = [:]
    @State private var wiring: (from: String, to: CGPoint)?
    @State private var viewport: CGSize = .zero
    @State private var attaching = false
    @State private var tick = 0
    @State private var errTick = 0
    @State private var fitted = false
    @State private var baseline: [ComposerOp] = []

    private var shot: ComposerShot? { store.piece.shots.first { $0.id == shotId } }
    private var byId: [String: ComposerAsset] { lib.byId }
    private var ops: [ComposerOp] { ComposerGraph.toOps(nodes, edges) }

    var body: some View {
        VStack(spacing: 0) {
            strip
            if !ready {
                Group {
                    if let f = lib.failed, lib.manifest == nil { ContentUnavailableView { Label("The library did not load", systemImage: "wifi.exclamationmark") } description: { Text(f + " The graph needs the library to name its sources.") } }
                    else { ProgressView("Reading the library…").tint(CMP.gold) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(CMP.well)
            } else {
                well
                Divider().overlay(CMP.line)
                inspector
            }
        }
        .background(CMP.bg)
        .cmpScreen()
        .navigationTitle(shot?.title ?? "Graph").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Section("Wire a step") {
                        ForEach(NodeKind.addable, id: \.self) { k in
                            Button { add(k) } label: { Label { Text(k.spec.label); Text(k.spec.why) } icon: { Image(systemName: "circle.fill").foregroundStyle(k.spec.output?.color ?? CMP.muted) } }
                        }
                    }
                    Button { attaching = true } label: { Label("Add a source from the library", systemImage: "photo.stack") }
                } label: { Label("Add node", systemImage: "plus.circle") }
                Menu {
                    Button { withAnimation(.snappy) { fit() } } label: { Label("Fit the whole graph", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                    Button { relayout() } label: { Label("Tidy the layout", systemImage: "rectangle.3.group") }
                    Button(role: .destructive) { resetToDefault() } label: { Label("Back to the default wiring", systemImage: "arrow.uturn.backward") }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $attaching) {
            NavigationStack {
                ComposerLibraryRoom(model: model, attachTo: shotId).navigationTitle("Add a source").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { attaching = false } } }
            }.presentationDetents([.large])
        }
        .sensoryFeedback(PLHaptic.select, trigger: tick)
        .sensoryFeedback(PLHaptic.error, trigger: errTick)
        .task {
            await lib.load(model: model)
            guard !ready, lib.manifest != nil, let s = shot else { return }
            let seed = ComposerGraph.canvasFor(s, byId: byId)
            nodes = seed.nodes; edges = seed.edges; baseline = ComposerGraph.toOps(seed.nodes, seed.edges); ready = true
        }
        .onChange(of: shot?.sourceIds ?? []) { _, ids in syncSources(ids) }
        .onChange(of: ops) { _, new in
            guard ready, let s = shot else { return }
            if s.nodes == nil, new == baseline { return }   // opening a graph is not editing it: the default wiring stays derived
            guard (s.nodes ?? []) != new else { return }
            store.patch(shotId) { $0.nodes = new }   // the canvas is the author; shot.nodes is the artifact, written on every settled change
        }
    }

    // MARK: strip

    private var strip: some View {
        HStack(spacing: 10) {
            Text("graph").cmpLabel(9)
            Text(shot?.title ?? "").font(.system(size: 15, design: .serif)).foregroundStyle(CMP.text).lineLimit(1)
            Text("\(ops.count) op\(ops.count == 1 ? "" : "s")").cmpNum(11).foregroundStyle(CMP.muted)
            Spacer()
            if let h = hint { Text(h).font(.system(size: 11)).foregroundStyle(CMP.danger).lineLimit(2).multilineTextAlignment(.trailing).transition(.opacity) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 40)
        .background(CMP.surface.opacity(0.9))
        .animation(.snappy, value: hint)
    }

    // MARK: the well

    private func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + pan.width, y: p.y * zoom + pan.height) }
    private func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - pan.width) / zoom, y: (p.y - pan.height) / zoom) }
    private func nodeFor(_ id: String) -> GNode? { nodes.first { $0.id == id } }

    private var well: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                CMP.well
                Canvas { ctx, size in
                    let gap = 18 * zoom
                    if gap > 7 {
                        var x = pan.width.truncatingRemainder(dividingBy: gap)
                        while x < size.width {
                            var y = pan.height.truncatingRemainder(dividingBy: gap)
                            while y < size.height { ctx.fill(Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5, width: 1.2, height: 1.2)), with: .color(CMP.gold.opacity(0.16))); y += gap }
                            x += gap
                        }
                    }
                    for e in edges {
                        guard let a = nodeFor(e.source), let b = nodeFor(e.target) else { continue }
                        let on = selEdge == e.id
                        ctx.stroke(curve(screen(ComposerGraph.outputPoint(a)), screen(ComposerGraph.inputPoint(b, e.port))), with: .color(on ? CMP.gold : CMP.edge),
                                   style: StrokeStyle(lineWidth: on ? 2.6 : 1.6, lineCap: .round))
                    }
                    if let w = wiring, let a = nodeFor(w.from) {
                        ctx.stroke(curve(screen(ComposerGraph.outputPoint(a)), w.to), with: .color(CMP.gold.opacity(0.85)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5, 4]))
                    }
                }
                .allowsHitTesting(false)

                // empty well: pan, pinch, tap to select a wire or clear the selection
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tapWell($0.location) })
                    .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                        if panStart == nil { panStart = pan }
                        pan = CGSize(width: panStart!.width + v.translation.width, height: panStart!.height + v.translation.height)
                    }.onEnded { _ in panStart = nil })
                    .gesture(MagnifyGesture().onChanged { v in
                        if zoomStart == nil { zoomStart = zoom }
                        setZoom(zoomStart! * v.magnification, around: v.startLocation)
                    }.onEnded { _ in zoomStart = nil })

                ForEach(nodes) { n in nodeView(n) }

                VStack(spacing: 8) {
                    zoomButton("plus", "Zoom in") { setZoom(zoom * 1.25, around: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)) }
                    zoomButton("minus", "Zoom out") { setZoom(zoom / 1.25, around: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)) }
                    zoomButton("arrow.up.left.and.down.right.magnifyingglass", "Fit the whole graph") { withAnimation(.snappy) { fit() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(10)
            }
            .coordinateSpace(name: "well")
            .clipped()
            .onAppear { viewport = geo.size; if !fitted { fitted = true; fit(in: geo.size) } }
            .onChange(of: geo.size) { _, s in viewport = s }
        }
        .frame(minHeight: 220)
    }

    private func zoomButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(CMP.dim).frame(width: 40, height: 40).glassEffect(.regular.interactive(), in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func curve(_ a: CGPoint, _ b: CGPoint) -> Path {
        let dx = max(40 * zoom, abs(b.x - a.x) * 0.5)
        var p = Path(); p.move(to: a); p.addCurve(to: b, control1: CGPoint(x: a.x + dx, y: a.y), control2: CGPoint(x: b.x - dx, y: b.y))
        return p
    }

    // gestures

    private func tapWell(_ at: CGPoint) {
        var best: (String, CGFloat)?
        for e in edges {
            guard let a = nodeFor(e.source), let b = nodeFor(e.target) else { continue }
            let a0 = screen(ComposerGraph.outputPoint(a)), b0 = screen(ComposerGraph.inputPoint(b, e.port))
            let dx = max(40 * zoom, abs(b0.x - a0.x) * 0.5)
            for i in 0...24 {
                let t = CGFloat(i) / 24, m = 1 - t
                let x = m*m*m*a0.x + 3*m*m*t*(a0.x + dx) + 3*m*t*t*(b0.x - dx) + t*t*t*b0.x
                let y = m*m*m*a0.y + 3*m*m*t*a0.y + 3*m*t*t*b0.y + t*t*t*b0.y
                let d = hypot(x - at.x, y - at.y)
                if d < 22, d < (best?.1 ?? .infinity) { best = (e.id, d) }
            }
        }
        withAnimation(.snappy) { selEdge = best?.0; selNode = nil; hint = nil }
        if best != nil { tick += 1 }
    }

    private func setZoom(_ z: CGFloat, around p: CGPoint) {
        let nz = min(2, max(0.15, z))
        let w = world(p)
        zoom = nz
        pan = CGSize(width: p.x - w.x * nz, height: p.y - w.y * nz)
    }

    /// Open fitted to the pane, zoomed out as far as it needs (a wide graph must not open clipped).
    private func fit(in size: CGSize? = nil) {
        let s = size ?? viewport
        guard !nodes.isEmpty, s.width > 0, s.height > 0 else { return }
        let minX = nodes.map { $0.position.x }.min()!, maxX = nodes.map { $0.position.x + ComposerGraph.nodeWidth }.max()!
        let minY = nodes.map { $0.position.y }.min()!, maxY = nodes.map { $0.position.y + ComposerGraph.height($0.kind) }.max()!
        let pad: CGFloat = 28
        let z = min(1, max(0.15, min((s.width - pad * 2) / (maxX - minX), (s.height - pad * 2) / (maxY - minY))))
        zoom = z
        pan = CGSize(width: (s.width - (maxX - minX) * z) / 2 - minX * z, height: (s.height - (maxY - minY) * z) / 2 - minY * z)
    }

    // MARK: a node

    @ViewBuilder private func nodeView(_ n: GNode) -> some View {
        let inset: CGFloat = 16
        let h = ComposerGraph.height(n.kind)
        let origin = screen(n.position)
        GraphNodeBody(node: n, asset: n.assetId.flatMap { byId[$0] }, outType: ComposerGraph.outputType(n, byId), selected: selNode == n.id, connected: Set(edges.filter { $0.target == n.id }.map(\.port)))
            .frame(width: ComposerGraph.nodeWidth, height: h)
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                if dragOrigin[n.id] == nil { dragOrigin[n.id] = n.position; selNode = n.id; selEdge = nil }
                if let o = dragOrigin[n.id], let i = nodes.firstIndex(where: { $0.id == n.id }) {
                    nodes[i].position = CGPoint(x: o.x + v.translation.width / zoom, y: o.y + v.translation.height / zoom)
                }
            }.onEnded { _ in dragOrigin[n.id] = nil })
            .onTapGesture { withAnimation(.snappy) { selNode = n.id; selEdge = nil; hint = nil }; tick += 1 }
            .padding(.horizontal, inset)
            .overlay(alignment: .topLeading) {
                if n.kind != .shot {
                    // the output socket: drag from here to an input. A 36 pt target around a 9 pt dot.
                    Circle().fill(Color.clear).frame(width: 40, height: 40).contentShape(Circle())
                        .position(x: inset + ComposerGraph.nodeWidth, y: ComposerGraph.head + ComposerGraph.row * CGFloat(n.kind.spec.inputs.count) + ComposerGraph.row / 2)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("well")).onChanged { v in
                            wiring = (n.id, v.location); selNode = n.id; selEdge = nil
                        }.onEnded { v in finishWire(from: n, at: v.location) })
                        .accessibilityLabel("Output of \(nodeTitle(n)). Use the inspector to wire it.")
                }
            }
            .frame(width: ComposerGraph.nodeWidth + inset * 2, height: h, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(x: origin.x - inset * zoom, y: origin.y)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(nodeTitle(n)), \(n.kind.spec.label)")
            .accessibilityAddTraits(selNode == n.id ? .isSelected : [])
    }

    private func nodeTitle(_ n: GNode) -> String { n.kind == .source ? (n.assetId.flatMap { byId[$0] }?.name ?? "missing asset") : n.kind.spec.label }

    private func finishWire(from n: GNode, at p: CGPoint) {
        defer { wiring = nil }
        var best: (GNode, String, CGFloat)?
        for t in nodes where t.id != n.id {
            for port in t.kind.spec.inputs {
                let d = hypot(screen(ComposerGraph.inputPoint(t, port.id)).x - p.x, screen(ComposerGraph.inputPoint(t, port.id)).y - p.y)
                if d < 34, d < (best?.2 ?? .infinity) { best = (t, port.id, d) }
            }
        }
        guard let (t, port, _) = best else { return }
        connect(n.id, t.id, port)
    }

    private func connect(_ s: String, _ t: String, _ port: String) {
        let v = ComposerGraph.canConnect(source: s, target: t, port: port, nodes: nodes, edges: edges, byId: byId)
        if !v.ok { hint = v.reason ?? "that connection is not allowed"; errTick += 1; return }
        hint = nil
        edges.append(GEdge(id: "e_" + String(UUID().uuidString.prefix(8)), source: s, target: t, port: port)); tick += 1
    }

    // MARK: edits

    private func add(_ k: NodeKind) {
        let id = "\(k.rawValue)_" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let bottom = (nodes.map { $0.position.y + ComposerGraph.height($0.kind) }.max() ?? 0) + 24
        let at = CGPoint(x: 24 + CGFloat(nodes.count % 3) * 40, y: bottom)
        nodes.append(GNode(id: id, position: at, kind: k, assetId: nil, out: ComposerGraph.nextOut(k, nodes), args: composerDefaultArgs(k)))
        selNode = id; selEdge = nil; hint = nil; tick += 1
        withAnimation(.snappy) { fit() }
    }

    private func removeNode(_ id: String) {
        guard let n = nodeFor(id), n.kind != .shot else { return }
        if n.kind == .source, let a = n.assetId { store.patch(shotId) { $0.sourceIds.removeAll { $0 == a } } }   // a source is the shot's own list: one truth
        nodes.removeAll { $0.id == id }; edges.removeAll { $0.source == id || $0.target == id }
        selNode = nil; tick += 1
    }

    /// Attaching or removing a source on the card shows up here: sources on the canvas are the shot's source list.
    private func syncSources(_ ids: [String]) {
        guard ready else { return }
        let have = Set(nodes.filter { $0.kind == .source }.compactMap(\.assetId))
        let gone = nodes.filter { $0.kind == .source && !ids.contains($0.assetId ?? "") }
        if !gone.isEmpty {
            let goneIds = Set(gone.map(\.id))
            nodes.removeAll { goneIds.contains($0.id) }; edges.removeAll { goneIds.contains($0.source) || goneIds.contains($0.target) }
        }
        for (i, aid) in ids.filter({ !have.contains($0) }).enumerated() {
            nodes.append(GNode(id: "src_new_\(aid)", position: CGPoint(x: 24, y: 24 + CGFloat(have.count + i) * 132), kind: .source, assetId: aid, out: nil, args: [:]))
        }
    }

    private func relayout() { var n = nodes; ComposerGraph.layout(&n, edges); withAnimation(.snappy) { nodes = n; fit() } }
    private func resetToDefault() {
        store.patch(shotId) { $0.nodes = nil }
        if let s = shot { let seed = ComposerGraph.canvasFor(s, byId: byId); nodes = seed.nodes; edges = seed.edges; selNode = nil; selEdge = nil; withAnimation(.snappy) { fit() } }
    }

    // MARK: the inspector (the web's N-panel)

    @ViewBuilder private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let eid = selEdge, let e = edges.first(where: { $0.id == eid }), let a = nodeFor(e.source), let b = nodeFor(e.target) {
                    Text("Wire").cmpLabel(10)
                    Text("\(nodeTitle(a)) → \(nodeTitle(b)) (\(e.port))").font(.system(size: 14)).foregroundStyle(CMP.text)
                    Button(role: .destructive) { edges.removeAll { $0.id == eid }; selEdge = nil; tick += 1 } label: { Label("Remove wire", systemImage: "scissors").frame(maxWidth: .infinity) }.buttonStyle(CMPPill())
                } else if let id = selNode, let n = nodeFor(id) {
                    nodePanel(n)
                } else {
                    Text("Select a node to edit its parameters. Drag from a socket to wire it; only matching types connect. Tap a wire to remove it.").font(.system(size: 12)).foregroundStyle(CMP.dim)
                    FlowLegend()
                }
            }
            .padding(14)
        }
        .frame(maxHeight: 280).background(CMP.surface.opacity(0.95))
    }

    @ViewBuilder private func nodePanel(_ n: GNode) -> some View {
        let spec = n.kind.spec
        Text(nodeTitle(n)).font(.system(size: 18, design: .serif)).foregroundStyle(CMP.text)
        Text(n.kind == .source ? (n.assetId.flatMap { byId[$0] }?.path ?? "") : spec.why).font(.system(size: 11)).foregroundStyle(CMP.muted).textSelection(.enabled)
        if let o = n.out { Text("out: \(o)").cmpNum(11).foregroundStyle(CMP.dim) }
        ForEach(spec.params, id: \.key) { p in
            ParamRow(spec: p, value: n.args[p.key]) { v in
                if let i = nodes.firstIndex(where: { $0.id == n.id }) { nodes[i].args[p.key] = v }
            }
        }
        if !spec.inputs.isEmpty {
            Text("inputs").cmpLabel(9).padding(.top, 4)
            ForEach(spec.inputs, id: \.id) { port in
                let wired = edges.first { $0.target == n.id && $0.port == port.id }
                HStack(spacing: 8) {
                    CMPDot(color: port.accepts.first?.color ?? CMP.muted, size: 7)
                    Text(port.label).font(.system(size: 13)).foregroundStyle(CMP.text)
                    Text(port.accepts.map(\.rawValue).joined(separator: " / ")).cmpNum(9).foregroundStyle(CMP.muted)
                    Spacer()
                    Menu {
                        if let w = wired { Button(role: .destructive) { edges.removeAll { $0.id == w.id } } label: { Label("Disconnect \(nodeFor(w.source).map(nodeTitle) ?? "")", systemImage: "scissors") } }
                        ForEach(nodes.filter { $0.id != n.id && ComposerGraph.canConnect(source: $0.id, target: n.id, port: port.id, nodes: nodes, edges: edges, byId: byId).ok }) { c in
                            Button { connect(c.id, n.id, port.id) } label: { Text(nodeTitle(c)) }
                        }
                    } label: {
                        Text(wired.flatMap { nodeFor($0.source) }.map(nodeTitle) ?? (port.multi ? "Add a wire" : "Not wired")).font(.system(size: 12)).foregroundStyle(wired == nil ? CMP.warn : CMP.gold).lineLimit(1)
                            .padding(.horizontal, 10).frame(minHeight: 34).overlay { Capsule().strokeBorder(CMP.line, lineWidth: 0.8) }
                    }
                }
            }
        }
        if n.kind != .shot {
            Button(role: .destructive) { removeNode(n.id) } label: { Label(n.kind == .source ? "Remove from the shot" : "Delete node", systemImage: "trash").frame(maxWidth: .infinity) }
                .buttonStyle(CMPPill()).padding(.top, 4)
        }
    }
}

// MARK: the node, drawn (PLNode)

struct GraphNodeBody: View {
    let node: GNode
    let asset: ComposerAsset?
    let outType: ComposerSocket?
    let selected: Bool
    let connected: Set<String>

    private var accent: Color { outType?.color ?? Color(hex: 0x6b5d48) }
    private var title: String { node.kind == .source ? (asset?.name ?? "missing asset") : node.kind.spec.label }
    private var sub: String {
        if node.kind == .source { return asset.map { $0.catalog + $0.ext } ?? "\(node.assetId ?? "") — not in this manifest" }
        if let o = node.out { return o }
        let a = node.args
        switch node.kind {
        case .layer: return "\(a["blend"]?.string ?? "screen") · \(String(format: "%.2f", a["opacity"]?.number ?? 1))"
        case .matte: return a["threshold"].flatMap(\.number).map { "cut @ \(Int($0))" } ?? "soft"
        case .constant: return a["value"]?.string ?? ""
        case .file_to_curate: return a["technique"]?.string ?? ""
        default: return ""
        }
    }

    var body: some View {
        let spec = node.kind.spec
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                CMPDot(color: accent, size: 6)
                Text(title).font(.system(size: 11)).foregroundStyle(CMP.text).lineLimit(1)
                Spacer(minLength: 2)
                if let t = outType { Text(t.rawValue).font(.system(size: 9, design: .monospaced)).textCase(.uppercase).foregroundStyle(accent) }
            }
            .padding(.horizontal, 8).frame(height: ComposerGraph.head)
            .overlay(alignment: .bottom) { Rectangle().fill(CMP.nodeLine).frame(height: 1) }
            ForEach(spec.inputs, id: \.id) { p in
                HStack(spacing: 5) {
                    Text(p.label).font(.system(size: 10)).foregroundStyle(Color(hex: 0x9a8d78))
                    if connected.contains(p.id) { Image(systemName: "link").font(.system(size: 7)).foregroundStyle(accent.opacity(0.7)) }
                    Spacer()
                }
                .padding(.leading, 12).padding(.trailing, 8).frame(height: ComposerGraph.row)
                .overlay(alignment: .leading) {   // the hollow input dot, centred on the node's left edge
                    Circle().fill(CMP.node).frame(width: 9, height: 9).overlay { Circle().strokeBorder(p.accepts.first?.color ?? CMP.muted, lineWidth: 2) }.offset(x: -4.5)
                }
            }
            if node.kind != .shot {
                HStack {
                    Spacer()
                    Text(sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(hex: 0x9a8d78)).lineLimit(1)
                }
                .padding(.horizontal, 8).frame(height: ComposerGraph.row)
                .overlay(alignment: .trailing) { Circle().fill(accent).frame(width: 9, height: 9).overlay { Circle().strokeBorder(CMP.node, lineWidth: 2) }.offset(x: 4.5) }
            } else {
                Text("composites in wired order").font(.system(size: 10)).foregroundStyle(Color(hex: 0x9a8d78)).padding(.horizontal, 8).frame(height: ComposerGraph.row, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .background(CMP.node, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(selected ? accent : CMP.nodeLine, lineWidth: 1) }
        .shadow(color: selected ? accent.opacity(0.35) : .clear, radius: 5)
    }
}

/// The eight socket colours and what each carries, for an empty selection (the web's tooltips on the sockets, laid out).
struct FlowLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
            ForEach([ComposerSocket.media, .curve, .audio, .value, .model, .path, .shot], id: \.self) { s in
                HStack(alignment: .top, spacing: 6) {
                    CMPDot(color: s.color, size: 8).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 0) { Text(s.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(CMP.text); Text(s.carries).font(.system(size: 10)).foregroundStyle(CMP.muted) }
                }
            }
        }
    }
}

/// One parameter of the selected node (the N-panel): a word from a list, a number, or a range.
struct ParamRow: View {
    let spec: ParamSpec
    let value: GVal?
    let set: (GVal) -> Void

    var body: some View {
        switch spec.kind {
        case .select:
            HStack {
                Text(spec.label).cmpLabel(9)
                Spacer()
                Picker(spec.label, selection: Binding(get: { value?.string ?? spec.options.first ?? "" }, set: { set(.str($0)) })) { ForEach(spec.options, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.menu).labelsHidden()
            }
        case .number:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spec.label).cmpLabel(9)
                    Spacer()
                    TextField("", value: Binding(get: { value?.number ?? 0 }, set: { set(.num($0)) }), format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).cmpNum(13).frame(width: 80).padding(.vertical, 5).padding(.horizontal, 8)
                        .background(CMP.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
                }
                if let lo = spec.min, let hi = spec.max {
                    Slider(value: Binding(get: { min(hi, max(lo, value?.number ?? lo)) }, set: { set(.num(snap($0))) }), in: lo...hi).accessibilityLabel(spec.label)
                }
            }
        case .range:
            HStack {
                Text(spec.label).cmpLabel(9)
                Spacer()
                ForEach(0..<2, id: \.self) { i in
                    TextField("", value: Binding(get: { (value?.range ?? [0, 1])[safe: i] ?? Double(i) }, set: { v in
                        var r = value?.range ?? [0, 1]; while r.count < 2 { r.append(Double(r.count)) }; r[i] = v; set(.arr(r.map { .num($0) }))
                    }), format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).cmpNum(13).frame(width: 64).padding(.vertical, 5).padding(.horizontal, 8)
                        .background(CMP.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
                }
            }
        }
    }
    private func snap(_ v: Double) -> Double { guard let s = spec.step, s > 0 else { return v }; return (v / s).rounded() * s }
}

private extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
