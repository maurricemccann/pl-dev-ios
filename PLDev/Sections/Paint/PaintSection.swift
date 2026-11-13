import SwiftUI
import UserNotifications
import WebKit
import WidgetKit

/// PL Paint (his order 11-13, "Composer and PL Paint"). The painter itself is his PL Paint: the same `src/` as the laptop app,
/// served at the gallery's /paint/, run full screen with Apple Pencil pressure and tilt passing through, so laptop and phone can
/// never drift (the twin rule). Native around it: his synced works, the Daily Mark, the outbox, the widget. The sync key comes
/// from the config and is placed where the app keeps it, so he never pastes it. A native Metal stamp engine (sub-spec 1, P1-P6)
/// stays the later upgrade.
@MainActor enum PaintSection: PLSection {
    static let manifest = SectionManifest(id: "paint", title: "Paint", symbol: "paintbrush.pointed.fill", needsKeys: ["paintSync"], needsOrigins: ["gallery", "paint"])
    static let state = PaintModel()
    static func makeRoot(model: AppModel) -> AnyView { AnyView(PaintHome(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, path.first == "canvas" { state.canvasOpen = true }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh { await state.load(model: model); return SectionRefresh(badge: nil, notify: []) }
}

@MainActor @Observable final class PaintModel {
    struct Work: Identifiable { let id: String; let name: String; let w: Int; let h: Int; let updated: Date; let thumb: UIImage? }
    struct Outbox: Decodable { struct Item: Decodable, Identifiable { let id: String; let title: String?; let dest: String?; let at: Double? }; let items: [Item] }
    var works: [Work] = []
    var days: [String: Int] = [:]
    var outbox: [Outbox.Item] = []
    var failed: String?
    var canvasOpen = false

    func load(model: AppModel) async {
        guard let http = model.http else { return }
        do {
            let d = try await http.send(RequestPlan(origin: "paint", path: "index"), timeout: 30)
            let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
            let raw = o["works"] as? [String: [String: Any]] ?? [:]
            works = raw.map { id, m in
                let thumb = (m["thumb"] as? String).flatMap { s -> UIImage? in
                    guard let c = s.firstIndex(of: ",") else { return nil }
                    return Data(base64Encoded: String(s[s.index(after: c)...])).flatMap(UIImage.init(data:))
                }
                let updated = (m["updated"] as? Double) ?? Double(m["updated"] as? Int ?? 0)
                return Work(id: id, name: m["name"] as? String ?? "Untitled", w: m["w"] as? Int ?? 0, h: m["h"] as? Int ?? 0,
                            updated: Date(timeIntervalSince1970: updated / 1000), thumb: thumb)
            }.sorted { $0.updated > $1.updated }
            struct Daily: Decodable { let days: [String: Int]? }
            if let dd = try? await http.send(RequestPlan(origin: "paint", path: "file/daily.json")) { days = (try? JSONDecoder().decode(Daily.self, from: dd))?.days ?? [:] }
            if let ob = try? await http.send(RequestPlan(origin: "paint", path: "outbox")) { outbox = (try? JSONDecoder().decode(Outbox.self, from: ob))?.items ?? [] }
            failed = nil
            publish()
        } catch { failed = "Your works did not load. Pull to try again." }
    }

    /// The widget's numbers: the Daily Mark this month and today.
    private func publish() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: .now), month = String(today.prefix(7))
        SharedState.writePaint(PaintGlance(today: days[today] ?? 0, monthDays: days.keys.filter { $0.hasPrefix(month) }.count, works: works.count, updatedAt: .now))
    }

    /// Consecutive days with a mark, ending today or yesterday.
    var streak: Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var d = Date(), n = 0
        if days[f.string(from: d)] == nil { d = d.addingTimeInterval(-86400) }
        while days[f.string(from: d)] != nil { n += 1; d = d.addingTimeInterval(-86400) }
        return n
    }
}

struct PaintHome: View {
    let model: AppModel
    @Bindable var state: PaintModel
    @State private var nativeOpen = false

