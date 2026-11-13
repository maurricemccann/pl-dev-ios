import AVKit
import CryptoKit
import SwiftUI
import WebKit

// The Curve Library in full (his order 11-13; inventory of pl-curves-gallery at 1af6cabd). Everything with data is native.
// The code art (live pieces, the VJ instrument, Forge, the 3D worlds, the labs) is written as browser code (Canvas 2D,
// WebGL, Three.js: about 40k lines), so it plays in a full-screen web canvas inside native chrome, signed in with the same
// pl_lib cookie the gallery's own /unlock sets (SHA-256 of "pl-lib-unlock:" + the vault key), so his key is never in a page.

// MARK: - Rooms

enum GalleryRoom: String, CaseIterable, Identifiable, Hashable {
    case curves, live, forge, vault, archive, space, generated, cinematic, printful, classify, kit, tools, labs, worlds, town
    var id: String { rawValue }
    var title: String {
        switch self {
        case .curves: return "Curves"; case .live: return "Live"; case .forge: return "Forge"; case .vault: return "The vault"
        case .archive: return "Archive"; case .space: return "Walk the archive"; case .generated: return "Stills"
        case .cinematic: return "Cinematic"; case .printful: return "Printful"; case .classify: return "Classify the archive"
        case .kit: return "Design Kit"; case .tools: return "Tools and source"; case .labs: return "Labs"; case .worlds: return "The Defiance worlds"
        case .town: return "The town"
        }
    }
    var symbol: String {
        switch self {
        case .curves: return "scribble.variable"; case .live: return "waveform.path.ecg"; case .forge: return "hammer"
        case .vault: return "lock.rectangle.stack"; case .archive: return "photo.stack"; case .space: return "view.3d"
        case .generated: return "photo.on.rectangle"; case .cinematic: return "film"; case .printful: return "tshirt"
        case .classify: return "tag"; case .kit: return "swatchpalette"; case .tools: return "chevron.left.forwardslash.chevron.right"
        case .labs: return "flask"; case .worlds: return "cube.transparent"; case .town: return "building.2"
        }
    }
    var line: String {
        switch self {
        case .curves: return "Every live piece, running"; case .live: return "The VJ instrument"; case .forge: return "Write a piece with AI"
        case .vault: return "Everything filed, by kind"; case .archive: return "1,347 works"; case .space: return "The archive as a room"
        case .generated: return "Every still"; case .cinematic: return "Every clip"; case .printful: return "Template triage"
        case .classify: return "Name and file the archive"; case .kit: return "Colours, fonts, symbols"; case .tools: return "The code behind every piece"
        case .labs: return "Experiments"; case .worlds: return "The Haul, the Money Room, the Weight"; case .town: return "The pixel town"
        }
    }

    @MainActor @ViewBuilder func view(_ model: AppModel) -> some View {
        switch self {
        case .curves: CurvesRoom(model: model)
        case .live: GalleryCanvas(model: model, path: "live", title: "Live")
        case .forge: GalleryCanvas(model: model, path: "forge", title: "Forge")
        case .vault: VaultRoom(model: model)
        case .archive: ArchiveRoom(model: model)
        case .space: GalleryCanvas(model: model, path: "archive/space", title: "Walk the archive")
        case .generated: StillsRoom(model: model)
        case .cinematic: CinematicRoom(model: model)
        case .printful: PrintfulRoom(model: model)
        case .classify: ClassifyRoom(model: model)
        case .kit: KitRoom(model: model)
        case .tools: ToolsRoom(model: model)
        case .labs: WebListRoom(model: model, title: "Labs", items: GalleryRoom.labPages)
        case .worlds: WebListRoom(model: model, title: "The Defiance worlds", items: GalleryRoom.worldPages)
        case .town: GalleryCanvas(model: model, path: "town?r1=1", title: "The town")
        }
    }

