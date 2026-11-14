import AppIntents

/// The shortcuts offered to Siri, Shortcuts and the Action button. App target only: an app has one provider.
struct PLDevShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
        AppShortcut(   // wave 1 (11-13): the deck-aware twin of "Curate waiting"
            intent: CurateDeckCountIntent(),
            phrases: ["How many cards are in \(\.$target) in \(.applicationName)", "Cards waiting in \(\.$target) in \(.applicationName)"],
            shortTitle: "Cards in a deck",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(   // 11-14: Paint's daily canvas in place of the colourway vote (cap of 10; the vote stays an action in Shortcuts)
            intent: OpenPaintCanvasIntent(),
            phrases: ["Open the canvas in \(.applicationName)", "Paint in \(.applicationName)"],
            shortTitle: "Open the canvas",
            systemImageName: "paintbrush.pointed"
        )
        AppShortcut(
            intent: TownStatusIntent(),
            phrases: ["What is the session doing in \(.applicationName)", "\(.applicationName) town status"],
            shortTitle: "Town status",
            systemImageName: "building.2"
        )
        AppShortcut(   // wave 3 (11-13): Capture's two, in place of Shop status and Congregation status (cap of 10)
            intent: CaptureThoughtIntent(),
            phrases: ["Capture a thought in \(.applicationName)", "\(.applicationName) capture"],
            shortTitle: "Capture a thought",
            systemImageName: "square.and.arrow.down"
        )
        AppShortcut(
            intent: WaitingOnMeIntent(),
            phrases: ["What is waiting on me in \(.applicationName)"],
            shortTitle: "Waiting on me",
            systemImageName: "tray"
        )
        AppShortcut(
            intent: PracticeStatusIntent(),
            phrases: ["What's left in my practice today in \(.applicationName)"],
            shortTitle: "Practice today",
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: AskGlyphBotIntent(),
            phrases: ["Ask GlyphBot in \(.applicationName)"],
            shortTitle: "Ask GlyphBot",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
