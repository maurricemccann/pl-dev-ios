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
        AppShortcut(
            intent: ColourwayLeaderIntent(),
            phrases: ["Which colourway is winning in \(.applicationName)"],
            shortTitle: "Colourway vote",
            systemImageName: "paintpalette"
        )
        AppShortcut(
            intent: TownStatusIntent(),
            phrases: ["What is the session doing in \(.applicationName)", "\(.applicationName) town status"],
            shortTitle: "Town status",
            systemImageName: "building.2"
        )
        AppShortcut(
            intent: ShopStatusIntent(),
            phrases: ["What's in the shop in \(.applicationName)", "\(.applicationName) shop status"],
            shortTitle: "Shop status",
            systemImageName: "bag"
        )
        AppShortcut(
            intent: CongregationStatusIntent(),
            phrases: ["What's in the congregation in \(.applicationName)", "\(.applicationName) congregation status"],
            shortTitle: "Congregation status",
            systemImageName: "person.3"
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