    static let worldPages: [(String, String, String)] = [("defiance/the-haul", "The Haul", "Archive art on the walls of a room you walk"),
        ("defiance/the-money-room", "The Money Room", "GlyphGuy dancing in falling cash"), ("defiance/the-weight", "The Weight", "A field of floating works")]
    static let labPages: [(String, String, String)] = [
        ("lab", "Ribbon curves", "Three.js ribbons from his comps"), ("lab/golden-mend", "Golden Mend", "A kintsugi instrument played by the mic"),
        ("lab/life", "Life", "Game of Life on the GPU, fed by the mic"), ("lab/ar", "AR curves", "Gold curves over the camera"),
        ("lab/fly", "The fly", "A connectome steering a gold line"), ("lab/dance", "GlyphGuy dances", "His animation clips"),
        ("lab/glyphbot", "GlyphBot", "GlyphGuy under a spotlight"), ("lab/heart", "Heart coin", "The spinning heart"),
        ("lab/wordmark", "Wordmark", "His hand in 3D"), ("lab/nft-candidates", "Cards", "GlyphGuy on his palettes"),
        ("lab/trained-hero", "Hero grammar", "The painting-grammar generator"), ("lab/fluid", "Fluid", "Fluid cursor reveal"),
        ("lab/glitch", "Glitch", "Shader study"), ("lab/warp", "Warp", "Shader study"), ("lab/reaction-diffusion", "Reaction diffusion", "Shader study"),
        ("lab/glyph-plotter", "Glyph plotter", "p5 sketch"), ("lab/kinematic", "Kinematic", "p5 sketch"), ("lab/phyllotaxis", "Phyllotaxis", "p5 sketch"),
        ("lab/home", "Home study", "2,000 curves"), ("lab/study", "The study", "A door and the Three Truths"), ("lab/webgpu-probe", "WebGPU", "Probe"),
        ("components", "Components", "Glass, borders, countdowns"), ("curve-who", "Curve who", "Clay story, in progress"),
        ("living-curves-art/", "The curve in motion", "p5 and three"), ("hand.html", "His hand", "Type, rendered in his hands"),
    ]
}

/// The Curve Library's rooms: the gallery's More sheet, native.
struct GalleryRoomsView: View {
    let model: AppModel
    var body: some View {
        List {
            Section("See") { ForEach([GalleryRoom.curves, .live, .archive, .space, .generated, .cinematic]) { row($0) } }
            Section("Make") { ForEach([GalleryRoom.forge, .classify, .printful]) { row($0) } }
            Section("Find") { ForEach([GalleryRoom.vault, .kit, .tools]) { row($0) } }
            Section("Play") { ForEach([GalleryRoom.worlds, .labs, .town]) { row($0) } }
        }
        .gScreen()
        .navigationTitle("Curve Library")
    }
    private func row(_ r: GalleryRoom) -> some View {
        NavigationLink { r.view(model) } label: {
            Label { VStack(alignment: .leading) { Text(r.title); Text(r.line).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: r.symbol) }
        }
    }
}

// MARK: - The web canvas for code art

/// One gallery page as full-screen code art. Signed in with the gallery's own cookie, never the key itself.
struct GalleryCanvas: View {
    let model: AppModel
    let path: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GalleryWeb(model: model, path: path)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let u = URL(string: LibraryData.shared.base(model) + "/" + path) {
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                }
            }
    }
}

