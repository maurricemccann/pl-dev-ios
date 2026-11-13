import Foundation

public struct QueuedItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var kind: String
    public var origin: String
    public var path: String
    public var text: String?
    public var fileName: String?
    public var note: String?
    public var attempts: Int
    public var nextAttemptAt: Date?     // set by markFailed; nil = due now

    public init(id: String, createdAt: Date, kind: String, origin: String, path: String,
                text: String? = nil, fileName: String? = nil, note: String? = nil,
                attempts: Int = 0, nextAttemptAt: Date? = nil) {
        self.id = id; self.createdAt = createdAt; self.kind = kind; self.origin = origin; self.path = path
        self.text = text; self.fileName = fileName; self.note = note
        self.attempts = attempts; self.nextAttemptAt = nextAttemptAt
    }
}

/// A pure value type; the app persists it.
public struct OfflineQueue: Codable, Sendable, Equatable {
    public static let cap = 200

    public var items: [QueuedItem]

    public init(items: [QueuedItem] = []) { self.items = items }

    /// Returns the oldest item dropped to stay under the cap, so the caller can report it.
    @discardableResult
    public mutating func add(_ item: QueuedItem) -> QueuedItem? {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item; return nil }
        items.append(item)
        return items.count > Self.cap ? items.removeFirst() : nil
    }

    public mutating func markSent(_ id: String) { items.removeAll { $0.id == id } }

    public mutating func markFailed(_ id: String, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].attempts += 1
        items[i].nextAttemptAt = now.addingTimeInterval(Self.backoff(attempts: items[i].attempts))
    }

    /// Oldest first.
    public func due(now: Date) -> [QueuedItem] {
        items.filter { ($0.nextAttemptAt ?? .distantPast) <= now }.sorted { $0.createdAt < $1.createdAt }
    }

    /// 5 s, 10 s, 20 s ... capped at 15 minutes.
    public static func backoff(attempts: Int) -> TimeInterval {
        if attempts <= 0 { return 0 }
        return min(900, 5 * Double(1 << min(attempts - 1, 10)))
    }
}
