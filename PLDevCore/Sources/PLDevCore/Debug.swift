import Foundation

public struct DebugEvent: Codable, Sendable, Equatable {
    public var at: Date
    public var category: String
    public var message: String
    public init(at: Date, category: String, message: String) { self.at = at; self.category = category; self.message = message }
}

/// Removes secrets from a line before it is shown or sent: Bearer tokens, 32+ hex runs, key=/token=/k=/auth= values.
public enum Scrub {
    public static func clean(_ text: String) -> String {
        var s = text
        // Built per call (not stored) so the type stays trivially Sendable; log lines are short.
        let rules: [(String, String, NSRegularExpression.Options)] = [
            ("Bearer\\s+[A-Za-z0-9._~+/=_-]+", "Bearer [redacted]", [.caseInsensitive]),
            ("\\b((?:[A-Za-z0-9_]*(?:key|token))|k|auth)=([^&\\s\"',;]+)", "$1=[redacted]", [.caseInsensitive]),
            ("\\b[0-9a-fA-F]{32,}\\b", "[redacted]", []),
        ]
        for (pattern, template, opts) in rules {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            s = re.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s
    }
}

public struct DebugBuffer: Codable, Sendable {
    public static let cap = 200

    public private(set) var events: [DebugEvent]

    public init() { events = [] }

    public mutating func add(_ e: DebugEvent) {
        events.append(e)
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
    }

    /// Takes the oldest `max` events out of the buffer.
    public mutating func drain(max: Int) -> [DebugEvent] {
        let n = Swift.min(Swift.max(max, 0), events.count)
        let out = Array(events.prefix(n))
        events.removeFirst(n)
        return out
    }
}
