import Foundation

/// The Companion's clock and growth rules, ported line for line from the R1 app (`pl-r1-pet/.../PetRules.java`, his ruled design).
/// Never re-derived: when a rule changes, it changes there first. No consecutive-day counter anywhere (his ruling).
enum CompanionRules {
    static let dayMs: Double = 86_400_000

    static func animationFps(_ saved: Int) -> Int { saved == 8 ? 8 : 12 }
    static func spriteFrame(elapsedMs: Double, fps: Int, frames: Int) -> Int {
        frames <= 0 ? 0 : Int(max(0, elapsedMs) * Double(animationFps(fps)) / 1000) % frames
    }
    static func spriteDurationMs(fps: Int, frames: Int) -> Double {
        let f = animationFps(fps); return Double((frames * 1000 + f - 1) / f)
    }

    /// The baby's gestures in the order babies learn them (his link, S346, FIRST WORDS Project), then Mesh2Motion's CC0 moves.
    static let babyGestures = ["reach", "shake", "raise", "show", "wave", "point", "clap", "kiss", "shh", "nod", "dunno", "victory",
        "laugh", "bow", "dance", "tumble", "jump", "excited", "stomp", "spin", "dizzy", "yawn", "stretch", "scared", "twist", "chicken", "dab", "moonwalk", "charleston", "jacks"]
    private static let joyful: Set<String> = ["clap", "kiss", "victory", "wave", "thumbs", "nod", "laugh", "dance", "jump", "excited", "spin", "twist", "chicken", "bow", "dab", "moonwalk", "charleston", "jacks"]
    /// Two gestures from the start, the rest learned across the baby stage: all of them by the 20th active day.
    static func gesturesKnown(_ activeDays: Int) -> Int {
        max(2, min(babyGestures.count, 2 + activeDays * (babyGestures.count - 2) / 20))
    }
    /// A learned gesture for this moment: a joyful one for a gratitude, Held or came-true when it knows any, else any it knows.
    static func babyGesture(activeDays: Int, event: String, roll: Double) -> String {
        if event == "real" { return "baby-cheer" }
        let n = gesturesKnown(activeDays)
        let joy = ["gratitude", "real", "held", "fed"].contains(event)
        var pick = babyGestures.prefix(n).filter { !joy || joyful.contains($0) }
        if pick.isEmpty { pick = Array(babyGestures.prefix(n)) }
        return "baby-" + pick[min(pick.count - 1, Int(roll * Double(pick.count)))]
    }
    static func acknowledgement(stage: String, event: String) -> String {
        if stage == "baby" { return event == "real" ? "baby-cheer" : "baby-clap" }
        let joy = event == "gratitude" || event == "real"
        if stage == "teen" { return joy ? "teen-cheer" : "teen-headtilt" }
        return joy ? "adult-cheer" : "adult-thumbs"
    }

