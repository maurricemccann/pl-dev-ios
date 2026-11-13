import Foundation

/// Things the extensions captured, waiting for the app to send them. Extensions write, the app drains.
/// One small JSON file per item (plus its payload file), so two processes writing at once cannot lose each other's items.
enum SharedInbox {
    struct Item: Codable, Identifiable, Equatable, Sendable {
        var id: String
        var createdAt: Date
        var source: String     // "share" | "safari" | "widget"
        var kind: String       // "text" | "url" | "image"
        var text: String?
        var url: String?
        var title: String?
        var fileName: String?
        var note: String?
        var target: String? = nil   // "cron" | "board"; nil = the config's default
    }

    enum InboxError: Error, LocalizedError {
        case unavailable
        case badID

        var errorDescription: String? {
            switch self {
            case .unavailable: return "The shared inbox is not available in this install."
            case .badID: return "That item has an id the inbox cannot store."
            }
        }
    }

    private static var folder: URL? {
        SharedState.containerURL?.appendingPathComponent("Inbox", isDirectory: true)
    }

    static var isAvailable: Bool { folder != nil }

    /// An id becomes a file name, so it may hold only letters, digits and dashes.
    private static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func itemURL(_ id: String, in folder: URL) -> URL {
        folder.appendingPathComponent(id + ".json")
    }

    private static func payloadURL(_ id: String, in folder: URL) -> URL {
        folder.appendingPathComponent(id + ".data")
    }

    static func add(_ item: Item, file: Data?) throws {
        guard let folder else { throw InboxError.unavailable }
        guard isSafe(item.id) else { throw InboxError.badID }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The payload goes first, so a listed item never points at a file that is not there yet.
        if let file {
            try file.write(to: payloadURL(item.id, in: folder), options: .atomic)
        }
        try JSONEncoder().encode(item).write(to: itemURL(item.id, in: folder), options: .atomic)
    }

    /// Oldest first. A file that does not decode is skipped, never fatal.
    static func all() -> [Item] {
        guard let folder else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Item.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func data(for item: Item) -> Data? {
        guard let folder, isSafe(item.id) else { return nil }
        return try? Data(contentsOf: payloadURL(item.id, in: folder))
    }

    static func remove(_ id: String) {
        guard let folder, isSafe(id) else { return }
        try? FileManager.default.removeItem(at: itemURL(id, in: folder))
        try? FileManager.default.removeItem(at: payloadURL(id, in: folder))
    }
}
