import Foundation
import RealityKit
import simd

// THE FROZEN CONTRACT for PL World (blueprint in LANES-plworld.md). Owned by the integrator (the lane lead). No other lane edits this file:
// if you need a change, write it into your lane file and message the lead. Types here are declarations only; the runtime that drives them is lane A.
// Units: metres, Y up, local -Z forward. Every room is built in its own local frame; the layout (lane B) places it in the world exactly once.

/// The twelve places: the hub, and the eleven pages in book order.
enum PLWArea: Int, Codable, CaseIterable, Sendable {
    case hub = 0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11
    var page: Int? { self == .hub ? nil : rawValue }
}

enum PLWHero: String, Codable, CaseIterable, Sendable { case glyphGuy, glyphGirl }

/// The dream's story state: the save restores it.
enum PLWDream: String, Codable, Sendable { case absent, carried, buried, recovered, embraced }

/// One of the three glyph keys of a page. Slot 0...2. Collected with ACT, never gated by winning a station.
struct PLWKey: Hashable, Codable, Sendable {
    let page: PLWArea
    let slot: UInt8
}

/// His Glyph Field glyphs (the keys; S341).
enum PLWGlyph: String, Codable, Sendable {
    case glyphGuy = "glyph-guy", loveYourself = "love-yourself", money
    case povertyToLuxury = "poverty-to-luxury", smiley, moneyGrin = "money-grin"
}

struct PLWGlyphPlacement: Sendable {
    let key: PLWKey
    let glyph: PLWGlyph
    let position: SIMD3<Float>          // room-local
}

/// An oriented box the integrator turns into a collision trigger volume; the room never builds triggers itself.
struct PLWTrigger: Sendable {
    let id: String                      // stable, "p5.dig"
    let center: SIMD3<Float>
    let yaw: Float
    let halfExtents: SIMD3<Float>
}

enum PLWTriggerPhase: Sendable { case entered, stayed, exited }
struct PLWTriggerEvent: Sendable { let id: String; let phase: PLWTriggerPhase }

/// The page look at this moment: the palette owner computes it (vividness 0.5 at page 1 up to 0.7 at page 10, 1.0 after the Embrace,
/// 1.1 in free play; it scales SATURATION, never multiplies RGB toward black). Rooms read it, they never decide it.
struct PLWLook: Sendable {
    let pageRGB: SIMD3<Float>
    let fogRGB: SIMD3<Float>
    let saturation: Float
    let exposure: Float
}

/// Progress. Written atomically on every commit and on scenePhase change. `schemaVersion` starts at 1.
struct PLWSave: Codable, Sendable {
    var schemaVersion: Int = 1
    var hero: PLWHero = .glyphGuy
    var checkpointArea: PLWArea = .p1
    var checkpointPort: String = "start"
    var dream: PLWDream = .absent
    var reached: Set<PLWArea> = [.p1]
    var completed: Set<PLWArea> = []        // the page's moment is done
    var glyphs: Set<PLWKey> = []
    var marks: Set<String> = []             // his marks and seed lines, optional, never a gate
    var roomFlags: [Int: Set<String>] = [:] // keyed by PLWArea.rawValue
    var unlocks: Set<String> = []           // materials and dream colours earned by finishing pages
}

/// Gate policy. His S341 ruling: the open world is the game, nothing is locked but the customisations, so every gate is `.open`.
/// The type stays so a later ruling can tighten one gate without touching rooms.
enum PLWGateRule: Sendable { case open, completed(PLWArea) }
struct PLWGate: Sendable {
    let id: String                      // "p3>p4"
    let from: PLWArea, to: PLWArea
    let fromPort: String, toPort: String
    let rule: PLWGateRule
}

/// What the integrator hands a room each frame. Positions are room-local.
struct PLWFrame: Sendable {
    let dt: Float
    let position: SIMD3<Float>
    let velocity: SIMD3<Float>
    let lookDirection: SIMD3<Float>
    let grounded: Bool
    let jumpPressed: Bool, jumpHeld: Bool
    let actPressed: Bool, actHeld: Bool
    let save: PLWSave
}

/// What a room may ask for. The integrator validates and applies each, idempotently; a room never mutates the save or another room.
enum PLWCommand {
    case completeMoment(PLWArea)
    case collect(PLWKey)
    case mark(String)
    case roomFlag(PLWArea, String)
    case dream(PLWDream)
    case checkpoint(PLWArea, port: String)
    case camera(position: SIMD3<Float>, target: SIMD3<Float>, weight: Float)   // expires when the room unloads or the weight is 0
    case raiseDream(Float)                                                     // 0...1 the dream's rise (the gift)
    case caption(String)                                                       // one quiet line, his voice rules apply (copy only)
}

/// A room: one page, or the hub. Lanes C, D, E conform one type each; lane B conforms the hub.
@MainActor protocol PLWRoom: AnyObject {
    var id: PLWArea { get }
    var root: Entity { get }                          // room-local, unit scale, no world placement
    var ports: [String: Transform] { get }            // "start", "exit" and one per tunnel end, room-local
    var route: [SIMD3<Float>] { get }                 // the guiding path, start to exit (the light that brings him back)
    var triggers: [PLWTrigger] { get }
    var glyphs: [PLWGlyphPlacement] { get }
    func load() async throws
    func restore(_ save: PLWSave)
    func step(_ frame: PLWFrame) -> [PLWCommand]
    func receive(_ event: PLWTriggerEvent) -> [PLWCommand]
    func apply(_ look: PLWLook)
    func unload()
}
