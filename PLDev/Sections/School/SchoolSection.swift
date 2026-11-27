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
    let color: String?                     // whose traits the beat studies: "blue" | "red" | "both"
    let form: [FormPart]?                  // S354: the song's layout for the playlist (pl-r1-school tools/forms.json)
}
struct FormPart: Decodable, Hashable { let name: String; let bars: Int; let parts: [String] }

/// The track's dot: system blue, red, or half of each for "both". Nothing drawn for any other value.
struct TrackDot: View {
    let kind: String
    var body: some View {
        switch kind {
        case "blue": dot(Circle().fill(Color.blue))
        case "red": dot(Circle().fill(Color.red))
        case "both": dot(Circle().fill(LinearGradient(stops: [.init(color: .blue, location: 0.5), .init(color: .red, location: 0.5)],
                                                      startPoint: .leading, endPoint: .trailing)))
        default: EmptyView()
        }
    }
    private func dot(_ v: some View) -> some View { v.frame(width: 10, height: 10).accessibilityLabel(kind) }
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
    // S354 (his ask 11-27 "each track needs to tell me exactly how to create it and visually show me"): from pl_school_guide.py
    let fl: [String]?                      // numbered FL Studio Mobile actions for this page
    let rolls: [Roll]?                     // the notes of each MIDI this page imports, drawn as a piano roll
    let playlist: Bool?                    // the arrange page: draws the song layout
    struct Roll: Decodable, Hashable {
        let label: String
        let from_bar: Int
        let bars: Int
        let notes: [[Int]]                 // [start step, length in steps, MIDI pitch], 16 steps a bar
        let names: [String: String]        // pitch -> "C#3"
    }
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

