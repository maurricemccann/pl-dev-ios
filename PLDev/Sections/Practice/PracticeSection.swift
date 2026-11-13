import SwiftUI
import TipKit
import UserNotifications

/// Practice: his daily practice, native (his order 11-13: "the practice in full"). Same Worker as the web app and the R1
/// twin, same record. The line plays only the clips that already exist in his voice; nothing is synthesised on the phone.
@MainActor enum PracticeSection: PLSection {
    static let manifest = SectionManifest(id: "practice", title: "Practice", symbol: "heart.text.square",
                                          needsKeys: [], needsOrigins: ["practice"])
    static let state = PracticeModel()
    private static var indexed = false

    static func makeRoot(model: AppModel) -> AnyView { AnyView(PracticeView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { AnyView(PracticeSettingsRows()) }

    /// One notice type, "practice": the evening line. Two real buttons: tick the next habit (Face ID first) and another line.
    static func notificationCategories() -> Set<UNNotificationCategory> {
        PracticeNotice.registerActions()
        let habit = UNNotificationAction(identifier: "practice.habit", title: "Tick next habit", options: [.authenticationRequired],
                                         icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let line = UNNotificationAction(identifier: "practice.line", title: "Another line", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "shuffle"))
        return [UNNotificationCategory(identifier: "practice", actions: [habit, line], intentIdentifiers: [])]
    }

    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first {
            if let tab = PracticeModel.Tab(rawValue: first) { state.tab = tab }
            if let room = PracticeRoom(rawValue: first) { state.room = room }
        }
        return true
    }

    static func refresh(model: AppModel) async -> SectionRefresh {
        await PracticeOutbox.flush(model: model)
        await state.loadToday(model: model)
        if PracticeDeck.cached().isEmpty, let l = try? await Practice.get("affirmations", PracticeAffirmations.self, model: model) { PracticeDeck.cache(l.items) }
        await PracticeNotice.reschedule(model: model)
        if !indexed { indexed = true; await PracticeSpotlight.index() }
        let left = state.left
        return SectionRefresh(badge: left > 0 ? left : nil, notify: [])
    }
}

struct HabitSwipeTip: Tip {
    var title: Text { Text("Tick a habit with a swipe") }
    var message: Text? { Text("Swipe a habit left to tick it. Swipe it back to undo.") }
    var image: Image? { Image(systemName: "hand.draw") }
}

/// Every Practice destination, by name, so a link, Siri, Spotlight or a notification can land on it.
enum PracticeRoom: String, CaseIterable, Identifiable, Hashable {
    case morning, evening, lesson, reframe, affirmations, coach, desires, habits, rehearsal, vision, notes, wins, review, trends
    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning check-in"; case .evening: return "Evening check-in"; case .lesson: return "Today's lesson"
        case .reframe: return "Reframe a belief"; case .affirmations: return "Affirmations"; case .coach: return "Talk it through"
        case .desires: return "Desires"; case .habits: return "Habits"; case .rehearsal: return "Rehearsal"; case .vision: return "Vision board"
        case .notes: return "Notes"; case .wins: return "Wins and noticed"; case .review: return "Weekly review"; case .trends: return "The record"
        }
    }

    var symbol: String {
        switch self {
        case .morning: return "sunrise"; case .evening: return "moon.stars"; case .lesson: return "book"
        case .reframe: return "arrow.triangle.2.circlepath"; case .affirmations: return "quote.bubble"; case .coach: return "bubble.left.and.bubble.right"
        case .desires: return "sparkles"; case .habits: return "checklist"; case .rehearsal: return "wind"; case .vision: return "photo.on.rectangle"
        case .notes: return "note.text"; case .wins: return "trophy"; case .review: return "calendar.badge.checkmark"; case .trends: return "chart.xyaxis.line"
        }
    }

    @MainActor @ViewBuilder func view(_ model: AppModel) -> some View {
        switch self {
        case .morning: CheckinView(model: model, evening: false)
        case .evening: CheckinView(model: model, evening: true)
        case .lesson: LessonView(model: model)
        case .reframe: ReframeView(model: model)
        case .affirmations: AffirmationsView(model: model)
        case .coach: CoachView(model: model)
        case .desires: DesiresView(model: model)
        case .habits: HabitsView(model: model)
        case .rehearsal: RehearsalView(model: model)
        case .vision: VisionView(model: model)
        case .notes: NotesView(model: model)
        case .wins: WinsView(model: model)
        case .review: ReviewView(model: model)
        case .trends: TrendsView(model: model)
        }
    }
}

