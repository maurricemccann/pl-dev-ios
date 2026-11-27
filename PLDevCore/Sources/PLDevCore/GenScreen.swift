import Foundation

// Generative check-in screen (S355, spec "PL DEV PICKS ON THE PHONE" in the vault): the phone's model proposes a screen, this file
// holds it to the band's limits, throws out text that breaks the voice, and varies it by seed so screens do not look alike.
// Bands are their rank: 0 Heavy, 1 Hot, 2 Low, 3 Stuck, 4 Steady, 5 Rising, 6 Lit.

public enum GenPart: String, CaseIterable, Codable, Sendable {
    case move, breath, walk, plan, buddy, wall, week, vision, note, text
    /// A part he can act on; every screen carries at least one.
    public var acts: Bool { self == .move || self == .breath || self == .walk || self == .plan }
}

public struct GenBlock: Codable, Equatable, Sendable {
    public var part: GenPart
    public var size: Int      // 0 small, 1 middle, 2 large
    public var variant: Int   // 0...2, which way the part is drawn
    public init(_ part: GenPart, size: Int = 1, variant: Int = 0) { self.part = part; self.size = size; self.variant = variant }
}

public struct GenScreen: Codable, Equatable, Sendable {
    public var blocks: [GenBlock]
    public var shape: Int       // corner family 0...3
    public var motion: Int      // 0 still, 1 gentle, 2 lively
    public var heading: String?
    public var line: String?
    public var seed: UInt64 = 0
    public var spacing = 1      // 0 tight, 1 house, 2 open
    public var pack = 0         // which theme pack lends card, corners, type, wall and pace (modulo the pack count)
    public var wallAngle = 0    // degrees
    public var wallZoom = 1.0
    public init(blocks: [GenBlock], shape: Int = 1, motion: Int = 1, heading: String? = nil, line: String? = nil) {
        self.blocks = blocks; self.shape = shape; self.motion = motion; self.heading = heading; self.line = line
    }
}

public enum GenRules {
    public static func maxParts(_ band: Int) -> Int { band == 0 ? 3 : 6 }
    static func calm(_ band: Int) -> Bool { band <= 1 }

    static func allowed(_ part: GenPart, band: Int, hasNote: Bool, hasVision: Bool) -> Bool {
        switch part {
        case .vision: return band >= 5 && hasVision
        case .note: return band <= 2 && hasNote
        case .week: return band >= 3
        case .plan: return band == 3 || band >= 4
        case .walk: return band >= 2
        default: return true
        }
    }

    /// The model's proposal held to the band: only allowed parts, each once, a move he can act on, three to six parts (Heavy: two or
    /// three), calm on Heavy and Hot.
    public static func fit(_ s: GenScreen, band: Int, hasNote: Bool, hasVision: Bool) -> GenScreen {
        var out = s
        var seen = Set<GenPart>()
        var blocks = s.blocks.filter { allowed($0.part, band: band, hasNote: hasNote, hasVision: hasVision) && seen.insert($0.part).inserted }
        if !blocks.contains(where: { $0.part.acts }) { blocks.insert(GenBlock(.move, size: 2), at: 0) }
        for filler in [GenPart.buddy, .wall, .text] where blocks.count < (band == 0 ? 2 : 3) && !seen.contains(filler) {
            blocks.append(GenBlock(filler))
            seen.insert(filler)
        }
        while blocks.count > maxParts(band) {
            // drop from the end, never the last part he can act on
            let movers = blocks.filter { $0.part.acts }.count
            guard let i = blocks.indices.reversed().first(where: { !blocks[$0].part.acts || movers > 1 }) else { break }
            blocks.remove(at: i)
        }
        out.blocks = blocks.map { GenBlock($0.part, size: min(2, max(0, $0.size)), variant: min(2, max(0, $0.variant))) }
        out.shape = min(3, max(0, s.shape))
        out.motion = calm(band) ? 0 : min(2, max(0, s.motion))
        return out
    }

