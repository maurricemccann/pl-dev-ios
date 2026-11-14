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
            state.entryDone = true   // a link to a card goes straight there; the entry is for opening the app
            if first == "record" { state.tab = .trends }
            else if let tab = PracticeModel.Tab(rawValue: first) { state.tab = tab }
            if let room = PracticeRoom(rawValue: first) { state.tab = room.tab; state.scrollTo = room.card; if room == .preview { state.preview = true } }
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
    var title: Text { Text("Habits tick with a tap") }
    var message: Text? { Text("Tap the box to tick a habit. Touch and hold a habit to archive it.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Every Practice destination, by name, so a link, Siri, Spotlight or a notification can land on it.
enum PracticeRoom: String, CaseIterable, Identifiable, Hashable {
    case morning, evening, lesson, reframe, affirmations, coach, desires, habits, rehearsal, vision, notes, wins, review, trends, preview, seeds, tarot
    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning check-in"; case .evening: return "Evening check-in"; case .lesson: return "Today's lesson"
        case .reframe: return "Reframe a belief"; case .affirmations: return "Affirmations"; case .coach: return "Talk it through"
        case .desires: return "Desires"; case .habits: return "Habits"; case .rehearsal: return "Rehearsal"; case .vision: return "Vision board"
        case .notes: return "Notes"; case .wins: return "Wins and noticed"; case .review: return "Weekly review"; case .trends: return "The record"; case .preview: return "Vision preview"
        case .seeds: return "Seed phrase draw"; case .tarot: return "PL tarot"
        }
    }

    var symbol: String {
        switch self {
        case .morning: return "sunrise"; case .evening: return "moon.stars"; case .lesson: return "book"
        case .reframe: return "arrow.triangle.2.circlepath"; case .affirmations: return "quote.bubble"; case .coach: return "bubble.left.and.bubble.right"
        case .desires: return "sparkles"; case .habits: return "checklist"; case .rehearsal: return "wind"; case .vision: return "photo.on.rectangle"
        case .notes: return "note.text"; case .wins: return "trophy"; case .review: return "calendar.badge.checkmark"; case .trends: return "chart.xyaxis.line"; case .preview: return "eye"
        case .seeds: return "leaf"; case .tarot: return "rectangle.portrait.on.rectangle.portrait"
        }
    }

    /// Which screen the room lives on, and which card on it.
    var tab: PracticeModel.Tab { [.review, .trends, .preview].contains(self) ? .trends : .today }
    var card: String {
        switch self {
        case .morning: return "morning"; case .evening: return "evening"; case .lesson: return "lesson"; case .reframe: return "reframe"
        case .affirmations: return "affirmations"; case .coach: return "conversation"; case .desires: return "desires"; case .habits: return "habits"
        case .rehearsal: return "meditation"; case .vision: return "vision"; case .notes: return "scratchpad"; case .wins: return "wins"
        case .review: return "review"; case .trends: return "story"; case .preview: return "preview"
        case .seeds: return "seeds"; case .tarot: return "tarot"
        }
    }
}

@MainActor @Observable final class PracticeModel {
    enum Tab: String, CaseIterable, Identifiable {
        case today, trends
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var tab: Tab = .today
    /// The vision preview (his private, made-up Mastermind Board) is pushed on this.
    var preview = false
    /// The card a link, Siri or a notification wants in view; the screen scrolls to it and clears this.
    var scrollTo: String?
    /// Bumped on pull-to-refresh and after writes other cards care about; every card reloads when it changes.
    var reload = 0
    /// Bumped when the desire list changes, so the rehearsal's choice of desire follows.
    var desiresRev = 0
    /// The speak-first entry shows once per launch.
    var entryDone = false
    static var pinged = false
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
    @State private var started = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if let m = state.message { Text(m).candleHint().frame(maxWidth: .infinity, alignment: .leading) }
                    switch state.tab {
                    case .today: TodayScreen(model: model, state: state)
                    case .trends: TrendsScreen(model: model, state: state)
                    }
                }
                .frame(maxWidth: 640).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 64).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await state.loadToday(model: model); state.reload += 1 }
            .onChange(of: state.scrollTo) { _, id in jump(proxy, id) }
            .onChange(of: state.tab) { _, _ in if state.scrollTo == nil { proxy.scrollTo("top", anchor: .top) } }
            .task { if !started { started = true; await openPing(); jump(proxy, state.scrollTo) } }
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
        .toolbar(state.entryDone ? .automatic : .hidden, for: .navigationBar)
        .overlay { if !state.entryDone { PracticeEntry(model: model, state: state).transition(.opacity) } }
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .navigationDestination(isPresented: $state.preview) { VisionPreviewView() }
        .task { await PracticeOutbox.flush(model: model); await state.loadToday(model: model) }
    }

    private func jump(_ proxy: ScrollViewProxy, _ id: String?) {
        guard let id else { return }
        withAnimation(.smooth) { proxy.scrollTo(id, anchor: .top) }
        state.scrollTo = nil
    }

    /// The web's return-moment measure (S322): one quiet ping per cold start, never blocks, fails silent.
    private func openPing() async {
        guard !PracticeModel.pinged, let url = URL(string: "https://pl-cron.psychedluxuries.com/api/practice/open") else { return }
        PracticeModel.pinged = true
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "content-type"); r.timeoutInterval = 10
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["via": "direct", "local_hour": Calendar.current.component(.hour, from: .now)])
        _ = try? await URLSession.shared.data(for: r)
    }
}

/// Today: the web's cards, in its order.
struct TodayScreen: View {
    let model: AppModel
    @Bindable var state: PracticeModel

    var body: some View {
        VStack(spacing: 16) {
            Color.clear.frame(height: 0).id("top")
            StreakCard(state: state)
            ScratchpadCard(model: model, state: state)
            WinsCard(model: model, state: state)
            CheckinCard(model: model, state: state, evening: false)
            LessonCard(model: model, state: state)
            ReframeCard(model: model, state: state)
            AffirmationsCard(model: model, state: state)
            SeedDrawCard()
            TarotCard(model: model)
            ConversationCard(model: model, state: state)
            DesireListCard(model: model, state: state)
            HabitsCard(model: model, state: state)
            MeditationCard(model: model, state: state)
            VisionBoardCard(model: model, state: state)
            CheckinCard(model: model, state: state, evening: true)
        }
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
