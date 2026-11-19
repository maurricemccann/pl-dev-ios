import Foundation
import RealityKit
import simd

// The ring layout (lane B): where every room root sits, and the 23 links (ten page tunnels, two entrance cut ends, eleven hub doors).
// Geometry is RING-DESIGN.md, frozen in PLWRing. Pure maths: no entities here, so lane A and the lead can call it from anywhere.

enum PLWLinkKind: Sendable { case pageToPage, entranceCut, hubDoor }

struct PLWLink: Sendable {
    let id: String                       // "p3>p4", "gap>p1", "p11>gap", "hub>p5"
    let kind: PLWLinkKind
    let from: PLWArea, to: PLWArea       // the entrance green stands as .hub (same family, same area for the save)
    let fromHex: UInt32, toHex: UInt32   // the wash runs from one to the other along travel
    let center: SIMD3<Float>             // world, floor level
    let yaw: Float                       // local -Z is the direction of travel, from -> to
    let length: Float, width: Float, wallHeight: Float   // clear width, straight wall height (the crown arch adds width / 2)
    let gate: PLWGate

    var clearHeight: Float { wallHeight + width / 2 }
    var forward: SIMD3<Float> { simd_act(PLWMath.rot(yaw), SIMD3<Float>(0, 0, -1)) }
    var transform: Transform { Transform(scale: .one, rotation: PLWMath.rot(yaw), translation: center) }
}

enum PLWLayout {
    /// The entrance, hub and outer band green (sampled from his ring drawing).
    static let greenHex: UInt32 = 0x64A38A
    static let tunnelRadius: Float = 680           // page-to-page tunnels sit on this radius
    static let ridgeThickness: Float = 24
    static let pageTunnel = (length: Float(30), width: Float(6), wall: Float(2))       // 5 m clear height
    static let hubTunnel = (length: Float(60), width: Float(8), wall: Float(2))        // 6 m clear height
    static let innerRidge: ClosedRange<Float> = 366...390, outerRidge: ClosedRange<Float> = 976...1000, outerBand: ClosedRange<Float> = 1000...1150
    static let entranceGap: ClosedRange<Float> = 165...195

    static func pageHex(_ page: Int) -> UInt32 { PLWRing.pageHex[page - 1] }
    static func area(_ page: Int) -> PLWArea { PLWArea(rawValue: page) ?? .hub }

    /// Compass direction of increasing angle (clockwise tangent) as a world vector.
    static func tangent(_ thetaDeg: Float) -> SIMD3<Float> {
        let a = thetaDeg * .pi / 180
        return SIMD3<Float>(cos(a), 0, sin(a))
    }

    // MARK: rooms

    /// The world transform for page i's room root: origin at the entry lip C_i - 30 T_i, local -Z along T_i (RING-DESIGN). Rooms are built in their own frame; set `root.transform` to this once.
    static func roomTransform(page: Int) -> Transform {
        let th = PLWRing.centerAngle(page: page)
        let t = tangent(th)
        return Transform(scale: .one, rotation: PLWMath.rot(PLWMath.yaw(facing: t)), translation: PLWMath.world(PLWRing.centerpieceRadius, th, y: roomLift) - 30 * t)
    }
    static func toWorld(page: Int, local p: SIMD3<Float>) -> SIMD3<Float> { let t = roomTransform(page: page); return simd_act(t.rotation, p) + t.translation }
    static func toLocal(page: Int, world p: SIMD3<Float>) -> SIMD3<Float> { let t = roomTransform(page: page); return simd_act(t.rotation.inverse, p - t.translation) }

    /// Puts a room's root where it belongs and parents it. The hub stays at the origin. Idempotent.
    /// Rooms sit 4 cm above the ring's sector ground: both floors at exactly 0 made the GPU flip between them every frame (his 11-18 "the floor
    /// tile blinks/clips itself"). Far under the 0.4 m step limit, so the tunnel mouths still walk flat; inside the layout self-check's 5 cm.
    static let roomLift: Float = 0.04
    @MainActor static func place(_ room: PLWRoom, under parent: Entity) {
        if let page = room.id.page { room.root.transform = roomTransform(page: page) } else { room.root.transform = Transform() }
        if room.root.parent !== parent { parent.addChild(room.root) }
    }

    // MARK: classification

    /// Compass angle (0..<360, clockwise from north) of a world point.
    static func compass(_ p: SIMD3<Float>) -> Float {
        let d = atan2(p.x, -p.z) * 180 / .pi
        return d < 0 ? d + 360 : d
    }
    /// Which area a world point belongs to: the hub, the entrance green and the outer band are all `.hub` (open free-play ground); page sectors by wedge.
    /// Inside a tunnel the caller keeps the last area (use `link(containing:)`), exactly as RING-DESIGN says.
    static func area(at p: SIMD3<Float>) -> PLWArea {
        let r = hypot(p.x, p.z)
        if r < innerRidge.upperBound || r >= PLWRing.ringOuter { return .hub }
        let th = compass(p)
        if th >= entranceGap.lowerBound && th < entranceGap.upperBound { return .hub }
        let i = Int(floor(((th - 195 + 360).truncatingRemainder(dividingBy: 360)) / 30)) + 1
        return PLWArea(rawValue: min(max(i, 1), 11)) ?? .hub
    }

