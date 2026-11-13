import Foundation
import WidgetKit

/// What the Composer widget shows: the render board in counts, the newest card, and the piece he has open. Names and counts only.
struct ComposerGlance: Codable, Equatable, Sendable {
    var sent = 0, rendering = 0, mixing = 0, filed = 0, ruled = 0, failed = 0
    var newestShot: String?
    var newestLane: String?
    var pieces = 0
    var piece: String?
    var shots = 0
    var seconds = 0.0
    var updatedAt = Date.now
    var inFlight: Int { sent + rendering + mixing }
}

extension PLDevKinds {
    static let composerWidget = "com.psychedluxuries.dev.composer"
}

extension SharedState {
    static func writeComposer(_ g: ComposerGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readComposer()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "composer")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.composerWidget) }
    }

    static func readComposer() -> ComposerGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "composer") else { return nil }
        return try? JSONDecoder().decode(ComposerGlance.self, from: data)
    }
}

/// The two halves of the glance come from two places (the board poll and the piece store); each merges into what the other wrote.
enum ComposerGlanceWriter {
    static func publishBoard(sent: Int, rendering: Int, mixing: Int, filed: Int, ruled: Int, failed: Int, newestShot: String?, newestLane: String?) {
        var g = SharedState.readComposer() ?? ComposerGlance()
        g.sent = sent; g.rendering = rendering; g.mixing = mixing; g.filed = filed; g.ruled = ruled; g.failed = failed
        g.newestShot = newestShot; g.newestLane = newestLane; g.updatedAt = .now
        SharedState.writeComposer(g)
    }

    static func publishPieces(_ count: Int, active: String, shots: Int, seconds: Double) {
        var g = SharedState.readComposer() ?? ComposerGlance()
        g.pieces = count; g.piece = active; g.shots = shots; g.seconds = seconds; g.updatedAt = .now
        SharedState.writeComposer(g)
    }
}
