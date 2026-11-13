import Foundation
import SwiftUI
import UIKit

/// Task Town's data, ported from the web page (`app/town/page.tsx` in the gallery): the street, the feed, the sun over the town.

struct TownBuilding: Identifiable, Hashable {
    enum Roof { case flat, gable, tiles, tower, dome }
    let id: String, label: String
    let w: CGFloat, h: CGFloat
    let wall: String, trim: String
    let roof: Roof
    let roofC: String, neon: String, note: String
    var lot = false, modern = false, penthouse = false
    var x: CGFloat = 0
    var doorX: CGFloat { x + w / 2 }
}

enum TownStreet {
    static let LH: CGFloat = 252
    static let WALK: CGFloat = 236
    static let doorW: CGFloat = 30, doorH: CGFloat = 62

    static let buildings: [TownBuilding] = {
        var b: [TownBuilding] = [
            .init(id: "home", label: "HOME", w: 92, h: 150, wall: "#5a6a8a", trim: "#2a3450", roof: .flat, roofC: "#2a3f70", neon: "#6ab0ff", note: "Your door. The session comes here when it has a question only you can answer.", penthouse: true),
            .init(id: "studio", label: "STUDIO", w: 150, h: 142, wall: "#b0503a", trim: "#5a2014", roof: .flat, roofC: "#3a2a2a", neon: "#ff6a6a", note: "The gallery: 612 commits in 30 days, the busiest repo. Every edit happens here."),
            .init(id: "mill", label: "RENDERS", w: 92, h: 124, wall: "#6a4a3a", trim: "#2a1a10", roof: .tiles, roofC: "#4a3030", neon: "#ffb050", note: "The render mill: 9,947 generated pieces and 3,734 cinematic posters this month. Smoke while a render runs."),
            .init(id: "curate", label: "CURATE", w: 104, h: 100, wall: "#e8d8b8", trim: "#8a7050", roof: .flat, roofC: "#a08a6a", neon: "#ffd060", note: "Your verdicts: keep, maybe, cut. What you keep teaches everything else."),
            .init(id: "shop", label: "SHOP", w: 112, h: 108, wall: "#d8d4cc", trim: "#3a3a44", roof: .flat, roofC: "#24502e", neon: "#5ae89a", note: "psychedluxuries.com: 150 commits in 30 days. The storefront strangers see.", modern: true),
            .init(id: "print", label: "PRINT", w: 88, h: 116, wall: "#7a7a86", trim: "#3a3a44", roof: .flat, roofC: "#4a4a54", neon: "#9fe8ff", note: "Print works: Printful, the most-mentioned theme in the record (2,607 times).", modern: true),
            .init(id: "bank", label: "BANK", w: 84, h: 124, wall: "#d8d0c0", trim: "#7a6a50", roof: .dome, roofC: "#8a7a5a", neon: "#ffe07a", note: "Square: checkout and payouts. $65k a year is the quit-Amazon line."),
            .init(id: "post", label: "POST", w: 92, h: 108, wall: "#a83a2a", trim: "#4a1a10", roof: .gable, roofC: "#6a2018", neon: "#ff8a5a", note: "Deploys and sends leave from here. A pigeon flies on every push."),
            .init(id: "clock", label: "CRON", w: 60, h: 204, wall: "#8a7a6a", trim: "#3a2a20", roof: .tower, roofC: "#4a3a30", neon: "#ffe07a", note: "The clock tower: pl-cron, 188 commits in 30 days, every scheduled job. The face shows the real time."),
            .init(id: "signal", label: "SOCIAL", w: 72, h: 178, wall: "#4a5a7a", trim: "#2a3048", roof: .tower, roofC: "#2a3048", neon: "#ff6ad0", note: "The signal tower: Instagram, Threads, Bluesky, Facebook, YouTube. The light blinks when a post goes out.", modern: true),
            .init(id: "stale", label: "STALE", w: 70, h: 0, wall: "", trim: "", roof: .flat, roofC: "", neon: "", note: "The stale lot: anything on the Roadmap for a week or more waits here, big and red.", lot: true),
            .init(id: "watch", label: "AUDIT", w: 62, h: 162, wall: "#5a5a4a", trim: "#2a2a20", roof: .tower, roofC: "#3a3a2a", neon: "#ff4a3a", note: "The watchtower: audits and security, 1,356 mentions in the record. Blocked work stands under its red lamp.", modern: true),
            .init(id: "terminal", label: "TERMINAL", w: 96, h: 102, wall: "#6a6a7a", trim: "#2a2a36", roof: .flat, roofC: "#3a3a48", neon: "#7ae8ff", note: "Commands: 1,676 shell calls across the last 6 sessions, the most of anything.", modern: true),
            .init(id: "lookout", label: "WEB", w: 60, h: 190, wall: "#6a5a7a", trim: "#2a2238", roof: .tower, roofC: "#3a3050", neon: "#ffd060", note: "The lookout: web research, 390 calls in 6 sessions.", modern: true),
            .init(id: "library", label: "LIBRARY", w: 164, h: 146, wall: "#6a3a8a", trim: "#2a1438", roof: .dome, roofC: "#44245a", neon: "#d080ff", note: "The vault: 736 commits in 30 days. The record, the rules, the lore."),
            .init(id: "records", label: "RECORDS", w: 92, h: 120, wall: "#7a5a8a", trim: "#3a2448", roof: .gable, roofC: "#44245a", neon: "#d080ff", note: "The changelog, the session blocks, the receipts. Every session leaves its account here."),
            .init(id: "jarvis", label: "JARVIS", w: 100, h: 112, wall: "#3a4a5a", trim: "#1a2430", roof: .flat, roofC: "#2a3440", neon: "#6ae8ff", note: "The board on this PC: 61 commits in 30 days, 2,368 mentions in the record.", modern: true),
            .init(id: "r1", label: "R1", w: 54, h: 76, wall: "#ff6a1a", trim: "#7a2a00", roof: .flat, roofC: "#c04a10", neon: "#ff8a2a", note: "The R1 kiosk: launcher and homebase, 96 commits this month."),
            .init(id: "voice", label: "VOICE", w: 64, h: 92, wall: "#3a3a3a", trim: "#1a1a1a", roof: .flat, roofC: "#2a2a2a", neon: "#ff5a5a", note: "The voice booth: your voice, from Voicebox only.", modern: true),
            .init(id: "forge", label: "FORGE", w: 92, h: 112, wall: "#5a3a2a", trim: "#2a1a10", roof: .gable, roofC: "#3a2418", neon: "#ff7a2a", note: "The Forge course: 142 commits in 90 days."),
            .init(id: "arcade", label: "ARCADE", w: 100, h: 112, wall: "#3a2a5a", trim: "#1a1430", roof: .flat, roofC: "#2a2040", neon: "#ff6ad0", note: "PL World and the games.", modern: true),
            .init(id: "dock", label: "CLOUD", w: 112, h: 84, wall: "#ff8a2a", trim: "#7a3000", roof: .flat, roofC: "#c05a10", neon: "#ff8a2a", note: "The cloud dock: cloud sessions arrive here on the orange cart while they work."),
        ]
        var x0: CGFloat = 24
        for i in b.indices { b[i].x = x0; x0 += b[i].w + (b[i].lot ? 10 : 18) }
        return b
    }()

