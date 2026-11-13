import AppIntents

/// The shortcuts offered to Siri, Shortcuts and the Action button. App target only: an app has one provider.
struct PLDevShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: InboxCountIntent(),
            phrases: [
                "What is in my \(.applicationName) inbox"
            ],
            shortTitle: "Inbox",
            systemImageName: "tray"
        )
    }
}
