import SwiftUI
import UIKit
import UserNotifications

/// Capture: pl-os Intake on the phone. Artwork, text, a quote or a link go into the intake (what pl-os Capture shows); the board's
/// inbox for Claude is the other door. It is also the sender for everything the share sheet and Safari saved: it sets InboxDrain's hook.
/// Shows what is waiting on him (pl-cron /api/widget/waiting) and hands that line to the widget.
/// The look is pl-os's (House's skin), because the web app it twins lives in pl-os.
@MainActor enum CaptureSection: PLSection {
    static let manifest = SectionManifest(id: "capture", title: "Capture", symbol: "square.and.arrow.down",
                                          needsKeys: ["widgetWrite"], needsOrigins: ["cron"])
    static let state = CaptureModel()

    static func makeRoot(model: AppModel) -> AnyView {
        install(model: model)
        return AnyView(CaptureView(model: model, state: state))
    }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }

    /// Capture's own Settings rows: the rooms back into Spotlight.
    static func settingsRows(model: AppModel) -> AnyView? {
        AnyView(Button { Task { await CaptureSpotlight.index() } } label: {
            SettingsLabel("Add Capture rooms to Spotlight again", "magnifyingglass", Color(uiColor: .systemGray))
        })
    }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }

    /// `pldev://section/capture/<add|trail|waiting>?mode=<artwork|text|quote|link>`
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, let query) = link {
            if let first = path.first, let room = CaptureRoom(rawValue: first) { state.room = room }
            if let mode = query["mode"], let kind = CaptureKind(rawValue: mode) { state.room = .add; state.switchKind(kind) }
        }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        install(model: model)
        await model.drainInbox()
        await state.loadWaiting(model: model)
        state.log = CaptureLog.read()
        state.publishGlance(model: model)
        return SectionRefresh(badge: model.inboxCount > 0 ? model.inboxCount : nil, notify: [])
    }

    /// Gives the offline queue its way out. Safe to call more than once.
    static func install(model: AppModel) {
        InboxDrain.sendItem = { item, file in await send(item, file: file, model: model) }
    }

    /// One queued item to its target. True when the server took it.
    static func send(_ item: QueuedItem, file: Data?, model: AppModel) async -> Bool {
        guard let http = model.http, let config = model.config, let write = config.key("widgetWrite") else { return false }
        // a link from the share sheet carries its title in the note: the address leads, as pl-os writes it
        let parts = item.kind == "url" ? [item.text, item.note] : [item.note, item.text]
        let words = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        do {
            if item.kind == "image" {
                guard let file, let jpeg = CaptureModel.jpeg(file) else {
                    model.debug.note("capture", "an image could not be read; dropped")
                    state.markSent(item.id)
                    return true   // unreadable: retrying cannot help
                }
                let data = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/photo",
                                                           query: ["caption": String(words.prefix(300)), "source": "pl-dev"],
                                                           headers: ["content-type": "image/jpeg"], body: jpeg),
                                               idempotent: false, extraHeaders: ["Authorization": "Bearer " + write], timeout: 60)
                state.noteCap(from: data)
                state.markSent(item.id)
                return true
            }
            guard !words.isEmpty else { return true }   // nothing to send
            if item.origin == "board", config.origin("board") != nil {
                let body = try JSONSerialization.data(withJSONObject: ["text": words, "context": "PL DEV capture"])
                _ = try await http.send(RequestPlan(origin: "board", method: "POST", path: "api/for-claude",
                                                    headers: ["content-type": "application/json"], body: body), idempotent: false)
                state.markSent(item.id)
                return true
            }
            // The console door keeps the capture's type and up to 8000 characters (pl-os Intake). The widget door is the way
            // when the console is not in the config, or refuses: it takes plain text, 500 characters.
            if config.origin("console") != nil {
                let type = ["quote": "quote", "url": "link", "link": "link"][item.kind] ?? "text"
                if let body = try? JSONSerialization.data(withJSONObject: ["type": type, "note": String(words.prefix(8000))]),
                   (try? await http.send(RequestPlan(origin: "console", method: "POST", path: "api/pldev/x/intake",
                                                     headers: ["content-type": "application/json"], body: body), idempotent: false)) != nil {
                    state.markSent(item.id)
                    return true
                }
            }
            let body = try JSONSerialization.data(withJSONObject: ["text": String(words.prefix(500)), "source": "pl-dev"])
            let data = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/capture",
                                                       headers: ["content-type": "application/json"], body: body),
                                           idempotent: false, extraHeaders: ["Authorization": "Bearer " + write])
            state.noteCap(from: data)
            state.markSent(item.id)
            return true
        } catch {
            model.debug.note("capture", "send failed, will retry: \(error.localizedDescription)")
            return false
        }
    }
}
