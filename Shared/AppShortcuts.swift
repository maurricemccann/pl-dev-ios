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
            intent: HouseStatusIntent(),
            phrases: ["What's waiting in \(.applicationName)", "\(.applicationName) house status"],
            shortTitle: "House status",
            systemImageName: "house"
        )
        AppShortcut(
            intent: NextShiftTaskDoneIntent(),
            phrases: ["Mark my shift task done in \(.applicationName)"],
            shortTitle: "Shift task done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ApproveAllDraftsIntent(),
            phrases: ["Approve all drafts in \(.applicationName)"],
            shortTitle: "Approve drafts",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: OpenHouseRoomIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)"],
            shortTitle: "Open a room",
            systemImageName: "door.left.hand.open"
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