struct GalleryWeb: UIViewRepresentable {
    let model: AppModel
    let path: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = true
        let base = LibraryData.shared.base(model)
        guard let url = URL(string: base + "/" + path), let host = url.host else { return web }
        if let key = model.config?.key("vault") {
            let token = SHA256.hash(data: Data("pl-lib-unlock:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
            let cookie = HTTPCookie(properties: [.name: "pl_lib", .value: token, .domain: host, .path: "/", .secure: "TRUE",
                                                 HTTPCookiePropertyKey("HttpOnly"): "TRUE", .sameSitePolicy: "Lax",
                                                 .expires: Date().addingTimeInterval(400 * 86400)])
            if let cookie {
                web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { web.load(URLRequest(url: url)) }
                return web
            }
        }
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

struct WebListRoom: View {
    let model: AppModel
    let title: String
    let items: [(String, String, String)]
    var body: some View {
        List {
            if title == "Labs" {
                Section {
                    NavigationLink { GalleryCanvas(model: model, path: "live", title: "The VJ") } label: {
                        VStack(alignment: .leading, spacing: 2) { Text("● Live").gEyebrow(10).foregroundStyle(PLG.red); Text("The VJ").gTitle(22); Text("The living set as a controller: tracks, tap tempo, rack.").font(.caption).foregroundStyle(.secondary) }
                    }
                    NavigationLink { GalleryCanvas(model: model, path: "lab", title: "Living Curves") } label: {
                        VStack(alignment: .leading, spacing: 2) { Text("Ribbon").gEyebrow(10).foregroundStyle(PLG.goldDim(.dark)); Text("Living Curves, the ribbon lab").gTitle(22) }
                    }
                } header: { Text("Instruments and experiments. The VJ lives here now.") }
            }
            Section {
                ForEach(items.filter { title != "Labs" || $0.0 != "lab" }, id: \.0) { it in
                    NavigationLink { GalleryCanvas(model: model, path: it.0, title: it.1) } label: {
                        VStack(alignment: .leading) { Text(it.1); Text("/" + it.0).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .gScreen()
        .navigationTitle(title == "Labs" ? "The Labs" : title)
    }
}

// MARK: - Curves: every live piece, liked filter, full-screen live

struct CurvesRoom: View {
    let model: AppModel
    @State private var data = LibraryData.shared
    @State private var liked = Set<String>()
    @State private var onlyLiked = false
    @State private var search = ""
    @State private var playing: LibraryItem?
    @State private var tick = 0

    private var pieces: [LibraryItem] {
        data.items.filter { $0.class == "code-piece" && data.marks[$0.vault_id]?.v != "cut" }
            .filter { !onlyLiked || liked.contains($0.item_id) }
            .filter { search.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(search) || $0.item_id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                ForEach(pieces) { p in
                    Button { playing = p } label: {
                        ZStack(alignment: .bottomLeading) {
                            Tile(item: p, mark: data.marks[p.vault_id], url: data.media(p, model: model).still)
                            if liked.contains(p.item_id) { Image(systemName: "heart.fill").foregroundStyle(PLG.gold).padding(6) }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button(liked.contains(p.item_id) ? "Unlike" : "Like", systemImage: "heart") { Task { await like(p) } } }
                }
            }
            .padding(6)
        }
        .gScreen()
        .searchable(text: $search, prompt: "Piece")
        .navigationTitle("Curves · \(pieces.count)")
        .toolbar { Toggle(isOn: $onlyLiked) { Image(systemName: onlyLiked ? "heart.fill" : "heart") }.accessibilityLabel("Liked only") }
        .task {
            if data.items.isEmpty { try? await data.load(model: model) }
            struct L: Decodable { let liked: [String] }
            if let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/likes")),
               let l = try? JSONDecoder().decode(L.self, from: d) { liked = Set(l.liked) }
        }
        .fullScreenCover(item: $playing) { p in
            NavigationStack {
                GalleryWeb(model: model, path: "pieces/embed?id=\(p.item_id)").ignoresSafeArea()
                    .navigationTitle(p.name ?? p.item_id).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { playing = nil } }
                        ToolbarItem(placement: .primaryAction) {
                            Button { Task { await like(p) } } label: { Image(systemName: liked.contains(p.item_id) ? "heart.fill" : "heart") }
                        }
                        ToolbarItem(placement: .secondaryAction) { NavigationLink("The code") { SourceView(model: model, id: p.item_id) } }
                    }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
    }

    private func like(_ p: LibraryItem) async {
        guard let http = model.http else { return }
        struct R: Decodable { let liked: Bool? }
        let body = try? JSONSerialization.data(withJSONObject: ["id": p.item_id])
        if let d = try? await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/likes",
                                                    headers: ["content-type": "application/json", "Origin": data.base(model)], body: body), idempotent: false),
           let r = try? JSONDecoder().decode(R.self, from: d) {
            if r.liked == true { liked.insert(p.item_id) } else { liked.remove(p.item_id) }
            tick += 1
        }
    }
}

/// The code behind a piece (/api/source/<id>), selectable.
struct SourceView: View {
    let model: AppModel
    let id: String
    struct Src: Decodable { let name: String?; let sub: String?; let code: String? }
    var body: some View {
        Loaded(load: {
            guard let http = model.http else { throw Console.Problem.notSetUp }
            return try JSONDecoder().decode(Src.self, from: try await http.send(RequestPlan(origin: "gallery", path: "api/source/\(id)")))
        }) { s, _ in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 8) {
                    if let sub = s.sub { Text(sub).font(.callout).foregroundStyle(.secondary) }
                    Text(s.code ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle(s.name ?? id)
            .toolbar { if let c = s.code { ShareLink(item: c) { Image(systemName: "square.and.arrow.up") } } }
        }
    }
}

// MARK: - Archive, stills, cinematic

struct ArchiveRoom: View {
    let model: AppModel
    struct Piece: Decodable, Identifiable, Hashable { let cr: String; let title: String?; let url: String?; let thumb: String?; let cat: String?; let subj: String?; let color: String?; let medium: String?; let body: String?; let note: String?; var id: String { cr } }
    struct M: Decodable { let pieces: [Piece] }
    @State private var pieces: [Piece] = []
    @State private var cat: String?
    @State private var color: String?
    @State private var subj: String?
    @State private var search = ""
    @State private var open: Piece?

    var body: some View {
        let cats = Array(Set(pieces.compactMap(\.cat))).sorted()
        let shown = pieces.filter { (cat == nil || $0.cat == cat) && (color == nil || $0.color == color) && (subj == nil || $0.subj == subj) && (search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search) || $0.cr.localizedCaseInsensitiveContains(search) || ($0.subj ?? "").localizedCaseInsensitiveContains(search)) }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                ForEach(shown) { p in
                    Button { open = p } label: {
                        AsyncImage(url: URL(string: p.thumb ?? p.url ?? "")) { $0.resizable().scaledToFill() } placeholder: { Color(hex: 0x1a1610) }
                            .frame(height: 104).clipped()
                    }
                    .buttonStyle(.plain).accessibilityLabel(p.title ?? p.cr)
                }
            }
            .padding(4)
        }
        .gScreen()
        .searchable(text: $search, prompt: "Title, PL number or subject")
        .navigationTitle("The complete works")
        .toolbar {
            Menu {
                Picker("Category", selection: $cat) { Text("Every kind").tag(String?.none); ForEach(cats, id: \.self) { Text($0.capitalized).tag(String?.some($0)) } }
                Picker("Colour", selection: $color) { Text("Every colour").tag(String?.none); ForEach(Array(Set(pieces.compactMap(\.color))).sorted(), id: \.self) { Text($0.capitalized).tag(String?.some($0)) } }
                Picker("Subject", selection: $subj) { Text("Every subject").tag(String?.none); ForEach(Array(Set(pieces.compactMap(\.subj))).sorted(), id: \.self) { Text($0.capitalized).tag(String?.some($0)) } }
            } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            NavigationLink { GalleryCanvas(model: model, path: "archive/space", title: "Walk the archive") } label: { Label("Walk it in 3D", systemImage: "view.3d") }
        }
        .task { if pieces.isEmpty, let d = try? await gallery("archive/manifest.json"), let m = try? JSONDecoder().decode(M.self, from: d) { pieces = m.pieces } }
        .sheet(item: $open) { p in
            NavigationStack {
                ScrollView {
                    // the thumb shows at once, the original (10-20 MB) fades in over it
                    ZStack {
                        AsyncImage(url: URL(string: p.thumb ?? "")) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        AsyncImage(url: URL(string: p.url ?? "")) { $0.resizable().scaledToFit().transition(.opacity) } placeholder: { Color.clear }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text([p.cr, p.cat, p.medium, p.body].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        if let n = p.note, !n.isEmpty { Text(n).plReading() }
                    }
                    .padding()
                }
                .navigationTitle(p.title ?? p.cr).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { open = nil }; if let u = URL(string: p.url ?? "") { ShareLink(item: u) } }
            }
        }
    }

    private func gallery(_ path: String) async throws -> Data {
        guard let http = model.http else { throw Console.Problem.notSetUp }
        return try await http.send(RequestPlan(origin: "gallery", path: path), timeout: 60)
    }
}

/// Favourite and hide are kept on this phone, as the web keeps them in the browser.
struct StillsRoom: View {
    let model: AppModel
    struct Item: Decodable, Identifiable, Hashable { let id: String; let file: String; let collection: String?; let tier: String?; let w: Int?; let h: Int? }
    struct M: Decodable { let items: [Item] }
    @State private var items: [Item] = []
    @State private var collection: String?
    @State private var view = "all"
    @AppStorage("pldev.stills.fav") private var favs = ""
    @AppStorage("pldev.stills.hide") private var hides = ""
    @State private var open: Item?
    @State private var jump = ""

    private func has(_ list: String, _ id: String) -> Bool { list.split(separator: ",").contains(Substring(id)) }
    private func toggled(_ list: String, _ id: String) -> String {
        var s = Set(list.split(separator: ",").map(String.init)); if s.contains(id) { s.remove(id) } else { s.insert(id) }; return s.sorted().joined(separator: ",")
    }

    var body: some View {
        let cols = Array(Set(items.compactMap(\.collection))).sorted()
        let shown = items.filter { it in
            (jump.isEmpty || it.id.hasSuffix(jump) || it.id == jump) && (collection == nil || it.collection == collection) &&
            (view == "fav" ? has(favs, it.id) : view == "hidden" ? has(hides, it.id) : (!has(hides, it.id) && (view == "all" || it.tier == "featured")))
        }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                ForEach(shown.prefix(1500)) { it in
                    Button { open = it } label: {
                        AsyncImage(url: url(it)) { $0.resizable().scaledToFill() } placeholder: { Color(hex: 0x1a1610) }
                            .frame(height: 130).clipped()
                            .overlay(alignment: .topTrailing) { if has(favs, it.id) { Image(systemName: "star.fill").foregroundStyle(PLTone.house).padding(4) } }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(has(favs, it.id) ? "Unfavourite" : "Favourite", systemImage: "star") { favs = toggled(favs, it.id) }
                        Button(has(hides, it.id) ? "Show again" : "Hide", systemImage: "eye.slash") { hides = toggled(hides, it.id) }
                        Button("Copy the id", systemImage: "doc.on.doc") { UIPasteboard.general.string = it.id }
                    }
                }
            }
            .padding(4)
        }
        .gScreen()
        .navigationTitle("The Generated")
        .searchable(text: $jump, prompt: "Jump to # (e.g. 042)")
        .safeAreaInset(edge: .top) {
            Picker("View", selection: $view) { Text("Featured").tag("featured"); Text("All").tag("all"); Text("Favourites").tag("fav"); Text("Hidden").tag("hidden") }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6).background(.bar)
        }
        .toolbar { Menu { Picker("Collection", selection: $collection) { Text("All").tag(String?.none); ForEach(cols, id: \.self) { Text($0).tag(String?.some($0)) } } } label: { Image(systemName: "line.3.horizontal.decrease.circle") } }
        .task {
            guard items.isEmpty, let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "generated/manifest.json"), timeout: 60),
                  let m = try? JSONDecoder().decode(M.self, from: d) else { return }
            items = m.items
        }
        .sheet(item: $open) { it in
            NavigationStack {
                AsyncImage(url: url(it)) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .navigationTitle(it.id).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { open = nil }; if let u = url(it) { ShareLink(item: u) } }
            }
        }
    }

    private func url(_ it: Item) -> URL? { URL(string: LibraryData.shared.base(model) + "/generated/" + it.file) }
}

