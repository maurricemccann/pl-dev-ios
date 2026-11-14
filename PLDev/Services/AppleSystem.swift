import AppIntents
import CoreHaptics
import EventKit
import Foundation
import HealthKit
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// The apple lane (11-13): the iPhone's own frameworks, each behind its own switch in Settings, none of them holding a key.
// Free-account check (Apple's "Supported capabilities (iOS)", 11-13): App Groups, Siri/App Intents, Background modes and HealthKit are
// capabilities a Personal Team can carry (the lead's word for HealthKit); Push, Time Sensitive Notifications and iCloud are not, and are not used.
// EventKit, Vision, Core Haptics, Foundation Models, Translation and Focus filters need no entitlement at all.

// MARK: - Apple Intelligence (Foundation Models): drafts only, on this phone, never posted as finished

@MainActor enum PLIntelligence {
    static var on: Bool { UserDefaults.standard.object(forKey: "pldev.intel") as? Bool ?? true }

    /// One plain sentence: ready, or why this phone cannot.
    static var statusLine: String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return "Apple Intelligence is ready on this iPhone."
        case .unavailable(let why):
            switch why {
            case .deviceNotEligible: return "This iPhone does not support Apple Intelligence. Answers fall back to the saved record."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is off. Turn it on in the iPhone\u{2019}s Settings to draft offline."
            case .modelNotReady: return "Apple Intelligence is still getting ready. Try again later."
            @unknown default: return "Apple Intelligence is not available right now."
            }
        @unknown default: return "Apple Intelligence is not available right now."
        }
        #else
        return "Apple Intelligence is not in this build."
        #endif
    }

    static var isReady: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return on }
        #endif
        return false
    }

    private static func ask(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        guard isReady else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        guard let reply = try? await session.respond(to: prompt) else { return nil }
        let text = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }

    /// GlyphBot offline: an answer written only from what the phone already holds (past Oracle answers and their passages).
    /// Nil when the phone has no Apple Intelligence or holds nothing relevant, so the caller keeps its own fallback.
    static func glyphAnswer(question: String, turns: [GlyphTurn]) async -> String? {
        let words = Set(question.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        guard !words.isEmpty else { return nil }
        let related = turns.filter { t in
            guard !t.answer.isEmpty, !t.via.hasPrefix("on-device"), !t.via.hasPrefix("doctrine") else { return false }   // grounded in real answers only, never in its own drafts
            let hay = (t.question + " " + t.answer).lowercased()
            return words.contains { hay.contains($0) }
        }.prefix(4)
        guard !related.isEmpty else { return nil }
        let record = related.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        let rules = "You are GlyphBot, the voice of Psyched Luxuries. Answer only from the record below. If it does not hold the answer, say plainly that you do not know yet. Declarative, spare, weighted. Never use the words excited, amazing, unique, limited, exclusive or manifest. Never ask a question back."
        return await ask(instructions: rules, prompt: "The record:\n\n\(record)\n\nThe question: \(question)")
    }

    private static let banned = ["excited", "honored", "blessed", "check out", "amazing", "unique", "limited", "exclusive", "manifest"]

    /// A first draft of a caption from a seed (a title, a line, an existing caption). The house voice is in the instructions and
    /// checked after: a draft that breaks it is thrown away, not shown.
    static func captionDraft(seed: String, platform: String?) async -> String? {
        let rules = "You write captions for Psyched Luxuries, a philosophy-first wearable art brand. Voice: declarative, earned certainty, spare and weighted, catalogue prose. Never use: excited, honored, blessed, check out, amazing, unique, limited, exclusive, manifest. Never ask a question. No hashtags, no emoji. Two short sentences at most."
        guard let text = await ask(instructions: rules, prompt: "Write one caption" + (platform.map { " for \($0)" } ?? "") + " about:\n\(seed)") else { return nil }
        let lower = text.lowercased()
        if banned.contains(where: { lower.contains($0) }) || text.hasSuffix("?") { return nil }
        return text
    }
}

// MARK: - Vision: the words in a photo

