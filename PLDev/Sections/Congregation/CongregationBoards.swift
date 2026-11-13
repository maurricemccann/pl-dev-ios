import SwiftUI

// Saving to boards and choosing visuals, as the site does: the Save button under any post or piece, the member's boards
// (collections), the picker that pairs a post with a visual chosen from the archive, and the picker for the works a profile shows.

@MainActor @Observable final class BoardsModel {
    static let shared = BoardsModel()

    struct Board: Decodable, Identifiable, Hashable { let id: String; let name: String; let items: Int; let cover: String? }
    struct Item: Decodable, Identifiable, Hashable {
        let refType: String
        let refId: String
        let mediaUrl: String?
        var id: String { refType + "|" + refId }
    }
    private struct BoardsReply: Decodable { let boards: [Board] }
    private struct ItemsReply: Decodable { let items: [Item] }

    var boards: [Board] = []
    var boardsLoaded = false
    var failure: String?
    /// What is in the default "Saved" board, as `type|id`, so a Save button shows what is already saved.
    private(set) var saved: Set<String> = []
    private var savedLoaded = false

    func isSaved(_ type: String, _ id: String) -> Bool { saved.contains(type + "|" + id) }

    func loadBoards() async {
        do { boards = try await Site.get("api/account/boards", BoardsReply.self).boards; boardsLoaded = true; failure = nil }
        catch { if !boardsLoaded { failure = error.localizedDescription } }
    }

    /// Once per launch: reads the Saved board so every Save button starts true to the site.
    func loadSaved() async {
        guard !savedLoaded, SiteAccount.shared.signedIn else { return }
        await loadBoards()
        guard let board = boards.first(where: { $0.name == "Saved" }) ?? boards.first else { return }
        if let r = try? await Site.get("api/account/boards/items", ItemsReply.self, query: ["board": board.id]) {
            saved = Set(r.items.map(\.id)); savedLoaded = true
        }
    }

    /// Nil on success, else the site's sentence. Optimistic: the mark changes at once and comes back on a refusal.
    func toggle(_ type: String, _ id: String, media: String?) async -> String? {
        let key = type + "|" + id
        let adding = !saved.contains(key)
        if adding { saved.insert(key) } else { saved.remove(key) }
        do {
            try await Site.post("api/account/boards/items", ["refType": type, "refId": id, "mediaUrl": media ?? "", "action": adding ? "add" : "remove"])
            return nil
        } catch {
            if adding { saved.remove(key) } else { saved.insert(key) }
            return error.localizedDescription
        }
    }

    func items(_ board: Board) async -> [Item]? {
        (try? await Site.get("api/account/boards/items", ItemsReply.self, query: ["board": board.id]))?.items
    }

    func create(_ name: String) async -> String? {
        do { try await Site.post("api/account/boards", ["name": name]); await loadBoards(); return nil }
        catch { return error.localizedDescription }
    }
}

/// `✧ save` under a post or a piece: one tap into the Saved board, a second takes it out.
struct SaveButton: View {
    let refType: String
    let refId: String
    var mediaURL: String? = nil
    private let boards = BoardsModel.shared
    @State private var busy = false
    @State private var tick = 0

