import SwiftUI
import TipKit

struct PickLookTip: Tip {
    var title: Text { Text("Look closer") }
    var message: Text? { Text("Touch and hold a colourway to see its colours, copy them or share the vote.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
