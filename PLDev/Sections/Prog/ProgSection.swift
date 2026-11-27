import SwiftUI
import UserNotifications

/// PL Prog (S354·3f9c, his ask 11-26): the R1 Linux he learns on, taught on the phone. Four tracks (Get in, Linux, Code,
/// Pieces) from `prog.json`, built by `C:\R1\learn\make_prog.py` from the same files the R1 has, so `learn 3` there and
/// Code > 3 here show the same code. Every command and code block copies (paste into Easy SSH); a Done tick stays on the
/// phone. Over the air at `pldev/prog.json` like PL Prod's lessons. Spec: vault Plans/SPEC - PL PROG ON PL DEV (S354).
@MainActor enum ProgSection: PLSection {
    static let manifest = SectionManifest(id: "prog", title: "PL Prog", symbol: "terminal")
    static let state = ProgModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(ProgView(state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

struct ProgLesson: Decodable, Identifiable, Hashable {
    let id, title, text, code, image: String
    let run: [String]
}
struct ProgTrack: Decodable, Identifiable, Hashable {
    let id, title, sub: String
    let lessons: [ProgLesson]
}
private struct ProgFile: Decodable { let v: Int; let tracks: [ProgTrack] }

@MainActor @Observable final class ProgModel {
    private(set) var tracks: [ProgTrack] = []
    private(set) var loadError: String?
    private(set) var done: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "prog.done") ?? [])

    /// The fetched copy (ThemeFeed, `pldev/prog.json`) when it reads, else the bundled one.
    init() {
        let url = Bundle.main.url(forResource: "prog", withExtension: "json")
            ?? Bundle.main.url(forResource: "prog", withExtension: "json", subdirectory: "Prog")
        guard let f = ThemeFeed.extra("prog.json").flatMap({ Self.decode($0) }) ?? url.flatMap({ try? Data(contentsOf: $0) }).flatMap({ Self.decode($0) }) else {
            loadError = "The lessons are missing from this build."; return
        }
        tracks = f.tracks
    }
    nonisolated private static func decode(_ data: Data) -> ProgFile? {
        guard let f = try? JSONDecoder().decode(ProgFile.self, from: data), f.v == 1, !f.tracks.isEmpty else { return nil }
        return f
    }
    nonisolated static func valid(_ data: Data) -> Bool { decode(data) != nil }

    func toggle(_ id: String) {
        if done.contains(id) { done.remove(id) } else { done.insert(id) }
        UserDefaults.standard.set(Array(done), forKey: "prog.done")
    }
    func count(_ t: ProgTrack) -> Int { t.lessons.filter { done.contains($0.id) }.count }
}

struct ProgView: View {
    @Bindable var state: ProgModel
    var body: some View {
        List { Group {
            if let e = state.loadError { ContentUnavailableView("No lessons", systemImage: "terminal", description: Text(e)) }
            Section {
                ForEach(state.tracks) { t in
                    NavigationLink { ProgTrackView(state: state, track: t).osScreen() } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.title).font(Font.pl(.headline))
                            Text("\(t.sub) · \(state.count(t)) of \(t.lessons.count) done").font(Font.pl(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Everything here runs on your R1: in Termux on the R1, Easy SSH on the iPhone, or the desktop on the iPad.").font(Font.pl(.footnote))
            }
        }.listRowBackground(PLRowGround()) }
        .navigationTitle("PL Prog")
    }
}

struct ProgTrackView: View {
    @Bindable var state: ProgModel
    let track: ProgTrack
    var body: some View {
        List { Group {
            ForEach(track.lessons) { l in
                NavigationLink { ProgLessonView(state: state, lesson: l).osScreen() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: state.done.contains(l.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(state.done.contains(l.id) ? Color.accentColor : .secondary)
                            .accessibilityLabel(state.done.contains(l.id) ? "Done" : "Not done")
                        Text(l.title).font(Font.pl(.body))
                    }
                }
            }
        }.listRowBackground(PLRowGround()) }
        .plScreenTitle(track.title)
    }
}

struct ProgLessonView: View {
    @Bindable var state: ProgModel
    let lesson: ProgLesson
    @State private var copied = 0
    @State private var cardPack: PackKey?   // a lesson first marked done earns a card pack (his ask 11-27)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(lesson.title).font(Font.pl(.title2).bold())
                if !lesson.image.isEmpty, let u = URL(string: lesson.image) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                        case .failure: Text("The picture did not load. Run the piece to make your own.").font(Font.pl(.footnote)).foregroundStyle(.secondary)
                        default: ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                    .accessibilityLabel("What \(lesson.title) makes")
                }
                if !lesson.text.isEmpty { Text(lesson.text).font(Font.pl(.body)) }
                if !lesson.run.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TYPE").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
                        ForEach(lesson.run, id: \.self) { cmd in copyRow(cmd) }
                    }
                }
                if !lesson.code.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("THE CODE").font(Font.pl(.caption)).foregroundStyle(Color.accentColor)
                            Spacer()
                            Button { copy(lesson.code) } label: { Label("Copy all", systemImage: "doc.on.doc") }
                                .buttonStyle(.bordered).frame(minHeight: 44)
                        }
                        ScrollView(.horizontal) {
                            Text(lesson.code).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(12)
                        }
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Button {
                    state.toggle(lesson.id)
                    if state.done.contains(lesson.id) { cardPack = PackEarn.fresh("prog-\(lesson.id)") }
                } label: {
                    Label(state.done.contains(lesson.id) ? "Done" : "Mark done",
                          systemImage: state.done.contains(lesson.id) ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .plScreenTitle(lesson.title)
        .sensoryFeedback(PLHaptic.select, trigger: copied)
        .earnsPack($cardPack)
    }

    private func copyRow(_ cmd: String) -> some View {
        Button { copy(cmd) } label: {
            HStack {
                Text(cmd).font(.system(.callout, design: .monospaced)).foregroundStyle(.primary).lineLimit(2)
                Spacer()
                Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Copy \(cmd)")
    }

    private func copy(_ s: String) { UIPasteboard.general.string = s; copied += 1 }
}
