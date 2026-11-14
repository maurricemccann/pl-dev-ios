import SwiftUI
import TipKit

// Paint's tips, in their own file: TipKit's @Parameter macro clashes with App Intents' in PaintSystem.swift.
struct PaintGesturesTip: Tip {
    var title: Text { Text("Fingers move the picture") }
    var message: Text? { Text("Tap with two fingers to undo, three to redo, four to fit the picture. Hold to keep stepping. Change them in Settings, Gesture controls.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

struct PaintPencilTip: Tip {
    var title: Text { Text("The Pencil has buttons too") }
    var message: Text? { Text("Double tap runs the Pen side button's action, a squeeze (Pencil Pro) the second button's. Swap them in Settings.") }
    var image: Image? { Image(systemName: "applepencil") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}