@MainActor @Observable final class PracticeModel {
    enum Tab: String, CaseIterable, Identifiable {
        case today, practice, record
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var tab: Tab = .today
    var room: PracticeRoom?
    var streak: PracticeStreak?
    var today: PracticeCheckin?
    var lesson: PracticeLesson?
    var habits: [PracticeHabit] = []
    var reviewDue = false
    var message: String?
    var tick = 0
    var loaded = false

    var morningDone: Bool { today?.morning_at != nil }
    var eveningDone: Bool { today?.evening_at != nil }
    var habitsOpen: Int { habits.filter { !$0.tickedToday }.count }
    /// What is left today: the two check-ins and the habits not yet ticked.
    var left: Int { (morningDone ? 0 : 1) + (eveningDone ? 0 : 1) + habitsOpen }

    func loadToday(model: AppModel) async {
        async let s = try? Practice.get("streak", PracticeStreak.self, model: model)
        async let c = try? Practice.getOrNil("checkin/today", PracticeCheckin.self, model: model)
        async let l = try? Practice.get("lesson", PracticeLesson.self, model: model)
        async let h = try? Practice.get("habits", [PracticeHabit].self, model: model)
        async let r = try? Practice.get("reviews", [PracticeReview].self, model: model)
        let (s1, c1, l1, h1, r1) = await (s, c, l, h, r)
        if let s1 { streak = s1 }
        if s1 != nil { today = c1 }   // the practice answered: a nil check-in means none yet today
        if let l1 { lesson = l1 }
        if let h1 { habits = h1 }
        if let r1 {
            let latest = r1.first.flatMap { Date.pl($0.date) }
            reviewDue = latest.map { Date().timeIntervalSince($0) > 7 * 86400 } ?? true
        }
        loaded = true
        message = (s1 == nil && l1 == nil && h1 == nil) ? "Could not reach the practice. Pull to try again." : nil
        publish()
    }

    /// The widget's numbers, from what the app just read.
    func publish() {
        guard let streak else { return }
        PracticeGlance.write(PracticeGlance(monthDays: streak.practisedThisMonth, totalDays: streak.practisedTotal, weekDays: streak.completedOfLast7,
                                            morning: morningDone, evening: eveningDone, habitsDone: habits.count - habitsOpen, habitsTotal: habits.count,
                                            lessonTitle: lesson?.lesson.title, line: nil, updatedAt: .now))
    }

    /// Ticks or unticks today's habit. The row changes at once and comes back if the server refuses.
    func tickHabit(_ h: PracticeHabit, model: AppModel) async {
        guard let i = habits.firstIndex(where: { $0.id == h.id }) else { return }
        let before = habits[i]
        habits[i].tickedToday.toggle()
        if !habits[i].week.isEmpty { habits[i].week[habits[i].week.count - 1] = habits[i].tickedToday }
        do { try await Practice.post("habits/\(h.id)/tick", model: model); tick += 1; publish() }
        catch { if let j = habits.firstIndex(where: { $0.id == h.id }) { habits[j] = before }; message = error.localizedDescription }   // find it again: the list may have reloaded
    }
}

struct PracticeView: View {
    let model: AppModel
    @Bindable var state: PracticeModel

    var body: some View {
        Group {
            switch state.tab {
            case .today: TodayTab(model: model, state: state)
            case .practice: PracticeTab(model: model, state: state)
            case .record: RecordTab(model: model, state: state)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CandleTabs(titles: PracticeModel.Tab.allCases.map(\.title), index: Binding(
                get: { PracticeModel.Tab.allCases.firstIndex(of: state.tab) ?? 0 },
                set: { state.tab = PracticeModel.Tab.allCases[$0] }))
        }
        .background { CandleGround() }
        .preferredColorScheme(.dark)
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .navigationDestination(item: $state.room) { room in room.view(model) }
    }
}

/// Today: the loop in the web's order. The streak is soft: days practised this month and in all, nothing to break.
struct TodayTab: View {
    let model: AppModel
    @Bindable var state: PracticeModel
    @State private var win = ""
    @State private var result: String?

