import Foundation

/// The one list a new section is added to. The home grid, Settings, the probes, the notification categories
/// and the poller all read it; nothing else needs to know a section exists.
@MainActor enum SectionRegistry {
    static var all: [any PLSection.Type] {
        [StatusSection.self, CaptureSection.self, PickSection.self]
    }

    static func section(_ id: String) -> (any PLSection.Type)? {
        all.first { $0.manifest.id == id }
    }
}
