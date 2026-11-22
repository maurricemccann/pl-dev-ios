import SwiftUI
import AVFoundation
import UserNotifications

/// PL Prod (S351): the R1 School app (`pl-r1-school`) retrofitted for iOS, the way the other R1 apps came over. He builds in
/// FL Studio on the iPad and reads the lesson here on the phone, his second screen. Same screens as the R1: the track list
/// (First Loop, Beats 1 to 3, then his own beats), a track opens on the whole-track pads, then one lesson step per page,
/// and the bar plays the step's clip (the stage clip where the step names one, else the finished beat). Double press on
/// the R1 = the Notes button here. The phone adds what the R1 could not: swipe paging and the screen kept awake in a track.
///
/// Content: `school.json`, ported from the R1 app by the vault's `pl-school-port.py`. Audio is his unreleased work, so it
/// never ships in this public repo: each file is read once through the PL DEV door (`api/pldev/school/<id>.m4a`, a private
/// bucket) and kept in Caches.
@MainActor enum SchoolSection: PLSection {
    static let manifest = SectionManifest(id: "school", title: "PL Prod", symbol: "pianokeys",
                                          needsKeys: ["pldev"], needsOrigins: ["console"])
    static let state = SchoolModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(SchoolView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    /// `pldev://section/school/<track>[/<step id>]` opens that track, on that step when given.
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let id = path.first, let t = state.tracks.first(where: { $0.id == id }) {
            if path.count > 1, let i = t.slides.firstIndex(of: path[1]) { state.setPage(t, i + 1) }
            state.open = t
        }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

// MARK: - Content (the R1 app's own shapes)

struct SchoolTrack: Decodable, Identifiable, Hashable {
    let id, title, sub, ref, refName: String
    let slides: [String]
    let clips: [String: [String]]          // step id -> [audio id, spoken name]
}
struct SchoolBeat: Decodable, Identifiable, Hashable { let id, title, sub: String }
struct SchoolLesson: Decodable, Identifiable, Hashable {
    struct GridRow: Decodable, Hashable { let label: String; let steps: [Bool]; let color: String? }
    struct Block: Decodable, Hashable { let head: String; let text: String }
    let id, eyebrow, title, notes: String
    let chips: [String]
    let grids: [GridRow]
    let blocks: [Block]
    let table: [[String]]
}
private struct SchoolFile: Decodable { let v: Int; let tracks: [SchoolTrack]; let his: [SchoolBeat]; let lessons: [SchoolLesson] }

/// One pad row on the whole-track page.
struct PadRow: Hashable { let heading: String; let label: String; let steps: [Bool]; let color: String? }

@MainActor @Observable final class SchoolModel {
    private(set) var tracks: [SchoolTrack] = []
    private(set) var his: [SchoolBeat] = []
    private(set) var loadError: String?
    private var byId: [String: SchoolLesson] = [:]
    var open: SchoolTrack?
    let player = SchoolPlayer()

    init() {
        let url = Bundle.main.url(forResource: "school", withExtension: "json")
            ?? Bundle.main.url(forResource: "school", withExtension: "json", subdirectory: "School")
        guard let url, let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(SchoolFile.self, from: data), f.v == 2 else {
            loadError = "The lessons are missing from this build."; return
        }
        tracks = f.tracks; his = f.his
        byId = Dictionary(f.lessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func lesson(_ id: String) -> SchoolLesson? { byId[id] }
    /// Page 0 is the whole-track pads; page n is step n. Kept per track, as the R1 keeps `school.at.<track>`.
    func page(_ t: SchoolTrack) -> Int { min(UserDefaults.standard.integer(forKey: "school.at.\(t.id)"), t.slides.count) }
    func setPage(_ t: SchoolTrack, _ p: Int) { UserDefaults.standard.set(p, forKey: "school.at.\(t.id)") }

    /// The clip a step plays: its stage clip where the step names one, else the track's finished beat.
    func clip(_ t: SchoolTrack, page: Int) -> (id: String, name: String) {
        if page > 0, let c = t.clips[t.slides[page - 1]], c.count == 2 { return (c[0], c[1]) }
        return (t.ref, t.refName)
    }

    /// Every pad row of the track on one page (the R1's fullView): covers skipped, contrast rows marked "(normal)" skipped,
    /// a row repeated on a later step shown once.
    func padRows(_ t: SchoolTrack) -> [PadRow] {
        var seen = Set<String>(), out: [PadRow] = []
        for sid in t.slides where !sid.hasSuffix("cover") {
            guard let l = byId[sid] else { continue }
            for g in l.grids where g.steps.count == 16 {
                let label = g.label.isEmpty ? l.title + (l.chips.first.map { " · " + $0 } ?? "") : g.label
                if label.lowercased().contains("(normal)") { continue }
                let key = (label.split(whereSeparator: { " ·,".contains($0) }).first.map(String.init) ?? "").lowercased() + g.steps.map { $0 ? "1" : "0" }.joined()
                if seen.insert(key).inserted { out.append(PadRow(heading: l.title, label: label, steps: g.steps, color: g.color)) }
            }
        }
        return out
    }

    /// The file on this phone, fetched once through the PL DEV key. Ids come from the bundled lessons only.
    func localFile(_ id: String, model: AppModel) async throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "school", directoryHint: .isDirectory)
        let file = dir.appending(path: id + ".m4a")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let http = model.http else { throw Console.Problem.notSetUp }
        let data = try await http.send(RequestPlan(origin: "console", path: "api/pldev/school/\(id).m4a"), timeout: 60)
        guard data.count > 1000 else { throw Console.Problem.refused("The clip did not come down whole.") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }
}

/// One clip at a time, as the R1's single Audio element: press plays, press again pauses, a new clip starts from the top.
@MainActor @Observable final class SchoolPlayer {
    private(set) var playing: String?
    private(set) var loading: String?
    var result: String?
    private var audio: AVAudioPlayer?

    var isOn: Bool { playing != nil && (audio?.isPlaying ?? false) }
    var progress: Double { guard let a = audio, a.duration > 0 else { return 0 }; return a.currentTime / a.duration }

    func toggle(_ id: String, state: SchoolModel, model: AppModel) async {
        if playing == id, let a = audio {
            if a.isPlaying { a.pause() } else { a.play() }
            playing = id; return
        }
        stop(); loading = id; defer { loading = nil }
        do {
            let f = try await state.localFile(id, model: model)
            try AVAudioSession.sharedInstance().setCategory(.playback)   // plays with the silent switch on, beside FL
            try AVAudioSession.sharedInstance().setActive(true)
            let a = try AVAudioPlayer(contentsOf: f); audio = a; playing = id; a.play(); result = nil
        } catch { result = "Not played. \(error.localizedDescription)" }
    }
    func stop() { audio?.stop(); audio = nil; playing = nil }
}

// MARK: - The list

struct SchoolView: View {
    let model: AppModel
    @Bindable var state: SchoolModel

    var body: some View {
        List {
            if let e = state.loadError {
                ContentUnavailableView("No lessons", systemImage: "pianokeys", description: Text(e))
            }
            Section {
                ForEach(state.tracks) { t in
                    Button { state.open = t } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.title).font(.headline).foregroundStyle(.primary)
                            Text("\(t.sub) · \(t.slides.count) steps").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
            }
            if !state.his.isEmpty {
                Section("Your beats") {
                    ForEach(state.his) { h in
                        Button { Task { await state.player.toggle(h.id, state: state, model: model) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(h.title).font(.headline).foregroundStyle(.primary)
                                    Text(h.sub).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if state.player.loading == h.id { ProgressView() }
                                else { Image(systemName: state.player.playing == h.id && state.player.isOn ? "pause.fill" : "play.fill").foregroundStyle(Color.accentColor) }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    ResultLine(text: state.player.result)
                }
            }
        }
        .navigationTitle("PL Prod")
        .navigationDestination(item: $state.open) { TrackView(model: model, state: state, track: $0).osScreen() }
        .onDisappear { if state.open == nil { state.player.stop() } }
    }
}

// MARK: - A track

struct TrackView: View {
    let model: AppModel
    let state: SchoolModel
    let track: SchoolTrack
    @State private var page = 0
    @State private var notes = false

    var body: some View {
        TabView(selection: $page) {
            ScrollView { PadsPage(rows: state.padRows(track)).padding() }.tag(0)
            ForEach(Array(track.slides.enumerated()), id: \.offset) { i, sid in
                ScrollView { if let l = state.lesson(sid) { StepPage(lesson: l).padding() } }.tag(i + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(track.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bar }
        .sheet(isPresented: $notes) {
            NavigationStack {
                ScrollView { Text(currentNotes).font(.body).padding().frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { notes = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { page = state.page(track); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { state.player.stop(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: page) { _, p in state.setPage(track, p); state.player.stop() }
        .sensoryFeedback(PLHaptic.select, trigger: page)
    }

    private var currentNotes: String { page > 0 ? (state.lesson(track.slides[page - 1])?.notes ?? "") : "" }

    /// The R1's bottom bar: play this step's clip, its name, the notes, a thin progress line.
    private var bar: some View {
        let c = state.clip(track, page: page)
        let on = state.player.playing == c.id && state.player.isOn
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { Task { await state.player.toggle(c.id, state: state, model: model) } } label: {
                    Group {
                        if state.player.loading == c.id { ProgressView() }
                        else { Image(systemName: on ? "pause.fill" : "play.fill").font(.title2).contentTransition(.symbolEffect(.replace)) }
                    }
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(on ? "Pause \(c.name)" : "Play \(c.name)")
                VStack(alignment: .leading, spacing: 1) {
                    // the step counter lives here, not in the top bar: there it pushed the track's name out on the longer Beat titles (S351 frames)
                    Text(page == 0 ? "pads" : "step \(page) of \(track.slides.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(c.name).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !currentNotes.isEmpty {
                    Button("Notes") { notes = true }.buttonStyle(.bordered).frame(minHeight: 44)
                }
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                ProgressView(value: state.player.playing == c.id ? state.player.progress : 0).progressViewStyle(.linear)
            }
            ResultLine(text: state.player.result)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .plGlass(in: Rectangle())
    }
}

/// FL's step grid as the R1 draws it: 8 pads a line, a beat line every 4, the pad number at the foot of each pad.
struct PadGrid: View {
    let steps: [Bool]
    let color: String?
    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { line in
                HStack(spacing: 5) {
                    ForEach(0..<8, id: \.self) { j in
                        let i = line * 8 + j, on = i < steps.count && steps[i]
                        if j == 4 { RoundedRectangle(cornerRadius: 1).fill(Color.accentColor.opacity(0.55)).frame(width: 3) }
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(on ? (Color(hex: color) ?? .accentColor) : Color.secondary.opacity(j < 4 ? 0.22 : 0.12))
                            .frame(height: 44)
                            .overlay(alignment: .bottom) {
                                Text("\(i + 1)").font(.system(size: 12, weight: on ? .bold : .regular).monospacedDigit())
                                    .foregroundStyle(on ? Color.black.opacity(0.8) : .secondary).padding(.bottom, 3)
                            }
                            .accessibilityLabel("Pad \(i + 1), \(on ? "on" : "off")")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PadsPage: View {
    let rows: [PadRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE WHOLE TRACK · EVERY PAD ROW").font(.caption).foregroundStyle(Color.accentColor)
            if rows.isEmpty { Text("No pad rows in this track.").foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i == 0 || rows[i - 1].heading != r.heading {
                    Divider().padding(.top, 6)
                    Text(r.heading.uppercased()).font(.caption).foregroundStyle(.secondary)
                }
                Text(r.label).font(.subheadline)
                PadGrid(steps: r.steps, color: r.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StepPage: View {
    let lesson: SchoolLesson
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !lesson.eyebrow.isEmpty { Text(lesson.eyebrow.uppercased()).font(.caption).foregroundStyle(Color.accentColor) }
            Text(lesson.title).font(.title.bold())
            ForEach(lesson.chips, id: \.self) { Text($0).font(.footnote.monospaced()).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: Capsule()) }
            ForEach(Array(lesson.grids.enumerated()), id: \.offset) { _, g in
                VStack(alignment: .leading, spacing: 4) {
                    if !g.label.isEmpty { Text(g.label).font(.subheadline) }
                    PadGrid(steps: g.steps, color: g.color)
                }
            }
            ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { _, b in
                VStack(alignment: .leading, spacing: 4) {
                    if !b.head.isEmpty { Text(b.head).font(.headline) }
                    if !b.text.isEmpty { Text(b.text).font(.body) }
                }
            }
            if lesson.table.count > 1 {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(Array(lesson.table.enumerated()), id: \.offset) { i, r in
                        GridRow { ForEach(Array(r.enumerated()), id: \.offset) { _, c in Text(c).font(i == 0 ? .caption.bold() : .footnote) } }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
