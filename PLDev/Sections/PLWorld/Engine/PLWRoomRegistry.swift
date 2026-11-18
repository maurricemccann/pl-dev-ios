import Foundation

/// Builds a room by area. The lead adds one `case` per room at merge (the rooms are written against the frozen contract meanwhile).
/// Until a room exists its area loads the greybox, so the runtime always has somewhere to stand.
@MainActor enum PLWRoomRegistry {
    static func make(_ area: PLWArea) -> any PLWRoom {
        switch area {
        case .p1: return PLWRoomP1()
        case .p2: return PLWRoomP2()
        case .p3: return PLWRoomP3()
        case .p4: return PLWRoomP4()
        case .p5: return PLWRoomP5()
        case .p6: return PLWRoomP6()
        case .p7: return PLWRoomP7()
        case .p8: return PLWRoomP8()
        case .p9: return PLWRoomP9()
        case .p10: return PLWRoomP10()
        case .p11: return PLWRoomP11()
        case .hub: return PLWRoomHub()
        default: return PLWRoomGreybox(area: area)
        }
    }
}
