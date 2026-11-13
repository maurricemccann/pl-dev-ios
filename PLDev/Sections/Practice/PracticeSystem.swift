import ActivityKit
import AppIntents
import CoreSpotlight
import SwiftUI
import UserNotifications

// Practice's system add-ons, built the way House's are (DESIGN.md section 6): the evening notice with real buttons,
// the rehearsal as a Live Activity, Siri and Shortcuts, Spotlight, one tip, and a deep link to every room.

// MARK: - The evening notice

/// One line each evening, at the hour he chose (9 PM by default, like the R1). Its buttons do something: tick the next
/// habit (Face ID first) or show another line. Local only; the line comes from the cached library, shuffled, never repeated until all were shown.
@MainActor enum PracticeNotice {
    static let id = "practice.evening"
    static var on: Bool { UserDefaults.standard.object(forKey: "practice.remind") as? Bool ?? true }
    static var hour: Int { UserDefaults.standard.object(forKey: "practice.hour") as? Int ?? 21 }

    static func registerActions() {
        NotificationHub.actions["practice.habit"] = {
            let model = AppModel.shared
            await model.restoreIfNeeded()
            guard let habits = try? await Practice.get("habits", [PracticeHabit].self, model: model),
                  let next = habits.first(where: { !$0.tickedToday }) else { return }
            if (try? await Practice.post("habits/\(next.id)/tick", model: model)) != nil {
                _ = await NotificationHub.shared.post(id: "practice.ticked", title: "Ticked", body: next.response, category: nil, link: nil)
            } else {
                _ = await NotificationHub.shared.post(id: "practice.ticked", title: "Not ticked", body: "The practice did not answer. Open PL DEV to try again.", category: nil, link: nil)
            }
        }
        NotificationHub.actions["practice.line"] = {
            await schedule(after: 2)
        }
    }

    /// Plans the next evening notice. Called after every refresh and every check-in, so it knows when the day is already closed.
    static func reschedule(model: AppModel) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard on else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let state = PracticeSection.state
        var at = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        if at <= .now || state.eveningDone { at = Calendar.current.date(byAdding: .day, value: 1, to: at) ?? at }
        await schedule(at: at)
    }

    private static func schedule(after seconds: TimeInterval) async { await schedule(at: .now.addingTimeInterval(seconds), id: "practice.line") }

    private static func schedule(at date: Date, id: String = PracticeNotice.id) async {
        let lines = PracticeDeck.cached()
        let line = PracticeDeck.next(of: lines.map(\.key)).flatMap { k in lines.first { $0.key == k }?.text } ?? "Close the day: gratitude, and whether the story shifted."
        let c = UNMutableNotificationContent()
        c.title = "Your line for tonight"
        c.body = line
        c.sound = .default
        c.categoryIdentifier = "practice"
        c.threadIdentifier = "practice"
        c.userInfo = [NotificationHub.linkKey: DeepLink.section(id: "practice", path: ["evening"], query: [:]).url.absoluteString]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await UNUserNotificationCenter.current().add(req)
        PracticeGlance.write(PracticeGlance(monthDays: PracticeSection.state.streak?.practisedThisMonth ?? 0, totalDays: PracticeSection.state.streak?.practisedTotal ?? 0,
                                            weekDays: PracticeSection.state.streak?.completedOfLast7 ?? 0, morning: PracticeSection.state.morningDone,
                                            evening: PracticeSection.state.eveningDone, habitsDone: PracticeSection.state.habits.count - PracticeSection.state.habitsOpen,
                                            habitsTotal: PracticeSection.state.habits.count, lessonTitle: PracticeSection.state.lesson?.lesson.title, line: line, updatedAt: .now))
    }
}

/// Practice's own Settings rows: the reminder, its hour, and the tips.
struct PracticeSettingsRows: View {
    @AppStorage("practice.remind") private var on = true
    @AppStorage("practice.hour") private var hour = 21

    var body: some View {
        Group {
            Toggle(isOn: $on) { SettingsLabel("Evening line", "moon.stars", IOS27.SystemColors.indigo) }
            if on {
                Picker(selection: $hour) { ForEach(17...23, id: \.self) { Text(Date.pl(hour: $0)).tag($0) } } label: { SettingsLabel("Evening line at", "clock", Color(uiColor: .systemGray)) }
            }
        }
        .onChange(of: on) { _, _ in Task { await PracticeNotice.reschedule(model: AppModel.shared) } }
        .onChange(of: hour) { _, _ in Task { await PracticeNotice.reschedule(model: AppModel.shared) } }
    }
}