enum PLVision {
    /// Recognised text in a JPEG or PNG, one line per line of print. Empty when there is none or the picture cannot be read.
    static func text(in image: Data) async -> String {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(data: image, options: [:])
            guard (try? handler.perform([request])) != nil else { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}

// MARK: - HealthKit: mindful minutes from a practice session

@MainActor enum PLHealth {
    static var on: Bool { UserDefaults.standard.bool(forKey: "pldev.health.mindful") }
    private static let store = HKHealthStore()
    private static var type: HKCategoryType { HKCategoryType(.mindfulSession) }

    /// What iOS itself says when the build has no HealthKit entitlement. Shown to him as it is, never softened (his note 11-14).
    static let missingEntitlement = "Missing com.apple.developer.healthkit entitlement."

    /// The exact result of the last write (or the last refusal), kept where Settings reads it: one line, whether it worked, and when.
    static let lastKey = "pldev.health.last", lastOKKey = "pldev.health.lastOK"
    private static func record(_ line: String, ok: Bool) {
        UserDefaults.standard.set(line, forKey: lastKey); UserDefaults.standard.set(ok, forKey: lastOKKey)
    }

    /// Whether THIS build carries the HealthKit entitlement, read from the provisioning profile embedded in the app (the profile is what
    /// iOS checks). SideStore signs with its own free-account profile, and AltSign hands a free account only the entitlements on
    /// its short list (app groups, keychain groups, inter-app audio, memory limit): HealthKit is not on it, so the profile has none and
    /// iOS refuses Health. nil = no embedded profile to read (the simulator, a store build): try it and let iOS answer.
    static func hasEntitlement() -> Bool? {
        #if targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: "simNoHealthKit") { return false }   // the screenshots workflow acts out a free-account build
        #endif
        return entitlementRead
    }
    private static let entitlementRead: Bool? = {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path),
              let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8)), start.lowerBound < end.upperBound,
              let dict = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
              let ents = dict["Entitlements"] as? [String: Any] else { return nil }
        return ents["com.apple.developer.healthkit"] != nil
    }()

    /// Asks Health for permission to write mindful minutes. Nil when granted, else one plain sentence (also kept as the last result).
    static func enable() async -> String? {
        let problem = await authorize()
        if let problem { record("Not on. " + problem, ok: false) }
        else { record("Allowed. Practice sessions now write mindful minutes to Health.", ok: true) }
        return problem
    }

    /// The permission step both the switch and the test use. Never calls HealthKit when the build has no entitlement: HealthKit answers
    /// that with an Objective-C exception, which Swift cannot catch and which would close the app.
    private static func authorize() async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return "Health is not available on this device." }
        if hasEntitlement() == false { return missingEntitlement }
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
        } catch {
            return "Health did not allow it: \(error.localizedDescription)"
        }
        switch store.authorizationStatus(for: type) {
        case .sharingAuthorized: return nil
        case .sharingDenied: return "Mindful Minutes is switched off for PL DEV in Health. Open Health, Sharing, Apps, PL DEV and allow it."
        default: return "Health has not been asked yet. Try the switch again."
        }
    }

    /// Writes one mindful session and records exactly what happened. Does nothing when the switch is off (a test passes `force`).
    @discardableResult
    static func logMindful(start: Date, end: Date, force: Bool = false) async -> String? {
        guard on || force else { return nil }
        guard end > start else { return nil }
        if let problem = await authorize() { let line = "Not written. " + problem; record(line, ok: false); return line }
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue, start: start, end: end)
        do {
            try await store.save(sample)
            let secs = Int(end.timeIntervalSince(start).rounded())
            let len = secs >= 90 ? "\(Int((Double(secs) / 60).rounded())) min" : "\(secs) s"
            let line = "Written \(len) at \(end.formatted(date: .omitted, time: .shortened))."
            record(line, ok: true); return line
        } catch {
            let line = "Not written. \(error.localizedDescription)"
            record(line, ok: false); return line
        }
    }

    /// The test button: one minute ending now, written whether or not the switch is on, with the real result.
    static func writeTest() async -> String {
        let end = Date.now
        return await logMindful(start: end.addingTimeInterval(-60), end: end, force: true) ?? "Nothing was written."
    }
}

// MARK: - EventKit: his shift days and drop dates, on request

