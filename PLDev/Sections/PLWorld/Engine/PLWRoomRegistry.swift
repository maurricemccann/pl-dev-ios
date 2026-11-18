import Foundation

/// Builds a room by area. The lead adds one `case` per room at merge (the rooms are written against the frozen contract meanwhile).
/// Until a room exists its area loads the greybox, so the runtime always has somewhere to stand.
@MainActor enum PLWRoomRegistry {
    static func make(_ area: PLWArea) -> any PLWRoom {
        switch area {
        // lead: add `case .p1: return PLWRoomP1()` ... `case .hub: return PLWRoomHub()` here when each lane merges
        default: return PLWRoomGreybox(area: area)
        }
    }
}
