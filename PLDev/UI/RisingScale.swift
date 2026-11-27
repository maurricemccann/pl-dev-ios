import AVFoundation
import CryptoKit
import SwiftUI
import UserNotifications

// The Rising Scale (his ask 11-25, S353·7b1e; spec: "PL DEV RISING SCALE" in the vault): one tap says how he feels, the look
// follows what he tapped and aims one step up (RisingSteps.swift), and a new look is drawn from each date. Everything he taps stays on this phone.

/// Seven bands over the 22 steps, lowest first.
enum Band: Int, CaseIterable, Codable {
    case heavy, hot, low, stuck, steady, rising, lit
    var title: String { ["Heavy", "Hot", "Low", "Stuck", "Steady", "Rising", "Lit"][rawValue] }
    var words: [String] {
        [["fear", "grief", "despair", "powerless", "insecure", "guilt", "unworthy"],
         ["anger", "revenge", "rage", "hatred", "jealousy"],
         ["doubt", "worry", "blame", "discouraged"],
         ["boredom", "pessimism", "frustration", "overwhelm", "disappointment"],
         ["contentment", "hope", "optimism"],
         ["belief", "expectation", "enthusiasm", "happiness"],
         ["joy", "appreciation", "love", "passion", "empowered"]][rawValue]
    }
    var key: String { title.lowercased() }
    var oneUp: Band { Band(rawValue: rawValue + 1) ?? .lit }
}
extension Band: Comparable { static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue } }

struct CheckIn: Codable {
    let at: Date; let band: Band; var word: String?; var tiredBody = false; var did: Bool? = nil
    // the quick questions (his 11-26: "it may need more questions to understand how u feel"); optional, so older taps still read
    var energy: Int? = nil, control: Int? = nil, about: String? = nil
    // what he did and when (for "what lifts you"), and one-tap tags (his rulings 11-26 afternoon); optional, so older taps still read
    var move: String? = nil, doneAt: Date? = nil, tags: [String]? = nil
}

/// One-tap questions after the curve, and what the answers change. Wording is a working draft, his to rewrite.
enum RisingAsk {
    static let questions: [(ask: String, options: [String])] = [
        ("How much have you got in you?", ["Empty", "Some", "Plenty"]),
        ("Is it in your hands?", ["No", "Partly", "Yes"]),
        ("What is it about?", ["Work", "Money", "Body", "People", "My art", "No idea"])]

    /// One-tap context for a tap, so the month can be read against what the day held.
    static let tags = ["Slept short", "Drew", "Posted", "Sale", "Day off"]

    /// At the very bottom ask almost nothing.
    static func count(_ band: Band) -> Int { band == .heavy ? 1 : questions.count }

    /// One sentence from the answers, the strongest need first.
    static func nudge(_ t: CheckIn) -> String? {
        if t.energy == 0 { return "Empty tank. Water, then lie down." }
        if t.control == 0 { return "Not yours tonight. Pick one thing that is." }
        return switch t.about {
        case "Work": "Finish one small thing before the next one starts."
        case "Money": "Name the next money move, and the one thing in its way."
        case "Body": "Move for two minutes, then drink water."
        case "People": "Send one line of thanks to someone. It does not need the right words."
        case "My art": "Make for ten minutes, then show one person."
        case "No idea": "It needs no name. Take the one small move below."
        default: nil
        }
    }

    /// One small thing a day that makes a person good to be near. From Stuck up; the feed's `buddy.magnet` replaces the list.
    static func magnet(_ date: Date = .now) -> String {
        // Duet job 71, section 4: the five warmth steps with evidence. Done or skip; nothing is counted against him.
        let own = ["One follow-up: in your next conversation, ask one question about what they just said.",
                   "One thank-you: two lines to someone, what they did and why it mattered. Send it or keep it.",
                   "One kind act, any size, for anyone.",
                   "Expect warmth: people usually like you more than you think. Pick one warm opener.",
                   "One tiny step: say hello to someone new, show one work in progress, or tidy one thing."]
        let list = ThemeFeed.list(ThemeFeed.feed?.buddy?["magnet"]) ?? own
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date.addingTimeInterval(-15 * 3600)) ?? 0
        return list.isEmpty ? "" : list[day % list.count]
    }
}

@MainActor @Observable final class RisingScale {
    static let shared = RisingScale()
    nonisolated static let id = "daily"
    private let d = UserDefaults.standard
    /// His check-ins and note, in a file the phone cannot be read from while locked (they were in app preferences until 11-26).
    nonisolated static let file = URL.applicationSupportDirectory.appending(path: "rising.json")
    private struct Store: Codable { var log: [CheckIn]; var note: String }
    private(set) var log: [CheckIn] = []
    var note = "" { didSet { if loaded { save() } } }
    @ObservationIgnored private var loaded = false

    private init() { load() }

