import SwiftUI
import UserNotifications
import WidgetKit

/// PL Paint: the native painter. The canvas is `Native/` (the laptop's engine, ported); this file is the section around it: the app's home
/// (continue, new, the Daily Mark, his works on this phone and the ones waiting from the laptop, the outbox, the handbook) and the sync key.
/// There is no web canvas any more. The sync key comes from the config and is read by the native sync, so he never pastes it.
@MainActor enum PaintSection: PLSection {
    static let manifest = SectionManifest(id: "paint", title: "Paint", symbol: "paintbrush.pointed.fill", needsKeys: ["paintSync"], needsOrigins: ["gallery", "paint"])
    static let state = PaintModel()
    static func makeRoot(model: AppModel) -> AnyView { AnyView(PaintHome(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, path.first == "canvas" || path.first == "native" {
            state.openCanvas(work: nil, panel: path.count > 1 ? PaintRoom(rawValue: path[1])?.panel : nil)
        }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh { await state.load(model: model); await PaintSpotlight.index(); return SectionRefresh(badge: nil, notify: []) }
}

/// What the canvas is asked to open: the current work, or one by id.
struct PaintCanvasRequest: Identifiable { let id = UUID(); let work: String?; var panel: NativePanel? = nil; var setup: (@MainActor (NativeCanvasModel) -> Void)? = nil }

@MainActor @Observable final class PaintModel {
    struct Work: Identifiable { let id: String; let name: String; let w: Int; let h: Int; let updated: Date; let thumb: UIImage?; let here: Bool; var stack: String? = nil; var entry: NativeRemote.Entry? = nil }
    struct Outbox: Decodable { struct Item: Decodable, Identifiable { let id: String; let title: String?; let dest: String?; let at: Double? }; let items: [Item] }
    var works: [Work] = []
    var days: [String: Int] = NativeDaily.days
    var outbox: [Outbox.Item] = []
    var failed: String?
    var request: PaintCanvasRequest?
    var synced = false
    /// The gallery edits the index through a canvas model with no document open (rename, copy, delete, stack all live there).
    let ops = NativeCanvasModel()

    func openCanvas(work: String?, panel: NativePanel? = nil) { request = PaintCanvasRequest(work: work, panel: panel) }

    /// His works: the ones on this phone first-hand, then the laptop's that are not here yet. The Daily Mark merges what the laptop counted.
    func load(model: AppModel) async {
        func thumb(_ s: String?) -> UIImage? { s.flatMap { NativeDoc.image(fromDataURL: $0) }.map { UIImage(cgImage: $0) } }
        let local = NativeStore.loadIndex().list.map { e in
            Work(id: e["id"] as? String ?? "", name: e["name"] as? String ?? "Untitled", w: e["w"] as? Int ?? 0, h: e["h"] as? Int ?? 0,
                 updated: Date(timeIntervalSince1970: ((e["updated"] as? Double) ?? Double(e["updated"] as? Int ?? 0)) / 1000), thumb: thumb(e["thumb"] as? String), here: true, stack: (e["stack"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        works = local.sorted { $0.updated > $1.updated }
        days = NativeDaily.days
        publish()
        guard let http = model.http else { return }
        do {
            let remote = try await NativeRemote.list(http)
            let have = Set(local.map(\.id))
            works += remote.filter { !have.contains($0.id) }.map { Work(id: $0.id, name: $0.name, w: $0.w, h: $0.h, updated: Date(timeIntervalSince1970: $0.updated / 1000), thumb: $0.thumb, here: false, entry: $0) }
            struct Daily: Decodable { let days: [String: Int]? }
            if let dd = try? await http.send(RequestPlan(origin: "paint", path: "file/daily.json")) {
                let theirs = (try? JSONDecoder().decode(Daily.self, from: dd))?.days ?? [:]
                days = days.merging(theirs) { max($0, $1) }
            }
            if let ob = try? await http.send(RequestPlan(origin: "paint", path: "outbox")) { outbox = (try? JSONDecoder().decode(Outbox.self, from: ob))?.items ?? [] }
            failed = nil
            publish()
        } catch { failed = works.isEmpty ? "Your works did not load. Pull to try again." : "The laptop's works did not load. Pull to try again." }
    }

    /// The widget's numbers: the Daily Mark this month and today.
    private func publish() {
        let today = NativeDaily.key(), month = String(today.prefix(7))
        SharedState.writePaint(PaintGlance(today: days[today] ?? 0, monthDays: days.keys.filter { $0.hasPrefix(month) }.count, works: works.count, updatedAt: .now))
    }

    /// Consecutive days with a mark, ending today or yesterday.
    var streak: Int {
        var d = Date(), n = 0
        if days[NativeDaily.key(d)] == nil { d = d.addingTimeInterval(-86400) }
        while days[NativeDaily.key(d)] != nil { n += 1; d = d.addingTimeInterval(-86400) }
        return n
    }
}

/// PL Paint's own look (its `style.css` and kit.css): the dark ground, the warm cream text, his gold for the one active thing, panels as thin glass.
enum PaintSkin {
    static let ground = Color(red: 0.055, green: 0.047, blue: 0.031)     // #0e0c08
    static let text = Color(red: 0.937, green: 0.914, blue: 0.863)       // #efe9dc
    static let gold = Color(red: 0.788, green: 0.659, blue: 0.298)       // #c9a84c
    static let gold2 = Color(red: 0.906, green: 0.812, blue: 0.525)      // #e7cf86
}

/// The last five weeks of marks, darker for more strokes (the laptop's Daily Mark, as a strip).
struct DailyMarkStrip: View {
    let days: [String: Int]
    var body: some View {
        let dates = (0..<35).reversed().map { Date().addingTimeInterval(-Double($0) * 86400) }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(dates, id: \.self) { d in
                let n = days[NativeDaily.key(d)] ?? 0
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(n == 0 ? Color.white.opacity(0.07) : PaintSkin.gold.opacity(min(1, 0.3 + Double(n) / 200)))
                    .frame(height: 18)
                    .accessibilityLabel("\(d.formatted(date: .abbreviated, time: .omitted)): \(n) strokes")
            }
        }
    }
}

/// The screen a placeholder app opens to: what it will be, and the web version to use until then.
struct ComingSection: View {
    let model: AppModel
    let title: String
    let symbol: String
    let webPath: String?
    var webURL: String? = nil   // a full address, for a web version that is not on the gallery
    let points: [String]
    @Environment(\.openURL) private var openURL

    // explicit: a private property would make the synthesized initializer file-private, and other files build these
    init(model: AppModel, title: String, symbol: String, webPath: String?, webURL: String? = nil, points: [String]) {
        self.model = model; self.title = title; self.symbol = symbol; self.webPath = webPath; self.webURL = webURL; self.points = points
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Wallpaper.line.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("\(title) is being built").font(.title2.bold())
                    Text("A native version is on the way. This tile is its place on the grid.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)
            Section("What it will have") {
                ForEach(points, id: \.self) { Label($0, systemImage: "checkmark.circle") }
            }
            if let url = webURL.flatMap(URL.init(string:)) ?? webPath.flatMap({ p in model.config?.origin("gallery").flatMap { URL(string: $0.base + p) } }) {
                Section {
                    Button { openURL(url) } label: { Label("Open the web version", systemImage: "safari") }
                } footer: { Text("Works today, in Safari.") }
            }
        }
        .navigationTitle(title)
    }
}