    var body: some View {
        if SiteAccount.shared.signedIn {
            let on = boards.isSaved(refType, refId)
            Button {
                busy = true
                Task { _ = await boards.toggle(refType, refId, media: mediaURL); tick += 1; busy = false }
            } label: {
                Text(on ? "\u{2726} saved" : "\u{2727} save").font(SiteFont.body(11, relativeTo: .caption, weight: .medium)).textCase(.uppercase).tracking(2)
                    .foregroundStyle(on ? Bone.goldDim : Bone.inkFaint(.light)).frame(minHeight: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(busy)
            .accessibilityLabel(on ? "Saved. Tap to remove from your boards" : "Save to your boards")
            .sensoryFeedback(PLHaptic.select, trigger: tick)
            .task { await boards.loadSaved() }
        }
    }
}

// MARK: - Boards (the owner's tab)

struct BoardsPanel: View {
    private let model = BoardsModel.shared
    @State private var open: BoardsModel.Board?
    @State private var items: [BoardsModel.Item]?
    @State private var newName = ""
    @State private var line: String?
    @State private var lightbox: LightboxItem?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let board = open { boardView(board) } else { list }
        }
        .task { await model.loadBoards() }
        .fullScreenCover(item: $lightbox) { Lightbox(item: $0) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                TextField("New board name", text: $newName).siteField().submitLabel(.done)
                    .onSubmit { Task { await create() } }
                Button("Create") { Task { await create() } }.buttonStyle(SiteGhost()).frame(maxWidth: 120)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            SiteNote(text: line)
            if !model.boardsLoaded {
                if let f = model.failure { SiteEmpty(title: "Could not load your boards", detail: f, actionTitle: "Try again") { Task { await model.loadBoards() } } }
                else { SitePulse() }
            } else if model.boards.isEmpty {
                SiteEmpty(title: "No boards yet", detail: "Save a visual from the feed or the archive to start one.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.boards) { b in
                        Button { openBoard(b) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Color(Bone.raised(scheme)).aspectRatio(1, contentMode: .fit).overlay {
                                    if let c = b.cover, let u = URL(string: c) {
                                        AsyncImage(url: u) { p in if case .success(let i) = p { i.resizable().scaledToFill() } else { Color.clear } }
                                    } else { Text("empty").siteLabel(10) }
                                }.clipped()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name).font(SiteFont.body(14)).foregroundStyle(Bone.ink(scheme)).lineLimit(1)
                                    Text("\(b.items) saved").siteLabel(10)
                                }.padding(.horizontal, 10).padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func boardView(_ board: BoardsModel.Board) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteAction(title: "\u{2190} boards", tone: .faint) { open = nil; items = nil }
            Text(board.name).font(SiteFont.display(26)).foregroundStyle(Bone.ink(scheme))
            if let items {
                if items.isEmpty { SiteEmpty(title: "Empty board", detail: "Save visuals from the feed and the archive.") }
                else {
                    Masonry(items: items, columns: 2, spacing: 8) { it in
                        Group {
                            if let m = it.mediaUrl, let u = URL(string: m) {
                                Button { lightbox = LightboxItem(src: u, caption: it.refId) } label: {
                                    AsyncImage(url: u) { p in
                                        if case .success(let i) = p { i.resizable().scaledToFit() } else { Bone.line(scheme).opacity(0.3).frame(height: 120) }
                                    }
                                }.buttonStyle(.plain)
                            } else {
                                Bone.raised(scheme).frame(height: 120).overlay { Text(it.refId).siteLabel(10) }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                    }
                }
            } else { SitePulse() }
        }
    }

    private func openBoard(_ b: BoardsModel.Board) {
        open = b; items = nil
        Task { items = await model.items(b) ?? [] }
    }

    private func create() async {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let err = await model.create(n) { line = "Not saved. \(err)" } else { newName = ""; line = nil }
    }
}

// MARK: - The visual picker (pairs a post with a chosen visual)

/// Members pair their words with a visual chosen from the archive, or a curve or image link. No upload: the curated set is the
/// guard (as on the site). Gives back the picture's address.
struct VisualPickerSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private let manifest = ArchiveManifest.shared
    @State private var query = ""
    @State private var link = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a visual").siteLabel(11)
                    HStack(spacing: 8) {
                        TextField("Paste a curve or image link", text: $link).siteField()
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button("Use") { pick(link.trimmingCharacters(in: .whitespaces)) }.buttonStyle(SiteGhost()).frame(maxWidth: 90)
                            .disabled(URL(string: link.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") != true)
                    }
                    TextField("\u{2026}or search the archive (code or title)", text: $query).siteField().autocorrectionDisabled()
                    if manifest.loading && manifest.pieces.isEmpty { SitePulse() }
                    else if manifest.failed { SiteEmpty(title: "The archive did not answer", detail: "Check your connection and try again.", actionTitle: "Try again") { Task { await manifest.load() } } }
                    else {
                        let found = manifest.search(query)
                        if found.isEmpty { SiteEmpty(title: "Nothing by that name") }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                            ForEach(found.prefix(80)) { p in
                                Button { pick(p.thumb) } label: {
                                    Color(Bone.raised(scheme)).aspectRatio(1, contentMode: .fit).overlay {
                                        AsyncImage(url: URL(string: p.thumb)) { ph in if case .success(let i) = ph { i.resizable().scaledToFill() } else { Color.clear } }
                                    }.clipped().overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
                                }.buttonStyle(.plain).accessibilityLabel("\(p.cr), \(p.title)")
                            }
                        }
                        if found.count > 80 { Text("Showing 80 of \(found.count). Search to narrow it.").siteLabel(10) }
                    }
                }
                .padding(20)
            }
            .siteScreen()
            .navigationTitle("A visual").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await manifest.load() }
        }
    }

    private func pick(_ s: String) { guard !s.isEmpty else { return }; onPick(s); dismiss() }
}

