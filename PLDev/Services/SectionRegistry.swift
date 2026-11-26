import Foundation

/// The one list a new section is added to. The home grid, Settings, the probes, the notification categories
/// and the poller all read it; nothing else needs to know a section exists.
@MainActor enum SectionRegistry {
    // ComposerSection was dropped from Home (his ruling 11-14 ~5:35 AM PT); it is back in the registry but hidden by default
    // (ThemeFeed.defaultHidden, with PL World), so the feed's home.hidden turns it on or off over the air (S353·7b1e)
    static var all: [any PLSection.Type] {
        [NeedsSection.self, StatusSection.self, HouseSection.self, CaptureSection.self, CurateSection.self, LibrarySection.self, TownSection.self, PickSection.self, PaintSection.self, ShopSection.self, CongregationSection.self, PracticeSection.self, GlyphBotSection.self, CompanionSection.self, PLWorldSection.self, SchoolSection.self, CalendarSection.self, ComposerSection.self, GateSection.self]
    }

    static func section(_ id: String) -> (any PLSection.Type)? {
        all.first { $0.manifest.id == id }
    }
}
