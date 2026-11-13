import SwiftUI
import TipKit

@main
struct PLDevApp: App {
    init() {
        PLFonts.register()
        ThemePack.shared.load()            // optional look from the app's Documents folder; none is fine
        NotificationHub.shared.start()     // the delegate and the sections' categories must exist before launch ends
        IntentBridge.open = { link in AppModel.shared.open(link) }   // intents and controls route through the same door as links
        _ = AppModel.shared                // starts reading the saved config back, also on a background launch
        try? Tips.configure([.displayFrequency(.daily)])   // tips only for gestures that cannot be seen, one a day at most
        Task { await HouseSpotlight.index() }   // House rooms in Spotlight
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: AppModel.shared)
                .onOpenURL { url in
                    if url.isFileURL {
                        Task { await AppModel.shared.loadConfig(from: url) }   // a .json opened into the app is a config to load
                    } else if let link = DeepLink(url: url) {
                        AppModel.shared.open(link)
                    }
                }
        }
        // the system's background refresh: registered here, requested by the poller each time the app leaves the front
        .backgroundTask(.appRefresh(Poller.taskID)) {
            await Poller.shared.backgroundRefresh()
        }
    }
}
