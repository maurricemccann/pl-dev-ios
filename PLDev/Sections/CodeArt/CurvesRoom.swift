import SwiftUI
import TipKit
import UniformTypeIdentifiers

// The Curves room, native: every code piece as a tile (the first few running live as you scroll), a full-screen piece you
// swipe through, likes, the code, and a sound source (the microphone or a track) so audio-reactive pieces react.

struct PieceEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let still: URL?
}

// MARK: - likes

@MainActor @Observable final class LikesStore {
    static let shared = LikesStore()
    private(set) var liked = Set<String>()
    private(set) var loaded = false
    var line: String?

    func load(model: AppModel) async {
        struct L: Decodable { let liked: [String] }
        guard let http = model.http else { return }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "api/likes")), let l = try? JSONDecoder().decode(L.self, from: d) { liked = Set(l.liked); loaded = true }
    }

    /// Optimistic: the heart changes at once and comes back if the gallery refuses.
    func toggle(_ id: String, model: AppModel) async {
        struct R: Decodable { let liked: Bool? }
        guard let http = model.http else { return }
        let was = liked.contains(id)
        if was { liked.remove(id) } else { liked.insert(id) }
        let body = try? JSONSerialization.data(withJSONObject: ["id": id])
        do {
            let d = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/likes",
                                                    headers: ["content-type": "application/json", "Origin": LibraryData.shared.base(model)], body: body), idempotent: false)
            if let r = try? JSONDecoder().decode(R.self, from: d), let l = r.liked { if l { liked.insert(id) } else { liked.remove(id) } }
            line = nil
        } catch {
            if was { liked.insert(id) } else { liked.remove(id) }
            line = "Not saved. The gallery did not take the like."
        }
    }
}

// MARK: - sound

/// The room's sound: the microphone, a track from the gallery, or a file from the phone. One at a time, shared by every code-art screen.
@MainActor @Observable final class AudioController {
    static let shared = AudioController()
    struct Track: Identifiable, Hashable { let id: String; let label: String; let path: String; let bpm: Int }
    static let tracks = [Track(id: "helium", label: "Helium", path: "audio/helium.mp3", bpm: 122), Track(id: "fractal", label: "Fractal", path: "audio/fractal.mp4", bpm: 123)]

    private(set) var label = "Silent"
    private(set) var playing = false
    var line: String?
    var busy = false

    func mic() async {
        busy = true; defer { busy = false }
        do { try await VJAudio.shared.startMic(); label = "Microphone"; playing = true; line = nil }
        catch { line = "Not started. \(error.localizedDescription)" }
    }

    func play(_ t: Track, model: AppModel) async {
        guard let http = model.http else { line = "Not started. The gallery is not set up."; return }
        busy = true; defer { busy = false }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("codeart", isDirectory: true).appendingPathComponent(t.path.replacingOccurrences(of: "/", with: "-"))
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let d = try await http.send(RequestPlan(origin: "gallery", path: t.path), timeout: 120)
                try d.write(to: url)
            }
            try VJAudio.shared.play(url: url, label: t.label)
            label = t.label; playing = true; line = nil
        } catch { line = "Not started. \(error.localizedDescription)" }
    }

    func file(_ picked: URL) {
        let ok = picked.startAccessingSecurityScopedResource()
        defer { if ok { picked.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("codeart", isDirectory: true).appendingPathComponent("picked-" + picked.lastPathComponent)
        do {
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: picked, to: dest)
            try VJAudio.shared.play(url: dest, label: picked.deletingPathExtension().lastPathComponent)
            label = picked.deletingPathExtension().lastPathComponent; playing = true; line = nil
        } catch { line = "Not started. The file would not play." }
    }

    func stop() { VJAudio.shared.stop(); label = "Silent"; playing = false }
    func toggle() { if playing { VJAudio.shared.pause(); playing = false } else { VJAudio.shared.resume(); playing = VJAudio.shared.isPlaying } }
}

struct AudioSourceMenu: View {
    let model: AppModel
    @State private var audio = AudioController.shared
    @State private var picking = false

    var body: some View {
        Menu {
            Button("Microphone", systemImage: "mic") { Task { await audio.mic() } }
            ForEach(AudioController.tracks) { t in Button(t.label, systemImage: "music.note") { Task { await audio.play(t, model: model) } } }
            Button("A file from this phone", systemImage: "folder") { picking = true }
            if audio.label != "Silent" { Button("Silence", systemImage: "speaker.slash", role: .destructive) { audio.stop() } }
        } label: {
            Label(audio.label, systemImage: audio.playing ? "waveform" : "speaker.slash")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { r in if case .success(let u) = r { audio.file(u) } }
        .sensoryFeedback(PLHaptic.select, trigger: audio.label)
    }
}

// MARK: - the room

struct NativeCurvesRoom: View {
    let model: AppModel
    @State private var data = LibraryData.shared
    @State private var likes = LikesStore.shared
    @State private var onlyLiked = false
    @State private var liveGrid = true
    @State private var search = ""
    @State private var playing: PieceEntry?
    @State private var visible: [String: Int] = [:]
    @State private var tick = 0