    static let spelled: Set<String> = ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                                       "twenty", "thirty", "forty", "fifty", "hundred", "thousand", "million"]
    static let abundance = ["luxur", "abundan", "wealth", "rich", "money", "prosper", "empire", "fortune"]

    static func words(_ s: String) -> [String] { s.lowercased().split { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" }.map(String.init) }

    /// One piece of written text, or nil when it breaks a rule: a banned word, a question, an exclamation, a number, too long, or
    /// (on Heavy) abundance talk.
    public static func clean(_ text: String?, maxWords: Int, band: Int, banned: [String]) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.count <= maxWords * 9 else { return nil }
        let lower = t.lowercased(), w = words(t)
        if w.isEmpty || w.count > maxWords { return nil }
        if t.contains("?") || t.contains("!") || t.contains("\n") || t.contains(where: { $0.isNumber }) { return nil }
        if w.contains(where: { spelled.contains($0) }) { return nil }
        if banned.contains(where: { !$0.isEmpty && lower.contains($0.lowercased()) }) { return nil }
        if band == 0 && abundance.contains(where: { root in w.contains { $0.hasPrefix(root) } }) { return nil }
        return t
    }

    /// Heading and line after the filter. A rejected line is replaced by his crowned one; Heavy shows at most 8 written words in all.
    public static func written(heading: String?, line: String?, band: Int, crowned: String, banned: [String]) -> (heading: String?, line: String) {
        let h = clean(heading, maxWords: band == 0 ? 3 : 5, band: band, banned: banned)
        guard let l = clean(line, maxWords: band == 0 ? 8 : 18, band: band, banned: banned) else {
            return (band == 0 ? nil : h, crowned)
        }
        if band == 0, let h, words(h).count + words(l).count > 8 { return (nil, l) }
        return (h, l)
    }
}

/// SplitMix64: the same seed draws the same screen.
public struct GenRandom: Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next(_ bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % UInt64(max(1, bound)))
    }
}

public enum GenVariety {
    /// FNV-1a, so a seed comes from words (shift date, tap count, band) and is the same every time.
    public static func seed(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }

    /// The app's own variation on top of the model: order, sizes, drawing variants, spacing, corners, the borrowed pack and the wall.
    public static func vary(_ s: GenScreen, band: Int, seed: UInt64) -> GenScreen {
        var r = GenRandom(seed: seed), out = s
        out.seed = seed
        var blocks = s.blocks
        // the model's lead stays first; the rest are re-ordered
        if blocks.count > 2 {
            var tail = Array(blocks.dropFirst())
            for i in stride(from: tail.count - 1, to: 0, by: -1) { tail.swapAt(i, r.next(i + 1)) }
            blocks = [blocks[0]] + tail
        }
        for i in blocks.indices {
            blocks[i].variant = r.next(3)
            blocks[i].size = i == 0 ? 1 + r.next(2) : r.next(3)
        }
        out.blocks = blocks
        out.shape = r.next(4)
        out.spacing = r.next(3)
        out.pack = r.next(997)
        out.wallAngle = band <= 1 ? 0 : r.next(8) * 45
        out.wallZoom = 1.0 + Double(r.next(5)) * 0.25
        return out
    }

    /// What a screen looks like, words left out.
    public static func signature(_ s: GenScreen) -> [String] {
        s.blocks.enumerated().map { "\($0.offset):\($0.element.part.rawValue).\($0.element.size).\($0.element.variant)" }
            + ["shape:\(s.shape)", "space:\(s.spacing)", "pack:\(s.pack)"]
    }

    /// 0 nothing shared, 1 identical.
    public static func likeness(_ a: [String], _ b: [String]) -> Double {
        let sa = Set(a), sb = Set(b)
        let all = sa.union(sb).count
        return all == 0 ? 1 : Double(sa.intersection(sb).count) / Double(all)
    }

    /// Re-seeds until the screen is unlike every one of the recent ones; if none passes, the least alike wins.
    public static func distinct(_ s: GenScreen, band: Int, seed: UInt64, recent: [[String]], limit: Double = 0.5) -> GenScreen {
        var best = vary(s, band: band, seed: seed), bestScore = 2.0
        for i in 0..<40 {
            let v = vary(s, band: band, seed: seed &+ UInt64(i))
            let sig = signature(v)
            let score = recent.map { likeness(sig, $0) }.max() ?? 0
            if score < limit { return v }
            if score < bestScore { best = v; bestScore = score }
        }
        return best
    }
}
