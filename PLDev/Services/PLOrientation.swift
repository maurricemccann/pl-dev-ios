import SwiftUI
import UIKit

/// Which way the phone may turn. The app is upright everywhere except a Paint canvas, which turns with the phone (his handbook,
/// ch. 10 "Drawing on a phone": "Landscape works too. Turn the phone and the app fits itself to the screen", 11-14).
@MainActor enum PLOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait

    /// Lets the screen turn (a canvas opening) or brings it back upright (the canvas closing).
    static func allow(_ m: UIInterfaceOrientationMask) {
        mask = m
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            ws.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if m == .portrait { ws.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in } }
        }
    }
}

/// Only here so the system can ask which ways the app may turn.
final class PLAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CrashReport.shared.start()   // last run's crash, if any, arrives in the debug log
        return true
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { PLOrientation.mask }
    }
}
