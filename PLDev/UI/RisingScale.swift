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
}

/// One-tap questions after the curve, and what the answers change. Wording is a working draft, his to rewrite.
enum RisingAsk {
    static let questions: [(ask: String, options: [String])] = [
        ("How much have you got in you?", ["Empty", "Some", "Plenty"]),
        ("Is it in your hands?", ["No", "Partly", "Yes"]),
        ("What is it about?", ["Work", "Money", "Body", "People", "My art", "No idea"])]

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
        let own = ["Ask someone one follow-up question and listen to the answer.",
                   "Tell one person something you appreciate about them.",
                   "Walk in expecting to be liked. People usually like you more than you think.",
                   "Say yes to one short talk you would normally skip.",
                   "Finish one thing you said you would do.",
                   "Show one piece of your work without explaining it away.",
                   "Picture it done, then name the obstacle and your move."]
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
        for k in ["last", "plan", "saidDay", "said", "turn", "undone", "log", "note", "drained"] { d.removeObject(forKey: "pldev.rising." + k) }
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

    func tap(_ band: Band) {
        load()
        log.append(CheckIn(at: .now, band: band)); save()
        d.set(Self.shiftDay(.now) + "/\(band.rawValue)", forKey: "pldev.rising.last")
        d.removeObject(forKey: "pldev.rising.undone")
        d.removeObject(forKey: "pldev.rising.drained")
        scheduleReminders()
        Task { if followsFeeling && !wearsDaily { await setDaily(true) } else { await wearIfDue() } }
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

    func markDone() {
        guard current != nil, !log.isEmpty else { return }
        log[log.count - 1].did = true; save()
        guard reminds else { return }
        // ask again a little later: the second tap is what shows whether the move lifted him
        let content = UNMutableNotificationContent()
        content.title = "And now? Tap how you feel."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rising-after", content: content,
                                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)))
    }

    /// The last seven shift days, oldest first: the day's letter and its average step (nil = no tap, which costs nothing).
    var week: [(letter: String, step: Double?)] {
        let days = Dictionary(grouping: log.suffix(200), by: { Self.shiftDay($0.at) })
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return (0..<7).reversed().map { back in
            let date = Date().addingTimeInterval(Double(-back) * 86400)
            let taps = days[Self.shiftDay(date)] ?? []
            let step = taps.isEmpty ? nil : Double(taps.map(\.band.rawValue).reduce(0, +)) / Double(taps.count)
            return (f.string(from: date.addingTimeInterval(-15 * 3600)), step)
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

    // MARK: the look

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

    /// Today's colours. The ground stays dark and the text light, so every hue reads.
    nonisolated static func palette() -> HousePalette {
        let f = seed(), step = lookBand().map(RisingStep.of)
        let h = step?.hue.map { $0 + (f[0] - 0.5) * 12 } ?? f[0] * 360
        let c = step?.chroma ?? 0.05 + f[1] * 0.07
        let light = step?.light ?? 0.19
        return HousePalette(name: "th-daily", ground: hex(light, c * 0.5, h), text: hex(0.94, 0.015, h),
                            key: hex(0.70, c * 1.2, h), accent: hex(0.82, c, h + (step?.turn ?? 40)),
                            surface: hex(light + 0.06, c * 0.5, h))
    }

    nonisolated static func preset() -> PLThemePreset {
        let f = seed(), step = lookBand().map(RisingStep.of)
        var t = PLThemePreset(id: id, title: "Daily", palette: "th-daily", face: "v1", text: "jost",
                              note: "A new look each day; your check-in leads it one step up", dark: true, card: .frosted,
                              radius: step?.radius ?? [1, 1.25, 1.5][Int(f[2] * 3)], space: step?.space ?? 1,
                              tile: step?.tile ?? "squircle", look: "glass",
                              wall: step?.wall ?? ["curves", "code|aurora", "code|contour", "code|night"][Int(f[3] * 4)])
        t.calm = (step?.calm ?? false) || UserDefaults.standard.bool(forKey: "pldev.rising.drained")
        t.tint = 0.4
        return t
    }

    /// Applies the Daily theme only when its day or band changed, so his own tweaks are not stomped on every launch.
    func wearIfDue(force: Bool = false) async {
        let stamp = Self.shiftDay(.now) + "/v2/" + (Self.lookBand().map { "\($0.rawValue)" } ?? "-") + (d.bool(forKey: "pldev.rising.drained") ? "/still" : "")
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
        if !tap.tiredBody, tap.band <= .low, !note.isEmpty, turn % 2 == 0 { line = "You left yourself this: " + note }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rising.showWords, let tap = rising.current {
                HStack {
                    Text(RisingStep.of(tap.band).title).plFont(.subhead, emphasized: true)
                    Spacer()
                    if rising.wearsDaily, RisingScale.lookBand() != nil {
                        Button("Undo") { rising.undoFeeling() }.frame(minWidth: 44, minHeight: 44)
                    }
                    menu
                }
                if asked < RisingAsk.count(tap.band) {
                    question(RisingAsk.questions[asked], at: asked)
                } else {
                if let line = RisingAsk.nudge(tap) { Text(line).plFont(.callout).padding(.vertical, 6) }
                RisingAction(band: tap.band).id(tap.at)
                // at the very bottom ask almost nothing: the words wait until he wants them (research, 11-26)
                if let word = tap.word {
                    Text(word).plFont(.callout, emphasized: true).frame(minHeight: 44)
                } else if tap.band <= .low && !named {
                    Button("Name it") { named = true }.frame(minHeight: 44)
                } else {
                    words(tap)
                }
                HStack {
                    Button(tap.tiredBody ? "Tired body: on" : "Tired body") { rising.refine(tiredBody: !tap.tiredBody) }.frame(minHeight: 44)
                    Button("Body map") { showBody = true }.frame(minHeight: 44).padding(.leading, 12)
                    Spacer()
                    Button("Done") { rising.showWords = false }.frame(minWidth: 44, minHeight: 44)
                }
                if tap.band >= .stuck {
                    Text("Today's magnet move: " + RisingAsk.magnet()).plFont(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    weekBars
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
        .onChange(of: rising.current?.at) { named = false; asked = 0 }
        .sheet(isPresented: $showBody) { GateBodyMap() }
        .confirmationDialog("Erase every check-in, note and plan on this phone?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { rising.erase() }
        }
        .background {
            if rising.showWords { Color.clear.plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous)) }
        }
    }

    /// Seven days as bars: height is the step, so it reads without the colour.
    private var weekBars: some View {
        let days = rising.week
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(days.indices, id: \.self) { i in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(days[i].step.map { RisingScale.tint(Band(rawValue: Int($0.rounded())) ?? .stuck) } ?? Color.secondary.opacity(0.25))
                        .frame(width: 10, height: days[i].step.map { 8 + CGFloat($0) * 6 } ?? 4)
                    Text(days[i].letter).plFont(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last seven days: " + days.map { d in d.step.map { Band(rawValue: Int($0.rounded()))?.title ?? "" } ?? "no tap" }.joined(separator: ", "))
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
            }
            Button("Skip the questions") { asked = RisingAsk.questions.count }.plFont(.footnote).frame(minHeight: 44)
        }
    }

    private func words(_ tap: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tap.band.words, id: \.self) { w in
                Button { rising.refine(word: w) } label: {
                    Text(w)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            Toggle("Daily look", isOn: Binding(get: { rising.wearsDaily }, set: { on in if !on { rising.followsFeeling = false }; Task { await rising.setDaily(on) } }))
            Toggle("Look follows my check-in", isOn: Binding(get: { rising.followsFeeling }, set: { rising.followsFeeling = $0 }))
            Toggle("Three reminders", isOn: Binding(get: { rising.reminds }, set: { rising.reminds = $0 }))
            Toggle("Buddy pops up", isOn: Binding(get: { rising.buddyOn }, set: { rising.buddyOn = $0 }))
            ShareLink("Export my check-ins", item: RisingScale.file)
            Button("Erase my check-ins", role: .destructive) { confirmErase = true }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Check-in settings")
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
            // over the stem's flat foot, which spans 0.55 to 0.91 of the drawing
            if hole { BuddyHole().frame(width: side * 0.66, height: side * 0.24).position(x: side * 0.73, y: side * 0.97) }
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
            try? await Task.sleep(for: .seconds(Double(BuddyModel.mouthTrack(said).count) * 0.07 + 12))
            guard !Task.isCancelled else { return }
            withAnimation { line = nil }
        }
    }
}
