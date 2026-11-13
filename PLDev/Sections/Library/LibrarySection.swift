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
        await MarkOutbox.flush(model: model)   // marks made offline go first, so the fresh marks below include them
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
        LibraryGlanceWriter.publish(self)   // the Curate widget's numbers
    }

    func base(_ model: AppModel) -> String {
        var b = model.config?.origin("gallery")?.base ?? ""
        if b.hasSuffix("/") { b.removeLast() }
        return b
    }

    /// One write to /api/taste. Offline, the mark waits in the outbox (and counts as made); any other failure is counted, never hidden.
    func post(_ body: [String: String], model: AppModel) async -> Bool {
        guard marksLoaded, let http = model.http, let data = try? JSONSerialization.data(withJSONObject: body) else { notSaved += 1; return false }
        if !OfflineState.shared.online { MarkOutbox.add(body); return true }
        do {
            _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/taste",
                                                headers: ["content-type": "application/json", "Origin": base(model)], body: data),
                                    idempotent: false)
            return true
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut].contains(e.code) {
            MarkOutbox.add(body); return true
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
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first, let room = GalleryRoom(rawValue: first) { GalleryNav.shared.room = room }
        return true
    }
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
    @State private var nav = GalleryNav.shared
    @State private var verdict: Verdict = .all
    @State private var cls: String? = nil
    @State private var search = ""
    @State private var failed = false
    @State private var open: LibraryItem?
    @State private var batch: String?
    @State private var source: String?
    @State private var selecting = false
    @State private var picked = Set<String>()
    @State private var tagName = ""
    @State private var askTag = false
    @State private var bulkTick = 0
    private let classes: [(String?, String)] = [(nil, "All classes"), ("still", "Stills"), ("cinematic", "Shorts"), ("code-piece", "Code"), ("font", "Fonts"), ("archive-work", "Archive")]

    /// Archive works stay hidden unless the class filter picks them; unrenderable pieces never show. Newest batch first.
    private var shown: [LibraryItem] {
        let q = search.lowercased()
        return data.items.filter { it in
            (cls == nil ? it.class != "archive-work" : it.class == cls) && !it.tagList.contains("unrenderable")
                && verdict.matches(data.marks[it.vault_id])
                && (batch == nil || it.batch == batch) && (source == nil || it.source == source)
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
            if !data.items.isEmpty { shelf }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                ForEach(list) { it in
                    Button { if selecting { toggle(it.vault_id) } else { open = it } } label: {
                        Tile(item: it, mark: data.marks[it.vault_id], url: data.media(it, model: model).still)
                            .overlay(alignment: .bottomTrailing) {
                                if selecting {
                                    Image(systemName: picked.contains(it.vault_id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(.white, picked.contains(it.vault_id) ? Color.accentColor : .black.opacity(0.3)).padding(6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { GalleryRoomsView(model: model) } label: { Label("Rooms", systemImage: "square.grid.2x2") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") { withAnimation { selecting.toggle(); picked.removeAll() } }
            }
            if selecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu("\(picked.count) chosen") {
                        Button("Choose all shown") { picked = Set(list.map(\.vault_id)) }
                        Button("Choose none") { picked.removeAll() }
                        Button("Tag…", systemImage: "tag") { askTag = true }
                    }
                    Spacer()
                    Button { Task { await bulk("cut") } } label: { Image(systemName: "xmark") }.tint(.red).accessibilityLabel("Cut")
                    Button { Task { await bulk("maybe") } } label: { Image(systemName: "questionmark") }.tint(.yellow).accessibilityLabel("Maybe")
                    Button { Task { await bulk("keep") } } label: { Image(systemName: "checkmark") }.tint(.green).accessibilityLabel("Keep")
                    Button { Task { await bulk("fav") } } label: { Image(systemName: "star.fill") }.tint(.orange).accessibilityLabel("Favourite")
                    Button { Task { await bulk("clear") } } label: { Image(systemName: "eraser") }.accessibilityLabel("Clear the mark")
                }
            }
        }
        .alert("Tag \(picked.count) pieces", isPresented: $askTag) {
            TextField("tag (a-z, 0-9, dashes)", text: $tagName).textInputAutocapitalization(.never)
            Button("Add the tag") { Task { await tag(add: true) } }
            Button("Remove the tag") { Task { await tag(add: false) } }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: bulkTick)
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
        .navigationDestination(item: $nav.room) { room in room.view(model) }
    }

    /// The web Library's "Latest batches" shelf (the ten newest, with what is new, kept, maybe and cut) and the source chips.
    private var shelf: some View {
        let batches = Array(Set(data.items.compactMap(\.batch))).sorted(by: >).prefix(10)
        return VStack(alignment: .leading, spacing: 8) {
            Text("LATEST BATCHES").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(batches), id: \.self) { b in
                        let its = data.items.filter { $0.batch == b }
                        let n = its.filter { data.marks[$0.vault_id] == nil }.count, k = its.filter { data.marks[$0.vault_id]?.v == "keep" }.count
                        let m = its.filter { data.marks[$0.vault_id]?.v == "maybe" }.count, c = its.filter { data.marks[$0.vault_id]?.v == "cut" }.count
                        Button { batch = batch == b ? nil : b } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b).font(.caption.monospaced().weight(.semibold))
                                Text("\(n) new · \(k)✓ \(m)~ \(c)×").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(batch == b ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach([("cloud-batch", "Cloud batches"), ("on-model", "API renders")], id: \.0) { s in
                        Button { source = source == s.0 ? nil : s.0 } label: {
                            Text("\(s.1) \(data.items.filter { $0.source == s.0 }.count)").font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(source == s.0 ? Color.orange.opacity(0.3) : Color.orange.opacity(0.1), in: Capsule())
                                .overlay(Capsule().stroke(Color.orange.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 6).padding(.top, 6)
    }

    private func toggle(_ id: String) { if picked.contains(id) { picked.remove(id) } else { picked.insert(id) } }

    /// Many marks at once, 50 to a write as the web sends them. Optimistic; a refused batch is put back.
    private func bulk(_ v: String) async {
        let ids = Array(picked)
        guard !ids.isEmpty, data.marksLoaded, let http = model.http else { return }
        let before = ids.map { ($0, data.marks[$0]) }
        for id in ids {
            switch v {
            case "clear": data.marks[id] = nil
            case "fav": data.marks[id] = TasteMark(v: "keep", note: "fav", comment: data.marks[id]?.comment)
            default: data.marks[id] = TasteMark(v: v, comment: data.marks[id]?.comment)
            }
        }
        var refused: [String] = []
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            let marks: [[String: String]] = chunk.map { v == "fav" ? ["id": $0, "v": "keep", "note": "fav"] : ["id": $0, "v": v] }
            guard let body = try? JSONSerialization.data(withJSONObject: ["marks": marks]) else { continue }
            do {
                _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/taste",
                                                    headers: ["content-type": "application/json", "Origin": data.base(model)], body: body), idempotent: false)
            } catch { refused += chunk }
        }
        if !refused.isEmpty { for id in refused { data.marks[id] = before[id] }; data.notSaved += 1 }
        picked.removeAll(); bulkTick += 1
    }

    private func tag(add: Bool) async {
        let t = tagName.lowercased().trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^[a-z0-9-]{1,24}$"#, options: .regularExpression) != nil, let http = model.http else { return }
        let body = try? JSONSerialization.data(withJSONObject: ["ids": Array(picked.prefix(500)), (add ? "add" : "remove"): t])
        if (try? await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/tags", headers: ["content-type": "application/json"], body: body), idempotent: false)) == nil {
            data.notSaved += 1
        }
        tagName = ""; bulkTick += 1
    }

    private func reload(force: Bool) async {
        do { try await data.load(model: model, force: force); failed = false } catch { failed = true }
    }
}

/// A library tile as the web draws it: the piece, its name, a play badge on clips, the mark's dot, an orange ring on cloud and API renders.
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
        .overlay(alignment: .topLeading) {
            if item.class == "cinematic" || item.class == "code-piece" {
                Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(5).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4)).padding(5)
            }
        }
        .overlay(alignment: .bottom) {
            Text(item.name ?? item.vault_id).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.white)
                .lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange, lineWidth: item.source == "cloud-batch" || item.source == "on-model" ? 2 : 0))
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let it = current, let u = data.media(it, model: model).video ?? data.media(it, model: model).still {
                    ToolbarItem(placement: .primaryAction) { ShareLink(item: u) }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .onChange(of: selection, initial: true) { _, id in comment = data.marks[id]?.comment ?? "" }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom) {
                TextField("Comment", text: $comment, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                    .onSubmit { saveComment() }
                Button("Save") { saveComment() }.buttonStyle(.bordered)
            }
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
