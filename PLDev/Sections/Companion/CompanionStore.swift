import Foundation
import Observation
import UserNotifications

/// One gratitude line, kept forever.
struct CompanionGratitude: Codable, Equatable, Identifiable {
    var text: String
    var time: Double
    var day: String
    var palette: String
    var credited: Bool
    var id: Double { time }
}

/// One desire: active, real (came true) or archived. Nothing is ever deleted.
struct CompanionDesire: Codable, Equatable {
    var name: String
    var created: Double
    var status: String = "active"
    var heldDay: String?
    var lastHeld: Double?
    var realised: Double?
}

/// The whole pet, one JSON file (port of `pl-r1-pet/.../PetStore.java`, its own state on the phone, no network, no sync).
struct CompanionRecord: Codable, Equatable {
    var v = 3
    var who = "him"                 // him | her
    var born: Double = 0
    var stage = "baby"
    var days: [String] = []         // credited practice days, never a streak
    var order: [String] = []        // colourway order, shuffled at birth
    var gratitudes: [CompanionGratitude] = []
    var desires: [CompanionDesire] = []
    var lastGratitude: Double = 0
    var lastHeld: Double = 0
    var wake = 900                  // 15:00, minutes after midnight
    var sleep = 360                 // 06:00
    var nudge = true
    var nudgeTime = 1260            // 21:00
    var lastNudge = ""
    var animationFps = 12
    var off: [String] = []          // wardrobe items he switched off

    init() {}
    /// Every field optional on read: a record saved by an older build (fewer fields) still opens; only a broken file is unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CompanionRecord()
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? d.v
        who = try c.decodeIfPresent(String.self, forKey: .who) ?? d.who
        born = try c.decodeIfPresent(Double.self, forKey: .born) ?? d.born
        stage = try c.decodeIfPresent(String.self, forKey: .stage) ?? d.stage
        days = try c.decodeIfPresent([String].self, forKey: .days) ?? d.days
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? d.order
        gratitudes = try c.decodeIfPresent([CompanionGratitude].self, forKey: .gratitudes) ?? d.gratitudes
        desires = try c.decodeIfPresent([CompanionDesire].self, forKey: .desires) ?? d.desires
        lastGratitude = try c.decodeIfPresent(Double.self, forKey: .lastGratitude) ?? d.lastGratitude
        lastHeld = try c.decodeIfPresent(Double.self, forKey: .lastHeld) ?? d.lastHeld
        wake = try c.decodeIfPresent(Int.self, forKey: .wake) ?? d.wake
        sleep = try c.decodeIfPresent(Int.self, forKey: .sleep) ?? d.sleep
        nudge = try c.decodeIfPresent(Bool.self, forKey: .nudge) ?? d.nudge
        nudgeTime = try c.decodeIfPresent(Int.self, forKey: .nudgeTime) ?? d.nudgeTime
        lastNudge = try c.decodeIfPresent(String.self, forKey: .lastNudge) ?? d.lastNudge
        animationFps = try c.decodeIfPresent(Int.self, forKey: .animationFps) ?? d.animationFps
        off = try c.decodeIfPresent([String].self, forKey: .off) ?? d.off
    }
}

/// One transactional file: a change is applied to a copy, written atomically, and only then becomes the pet. A failed write never advances it.
@MainActor @Observable final class CompanionStore {
    static let shared = CompanionStore()
    private(set) var record: CompanionRecord?
    var error = ""
    private(set) var unreadable = false
    /// The last act and when it happened: the scene plays its clip for it.
    private(set) var event = ""
    private(set) var eventAt = Date.distantPast
    private let url: URL

    init(url: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? dir.appendingPathComponent("companion.json")
        if let data = try? Data(contentsOf: self.url) {
            if let r = try? JSONDecoder().decode(CompanionRecord.self, from: data) { record = r }
            else { unreadable = true; error = "The saved pet could not be read. Nothing was changed; reset is in Settings." }
        }
    }

    private func change(_ apply: (inout CompanionRecord) throws -> Void) -> Bool {
        guard !unreadable, var next = record else { return false }
        do {
            try apply(&next)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            record = next; error = ""; return true
        } catch {
            self.error = "The pet was not saved. Try again."; return false
        }
    }

    private func mark(_ e: String) { event = e; eventAt = Date() }
    static func nowMs(_ d: Date = Date()) -> Double { d.timeIntervalSince1970 * 1000 }