struct CinematicRoom: View {
    let model: AppModel
    struct Item: Decodable, Identifiable, Hashable { let id: String; let file: String; let collection: String?; let duration: Double? }
    struct M: Decodable { let items: [Item] }
    @State private var items: [Item] = []
    @State private var collection: String?
    @State private var open: Item?
    @AppStorage("pldev.cine.fav") private var favs = ""
    @AppStorage("pldev.cine.hide") private var hides = ""
    @State private var view = "all"
    private func has(_ list: String, _ id: String) -> Bool { list.split(separator: ",").contains(Substring(id)) }
    private func toggled(_ list: String, _ id: String) -> String {
        var s = Set(list.split(separator: ",").map(String.init)); if s.contains(id) { s.remove(id) } else { s.insert(id) }; return s.sorted().joined(separator: ",")
    }

    var body: some View {
        let cols = Array(Set(items.compactMap(\.collection))).sorted()
        let shown = items.filter { (collection == nil || $0.collection == collection) && (view == "fav" ? has(favs, $0.id) : view == "hidden" ? has(hides, $0.id) : !has(hides, $0.id)) }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
                ForEach(shown.prefix(1500)) { it in
                    Button { open = it } label: {
                        AsyncImage(url: poster(it)) { $0.resizable().scaledToFill() } placeholder: { Color(hex: 0x1a1610) }
                            .frame(height: 100).clipped()
                            .overlay(alignment: .bottomTrailing) {
                                if let d = it.duration { Text(Duration.seconds(d).formatted(.time(pattern: .minuteSecond))).font(.caption2.monospacedDigit()).padding(3).background(.black.opacity(0.5)).foregroundStyle(.white) }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(has(favs, it.id) ? "Unfavourite" : "Favourite", systemImage: "star") { favs = toggled(favs, it.id) }
                        Button(has(hides, it.id) ? "Show again" : "Hide", systemImage: "eye.slash") { hides = toggled(hides, it.id) }
                    }
                }
            }
            .padding(6)
        }
        .safeAreaInset(edge: .top) {
            Picker("View", selection: $view) { Text("All").tag("all"); Text("★").tag("fav"); Text("Hidden").tag("hidden") }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6).background(.bar)
        }
        .gScreen()
        .navigationTitle("The Cinematic")
        .toolbar { Menu { Picker("Collection", selection: $collection) { Text("All").tag(String?.none); ForEach(cols, id: \.self) { Text($0).tag(String?.some($0)) } } } label: { Image(systemName: "line.3.horizontal.decrease.circle") } }
        .task {
            guard items.isEmpty, let http = model.http, let d = try? await http.send(RequestPlan(origin: "gallery", path: "cinematic/manifest.json"), timeout: 60),
                  let m = try? JSONDecoder().decode(M.self, from: d) else { return }
            items = m.items
        }
        .fullScreenCover(item: $open) { it in
            NavigationStack {
                Group { if let u = video(it) { VideoPlayer(player: AVPlayer(url: u)).ignoresSafeArea() } else { ContentUnavailableView("No video for this one", systemImage: "film") } }
                    .toolbar { Button("Close") { open = nil } }
            }
        }
    }

    private func base() -> String { LibraryData.shared.base(model) }
    private func video(_ it: Item) -> URL? { URL(string: base() + "/media/cinematic/" + it.file) }
    private func poster(_ it: Item) -> URL? {
        URL(string: base() + "/cinematic-poster/" + it.file.replacingOccurrences(of: #"\.(mp4|mov)$"#, with: ".jpg", options: [.regularExpression, .caseInsensitive]))
    }
}

// MARK: - The vault (filed objects, by kind)

struct VaultRoom: View {
    let model: AppModel
    struct File: Decodable, Identifiable { let name: String; let key: String; let size: Int?; let uploaded: String?; var id: String { key } }
    struct L: Decodable { let groups: [String: [File]] }
    @State private var data = LibraryData.shared

    var body: some View {
        let byClass = Dictionary(grouping: data.items, by: \.class).mapValues(\.count)
        Loaded(load: {
            guard let http = model.http else { throw Console.Problem.notSetUp }
            return try JSONDecoder().decode(L.self, from: try await http.send(RequestPlan(origin: "gallery", path: "api/vault-list"), timeout: 60)).groups
        }) { groups, _ in
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        vaultTile("GENERATED", "\(byClass["still"] ?? 0)", "stills", .generated)
                        vaultTile("CINEMATIC", "\(byClass["cinematic"] ?? 0)", "scored and timelapse", .cinematic)
                        vaultTile("ARCHIVE", "\(byClass["archive-work"] ?? 0)", "the complete works", .archive)
                        vaultTile("CURVES", "LIVE", "the living set", .curves)
                        vaultTile("FORGE", "OPEN", "shader studio", .forge)
                        vaultTile("TOOLS", "REG", "provenance registry", .tools)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: { Text("Everything in one place. Open a folder, open a file.") }
                Section("What the library holds") {
                    ForEach(byClass.keys.sorted(), id: \.self) { k in LabeledContent(k, value: "\(byClass[k] ?? 0)") }
                }
                Section("Filed in the private vault") {
                    ForEach(groups.keys.sorted(), id: \.self) { g in
                        NavigationLink {
                            List(groups[g] ?? []) { f in
                                NavigationLink { GalleryCanvas(model: model, path: "api/vault/" + (f.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f.key), title: f.name) } label: {
                                    VStack(alignment: .leading) {
                                        Text(f.name).lineLimit(1)
                                        Text([f.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }, f.uploaded.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .navigationTitle(g)
                        } label: { LabeledContent(g, value: "\(groups[g]?.count ?? 0)") }
                    }
                }
            }
        }
        .gScreen()
        .navigationTitle("The Vault")
        .task { if data.items.isEmpty { try? await data.load(model: model) } }
    }

    private func vaultTile(_ kind: String, _ big: String, _ line: String, _ room: GalleryRoom) -> some View {
        NavigationLink { room.view(model) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind).gEyebrow(9.5).foregroundStyle(PLG.goldDim(.dark))
                Text(big).font(.system(size: 28, weight: .regular, design: .serif).italic()).monospacedDigit().foregroundStyle(PLG.gold)
                Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.dim(.dark))
            }
            .gCard(padding: 12, radius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Printful triage

struct PrintfulRoom: View {
    let model: AppModel
    struct T: Decodable, Identifiable { let id: Int; let t: String?; let c: String?; let s: String?; let m: String?; let dead: Bool? }
    struct M: Decodable { let items: [T] }
    struct Triage: Decodable { let hearted: [String]; let deleted: [String] }
    @State private var items: [T] = []
    @State private var hearted = Set<String>()
    @State private var deleted = Set<String>()
    @State private var view = "review"
    @State private var showDead = false
    @State private var search = ""

    var body: some View {
        let shown = items.filter { t in
            let k = String(t.id)
            let inView = view == "review" ? !hearted.contains(k) && !deleted.contains(k) : view == "hearted" ? hearted.contains(k) : view == "deleted" ? deleted.contains(k) : true
            return inView && (showDead || t.dead != true) && (search.isEmpty || (t.t ?? "").localizedCaseInsensitiveContains(search))
        }
        List(shown) { t in
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: t.m ?? "")) { $0.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.1) }.frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.t ?? "").font(.headline)
                    Text([t.c, t.s].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    if t.dead == true { Text("Discontinued").font(.caption2).foregroundStyle(PLTone.house) }
                }
                Spacer()
                if hearted.contains(String(t.id)) { Image(systemName: "heart.fill").foregroundStyle(PLG.gold) }
            }
            .swipeActions(edge: .trailing) { Button("Heart") { Task { await act(t, "heart") } }.tint(PLTone.house) }
            .swipeActions(edge: .leading) {
                Button("Delete", role: .destructive) { Task { await act(t, "delete") } }
                Button("Clear") { Task { await act(t, "clear") } }.tint(.gray)
            }
        }
        .gScreen()
        .searchable(text: $search, prompt: "Template")
        .navigationTitle("What Survives")
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Seven hundred pieces sat unpublished when the old storefront closed. Heart what comes home to Psyched Luxuries, delete what doesn't; what you leave alone gets drafted.")
                    .font(.footnote).foregroundStyle(.secondary).plReading()
                Picker("View", selection: $view) { Text("To review").tag("review"); Text("♥").tag("hearted"); Text("Deleted").tag("deleted"); Text("All").tag("all") }
            }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6).background(.bar)
        }
        .toolbar { Toggle("Show the dead", isOn: $showDead) }
        .task {
            guard let http = model.http else { return }
            if items.isEmpty, let d = try? await http.send(RequestPlan(origin: "gallery", path: "printful-templates.json"), timeout: 60),
               let m = try? JSONDecoder().decode(M.self, from: d) { items = m.items }
            if let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/printful-triage")), let t = try? JSONDecoder().decode(Triage.self, from: d) {
                hearted = Set(t.hearted); deleted = Set(t.deleted)
            }
        }
    }

    private func act(_ t: T, _ action: String) async {
        guard let http = model.http else { return }
        let body = try? JSONSerialization.data(withJSONObject: ["id": String(t.id), "action": action])
        if let d = try? await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/printful-triage",
                                                    headers: ["content-type": "application/json", "Origin": LibraryData.shared.base(model)], body: body), idempotent: false),
           let r = try? JSONDecoder().decode(Triage.self, from: d) { hearted = Set(r.hearted); deleted = Set(r.deleted) }
    }
}

