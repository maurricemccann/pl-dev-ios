import SwiftUI
import TipKit

struct CurateSwipeTip: Tip {
    var title: Text { Text("Swipe to judge") }
    var message: Text? { Text("Right keeps, left cuts, up is maybe. The keys below do the same, and Undo takes back the last one.") }
    var image: Image? { Image(systemName: "hand.draw") }
}
