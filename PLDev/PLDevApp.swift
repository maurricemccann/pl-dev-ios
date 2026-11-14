import SwiftUI
import TipKit

@main
struct PLDevApp: App {
    init() {
        PLFonts.register()
        ThemePack.shared.load()            // optional look from the app's Documents folder; none is fine
        Poller.shared.registerProcessing() // the BGProcessingTask handler must exist before launch ends
        AppleActionQueue.onAdd = { Task { @MainActor in await AppleWatch.drain(model: AppModel.shared) } }   // a widget button run in the app's own process is sent at once
        NotificationHub.shared.start()     // the delegate and the sections' categories must exist before launch ends
        IntentBridge.open = { link in AppModel.shared.open(link) }   // intents and controls route through the same door as links
        _ = AppModel.shared                // starts reading the saved config back, also on a background launch
        if UserDefaults.standard.bool(forKey: "pldev.resetTips") {   // Settings asked for the tips again
            try? Tips.resetDatastore(); UserDefaults.standard.set(false, forKey: "pldev.resetTips")
        }
        try? Tips.configure([.displayFrequency(.daily)])   // tips only for gestures that cannot be seen, one a day at most
        _ = OfflineState.shared   // watches the network; sends the mark outbox when it is back
        _ = HouseKit.shared   // the PL remix: his palette and his hand applied before the first screen draws
        Task { await AppModel.shared.restoreIfNeeded(); await HouseKit.shared.refresh(model: AppModel.shared) }
        Task {   // every app's rooms in Spotlight, each in its own named index
            await HouseSpotlight.index(); await GallerySpotlight.index(); await ShopSpotlight.index(); await CongregationSpotlight.index()
            await PracticeSpotlight.index(); await GlyphBotSpotlight.index(); await CurateSpotlight.index(); await PickSpotlight.index(); await CaptureSpotlight.index(); await ComposerSpotlight.index(); await WorldsSpotlight.index()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: AppModel.shared)
                #if targetEnvironment(simulator)
                // Simulator only (the screens workflow): a config file and a link handed in at launch, so every screen can be
                // photographed without the system's "Open in PL DEV?" prompt. Never compiled into a device build.
                .task {
                    let d = UserDefaults.standard
                    if let path = d.string(forKey: "simConfig"), AppModel.shared.config == nil { AppModel.shared.loadConfigForSimulator(from: URL(fileURLWithPath: path)) }
                    if let s = d.string(forKey: "simLink"), let u = URL(string: s), let link = DeepLink(url: u) {
                        try? await Task.sleep(for: .seconds(2)); AppModel.shared.open(link)
                    }
                }
                #endif
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