    var body: some View {
        List {
            Section {
                Button { state.canvasOpen = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "paintbrush.pointed.fill").font(.title).foregroundStyle(.white)
                            .frame(width: 56, height: 56).background(Wallpaper.line.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open the canvas").font(.headline)
                            Text("PL Paint, the same app as the laptop. Apple Pencil pressure and tilt.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                // lane C (11-13): the native engine, beside the web canvas until it matches it
                Button { nativeOpen = true } label: {
                    Label { VStack(alignment: .leading, spacing: 2) { Text("Native canvas (beta)"); Text("Built for the iPhone: your brushes, layers and blends. Works stay on this iPhone for now.").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "paintbrush.pointed") }
                }
            }
            if let f = state.failed { Text(f).foregroundStyle(.secondary) }
            Section("The Daily Mark") {
                LabeledContent("Streak", value: "\(state.streak) days")
                DailyMarkStrip(days: state.days)
            }
            Section("Your works · \(state.works.count)") {
                if state.works.isEmpty && state.failed == nil { Text("Nothing synced yet. Works you make on the laptop or here appear in this list.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(state.works) { w in
                        Button { state.canvasOpen = true } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Group {
                                    if let t = w.thumb { Image(uiImage: t).resizable().scaledToFit() } else { Color.secondary.opacity(0.12) }
                                }
                                .frame(height: 110).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(w.name).font(.caption).lineLimit(1)
                                Text(w.updated, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !state.outbox.isEmpty {
                Section {
                    ForEach(state.outbox) { i in LabeledContent(i.title ?? i.id, value: (i.dest ?? "").capitalized) }
                } header: { Text("Waiting to be filed") } footer: { Text("Sent to Curate or the Archive; the PC files them.") }
            }
            Section { NavigationLink("The handbook") { GalleryCanvas(model: model, path: "paint/handbook/", title: "Handbook") } }
        }
        .navigationTitle("Paint")
        .fullScreenCover(isPresented: $nativeOpen) { NativeCanvasView(model: model) }
        .refreshable { await state.load(model: model) }
        .task { await state.load(model: model) }
        .fullScreenCover(isPresented: $state.canvasOpen, onDismiss: { Task { await state.load(model: model) } }) {
            PaintCanvas(model: model) { state.canvasOpen = false }
        }
    }
}

/// The last five weeks of marks, darker for more strokes (the laptop's Daily Mark, as a strip).
struct DailyMarkStrip: View {
    let days: [String: Int]
    var body: some View {
        let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
        let dates = (0..<35).reversed().map { Date().addingTimeInterval(-Double($0) * 86400) }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(dates, id: \.self) { d in
                let n = days[f.string(from: d)] ?? 0
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(n == 0 ? Color.secondary.opacity(0.12) : Wallpaper.line.opacity(min(1, 0.3 + Double(n) / 200)))
                    .frame(height: 18)
                    .accessibilityLabel("\(d.formatted(date: .abbreviated, time: .omitted)): \(n) strokes")
            }
        }
    }
}

/// His PL Paint, full screen. The config's sync key is placed in the app's own store before it starts.
struct PaintCanvas: View {
    let model: AppModel
    let close: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            PaintWeb(model: model).ignoresSafeArea()
            Button(action: close) { Image(systemName: "xmark").font(.headline).padding(12) }
                .glassControl(in: Circle())
                .padding(.leading, 12).padding(.top, 4)
                .accessibilityLabel("Close the canvas")
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

struct PaintWeb: UIViewRepresentable {
    let model: AppModel
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        if let key = model.config?.key("paintSync"), key.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil {
            // The app reads {key, device, last} from localStorage "plpaint-sync" (src/sync.js); only fill it when empty.
            let host = URL(string: LibraryData.shared.base(model))?.host ?? ""
            let js = "try{if(location.host==='\(host)'&&location.pathname.indexOf('/paint/')===0){var s=JSON.parse(localStorage.getItem('plpaint-sync')||'{}');if(!s.key){s.key='\(key)';s.device=s.device||'iphone-pldev';s.last=s.last||0;localStorage.setItem('plpaint-sync',JSON.stringify(s));}}}catch(e){}"
            cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if let u = URL(string: LibraryData.shared.base(model) + "/paint/") { web.load(URLRequest(url: u)) }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
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
