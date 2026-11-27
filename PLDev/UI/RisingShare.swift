import ActivityKit
import Foundation

/// Each Rising check-in handed to the widgets and the shift Live Activity (his pick 11-26, item 89). Called from RisingScale.tap.
@MainActor enum RisingShare {
    static func tapped(_ band: Band, at: Date = .now) {
        let day = RisingScale.shiftDay(at), ends = shiftEnd(at)
        let g = RisingGlance(band: band.title, step: RisingStep.of(band).title, level: band.rawValue, at: at, shiftEnds: ends)
        RisingGlance.write(g)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RisingAttributes.ContentState(band: g.band, step: g.step, level: g.level, at: at)
        if Activity<RisingAttributes>.activities.contains(where: { $0.attributes.shiftDay == day }) {
            Task { await update(day, state, ends) }
        } else {
            Task { await endOthers(day) }   // last shift's goes first
            _ = try? Activity.request(attributes: RisingAttributes(shiftDay: day), content: .init(state: state, staleDate: ends, relevanceScore: 50))
        }
    }

    // The activity is looked up inside each nonisolated helper and never handed between actors (as BuddyIsland does).
    nonisolated private static func update(_ day: String, _ state: RisingAttributes.ContentState, _ ends: Date) async {
        for a in Activity<RisingAttributes>.activities where a.attributes.shiftDay == day {
            await a.update(.init(state: state, staleDate: ends, relevanceScore: 50))
        }
    }

    nonisolated private static func endOthers(_ day: String) async {
        for a in Activity<RisingAttributes>.activities where a.attributes.shiftDay != day { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// The shift day runs 3 PM to 3 PM Pacific (RisingScale.shiftDay); this is the 3 PM that ends the one `date` falls in.
    nonisolated static func shiftEnd(_ date: Date) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        var p = c.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-15 * 3600))
        p.hour = 15
        let start = c.date(from: p) ?? date
        return c.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}
