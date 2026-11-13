import SwiftUI
import TipKit

// MARK: - Tips (only for what cannot be seen)

struct DraftGesturesTip: Tip {
    var title: Text { Text("More on every draft") }
    var message: Text? { Text("Touch and hold a draft for Post now, Rewrite the caption and Change the picture.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

struct ShiftLockScreenTip: Tip {
    var title: Text { Text("Keep the shift on your Lock Screen") }
    var message: Text? { Text("It ticks along as you finish tasks and leaves when the shift is done.") }
    var image: Image? { Image(systemName: "lock.iphone") }
}
