import SwiftUI
import RealityKit

// The walk-through archive, as `app/archive/space/SpaceClient.tsx` is meant to work: every work is a square in one long hall.
// One lane per category, side to side; time runs away from you (the oldest PL number is 140 m back); the camera rides rails.
// Drag slides across the lanes, a pinch moves you along the hall, a tap opens the work. Thumbnails load as you near them and
// the far ones are released (the page keeps 280, the phone keeps 200).
//
// The page's own layout has drifted from its data: it lays six old categories on the x axis and reads `n` as the PL number, but
// the manifest now has five categories and `n` counts within a subject. Here the lanes are the categories the manifest really
// carries and the depth is the PL number read from the id, which is what the page was written to do.

@MainActor final class SpaceScene {
    @MainActor final class Item {
        let piece: WorldPiece
        let pos: SIMD3<Float>
        let entity: ModelEntity
        var texture: TextureResource?
        var band = -1
        var shown = false
        var loading = false
        var tries = 0
        init(piece: WorldPiece, pos: SIMD3<Float>, entity: ModelEntity) { self.piece = piece; self.pos = pos; self.entity = entity }
    }

    private(set) var items: [Item] = []
    private(set) var lanes: [String] = []
    var target = SIMD3<Float>(0, 0, 20)
    private(set) var current = SIMD3<Float>(0, 0, 20)
    private let root = Entity()
    private let mesh = MeshResource.generatePlane(width: 1.6, height: 1.6)
    private let bandLevel: [Float] = [0.5, 0.67, 0.82, 1.0]
    private var bandMaterials: [UnlitMaterial] = []
    private var sinceRefresh: Float = 1
    private var inFlight = 0

    static let hall: Float = 140
    static let total: Float = 1768
    private static let keep = 200, trim = 160

    func build(engine: WorldEngine, works: [WorldPiece]) {
        engine.add(root)
        bandMaterials = bandLevel.map { UnlitMaterial(color: ThreeDHouse.gold.worldDim($0)) }
        // lanes: the categories the manifest carries, biggest first, eight metres apart and centred
        var counts: [String: Int] = [:]
        for w in works { counts[w.cat ?? "", default: 0] += 1 }
        lanes = counts.sorted { $0.value > $1.value }.map(\.key).filter { !$0.isEmpty }
        var made: [Item] = []
        made.reserveCapacity(works.count)
        for w in works {
            let n = w.number
            let lane = lanes.firstIndex(of: w.cat ?? "").map { (Float($0) - Float(lanes.count - 1) / 2) * 8 } ?? 0
            let pos: SIMD3<Float> = [lane + worldSeeded(n, 0) * 4, worldSeeded(n, 1) * 8, (Float(n) / Self.total - 1) * Self.hall]
            let e = ModelEntity(mesh: mesh, materials: [bandMaterials[3]])
            e.position = pos; e.isEnabled = false
            root.addChild(e)
            made.append(Item(piece: w, pos: pos, entity: e))
        }
        items = made
        refresh()
    }

    /// The year the page's own scale gives for a PL number.
    static func year(forNumber n: Int) -> String {
        let b = [1, 253, 505, 757, 1009, 1261, 1513, 1769], y = ["2019", "2020", "2021", "2022", "2023", "2024", "2025"]
        for i in 0..<7 where n >= b[i] && n < b[i + 1] { return y[i] }
        return "2025"
    }
    static func year(atZ z: Float) -> String {
        let n = Int(((z / hall + 1) * total).rounded())
        return year(forNumber: max(1, min(1768, n)))
    }
    /// Where to stand to meet the start of a year.
    static func z(forYear year: String) -> Float {
        let b: [String: Float] = ["2019": 1, "2020": 253, "2021": 505, "2022": 757, "2023": 1009, "2024": 1261, "2025": 1513]
        return min(25, ((b[year] ?? 1513) / total - 1) * hall + 18)
    }

    func step(_ dt: Float, engine: WorldEngine) {
        let f = 1 - pow(0.9, dt * 60)
        current += (target - current) * f
        engine.camera.position = current
        sinceRefresh += dt
        if sinceRefresh > 0.35 { sinceRefresh = 0; refresh() }
    }

