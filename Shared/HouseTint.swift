import SwiftUI
import WidgetKit

/// The chosen house palette's key and ground, handed to the widgets and Live Activities through the App Group,
/// so the Lock Screen and the Home Screen wear the same colour as the app (the PL remix).
extension SharedState {
    static func writeHouseTint(_ key: String, ground: String) {
        guard let id = groupID, let store = UserDefaults(suiteName: id) else { return }
        if store.string(forKey: "houseKey") == key && store.string(forKey: "houseGround") == ground { return }
        store.set(key, forKey: "houseKey"); store.set(ground, forKey: "houseGround")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum HouseTint {
    private static func rgb(_ hex: String?) -> Color? {
        guard var t = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt64(t, radix: 16) else { return nil }
        return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
    private static var store: UserDefaults? { SharedState.groupID.flatMap { UserDefaults(suiteName: $0) } }
    /// The palette's key colour (his Home Screen orange until he picks another).
    static var key: Color { rgb(store?.string(forKey: "houseKey")) ?? Color(.sRGB, red: 0.72, green: 0.33, blue: 0.21, opacity: 1) }
    static var ground: Color { rgb(store?.string(forKey: "houseGround")) ?? Color(.sRGB, red: 0.35, green: 0.12, blue: 0.055, opacity: 1) }
}