    // MARK: links

    static let links: [PLWLink] = {
        var out: [PLWLink] = []
        func rule(_ r: PLWGateRule, _ id: String, _ f: PLWArea, _ t: PLWArea, _ fp: String, _ tp: String) -> PLWGate {
            PLWGate(id: id, from: f, to: t, fromPort: fp, toPort: tp, rule: r)
        }
        func tunnel(_ id: String, _ kind: PLWLinkKind, _ f: PLWArea, _ t: PLWArea, _ fh: UInt32, _ th: UInt32, boundary b: Float, gate: PLWGate) -> PLWLink {
            let d = tangent(b)
            return PLWLink(id: id, kind: kind, from: f, to: t, fromHex: fh, toHex: th, center: PLWMath.world(tunnelRadius, b),
                           yaw: PLWMath.yaw(facing: d), length: pageTunnel.length, width: pageTunnel.width, wallHeight: pageTunnel.wall, gate: gate)
        }
        // the entrance cut end beside page 1 (boundary 195): green to page 1 yellow. Walkable from the gap, no quota.
        out.append(tunnel("gap>p1", .entranceCut, .hub, .p1, greenHex, pageHex(1), boundary: 195,
                          gate: rule(.open, "gap>p1", .hub, .p1, "gap", "start")))
        for i in 1...10 {
            let b = (PLWRing.centerAngle(page: i) + 15).truncatingRemainder(dividingBy: 360)
            out.append(tunnel("p\(i)>p\(i + 1)", .pageToPage, area(i), area(i + 1), pageHex(i), pageHex(i + 1), boundary: b,
                              gate: rule(.completed(area(i)), "p\(i)>p\(i + 1)", area(i), area(i + 1), "exit", "start")))
        }
        // the cut end beside page 11 (boundary 165): gold to green, opens when page 11's moment is done
        out.append(tunnel("p11>gap", .entranceCut, .p11, .hub, pageHex(11), greenHex, boundary: 165,
                          gate: rule(.completed(.p11), "p11>gap", .p11, .hub, "exit", "gap")))
        // eleven hub doors, 330 to 390, travel outward from the hub (green to the page colour); a door to a later page is for pages already reached in book order
        for i in 1...11 {
            let th = PLWRing.centerAngle(page: i)
            let d = PLWMath.world(1, th)
            out.append(PLWLink(id: "hub>p\(i)", kind: .hubDoor, from: .hub, to: area(i), fromHex: greenHex, toHex: pageHex(i),
                               center: PLWMath.world(360, th), yaw: PLWMath.yaw(facing: d), length: hubTunnel.length, width: hubTunnel.width, wallHeight: hubTunnel.wall,
                               gate: rule(i == 1 ? .open : .completed(area(i - 1)), "hub>p\(i)", .hub, area(i), "door\(i)", "start")))
        }
        return out
    }()

    static func link(_ id: String) -> PLWLink? { links.first { $0.id == id } }

    /// The oriented tunnel volume a world point is inside (with progress t, 0 at the source mouth to 1 at the destination), or nil. The runtime uses it for the first-person switch.
    static func link(containing p: SIMD3<Float>, margin: Float = 0.3) -> (link: PLWLink, t: Float)? {
        for l in links {
            let q = simd_act(PLWMath.rot(-l.yaw), p - l.center)
            if abs(q.x) <= l.width / 2 + margin, abs(q.z) <= l.length / 2, q.y >= -1, q.y <= l.clearHeight + margin {
                return (l, simd_clamp(0.5 - q.z / l.length, 0, 1))     // travel is -Z, so the source mouth is +Z
            }
        }
        return nil
    }

    /// Cheap self-check of the layout maths; returns the failures (empty = fine). Unrun until a device or CI test target calls it.
    static func selfCheck() -> [String] {
        var bad: [String] = []
        if links.count != 23 { bad.append("links \(links.count) != 23") }
        if Set(links.map(\.id)).count != links.count { bad.append("duplicate link id") }
        for p in 1...11 {
            let w = toWorld(page: p, local: SIMD3<Float>(0, 0, -30))                      // 30 m along the room's forward = the centrepiece
            let c = PLWMath.world(PLWRing.centerpieceRadius, PLWRing.centerAngle(page: p))
            if simd_distance(w, c) > 0.05 { bad.append("p\(p) centrepiece off by \(simd_distance(w, c))") }
            if area(at: c) != PLWArea(rawValue: p) { bad.append("p\(p) centre classified \(area(at: c))") }
            if simd_distance(toLocal(page: p, world: w), SIMD3<Float>(0, 0, -30)) > 0.01 { bad.append("p\(p) round trip") }
        }
        if area(at: PLWMath.world(500, 180)) != .hub || area(at: SIMD3<Float>(0, 0, 100)) != .hub || area(at: PLWMath.world(1100, 10)) != .hub { bad.append("open ground not hub") }
        for l in links where link(containing: l.center)?.link.id != l.id { bad.append("\(l.id) centre not inside its own volume") }
        return bad
    }
}
