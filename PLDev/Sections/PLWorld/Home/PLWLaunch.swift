import Foundation

/// Deep links into PL World (for the screenshot run and for him): pldev://section/plworld/<arg>.
/// home or pick: the title with the hero pick. hub, p1 ... p11: play there at once as GlyphGuy, no title, no hints. A second word girl: as GlyphGirl.
/// hub then ring: the whole ring from above. With no link the title shows. Read by `PLWHome`.
@MainActor @Observable final class PLWLaunch {
    static let shared = PLWLaunch()
    struct Play: Equatable { var area: PLWArea; var hero: PLWHero; var ring: Bool }
    private(set) var play: Play?
    private(set) var store: PLWSaveStore?       // the throwaway save for the current link
    private(set) var stamp = 0                // bumps on every link so a repeat of the same link restarts the scene

    func apply(_ path: [String]) {
        guard let first = path.first?.lowercased() else { return }
        let rest = path.dropFirst().map { $0.lowercased() }
        if first == "home" || first == "pick" { play = nil; store = nil; stamp += 1; return }
        let area: PLWArea? = first == "hub" ? .hub : first.hasPrefix("p") ? Int(first.dropFirst()).flatMap { PLWArea(rawValue: $0) }.flatMap { $0 == .hub ? nil : $0 } : nil
        guard let area else { return }          // unknown words are ignored
        play = Play(area: area, hero: rest.contains("girl") ? .glyphGirl : .glyphGuy, ring: area == .hub && rest.contains("ring"))
        stamp += 1
        store = makeStore(for: play!)
    }

    /// A throwaway save that starts at `area`'s "start" port, so a screenshot run never touches his progress.
    private func makeStore(for p: Play) -> PLWSaveStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plw-launch-\(stamp).json")
        try? FileManager.default.removeItem(at: url)
        let s = PLWSaveStore(url: url)
        s.commit { $0.hero = p.hero; $0.checkpointArea = p.area; $0.checkpointPort = "start"; $0.reached.insert(p.area) }
        return s
    }
}
