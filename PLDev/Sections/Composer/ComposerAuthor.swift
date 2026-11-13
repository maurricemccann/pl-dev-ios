import SwiftUI

// Composer in full on the phone (his order 11-13; live page read at pl-composer.psychedluxuries.workers.dev). The web opens on a
// piece editor (title, transition, shots, fps, resolution, Build spec, Board) over the asset library. The graph canvas and the
// render stay on the laptop (sub-spec 7): the phone authors the piece, browses the 1,654 assets, and emits the same spec text
// (lib/emit.ts) minus the graph wiring, which the laptop's emitter derives from the sources exactly as it does for a shot
// that has no hand-built graph.

struct ComposerAsset: Decodable, Identifiable, Hashable {
    let id: String; let kind: String; let name: String; let catalog: String?; let ext: String?
    let width: Int?; let height: Int?; let duration: Double?; let tags: [String]?
}

struct ComposerShot: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title = "New shot"
    var duration = 4.0
    var transition: String?
    var sourceIds: [String] = []
}

struct ComposerPiece: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var piece = "untitled-piece"
    var target = "remotion → openmontage"
    var fps = 30
    var resolution = "1080x1920"
    var transition: String?
    var shots: [ComposerShot] = []
    var duration: Double { shots.reduce(0) { $0 + $1.duration } }
}

@MainActor @Observable final class ComposerLibrary {
    static let shared = ComposerLibrary()
    var assets: [ComposerAsset] = []
    var thumbs: [String: String] = [:]
    var failed: String?

    func load(model: AppModel) async {
        guard assets.isEmpty, let http = model.http else { return }
        struct M: Decodable { let assets: [ComposerAsset] }
        struct T: Decodable { let thumbs: [String: String]? }
        do {
            let d = try await http.send(RequestPlan(origin: "composer", path: "api/manifest"), timeout: 60)
            assets = try JSONDecoder().decode(M.self, from: d).assets
            if let t = try? await http.send(RequestPlan(origin: "composer", path: "api/thumbs"), timeout: 60) { thumbs = (try? JSONDecoder().decode(T.self, from: t))?.thumbs ?? [:] }
            failed = nil
        } catch { failed = "The asset library did not load." }
    }

    /// Thumbnails come as data URLs; decode once.
    func image(_ id: String) -> UIImage? {
        guard let s = thumbs[id], let comma = s.firstIndex(of: ","), let d = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return UIImage(data: d)
    }
}

/// The pieces, kept on this phone (the web keeps them in the browser).
@MainActor @Observable final class ComposerPieces {
    static let shared = ComposerPieces()
    var pieces: [ComposerPiece] = [] { didSet { save() } }
    private let key = "pldev.composer.pieces"
    init() { pieces = (try? JSONDecoder().decode([ComposerPiece].self, from: UserDefaults.standard.data(forKey: key) ?? Data())) ?? [] }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(pieces), forKey: key) }

    /// lib/emit.ts emitSpec, line for line, without the graph block (the laptop derives it from the sources).
    static func spec(_ p: ComposerPiece, assets: [ComposerAsset], now: Date = .now) -> String {
        let byId = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        var out = ["---", "spec_version: 1", "piece: \(p.piece)", "created: \(f.string(from: now))", "target: \(p.target)", "fps: \(p.fps)", "resolution: \(p.resolution)"]
        if let t = p.transition { out.append("transition: \(t)") }
        out += ["duration: \(String(format: "%.1f", p.duration))", "---", ""]
        for (i, s) in p.shots.enumerated() {
            out.append("## Shot \(String(format: "%02d", i + 1)): \(s.title)")
            out.append("duration: \(String(format: "%.1f", s.duration))")
            if let t = s.transition, i > 0 { out.append("transition: \(t)") }
            let resolved = s.sourceIds.compactMap { byId[$0] }
            if resolved.isEmpty { out.append("sources: []   # no sources attached, so this shot renders black") }
            else { out.append("sources:"); for a in resolved { out.append("  - \(a.kind): \(a.id)   # \(a.name)\(a.ext ?? "")") } }
            out.append("# graph: derived on the laptop from the sources")
            out.append("")
        }
        return out.joined(separator: "\n")
    }
}

/// The five words, and what each does (lib/types.ts TRANSITION_WHY).
let composerTransitions: [(String, String)] = [("cut", "Nothing. The next shot is simply there."), ("dissolve", "One picture becomes the other."),
    ("black", "Out through black, then in. The longest pause."), ("wipe", "The next shot pushes up over this one."), ("slide", "Both move together, upward.")]

struct ComposerPiecesView: View {
    let model: AppModel
    @State private var store = ComposerPieces.shared

