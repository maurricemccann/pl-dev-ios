import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button controls for the apps he reaches for most (the PL remix, full Apple capability).
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psychedluxuries.dev.control.capture") {
            ControlWidgetButton(action: OpenSectionIntent(section: "capture")) { Label("Capture", systemImage: "tray.and.arrow.down") }
        }
        .displayName("Capture").description("Opens Capture, ready for a note or a photo.")
    }
}

struct CanvasControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psychedluxuries.dev.control.canvas") {
            ControlWidgetButton(action: OpenSectionIntent(section: "paint")) { Label("Paint", systemImage: "paintbrush.pointed.fill") }
        }
        .displayName("PL Paint").description("Opens PL Paint.")
    }
}

struct HouseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psychedluxuries.dev.control.house") {
            ControlWidgetButton(action: OpenSectionIntent(section: "house")) { Label("House", systemImage: "house.fill") }
        }
        .displayName("House").description("Opens the console: the shift, approvals, the house.")
    }
}

struct GlyphBotControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psychedluxuries.dev.control.glyphbot") {
            ControlWidgetButton(action: OpenSectionIntent(section: "glyphbot")) { Label("GlyphBot", systemImage: "bubble.left.and.text.bubble.right") }
        }
        .displayName("GlyphBot").description("Opens GlyphBot to ask or to sit.")
    }
}