    /// The lessons fetched over the air (ThemeFeed, `pldev/school.json`, same shape) when that copy reads, else the bundled one.
    init() {
        let url = Bundle.main.url(forResource: "school", withExtension: "json")
            ?? Bundle.main.url(forResource: "school", withExtension: "json", subdirectory: "School")
        let remote = ThemeFeed.extra("school.json").flatMap { Self.decode($0) }
        guard let f = remote ?? url.flatMap({ try? Data(contentsOf: $0) }).flatMap({ Self.decode($0) }) else {
            loadError = "The lessons are missing from this build."; return
        }
        tracks = f.tracks; his = f.his
        byId = Dictionary(f.lessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    nonisolated private static func decode(_ data: Data) -> SchoolFile? {
        guard let f = try? JSONDecoder().decode(SchoolFile.self, from: data), f.v == 2, !f.tracks.isEmpty else { return nil }
        return f
    }
    /// What ThemeFeed checks before it keeps a fetched copy.
    nonisolated static func valid(_ data: Data) -> Bool { decode(data) != nil }

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

    /// The beat's iPad pack (S354, his ask: download it, AirDrop it to the iPad): pack-b<N>.zip through the PL DEV key,
    /// saved under the name the iPad folder uses ("PL Prod - Beat N - Name.zip").
    func packFile(_ t: SchoolTrack, model: AppModel) async throws -> URL {
        guard let http = model.http else { throw Console.Problem.notSetUp }
        let data = try await http.send(RequestPlan(origin: "console", path: "api/pldev/school/pack-\(t.id).zip"), timeout: 300)
        guard data.count > 1000, data.starts(with: [0x50, 0x4B]) else { throw Console.Problem.refused("The pack did not come down whole.") }
        let file = FileManager.default.temporaryDirectory.appending(path: "PL Prod - " + t.title.replacingOccurrences(of: " · ", with: " - ") + ".zip")
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
        List { Group {
            if let e = state.loadError {
                ContentUnavailableView("No lessons", systemImage: "pianokeys", description: Text(e))
            }
            Section {
                ForEach(state.tracks) { t in
                    Button { state.open = t } label: {
                        HStack(spacing: 10) {
                            if let c = t.color { TrackDot(kind: c) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.title).font(Font.pl(.headline)).foregroundStyle(.primary)
                                Text("\(t.sub) · \(t.slides.count) steps").font(Font.pl(.subheadline)).foregroundStyle(.secondary)
                            }
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
                                    Text(h.title).font(Font.pl(.headline)).foregroundStyle(.primary)
                                    Text(h.sub).font(Font.pl(.subheadline)).foregroundStyle(.secondary)
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
        }.listRowBackground(PLRowGround()) }
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
    @State private var packLoading = false
    @State private var packNote: String?
    @State private var share: CodeArtShareItem?
    @State private var cardPack: PackKey?   // the beat's last step earns a card pack (his ask 11-27)

    var body: some View {
        TabView(selection: $page) {
            // S354 (his ask "show the whole thing like FL Studio"): sideways = FL's channel rack; both ways = the song's layout
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        packButton
                        if geo.size.width > geo.size.height {
                            RackView(rows: state.padRows(track))
                        } else {
                            Label("Turn the phone sideways for the channel rack", systemImage: "rotate.right")
                                .font(Font.pl(.footnote)).foregroundStyle(.secondary)
                            PadsPage(rows: state.padRows(track))
                        }
                        if let f = track.form, !f.isEmpty { PianoRollParts(form: f, padLabels: state.padRows(track).map(\.label)); PlaylistView(form: f) }
                    }
                    .padding()
                }
            }
            .tag(0)
            ForEach(Array(track.slides.enumerated()), id: \.offset) { i, sid in
                ScrollView { if let l = state.lesson(sid) { StepPage(lesson: l, form: track.form).padding() } }.tag(i + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .plScreenTitle(track.title)   // S352: the plain nav title dropped out on some step pages opened directly (b1 kick, b3 drop); the house title slot holds
        .safeAreaInset(edge: .bottom) { bar }
        .sheet(isPresented: $notes) {
            NavigationStack {
                ScrollView { Text(currentNotes).font(Font.pl(.body)).padding().frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { notes = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { page = state.page(track); UIApplication.shared.isIdleTimerDisabled = true; PLOrientation.allow(.allButUpsideDown) }
        .onDisappear { state.player.stop(); UIApplication.shared.isIdleTimerDisabled = false; PLOrientation.allow(.portrait) }   // turns like a Paint canvas, upright again on the way out
        .onChange(of: page) { _, p in
            state.setPage(track, p); state.player.stop()
            if p == track.slides.count, p > 0 { cardPack = PackEarn.fresh("prod-\(track.id)") }
        }
        .earnsPack($cardPack)
        .sensoryFeedback(PLHaptic.select, trigger: page)
    }

    private var currentNotes: String { page > 0 ? (state.lesson(track.slides[page - 1])?.notes ?? "") : "" }

    /// One tap: this beat's sounds and MIDI come down, then Share opens (AirDrop to the iPad, or Save to Files).
    @ViewBuilder private var packButton: some View {
        if track.id.hasPrefix("b") {
            VStack(alignment: .leading, spacing: 6) {
                Button { Task { await getPack() } } label: {
                    HStack(spacing: 8) {
                        if packLoading { ProgressView() } else { Image(systemName: "square.and.arrow.down") }
                        Text("Get the pack for the iPad")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).disabled(packLoading)
                .accessibilityHint("Downloads this beat's sounds and MIDI, then opens Share so you can AirDrop it")
                ResultLine(text: packNote)
            }
            .sheet(item: $share) { CodeArtShareSheet(items: $0.items) }
        }
    }

    private func getPack() async {
        packLoading = true; defer { packLoading = false }
        do { share = CodeArtShareItem(items: [try await state.packFile(track, model: model)]); packNote = nil }
        catch { packNote = "Not downloaded. \(error.localizedDescription)" }
    }

    /// The R1's bottom bar: play this step's clip, its name, the notes, a thin progress line.
    private var bar: some View {
        let c = state.clip(track, page: page)
        let on = state.player.playing == c.id && state.player.isOn
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { Task { await state.player.toggle(c.id, state: state, model: model) } } label: {
                    Group {
                        if state.player.loading == c.id { ProgressView() }
                        else { Image(systemName: on ? "pause.fill" : "play.fill").font(Font.pl(.title2)).contentTransition(.symbolEffect(.replace)) }
                    }
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(on ? "Pause \(c.name)" : "Play \(c.name)")
                VStack(alignment: .leading, spacing: 1) {
                    // the step counter lives here, not in the top bar: there it pushed the track's name out on the longer Beat titles (S351 frames)
                    Text(page == 0 ? "pads" : "step \(page) of \(track.slides.count)").font(Font.pl(.caption).monospacedDigit()).foregroundStyle(.secondary)
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
                        if j == 4 { RoundedRectangle(cornerRadius: 1 * PLStyle.radius).fill(Color.accentColor.opacity(0.55)).frame(width: 3) }
                        RoundedRectangle(cornerRadius: 9 * PLStyle.radius, style: .continuous)
                            .fill(on ? (Color(hex: color) ?? .accentColor) : Color.secondary.opacity(j < 4 ? 0.22 : 0.12))
                            .frame(height: 44)
                            .overlay(alignment: .bottom) {
                                Text("\(i + 1)").font(Font.pl(size: 12, weight: on ? .bold : .regular).monospacedDigit())
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
            Text("THE WHOLE TRACK · EVERY PAD ROW").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
            if rows.isEmpty { Text("No pad rows in this track.").foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i == 0 || rows[i - 1].heading != r.heading {
                    Divider().padding(.top, 6)
                    Text(r.heading.uppercased()).font(Font.pl(.caption)).foregroundStyle(.secondary)
                }
                Text(r.label).font(Font.pl(.subheadline))
                PadGrid(steps: r.steps, color: r.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// FL's channel rack (S354): one row per instrument, all 16 steps in a line, a beat line every 4. Shown with the phone sideways.
struct RackView: View {
    let rows: [PadRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHANNEL RACK · EVERY ROW, 16 STEPS").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
            if rows.isEmpty { Text("No pad rows in this track.").foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 3) {
                    Text(r.label).font(Font.pl(size: 12)).lineLimit(1).frame(width: 140, alignment: .leading)
                    ForEach(0..<16, id: \.self) { i in
                        if i > 0 && i % 4 == 0 { Rectangle().fill(Color.accentColor.opacity(0.55)).frame(width: 2, height: 26) }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i < r.steps.count && r.steps[i] ? (Color(hex: r.color) ?? .accentColor) : Color.secondary.opacity((i / 4) % 2 == 0 ? 0.22 : 0.12))
                            .frame(height: 26)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.label): steps \(r.steps.enumerated().filter { $0.element }.map { String($0.offset + 1) }.joined(separator: ", "))")
            }
            HStack(spacing: 3) {
                Color.clear.frame(width: 140, height: 1)
                ForEach(0..<16, id: \.self) { i in
                    if i > 0 && i % 4 == 0 { Color.clear.frame(width: 2, height: 1) }
                    Text(i % 4 == 0 ? "\(i + 1)" : "").font(Font.pl(size: 11).monospacedDigit()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// The song's parts that are not step pads (S354, his read 11-27: "you said keys at the bottom then it's not at the top"):
/// keys, guitar, pads, samples and 808 lines are played as notes in FL's piano roll, so the rack has no row for them.
/// Listed here with the file to load, so every row of the song layout has a match above it.
struct PianoRollParts: View {
    let form: [FormPart]
    let padLabels: [String]
    private static let melodic: Set<String> = ["keys", "guitar", "pad", "sample", "arp", "strings", "bass", "hook", "tones", "bells"]
    private var parts: [String] {
        let pads = Set(padLabels.map { $0.lowercased().split(whereSeparator: { " ·,".contains($0) }).first.map(String.init) ?? "" })
        return form.flatMap(\.parts).reduce(into: [String]()) { out, p in
            let name = p.components(separatedBy: " · ")[0].lowercased()
            let isMelodic = Self.melodic.contains(name) || (name == "808" && !pads.contains("808"))
            if isMelodic && !out.contains(p) { out.append(p) }
        }
    }
    var body: some View {
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("PLAYED IN THE PIANO ROLL, NOT ON PADS").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
                ForEach(parts, id: \.self) { p in
                    let bits = p.components(separatedBy: " · ")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(bits[0]).font(Font.pl(.subheadline).weight(.semibold))
                        Text(bits.count > 1 ? bits[1] : "").font(Font.pl(.footnote)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Load the sound, then import its MIDI (or play the notes yourself) in the piano roll.")
                    .font(Font.pl(.footnote)).foregroundStyle(.secondary)
            }
        }
    }
}

/// FL's playlist (S354; labels redone on his read 11-27, "I think what it is, is the labeling"): a bar ruler on top, one cell
/// per bar in every row, each part named over its own bars with its span, and each row saying which bars it plays.
struct PlaylistView: View {
    let form: [FormPart]
    private var parts: [String] { form.flatMap(\.parts).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } }
    private var total: Int { form.reduce(0) { $0 + $1.bars } }
    private func start(_ i: Int) -> Int { form.prefix(i).reduce(1) { $0 + $1.bars } }
    /// Bar n (1-based) belongs to which part of the song.
    private func section(of bar: Int) -> FormPart? {
        var b = 1
        for f in form { if bar < b + f.bars { return f }; b += f.bars }
        return nil
    }
    /// "bars 5-8" or "bars 1-4, 9-12" for one row.
    private func span(_ part: String) -> String {
        var runs: [(Int, Int)] = []
        for bar in 1...max(total, 1) where section(of: bar)?.parts.contains(part) == true {
            if let last = runs.last, last.1 == bar - 1 { runs[runs.count - 1].1 = bar } else { runs.append((bar, bar)) }
        }
        let txt = runs.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)-\($0.1)" }.joined(separator: ", ")
        return runs.isEmpty ? "" : (runs.count == 1 && runs[0].0 == runs[0].1 ? "bar " : "bars ") + txt
    }

    var body: some View {
        let cell = total <= 16 ? 30.0 : (total <= 32 ? 18.0 : 11.0)          // width of one bar
        let every = total <= 16 ? 1 : 4                                       // which bar numbers to print
        let label = 170.0
        VStack(alignment: .leading, spacing: 6) {
            Text("WHO PLAYS WHEN · \(total) BARS").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
            Text("Like FL's Playlist: time runs left to right, one square per bar. Gold means that sound plays in that bar.")
                .font(Font.pl(.footnote)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {                                       // the bar ruler
                        Text("bar").font(Font.pl(size: 10)).foregroundStyle(.secondary).frame(width: label, alignment: .leading)
                        ForEach(1...max(total, 1), id: \.self) { b in
                            Text((b - 1) % every == 0 ? "\(b)" : "").font(Font.pl(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: cell, alignment: .leading)
                        }
                    }
                    HStack(spacing: 0) {                                       // each part of the song over its own bars
                        Color.clear.frame(width: label, height: 1)
                        ForEach(form.indices, id: \.self) { i in
                            let b0 = start(i), b1 = start(i) + form[i].bars - 1
                            VStack(alignment: .leading, spacing: 1) {
                                Text(form[i].name).font(Font.pl(size: 11, weight: .bold)).lineLimit(1)
                                Text(b0 == b1 ? "bar \(b0)" : "bars \(b0)-\(b1)").font(Font.pl(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 4)
                            .frame(width: CGFloat(Double(form[i].bars) * cell), alignment: .leading)
                            .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 2) }
                        }
                    }
                    ForEach(parts, id: \.self) { p in
                        HStack(spacing: 0) {
                            // "Kick · Kick.wav": the sound's name, then the file you load (the same names as the pads and the pack)
                            let bits = p.components(separatedBy: " · ")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(bits[0]).font(Font.pl(size: 12, weight: .semibold)).lineLimit(1)
                                if bits.count > 1 { Text(bits[1]).font(Font.pl(size: 9.5)).foregroundStyle(.secondary).lineLimit(2) }
                                Text(span(p)).font(Font.pl(size: 9.5).monospacedDigit()).foregroundStyle(Color.accentColor.opacity(0.8)).lineLimit(1)
                            }
                            .frame(width: label, alignment: .leading)
                            .padding(.vertical, 3)
                            ForEach(1...max(total, 1), id: \.self) { b in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(section(of: b)?.parts.contains(p) == true ? Color.accentColor : Color.secondary.opacity((b - 1) / 4 % 2 == 0 ? 0.16 : 0.09))
                                    .frame(width: max(2, cell - 2), height: 20)
                                    .frame(width: cell, alignment: .leading)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(p.replacingOccurrences(of: " · ", with: ", ")): \(span(p))")
                    }
                }
            }
        }
    }
}

/// The notes of one MIDI file as FL's piano roll draws them (S354): note names down the side, bars across, gold notes.
struct PianoRollView: View {
    let roll: SchoolLesson.Roll
    var body: some View {
        let pitches = roll.notes.map { $0[2] }.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.sorted(by: >)
        let steps = roll.bars * 16, cell = 7.0, rowH = 15.0, label = 40.0
        VStack(alignment: .leading, spacing: 6) {
            Text("PIANO ROLL · \(roll.label) · BARS \(roll.from_bar)-\(roll.from_bar + roll.bars - 1)")
                .font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(pitches, id: \.self) { p in
                            Text(roll.names[String(p)] ?? "").font(Font.pl(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: label - 4, height: rowH, alignment: .trailing)
                        }
                        Text("bar").font(Font.pl(size: 9)).foregroundStyle(.secondary).frame(width: label - 4, height: 14, alignment: .trailing)
                    }
                    .padding(.trailing, 4)
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            ForEach(0...steps, id: \.self) { s in             // beat lines every 4, bar lines every 16
                                Rectangle().fill(Color.secondary.opacity(s % 16 == 0 ? 0.45 : (s % 4 == 0 ? 0.18 : 0.06)))
                                    .frame(width: s % 16 == 0 ? 1.5 : 1, height: CGFloat(pitches.count) * rowH)
                                    .offset(x: CGFloat(Double(s) * cell))
                            }
                            ForEach(Array(pitches.enumerated()), id: \.offset) { i, _ in
                                Rectangle().fill(Color.secondary.opacity(i % 2 == 0 ? 0.07 : 0.03))
                                    .frame(width: CGFloat(Double(steps) * cell), height: rowH).offset(y: CGFloat(Double(i) * rowH))
                            }
                            ForEach(Array(roll.notes.enumerated()), id: \.offset) { _, n in
                                if n.count == 3, let row = pitches.firstIndex(of: n[2]) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.accentColor)
                                        .frame(width: max(3, CGFloat(Double(n[1]) * cell) - 1), height: rowH - 3)
                                        .offset(x: CGFloat(Double(n[0]) * cell) + 0.5, y: CGFloat(Double(row) * rowH) + 1.5)
                                }
                            }
                        }
                        .frame(width: CGFloat(Double(steps) * cell), height: CGFloat(pitches.count) * rowH, alignment: .topLeading)
                        HStack(spacing: 0) {
                            ForEach(0..<roll.bars, id: \.self) { b in
                                Text("\(roll.from_bar + b)").font(Font.pl(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: CGFloat(16 * cell), height: 14, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Piano roll for \(roll.label): \(roll.notes.count) notes over \(roll.bars) bars")
        }
    }
}

/// "In FL": the page's actions, numbered, in FL Studio Mobile's own words (S354).
struct FLSteps: View {
    let steps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IN FL STUDIO MOBILE").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(Font.pl(.subheadline).monospacedDigit().weight(.bold)).foregroundStyle(Color.accentColor)
                        .frame(width: 22, alignment: .trailing)
                    Text(s).font(Font.pl(.body)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StepPage: View {
    let lesson: SchoolLesson
    var form: [FormPart]? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !lesson.eyebrow.isEmpty { Text(lesson.eyebrow.uppercased()).font(Font.pl(.caption)).foregroundStyle(Color.accentColor) }
            Text(lesson.title).font(Font.pl(.title).bold())
            ForEach(lesson.chips, id: \.self) { Text($0).font(Font.pl(.footnote).monospaced()).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: Capsule()) }
            ForEach(Array(lesson.grids.enumerated()), id: \.offset) { _, g in
                VStack(alignment: .leading, spacing: 4) {
                    if !g.label.isEmpty { Text(g.label).font(Font.pl(.subheadline)) }
                    PadGrid(steps: g.steps, color: g.color)
                }
            }
            ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { _, b in
                VStack(alignment: .leading, spacing: 4) {
                    if !b.head.isEmpty { Text(b.head).font(Font.pl(.headline)) }
                    if !b.text.isEmpty { Text(b.text).font(Font.pl(.body)) }
                }
            }
            if lesson.table.count > 1 {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(Array(lesson.table.enumerated()), id: \.offset) { i, r in
                        GridRow { ForEach(Array(r.enumerated()), id: \.offset) { _, c in Text(c).font(i == 0 ? .caption.bold() : .footnote) } }
                    }
                }
            }
            if let fl = lesson.fl, !fl.isEmpty { FLSteps(steps: fl) }
            ForEach(lesson.rolls ?? [], id: \.self) { PianoRollView(roll: $0) }
            if lesson.playlist == true, let f = form, !f.isEmpty { PlaylistView(form: f) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
