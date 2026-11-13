#if canImport(ActivityKit)
import ActivityKit

/// One render followed on the Lock Screen: its lane (sent, rendering, mixing, filed, ruled, failed) and progress line.
struct RenderAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var lane: String
        var progress: String?
    }
    var cardID: String
    var shot: String
}
#endif
