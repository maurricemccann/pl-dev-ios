import SwiftUI
import TipKit

struct TownDragTip: Tip {
    var title: Text { Text("Walk the street") }
    var message: Text? { Text("Drag the town sideways to walk it. Tap anyone to hear what they are on, and tap a building to read it. Touch the mini-map to jump.") }
    var image: Image? { Image(systemName: "hand.draw") }
}
