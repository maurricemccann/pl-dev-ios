import CryptoKit
import SwiftUI
import UserNotifications

// The Rising Scale (his ask 11-25, S353·7b1e; spec: "PL DEV RISING SCALE" in the vault): one tap says how he feels, the look
// leads one band up, Buddy says one line, and a new look is drawn from each date. Everything he taps stays on this phone.

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
    /// OKLCH hue and chroma of the look.
    var hue: Double { [250, 20, 215, 175, 145, 85, 78][rawValue] }
    var chroma: Double { [0.02, 0.05, 0.05, 0.06, 0.07, 0.10, 0.13][rawValue] }
    var oneUp: Band { Band(rawValue: rawValue + 1) ?? .lit }
    var group: String { self <= .low ? "low" : self <= .steady ? "middle" : "high" }
}
extension Band: Comparable { static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue } }

struct CheckIn: Codable { let at: Date; let band: Band; var word: String?; var tiredBody = false }

@MainActor @Observable final class RisingScale {
    static let shared = RisingScale()
    nonisolated static let id = "daily"
    private let d = UserDefaults.standard
    private(set) var log: [CheckIn]
    var note: String { didSet { d.set(note, forKey: "pldev.rising.note") } }

    private init() {
        log = (UserDefaults.standard.data(forKey: "pldev.rising.log")).flatMap { try? JSONDecoder().decode([CheckIn].self, from: $0) } ?? []
        note = UserDefaults.standard.string(forKey: "pldev.rising.note") ?? ""
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

    private func save() { d.set(try? JSONEncoder().encode(Array(log.suffix(2000))), forKey: "pldev.rising.log") }

    func tap(_ band: Band) {
        log.append(CheckIn(at: .now, band: band)); save()
        d.set(Self.shiftDay(.now) + "/\(band.rawValue)", forKey: "pldev.rising.last")
        d.removeObject(forKey: "pldev.rising.undone")
        scheduleReminders()
        Task { await wearIfDue() }
    }
    func refine(word: String? = nil, tiredBody: Bool? = nil) {
        guard var last = current, !log.isEmpty else { return }
        if let word { last.word = word }
        if let tiredBody { last.tiredBody = tiredBody }
        log[log.count - 1] = last; save()
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

    var wearsDaily: Bool { d.string(forKey: "pldev.themeId") == Self.id }
    var followsFeeling: Bool {
        get { d.object(forKey: "pldev.rising.follow") as? Bool ?? true }
        set { d.set(newValue, forKey: "pldev.rising.follow"); Task { await wearIfDue() } }
    }
    /// "Undo": today's date look without the feeling, until the next tap.
    func undoFeeling() { d.set(true, forKey: "pldev.rising.undone"); Task { await wearIfDue() } }

    /// The band the look wears: one up from his tap, never more.
    nonisolated static func lookBand() -> Band? {
        let d = UserDefaults.standard
        guard d.object(forKey: "pldev.rising.follow") as? Bool ?? true, !d.bool(forKey: "pldev.rising.undone"),
              let last = d.string(forKey: "pldev.rising.last")?.split(separator: "/"), last.count == 2, String(last[0]) == shiftDay(.now)
        else { return nil }
        return Int(last[1]).flatMap(Band.init(rawValue:))?.oneUp
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

    /// Today's colours. Lightness is fixed per role (dark ground, light text), so every hue reads.
    nonisolated static func palette() -> HousePalette {
        let f = seed(), band = lookBand()
        let h = band.map { $0.hue + (f[0] - 0.5) * 24 } ?? f[0] * 360
        let c = band?.chroma ?? 0.05 + f[1] * 0.07
        return HousePalette(name: "th-daily", ground: hex(0.19, c * 0.5, h), text: hex(0.94, 0.015, h),
                            key: hex(0.70, c * 1.2, h + (band == .steady ? -60 : 0)), accent: hex(0.82, c, h + 40),
                            surface: hex(0.25, c * 0.5, h))
    }

    nonisolated static func preset() -> PLThemePreset {
        let f = seed(), band = lookBand()
        var t = PLThemePreset(id: id, title: "Daily", palette: "th-daily", face: "v1", text: "jost",
                              note: "A new look each day; your check-in leads it one step up", dark: true, card: .frosted,
                              radius: [0.5, 1, 1.5][Int(f[2] * 3)], space: 1, tile: "squircle", look: "glass",
                              wall: ["curves", "code|aurora", "code|contour", "code|night"][Int(f[3] * 4)])
        t.calm = band.map { $0 <= .low } ?? false
        t.tint = 0.4
        return t
    }

    /// Applies the Daily theme only when its day or band changed, so his own tweaks are not stomped on every launch.
    func wearIfDue(force: Bool = false) async {
        let stamp = Self.shiftDay(.now) + "/" + (Self.lookBand().map { "\($0.rawValue)" } ?? "-")
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

    /// Working drafts from the research, for him to rewrite; the feed's `buddy` block replaces them without a reinstall.
    private static let drafts: [String: [String]] = [
        "low": ["Heavy is allowed here. Name it, breathe once, and the practice will wait for you.",
                "Abundance does not ask you to feel good first. It starts with one honest breath.",
                "Even on a hard night, something small is working for you. One thing is enough to notice.",
                "Prosperity is built from small steady moves. Tonight, one small move counts as a full step."],
        "middle": ["Boredom is a quiet doorway. Picture one room of the life you want, down to the light.",
                   "Luxury is attention. Your coffee, your music, your gloves: choose each one on purpose tonight.",
                   "The practice is simple: notice what is already good, then let it grow a little.",
                   "Hope is a real step up. Write one line about the version of you who has plenty."],
        "high": ["This feeling is the practice working. Stay with it a moment and let it settle in.",
                 "Abundance follows appreciation. Name three things you enjoy right now, and mean each one.",
                 "Luxury living is a way of standing in the world. You are standing in it now.",
                 "Good nights add up. Keep this one as a marker for the next."],
        "body": ["Water, food or sleep first. The rest can wait."],
    ]

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
        let key = tap.tiredBody ? "body" : tap.band.group
        let pool = ThemeFeed.list(ThemeFeed.feed?.buddy?[key]) ?? Self.drafts[key] ?? []
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

/// The check-in is one line of his beside the title (curve-comp-02, his 11-25 "Comp 2 curve 11 ... right next to where it says
/// pl dev"). The curve is the slider: Heavy at its low left end, Lit at the top right. It glows while there is a question.
struct RisingCurve: View {
    @State private var rising = RisingScale.shared
    @State private var dragging: Band?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private static let size = CGSize(width: 190, height: 89)   // his shape's own 2.13 : 1

    private static let shape: [(CGFloat, CGFloat)] = [
        (0.0, 0.8623), (0.0, 0.9045), (0.0, 0.9465), (0.0151, 0.9596), (0.0352, 0.9644), (0.0554, 0.9697),
        (0.0756, 0.9745), (0.0957, 0.979), (0.1159, 0.9832), (0.1362, 0.987), (0.1564, 0.9902), (0.1766, 0.9932),
        (0.1969, 0.9955), (0.2172, 0.9975), (0.2375, 0.9989), (0.2578, 0.9997), (0.2781, 1.0), (0.2984, 0.9997),
        (0.3187, 0.9988), (0.3389, 0.9971), (0.3592, 0.9948), (0.3794, 0.9918), (0.3996, 0.988), (0.4198, 0.9833),
        (0.44, 0.9777), (0.46, 0.9712), (0.48, 0.9636), (0.4999, 0.9552), (0.5196, 0.9455), (0.5392, 0.9346),
        (0.5587, 0.9226), (0.5779, 0.9092), (0.5969, 0.8945), (0.6157, 0.8784), (0.6341, 0.8609), (0.6523, 0.842),
        (0.67, 0.8215), (0.6873, 0.7994), (0.7041, 0.7759), (0.7204, 0.7508), (0.7362, 0.7243), (0.7513, 0.6963),
        (0.7659, 0.6671), (0.7799, 0.6366), (0.7933, 0.605), (0.8061, 0.5723), (0.8184, 0.5388), (0.8302, 0.5045),
        (0.8416, 0.4697), (0.8529, 0.4347), (0.8643, 0.3999), (0.8757, 0.3652), (0.8872, 0.3304), (0.8987, 0.2958),
        (0.9104, 0.2613), (0.922, 0.2269), (0.9338, 0.1926), (0.9457, 0.1585), (0.9577, 0.1245), (0.9698, 0.0907),
        (0.9821, 0.0572), (0.9945, 0.0239), (0.9932, 0.0), (0.9729, 0.0), (0.9526, 0.0), (0.9376, 0.022),
        (0.9253, 0.0557), (0.9133, 0.0895), (0.9014, 0.1236), (0.8896, 0.1578), (0.8779, 0.1923), (0.8663, 0.2267),
        (0.8547, 0.2613), (0.8432, 0.2959), (0.8317, 0.3308), (0.8203, 0.3656), (0.8089, 0.4004), (0.7976, 0.4353),
        (0.786, 0.4699), (0.7738, 0.5036), (0.761, 0.5362), (0.7476, 0.5677), (0.7335, 0.5981), (0.7188, 0.6271),
        (0.7035, 0.6547), (0.6876, 0.6809), (0.6711, 0.7055), (0.6541, 0.7285), (0.6367, 0.75), (0.6188, 0.7699),
        (0.6005, 0.7881), (0.5818, 0.8047), (0.5629, 0.8197), (0.5437, 0.8332), (0.5242, 0.8453), (0.5046, 0.8562),
        (0.4849, 0.8657), (0.4649, 0.8741), (0.445, 0.8814), (0.4249, 0.8875), (0.4048, 0.8927), (0.3846, 0.8969),
        (0.3643, 0.9003), (0.344, 0.903), (0.3238, 0.9047), (0.3035, 0.9058), (0.2832, 0.9062), (0.2629, 0.9059),
        (0.2426, 0.9051), (0.2223, 0.9037), (0.202, 0.9017), (0.1818, 0.8993), (0.1615, 0.8964), (0.1413, 0.893),
        (0.1211, 0.8892), (0.1009, 0.885), (0.0807, 0.8804), (0.0605, 0.8756), (0.0404, 0.8703), (0.0203, 0.8655)
    ]
    /// The middle of his shape, 61 points from the Heavy end; band i sits at point i * 10.
    private static let line: [(CGFloat, CGFloat)] = [
        (0.0, 0.9465), (0.0088, 0.9318), (0.0192, 0.9137), (0.0392, 0.9179), (0.0591, 0.9227), (0.0791, 0.9275),
        (0.0991, 0.932), (0.1191, 0.9361), (0.1391, 0.9398), (0.1592, 0.9431), (0.1792, 0.946), (0.1993, 0.9484),
        (0.2194, 0.9503), (0.2395, 0.9517), (0.2596, 0.9526), (0.2797, 0.9528), (0.2998, 0.9526), (0.3199, 0.9516),
        (0.34, 0.95), (0.36, 0.9476), (0.3801, 0.9445), (0.4001, 0.9406), (0.4201, 0.9358), (0.44, 0.9301),
        (0.4599, 0.9235), (0.4796, 0.9159), (0.4993, 0.907), (0.5189, 0.8972), (0.5383, 0.886), (0.5575, 0.8736),
        (0.5765, 0.8598), (0.5953, 0.8446), (0.6138, 0.8279), (0.632, 0.8097), (0.6498, 0.7899), (0.6672, 0.7685),
        (0.6842, 0.7456), (0.7007, 0.721), (0.7166, 0.695), (0.732, 0.6675), (0.7468, 0.6385), (0.761, 0.6082),
        (0.7746, 0.5767), (0.7876, 0.5441), (0.8, 0.5105), (0.8118, 0.476), (0.8234, 0.4409), (0.8348, 0.4058),
        (0.8463, 0.3707), (0.8578, 0.3356), (0.8694, 0.3007), (0.881, 0.2658), (0.8927, 0.231), (0.9045, 0.1964),
        (0.9163, 0.1619), (0.9283, 0.1275), (0.9404, 0.0934), (0.9526, 0.0594), (0.968, 0.0371), (0.9843, 0.0205),
        (1.0, 0.0068)
    ]
    private static func at(_ p: (CGFloat, CGFloat)) -> CGPoint { CGPoint(x: p.0 * size.width, y: p.1 * size.height) }
    private static func band(near p: CGPoint) -> Band {
        let i = line.indices.min { a, b in
            hypot(at(line[a]).x - p.x, at(line[a]).y - p.y) < hypot(at(line[b]).x - p.x, at(line[b]).y - p.y)
        } ?? 30
        return Band(rawValue: Int((Double(i) / 10).rounded())) ?? .stuck
    }

    var body: some View {
        let shown = dragging ?? (rising.asking ? nil : rising.current?.band)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addLines(Self.shape.map(Self.at))
                p.closeSubpath()
            }
            .fill(Color.primary.opacity(0.92))
            .shadow(color: PLTone.accent.opacity(rising.asking ? 0.95 : 0), radius: rising.asking ? (pulse ? 14 : 5) : 0)
            if let shown {
                Circle().fill(PLTone.accent).frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary, lineWidth: 2))
                    .position(Self.at(Self.line[shown.rawValue * 10]))
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

/// The words for where he is, stacked; up only after he answers the curve, and gone on a word or Done.
struct RisingPanel: View {
    @State private var rising = RisingScale.shared
    @State private var heavyDismissed = UserDefaults.standard.string(forKey: "pldev.rising.heavyShown")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rising.showWords, let tap = rising.current {
                HStack {
                    Text("Look: \(tap.band.oneUp.title)").plFont(.subhead, emphasized: true)
                    Spacer()
                    if rising.wearsDaily, RisingScale.lookBand() != nil {
                        Button("Undo") { rising.undoFeeling() }.frame(minWidth: 44, minHeight: 44)
                    }
                    menu
                }
                ForEach(tap.band.words, id: \.self) { w in
                    Button { rising.refine(word: w); rising.showWords = false } label: {
                        Text(w).fontWeight(tap.word == w ? .bold : .regular)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                }
                HStack {
                    Button(tap.tiredBody ? "Tired body: on" : "Tired body") { rising.refine(tiredBody: !tap.tiredBody) }.frame(minHeight: 44)
                    Spacer()
                    Button("Done") { rising.showWords = false }.frame(minWidth: 44, minHeight: 44)
                }
                if tap.band >= .rising {
                    TextField("A note for your low self", text: $rising.note, axis: .vertical).textFieldStyle(.roundedBorder)
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
        .background {
            if rising.showWords { Color.clear.plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous)) }
        }
    }

    private var menu: some View {
        Menu {
            Toggle("Daily look", isOn: Binding(get: { rising.wearsDaily }, set: { on in Task { await rising.setDaily(on) } }))
            Toggle("Look follows my check-in", isOn: Binding(get: { rising.followsFeeling }, set: { rising.followsFeeling = $0 }))
            Toggle("Three reminders", isOn: Binding(get: { rising.reminds }, set: { rising.reminds = $0 }))
            Toggle("Buddy pops up", isOn: Binding(get: { rising.buddyOn }, set: { rising.buddyOn = $0 }))
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Check-in settings")
    }
}

/// His head for Buddy (his drawing, 11-25, the red figure from the left-chest embroidery), used as he drew it; the face is
/// laid on it and the stem's flat foot rests on whatever is under it.
struct BuddyHead: View {
    let model: BuddyModel
    var side: CGFloat = 144
    private static let art = Bundle.main.url(forResource: "buddy-head", withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }

    var body: some View {
        ZStack {
            if let art = Self.art { Image(uiImage: art).resizable().scaledToFit().accessibilityHidden(true) }
            // the big face he ticked (11-25), anchored at his green dot (0.47, 0.36 of the head): face 0.66 of the head wide.
            // pinned = it stays on that spot; every expression and move still plays on it
            BuddyView(model: model, pinned: true)
                .frame(width: side * 0.717, height: side * 0.864)   // BuddyView fits 440 x 530 into 0.92 of this box
                .position(x: side * 0.48, y: side * 0.31)
        }
        .frame(width: side, height: side)
    }
}

/// Buddy slides in from the lower corner of Home, says one line, and leaves after eight seconds. Home only, so he never
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
                    BuddyHead(model: buddy)
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
            // and the face that matches where he is: calm when low, happy in the middle, excited when high
            if let band = rising.current?.band { buddy.playState(band <= .low ? "calm" : band <= .steady ? "happy" : "excited") }
            withAnimation { line = said }
            AccessibilityNotification.Announcement(said).post()
            try? await Task.sleep(for: .seconds(8))
            withAnimation { line = nil }
        }
    }
}