    /// Minutes after local midnight.
    static func minutes(_ date: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    /// The practice day turns at wake, not midnight: before wake it is still yesterday.
    static func day(_ date: Date, wake: Int, cal: Calendar = .current) -> String {
        var d = date
        if minutes(date, cal) < wake { d = cal.date(byAdding: .day, value: -1, to: date) ?? date }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func asleep(_ date: Date, sleep: Int, wake: Int, cal: Calendar = .current) -> Bool {
        let m = minutes(date, cal)
        return sleep < wake ? (m >= sleep && m < wake) : (m >= sleep || m < wake)
    }
    /// A meter 0 to 4: full the day of the act, one step less each 24 h after it.
    static func meter(nowMs: Double, lastMs: Double) -> Int {
        lastMs <= 0 ? 0 : max(0, 4 - Int(max(0, nowMs - lastMs) / dayMs))
    }
    /// A desire not held for 3 days dims (1), for 14 days goes quiet (2); a Held OR any later gratitude wakes it (0).
    static func desireLevel(nowMs: Double, lastHeldOrCreated: Double, lastGratitude: Double) -> Int {
        let since = nowMs - max(lastHeldOrCreated, lastGratitude)
        return since >= 14 * dayMs ? 2 : since >= 3 * dayMs ? 1 : 0
    }
    /// A new colour every 6 active days until adult (66); after that it keeps the last one.
    static func colourIndex(days: Int, colours: Int) -> Int { max(0, min(colours - 1, min(days, 65) / 6)) }
    /// Return after absence: under 3 days full light, 3 days dim, 14 days or more the quiet resting scene at 30 %.
    static func absenceLight(nowMs: Double, lastActive: Double) -> Double {
        let since = nowMs - lastActive
        return since >= 14 * dayMs ? 0.3 : since >= 3 * dayMs ? 0.6 : 1
    }
    static func resting(nowMs: Double, lastActive: Double) -> Bool { nowMs - lastActive >= 14 * dayMs }
    /// The resting scene breathes on an 8-second cycle, a little either side of its level.
    static func breath(_ level: Double, ms: Double) -> Double {
        level * (0.8 + 0.2 * sin(2 * .pi * ms.truncatingRemainder(dividingBy: 8000) / 8000))
    }
    /// One gratitude brings the light from where it was up to 100 % over 3 seconds.
    static func wake(from: Double, sinceMs: Double) -> Double { from + (1 - from) * max(0, min(1, sinceMs / 3000)) }
    /// "HH:MM" (24 hour) to minutes after midnight, or -1 when it is not a time.
    static func parseTime(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.range(of: "^([01]?[0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else { return -1 }
        let p = t.split(separator: ":"); return Int(p[0])! * 60 + Int(p[1])!
    }
    static func stage(_ days: Int) -> String { days >= 66 ? "adult" : days >= 21 ? "teen" : "baby" }
    static func nextStage(_ current: String, days: Int) -> String {
        if current == "baby" && stage(days) != "baby" { return "teen" }
        if current == "teen" && stage(days) == "adult" { return "adult" }
        return current
    }
    /// Credits a practice day once; non-consecutive days count, nothing resets.
    static func creditDay(_ days: inout [String], _ day: String) -> Bool {
        if days.contains(day) { return false }
        days.append(day); return true
    }
    static func nudge(enabled: Bool, asleep: Bool, fed: Bool, day: String, lastNudge: String) -> Bool {
        enabled && !asleep && !fed && day != lastNudge
    }

    /// The wardrobe: items unlock by active days (the same clock as the stages), never bought. (id, label, unlock day)
    struct Wear: Identifiable, Sendable { let id: String; let label: String; let day: Int }
    static let wardrobe: [Wear] = [
        Wear(id: "binky", label: "Binky", day: 0), Wear(id: "crayon", label: "Crayon", day: 7), Wear(id: "bottle", label: "Water bottle", day: 21), Wear(id: "laptop", label: "Laptop", day: 25), Wear(id: "notebook", label: "Notebook", day: 30),
        Wear(id: "book", label: "Book", day: 35), Wear(id: "cart", label: "Shopping cart", day: 40), Wear(id: "brush", label: "Paintbrush", day: 45), Wear(id: "tapegun", label: "Tape gun", day: 50), Wear(id: "mic", label: "Microphone", day: 55),
        Wear(id: "cup", label: "Coffee", day: 66), Wear(id: "vest", label: "Safety vest", day: 68), Wear(id: "scanner", label: "Hand scanner", day: 70)]

    /// Assert-style self-check of the rules that carry his design (run from the Status probes). Returns the failed checks, empty when all pass.
    static func selfCheck() -> [String] {
        var bad: [String] = []
        func expect(_ ok: Bool, _ what: String) { if !ok { bad.append(what) } }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date { cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))! }
        expect(day(at(2026, 11, 19, 14, 59), wake: 900, cal: cal) == "2026-11-18", "before wake is still yesterday")
        expect(day(at(2026, 11, 19, 15, 0), wake: 900, cal: cal) == "2026-11-19", "the day turns at wake")
        expect(day(at(2026, 11, 20, 5, 0), wake: 900, cal: cal) == "2026-11-19", "the small hours belong to the night before")
        expect(asleep(at(2026, 11, 19, 7, 0), sleep: 360, wake: 900, cal: cal), "rest runs 06:00 to 15:00")
        expect(!asleep(at(2026, 11, 19, 15, 0), sleep: 360, wake: 900, cal: cal), "awake from 15:00")
        expect(asleep(at(2026, 11, 19, 23, 30), sleep: 1380, wake: 420, cal: cal) && !asleep(at(2026, 11, 19, 12, 0), sleep: 1380, wake: 420, cal: cal), "a night across midnight")
        let now = 1_000 * dayMs
        expect(meter(nowMs: now, lastMs: now) == 4 && meter(nowMs: now, lastMs: now - dayMs) == 3 && meter(nowMs: now, lastMs: now - 4 * dayMs) == 0 && meter(nowMs: now, lastMs: 0) == 0, "meters 4 to 0, minus 1 per 24 h")
        expect(stage(20) == "baby" && stage(21) == "teen" && stage(65) == "teen" && stage(66) == "adult", "baby to teen at 21, teen to adult at 66")
        expect(nextStage("baby", days: 70) == "teen" && nextStage("teen", days: 70) == "adult", "a stage steps once at a time")
        var ds: [String] = []
        expect(creditDay(&ds, "a") && !creditDay(&ds, "a") && creditDay(&ds, "c") && ds.count == 2, "a day credits once; days need not be consecutive")
        expect(desireLevel(nowMs: now, lastHeldOrCreated: now - 15 * dayMs, lastGratitude: now - dayMs) == 0, "a gratitude wakes a dimmed desire")
        expect(desireLevel(nowMs: now, lastHeldOrCreated: now - 4 * dayMs, lastGratitude: 0) == 1 && desireLevel(nowMs: now, lastHeldOrCreated: now - 14 * dayMs, lastGratitude: 0) == 2, "dim at 3 days, quiet at 14")
        expect(parseTime("15:00") == 900 && parseTime("6:00") == 360 && parseTime("24:00") == -1 && parseTime("x") == -1, "times parse")
        expect(gesturesKnown(0) == 2 && gesturesKnown(20) == babyGestures.count, "gestures learned by day 20")
        expect(colourIndex(days: 0, colours: 11) == 0 && colourIndex(days: 70, colours: 11) == 10, "colour steps every 6 days, held after 66")
        expect(spriteFrame(elapsedMs: 3000, fps: 12, frames: 36) == 0 && spriteFrame(elapsedMs: 1000, fps: 12, frames: 36) == 12, "strips play at 12 fps")
        return bad
    }
}