    var body: some View {
        List {
            if let m = state.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
            if let s = state.streak {
                Section {
                    VStack(spacing: 4) {
                        Text("\(s.practisedThisMonth)").font(.system(size: 38, weight: .light)).foregroundStyle(Candle.goldHi).monospacedDigit().contentTransition(.numericText())
                        Text("days practised this month").candleHint().font(.system(size: 13))
                        Text("\(s.practisedTotal) in all \u{00B7} \(s.completedOfLast7) of the last 7 complete").candleHint()
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                } footer: { Text("A day counts when either check-in is done. Missing one costs nothing.") }
            }
            Section("Today") {
                row(.morning, done: state.morningDone, detail: state.today?.mood.flatMap { $0.isEmpty ? nil : $0.capitalized } ?? "Mood and the story running")
                if let l = state.lesson {
                    NavigationLink { LessonView(model: model) } label: {
                        Label { Text(l.lesson.title).lineLimit(2); Text("Day \(l.lesson.day + 1)") } icon: { Image(systemName: "book") }
                    }
                }
                row(.evening, done: state.eveningDone, detail: "Gratitude, and whether the story shifted")
            }
            if !state.habits.isEmpty {
                Section {
                    TipView(HabitSwipeTip())
                    ForEach(state.habits) { h in
                        HabitRow(habit: h)
                            .swipeActions(edge: .trailing) {
                                Button(h.tickedToday ? "Undo" : "Done") { Task { await state.tickHabit(h, model: model) } }.tint(h.tickedToday ? .gray : .green)
                            }
                    }
                } header: { Text("Habits · \(state.habits.count - state.habitsOpen) of \(state.habits.count)") } footer: { Text("Swipe left to tick a habit.") }
            }
            Section("A win") {
                HStack {
                    TextField("A win from today", text: $win, axis: .vertical)
                    Button("Log") { Task { await logWin() } }.disabled(win.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ResultLine(text: result)
            }
            if state.reviewDue {
                Section { NavigationLink { ReviewView(model: model) } label: { Label("Close the week", systemImage: "calendar.badge.checkmark") } }
                footer: { Text("Seven days on the record. The weekly review is due.") }
            }
        }
        .practiceList()
        .overlay { if !state.loaded && state.streak == nil && state.message == nil { ProgressView() } }
        .refreshable { await PracticeOutbox.flush(model: model); await state.loadToday(model: model) }
        .task { await PracticeOutbox.flush(model: model); await state.loadToday(model: model) }
    }

    private func row(_ room: PracticeRoom, done: Bool, detail: String) -> some View {
        NavigationLink { room.view(model) } label: {
            Label { Text(room.title); Text(detail) } icon: {
                Image(systemName: done ? "checkmark.circle.fill" : room.symbol).foregroundStyle(done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: done)
            }
        }
    }

    private func logWin() async {
        let text = win.trimmingCharacters(in: .whitespaces)
        do { let sent = try await Practice.postQueued("logs", ["kind": "win", "text": text], model: model); win = ""; result = sent ? "Logged." : "Saved on this iPhone. It sends when you are online."; state.tick += 1 }
        catch { result = error.localizedDescription }
    }
}

struct HabitRow: View {
    let habit: PracticeHabit
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: habit.tickedToday ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(habit.tickedToday ? .green : .secondary).font(.title3)
                .contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: habit.tickedToday)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.response).strikethrough(habit.tickedToday)
                if let c = habit.cue, !c.isEmpty { Text("After: \(c)").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(Array(habit.week.enumerated()), id: \.offset) { _, on in
                    Circle().fill(on ? Candle.gold : Candle.ink.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.response), \(habit.tickedToday ? "done today" : "not done today"), \(habit.week.filter { $0 }.count) of 7 days")
    }
}

/// Practice: the rooms.
struct PracticeTab: View {
    let model: AppModel
    @Bindable var state: PracticeModel

    var body: some View {
        List {
            Section("Rooms") {
                ForEach([PracticeRoom.reframe, .affirmations, .coach, .desires, .habits, .rehearsal, .vision], id: \.self) { r in
                    NavigationLink { r.view(model) } label: {
                        Label(r.title, systemImage: r.symbol)
                    }
                    .badge(r == .habits && state.habitsOpen > 0 ? state.habitsOpen : 0)
                }
            }
        }
        .practiceList()
    }
}

/// Record: what the practice has kept.
struct RecordTab: View {
    let model: AppModel
    @Bindable var state: PracticeModel

    var body: some View {
        List {
            Section {
                ForEach([PracticeRoom.trends, .wins, .notes, .review], id: \.self) { r in
                    NavigationLink { r.view(model) } label: { Label(r.title, systemImage: r.symbol) }
                        .badge(r == .review && state.reviewDue ? 1 : 0)
                }
            } footer: {
                Text("Nothing here can be deleted from the phone. The record is the record.\(PracticeOutbox.count > 0 ? " \(PracticeOutbox.count) written offline, waiting to send." : "")")
            }
        }
        .practiceList()
    }
}

/// Figures in a row at normal sizes, stacked at the largest accessibility sizes (every screen must work at the largest size).
struct PracticeKpis: View {
    let items: [(String, String)]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PLSpace.margin) { ForEach(items.indices, id: \.self) { Kpi(title: items[$0].0, value: items[$0].1) } }
            VStack(alignment: .leading, spacing: PLSpace.gap) { ForEach(items.indices, id: \.self) { Kpi(title: items[$0].0, value: items[$0].1) } }
        }
    }
}
