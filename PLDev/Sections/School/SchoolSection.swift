import SwiftUI
import AVKit
import UserNotifications

/// Production School (S351): the beat course from the Production School deck, one lesson per slide, to build the three
/// crowned beats in FL Studio Mobile. The lessons ship in `school.json` (ported from the deck by the vault's
/// `pl-school-port.py`); the stage audio is his unreleased work, so it never ships in this repo: it is read once from the
/// PL DEV door (`api/pldev/school/<key>`, private bucket) and kept in Caches.
@MainActor enum SchoolSection: PLSection {
    static let manifest = SectionManifest(id: "school", title: "Production School", symbol: "pianokeys",
                                          needsKeys: ["pldev"], needsOrigins: ["console"])
    static let state = SchoolModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(SchoolView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

struct SchoolLesson: Decodable, Identifiable, Hashable {
    struct GridRow: Decodable, Hashable { let label: String; let steps: [Bool]; let color: String? }
    struct Block: Decodable, Hashable { let head: String; let text: String }
    struct Audio: Decodable, Hashable { let title: String; let key: String }
    let id, chapter, eyebrow, title, notes: String
    let chips: [String]
    let grids: [GridRow]
    let blocks: [Block]
    let table: [[String]]
    let audio: [Audio]
}

private struct SchoolFile: Decodable { let v: Int; let lessons: [SchoolLesson] }

@MainActor @Observable final class SchoolModel {
    private(set) var lessons: [SchoolLesson] = []
    private(set) var loadError: String?
    private(set) var done: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "school.done") ?? [])

    init() {
        let url = Bundle.main.url(forResource: "school", withExtension: "json")
            ?? Bundle.main.url(forResource: "school", withExtension: "json", subdirectory: "School")
        guard let url, let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(SchoolFile.self, from: data), f.v == 1 else {
            loadError = "The course file is missing from this build."; return
        }
        lessons = f.lessons
    }

    /// Chapters in course order: "0" is the first loop, then the three beats.
    var chapters: [String] { lessons.map(\.chapter).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
    func lessons(in ch: String) -> [SchoolLesson] { lessons.filter { $0.chapter == ch } }
    /// The chapter's name is its first slide's title (the deck's cover for each chapter).
    func name(of ch: String) -> String { lessons(in: ch).first?.title ?? "Chapter \(ch)" }
    func progress(_ ch: String) -> Double {
        let l = lessons(in: ch); return l.isEmpty ? 0 : Double(l.filter { done.contains($0.id) }.count) / Double(l.count)
    }
    func next(after l: SchoolLesson) -> SchoolLesson? {
        guard let i = lessons.firstIndex(of: l), i + 1 < lessons.count else { return nil }
        return lessons[i + 1]
    }
    func toggle(_ id: String) {
        if done.contains(id) { done.remove(id) } else { done.insert(id) }
        UserDefaults.standard.set(Array(done), forKey: "school.done")
    }

    /// The stage file on this phone, fetched once through the PL DEV key. Keys come from the bundled course file only.
    func localFile(_ key: String, model: AppModel) async throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "school", directoryHint: .isDirectory)
        let file = dir.appending(path: key.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let http = model.http else { throw Console.Problem.notSetUp }
        let data = try await http.send(RequestPlan(origin: "console", path: "api/pldev/school/\(key)"), timeout: 60)
        guard data.count > 1000 else { throw Console.Problem.refused("The stage did not come down whole.") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }
}

struct SchoolView: View {
    let model: AppModel
    @Bindable var state: SchoolModel

