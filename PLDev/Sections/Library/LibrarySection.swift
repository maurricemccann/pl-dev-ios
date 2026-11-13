import SwiftUI
import UserNotifications

/// The index and the marks, loaded once and shared by Library and Curate. A failed marks load is an error, never "nothing marked".
@MainActor @Observable final class LibraryData {
    static let shared = LibraryData()
    private(set) var items: [LibraryItem] = []
    var marks: [String: TasteMark] = [:]
    private(set) var marksLoaded = false
    private(set) var loading = false
    var notSaved = 0

    func load(model: AppModel, force: Bool = false) async throws {
        guard let http = model.http else { throw URLError(.notConnectedToInternet) }
        if loading { return }
        loading = true; defer { loading = false }
        if items.isEmpty || force {
            URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)   // 9.5k tiles: keep them on disk
            let data = try await http.send(RequestPlan(origin: "gallery", path: "library-index.json"), timeout: 60)
            struct Index: Decodable { let items: [LibraryItem] }
            items = try await Task.detached { try JSONDecoder().decode(Index.self, from: data).items }.value
        }
        let tdata = try await http.send(RequestPlan(origin: "gallery", path: "api/taste"), timeout: 60)
        struct Taste: Decodable { let marks: [String: TasteMark]? }
        guard let m = try await Task.detached(operation: { try JSONDecoder().decode(Taste.self, from: tdata).marks }).value else {
            marksLoaded = false
            throw URLError(.cannotParseResponse)
        }
        marks = m
        marksLoaded = true
    }

    func base(_ model: AppModel) -> String {
        var b = model.config?.origin("gallery")?.base ?? ""
        if b.hasSuffix("/") { b.removeLast() }
        return b
    }

    /// One write to /api/taste. Counts a failure instead of hiding it.
    func post(_ body: [String: String], model: AppModel) async -> Bool {
        guard marksLoaded, let http = model.http, let data = try? JSONSerialization.data(withJSONObject: body) else { notSaved += 1; return false }
        do {
            _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/taste",
                                                headers: ["content-type": "application/json", "Origin": base(model)], body: data),
                                    idempotent: false)
            return true
        } catch { notSaved += 1; return false }
    }

    /// Where a piece's picture or clip lives on the gallery.
    func media(_ it: LibraryItem, model: AppModel) -> (still: URL?, video: URL?) {
        let b = base(model)
        func u(_ p: String) -> URL? { URL(string: b + (p.hasPrefix("/") ? p : "/" + p)) }
        let file = (it.src?.split(separator: "/").last.map(String.init)) ?? it.name ?? ""
        switch it.class {
        case "still", "font": return (it.name.flatMap { u("/generated/" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)) }, nil)
        case "archive-work": return ((it.sub ?? "").contains("· edited") ? u("/archive-edits/ba/\(it.item_id).jpg") : it.src.flatMap(u), nil)
        case "code-piece": return (it.src?.hasPrefix("/thumbs/") == true ? u(it.src!) : nil, nil)
        case "cinematic":
            let poster = file.replacingOccurrences(of: #"\.(mp4|mov)$"#, with: ".jpg", options: [.regularExpression, .caseInsensitive])
            return (u("/cinematic-poster/" + poster), u("/media/cinematic/" + file))
        default: return (nil, nil)
        }
    }
}