    /// Shows what is in front of you, tints it for fog, asks for thumbnails near you and lets go of far ones.
    private func refresh() {
        let cz = current.z
        for it in items {
            let ahead = cz - it.pos.z                       // metres in front of the camera
            let show = ahead > -12 && ahead < 100
            if show != it.shown { it.shown = show; it.entity.isEnabled = show }
            guard show else { continue }
            let vis = worldFog(abs(ahead), density: 0.008)
            let band = vis > 0.9 ? 3 : vis > 0.75 ? 2 : vis > 0.6 ? 1 : 0
            if band != it.band { it.band = band; apply(it) }
        }
        loadNear(cz)
        trim(cz)
    }

    private func apply(_ it: Item) {
        guard it.band >= 0 else { return }
        if let t = it.texture {
            var m = UnlitMaterial()
            m.color = .init(tint: UIColor(white: CGFloat(bandLevel[it.band]), alpha: 1), texture: .init(t))
            it.entity.model?.materials = [m]
        } else {
            it.entity.model?.materials = [bandMaterials[it.band]]
        }
    }

    private func loadNear(_ cz: Float) {
        guard inFlight < 10 else { return }
        let want = items.filter { $0.texture == nil && !$0.loading && $0.tries < 2 && abs($0.pos.z - cz) <= 40 }
            .sorted { abs($0.pos.z - cz) < abs($1.pos.z - cz) }
            .prefix(10 - inFlight)
        for it in want {
            guard let url = it.piece.thumbURL else { it.tries = 9; continue }
            it.loading = true; it.tries += 1; inFlight += 1
            Task { @MainActor in
                let t = await WorldTextures.load(url)
                it.loading = false; inFlight -= 1
                if let t { it.texture = t; it.band = -1; if it.shown { refresh() } }
                else { loadNear(current.z) }
            }
        }
    }

    private func trim(_ cz: Float) {
        let held = items.filter { $0.texture != nil }
        guard held.count > Self.keep else { return }
        for it in held.sorted(by: { abs($0.pos.z - cz) > abs($1.pos.z - cz) }).prefix(held.count - Self.trim) {
            it.texture = nil; it.band = -1; it.tries = 0
            it.entity.model?.materials = [bandMaterials[0]]
        }
    }

    /// The work under a tap: a ray from the camera (which looks straight down the hall) against the squares in front of it.
    func pick(at p: CGPoint, size: CGSize, fov: Float) -> WorldPiece? {
        guard size.width > 1, size.height > 1 else { return nil }
        let th = tan(fov * .pi / 360), aspect = Float(size.width / size.height)
        let nx = Float(p.x / size.width) * 2 - 1, ny = 1 - Float(p.y / size.height) * 2
        let dir = simd_normalize(SIMD3<Float>(nx * th * aspect, ny * th, -1))
        var best: (t: Float, item: Item)?
        for it in items where it.shown {
            let t = (it.pos.z - current.z) / dir.z
            guard t > 0 else { continue }
            let hx = current.x + dir.x * t - it.pos.x, hy = current.y + dir.y * t - it.pos.y
            if abs(hx) <= 0.85, abs(hy) <= 0.85, best == nil || t < best!.t { best = (t, it) }
        }
        return best?.item.piece
    }
}

struct ArchiveSpaceWorld: View {
    let model: AppModel
    @State private var archive = WorldArchive.shared
    @State private var engine = WorldEngine(fov: 55, far: 300)
    @State private var scene = SpaceScene()
    @State private var zone = "2025"
    @State private var lanes: [String] = []
    @State private var lightbox: WorldPiece?
    @State private var openArchive = false
    @State private var archiveQuery = ""
    @State private var size: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var clock: Float = 0
    private let gold = PLG.gold

