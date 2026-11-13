import SwiftUI
import WidgetKit

/// Everything the one extension offers: the snapshot widget and the control. No Live Activity yet.
@main
struct PLDevWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SnapshotWidget()
        HomeControl()
    }
}