    var body: some View {
        List {
            if let e = state.loadError {
                ContentUnavailableView("No lessons", systemImage: "pianokeys", description: Text(e))
            }
            ForEach(state.chapters, id: \.self) { ch in
                Section {
                    ForEach(state.lessons(in: ch)) { l in
                        NavigationLink {
                            LessonView(model: model, state: state, lesson: l).osScreen()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.title)
                                    if !l.eyebrow.isEmpty { Text(l.eyebrow).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            } icon: {
                                Image(systemName: state.done.contains(l.id) ? "checkmark.circle.fill" : (l.audio.isEmpty ? "circle" : "play.circle"))
                                    .foregroundStyle(state.done.contains(l.id) ? Color.accentColor : .secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(ch == "0" ? "First loop" : "Beat \(ch) · \(state.name(of: ch))")
                        Spacer()
                        Text(state.progress(ch), format: .percent.precision(.fractionLength(0)))
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .navigationTitle("Production School")
    }
}

struct LessonView: View {
    let model: AppModel
    @Bindable var state: SchoolModel
    let lesson: SchoolLesson
    @State private var tick = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if !lesson.eyebrow.isEmpty { Text(lesson.eyebrow.uppercased()).font(.caption).foregroundStyle(.secondary) }
                    Text(lesson.title).font(.title.bold())
                    if !lesson.chips.isEmpty {
                        HStack { ForEach(lesson.chips, id: \.self) { Text($0).font(.footnote.monospaced()).padding(.horizontal, 10).padding(.vertical, 4).background(.quaternary, in: Capsule()) } }
                    }
                }
            }
            if !lesson.grids.isEmpty {
                Section("In FL's step grid") {
                    ForEach(Array(lesson.grids.enumerated()), id: \.offset) { _, g in StepRow(row: g) }
                    BoxNumbers()
                }
            }
            ForEach(lesson.audio, id: \.self) { a in Section("Listen") { StagePlayer(model: model, state: state, audio: a) } }
            if !lesson.blocks.isEmpty {
                Section {
                    ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { _, b in
                        VStack(alignment: .leading, spacing: 4) {
                            if !b.head.isEmpty { Text(b.head).font(.headline) }
                            if !b.text.isEmpty { Text(b.text) }
                        }
                    }
                }
            }
            if lesson.table.count > 1 {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(Array(lesson.table.enumerated()), id: \.offset) { i, r in
                            GridRow { ForEach(Array(r.enumerated()), id: \.offset) { _, c in Text(c).font(i == 0 ? .caption.bold() : .footnote) } }
                        }
                    }
                }
            }
            if !lesson.notes.isEmpty {
                Section("Why") { Text(lesson.notes).foregroundStyle(.secondary) }
            }
            Section {
                Button {
                    state.toggle(lesson.id); tick += 1
                } label: {
                    Label(state.done.contains(lesson.id) ? "Done in FL" : "Mark done in FL",
                          systemImage: state.done.contains(lesson.id) ? "checkmark.circle.fill" : "circle")
                        .symbolEffect(.bounce, value: tick)
                }
                if let n = state.next(after: lesson) {
                    NavigationLink { LessonView(model: model, state: state, lesson: n).osScreen() } label: { Label("Next: \(n.title)", systemImage: "arrow.right") }
                }
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.success, trigger: tick)
    }
}

/// One row of FL's 16-step grid: filled boxes are the taps, groups of four are the beats (as the deck draws it).
struct StepRow: View {
    let row: SchoolLesson.GridRow
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !row.label.isEmpty { Text(row.label).font(.caption.monospaced()).foregroundStyle(.secondary) }
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { i in
                    let on = i < row.steps.count && row.steps[i]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(on ? (Color(hex: row.color) ?? .accentColor) : ((i / 4) % 2 == 0 ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.08)))
                        .aspectRatio(0.8, contentMode: .fit)
                        .accessibilityLabel("Box \(i + 1), \(on ? "tap" : "empty")")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BoxNumbers: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...16, id: \.self) { n in Text("\(n)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }
        .accessibilityHidden(true)
    }
}

/// A stage of the beat to compare against by ear. Nothing downloads until he taps.
struct StagePlayer: View {
    let model: AppModel
    let state: SchoolModel
    let audio: SchoolLesson.Audio
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var result: String?

    var body: some View {
        if let player {
            VideoPlayer(player: player).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onDisappear { player.pause() }
        } else {
            Button {
                Task {
                    loading = true; defer { loading = false }
                    do {
                        let f = try await state.localFile(audio.key, model: model)
                        let p = AVPlayer(url: f); player = p; p.play(); result = nil
                    } catch { result = "Not loaded. \(error.localizedDescription)" }
                }
            } label: {
                HStack { Label(audio.title, systemImage: "play.fill"); Spacer(); if loading { ProgressView() } }
            }
            .disabled(loading)
            ResultLine(text: result)
        }
    }
}