// MARK: - Classify the archive (public/classify, through the PL DEV door)

struct ClassifyRoom: View {
    let model: AppModel
    struct Piece: Decodable, Identifiable { let cr: String; let title: String?; let thumb: String?; let url: String?; let conf: String?; var id: String { cr } }
    struct M: Decodable { let pieces: [Piece] }
    struct Progress: Decodable { let reviewed: Int?; let reviewed_crs: [String]? }
    @State private var queue: [Piece] = []
    @State private var reviewed = 0
    @State private var title = ""
    @State private var year = ""
    @State private var pillar = ""
    @State private var cat = ""
    @State private var medium = ""
    @State private var body_ = ""
    @State private var shareable = true
    @State private var result: String?
    @State private var confirmPublish = false
    @State private var busy = false
    private let pillars = ["Art", "Philosophy", "Process", "Proof"]
    private let cats = [("Digital", "digital"), ("Seeds", "seeds"), ("Finished", "finished_works"), ("Studies", "studies")]
    private let media = ["Digital", "Physical"]
    private let bodies = ["Commercial", "Fine Art", "Interference"]

    private var cur: Piece? { queue.first }
    private var valid: Bool {
        let y = Int(year); return !title.trimmingCharacters(in: .whitespaces).isEmpty && (year.isEmpty || (y != nil && (2009...2030).contains(y!))) && !pillar.isEmpty && !cat.isEmpty && !medium.isEmpty && !body_.isEmpty
    }

