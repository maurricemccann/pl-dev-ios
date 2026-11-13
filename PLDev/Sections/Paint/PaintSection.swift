import SwiftUI
import UserNotifications

/// Paint: a placeholder until its native build (sub-spec 1, phases P1 to P6). It says what is coming instead of
/// opening to nothing, and points at the web Paint that works today.
@MainActor enum PaintSection: PLSection {
    static let manifest = SectionManifest(id: "paint", title: "Paint", symbol: "paintbrush.pointed.fill", needsKeys: [], needsOrigins: ["gallery"])
    static func makeRoot(model: AppModel) -> AnyView { AnyView(ComingSection(model: model, title: "Paint", symbol: manifest.symbol, webPath: "paint/",
        points: ["Apple Pencil pressure, tilt and hover", "Layers, groups and blend modes", "His brushes from the toolkit",
                 "Sync with the laptop's PL Paint", "Send to Curate or the Archive"])) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
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
                        .background(SectionTile.tint(title.lowercased()).gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