    static var width: CGFloat { (buildings.last.map { $0.x + $0.w } ?? 0) + 24 + 18 }
    static func building(_ id: String) -> TownBuilding? { buildings.first { $0.id == id } }

    /// What the session is doing -> where he walks: a repo area first, then the kind of call.
    static let areaB: [String: String] = ["gallery": "studio", "headless": "shop", "cron": "clock", "os": "terminal", "jarvis": "jarvis", "r1": "r1", "vault": "library",
                                          "forge": "forge", "world": "arcade", "voice": "voice", "interview": "voice", "printful": "print", "square": "bank", "social": "signal"]
    static let kindB: [String: String] = ["edit": "studio", "shell": "terminal", "deploy": "post", "send": "post", "read": "library", "web": "lookout", "commerce": "shop",
                                          "ask": "home", "cloud": "dock", "other": "clock"]
    static let kindLabel: [String: String] = ["edit": "EDIT", "shell": "BASH", "deploy": "DEPLOY", "send": "SEND", "read": "READ", "web": "WEB", "commerce": "SHOP", "ask": "ASK YOU", "cloud": "CLOUD"]

    static func target(area: String?, kind: String?) -> TownBuilding? {
        if let a = area, let id = areaB[a] ?? (building(a) != nil ? a : nil) { return building(id) }
        if let k = kind, let id = kindB[k] { return building(id) }
        return nil
    }

