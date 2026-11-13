import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, Lock Screen and Action button control that opens the app on Home (pldev://home).
struct HomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PLDevKinds.homeControl) {
            ControlWidgetButton(action: OpenSectionIntent(section: "home")) {
                Label("PL DEV", systemImage: "square.grid.2x2")
            }
        }
        .displayName("PL DEV")
        .description("Opens the app.")
    }
}