    func born(who: String, colours: [String]) -> Bool {
        guard !unreadable, record == nil else { return false }
        var r = CompanionRecord(); r.who = who; r.born = Self.nowMs(); r.order = colours.shuffled()
        record = r
        if change({ _ in }) { scheduleNudge(); return true }
        record = nil; return false
    }

    func day(_ d: Date = Date()) -> String { CompanionRules.day(d, wake: record?.wake ?? 900) }
    func asleep(_ d: Date = Date()) -> Bool { CompanionRules.asleep(d, sleep: record?.sleep ?? 360, wake: record?.wake ?? 900) }
    var activeDays: Int { record?.days.count ?? 0 }
    /// Today's practice is fed: a gratitude was kept this practice day.
    func fed(_ d: Date = Date()) -> Bool {
        let today = day(d); return record?.gratitudes.contains { $0.day == today } ?? false
    }
    /// The last real act (a gratitude or a Held), else birth: what the absence light reads.
    var lastActive: Double { guard let r = record else { return 0 }; return max(r.born, max(r.lastGratitude, r.lastHeld)) }

    /// Keeps a gratitude (1 to 240 characters). The first one of a practice day credits the day; later ones are kept and credit nothing.
    @discardableResult func gratitude(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 240 else { error = text.isEmpty ? "" : "Keep it to 240 characters."; return false }
        let now = Date(), ms = Self.nowMs(now), today = day(now)
        let ok = change { s in
            let palette = s.order.isEmpty ? "bone-blue" : s.order[CompanionRules.colourIndex(days: s.days.count, colours: s.order.count)]
            let credited = CompanionRules.creditDay(&s.days, today)
            s.gratitudes.append(CompanionGratitude(text: text, time: ms, day: today, palette: palette, credited: credited))
            s.lastGratitude = ms
            s.stage = CompanionRules.nextStage(s.stage, days: s.days.count)
        }
        if ok { mark("gratitude"); scheduleNudge() }
        return ok
    }

    var activeDesires: Int { record?.desires.filter { $0.status == "active" }.count ?? 0 }

    /// Adds a desire (1 to 80 characters), at most 12 active.
    @discardableResult func desire(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n.count <= 80 else { return false }
        guard activeDesires < 12 else { error = "Twelve desires are already held. Archive one first."; return false }
        return change { $0.desires.append(CompanionDesire(name: n, created: Self.nowMs())) }
    }

    /// Held, once a practice day: lights Pull and credits the day. Holding again the same day replays the acknowledgement and changes no number.
    @discardableResult func held(_ i: Int) -> Bool {
        guard let r = record, r.desires.indices.contains(i), r.desires[i].status == "active" else { return false }
        let now = Date(), ms = Self.nowMs(now), today = day(now)
        if r.desires[i].heldDay == today { mark("held"); return true }
        let ok = change { s in
            s.desires[i].heldDay = today; s.desires[i].lastHeld = ms; s.lastHeld = ms
            _ = CompanionRules.creditDay(&s.days, today)
            s.stage = CompanionRules.nextStage(s.stage, days: s.days.count)
        }
        if ok { mark("held") }
        return ok
    }

    /// Came true, or its undo.
    @discardableResult func real(_ i: Int, _ isReal: Bool) -> Bool {
        guard let r = record, r.desires.indices.contains(i) else { return false }
        if !isReal && activeDesires >= 12 { error = "Twelve desires are already held. Archive one first."; return false }
        let ok = change { s in s.desires[i].status = isReal ? "real" : "active"; s.desires[i].realised = isReal ? Self.nowMs() : nil }
        if ok && isReal { mark("real") }
        return ok
    }

    @discardableResult func archive(_ i: Int) -> Bool {
        guard let r = record, r.desires.indices.contains(i) else { return false }
        return change { $0.desires[i].status = "archived" }
    }

    /// A desire's light: 0 lit, 1 dim, 2 quiet. A Held or any later gratitude wakes it.
    func desireLevel(_ d: CompanionDesire, now: Double = CompanionStore.nowMs()) -> Int {
        CompanionRules.desireLevel(nowMs: now, lastHeldOrCreated: d.lastHeld ?? d.created, lastGratitude: record?.lastGratitude ?? 0)
    }