    static let lore: [(String, String)] = [
        ("Ghost number", "A session guessed its own number after a compaction and wrote the wrong one 14 times. Check who you are before you write your name."),
        ("Car voice", "A README said the founder's voice. Five mixes went out in a voice that was not his. What ships is the authority, not a file describing itself."),
        ("Open bucket", "The nightly backup sat in a public bucket for 136 days, every write reporting success. Stored data is done when a stranger asks for it and is refused."),
        ("Elbows", "A pose was judged from thumbnails. He zoomed in and found the forearms floating. Look at one frame at full size, the way he will."),
        ("Two pixels", "A frozen cloth got a plausible fix, a commit and a render, and came back frozen. Measure the cause before you call it fixed."),
        ("Not my model", "His GlyphGuy was redrawn three times while his rigged model sat on disk. If he made it, find it and use it."),
        ("Frozen map", "Work finished all day while the Roadmap showed item 1 in progress. The QUEUE moves in the same breath as the work."),
        ("Runway", "Queue depth was read as approvals waiting on him, three sessions running. Learn what a number counts before reporting it."),
        ("The void", "The board wrote 290 files nothing ever read. Output nobody consumes is not work."),
        ("Stub", "He was asked for a key whose consumer was an empty stub. Read the code that uses what you ask for."),
        ("Not this bug", "SearXNG was called a separate problem and left down two more nights. Scoping out is not handling."),
        ("Pending", "Pinterest was reported waiting while the decision sat in the console. Read the live status of anything waiting on someone else."),
        ("Placeit", "A whole session judged a mockup library that could not show our garments. Open the real product first."),
        ("Stills", "He judged frozen frames thinking they were videos. Check what he will actually see, where he will see it."),
        ("Overwrite", "A plan was written over his unsaved work, no undo. Check a path is empty before calling a write new."),
    ]
}

// MARK: - The sun over the town: sky, light and windows follow it

enum TownLight: String, CaseIterable { case day, dusk, night, dawn }

enum TownSun {
    static let lat = 35.0, lon = -120.0

    static func times(_ now: Date = Date()) -> (rise: Date, set: Date) {
        let r = Double.pi / 180
        func sinD(_ d: Double) -> Double { sin(d * r) }
        func cosD(_ d: Double) -> Double { cos(d * r) }
        let n = (now.timeIntervalSince1970 / 86400 - 10957.5 + 0.0008).rounded(.up) - lon / 360
        let M = (357.5291 + 0.98560028 * n).truncatingRemainder(dividingBy: 360)
        let lam = (M + 1.9148 * sinD(M) + 0.02 * sinD(2 * M) + 0.0003 * sinD(3 * M) + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2451545 + n + 0.0053 * sinD(M) - 0.0069 * sinD(2 * lam)
        let decl = asin(sinD(lam) * sinD(23.4397)) / r
        let w = acos((sinD(-0.833) - sinD(lat) * sinD(decl)) / (cosD(lat) * cosD(decl))) / r
        func date(_ j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }
        return (date(transit - w / 360), date(transit + w / 360))
    }

    static func mode(_ now: Date = Date()) -> TownLight {
        let (rise, set) = times(now)
        let t = now.timeIntervalSince1970, e = 40.0 * 60
        if t < rise.timeIntervalSince1970 - e || t > set.timeIntervalSince1970 + e { return .night }
        if t < rise.timeIntervalSince1970 + e { return .dawn }
        if t > set.timeIntervalSince1970 - e { return .dusk }
        return .day
    }
}

// MARK: - The feed (gallery /api/town, polled every 10 s while the town is on screen)

struct TownFeed: Decodable {
    struct Task: Decodable, Identifiable, Hashable {
        let key: String?, title: String?, state: String?, proof: String?, session: String?
        let age_days: Int?
        var id: String { key ?? title ?? UUID().uuidString }
    }
    struct Step: Decodable, Hashable { let k: String?; let a: String?; let t: String? }
    struct Live: Decodable { let kind: String?; let tool: String?; let area: String?; let at: String?; let age_s: Int?; let calls: Int?; let hist: [Step]? }
    struct Visitor: Decodable, Identifiable, Hashable { let name: String?; let at: String?; let age_s: Int?; let kind: String?; var id: String { (name ?? "") + (at ?? "") } }
    struct Ghost: Decodable { let s: String?; let p: [String]? }
    let ok: Bool?
    let at: String?
    let age_min: Int?
    let working: Bool?
    let tasks: [Task]?
    let live: Live?
    let visitors: [Visitor]?
    let ghosts: [Ghost]?
}

func townHex(_ s: String) -> UIColor {
    let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return .gray }
    return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

func townTint(_ c: UIColor, _ k: CGFloat) -> UIColor {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return UIColor(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k), alpha: 1)
}

func townMix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
}

func townHash(_ s: String) -> Int { var h = 7; for u in s.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fffffff }; return h }
