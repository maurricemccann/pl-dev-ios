import Foundation
import Observation
import UIKit

/// The capability probe: each item really exercises the feature on this install and says pass or fail with the reason.
/// Nothing about a free-signed install is believed until it passes here. No result ever shows an address or a key.
@MainActor @Observable final class ProbeModel {
    struct Item: Identifiable {
        let id: String
        var title: String
        var detail: String
        var result: Result
        var run: @MainActor () async -> Result

        enum Result { case untested, running, pass(String), fail(String) }
    }

    var items: [Item] = []

    @ObservationIgnored private var bySection: [String: [String]] = [:]   // section id -> the probe ids it owns

    /// Builds the list for the loaded config: the shell's checks, one per configured address, then each section's own.
    /// A result already on screen is kept when its item survives the rebuild.
    func rebuild(model: AppModel) {
        var old: [String: Item.Result] = [:]
        for item in items { old[item.id] = item.result }
        var all = Self.shell()
        for name in (model.config?.origins.keys.sorted() ?? []) {
            all.append(Item(id: "origin." + name, title: "Address: " + name, detail: "Asks the address named \u{201C}\(name)\u{201D} for an answer and checks its certificate name.",
                            result: .untested, run: { await Self.origin(name) }))
        }
        bySection = [:]
        for section in SectionRegistry.all {
            let own = section.probes(model: model)
            bySection[section.manifest.id] = own.map(\.id) + section.manifest.needsOrigins.map { "origin." + $0 }
            all.append(contentsOf: own)
        }
        for index in all.indices {
            if let kept = old[all[index].id] { all[index].result = kept }
        }
        items = all
    }

    func run(_ id: String) async {
        guard let item = items.first(where: { $0.id == id }), !isRunning(item) else { return }
        mark(id, .running)
        let result = await item.run()
        mark(id, result)
    }

    /// One after another: a few of these write to the same shared store.
    func runAll() async {
        for id in items.map(\.id) { await run(id) }
    }

    /// The checks one section depends on. A section that declares none gets the whole list.
    func run(section id: String) async {
        let own = bySection[id] ?? []
        if own.isEmpty {
            await runAll()
        } else {
            for probe in own { await run(probe) }
        }
    }

    func isRunning(_ item: Item) -> Bool {
        if case .running = item.result { return true }
        return false
    }

    private func mark(_ id: String, _ result: Item.Result) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].result = result
    }

    // MARK: the shell's own checks

    private static let noContainer = "This signing has no shared container, so the app and its extensions cannot hand anything to each other."

    private static func shell() -> [Item] {
        [
            Item(id: "config", title: "Config", detail: "Checks that a config is loaded and valid.", result: .untested, run: { config() }),
            Item(id: "keychain", title: "Keychain", detail: "Writes, reads and removes one throwaway item.", result: .untested, run: { await keychain() }),
            Item(id: "appGroup", title: "Shared container", detail: "Checks the store the widget and the extensions share with the app.", result: .untested, run: { appGroup() }),
            Item(id: "sharedKeychain", title: "Shared Keychain", detail: "Tries a Keychain item the extensions could read. Nothing depends on it.", result: .untested, run: { await sharedKeychain() }),
            Item(id: "notification", title: "Notification", detail: "Asks for permission and shows one notice.", result: .untested, run: { await notification() }),
            Item(id: "backgroundRefresh", title: "Background refresh", detail: "Asks the system for a background refresh.", result: .untested, run: { backgroundRefresh() }),
            Item(id: "widgetFetch", title: "Widget state", detail: "Writes and reads back what the widget shows.", result: .untested, run: { widgetFetch() }),
            Item(id: "shareInbox", title: "Share sheet inbox", detail: "Checks the inbox the share sheet writes into.", result: .untested, run: { inbox(source: "share", name: "the share sheet") }),
            Item(id: "safariInbox", title: "Safari inbox", detail: "Checks the inbox the Safari extension writes into.", result: .untested, run: { inbox(source: "safari", name: "the Safari extension") })
        ]
    }

    private static func config() -> Item.Result {
        guard let config = AppModel.shared.config else { return .fail("No config is loaded.") }
        let set = config.keys.keys.filter { config.key($0) != nil }.count
        return .pass("Version \(config.v): \(config.sections.count) section(s) listed, \(config.origins.count) address(es), \(set) key(s) set.")
    }

    private static func keychain() async -> Item.Result {
        let problem = await Task.detached { KeyStore.roundTrip() }.value
        if let problem { return .fail(problem) }
        return .pass("The Keychain holds and returns an item.")
    }

    private static func appGroup() -> Item.Result {
        SharedState.isAvailable ? .pass("The shared container opens.") : .fail(noContainer)
    }

    private static func sharedKeychain() async -> Item.Result {
        guard let group = SharedState.groupID else { return .fail(noContainer) }
        let outcome = await Task.detached { KeyStore.sharedProbe(group: group) }.value
        return outcome.ok ? .pass(outcome.detail) : .fail(outcome.detail)
    }

    private static func notification() async -> Item.Result {
        guard await NotificationHub.shared.authorize() else { return .fail("Notifications are off for this app in Settings.") }
        if let refused = await NotificationHub.shared.postProbe() { return .fail("The system refused the notice: \(refused)") }
        return .pass("Allowed, and a notice was shown.")
    }

    private static func backgroundRefresh() -> Item.Result {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .denied: return .fail("Background App Refresh is off for this app in Settings.")
        case .restricted: return .fail("Background App Refresh is restricted on this iPhone.")
        case .available: break
        @unknown default: break
        }
        if let refused = Poller.shared.schedule() { return .fail("The system refused the request: \(refused)") }
        return .pass("The system took a refresh request. iOS decides when it runs.")
    }

    private static func widgetFetch() -> Item.Result {
        guard SharedState.isAvailable else { return .fail(noContainer) }
        let before = SharedState.readSnapshot()
        let token = "probe \(Int(Date().timeIntervalSince1970))"
        SharedState.writeSnapshot(WidgetSnapshot(updatedAt: Date(), inboxCount: 0, badges: [:], statusLine: token))
        let back = SharedState.readSnapshot()?.statusLine
        if let before {
            SharedState.writeSnapshot(before)
        } else {
            AppModel.shared.writeSnapshot()
        }
        if back == token { return .pass("The shared store works. The widget reads it; it never uses the network.") }
        return .fail("The shared store did not hold what was written.")
    }

    private static func inbox(source: String, name: String) -> Item.Result {
        guard SharedInbox.isAvailable else { return .fail(noContainer) }
        let waiting = SharedInbox.all().filter { $0.source == source }.count
        let item = SharedInbox.Item(id: "probe-" + UUID().uuidString, createdAt: Date(), source: "probe", kind: "text",
                                    text: "probe", url: nil, title: nil, fileName: nil, note: nil)
        do {
            try SharedInbox.add(item, file: nil)
        } catch {
            return .fail("The inbox refused a write: \(Scrub.clean(error.localizedDescription))")
        }
        let held = SharedInbox.all().contains { $0.id == item.id }
        SharedInbox.remove(item.id)
        guard held else { return .fail("The inbox did not hold what was written.") }
        return .pass("The inbox works. \(waiting) item(s) from \(name) are waiting there.")
    }

    private static func origin(_ name: String) async -> Item.Result {
        switch await AppModel.shared.reach(name) {
        case .up(let status): return .pass("Reachable. It answered \(status).")
        case .down(let reason): return .fail(reason)
        case .unknown, .checking: return .fail("No answer.")
        }
    }
}