    // MARK: C3, time and growth

    /// The test hook (his C3 check): shows the scene at another day count without touching the record. Not saved.
    var previewDays: Int?
    /// Lights out: a tap on the scene; the pet lies down at 15 % light. Not saved, like the R1's.
    var lightsOut = false
    var shownDays: Int { previewDays ?? activeDays }
    var shownStage: String { previewDays.map(CompanionRules.stage) ?? record?.stage ?? "baby" }
    /// Unlocked wardrobe items he has not switched off, in draw order.
    var worn: [String] { CompanionRules.wardrobe.filter { shownDays >= $0.day && !(record?.off.contains($0.id) ?? false) }.map { $0.id } }

    @discardableResult func setWho(_ w: String) -> Bool { change { $0.who = w } }
    @discardableResult func setTimes(wake: Int? = nil, sleep: Int? = nil, nudgeTime: Int? = nil, nudge: Bool? = nil) -> Bool {
        let ok = change { s in
            if let wake { s.wake = wake }; if let sleep { s.sleep = sleep }
            if let nudgeTime { s.nudgeTime = nudgeTime }; if let nudge { s.nudge = nudge }
        }
        if ok { scheduleNudge() }
        return ok
    }
    @discardableResult func setWorn(_ id: String, _ on: Bool) -> Bool {
        change { s in s.off.removeAll { $0 == id }; if !on { s.off.append(id) } }
    }

    /// The one soft nudge a day: a local notification at his time, only on a practice day not yet fed and never during rest.
    /// Rescheduled on open, on each gratitude and on each settings change, so it never stacks and never fires after a gratitude.
    func scheduleNudge() {
        let center = UNUserNotificationCenter.current(), id = "companion.nudge"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let r = record, r.nudge else { return }
        let cal = Calendar.current, now = Date()
        for ahead in 0...2 {
            guard let base = cal.date(byAdding: .day, value: ahead, to: cal.startOfDay(for: now)),
                  let at = cal.date(byAdding: .minute, value: r.nudgeTime, to: base), at > now else { continue }
            if asleep(at) { return }   // his time sits inside rest: no nudge (the R1 rule)
            if day(at) == day(now) && fed(now) { continue }
            let c = UNMutableNotificationContent(); c.title = "Companion"; c.body = "A moment for one gratitude."; c.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            return
        }
    }

    /// The only delete: his own reset from Settings, which removes the file and starts over.
    @discardableResult func reset() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            record = nil; unreadable = false; error = ""; return true
        } catch { self.error = "The pet was not reset. Try again."; return false }
    }

    /// Store self-check on a scratch file: a gratitude credits once, a kill and reopen keeps everything, an over-long line is refused.
    static func selfCheck() -> [String] {
        var bad: [String] = []
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("companion-check-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let s = CompanionStore(url: tmp)
        if !s.born(who: "him", colours: ["bone-blue"]) { bad.append("birth did not save") }
        s.gratitude("first"); s.gratitude("second")
        if s.record?.gratitudes.count != 2 || s.record?.days.count != 1 || s.record?.gratitudes.first?.credited != true || s.record?.gratitudes.last?.credited != false { bad.append("a gratitude credits today once") }
        if s.gratitude(String(repeating: "x", count: 241)) { bad.append("241 characters were accepted") }
        s.desire("a quiet studio"); s.held(0); s.held(0)
        if s.record?.lastHeld == 0 || s.record?.days.count != 1 { bad.append("Held lights Pull without a second day") }
        let reopened = CompanionStore(url: tmp)
        if reopened.record != s.record { bad.append("the record did not survive a reopen") }
        // a record saved by the first build (no `off` field) must still open
        let old = Data(#"{"v":3,"who":"her","born":1,"stage":"baby","days":["2026-11-19"],"order":[],"gratitudes":[],"desires":[],"lastGratitude":0,"lastHeld":0,"wake":900,"sleep":360,"nudge":true,"nudgeTime":1260,"lastNudge":"","animationFps":12}"#.utf8)
        if (try? JSONDecoder().decode(CompanionRecord.self, from: old))?.who != "her" { bad.append("an older record would not open") }
        if CompanionRules.wardrobe.filter({ 21 >= $0.day }).map({ $0.id }) != ["binky", "crayon", "bottle"] { bad.append("wardrobe unlocks by day") }
        return bad
    }
}
