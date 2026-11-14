import Foundation

/// The one list a new section is added to. The home grid, Settings, the probes, the notification categories
/// and the poller all read it; nothing else needs to know a section exists.
@MainActor enum SectionRegistry {
    // ComposerSection dropped from PL DEV (his ruling 11-14 ~5:35 AM PT); its code stays, adding it back here restores it
    static var all: [any PLSection.Type] {
        [StatusSection.self, HouseSection.self, CaptureSection.self, CurateSection.self, LibrarySection.self, TownSection.self, PickSection.self, PaintSection.self, ShopSection.self, CongregationSection.self, PracticeSection.self, GlyphBotSection.self]
    }

    static func section(_ id: String) -> (any PLSection.Type)? {
        all.first { $0.manifest.id == id }
    }
}
