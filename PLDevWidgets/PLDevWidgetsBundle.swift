import SwiftUI
import WidgetKit

/// Everything the one extension offers, in three groups (a bundle's builder takes ten at a time):
/// the widgets, the Control Center controls, and the Live Activities.
@main
struct PLDevWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PLDevHomeWidgets().body
        PLDevControls().body
        PLDevLiveActivities().body
    }
}

struct PLDevHomeWidgets: WidgetBundle {
    var body: some Widget {
        SnapshotWidget()
        HouseWidget()
        StorefrontWidget()
        PracticeWidget()
        GlyphBotWidget()
        LibraryWidget()
        PaintWidget()
    }
}

struct PLDevControls: WidgetBundle {
    var body: some Widget {
        HomeControl()
        CaptureControl()
        CanvasControl()
        HouseControl()
        GlyphBotControl()
    }
}

struct PLDevLiveActivities: WidgetBundle {
    var body: some Widget {
        ShiftLiveActivity()
        RenderLiveActivity()
        RehearsalLiveActivity()
        SittingLiveActivity()
    }
}