    var body: some View {
        Form {
            Section { LabeledContent("Classified", value: "\(reviewed)"); LabeledContent("Left", value: "\(queue.count)") }
            if let p = cur {
                Section {
                    AsyncImage(url: URL(string: p.thumb ?? p.url ?? "")) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 300)
                    Text(p.cr).font(.caption).foregroundStyle(.secondary)
                    TextField("Title", text: $title)
                    TextField("Year (optional, 2009 to 2030)", text: $year).keyboardType(.numberPad)
                }
                Section {
                    Picker("Pillar", selection: $pillar) { Text("Choose").tag(""); ForEach(pillars, id: \.self) { Text($0).tag($0) } }
                    Picker("Category", selection: $cat) { Text("Choose").tag(""); ForEach(cats, id: \.1) { Text($0.0).tag($0.1) } }
                    Picker("Medium", selection: $medium) { Text("Choose").tag(""); ForEach(media, id: \.self) { Text($0).tag($0) } }
                    Picker("Body of work", selection: $body_) { Text("Choose").tag(""); ForEach(bodies, id: \.self) { Text($0).tag($0) } }
                    Toggle("Shareable", isOn: $shareable)
                } footer: { Text("The body of work is your designation; the classifier never guesses it for you.") }
                Section {
                    Button(busy ? "Saving…" : "Save and next") { Task { await save(p) } }.disabled(!valid || busy).bold()
                    Button("Skip for now") { queue.append(queue.removeFirst()); load(queue.first) }.disabled(busy)
                }
            } else if !busy {
                Section { Text("Every piece is classified. Publish to push them to the live manifest.") }
            }
            if let r = result { Section { ResultLine(text: r) } }
            Section { Button("Publish…") { confirmPublish = true } } footer: { Text("Publishing rewrites the live archive manifest from what you classified.") }
        }
        .gScreen()
        .navigationTitle("Classify")
        .task { await boot() }
        .confirmationDialog("Publish the classified archive to the live manifest?", isPresented: $confirmPublish, titleVisibility: .visible) {
            Button("Publish") { Task { await publish() } }
        }
    }

    private func load(_ p: Piece?) { title = p?.title ?? ""; year = ""; pillar = ""; cat = ""; medium = ""; body_ = ""; shareable = true }

    private func boot() async {
        busy = true; defer { busy = false }
        guard let r = try? await URLSession.shared.data(from: URL(string: "https://assets.psychedluxuries.com/manifest.json")!),
              let m = try? JSONDecoder().decode(M.self, from: r.0),
              let prog = try? await Console.get("api/archive/progress", Progress.self, model: model) else { result = "Not loaded. Pull back and try again."; return }
        let done = Set(prog.reviewed_crs ?? [])
        reviewed = prog.reviewed ?? done.count
        let rank = ["low": 0, "medium": 1, "high": 2]
        queue = m.pieces.filter { !done.contains($0.cr) }.sorted { (rank[$0.conf ?? ""] ?? 3, $0.cr) < (rank[$1.conf ?? ""] ?? 3, $1.cr) }
        load(queue.first)
    }

    private func save(_ p: Piece) async {
        busy = true; defer { busy = false }
        var payload: [String: Any] = ["cr": p.cr, "title": title.trimmingCharacters(in: .whitespaces), "pillar": pillar, "cat": cat, "medium": medium, "body": body_, "shareable": shareable, "dup": false]
        if let y = Int(year) { payload["year"] = y } else { payload["year"] = NSNull() }
        do {
            try await Console.post("api/archive/classify", payload, model: model)
            queue.removeAll { $0.cr == p.cr }; reviewed += 1; load(queue.first); result = "Saved \(p.cr)."
        } catch { result = "Not saved. \(plainSentence(error))" }
    }

    private func publish() async {
        busy = true; defer { busy = false }
        do { try await Console.post("api/archive/publish", ["confirm": true], model: model, timeout: 120); result = "Published to the live manifest." }
        catch { result = "Not published. \(error.localizedDescription)" }
    }
}