    var body: some View {
        List {
            if store.pieces.isEmpty { ContentUnavailableView("No pieces yet", systemImage: "film.stack", description: Text("A piece is a sequence of shots. Add one, then attach assets to it from the library.")) }
            ForEach($store.pieces) { $p in
                NavigationLink { PieceEditor(model: model, piece: $p) } label: {
                    VStack(alignment: .leading) {
                        Text(p.piece).font(.headline)
                        Text("\(p.shots.count) shots · \(String(format: "%.1f", p.duration)) s · \(p.resolution) at \(p.fps)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { store.pieces.remove(atOffsets: $0) }
        }
        .navigationTitle("Pieces")
        .toolbar { Button("New piece", systemImage: "plus") { store.pieces.insert(ComposerPiece(), at: 0) } }
    }
}

struct PieceEditor: View {
    let model: AppModel
    @Binding var piece: ComposerPiece
    @State private var lib = ComposerLibrary.shared
    @State private var showSpec = false

    var body: some View {
        Form {
            Section {
                TextField("Piece name", text: $piece.piece).textInputAutocapitalization(.never)
                Picker("Transitions", selection: $piece.transition) {
                    Text("All cuts").tag(String?.none)
                    ForEach(composerTransitions, id: \.0) { Text($0.0.capitalized).tag(String?.some($0.0)) }
                }
                Picker("Resolution", selection: $piece.resolution) { ForEach(["1080x1920", "1080x1350", "1080x1080", "1920x1080"], id: \.self) { Text($0).tag($0) } }
                Stepper("FPS \(piece.fps)", value: $piece.fps, in: 24...60, step: 6)
            } footer: { Text("\(piece.shots.count) shots · \(String(format: "%.1f", piece.duration)) seconds") }
            Section("Shots") {
                ForEach($piece.shots) { $s in
                    NavigationLink { ShotEditor(model: model, shot: $s) } label: {
                        VStack(alignment: .leading) {
                            Text(s.title)
                            Text("\(String(format: "%.1f", s.duration)) s · \(s.sourceIds.count) sources\(s.transition.map { " · enters by \($0)" } ?? "")").font(.caption).foregroundStyle(s.sourceIds.isEmpty ? PLTone.house : .secondary)
                        }
                    }
                }
                .onMove { piece.shots.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { piece.shots.remove(atOffsets: $0) }
                Button("Add shot", systemImage: "plus") { piece.shots.append(ComposerShot(title: "Shot \(piece.shots.count + 1)")) }
            }
            Section {
                Button("Build spec") { showSpec = true }.disabled(piece.shots.isEmpty)
            } footer: { Text("Share the spec to the laptop; Composer there wires the graph and renders.") }
        }
        .navigationTitle(piece.piece)
        .toolbar { EditButton() }
        .task { await lib.load(model: model) }
        .sheet(isPresented: $showSpec) {
            let text = ComposerPieces.spec(piece, assets: lib.assets)
            NavigationStack {
                ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                    .navigationTitle("Spec").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ShareLink(item: text); Button("Done") { showSpec = false } }
            }
        }
    }
}

struct ShotEditor: View {
    let model: AppModel
    @Binding var shot: ComposerShot
    @State private var lib = ComposerLibrary.shared
    @State private var picking = false

    var body: some View {
        Form {
            TextField("Title", text: $shot.title)
            Stepper("Duration \(String(format: "%.1f", shot.duration)) s", value: $shot.duration, in: 0.5...60, step: 0.5)
            Picker("Enters by", selection: $shot.transition) {
                Text("The piece's").tag(String?.none)
                ForEach(composerTransitions, id: \.0) { Text($0.0.capitalized).tag(String?.some($0.0)) }
            }
            if let t = shot.transition, let why = composerTransitions.first(where: { $0.0 == t })?.1 { Text(why).font(.footnote).foregroundStyle(.secondary) }
            Section("Sources") {
                if shot.sourceIds.isEmpty { Text("No sources: this shot renders black.").foregroundStyle(PLTone.house) }
                ForEach(shot.sourceIds, id: \.self) { id in
                    let a = lib.assets.first { $0.id == id }
                    HStack {
                        if let img = lib.image(id) { Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipped() }
                        VStack(alignment: .leading) { Text(a?.name ?? id); Text(a.map { "\($0.kind) · \($0.catalog ?? "")" } ?? "").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .onDelete { shot.sourceIds.remove(atOffsets: $0) }
                Button("Attach from the library", systemImage: "plus") { picking = true }
            }
        }
        .navigationTitle(shot.title)
        .sheet(isPresented: $picking) {
            NavigationStack {
                AssetLibraryView(model: model) { a in if !shot.sourceIds.contains(a.id) { shot.sourceIds.append(a.id) }; picking = false }
                    .toolbar { Button("Done") { picking = false } }
            }
        }
    }
}

/// The 1,654 assets the laptop's index publishes, by catalog and kind, with their thumbnails. Pick one when attaching.
struct AssetLibraryView: View {
    let model: AppModel
    var pick: ((ComposerAsset) -> Void)? = nil
    @State private var lib = ComposerLibrary.shared
    @State private var catalog: String?
    @State private var search = ""

    var body: some View {
        let cats = Array(Set(lib.assets.compactMap(\.catalog))).sorted()
        let shown = lib.assets.filter { (catalog == nil || $0.catalog == catalog) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
        List {
            if let f = lib.failed { Text(f).foregroundStyle(.secondary) }
            ForEach(shown.prefix(600)) { a in
                Button { pick?(a) } label: {
                    HStack(spacing: 10) {
                        Group {
                            if let img = lib.image(a.id) { Image(uiImage: img).resizable().scaledToFill() }
                            else { Image(systemName: a.kind == "audio" ? "waveform" : a.kind == "model" ? "cube" : a.kind == "curve" ? "scribble" : "photo").foregroundStyle(.secondary) }
                        }
                        .frame(width: 48, height: 48).background(Color.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(a.name + (a.ext ?? "")).lineLimit(1)
                            Text([a.kind, a.catalog, a.duration.map { String(format: "%.1f s", $0) }, a.width.map { "\($0)×\(a.height ?? 0)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(pick == nil)
            }
        }
        .searchable(text: $search, prompt: "Asset name")
        .navigationTitle("Library · \(shown.count)")
        .toolbar { Menu { Picker("Catalog", selection: $catalog) { Text("Every catalog").tag(String?.none); ForEach(cats, id: \.self) { Text($0).tag(String?.some($0)) } } } label: { Image(systemName: "line.3.horizontal.decrease.circle") } }
        .task { await lib.load(model: model) }
    }
}
