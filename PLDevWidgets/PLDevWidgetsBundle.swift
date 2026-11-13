import SwiftUI
import WidgetKit

/// Everything the one extension offers: the snapshot widget, the House widget, the control, and the shift Live Activity.
@main
struct PLDevWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SnapshotWidget()
        HouseWidget()
        LibraryWidget()
        PaintWidget()
        HomeControl()
        ShiftLiveActivity()
        RenderLiveActivity()
    }
}
