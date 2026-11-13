import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// What the GlyphBot widget shows, written by the app after it reads the interview record. Counts and words only: no key, no address.
struct GlyphBotGlance: Codable, Equatable, Sendable {
    var asked: Int              // bank questions asked so far
    var total: Int              // the bank's size
    var answers: Int            // his answers on the record, all domains
    var thinnest: String?       // the domain with the fewest answers
    var thinnestCount: Int
    var waiting: Int            // Oracle turns not yet synced to the record
    var updatedAt: Date
}

extension PLDevKinds {
    static let glyphbotWidget = "com.psychedluxuries.dev.glyphbot"
}

extension GlyphBotGlance {
    /// Redraws the widget only when something other than the time changed.
    static func write(_ g: GlyphBotGlance) {
        guard let id = SharedState.groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = read()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "glyphbot")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.glyphbotWidget) }
    }

    static func read() -> GlyphBotGlance? {
        guard let id = SharedState.groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "glyphbot") else { return nil }
        return try? JSONDecoder().decode(GlyphBotGlance.self, from: data)
    }
}

#if canImport(ActivityKit)
/// A sitting with GlyphBot on the Lock Screen and in the Dynamic Island: a clock and how many answers he has given.
/// Started by his tap on Begin, updated only when an answer lands, ended the moment the sitting ends. Local only.
struct SittingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var answers: Int
        var seat: String        // who is asking: "Solomon", "Vessel", "Athena", "Stranger" or "GlyphBot"
    }
    var mode: String            // "Interview" or "Free talk"
    var started: Date
}
#endif