extension Date {
    /// "9 PM" for an hour of the day, in his locale.
    static func pl(hour: Int) -> String {
        (Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now).formatted(.dateTime.hour())
    }
}

// MARK: - The rehearsal Live Activity

@MainActor enum RehearsalLive {
    nonisolated static var running: Activity<RehearsalAttributes>? { Activity<RehearsalAttributes>.activities.first }
    private static let titles = ["See it", "Hear it", "Feel it", "The feeling", "Hold it"]

    /// Started only from the foreground, by his tap on Begin: a defined beginning and a defined end (two minutes).
    static func start(desire: String, started: Date, titles full: [String]) {
        guard running == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: RehearsalAttributes(desire: String(desire.prefix(80)), started: started, ends: started.addingTimeInterval(120)),
                                  content: .init(state: .init(stage: 0, title: titles[0]), staleDate: started.addingTimeInterval(150), relevanceScore: 90))
    }

    /// Updated only when the sense changes.
    nonisolated static func update(stage: Int, titles full: [String]) async {
        guard let a = running, a.content.state.stage != stage else { return }
        let names = ["See it", "Hear it", "Feel it", "The feeling", "Hold it"]
        await a.update(.init(state: .init(stage: stage, title: names[min(stage, names.count - 1)]), staleDate: nil, relevanceScore: 90))
    }

    /// Ended the moment the rehearsal ends.
    nonisolated static func stop() async {
        for a in Activity<RehearsalAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }
}

// MARK: - Siri, Shortcuts and the Action button (app target only, so they run in the app's process)

@MainActor private func practiceModel() async throws -> AppModel {
    let m = AppModel.shared
    await m.restoreIfNeeded()
    guard m.http != nil, m.config?.origin("practice") != nil else { throw Practice.Problem.notSetUp }
    return m
}

struct PracticeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Left in My Practice Today"
    static let description: IntentDescription? = "Says which check-ins are done, how many habits are ticked and how many days you have practised."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = try await practiceModel()
        await PracticeSection.state.loadToday(model: m)
        let s = PracticeSection.state
        var parts = [s.morningDone ? "Morning check-in done." : "Morning check-in not done.", s.eveningDone ? "Evening check-in done." : "Evening check-in not done."]
        if !s.habits.isEmpty { parts.append("\(s.habits.count - s.habitsOpen) of \(s.habits.count) habits ticked.") }
        if let k = s.streak { parts.append("\(k.practisedThisMonth) days practised this month, \(k.practisedTotal) in all.") }
        return .result(dialog: "\(parts.joined(separator: " "))")
    }
}

struct LogWinIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Win"
    static let description: IntentDescription? = "Writes a win into your practice record."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Win", requestValueDialog: "What was the win?") var text: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = try await practiceModel()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .result(dialog: "Nothing was logged. The win was empty.") }
        try await Practice.post("logs", ["kind": "win", "text": t], model: m)
        return .result(dialog: "Logged: \(t)")
    }
}

struct TickNextHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick My Next Habit"
    static let description: IntentDescription? = "Ticks the next habit you have not done today."
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = try await practiceModel()
        let habits = try await Practice.get("habits", [PracticeHabit].self, model: m)
        guard !habits.isEmpty else { return .result(dialog: "You have no habits yet.") }
        guard let next = habits.first(where: { !$0.tickedToday }) else { return .result(dialog: "All \(habits.count) habits are ticked today.") }
        try await Practice.post("habits/\(next.id)/tick", model: m)
        let left = habits.filter { !$0.tickedToday }.count - 1
        return .result(dialog: "Ticked: \(next.response). \(left) of \(habits.count) left today.")
    }
}

struct OpenPracticeRoomIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Practice Room"
    @Parameter(title: "Room") var target: PracticeRoomEntity

    init() {}
    init(target: PracticeRoomEntity) { self.target = target }

    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "practice", path: [target.id], query: [:])) }
        return .result()
    }
}

struct PracticeRoomEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Practice Room"
    static let defaultQuery = PracticeRoomQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "Practice") }

    static var all: [PracticeRoomEntity] { PracticeRoom.allCases.map { PracticeRoomEntity(id: $0.rawValue, title: $0.title) } }
}

struct PracticeRoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PracticeRoomEntity] { PracticeRoomEntity.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [PracticeRoomEntity] { PracticeRoomEntity.all.filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PracticeRoomEntity] { PracticeRoomEntity.all }
}

enum PracticeSpotlight {
    /// Every room into Spotlight, in Practice's own named index (Apple: not the default index).
    static func index() async {
        try? await CSSearchableIndex(name: "practice").indexAppEntities(PracticeRoomEntity.all)
    }
}
