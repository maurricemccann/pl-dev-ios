import UserNotifications

/// Local notifications only: no push, no time-sensitive level. Sections declare their categories; a tap opens the notice's link.
/// Unchecked Sendable: it holds no state.
final class NotificationHub: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationHub()

    static let probePrefix = "probe."
    static let linkKey = "link"
    static let generalType = "general"   // the per-type switch used by a notice with no category
    /// Notification buttons: action id → what it does. Sections fill it when they declare their categories.
    @MainActor static var actions: [String: @MainActor () async -> Void] = [:]
    /// Notification buttons that carry typed text (a reply): action id → what it does with the words.
    @MainActor static var textActions: [String: @MainActor (String) async -> Void] = [:]

    /// Called from the app's init: the delegate and the categories must exist before launch ends.
    @MainActor func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        var byID: [String: UNNotificationCategory] = [:]
        for category in AppleWatch.categories() { byID[category.identifier] = category }
        for section in SectionRegistry.all {
            for category in section.notificationCategories() { byID[category.identifier] = category }   // a section's own declaration wins
        }
        center.setNotificationCategories(Set(byID.values))
    }

    /// The notice types Settings shows a switch for: every category a registered section declared.
    @MainActor static var types: [String] {
        var all = Set<String>(AppleWatch.categories().map(\.identifier))
        for section in SectionRegistry.all {
            for category in section.notificationCategories() { all.insert(category.identifier) }
        }
        return all.sorted()
    }

    func authorize() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Shows one notice now. Returns nil when the system took it, else the reason.
    func post(id: String, title: String, body: String, category: String?, link: String?) async -> String? {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        if let link { content.userInfo = [Self.linkKey: link] }
        content.threadIdentifier = category ?? Self.generalType
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)   // nil = now
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().add(request) { @Sendable error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
    }

    func postProbe() async -> String? {
        await post(id: Self.probePrefix + UUID().uuidString, title: "Probe", body: "Notices work on this install.", category: nil, link: nil)
    }

    func clear(id: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        // The response is not Sendable: copy plain strings out before the task.
        let link = response.notification.request.content.userInfo[Self.linkKey] as? String
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        Task { @MainActor in
            if let typed, let run = Self.textActions[action] { await run(typed); completionHandler(); return }   // a reply: send the words
            if let run = Self.actions[action] { await run(); completionHandler(); return }   // a button: act, do not open
            if let link, let url = URL(string: link), let target = DeepLink(url: url) {
                AppModel.shared.open(target)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