/// Library: every piece with its verdict; filter by verdict, class and name; open one full screen to mark it.
@MainActor enum LibrarySection: PLSection {
    static let manifest = SectionManifest(id: "library", title: "Library", symbol: "square.grid.3x3", needsKeys: ["vault"], needsOrigins: ["gallery"])
    static func makeRoot(model: AppModel) -> AnyView { AnyView(LibraryView(model: model)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

enum Verdict: String, CaseIterable, Identifiable {
    case all = "All", unmarked = "Unmarked", keep = "Keep", fav = "Favourite", maybe = "Maybe", cut = "Cut", replaced = "Replaced"
    var id: String { rawValue }
    func matches(_ m: TasteMark?) -> Bool {
        switch self {
        case .all: return true
        case .unmarked: return m == nil || m?.v == ""
        case .keep: return m?.v == "keep" && m?.note != "fav"
        case .fav: return m?.isFav == true
        case .maybe: return m?.v == "maybe"
        case .cut: return m?.v == "cut"
        case .replaced: return m?.v == "replaced"
        }
    }
}

struct LibraryView: View {
    let model: AppModel
    @State private var data = LibraryData.shared
    @State private var verdict: Verdict = .all
    @State private var cls: String? = nil
    @State private var search = ""
    @State private var failed = false
    @State private var open: LibraryItem?
    private let classes: [(String?, String)] = [(nil, "All classes"), ("still", "Stills"), ("cinematic", "Shorts"), ("code-piece", "Code"), ("font", "Fonts"), ("archive-work", "Archive")]

    /// Archive works stay hidden unless the class filter picks them; unrenderable pieces never show. Newest batch first.
    private var shown: [LibraryItem] {
        let q = search.lowercased()
        return data.items.filter { it in
            (cls == nil ? it.class != "archive-work" : it.class == cls) && !it.tagList.contains("unrenderable")
                && verdict.matches(data.marks[it.vault_id])
                && (q.isEmpty || (it.name ?? "").lowercased().contains(q) || it.vault_id.lowercased().contains(q))
        }.sorted { ($0.batch ?? "") > ($1.batch ?? "") }
    }

    private func count(_ v: Verdict) -> Int {
        data.items.filter { (cls == nil ? $0.class != "archive-work" : $0.class == cls) && v.matches(data.marks[$0.vault_id]) }.count
    }

    var body: some View {
        let list = shown
        ScrollView {
            if failed {
                ContentUnavailableView("YOUR MARKS DID NOT LOAD", systemImage: "exclamationmark.triangle", description: Text("Nothing can be marked until they do. Pull to try again."))
            } else if data.items.isEmpty {
                ProgressView("Loading the library…").padding(.top, 80)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                ForEach(list) { it in
                    Button { open = it } label: { Tile(item: it, mark: data.marks[it.vault_id], url: data.media(it, model: model).still) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Name or id")
        .safeAreaInset(edge: .top) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Menu { Picker("Class", selection: $cls) { ForEach(classes, id: \.1) { Text($0.1).tag($0.0) } } }
                        label: { Label(classes.first { $0.0 == cls }?.1 ?? "Class", systemImage: "line.3.horizontal.decrease") }
                        .buttonStyle(.bordered)
                    ForEach(Verdict.allCases) { v in
                        Button("\(v.rawValue) \(count(v))") { verdict = v }
                            .buttonStyle(.bordered).tint(verdict == v ? .accentColor : .secondary)
                    }
                }.padding(.horizontal)
            }.padding(.vertical, 4).background(.bar)
        }
        .overlay(alignment: .bottom) {
            if data.notSaved > 0 { Text("\(data.notSaved) NOT SAVED").font(.caption.bold()).padding(8).background(.red, in: Capsule()).foregroundStyle(.white).padding() }
        }
        .refreshable { await reload(force: true) }
        .task { if data.items.isEmpty || !data.marksLoaded { await reload(force: false) } }
        .fullScreenCover(item: $open) { it in PieceViewer(model: model, list: list, start: it) }
    }

    private func reload(force: Bool) async {
        do { try await data.load(model: model, force: force); failed = false } catch { failed = true }
    }
}

struct Tile: View {
    let item: LibraryItem
    let mark: TasteMark?
    let url: URL?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.secondary.opacity(0.12)
            if let url { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            else { Text(item.name ?? item.vault_id).font(.caption2).padding(4) }
            if let c = dot { Circle().fill(c).frame(width: 10, height: 10).padding(6) }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private var dot: Color? {
        guard let m = mark else { return nil }
        if m.isFav { return .orange }
        switch m.v { case "keep": return .green; case "maybe": return .yellow; case "cut": return .red; default: return nil }
    }
}

/// Full screen: swipe between pieces, mark each. Favourite = keep with the note "fav"; tapping the active verdict clears it;
/// a favourite is never overwritten by a plain keep.
struct PieceViewer: View {
    let model: AppModel
    let list: [LibraryItem]
    @State var selection: String
    @State private var data = LibraryData.shared
    @State private var comment = ""
    @State private var tick = 0
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, list: [LibraryItem], start: LibraryItem) {
        self.model = model; self.list = list; _selection = State(initialValue: start.vault_id)
    }

    private var current: LibraryItem? { list.first { $0.vault_id == selection } }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(list) { it in
                    let m = data.media(it, model: model)
                    Group {
                        if let v = m.video { LoopingClip(url: v) }
                        else if let s = m.still { AsyncImage(url: s) { $0.resizable().scaledToFit() } placeholder: { ProgressView() } }
                        else { Text(it.name ?? it.vault_id) }
                    }
                    .tag(it.vault_id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(current?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .onChange(of: selection, initial: true) { _, id in comment = data.marks[id]?.comment ?? "" }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            TextField("Comment", text: $comment, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                .onSubmit { saveComment() }
            HStack {
                mark("Cut", "cut", .red); mark("Maybe", "maybe", .yellow); mark("Keep", "keep", .green); mark("Fav", "fav", .orange)
            }
        }
        .padding().background(.bar)
    }

    private func isActive(_ v: String) -> Bool {
        let m = data.marks[selection]
        return v == "fav" ? m?.isFav == true : (m?.v == v && !(v == "keep" && m?.isFav == true))
    }

    private func mark(_ label: String, _ v: String, _ tint: Color) -> some View {
        Button(label) { Task { await set(v) } }
            .buttonStyle(.borderedProminent).tint(isActive(v) ? tint : tint.opacity(0.35))
            .frame(maxWidth: .infinity)
    }

    private func set(_ v: String) async {
        let id = selection, prev = data.marks[id]
        saveComment()
        if isActive(v) {   // tapping the active verdict clears it
            data.marks[id] = nil
            if await !data.post(["id": id, "v": "clear"], model: model) { data.marks[id] = prev }
        } else if v == "fav" {
            data.marks[id] = TasteMark(v: "keep", note: "fav", comment: prev?.comment)
            if await !data.post(["id": id, "v": "keep", "note": "fav"], model: model) { data.marks[id] = prev }
        } else {
            data.marks[id] = TasteMark(v: v, comment: prev?.comment)
            if await !data.post(["id": id, "v": v], model: model) { data.marks[id] = prev }
        }
        tick += 1
    }

    private func saveComment() {
        let id = selection, t = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != (data.marks[id]?.comment ?? "") else { return }
        data.marks[id, default: TasteMark(v: "")].comment = t
        Task { _ = await data.post(["only": "comment", "id": id, "comment": String(t.prefix(1000))], model: model) }
    }
}
