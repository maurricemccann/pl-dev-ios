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
        case path, today, games, trends
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// His ruling 11-15: tap to hear your line, then the path.
    var tab: Tab = .path
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
    @State private var buddy = BuddyModel()   // Buddy lives top-right of Practice (his circle, 11-15), his drawn faces only
    @State private var rope: BuddyRopeRig?     // his rope, built once the bar item's place on screen is known

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if let m = state.message { Text(m).candleHint().frame(maxWidth: .infinity, alignment: .leading) }
                    switch state.tab {
                    case .path: PathScreen(model: model)
                    case .today: TodayScreen(model: model, state: state)
                    case .games: GamesScreen(model: model)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // a real Button: a bar item's plain tap gesture never fired on his phone (11-15, "Tap didn't play anything")
                // the bar clips anything drawn past an item (the simulator shot 11-15 showed the rope cut to a box), so the bar item is
                // only the touch target; the rope and Buddy are drawn in an overlay under the glass bar, from this item's place on screen
                Button { buddy.playNext() } label: { Color.clear.frame(width: 48, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                        let home = CGPoint(x: f.midX, y: f.midY)
                        if rope.map({ hypot($0.home.x - home.x, $0.home.y - home.y) > 2 }) ?? true { rope = BuddyRopeRig(home: home) }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { v in rope?.grab = v.location }
                        .onEnded { _ in rope?.grab = nil })
                    .accessibilityHint("Tap for his next move, drag to swing him")
                    .onAppear { buddy.react(.open); BuddyIsland.start() }
                    .task {
                        // his ruling 11-15 "now and then": at rest, every 20-40 s Buddy plays his next move from the shuffled deck
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(Double.random(in: 20...40)))
                            if !Task.isCancelled && buddy.move == nil && !UIAccessibility.isReduceMotionEnabled { buddy.playNext() }
                        }
                    }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(state.entryDone ? .automatic : .hidden, for: .navigationBar)
        .overlay { if state.entryDone, let rope { BuddyRope(buddy: buddy, rig: rope).ignoresSafeArea().allowsHitTesting(false) } }
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

/// Buddy on his own curve (his mock-up 11-15: "the orange curve then you can play with him like the curve below"): an orange rope from
/// above the top edge sweeps down to Buddy, who rides its tip. The hero curve's rope physics (FieldRig's spring, damping, spread, the
/// slow breathing drift): dragging Buddy pulls the tip and the rope follows; let go and it swings home. The rope is drawn past the
/// item's 56x44 frame (the bar does not clip it); only the item takes touches.
@MainActor final class BuddyRopeRig {
    static let n = 16
    let home: CGPoint
    var hx: [Double] = [], hy: [Double] = [], px: [Double] = [], py: [Double] = [], ox: [Double] = [], oy: [Double] = []
    var grab: CGPoint?
    var t = 0.0
    var trail: [CGPoint] = []   // the tip's last positions, newest last (the ragdoll squish reads it)
    private var acc = 0.0, last: Date?

    /// Screen points: the rope hangs from above the top edge, left of Buddy, and sweeps down to his home (his mock-up 11-15).
    init(home: CGPoint) {
        self.home = home
        let a = CGPoint(x: home.x - 200, y: -40), c = CGPoint(x: home.x - 90, y: home.y + 6), b = home
        for k in 0..<Self.n {
            let u = Double(k) / Double(Self.n - 1)
            hx.append((1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x)
            hy.append((1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y)
        }
        px = hx; py = hy; ox = hx; oy = hy
    }

    func advance(_ now: Date, still: Bool) {
        defer { last = now }
        guard !still, let last else { return }
        acc += min(0.1, now.timeIntervalSince(last)) * 60
        var g = 0
        while acc >= 1, g < 4 { step(); acc -= 1; g += 1 }
    }

    func step() {
        let N = Self.n
        for k in 1..<N {   // the anchor (k = 0) stays above the top edge
            let u = Double(k) / Double(N - 1), s = t * 0.008, amp = 6 * sin(.pi * u * 0.9)
            let tx = hx[k] + sin(s * 1.1 + u * 3) * amp, ty = hy[k] + cos(s * 0.9 + u * 2.4) * amp
            let vx = (px[k] - ox[k]) * FieldRig.damp, vy = (py[k] - oy[k]) * FieldRig.damp
            ox[k] = px[k]; oy[k] = py[k]
            px[k] += vx + (tx - px[k]) * FieldRig.spring; py[k] += vy + (ty - py[k]) * FieldRig.spring
        }
        if let g = grab { px[N - 1] = g.x; py[N - 1] = g.y }   // the finger holds Buddy; the rope follows
        trail.append(CGPoint(x: px[N - 1], y: py[N - 1])); if trail.count > 14 { trail.removeFirst() }
        for k in 1..<(N - 1) {
            let dx = (px[k - 1] - hx[k - 1] + px[k + 1] - hx[k + 1]) * 0.5 - (px[k] - hx[k])
            let dy = (py[k - 1] - hy[k - 1] + py[k + 1] - hy[k + 1]) * 0.5 - (py[k] - hy[k])
            px[k] += dx * FieldRig.spread; py[k] += dy * FieldRig.spread
        }
        t += 1
    }

    var tip: CGPoint { CGPoint(x: px[Self.n - 1], y: py[Self.n - 1]) }

    /// The ragdoll squish fitted to his top curve (spec BUDDY RAGDOLL SQUISH, his ruling 11-15 "Do but fit his top curve"): each piece
    /// sits where the tip was `lag` frames ago, so as the rope swings his eyes and mouth trail his head by their own delays and settle
    /// back when the rope rests. Offsets are capped so a hard fling never pulls a piece off his face.
    func lagOffset(_ lag: Int) -> CGSize {
        guard trail.count > lag else { return .zero }
        let then = trail[trail.count - 1 - lag], now = tip
        let dx = then.x - now.x, dy = then.y - now.y, d = max(1, hypot(dx, dy)), cap: CGFloat = 9
        let k = min(1, cap / d)
        return CGSize(width: dx * k, height: dy * k)
    }

    func path() -> Path {
        var p = Path(); let N = Self.n
        p.move(to: CGPoint(x: px[0], y: py[0]))
        for k in 1..<(N - 1) { p.addQuadCurve(to: CGPoint(x: (px[k] + px[k + 1]) / 2, y: (py[k] + py[k + 1]) / 2), control: CGPoint(x: px[k], y: py[k])) }
        p.addLine(to: tip)
        // the band runs on past Buddy to the right edge, in the direction it arrived
        let d = CGPoint(x: px[N - 1] - px[N - 3], y: py[N - 1] - py[N - 3]), l = max(1, hypot(d.x, d.y))
        p.addLine(to: CGPoint(x: tip.x + d.x / l * 70, y: tip.y + d.y / l * 70))
        return p
    }
}

struct BuddyRope: View {
    let buddy: BuddyModel
    let rig: BuddyRopeRig
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let orange = Color(red: 143 / 255, green: 101 / 255, blue: 40 / 255)   // sampled from his mock-up

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion && rig.grab == nil)) { tl in
            let _ = rig.advance(tl.date, still: reduceMotion && rig.grab == nil)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in ctx.stroke(rig.path(), with: .color(Self.orange), style: StrokeStyle(lineWidth: 26, lineCap: .butt, lineJoin: .round)) }
                BuddyView(model: buddy, trail: ["eyeL": rig.lagOffset(3), "eyeR": rig.lagOffset(5), "mouth": rig.lagOffset(8)], pinned: true)
                    .frame(width: 46, height: 46).position(rig.tip)
            }
        }
    }
}