    private var entries: [PieceEntry] {
        let fromLibrary = data.items.filter { $0.class == "code-piece" && data.marks[$0.vault_id]?.v != "cut" }
            .map { PieceEntry(id: $0.item_id, name: $0.name ?? $0.item_id, still: data.media($0, model: model).still) }
        let list = fromLibrary.isEmpty ? PieceRuntime.shared.pieces.filter(\.live).map { PieceEntry(id: $0.id, name: $0.name, still: nil) } : fromLibrary
        return list.filter { !onlyLiked || likes.liked.contains($0.id) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    /// The tiles that run live: the first few on screen (the one JavaScript queue draws them in turn).
    private var liveSet: Set<String> { liveGrid ? Set(visible.sorted { $0.value < $1.value }.prefix(6).map(\.key)) : [] }

    var body: some View {
        CodeArtGate(model: model) {
            let list = entries
            ScrollView {
                if list.isEmpty {
                    ContentUnavailableView(onlyLiked ? "Nothing liked yet" : "No pieces", systemImage: "scribble.variable",
                                           description: Text(onlyLiked ? "Touch and hold a piece and choose Like." : "The pieces appear here when the library loads."))
                } else {
                    let running = liveSet
                    TipView(PieceHoldTip()).padding(.horizontal, 6)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                            Button { tick += 1; playing = p } label: { tile(p, live: running.contains(p.id)) }
                                .buttonStyle(.plain)
                                .onAppear { visible[p.id] = i }
                                .onDisappear { visible[p.id] = nil }
                                .contextMenu {
                                    Button(likes.liked.contains(p.id) ? "Unlike" : "Like", systemImage: likes.liked.contains(p.id) ? "heart.slash" : "heart") { Task { await likes.toggle(p.id, model: model) } }
                                }
                                .accessibilityLabel(p.name)
                        }
                    }
                    .padding(6)
                }
                if let l = likes.line { ResultLine(text: l).padding() }
            }
            .searchable(text: $search, prompt: "Piece")
            .navigationTitle("Curves · \(list.count)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AudioSourceMenu(model: model) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Run the first few live", isOn: $liveGrid)
                        Toggle("Liked only", isOn: $onlyLiked)
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .task {
                if data.items.isEmpty { try? await data.load(model: model) }
                if !likes.loaded { await likes.load(model: model) }
            }
            .fullScreenCover(item: $playing) { p in PieceStage(model: model, entries: entries.isEmpty ? [p] : entries, start: p, close: { playing = nil }) }
            .sensoryFeedback(.impact(weight: .light), trigger: tick)
        }
        .plGround()
    }

    @ViewBuilder private func tile(_ p: PieceEntry, live: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.secondary.opacity(0.12)
            if live { LivePieceView(pieceID: p.id, fps: 30).allowsHitTesting(false) }
            else if let u = p.still { AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            Text(p.name).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 3).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(maxHeight: .infinity, alignment: .bottom)
            if likes.liked.contains(p.id) { Image(systemName: "heart.fill").foregroundStyle(.orange).padding(6) }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - the piece, full screen

/// One piece at full size. Swipe across for the next one, tap for the bars, the heart likes it, the code opens read-only.
struct PieceStage: View {
    let model: AppModel
    let entries: [PieceEntry]
    @State var current: PieceEntry
    let close: () -> Void
    @State private var likes = LikesStore.shared
    @State private var bars = true
    @State private var drag: CGFloat = 0

    init(model: AppModel, entries: [PieceEntry], start: PieceEntry, close: @escaping () -> Void) {
        self.model = model; self.entries = entries; self._current = State(initialValue: start); self.close = close
    }

    private var index: Int { entries.firstIndex(of: current) ?? 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LivePieceCard(model: model, pieceID: current.id, thumb: current.still).id(current.id)
                    .ignoresSafeArea()
                    .offset(x: drag * 0.25)
                    .transition(.opacity)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if bars { TipView(PieceSwipeTip()).padding() } }
            .onTapGesture { withAnimation(.snappy) { bars.toggle() } }
            .gesture(DragGesture(minimumDistance: 30).onChanged { drag = $0.translation.width }.onEnded { g in
                drag = 0
                if abs(g.translation.width) > 60, abs(g.translation.width) > abs(g.translation.height) { step(g.translation.width < 0 ? 1 : -1) }
            })
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(bars ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await likes.toggle(current.id, model: model) } } label: { Image(systemName: likes.liked.contains(current.id) ? "heart.fill" : "heart") }
                        .accessibilityLabel(likes.liked.contains(current.id) ? "Unlike" : "Like")
                }
                ToolbarItem(placement: .secondaryAction) { NavigationLink("The code") { SourceView(model: model, id: current.id) } }
                ToolbarItem(placement: .bottomBar) { AudioSourceMenu(model: model) }
                ToolbarItem(placement: .bottomBar) { Text("\(index + 1) of \(entries.count)").font(.caption).monospacedDigit() }
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .sensoryFeedback(.selection, trigger: current.id)
            .sensoryFeedback(PLHaptic.select, trigger: likes.liked.contains(current.id))
        }
    }

    private func step(_ d: Int) {
        guard !entries.isEmpty else { return }
        let n = (index + d + entries.count) % entries.count
        withAnimation(.snappy) { current = entries[n] }
    }
}
