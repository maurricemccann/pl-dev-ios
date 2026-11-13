import SwiftUI
import TipKit

// One tip each for what cannot be seen (DESIGN.md §6): a touch-and-hold, and a swipe on the picture.

struct PieceHoldTip: Tip {
    var title: Text { Text("Touch and hold to like") }
    var message: Text? { Text("Hold a piece to like it. The first few on screen are running live; tap one to see it full size.") }
    var image: Image? { Image(systemName: "heart") }
}

struct PieceSwipeTip: Tip {
    var title: Text { Text("Swipe for the next piece") }
    var message: Text? { Text("Swipe across the picture to move through the pieces. Tap it for the bars.") }
    var image: Image? { Image(systemName: "hand.draw") }
}

struct VJGestureTip: Tip {
    var title: Text { Text("Swipe, tap, tilt the rack") }
    var message: Text? { Text("Swipe the picture for the next piece. Tap it to start or stop the sound. The rack under it holds the decks, the effects and the routes.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