// MARK: - Design Kit, tools

struct KitRoom: View {
    let model: AppModel
    struct Palette: Decodable, Identifiable { let name: String; let ground: String?; let text: String?; let key: String?; let accent: String?; let use: String?; var id: String { name } }
    struct Named: Decodable, Identifiable { let name: String; let role: String?; let use: String?; let kind: String?; var id: String { name } }
    struct Colors: Decodable { let palettes: [Palette]? }
    struct Kit: Decodable { let colors: Colors?; let fonts: [Named]?; let symbols: [Named]?; let icons: [Named]?; let patterns: [Named]?; let layouts: [Named]? }

    var body: some View {
        Loaded(load: {
            guard let http = model.http else { throw Console.Problem.notSetUp }
            return try JSONDecoder().decode(Kit.self, from: try await http.send(RequestPlan(origin: "gallery", path: "kit.json"), timeout: 60))
        }) { k, _ in
            List {
                Section("Palettes") {
                    ForEach(k.colors?.palettes ?? []) { p in
                        HStack {
                            HStack(spacing: 0) { ForEach([p.ground, p.text, p.key, p.accent].compactMap { $0 }, id: \.self) { Rectangle().fill(Color(hex: $0) ?? .clear) } }
                                .frame(width: 96, height: 28).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading) { Text(p.name); if let u = p.use { Text(u).font(.caption).foregroundStyle(.secondary) } }
                        }
                    }
                }
                group("Fonts", k.fonts); group("Symbols", k.symbols); group("Icons", k.icons); group("Patterns", k.patterns); group("Layouts", k.layouts)
            }
        }
        .gScreen()
        .navigationTitle("Design Kit")
    }

    @ViewBuilder private func group(_ title: String, _ items: [Named]?) -> some View {
        if let items, !items.isEmpty {
            Section(title) {
                ForEach(items) { n in VStack(alignment: .leading) { Text(n.name); if let u = n.use ?? n.role { Text(u).font(.caption).foregroundStyle(.secondary) } } }
            }
        }
    }
}

struct ToolsRoom: View {
    let model: AppModel
    @State private var data = LibraryData.shared
    @State private var search = ""
    var body: some View {
        let pieces = data.items.filter { ($0.class == "code-piece" || $0.class == "lab") && (search.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(search) || $0.item_id.localizedCaseInsensitiveContains(search)) }
        List {
            Section { Text("Every piece's full code, from /api/source. Touch a piece to read it, or share it.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(pieces) { p in
                NavigationLink { SourceView(model: model, id: p.item_id) } label: {
                    VStack(alignment: .leading) { Text(p.name ?? p.item_id); Text(p.item_id).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
            }
        }
        .gScreen()
        .searchable(text: $search, prompt: "Piece")
        .navigationTitle("Tools and source")
        .task { if data.items.isEmpty { try? await data.load(model: model) } }
    }
}
