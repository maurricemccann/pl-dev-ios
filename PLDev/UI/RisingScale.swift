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

    /// 4:15 PM, 12:30 AM, 4:30 AM Pacific. Only the next two are set, then two more after a day's gap: if he ignores two in a
    /// row it goes quiet for a day by itself, and any open or tap sets them afresh.
    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<4).map { "rising-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard reminds, d.bool(forKey: "pldev.notify") else { return }
        let cal = Self.pacific
        var slots: [Date] = []
        for day in 0..<5 {
            guard let base = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: .now)) else { continue }
            for (h, m) in [(0, 30), (4, 30), (16, 15)] {
                if let at = cal.date(bySettingHour: h, minute: m, second: 0, of: base), at > Date().addingTimeInterval(3600) { slots.append(at) }
            }
        }
        guard slots.count > 2 else { return }
        let later = slots.filter { $0 > slots[1].addingTimeInterval(24 * 3600) }
        for (i, at) in (Array(slots.prefix(2)) + Array(later.prefix(2))).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Tap how you feel."
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            center.add(UNNotificationRequest(identifier: ids[i], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
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

/// The check-in on Home: seven taps; after one, its words, the body tag, the note and the switches.
struct RisingBar: View {
    @State private var rising = RisingScale.shared
    @State private var again = false
    @State private var heavyDismissed = UserDefaults.standard.string(forKey: "pldev.rising.heavyShown")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpace.gap) {
            HStack {
                Text(rising.current.map { "Look: \($0.band.oneUp.title)" } ?? "Tap how you feel").plFont(.subhead, emphasized: true)
                Spacer()
                if rising.current != nil, rising.wearsDaily, RisingScale.lookBand() != nil {
                    Button("Undo") { rising.undoFeeling() }.frame(minWidth: 44, minHeight: 44)
                }
                menu
            }
            if let tap = rising.current, !again { after(tap) } else { scale }
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
        .padding(14)
        .plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        .task { await rising.firstWear(); rising.scheduleReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await rising.wearIfDue(); rising.scheduleReminders() } }
        }
        .sensoryFeedback(PLHaptic.select, trigger: rising.log.count)
    }

    private var scale: some View {
        HStack(spacing: 2) {
            ForEach(Band.allCases, id: \.self) { band in
                Button {
                    again = false
                    rising.tap(band)
                } label: {
                    VStack(spacing: 4) {
                        Circle().fill(Color(hue: Double(band.rawValue) / 7 * 0.45 + 0.62, saturation: 0.55, brightness: 0.9))
                            .frame(width: 22, height: 22)
                        Text(band.title).font(Font.pl(.caption2)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("I feel \(band.title)")
            }
        }
    }

    private func after(_ tap: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: PLSpace.gap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(tap.band.words, id: \.self) { w in
                        Button(w) { rising.refine(word: w) }
                            .fontWeight(tap.word == w ? .bold : .regular).frame(minHeight: 44)
                    }
                }
            }
            HStack {
                Button(tap.tiredBody ? "Tired body: on" : "Tired body") { rising.refine(tiredBody: !tap.tiredBody) }.frame(minHeight: 44)
                Spacer()
                Button("Change") { again = true }.frame(minHeight: 44)
            }
            if tap.band >= .rising {
                TextField("A note for your low self", text: $rising.note, axis: .vertical).textFieldStyle(.roundedBorder)
            }
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
                    BuddyView(model: buddy).frame(width: 72, height: 72)
                }
                .padding(.horizontal, PLSpace.margin).padding(.bottom, PLSpace.gap)
                .transition(reduce ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .onTapGesture { withAnimation { self.line = nil } }
                .contextMenu {
                    Button("Quiet for 2 hours") { rising.snooze(hours: 2); self.line = nil }
                    Button("Quiet until tomorrow") { rising.snooze(hours: 18); self.line = nil }
                }
                .accessibilityHint("Tap to send Buddy away")
            }
        }
        .task(id: rising.current?.at) {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let said = rising.buddyLine() else { return }
            buddy.react(.open)
            withAnimation { line = said }
            AccessibilityNotification.Announcement(said).post()
            try? await Task.sleep(for: .seconds(8))
            withAnimation { line = nil }
        }
    }
}
