import Foundation

/// Whether a saved GlyphBot sitting may still be continued. The server starts a new sitting only when no session id is sent and
/// ends one only at the monthly budget, so a saved id alone would offer the question he left a month ago (his 11-24: "it's asking me
/// the same thing I left off on a month ago"). A sitting saved without a time, or by an older build, is not fresh.
public enum SittingFreshness {
    /// How long a sitting stays continuable.
    public static let window: TimeInterval = 12 * 3600

    public static func isFresh(savedAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let savedAt else { return false }
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age <= window && calendar.isDate(savedAt, inSameDayAs: now)
    }
}
