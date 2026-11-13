import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

/// Capture: text, links and photos into the intake (pl-cron captures, what pl-os Capture shows) or into the board's
/// escalation inbox. Also the sender for everything the share sheet and Safari saved: it sets InboxDrain's hook.
/// Shows what is waiting on him (pl-cron /api/widget/waiting) and hands that line to the widget.
@MainActor enum CaptureSection: PLSection {
    static let manifest = SectionManifest(id: "capture", title: "Capture", symbol: "square.and.arrow.down",
                                          needsKeys: ["widgetWrite"], needsOrigins: ["cron"])
    static let state = CaptureModel()

    static func makeRoot(model: AppModel) -> AnyView {
        install(model: model)
        return AnyView(CaptureView(model: model, state: state))
    }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }

    static func refresh(model: AppModel) async -> SectionRefresh {
        install(model: model)
        await model.drainInbox()
        await state.loadWaiting(model: model)
        return SectionRefresh(badge: model.inboxCount > 0 ? model.inboxCount : nil, notify: [])
    }

    /// Gives the offline queue its way out. Safe to call more than once.
    static func install(model: AppModel) {
        InboxDrain.sendItem = { item, file in await send(item, file: file, model: model) }
    }

    /// One queued item to its target. True when the server took it.
    static func send(_ item: QueuedItem, file: Data?, model: AppModel) async -> Bool {
        guard let http = model.http, let config = model.config, let write = config.key("widgetWrite") else { return false }
        let words = [item.note, item.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        do {
            if item.kind == "image" {
                guard let file, let jpeg = CaptureModel.jpeg(file) else {
                    model.debug.note("capture", "an image could not be read; dropped")
                    return true   // unreadable: retrying cannot help
                }
                _ = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/photo",
                                                    query: ["caption": String(words.prefix(300)), "source": "pl-dev"],
                                                    headers: ["content-type": "image/jpeg"], body: jpeg),
                                        idempotent: false, extraHeaders: ["Authorization": "Bearer " + write], timeout: 60)
                return true
            }
            guard !words.isEmpty else { return true }   // nothing to send
            if item.origin == "board", config.origin("board") != nil {
                let body = try JSONSerialization.data(withJSONObject: ["text": words, "context": "PL DEV capture"])
                _ = try await http.send(RequestPlan(origin: "board", method: "POST", path: "api/for-claude",
                                                    headers: ["content-type": "application/json"], body: body), idempotent: false)
            } else {
                let body = try JSONSerialization.data(withJSONObject: ["text": String(words.prefix(500)), "source": "pl-dev"])
                _ = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/capture",
                                                    headers: ["content-type": "application/json"], body: body),
                                        idempotent: false, extraHeaders: ["Authorization": "Bearer " + write])
            }
            return true
        } catch {
            model.debug.note("capture", "send failed, will retry: \(error.localizedDescription)")
            return false
        }
    }
}

@MainActor @Observable final class CaptureModel {
    struct Waiting: Decodable, Equatable {
        var drafts: Int?, pins: Int?, manual: Int?, ads: Int?, emails: Int?, tasks: Int?, captures: Int?, shift_open: Int?
    }
    var waiting: Waiting?
    var text = ""
    var toBoard = false
    var photo: Data?
    var sentTick = 0
    var message: String?

    /// The short line the widget shows, or nil before the first read.
    var waitingLine: String? {
        guard let w = waiting else { return nil }
        let parts: [(Int?, String)] = [(w.drafts, "drafts"), (w.pins, "Pins"), (w.tasks, "tasks"), (w.shift_open, "shift")]
        let shown = parts.compactMap { n, label in (n ?? 0) > 0 ? "\(n!) \(label)" : nil }
        return shown.isEmpty ? "Nothing waiting on you" : shown.joined(separator: " · ")
    }

    func loadWaiting(model: AppModel) async {
        guard let http = model.http else { return }
        if let data = try? await http.send(RequestPlan(origin: "cron", path: "api/widget/waiting")),
           let w = try? JSONDecoder().decode(Waiting.self, from: data) {
            waiting = w
            model.writeSnapshot()
        }
    }

    /// Saves the capture into the shared inbox (the same door the share sheet uses) and drains it.
    func submit(model: AppModel) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty || photo != nil else { return }
        let isLink = URL(string: words).map { ($0.scheme == "https" || $0.scheme == "http") && !words.contains(" ") } ?? false
        let item = SharedInbox.Item(id: UUID().uuidString, createdAt: Date(), source: "app",
                                    kind: photo != nil ? "image" : (isLink ? "url" : "text"),
                                    text: words.isEmpty ? nil : words, url: nil, title: nil,
                                    fileName: photo != nil ? "photo.jpg" : nil, note: nil,
                                    target: toBoard && photo == nil ? "board" : "cron")
        do {
            try SharedInbox.add(item, file: photo)
        } catch {
            message = error.localizedDescription
            return
        }
        CaptureSection.install(model: model)
        await model.drainInbox()
        text = ""; photo = nil; message = nil
        sentTick += 1
    }

    /// Any image the phone can read, as a JPEG under the server's 4 MB cap, longest side at most 2048.
    nonisolated static func jpeg(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = max(image.size.width, image.size.height)
        let scale = side > 2048 ? 2048 / side : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q in [0.85, 0.7, 0.5] {
            if let out = drawn.jpegData(compressionQuality: q), out.count < 4 * 1024 * 1024 { return out }
        }
        return nil
    }
}

struct CaptureView: View {
    let model: AppModel
    @Bindable var state: CaptureModel
    @State private var pick: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                TextField("A thought, a quote, a link", text: $state.text, axis: .vertical)
                    .lineLimit(3...10)
                PhotosPicker(selection: $pick, matching: .images) {
                    Label(state.photo == nil ? "Add a photo" : "Photo added", systemImage: state.photo == nil ? "photo" : "checkmark.circle.fill")
                }
                if state.photo == nil {
                    Toggle("Send to the board instead", isOn: $state.toBoard)
                }
                Button("Capture") { Task { await state.submit(model: model) } }
                    .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.photo == nil)
                if let m = state.message { Text(m).foregroundStyle(.red) }
            } footer: {
                Text(state.toBoard && state.photo == nil ? "Goes to the board's inbox for Claude." :
                        "Goes to the intake, where pl-os Capture shows it. Nothing is posted anywhere.")
            }
            Section("Waiting to send") {
                LabeledContent("Items", value: "\(model.inboxCount)")
                Button("Send now") { Task { CaptureSection.install(model: model); await model.drainInbox() } }
                    .disabled(model.inboxCount == 0)
            }
            Section("Waiting on you") {
                if let w = state.waiting {
                    row("Drafts", w.drafts); row("Pins", w.pins); row("Manual posts", w.manual); row("Ads", w.ads)
                    row("Emails", w.emails); row("Tasks", w.tasks); row("New captures", w.captures); row("Shift items open", w.shift_open)
                } else {
                    Text("Pull down to read.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Capture")
        .refreshable { await state.loadWaiting(model: model) }
        .task { await state.loadWaiting(model: model) }
        .sensoryFeedback(PLHaptic.success, trigger: state.sentTick)
        .onChange(of: pick) { _, item in
            Task { state.photo = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    private func row(_ label: String, _ n: Int?) -> some View {
        LabeledContent(label, value: n.map(String.init) ?? "?")
    }
}