// MARK: - Chosen works (the profile's face)

struct ArtworkPicker: View {
    var onSaved: (() -> Void)? = nil
    private let manifest = ArchiveManifest.shared
    @State private var selected: [String] = []
    @State private var slots = 3
    @State private var query = ""
    @State private var saving = false
    @State private var line: String?
    @State private var loadedSelection = false
    @Environment(\.colorScheme) private var scheme

    private struct Chosen: Decodable { let crs: [String]?; let slots: Int? }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chosen works").siteLabel(11)
                Spacer()
                Text("\(selected.count) of \(slots)").font(SiteFont.body(11, relativeTo: .caption)).tracking(2.4).textCase(.uppercase)
                    .foregroundStyle(selected.count >= slots ? Bone.goldDim : Bone.inkFaint(scheme)).monospacedDigit()
            }
            Text("The art you choose becomes the face of your profile.").siteBody(13)
            TextField("Search by code or title\u{2026}", text: $query).siteField().autocorrectionDisabled()
            if manifest.loading && manifest.pieces.isEmpty { SitePulse() }
            else if manifest.failed { SiteEmpty(title: "The archive did not answer", detail: "Check your connection and try again.", actionTitle: "Try again") { Task { await manifest.load() } } }
            else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(manifest.search(query).prefix(120)) { p in
                            let on = selected.contains(p.cr)
                            let atCap = !on && selected.count >= slots
                            Button { toggle(p.cr) } label: {
                                Color(Bone.raised(scheme)).aspectRatio(1, contentMode: .fit).overlay {
                                    AsyncImage(url: URL(string: p.thumb)) { ph in if case .success(let i) = ph { i.resizable().scaledToFill() } else { Color.clear } }
                                }
                                .clipped()
                                .overlay { Rectangle().strokeBorder(on ? Bone.gold : Bone.line(scheme), lineWidth: on ? 2.5 : 0.6) }
                                .overlay(alignment: .topTrailing) { if on { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Color(hex: 0x15120b)).padding(4).background(Bone.gold) } }
                                .opacity(atCap ? 0.4 : 1)
                            }
                            .buttonStyle(.plain).disabled(atCap).accessibilityLabel("\(p.cr), \(p.title)\(on ? ", chosen" : "")")
                        }
                    }
                }
                .frame(height: 320)
            }
            HStack {
                Button { Task { await save() } } label: { Text(saving ? "Saving\u{2026}" : "Save chosen works") }.buttonStyle(SitePill()).disabled(saving)
            }
            SiteNote(text: line)
        }
        .task {
            await manifest.load()
            if !loadedSelection, let c = try? await Site.get("api/account/artworks", Chosen.self) { selected = c.crs ?? []; slots = c.slots ?? 3; loadedSelection = true }
        }
        .sensoryFeedback(PLHaptic.success, trigger: line == "Saved.")
    }

    private func toggle(_ cr: String) {
        line = nil
        if let i = selected.firstIndex(of: cr) { selected.remove(at: i) } else if selected.count < slots { selected.append(cr) }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let r = try await Site.post("api/account/artworks", ["crs": selected])
            if let crs = r.json?["crs"] as? [String] { selected = crs }
            line = "Saved."; onSaved?()
        } catch { line = "Not saved. \(error.localizedDescription)" }
    }
}
