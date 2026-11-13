import Foundation

/// Moves what the extensions saved in the App Group into the app's own offline queue, then sends what is due.
/// Extensions hold no key and never use the network, so everything they capture passes through here.
///
/// This foundation build has no capture endpoint: `sendItem` is nil, so items stay queued and counted.
/// The future Capture section sets `sendItem`; nothing else here changes.
@MainActor enum InboxDrain {
    /// THE HOOK. Sends one queued item (with its file, if it has one) and returns true when the server took it.
    static var sendItem: (@MainActor (QueuedItem, Data?) async -> Bool)?

    private static var queue = load()
    private static var running = false

    /// Items waiting: already queued, plus anything the extensions have saved since the last drain.
    static var waiting: Int { queue.items.count + SharedInbox.all().count }

    static func run(model: AppModel) async {
        guard !running else { return }
        running = true
        defer { running = false }

        // 1. take in what the extensions saved
        let target = model.config?.capture?.defaultTarget ?? ""
        for item in SharedInbox.all() {
            let file = SharedInbox.data(for: item)
            if let file, !store(file, id: item.id) { continue }   // could not keep the file: leave it in the shared inbox for next time
            let words = [item.title, item.note].compactMap { $0 }.filter { !$0.isEmpty }
            let queued = QueuedItem(id: item.id, createdAt: item.createdAt, kind: item.kind, origin: item.target ?? target, path: "",
                                    text: item.text ?? item.url, fileName: item.fileName,
                                    note: words.isEmpty ? nil : words.joined(separator: "\n"))
            if let dropped = queue.add(queued) {
                removeFile(dropped.id)
                model.debug.note("inbox", "queue full: the oldest item was dropped")
            }
            guard save() else {
                model.lastError = "This iPhone could not save a captured item."
                break   // not saved: the shared inbox keeps its copy
            }
            SharedInbox.remove(item.id)
        }

        // 2. send what is due, when a section has provided the way
        if let sendItem {
            for item in queue.due(now: Date()) {
                if await sendItem(item, fileData(item.id)) {
                    queue.markSent(item.id)
                    removeFile(item.id)
                } else {
                    queue.markFailed(item.id)
                }
                _ = save()
            }
        }

        let count = waiting
        if model.inboxCount != count { model.inboxCount = count }
    }

    // MARK: on disk, inside the app's own container (never the shared one)

    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func load() -> OfflineQueue {
        guard let url = folder?.appendingPathComponent("queue.json"), let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(OfflineQueue.self, from: data) else { return OfflineQueue() }
        return saved
    }

    private static func save() -> Bool {
        guard let url = folder?.appendingPathComponent("queue.json"), let data = try? JSONEncoder().encode(queue) else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    private static func fileURL(_ id: String) -> URL? {
        folder?.appendingPathComponent("file-" + (id as NSString).lastPathComponent)
    }

    private static func store(_ data: Data, id: String) -> Bool {
        guard let url = fileURL(id) else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    private static func fileData(_ id: String) -> Data? {
        guard let url = fileURL(id) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func removeFile(_ id: String) {
        if let url = fileURL(id) { try? FileManager.default.removeItem(at: url) }
    }
}
