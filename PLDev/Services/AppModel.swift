import SwiftUI

/// Whether one configured address answered. The address itself is never part of this.
enum OriginReach: Equatable {
    case unknown, checking, up(Int), down(String)
}

/// The one model the shell binds to: the loaded config, the sections it allows, where a link wants to go, and what waits to be sent.
@MainActor @Observable final class AppModel {
    static let shared = AppModel()

    var config: PLDevConfig?                 // nil = show the config gate
    var configError: String?
    var sections: [SectionEntry] = []        // registered sections in the config's order, each with its readiness
    var route: DeepLink?                     // set by onOpenURL, intents and notifications
    var inboxCount = 0                       // items waiting in the shared inbox / offline queue
    var lastError: String?
    var restoring = true                     // the saved config is still being read back from the Keychain

    let probes = ProbeModel()
    let debug = DebugLog()

    @ObservationIgnored private let store = ConfigStore()
    @ObservationIgnored private(set) var http: HTTPClient?   // exists only while a config is loaded
    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    private init() {
        restoreTask = Task { await restore() }
    }

    // MARK: config

    /// A background launch waits here so a refresh never runs before the saved config is back.
    func restoreIfNeeded() async {
        await restoreTask?.value
    }

    private func restore() async {
        if let saved = await store.saved() { apply(saved) }
        restoring = false
    }

    func loadConfig(from url: URL) async {
        do {
            let loaded = try await store.load(from: url)
            apply(loaded)
            debug.note("config", "loaded: \(loaded.sections.count) sections, \(loaded.origins.count) addresses")
        } catch {
            configError = plainSentence(error)
        }
    }

    func forgetConfig() {
        Task { await store.forget() }
        SharedState.clearPublicConfig()   // the extensions lose their keyless copy too
        config = nil
        http = nil
        configError = nil
        lastError = nil
        route = nil
        sections = []
        probes.rebuild(model: self)
        debug.note("config", "forgotten")
    }

    private func apply(_ loaded: PLDevConfig) {
        config = loaded
        configError = nil
        http = HTTPClient(config: loaded)
        if UserDefaults.standard.object(forKey: "pldev.font") == nil, loaded.theme?.fontFamily?.lowercased() == "jost" {
            UserDefaults.standard.set("jost", forKey: "pldev.font")   // the config may suggest the text face; a choice made in Settings wins
        }
        ThemePack.shared.titleAllowed = loaded.theme?.handTitle ?? true
        rebuildSections()
        probes.rebuild(model: self)
        SharedState.writePublicConfig(loaded.publicCopy)   // the keyless copy: the only form that leaves the Keychain
        inboxCount = InboxDrain.waiting
        writeSnapshot()
    }

    private func rebuildSections() {
        guard let config else {
            sections = []
            return
        }
        var badges: [String: Int] = [:]
        for entry in sections { badges[entry.id] = entry.badge }
        var seen = Set<String>()
        var built: [SectionEntry] = []
        for id in config.sections where seen.insert(id).inserted {
            guard let section = SectionRegistry.section(id) else { continue }   // a section this build does not have yet
            let manifest = section.manifest
            built.append(SectionEntry(manifest: manifest, readiness: manifest.readiness(in: config),
                                      makeRoot: { SectionRegistry.section(id)?.makeRoot(model: AppModel.shared) ?? AnyView(EmptyView()) },
                                      badge: badges[id]))
        }
        sections = built
    }

    /// Every key name a registered section declared, for the Keys rows in Settings.
    var neededKeys: [String] {
        var names = Set<String>()
        for section in SectionRegistry.all { names.formUnion(section.manifest.needsKeys) }
        return names.sorted()
    }

    // MARK: routes

    func open(_ link: DeepLink) {
        route = link
        debug.note("route", "open \(link.url.host ?? "")")
    }

    // MARK: inbox, badges, widget

    /// Sends what the extensions dropped into the App Group, through the offline queue.
    func drainInbox() async {
        await InboxDrain.run(model: self)
    }

    func setBadge(_ badge: Int?, for id: String) {
        guard let index = sections.firstIndex(where: { $0.id == id }), sections[index].badge != badge else { return }
        sections[index].badge = badge
    }

    /// What the widget shows. Counts and a short line only.
    func writeSnapshot() {
        var badges: [String: Int] = [:]
        for entry in sections {
            if let badge = entry.badge, badge > 0 { badges[entry.id] = badge }
        }
        let line = inboxCount > 0 ? "\(inboxCount) waiting to send" : (CaptureSection.state.waitingLine ?? "Up to date")
        SharedState.writeSnapshot(WidgetSnapshot(updatedAt: Date(), inboxCount: inboxCount, badges: badges, statusLine: line))
    }

    // MARK: reachability

    /// One request to a configured address: its health path when the Status section knows one, else a HEAD of the base.
    /// Any answer at all, whatever the status code, means the address is reachable.
    func reach(_ name: String) async -> OriginReach {
        guard let http else { return .down("Load your config first.") }
        let health = StatusSection.healthPaths[name]
        let plan = RequestPlan(origin: name, method: health == nil ? "HEAD" : "GET", path: health ?? "")
        do {
            return .up(try await http.status(plan))
        } catch {
            return .down(plainSentence(error))
        }
    }
}