    /// Nothing is written until a read has worked, so a locked phone cannot replace his history with an empty one.
    func load() {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: Self.file.path) {
            guard let data = try? Data(contentsOf: Self.file) else { return }
            if let s = try? JSONDecoder().decode(Store.self, from: data) {
                log = s.log; note = s.note
            } else {
                try? FileManager.default.moveItem(at: Self.file, to: Self.file.appendingPathExtension("bad"))   // kept, not overwritten
            }
            loaded = true
        } else {
            log = d.data(forKey: "pldev.rising.log").flatMap { try? JSONDecoder().decode([CheckIn].self, from: $0) } ?? []
            note = d.string(forKey: "pldev.rising.note") ?? ""
            loaded = true
            if save() { d.removeObject(forKey: "pldev.rising.log"); d.removeObject(forKey: "pldev.rising.note") }
        }
    }

    /// Every check-in, the note and the plan, gone from this phone.
    func erase() {
        load()
        guard loaded else { return }
        log = []; note = ""; save()
        for k in ["last", "plan", "saidDay", "said", "turn", "undone", "log", "note", "drained", "looks", "firstSaid", "returned"] { d.removeObject(forKey: "pldev.rising." + k) }
        showWords = false
        Task { await wearIfDue() }
    }

    private static let pacific: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current; return c
    }()
    /// His day starts at 3 PM, so a 4 AM tap belongs to the shift that began the afternoon before.
    nonisolated static func shiftDay(_ date: Date) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let p = c.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-15 * 3600))
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    /// True while the check-in is up: every time the app is opened or come back to (his ruling 11-25).
    var asking = false
    var showWords = false

    var current: CheckIn? { log.last.flatMap { Self.shiftDay($0.at) == Self.shiftDay(.now) ? $0 : nil } }

    @discardableResult private func save() -> Bool {
        guard loaded, let data = try? JSONEncoder().encode(Store(log: Array(log.suffix(2000)), note: note)) else { return false }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: Self.file, options: [.atomic, .completeFileProtection])) != nil
    }

    /// The new look is revealed like a pack card (his ask 11-26): the glyph field covers the app the moment he answers, the look
    /// changes underneath, then the field burns away. `revealAt` is when the burn starts (nil while the look is still applying).
    var revealing = false
    var revealAt: Date?
    /// The step colour between the old band and the new (Duet job 71: OKLab midpoint), tinting the glyph field as it burns.
    var revealTint: String?

    /// The cable tour (PhoneTour.swift): a band shown as if tapped, held in memory only, never saved; endPreview reads his log back.
    func previewTap(_ band: Band) { log.append(CheckIn(at: .now, band: band)) }
    func endPreview() { loaded = false; load() }

    func tap(_ band: Band) {
        load()
        let reveals = followsFeeling || wearsDaily
        if reveals { revealTint = Self.stepHex(from: Self.lookBand(), to: band); revealAt = nil; revealing = true }
        ring(band)
        log.append(CheckIn(at: .now, band: band)); save(); RisingShare.tapped(band)   // the widget and the shift Live Activity
        d.set(Self.shiftDay(.now) + "/\(band.rawValue)", forKey: "pldev.rising.last")
        d.removeObject(forKey: "pldev.rising.undone")
        d.removeObject(forKey: "pldev.rising.drained")
        scheduleReminders()
        Task {
            if followsFeeling && !wearsDaily { await setDaily(true) } else { await wearIfDue() }
            if reveals { revealAt = .now }
        }
    }
    func refine(word: String? = nil, tiredBody: Bool? = nil, energy: Int? = nil, control: Int? = nil, about: String? = nil) {
        guard var last = current, !log.isEmpty else { return }
        if let word { last.word = word }
        if let energy {
            last.energy = energy
            d.set(energy == 0, forKey: "pldev.rising.drained")   // an empty tank stills the whole app
            Task { await wearIfDue() }
        }
        if let control { last.control = control }
        if let about { last.about = about }
        if let tiredBody { last.tiredBody = tiredBody }
        log[log.count - 1] = last; save()
    }

    func markDone(_ move: String) {
        guard current != nil, !log.isEmpty else { return }
        log[log.count - 1].did = true; log[log.count - 1].move = move; log[log.count - 1].doneAt = .now; save()
        guard reminds, !asleep(at: Date().addingTimeInterval(15 * 60)) else { return }
        // ask again a little later: the second tap is what shows whether the move lifted him
        let content = UNMutableNotificationContent()
        content.title = "And now? Tap how you feel."
        content.categoryIdentifier = "rising"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rising-after", content: content,
                                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)))
    }

    /// The last n shift days, oldest first: the day's label, its average step (nil = no tap, which costs nothing) and its tap count.
    func days(_ n: Int) -> [(letter: String, step: Double?, taps: Int)] {
        let byDay = Dictionary(grouping: log.suffix(400), by: { Self.shiftDay($0.at) })
        let f = DateFormatter()
        f.dateFormat = n > 7 ? "d" : "EEEEE"
        return (0..<n).reversed().map { back in
            let date = Date().addingTimeInterval(Double(-back) * 86400)
            let taps = byDay[Self.shiftDay(date)] ?? []
            let step = taps.isEmpty ? nil : Double(taps.map(\.band.rawValue).reduce(0, +)) / Double(taps.count)
            return (letter: f.string(from: date.addingTimeInterval(-15 * 3600)), step: step, taps: taps.count)
        }
    }

    /// Three shift days in a row averaging Heavy.
    var heavyRun: Bool {
        let days = Dictionary(grouping: log, by: { Self.shiftDay($0.at) })
        let last = (0..<3).map { Self.shiftDay(Date().addingTimeInterval(Double(-$0) * 86400)) }
        return last.allSatisfy { day in
            guard let taps = days[day], !taps.isEmpty else { return false }
            return Double(taps.map(\.band.rawValue).reduce(0, +)) / Double(taps.count) < 0.5
        }
    }

    /// Each move he marked done, against his next tap inside 90 minutes (the 15-minute re-ask): did it go up. Shown from 10 pairs
    /// (an early signal), a pattern from 20 (Duet job 71, section 6: fewer pairs than that is noise).
    var lifts: [(move: String, up: Int, of: Int)] {
        var t: [String: (up: Int, of: Int)] = [:]
        for (a, b) in zip(log, log.dropFirst()) {
            guard let move = a.move, let done = a.doneAt else { continue }
            let gap = b.at.timeIntervalSince(done)
            guard gap > 0, gap < 5400 else { continue }
            let v = t[move] ?? (up: 0, of: 0)
            t[move] = (up: v.up + (b.band > a.band ? 1 : 0), of: v.of + 1)
        }
        return t.filter { $0.value.of >= 10 }
            .map { (move: $0.key, up: $0.value.up, of: $0.value.of) }
            .sorted { $0.up * $1.of > $1.up * $0.of }
    }
    /// "Walk: you went up 6 of 8 times."
    var liftLine: String? {
        lifts.first.map { "\($0.move): you went up \($0.up) of \($0.of) times, " + ($0.of >= 20 ? "a pattern" : "an early signal")
            + ". Part of any lift is expecting it, and that still counts." }
    }

    /// The night's high point so far, for the end of every session (peak-end).
    var bestTonight: String? {
        log.suffix(40).filter { Self.shiftDay($0.at) == Self.shiftDay(.now) }.map(\.band).max().map(\.title)
    }
    /// Nights he tapped at all: a count that only grows.
    var nightsShown: Int { Set(log.map { Self.shiftDay($0.at) }).count }
    /// The awe minute comes back once a week.
    var aweDue: Bool { !log.contains { $0.move == "Awe minute" && ($0.doneAt ?? .distantPast) > Date().addingTimeInterval(-7 * 86400) } }
    /// Mondays and the 1st are fresh starts (Duet job 71), by his shift day.
    var freshStart: String? {
        let p = Self.shiftDay(.now).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let day = Self.pacific.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return nil }
        if p[2] == 1 { return "the 1st" }
        return Self.pacific.component(.weekday, from: day) == 2 ? "Monday" : nil
    }
    /// The wallpaper's drift (WCAG 2.2.2: moving content gets a way to stop it). Reduce Motion stops it too.
    var movingBackground: Bool {
        get { d.object(forKey: "pldev.rising.moving") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.moving") }
    }
    /// -1 smoother, 0 as is, 1 richer: the wall's density, contrast and drift one step either way (Duet job 72).
    var patternPick: Int {
        get { d.integer(forKey: "pldev.rising.pattern") }
        set { d.set(newValue, forKey: "pldev.rising.pattern"); if wearsDaily { Task { await wearIfDue(force: true) } } }
    }
    var dims: Bool {
        get { d.object(forKey: "pldev.rising.dim") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.dim") }
    }

    /// The word he picks most for a band, shown first while the rest fade in.
    func topWord(_ band: Band) -> String? {
        let words = log.suffix(300).filter { $0.band == band }.compactMap(\.word)
        return Dictionary(grouping: words, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    /// The first tap of a shift day is the wake check-in.
    var firstOfShift: Bool { current != nil && log.suffix(20).filter { Self.shiftDay($0.at) == Self.shiftDay(.now) }.count == 1 }

    func toggle(tag: String) {
        guard current != nil, !log.isEmpty else { return }
        var t = log[log.count - 1].tags ?? []
        if let i = t.firstIndex(of: tag) { t.remove(at: i) } else { t.append(tag) }
        log[log.count - 1].tags = t; save()
    }

    /// No notices from this screen through his daytime sleep, 6 AM to 3 PM Pacific (3 PM is where the shift day starts).
    /// Home brings forward the tiles that raise the scale for the last tap (his list 11-26 4:00 PM, over the research's
    /// "controls never move"); off puts the config's order back.
    var homeFollows: Bool {
        get { d.object(forKey: "pldev.rising.homeFollows") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.homeFollows") }
    }
    /// The section ids to bring forward now; empty = the config's order. Moves that lifted him (an early signal or better, up more
    /// often than not) bring their section first; the band's own list fills the rest.
    static func homeOrder() -> [String] {
        guard UserDefaults.standard.object(forKey: "pldev.rising.homeFollows") as? Bool ?? true, let b = lookBand() else { return [] }
        let lifted = shared.lifts.filter { $0.up * 2 > $0.of }.compactMap { l in moveSection.first { l.move.hasPrefix($0.0) }?.1 }
        var seen = Set<String>()
        return (lifted + RisingStep.of(b).lifts).filter { seen.insert($0).inserted }
    }
    /// Which Home section a done move belongs to, where it is obvious.
    static let moveSection: [(String, String)] = [
        ("Make something", "paint"), ("Made it", "paint"), ("Night scene", "paint"), ("Vision board", "paint"),
        ("Listen", "practice"), ("Breathe", "practice"), ("Box breathing", "practice"), ("Cool down", "practice"),
        ("Savour", "practice"), ("Awe minute", "gate"), ("Brisk walk with music", "composer")]

    /// One soft tone per band on the check-in (item 92), off until he turns it on; the ambient category obeys the ringer switch.
    var bandSounds: Bool {
        get { d.bool(forKey: "pldev.rising.sounds") }
        set { d.set(newValue, forKey: "pldev.rising.sounds") }
    }
    @ObservationIgnored private var chime: AVAudioPlayer?
    private func ring(_ band: Band) {
        guard bandSounds else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        chime = try? AVAudioPlayer(data: Self.tone(band))
        chime?.play()
    }
    /// Lower and longer at Heavy, higher and brighter toward Lit: a sine with a soft attack and a falling tail, quiet.
    nonisolated static func tone(_ band: Band) -> Data {
        let rate = 44_100, n = band.rawValue
        let freq = [196.0, 208, 233, 262, 294, 349, 392][n], seconds = 0.55 - Double(n) * 0.04, bright = Double(n) / 6 * 0.35
        let frames = Int(Double(rate) * seconds)
        var pcm = [Int16](repeating: 0, count: frames)
        for i in 0..<frames {
            let t = Double(i) / Double(rate)
            let env = min(1, t / 0.02) * exp(-4 * t / seconds)
            let wave = sin(2 * .pi * freq * t) + bright * sin(2 * .pi * freq * 2 * t)
            pcm[i] = Int16(wave / (1 + bright) * env * 3_000)
        }
        var d = Data()
        func word<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(frames * 2)
        d.append(contentsOf: Array("RIFF".utf8)); word(UInt32(36) + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(rate)); word(UInt32(rate * 2)); word(UInt16(2)); word(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); word(bytes)
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    var quietDay: Bool {
        get { d.object(forKey: "pldev.rising.quiet") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.quiet") }
    }
    func asleep(at date: Date) -> Bool { quietDay && (6..<15).contains(Self.pacific.component(.hour, from: date)) }

    /// Tonight's coin flip between his sources: a calm, ordinary night scene or a bright one. Drawn from the date, so it holds all night.
    var nightCalm: Bool { Self.seed()[4] < 0.5 }

    // MARK: the look

    /// Three taps on today's look, kept per day with its wallpaper; the date's pick leaves out wallpapers that score low.
    static let lookAsks = ["Pleasant", "Energy", "In control"]
    private var looksTick = 0
    var lookRated: [Int] {
        _ = looksTick
        return ((d.dictionary(forKey: "pldev.rising.looks") as? [String: [String]])?[Self.shiftDay(.now)] ?? []).dropFirst().compactMap { Int($0) }
    }
    func rateLook(_ i: Int) {
        var all = d.dictionary(forKey: "pldev.rising.looks") as? [String: [String]] ?? [:]
        var picked = Set(lookRated)
        if picked.contains(i) { picked.remove(i) } else { picked.insert(i) }
        all[Self.shiftDay(.now)] = [Self.preset().wall] + picked.sorted().map { String($0) }
        d.set(all, forKey: "pldev.rising.looks")
        looksTick += 1
    }
    /// Each wallpaper's scores, one per rated day (0 to 3 taps).
    nonisolated static func lookScores() -> [String: [Int]] {
        let all = UserDefaults.standard.dictionary(forKey: "pldev.rising.looks") as? [String: [String]] ?? [:]
        var out: [String: [Int]] = [:]
        for v in all.values { if let w = v.first { out[w, default: []].append(v.count - 1) } }
        return out
    }

    /// The feeling's own colour, for the curve and its dot (his ruling 11-25): each state plainly its own, heavy slate to lit yellow.
    nonisolated static func tint(_ b: Band) -> Color {
        Color(hex: ["#7f8db0", "#e0524a", "#5b93d6", "#3fb5a6", "#6cbf5e", "#f0912e", "#ffd84d"][b.rawValue]) ?? .orange
    }

    var wearsDaily: Bool { d.string(forKey: "pldev.themeId") == Self.id }
    var followsFeeling: Bool {
        get { d.object(forKey: "pldev.rising.follow") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.follow"); Task { await wearIfDue() } }
    }
    /// "Undo": today's date look without the feeling, until the next tap.
    func undoFeeling() { d.set(true, forKey: "pldev.rising.undone"); Task { await wearIfDue() } }

    /// The answer the look follows: what he tapped (its step aims one up). nil = today's date look alone.
    nonisolated static func lookBand() -> Band? {
        let d = UserDefaults.standard
        guard d.object(forKey: "pldev.rising.follow") as? Bool ?? true, !d.bool(forKey: "pldev.rising.undone"),
              let last = d.string(forKey: "pldev.rising.last")?.split(separator: "/"), last.count == 2, String(last[0]) == shiftDay(.now)
        else { return nil }
        return Int(last[1]).flatMap(Band.init(rawValue:))
    }

    private nonisolated static func seed() -> [Double] {
        let digest = Array(SHA256.hash(data: Data(("pldev-" + shiftDay(.now)).utf8)))
        return (0..<8).map { i in digest[i * 4..<i * 4 + 4].reduce(0.0) { $0 * 256 + Double($1) } / 4_294_967_296 }
    }

    /// OKLCH to "#rrggbb"; chroma is lowered until the colour fits sRGB, so lightness (and so contrast) holds.
    private nonisolated static func hex(_ L: Double, _ C: Double, _ h: Double) -> String {
        var c = C
        while true {
            let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
            let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
            let rgb = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                       -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                       -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
            if rgb.allSatisfy({ $0 >= -0.000001 && $0 <= 1.000001 }) || c <= 0 {
                return "#" + rgb.map { v in
                    let x = min(max(v, 0), 1)
                    return String(format: "%02x", Int(((x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055) * 255).rounded()))
                }.joined()
            }
            c = max(0, c - 0.005)
        }
    }

    /// The wall's line colour for the tapped band (Duet job 72, section 6): the ground's own hue and chroma, lighter by the band's
    /// Michelson contrast. OKLab L is close to the cube root of luminance, so L scales by ((1 + c) / (1 - c))^(1/3).
    nonisolated static func lineHex() -> String? {
        guard let band = lookBand(), let p = RisingStep.pattern[band], let g = RisingStep.of(band).oklch.first, g.count == 3 else { return nil }
        let c = p.contrast[RisingStep.patternLevel()]
        return hex(g[0] * pow((1 + c) / (1 - c), 1.0 / 3), g[1], g[2])
    }

    /// Upward drift in points a second for the tapped band (job 72, section 5); 0 = still. nil = no tap today.
    nonisolated static func driftSpeed() -> Double? {
        guard let band = lookBand(), let p = RisingStep.pattern[band] else { return nil }
        return (UserDefaults.standard.object(forKey: "pldev.rising.moving") as? Bool ?? true) ? p.drift[RisingStep.patternLevel()] : 0
    }

    /// The step colour from one band's accent to the next, mixed in OKLab so warm-to-cool passes through grey, not magenta.
    nonisolated static func stepHex(from: Band?, to: Band) -> String? {
        let b = RisingStep.of(to).oklch, a = from.map { RisingStep.of($0).oklch } ?? b
        guard a.count == 5, b.count == 5 else { return nil }
        func lab(_ p: [Double]) -> (Double, Double, Double) { (p[0], p[1] * cos(p[2] * .pi / 180), p[1] * sin(p[2] * .pi / 180)) }
        let x = lab(a[4]), y = lab(b[4])
        let L = (x.0 + y.0) / 2, A = (x.1 + y.1) / 2, B = (x.2 + y.2) / 2
        return hex(L, (A * A + B * B).squareRoot(), atan2(B, A) * 180 / .pi)
    }

    /// Today's colours. The ground stays dark and the text light, so every hue reads.
    nonisolated static func palette() -> HousePalette {
        if let o = lookBand().map({ RisingStep.of($0).oklch }), o.count == 5 {   // Duet job 71's exact table, contrast computed there
            let x = o.map { hex($0[0], $0[1], $0[2]) }
            return HousePalette(name: "th-daily", ground: x[0], text: x[2], key: x[4], accent: x[4], surface: x[1])
        }
        let f = seed(), step = lookBand().map(RisingStep.of)
        let h = step?.hue.map { $0 + (f[0] - 0.5) * 12 } ?? f[0] * 360
        let c = step?.chroma ?? 0.05 + f[1] * 0.07
        let light = step?.light ?? 0.19
        return HousePalette(name: "th-daily", ground: hex(light, c * 0.5, h), text: hex(0.94, 0.015, h),
                            key: hex(0.78, c * 1.2, h), accent: hex(0.82, step?.pop ?? c, h + (step?.turn ?? 40)),
                            surface: hex(light + 0.06, c * 0.5, h))
    }

    nonisolated static func preset() -> PLThemePreset {
        let f = seed(), step = lookBand().map(RisingStep.of)
        // the date's wallpaper, leaving out any he rated low (average under 1 of 3) on two or more days
        let walls = ["curves", "code|aurora", "code|contour", "code|night"], scores = lookScores()
        let kept = walls.filter { w in let s = scores[w] ?? []; return s.count < 2 || s.reduce(0, +) >= s.count }
        let pool = kept.isEmpty ? walls : kept
        var t = PLThemePreset(id: id, title: "Daily", palette: "th-daily", face: step?.titleFace ?? "v1", text: step?.textFace ?? "jost",
                              note: "A new look each day; your check-in leads it one step up", dark: true, card: step?.card ?? .frosted,
                              radius: step?.radius ?? [1, 1.25, 1.5][Int(f[2] * 3)], space: step?.space ?? 1,
                              tile: step?.tile ?? "squircle", look: step?.look ?? "glass",
                              wall: step?.wall ?? pool[Int(f[3] * Double(pool.count))])
        t.calm = (step?.calm ?? false) || UserDefaults.standard.bool(forKey: "pldev.rising.drained")
        t.tint = 0.4
        t.through = 0.01   // cards and tiles near opaque (surface at 0.88) so text never sits on the curves (his 424 screenshot)
        if let step {
            t.textScale = step.textScale; t.pace = step.pace; t.columns = step.columns
            t.curves = step.curves
            if let band = lookBand(), let p = RisingStep.pattern[band] { t.repeatSize = p.repeatPt[RisingStep.patternLevel()] / p.lineFrac }
        }
        return t
    }

    /// Applies the Daily theme only when its day or band changed, so his own tweaks are not stomped on every launch.
    func wearIfDue(force: Bool = false) async {
        let stamp = Self.shiftDay(.now) + "/v4/" + (Self.lookBand().map { "\($0.rawValue)" } ?? "-") + (d.bool(forKey: "pldev.rising.drained") ? "/still" : "")
        guard force || (wearsDaily && d.string(forKey: "pldev.rising.stamp") != stamp) else { return }
        d.set(stamp, forKey: "pldev.rising.stamp")
        _ = await Self.preset().apply()
    }

    /// First launch with this feature wears Daily (his pick "Both"); the theme he had is kept so the switch can put it back.
    func firstWear() async {
        guard !d.bool(forKey: "pldev.rising.started") else { await wearIfDue(); return }
        d.set(true, forKey: "pldev.rising.started")
        await setDaily(true)
    }
    func setDaily(_ on: Bool) async {
        if on {
            if !wearsDaily { d.set(d.string(forKey: "pldev.themeId") ?? "home", forKey: "pldev.rising.before") }
            await wearIfDue(force: true)
        } else if wearsDaily {
            let before = d.string(forKey: "pldev.rising.before") ?? "home"
            _ = await PLThemePreset.all.first { $0.id == before }?.apply()
        }
    }

    // MARK: reminders

    var reminds: Bool {
        get { d.object(forKey: "pldev.rising.remind") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.remind"); scheduleReminders() }
    }

    /// 4:15 PM, 12:30 AM, 4:30 AM Pacific, every day, as phone notifications (his ruling 11-25: if he has not opened the app
    /// in a while it still asks). The Check-in menu's "Three reminders" switch turns them off.
    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<4).map { "rising-\($0)" })
        guard reminds else { return }
        for (i, time) in [(16, 15), (0, 30), (4, 30)].enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Tap how you feel."
            content.body = "Touch and hold to answer here."
            content.categoryIdentifier = "rising"
            content.sound = .default
            var when = DateComponents(hour: time.0, minute: time.1)
            when.timeZone = TimeZone(identifier: "America/Los_Angeles")
            center.add(UNNotificationRequest(identifier: "rising-\(i)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
    }

    // MARK: Buddy's lines

    private static let body = ["Water, food or sleep first. The rest can wait."]

    var buddyOn: Bool {
        get { d.object(forKey: "pldev.rising.buddy") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.buddy") }
    }
    @ObservationIgnored private var spokeFor: Date?

    /// One line per tap per run of the app, three a shift, none while snoozed.
    func buddyLine() -> String? {
        guard buddyOn, let tap = current, Date().timeIntervalSince1970 > d.double(forKey: "pldev.rising.snooze"), spokeFor != tap.at else { return nil }
        let today = Self.shiftDay(.now)
        var said = d.string(forKey: "pldev.rising.saidDay") == today ? d.integer(forKey: "pldev.rising.said") : 0
        guard said < 3 else { return nil }
        let key = tap.tiredBody ? "body" : tap.band.key
        let pool = ThemeFeed.list(ThemeFeed.feed?.buddy?[key]) ?? (tap.tiredBody ? Self.body : RisingStep.of(tap.band).lines)
        guard !pool.isEmpty else { return nil }
        let turn = d.integer(forKey: "pldev.rising.turn")
        var line = pool[turn % pool.count]
        // a line he has heard comes back after 1, 3, 7 and 21 days, on a tap whose pool holds it (spaced returns; his crowned lines, verbatim)
        let gaps: [Double] = [1, 3, 7, 21], now = Date().timeIntervalSince1970
        var first = d.dictionary(forKey: "pldev.rising.firstSaid") as? [String: Double] ?? [:]
        var stage = d.dictionary(forKey: "pldev.rising.returned") as? [String: Int] ?? [:]
        if let due = pool.first(where: { l in
            guard let heard = first[l] else { return false }
            let s = stage[l] ?? 0
            return s < gaps.count && (now - heard) / 86400 >= gaps[s] }) {
            line = due
            let age = (now - (first[due] ?? now)) / 86400
            stage[due] = gaps.filter { $0 <= age }.count   // a long gap skips the stages it passed, so returns never pile up
            d.set(stage, forKey: "pldev.rising.returned")
        } else if !tap.tiredBody, tap.band <= .low, !note.isEmpty, turn % 2 == 0 {
            line = "You left yourself this: " + note
        } else if first[line] == nil {
            first[line] = now
            d.set(first, forKey: "pldev.rising.firstSaid")
        }
        said += 1
        d.set(turn + 1, forKey: "pldev.rising.turn"); d.set(said, forKey: "pldev.rising.said"); d.set(today, forKey: "pldev.rising.saidDay")
        spokeFor = tap.at
        return line
    }
    func snooze(hours: Double) { d.set(Date().addingTimeInterval(hours * 3600).timeIntervalSince1970, forKey: "pldev.rising.snooze") }
}

/// His line (the middle of curve-comp-02, path 11), 61 points from the Heavy end. His drawing runs off the page there, so its
/// ends were sliced flat and read as clipped (his note 11-25): the same line is drawn with round ends and room around it.
private enum CurvePoints {
    /// "x,y x,y ..." to points: text, not array literals, which held the compiler for 20 minutes (11-25).
    static func read(_ s: String) -> [(CGFloat, CGFloat)] {
        s.split(separator: " ").compactMap { pair in
            let v = pair.split(separator: ",").compactMap { Double($0) }
            return v.count == 2 ? (CGFloat(v[0]), CGFloat(v[1])) : nil
        }
    }
    static let line = read(
        "0.0,0.9465 0.0088,0.9318 0.0192,0.9137 0.0392,0.9179 0.0591,0.9227 0.0791,0.9275 0.0991,0.932 0.1191,0.9361 0.1391,0.9398 0.1592,0.9431 0.1792,0.946 0.1993,0.9484 0.2194,0.9503 0.2395,0.9517 0.2596,0.9526 0.2797,0.9528 0.2998,0.9526 0.3199,0.9516 0.34,0.95 0.36,0.9476 0.3801,0.9445 0.4001,0.9406 0.4201,0.9358 0.44,0.9301 0.4599,0.9235 0.4796,0.9159 0.4993,0.907 0.5189,0.8972 0.5383,0.886 0.5575,0.8736 0.5765,0.8598 0.5953,0.8446 0.6138,0.8279 0.632,0.8097 0.6498,0.7899 0.6672,0.7685 0.6842,0.7456 0.7007,0.721 0.7166,0.695 0.732,0.6675 0.7468,0.6385 0.761,0.6082 0.7746,0.5767 0.7876,0.5441 0.8,0.5105 0.8118,0.476 0.8234,0.4409 0.8348,0.4058 0.8463,0.3707 0.8578,0.3356 0.8694,0.3007 0.881,0.2658 0.8927,0.231 0.9045,0.1964 0.9163,0.1619 0.9283,0.1275 0.9404,0.0934 0.9526,0.0594 0.968,0.0371 0.9843,0.0205 1.0,0.0068")
    static let width: CGFloat = 14, inset: CGFloat = 9
    /// The drawn part: the corner hooks left by the flat cuts are trimmed off.
    static let drawn = 2...56
    static func at(_ i: Int, in r: CGRect) -> CGPoint {
        let p = line[min(max(i, drawn.lowerBound), drawn.upperBound)]
        return CGPoint(x: r.minX + inset + p.0 * (r.width - 2 * inset), y: r.minY + inset + p.1 * (r.height - 2 * inset))
    }
}

private struct HisCurve: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addLines(CurvePoints.drawn.map { CurvePoints.at($0, in: r) })
        return p.strokedPath(StrokeStyle(lineWidth: CurvePoints.width, lineCap: .round, lineJoin: .round))
    }
}

/// The check-in is one line of his beside the title (curve-comp-02, his 11-25 "Comp 2 curve 11 ... right next to where it says
/// pl dev"). The curve is the slider: Heavy at its low left end, Lit at the top right. It glows while there is a question.
struct RisingCurve: View {
    @State private var rising = RisingScale.shared
    @State private var dragging: Band?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private static let size = CGSize(width: 190, height: 89)   // his shape's own 2.13 : 1

    private static func at(_ i: Int) -> CGPoint { CurvePoints.at(i, in: CGRect(origin: .zero, size: size)) }
    private static func band(near p: CGPoint) -> Band {
        let i = CurvePoints.line.indices.min { a, b in
            hypot(at(a).x - p.x, at(a).y - p.y) < hypot(at(b).x - p.x, at(b).y - p.y)
        } ?? 30
        return Band(rawValue: Int((Double(i) / 10).rounded())) ?? .stuck
    }

    var body: some View {
        // the knob: where the finger is, else his last answer (hidden while a new question waits)
        let shown = dragging ?? (rising.asking ? nil : rising.current?.band)
        // the colour: the feeling chosen, and it keeps that colour while it asks again (his ruling 11-25)
        let tint = (dragging ?? rising.current?.band).map(RisingScale.tint) ?? PLTone.accent
        ZStack(alignment: .topLeading) {
            Color.clear
                .glassEffect(.regular.tint(tint.opacity(0.55)), in: HisCurve())
                .shadow(color: tint.opacity(rising.asking ? 1 : 0), radius: rising.asking ? (pulse ? 16 : 5) : 0)
            if let shown {
                Color.clear.frame(width: 30, height: 30)
                    .glassEffect(.regular.tint(RisingScale.tint(shown)).interactive(), in: Circle())   // the dot is the state's colour
                    .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 2))   // and stands off the curve of the same colour
                    .position(Self.at(shown.rawValue * 10))
                    .animation(.snappy, value: shown)
            }
            Text(shown?.title ?? "How do you feel")
                .plFont(.subhead, emphasized: true)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 130, alignment: .leading)
                .offset(x: 0, y: 14)   // above the low left end, where his line leaves room
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 0)   // the finger stays on the curve; the pages do not swipe under it
            .onChanged { dragging = Self.band(near: $0.location) }
            .onEnded { v in
                dragging = nil
                rising.tap(Self.band(near: v.location))
                rising.asking = false
                rising.showWords = true
            })
        .sensoryFeedback(PLHaptic.select, trigger: dragging)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("How you feel")
        .accessibilityValue(rising.current?.band.title ?? "Not set")
        .accessibilityAdjustableAction { d in
            let now = rising.current?.band.rawValue ?? 3
            if let b = Band(rawValue: now + (d == .increment ? 1 : -1)) { rising.tap(b); rising.asking = false; rising.showWords = true }
        }
    }
}

/// The one action for his answer, then the words for where he is, stacked; up only after he answers the curve. The words leave
/// on a pick; Done closes the panel.
struct RisingPanel: View {
    @State private var rising = RisingScale.shared
    @State private var heavyDismissed = UserDefaults.standard.string(forKey: "pldev.rising.heavyShown")
    @State private var named = false
    @State private var confirmErase = false
    @State private var asked = 0
    @State private var showBody = false
    @State private var intention = UserDefaults.standard.string(forKey: "pldev.rising.intention") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rising.showWords, let tap = rising.current {
                HStack {
                    Text(RisingStep.of(tap.band).title).plFont(.subhead, emphasized: true).lineLimit(1)
                    Spacer()
                    if rising.wearsDaily, RisingScale.lookBand() != nil {
                        Button("Undo") { rising.undoFeeling() }.frame(minWidth: 44, minHeight: 44)
                    }
                    menu
                }
                Text("Hawkins: " + RisingStep.of(tap.band).hawkins).plFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityLabel("Hawkins's number for this band: " + RisingStep.of(tap.band).hawkins + ". His muscle-testing number, not a measurement.")
                if asked < RisingAsk.count(tap.band) {
                    question(RisingAsk.questions[asked], at: asked)
                } else {
                if let line = RisingAsk.nudge(tap) { Text(line).plFont(.callout).padding(.vertical, 6) }
                RisingAction(band: tap.band).id(tap.at)
                if let lift = rising.liftLine { Text("What lifts you: " + lift).plFont(.footnote).foregroundStyle(.secondary).padding(.top, 4) }
                HStack {
                    Button(tap.tiredBody ? "Tired body: on" : "Tired body") { rising.refine(tiredBody: !tap.tiredBody) }.frame(minHeight: 44)
                    Button("Body map") { showBody = true }.frame(minHeight: 44).padding(.leading, 12)
                    Spacer()
                    Button("Done") { rising.showWords = false }.frame(minWidth: 44, minHeight: 44)
                }
                // everything else waits behind one More (his screenshots 11-26: the panel was a wall); one question at a time
                DisclosureGroup(isExpanded: $more) {
                    VStack(alignment: .leading, spacing: 6) { extra(tap) }.padding(.top, 6)
                } label: {
                    Text("More").plFont(.footnote).frame(minHeight: 44)
                }
                }
                if rising.heavyRun, heavyDismissed != RisingScale.shiftDay(.now) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Three heavy nights in a row. A good night to reach out to someone you trust.").plFont(.callout)
                        Button("Close") {
                            heavyDismissed = RisingScale.shiftDay(.now)
                            UserDefaults.standard.set(heavyDismissed, forKey: "pldev.rising.heavyShown")
                        }.frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(rising.showWords ? 14 : 0)
        .onChange(of: rising.current?.at) { named = false; asked = 0; more = false }
        .sheet(isPresented: $showBody) { GateBodyMap() }
        .confirmationDialog("Erase every check-in, note and plan on this phone?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { rising.erase() }
        }
        .background {
            if rising.showWords { Color.clear.plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous)) }
        }
    }

    @State private var more = false

    /// What sits behind More: the words, the vision strip, the day's tags, a fresh start, today's look, the magnet, the teaching
    /// line, the count that only grows, and the bars.
    @ViewBuilder private func extra(_ tap: CheckIn) -> some View {
        // at the very bottom ask almost nothing: the words wait until he wants them (research, 11-26)
        if let word = tap.word {
            Text(word).plFont(.callout, emphasized: true).frame(minHeight: 44)
        } else if tap.band <= .low && !named {
            Button("Name it") { named = true }.frame(minHeight: 44)
        } else {
            words(tap)
        }
        if tap.band >= .rising { visionStrip }
        if tap.band >= .steady { Text("Today's magnet move: " + RisingAsk.magnet()).plFont(.footnote).foregroundStyle(.secondary) }
        if tap.band >= .steady {
            Text("What you keep in mind changes what you notice, how hard you work and how you treat people.").plFont(.footnote).foregroundStyle(.secondary)
        }
        tags(tap)
        if tap.band > .heavy, let fresh = rising.freshStart {
            Text("Fresh start, " + fresh + ". One intention for this week, if you want one.").plFont(.footnote)
            TextField("This week I will", text: $intention, axis: .vertical).textFieldStyle(.roundedBorder)
                .onSubmit { UserDefaults.standard.set(intention, forKey: "pldev.rising.intention") }
                .onChange(of: intention) { UserDefaults.standard.set(intention, forKey: "pldev.rising.intention") }
        }
        if rising.wearsDaily { rateLook }
        Text("Nights you showed up: \(rising.nightsShown)").plFont(.caption2).foregroundStyle(.secondary)
        if tap.band >= .stuck { weekBars }
    }

    /// A chip that never breaks a word.
    private func chip(_ title: String, _ symbol: String? = nil, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Group { if let symbol { Label(title, systemImage: symbol) } else { Text(title) } }
                .plFont(.footnote).lineLimit(1).minimumScaleFactor(0.8).fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered).tint(on ? PLTone.accent : .secondary).frame(minHeight: 44)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Up high, his chosen pieces as a vision strip (the Gate's count), each to be paired with one obstacle and one move.
    @ViewBuilder private var visionStrip: some View {
        let _ = GateStore.shared.load()
        let urls = GateStore.shared.saved.count.compactMap { $0.isEmpty ? nil : URL(string: $0) }
        if !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(urls, id: \.self) { u in
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.top, 6)
            .accessibilityLabel("Your chosen pieces")
            Text("Hold one picture. Name the one thing in its way, and your move.").plFont(.footnote).foregroundStyle(.secondary)
        }
    }

    /// One tap each: what the day held.
    private func tags(_ tap: CheckIn) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(RisingAsk.tags, id: \.self) { t in
                    let on = tap.tags?.contains(t) == true
                    chip(t, on ? "checkmark" : "plus", on: on) { rising.toggle(tag: t) }
                }
            }
        }
        .contentMargins(.horizontal, 14, for: .scrollContent)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                     .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }

    /// Three taps on today's look; the Daily generator keeps the wallpapers that score well.
    private var rateLook: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's look").plFont(.footnote).foregroundStyle(.secondary)
            CongregationWrapLayout(spacing: 6) {
                ForEach(Array(RisingScale.lookAsks.enumerated()), id: \.offset) { i, ask in
                    chip(ask, on: rising.lookRated.contains(i)) { rising.rateLook(i) }
                }
            }
        }
    }

    @State private var month = false

    /// Seven days (or thirty) as bars: height is the step, so it reads without the colour. How many check-ins of how many shows
    /// only in the Month view (the diagnostic one), in plain words, never as "missed" (the ship test: progress only adds up).
    private var weekBars: some View {
        let days = rising.days(month ? 30 : 7)
        let stepped = days.compactMap(\.step)
        let tapped = days.reduce(0) { $0 + min(3, $1.taps) }
        let average = stepped.isEmpty ? "No taps" : "Average " + (Band(rawValue: Int((stepped.reduce(0, +) / Double(stepped.count)).rounded()))?.title ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(average + (month ? ", \(tapped) check-ins of \(days.count * 3)" : "")).plFont(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(month ? "Week" : "Month") { month.toggle() }.plFont(.footnote).frame(minWidth: 44, minHeight: 44)
            }
            HStack(alignment: .bottom, spacing: month ? 2 : 8) {
                ForEach(days.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(days[i].step.map { RisingScale.tint(Band(rawValue: Int($0.rounded())) ?? .stuck) } ?? Color.secondary.opacity(0.25))
                            .frame(width: month ? 5 : 10, height: days[i].step.map { 8 + CGFloat($0) * 6 } ?? 4)
                        Text(month && i % 5 != 4 ? " " : days[i].letter).plFont(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last \(days.count) days: " + days.map { d in d.step.map { Band(rawValue: Int($0.rounded()))?.title ?? "" } ?? "no tap" }.joined(separator: ", "))
        }
        .padding(.top, 8)
    }

    private func question(_ q: (ask: String, options: [String]), at i: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(q.ask).plFont(.callout, emphasized: true).padding(.vertical, 6)
            ForEach(Array(q.options.enumerated()), id: \.element) { n, option in
                Button {
                    switch i {
                    case 0: rising.refine(energy: n)
                    case 1: rising.refine(control: n)
                    default: rising.refine(about: option)
                    }
                    asked += 1
                } label: { Text(option).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                .buttonStyle(.bordered).tint(PLTone.accent).padding(.vertical, 2)
            }
            Button("Skip the questions") { asked = RisingAsk.questions.count }.plFont(.footnote).frame(minHeight: 44)
        }
    }

    private func words(_ tap: CheckIn) -> some View {
        let top = rising.topWord(tap.band)
        return CongregationWrapLayout(spacing: 6) {
            ForEach(tap.band.words, id: \.self) { w in
                chip(w, on: false) { rising.refine(word: w) }
                    .modifier(RisingLate(late: top.map { $0 != w } ?? false))   // his usual word first, the rest fade in; nothing moves
            }
        }
    }

    private var menu: some View {
        Menu {
            Toggle("Daily look", isOn: Binding(get: { rising.wearsDaily }, set: { on in if !on { rising.followsFeeling = false }; Task { await rising.setDaily(on) } }))
            Toggle("Look follows my check-in", isOn: Binding(get: { rising.followsFeeling }, set: { rising.followsFeeling = $0 }))
            Toggle("Three reminders", isOn: Binding(get: { rising.reminds }, set: { rising.reminds = $0 }))
            Toggle("Buddy pops up", isOn: Binding(get: { rising.buddyOn }, set: { rising.buddyOn = $0 }))
            Toggle("No notices 6 AM to 3 PM", isOn: Binding(get: { rising.quietDay }, set: { rising.quietDay = $0 }))
            Toggle("Home follows my mood", isOn: Binding(get: { rising.homeFollows }, set: { rising.homeFollows = $0 }))
            Toggle("Dim the app 4 AM to 3 PM", isOn: Binding(get: { rising.dims }, set: { rising.dims = $0 }))
            Toggle("Band sounds", isOn: Binding(get: { rising.bandSounds }, set: { rising.bandSounds = $0 }))
            Toggle("Moving background", isOn: Binding(get: { rising.movingBackground }, set: { rising.movingBackground = $0 }))
            Picker("Pattern", selection: Binding(get: { rising.patternPick }, set: { rising.patternPick = $0 })) {
                Text("Smoother").tag(-1); Text("As is").tag(0); Text("Richer").tag(1)
            }
            ShareLink("Export my check-ins", item: RisingScale.file)
            Button("Erase my check-ins", role: .destructive) { confirmErase = true }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Check-in settings")
    }
}

/// The reveal after a check-in: the pack's glyph field over the whole app, burnt away like the pack's cards (the moltenBurn shader:
/// smooth noise, a glowing gold edge, sparks) over 1.4 seconds once the new look is in place. Reduce Motion skips it. Never
/// blocks a tap.
struct LookReveal: View {
    @State private var rising = RisingScale.shared
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            if rising.revealing && !reduce {
                TimelineView(.animation) { ctx in
                    let p = rising.revealAt.map { min(1, ctx.date.timeIntervalSince($0) / 1.4) } ?? 0
                    GlyphField(strength: 0.6, tint: Color(hex: rising.revealTint) ?? Candle.gold)
                        .colorEffect(ShaderLibrary.moltenBurn(.float(p), .float(2.3), .color(Color(red: 1, green: 0.78, blue: 0.36))))
                        .onChange(of: p >= 1) { _, done in if done { rising.revealing = false } }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(PLHaptic.success, trigger: rising.revealAt)
        .onChange(of: rising.revealAt) { if reduce { rising.revealing = false } }
        .task(id: rising.revealing) {   // never left covering: if the look has not landed in 4 seconds, burn anyway
            guard rising.revealing else { return }
            try? await Task.sleep(for: .seconds(4))
            if rising.revealing && rising.revealAt == nil { rising.revealAt = .now }
        }
    }
}

/// Duet job 71's motion table (section 2), behind Home: Low an upward shimmer, Stuck soft particles, Steady gold motes, Rising
/// motes and a slow warm sweep, Lit motes and glints. Heavy and Hot keep only the breathing ring. Everything rises, nothing
/// pulses faster than once a second, at most 20 particles. Reduce Motion leaves the still ground.
struct RisingMotion: View {
    @State private var rising = RisingScale.shared
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let _ = rising.current   // redraw when he taps
        if !reduce, rising.wearsDaily, let band = RisingScale.lookBand(), band >= .low {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                Canvas { g, size in Self.draw(band, t: ctx.date.timeIntervalSinceReferenceDate, g: &g, size: size) }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private static func draw(_ band: Band, t: Double, g: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let gold = Color(red: 0.98, green: 0.80, blue: 0.45)
        if band == .low {   // three soft bands drifting up 3 pt a second
            for i in 0..<3 {
                let y = h - (t * 3 + Double(i) * h / 3).truncatingRemainder(dividingBy: h + 160) + 80
                g.fill(Path(ellipseIn: CGRect(x: -w * 0.2, y: y - 60, width: w * 1.4, height: 120)), with: .color(.white.opacity(0.035)))
            }
            return
        }
        let (count, speed, color, radius): (Int, Double, Color, Double) = switch band {
        case .stuck: (8, 7, Color.white, 2)
        case .steady: (10, 8, gold, 2.5)
        case .rising: (14, 13, gold, 2.5)
        default: (20, 19, gold, 2.2)
        }
        if band == .rising {   // a warm sweep, bottom to top every 8 seconds
            let y = h - (t / 8).truncatingRemainder(dividingBy: 1) * (h + 240) + 120
            g.fill(Path(CGRect(x: 0, y: y - 120, width: w, height: 240)),
                   with: .linearGradient(Gradient(colors: [.clear, gold.opacity(0.06), .clear]), startPoint: CGPoint(x: 0, y: y - 120), endPoint: CGPoint(x: 0, y: y + 120)))
        }
        for i in 0..<count {
            let r1 = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude
            let r2 = (sin(Double(i) * 78.233) * 12543.123).truncatingRemainder(dividingBy: 1).magnitude
            let travel = (t * speed * (0.8 + 0.4 * r2) + r2 * (h + 40)).truncatingRemainder(dividingBy: h + 40)
            let y = h + 20 - travel
            let x = (r1 * w + (band == .stuck ? travel * 0.3 : 0)).truncatingRemainder(dividingBy: w)
            let fade = min(1, travel / 60) * min(1, (h + 40 - travel) / 60)   // fade in at the bottom, out at the top
            // Lit's glint: one mote brightens for 0.4 s every 5 s
            let glint = band == .lit && i == Int(t / 5) % count && (t.truncatingRemainder(dividingBy: 5)) < 0.4
            let r = glint ? radius * 2.2 : radius
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity((glint ? 0.8 : 0.3) * fade)))
        }
    }
}

/// Dark grounds are not enough before his daytime sleep: brightness is what moves the body clock (Duet job 71, section 1), so
/// the whole app dims about 30% from 4 AM until 3 PM Pacific. A toggle in the check-in menu turns it off.
struct NightDim: View {
    @AppStorage("pldev.rising.dim") private var on = true
    private static let la: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current; return c
    }()

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Color.black.opacity(on && (4..<15).contains(Self.la.component(.hour, from: ctx.date)) ? 0.3 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// His head for Buddy (his drawing, 11-25, the red figure from the left-chest embroidery), his shape and line as he drew them; the face is
/// laid on it and the stem's flat foot rests on whatever is under it.
struct BuddyHead: View {
    let model: BuddyModel
    var side: CGFloat = 144
    var hole = true                     // he comes up out of a scribbled hole (his markup 11-26); Home's stands on the bar
    private static let art = image("buddy-head")
    private static let lines = image("buddy-head-lines")   // his outline alone, to lie over the coloured shape
    private static func image(_ name: String) -> UIImage? {
        Bundle.main.url(forResource: name, withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }
    }

    var body: some View {
        ZStack {
            // the hole first, so he stands in front of it (his note 11-26), over the stem's flat foot (0.55 to 0.91 of the drawing)
            if hole { BuddyHole().frame(width: side * 0.66, height: side * 0.24).position(x: side * 0.73, y: side * 0.97) }
            // his colour is today's step on the curve (his note 11-26: "he shifts like the emotional scale curve")
            if let art = Self.art {
                if let band = RisingScale.shared.current?.band, let lines = Self.lines {
                    Image(uiImage: art).renderingMode(.template).resizable().scaledToFit().foregroundStyle(RisingScale.tint(band)).accessibilityHidden(true)
                    Image(uiImage: lines).resizable().scaledToFit().accessibilityHidden(true)
                } else {
                    Image(uiImage: art).resizable().scaledToFit().accessibilityHidden(true)
                }
            }
            // the big face he ticked (11-25), anchored at his green dot (0.47, 0.36 of the head): face 0.66 of the head wide.
            // pinned = it stays on that spot; every expression and move still plays on it
            BuddyView(model: model, pinned: true)
                .frame(width: side * 0.717, height: side * 0.864)   // BuddyView fits 440 x 530 into 0.92 of this box
                .position(x: side * 0.48, y: side * 0.31)
        }
        .frame(width: side, height: side)
        .padding(.bottom, hole ? side * 0.09 : 0)
    }
}

/// A dark scribbled hole, loop over loop. The same every time: the wobble comes from the loop's number, not chance.
struct BuddyHole: View {
    var body: some View {
        Canvas { ctx, size in
            let ink = GraphicsContext.Shading.color(Color(red: 0.03, green: 0.02, blue: 0.06))
            let base = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.height * 0.14)
            ctx.fill(Path(ellipseIn: base), with: ink)
            for i in 0..<14 {
                let k = Double(i)
                let loop = base.offsetBy(dx: sin(k * 2.3) * size.width * 0.045, dy: cos(k * 1.7) * size.height * 0.08)
                    .insetBy(dx: sin(k * 3.1) * size.width * 0.03, dy: cos(k * 2.9) * size.height * 0.05)
                ctx.stroke(Path(ellipseIn: loop), with: ink, lineWidth: max(1.5, size.height * 0.09))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Buddy slides in from the lower corner of Home, says one line, and leaves 12 seconds after he finishes saying it. Home only, so he never
/// covers drawing or audio.
struct RisingBuddy: View {
    @State private var rising = RisingScale.shared
    @State private var buddy = BuddyModel()
    @State private var line: String?
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if let line {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(line).plFont(.callout)
                        .padding(12)
                        .plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
                        .padding(.bottom, 44)
                    BuddyHead(model: buddy, side: rising.current.map { RisingStep.of($0.band).side } ?? 144, hole: false)
                }
                .padding(.horizontal, PLSpace.margin)   // no gap under him: his stem stands on the bar
                .transition(reduce ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .onTapGesture { withAnimation { self.line = nil } }
                .contextMenu {
                    Button("Quiet for 2 hours") { rising.snooze(hours: 2); self.line = nil }
                    Button("Quiet until tomorrow") { rising.snooze(hours: 18); self.line = nil }
                }
                .accessibilityHint("Tap to send Buddy away")
            }
        }
        .task(id: "\(rising.current?.at.timeIntervalSince1970 ?? 0)/\(rising.asking)") {
            guard !rising.asking else { line = nil; return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let said = rising.buddyLine() else { return }
            buddy.react(.open)
            // and the step's face: calm when low, happy in the middle, excited when high
            if let band = rising.current?.band { buddy.playState(RisingStep.of(band).face) }
            buddy.say(said)
            withAnimation { line = said }
            AccessibilityNotification.Announcement(said).post()
            // up while his mouth moves, then time to read it again (his note 11-25: it left too quick)
            try? await Task.sleep(for: .seconds(Double(BuddyModel.mouthTrack(said).count) * BuddyModel.slot + 12))
            guard !Task.isCancelled else { return }
            withAnimation { line = nil }
        }
    }
}
