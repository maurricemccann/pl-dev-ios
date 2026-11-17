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
            if let mode = query["mode"], let route = CaptureRoute(rawValue: mode), route == .thought || route == .task {   // the widget's Thought and Task buttons
                state.room = .add; state.presetRoute = route
            } else if let mode = query["mode"], let kind = CaptureKind(rawValue: mode) { state.room = .add; state.switchKind(kind) }
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
                // 11-14 his ruling (smart capture): a photo of a new piece goes into the ART inbox (the archive pipeline: duplicate scan, name,
                // PL number, /curate verdict), the same inbox as the "New art" Shortcut, not the older caption-only photo lane. The title is
                // his words; "made" is the day it was captured, on this phone's calendar.
                let day = DateFormatter()
                day.dateFormat = "yyyy-MM-dd"
                day.locale = Locale(identifier: "en_US_POSIX")
                // his rules 11-14: the year comes from the photo itself when it says (else the day captured); his signature goes into the
                // image's metadata; a medium travels only when one was given (a camera capture of a physical piece)
                let made = CaptureMeta.madeDate(of: file) ?? day.string(from: item.createdAt)
                let title = String((item.note ?? "").prefix(120))
                let medium = String((item.text ?? "").prefix(80))
                let signedJPEG = CaptureMeta.signed(jpeg, artist: config.capture?.signature ?? "Psyched Luxuries", made: made, title: title)
                var query = ["title": title, "made": made]
                if !medium.isEmpty { query["medium"] = medium }
                let data = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/art",
                                                           query: query,
                                                           headers: ["content-type": "image/jpeg"], body: signedJPEG),
                                               idempotent: false, extraHeaders: ["Authorization": "Bearer " + write], timeout: 60)
                state.noteCap(from: data)
                state.markSent(item.id)
                return true
            }
            if item.kind == "video" {   // his pick N22, 11-14: up to 100 MB, into Captures for keep or release
                guard let file, file.count <= 100 * 1024 * 1024 else {
                    model.debug.note("capture", "a video over 100 MB or unreadable; dropped")
                    state.markSent(item.id)
                    return true
                }
                let isMov = String(decoding: file.prefix(12).suffix(8), as: UTF8.self).contains("qt")
                let data = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/video",
                                                           query: ["title": String((item.note ?? "").prefix(120))],
                                                           headers: ["content-type": isMov ? "video/quicktime" : "video/mp4"], body: file),
                                               idempotent: false, extraHeaders: ["Authorization": "Bearer " + write], timeout: 300)
                state.noteCap(from: data)
                state.markSent(item.id)
                return true
            }
            guard !words.isEmpty else { return true }   // nothing to send
            if item.kind == "thought" || item.kind == "task" {   // capture route (11-17): pl-cron keeps them for the PC sync into THOUGHTS.md
                let body = try JSONSerialization.data(withJSONObject: ["text": String(words.prefix(2000)), "source": "pl-" + item.kind])
                let data = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/capture",
                                                           headers: ["content-type": "application/json"], body: body),
                                               idempotent: false, extraHeaders: ["Authorization": "Bearer " + write])
                state.noteCap(from: data)
                state.markSent(item.id)
                return true
            }
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