    var body: some View {
        ZStack {
            WorldView(engine: engine, background: ThreeDHouse.ground) { eng in
                await archive.load(model: model)
                scene.build(engine: eng, works: archive.pieces)
                lanes = scene.lanes
            }
            .ignoresSafeArea()

            // the rails: drag slides, pinch walks the hall, a tap opens a work
            Color.clear.contentShape(Rectangle())
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        let dx = Float(v.translation.width - lastDrag.width) * 0.018, dy = Float(v.translation.height - lastDrag.height) * 0.018
                        scene.target.x = max(-28, min(28, scene.target.x - dx))
                        scene.target.y = max(-12, min(12, scene.target.y + dy))
                        lastDrag = v.translation
                    }
                    .onEnded { _ in lastDrag = .zero })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { v in
                        scene.target.z = max(-150, min(25, scene.target.z + Float(v.magnification - lastMagnification) * 20))
                        lastMagnification = v.magnification
                    }
                    .onEnded { _ in lastMagnification = 1 })
                .onTapGesture { p in if let w = scene.pick(at: p, size: size, fov: 55) { lightbox = w } }
                .accessibilityElement()
                .accessibilityLabel("The archive hall, \(zone)")
                .accessibilityHint("Swipe up or down to walk the hall. Years are below.")
                .accessibilityAdjustableAction { dir in
                    scene.target.z = max(-150, min(25, scene.target.z + (dir == .increment ? -12 : 12)))
                }

            hud
            WorldTipLine(tip: WorldHallTip())

            if archive.pieces.isEmpty {
                if archive.failed {
                    ContentUnavailableView {
                        Label("The archive did not load", systemImage: "wifi.slash")
                    } description: {
                        Text("The hall opens when the works do.")
                    } actions: {
                        Button("Try again") { Task { await archive.load(model: model, force: true) } }.buttonStyle(.borderedProminent).tint(gold)
                    }
                } else {
                    ProgressView().tint(gold)
                }
            }
            if let w = lightbox { lightboxView(w) }
        }
        .background(Color(uiColor: ThreeDHouse.ground))
        .navigationTitle("Walk the archive").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $openArchive) { ArchiveRoom(model: model, query: archiveQuery) }
        .sensoryFeedback(PLHaptic.open, trigger: lightbox?.cr)
        .animation(.smooth(duration: 0.25), value: lightbox)
        .onAppear {
            let scene = scene, engine = engine
            engine.onFrame = { dt in
                scene.step(dt, engine: engine)
                clock += dt
                if clock > 0.3 {
                    clock = 0
                    let y = SpaceScene.year(atZ: scene.target.z)
                    if y != zone { zone = y }
                }
            }
        }
    }

    private func caps(_ s: String, _ alpha: Double, size: CGFloat = 9, tracking: CGFloat = 2.9) -> some View {
        Text(s).font(.system(size: size)).tracking(tracking).textCase(.uppercase).foregroundStyle(gold.opacity(alpha))
    }

    private var hud: some View {
        VStack(spacing: 0) {
            HStack {
                caps("The Archive \u{00B7} Walk It", 0.28)
                Spacer()
                caps(zone, 0.52).contentTransition(.numericText())
            }
            .padding(.horizontal, 20).padding(.top, 8)
            Spacer()
            // the lanes, then the years: the page has the wheel and the pinch; the phone also gets a way to jump
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) { ForEach(lanes, id: \.self) { caps($0.replacingOccurrences(of: "_", with: " "), 0.28, size: 8, tracking: 2) } }
                        .padding(.horizontal, 20)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["2019", "2020", "2021", "2022", "2023", "2024", "2025"], id: \.self) { y in
                            Button { withAnimation(.smooth) { scene.target.z = SpaceScene.z(forYear: y) } } label: {
                                Text(y).font(.system(size: 11, weight: .medium)).tracking(1.4)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundStyle(zone == y ? Color.black : gold.opacity(0.85))
                                    .background(zone == y ? gold : gold.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain).accessibilityLabel("Go to \(y)")
                        }
                        Button { archiveQuery = ""; openArchive = true } label: {
                            caps("Archive \u{2192}", 0.6, size: 10, tracking: 2).padding(.horizontal, 10).padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func lightboxView(_ w: WorldPiece) -> some View {
        ZStack {
            Color(red: 8 / 255, green: 7 / 255, blue: 5 / 255).opacity(0.95).ignoresSafeArea().onTapGesture { lightbox = nil }
            VStack(alignment: .leading, spacing: 12) {
                AsyncImage(url: w.fullURL ?? w.thumbURL) { img in img.resizable().scaledToFit() } placeholder: { ProgressView().tint(gold).frame(maxWidth: .infinity, minHeight: 240) }
                    .frame(maxHeight: 520)
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.title ?? w.cr).font(.system(size: 11)).tracking(2.4).foregroundStyle(gold.opacity(0.88))
                    Text([w.cr, w.cat?.replacingOccurrences(of: "_", with: " "), w.med].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(.system(size: 9)).tracking(1.6).foregroundStyle(gold.opacity(0.52))
                }
                HStack(spacing: 18) {
                    Button { archiveQuery = w.cr; lightbox = nil; openArchive = true } label: { Text("View in archive \u{2192}").font(.system(size: 10, weight: .medium)).tracking(2.2) }
                    if let u = w.fullURL { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share") }
                }
                .foregroundStyle(gold)
            }
            .padding(24)
            .overlay(alignment: .topTrailing) {
                Button { lightbox = nil } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(gold.opacity(0.7)).padding(14) }
                    .accessibilityLabel("Close")
            }
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}
