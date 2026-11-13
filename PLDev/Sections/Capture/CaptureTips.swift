import SwiftUI
import TipKit

// Only for what cannot be seen; TipKit lives apart from the intents because its Parameter macro clashes with AppIntents.
struct CaptureDeckTip: Tip {
    var title: Text { Text("Keep or reject, by swiping") }
    var message: Text? { Text("Swipe a waiting capture left to keep it and right to reject it. Touch and hold for more.") }
    var image: Image? { Image(systemName: "hand.draw") }
}