@MainActor enum PLCalendar {
    private static let addedKey = "pldev.cal.added"
    private static var added: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: addedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: addedKey) }
    }

    private static func access(_ store: EKEventStore) async -> Bool {
        (try? await store.requestWriteOnlyAccessToEvents()) ?? false
    }

    /// The graveyard shift: 3 PM to 6 AM, for each working day coming up in the schedule.
    static func addShifts(model: AppModel) async -> String {
        let store = EKEventStore()
        guard await access(store) else { return "Calendar access was not given. Allow it in the iPhone\u{2019}s Settings." }
        guard let schedule = try? await Console.get("api/schedule", HouseModel.Schedule.self, model: model, query: ["days": "30"]) else {
            return "The schedule did not load. Try again."
        }
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        let parse = DateFormatter(); parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM-dd"
        var made = 0, known = added
        for day in schedule.days ?? [] where day.work == true {
            let key = "shift:" + day.date
            guard !known.contains(key), let d = parse.date(from: day.date), d >= today,
                  let start = cal.date(bySettingHour: 15, minute: 0, second: 0, of: d),
                  let end = cal.date(byAdding: .hour, value: 15, to: start) else { continue }
            let ev = EKEvent(eventStore: store)
            ev.title = "Shift"; ev.startDate = start; ev.endDate = end; ev.notes = "Added by PL DEV."
            ev.calendar = store.defaultCalendarForNewEvents
            do { try store.save(ev, span: .thisEvent, commit: false); made += 1; known.insert(key) } catch { continue }
        }
        do { try store.commit() } catch { return "Calendar did not save: \(error.localizedDescription)" }
        added = known
        return made == 0 ? "Your shift days are already in the calendar." : "Added \(made) shift \(made == 1 ? "day" : "days")."
    }

    private struct Chosen: Decodable { let chosen_no: Int?; let product: String?; let created_at: String? }

    /// Every drop chosen from the tally in the last month or since: an all-day event on its day.
    static func addDrops(model: AppModel) async -> String {
        let store = EKEventStore()
        guard await access(store) else { return "Calendar access was not given. Allow it in the iPhone\u{2019}s Settings." }
        guard let rows = try? await Console.q("chosen", [Chosen].self, model: model) else { return "The drops did not load. Try again." }
        let cal = Calendar.current, floor = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        var made = 0, known = added
        for r in rows {
            guard let when = Date.pl(r.created_at), when >= floor else { continue }
            let key = "drop:\(r.chosen_no ?? 0):\(r.product ?? "")"
            guard !known.contains(key) else { continue }
            let ev = EKEvent(eventStore: store)
            ev.title = "Drop: " + (r.product ?? "a piece"); ev.isAllDay = true
            ev.startDate = cal.startOfDay(for: when); ev.endDate = cal.startOfDay(for: when)
            ev.calendar = store.defaultCalendarForNewEvents
            do { try store.save(ev, span: .thisEvent, commit: false); made += 1; known.insert(key) } catch { continue }
        }
        do { try store.commit() } catch { return "Calendar did not save: \(error.localizedDescription)" }
        added = known
        return made == 0 ? "No new drop dates to add." : "Added \(made) drop \(made == 1 ? "date" : "dates")."
    }
}

// MARK: - Core Haptics: keep, cut and crown each have their own feel

@MainActor enum PLHaptics {
    static var on: Bool { UserDefaults.standard.object(forKey: "pldev.haptics") as? Bool ?? true }
    private static var engine: CHHapticEngine?

    private static func ready() -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if engine == nil { engine = try? CHHapticEngine(); engine?.isAutoShutdownEnabled = true }
        try? engine?.start()
        return engine
    }

    private static func tick(_ t: TimeInterval, _ intensity: Float, _ sharp: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                                               CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)], relativeTime: t)
    }

    private static func play(_ events: [CHHapticEvent], fallback: UINotificationFeedbackGenerator.FeedbackType) {
        guard on else { return }
        if let engine = ready(), let pattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: pattern), (try? player.start(atTime: 0)) != nil { return }
        UINotificationFeedbackGenerator().notificationOccurred(fallback)   // no Taptic Engine pattern: the plain system tap
    }

    /// A keep: one round, full thump, then a soft settle.
    static func keep() { play([tick(0, 0.9, 0.35), tick(0.09, 0.4, 0.2)], fallback: .success) }
    /// A cut: two dry clicks, close together.
    static func cut() { play([tick(0, 0.7, 0.9), tick(0.06, 0.7, 0.9)], fallback: .warning) }
    /// A crown (a favourite): a rising run of taps, then a long soft swell.
    static func crown() {
        var events = [tick(0, 0.4, 0.5), tick(0.07, 0.6, 0.5), tick(0.14, 0.8, 0.5), tick(0.21, 1.0, 0.6)]
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                                                                              CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)], relativeTime: 0.3, duration: 0.35))
        play(events, fallback: .success)
    }
}

// MARK: - Focus filter: a Focus can pause the house's notices

/// Added in Settings > Focus > Focus Filters. While the Focus is on, notices are held (or only the PC and stack alerts get through).
/// When the Focus ends the system runs this again with nothing set, which clears the hold.
struct PLDevFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Quiet the House"
    static let description: IntentDescription? = "Holds PL DEV\u{2019}s notices while this Focus is on."

    @Parameter(title: "Hold every notice") var pause: Bool?
    @Parameter(title: "Still let the PC and stack alerts through") var criticalOnly: Bool?

    var displayRepresentation: DisplayRepresentation {
        pause == true ? DisplayRepresentation(title: "Notices held", subtitle: criticalOnly == true ? "PC and stack alerts still come" : "None come") : DisplayRepresentation(title: "Notices as usual")
    }

    func perform() async throws -> some IntentResult {
        let d = UserDefaults.standard
        d.set(pause ?? false, forKey: "pldev.focus.pause")
        d.set(criticalOnly ?? false, forKey: "pldev.focus.critical")
        return .result()
    }
}

enum PLFocus {
    /// True when the current Focus asks that this notice type be held.
    static func holds(_ type: String) -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: "pldev.focus.pause") else { return false }
        if d.bool(forKey: "pldev.focus.critical"), type == "apple.pc" || type == "apple.stack" { return false }
        return true
    }
}
