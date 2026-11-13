import Foundation
import WidgetKit

/// What the Capture widget shows: what waits on him across the house, and what is still on this phone to send.
/// Counts and one short label only: no key, no address, no capture text beyond the last label.
struct CaptureGlance: Codable, Equatable, Sendable {
    var drafts: Int
    var pins: Int
    var tasks: Int
    var shiftOpen: Int
    var captures: Int      // new captures in his moderation deck
    var queued: Int        // on this phone, not sent yet
    var lastLabel: String? // the last thing he captured
    var updatedAt: Date

    /// The one number on the small widget: everything that waits on him.
    var owed: Int { drafts + pins + tasks + shiftOpen + captures }
}

extension PLDevKinds {
    static let captureWidget = "com.psychedluxuries.dev.capture"
}

extension SharedState {
    static func writeCapture(_ g: CaptureGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readCapture()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "capture")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.captureWidget) }
    }

    static func readCapture() -> CaptureGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "capture") else { return nil }
        return try? JSONDecoder().decode(CaptureGlance.self, from: data)
    }
}
