import SwiftUI

// One Teacher (S348·9a3e): the course. The practice is the course, the Academy is each unit's reading, the games and drills are its
// lessons. One file from the practice Worker (`GET /api/course`, generated from canon) drives everything here, so content cannot drift.
// His rulings: units open in order and reading is always open; a wrong answer shows why and comes back later; a lesson starts easy and
// ends hard; one earlier item in every lesson; a unit turns gold, for good, when every lesson is played, the quiz is passed and every
// page is read. Progress only adds. Nothing here is sent anywhere: the record stays on the phone.

// MARK: - the course file

/// An answer is a word, a number (which Truth) or a list (the order, the banned words).
enum CourseAnswer: Decodable, Sendable, Equatable {
    case text(String), number(Int), list([String])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .number(i) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .list((try? c.decode([String].self)) ?? []) }
    }
    var string: String { if case .text(let s) = self { return s }; if case .number(let n) = self { return String(n) }; return "" }
    var strings: [String] { if case .list(let l) = self { return l }; return [] }
}

struct CourseExercise: Decodable, Sendable, Identifiable, Equatable {
    let kind: String
    let prompt: String
    let level: Int
    let item: String
    let text: String?
    let answer: CourseAnswer?
    let options: [String]?
    let why: String?
    let glyph: String?
    var id: String { kind + "|" + item + "|" + prompt }
    /// The kinds this build can play. The rest (rewrite, draw-it) are in the file and wait for their views.
    static let playable: Set<String> = ["complete-phrase", "match-glyph", "choose", "which-truth", "order-truths", "rebuild-phrase", "recall-phrase", "find-banned-word", "reflect", "rewrite", "say-it", "draw-it"]
    /// draw-it needs his drawn mark for that glyph (5 of the 10 have one); the rest wait for theirs.
    var isPlayable: Bool { Self.playable.contains(kind) && (kind != "draw-it" || DrawItExercise.art(glyph ?? "") != nil) }
}

struct CourseLesson: Decodable, Sendable, Identifiable { let n: Int; let exercises: [CourseExercise]; let review_slots: Int?; var id: Int { n } }
struct CoursePage: Decodable, Sendable, Identifiable { let title: String; let key: String?; var id: String { title } }

struct CourseUnit: Decodable, Sendable, Identifiable {
    let n: Int
    let title: String
    let about: String
    let guidebook: [CoursePage]
    let items: [CourseItem]?
    let lessons: [CourseLesson]
    let quiz: [CourseExercise]
    let waits_on: String?
    var id: Int { n }
    var playableLessons: [CourseLesson] { lessons.filter { $0.exercises.contains(where: \.isPlayable) } }
}

struct Course: Decodable, Sendable { let version: Int; let units: [CourseUnit] }

// MARK: - the record (on the phone, only ever adds)

@MainActor @Observable final class CourseRecord {
    static let shared = CourseRecord()
    private(set) var lessonsDone: Set<String>
    private(set) var quizPassed: Set<Int>
    private(set) var misses: [String: Int]
    private(set) var days: Set<String>
    private let store = UserDefaults.standard

    private init() {
        lessonsDone = Set(store.stringArray(forKey: "course.lessons") ?? [])
        quizPassed = Set((store.array(forKey: "course.quiz") as? [Int]) ?? [])
        misses = (store.dictionary(forKey: "course.misses") as? [String: Int]) ?? [:]
        days = Set(store.stringArray(forKey: "course.days") ?? [])
    }

    private func today() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: .now) }
    private func save() {
        store.set(Array(lessonsDone), forKey: "course.lessons"); store.set(Array(quizPassed), forKey: "course.quiz")
        store.set(misses, forKey: "course.misses"); store.set(Array(days), forKey: "course.days")
    }
    func key(_ unit: Int, _ lesson: Int) -> String { "\(unit)-\(lesson)" }
    func isDone(_ unit: Int, _ lesson: Int) -> Bool { lessonsDone.contains(key(unit, lesson)) }
    func finish(unit: Int, lesson: Int) { lessonsDone.insert(key(unit, lesson)); days.insert(today()); save() }
    func passQuiz(_ unit: Int) { quizPassed.insert(unit); days.insert(today()); save() }
    func miss(_ item: String) { misses[item, default: 0] += 1; save() }

    func lessonsLeft(_ u: CourseUnit) -> Int { u.playableLessons.filter { !isDone(u.n, $0.n) }.count }
    func pagesLeft(_ u: CourseUnit) -> Int { u.guidebook.filter { p in p.key.map { Academy.read[$0] == nil } ?? false }.count }
    /// Gold: every lesson played, the quiz passed, every page read. A unit with nothing to play yet cannot be gold.
    func isGold(_ u: CourseUnit) -> Bool {
        !u.playableLessons.isEmpty && lessonsLeft(u) == 0 && quizPassed.contains(u.n) && pagesLeft(u) == 0
    }
    /// Units open in order: a unit's lessons open once the unit before it has every lesson played.
    func isOpen(_ u: CourseUnit, in course: Course) -> Bool {
        guard let prev = course.units.first(where: { $0.n == u.n - 1 }) else { return true }
        return prev.playableLessons.isEmpty || lessonsLeft(prev) == 0
    }
    func next(in course: Course) -> (CourseUnit, CourseLesson)? {
        for u in course.units where isOpen(u, in: course) {
            if let l = u.playableLessons.first(where: { !isDone(u.n, $0.n) }) { return (u, l) }
        }
        return nil
    }
    /// One earlier exercise for review: the most-missed item first, then a shuffled deck over the rest.
    func review(for unit: CourseUnit, in course: Course) -> CourseExercise? {
        let pool = course.units.filter { $0.n < unit.n }.flatMap(\.quiz).filter(\.isPlayable)
        guard !pool.isEmpty else { return nil }
        if let worst = pool.max(by: { (misses[$0.item] ?? 0) < (misses[$1.item] ?? 0) }), (misses[worst.item] ?? 0) > 0 { return worst }
        guard let k = PracticeDeck.next(of: pool.map(\.id), deck: "course.review.deck") else { return nil }
        return pool.first { $0.id == k }
    }
}

// MARK: - the Path

@MainActor @Observable final class CourseModel {
    var course: Course?
    var message: String?
    func load(model: AppModel) async {
        do { course = try await Practice.get("course", Course.self, model: model, timeout: 40); message = nil }
        catch { if course == nil { message = "Could not reach the course. Pull to try again." } }
    }
}

struct PathScreen: View {
    let model: AppModel
    @State private var state = CourseModel()
    @State private var playing: LessonRun?
    @State private var goldPack: GoldPack?
    /// His daily minutes (asked once here, changeable in Settings): a lesson is about three minutes.
    @AppStorage("course.minutes") private var minutes = 0
    @State private var pathBuddy = BuddyModel()
    /// Bumped each time the Path comes back into view, so pages read in the Academy reader count at once.
    @State private var seen = 0
    private let record = CourseRecord.shared

    var body: some View {
        let _ = seen
        VStack(spacing: 16) {
            if let m = state.message { Text(m).candleHint().frame(maxWidth: .infinity, alignment: .leading) }
            if minutes == 0 { goalCard }
            if let course = state.course {
                summary(course)
                ForEach(course.units) { u in
                    unitCard(u, course)
                    // his ruling 11-15: each unit's lessons as fields of six, lesson n riding stroke n of The Direction
                    ForEach(PracticeChapter.of(u)) { ch in
                        PracticeField(unit: u, chapter: ch, open: record.isOpen(u, in: course)) { l in start(u, l, course) }
                    }
                }
            } else if state.message == nil {
                ProgressView().tint(Candle.gold).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .onAppear { seen += 1 }
        .task { await state.load(model: model) }
        .fullScreenCover(item: $playing) { run in LessonView(model: model, run: run) { playing = nil } }
        .background { Color.clear.fullScreenCover(item: $goldPack) { g in PackScreen(model: model, key: "gold-\(g.unit)") { goldPack = nil } } }
    }

    /// First open: his daily goal in minutes sizes what Today suggests.
    private var goalCard: some View {
        PCard(title: "How long each day?", hint: "It sets how many lessons a day are suggested. Change it any time in Settings.") {
            HStack(spacing: 8) {
                ForEach([5, 10, 15], id: \.self) { m in
                    Button("\(m) min") { minutes = m }.buttonStyle(CandleGhost())
                }
            }
        }
    }

    private var daysAway: Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let last = record.days.compactMap({ f.date(from: $0) }).max() else { return 0 }
        return Calendar.current.dateComponents([.day], from: last, to: Calendar.current.startOfDay(for: .now)).day ?? 0
    }

    private func summary(_ course: Course) -> some View {
        let gold = course.units.filter { record.isGold($0) }.count
        return VStack(alignment: .leading, spacing: 6) {
            if daysAway >= 3 {
                HStack(spacing: 10) {
                    BuddyView(model: pathBuddy).frame(width: 52, height: 52)
                    Text("Welcome back.").candleH2()
                }
                .onAppear { pathBuddy.react(.returned) }
            }
            Text("\(record.days.count) \(record.days.count == 1 ? "day" : "days") of lessons").font(.system(size: 22, weight: .semibold)).foregroundStyle(Candle.goldHi)
            Text("\(gold) of \(course.units.count) units gold").candleHint()
            if minutes > 0 { Text("About \(max(1, minutes / 3)) \(minutes / 3 > 1 ? "lessons" : "lesson") a day for your \(minutes) minutes.").candleHint() }
            if let (u, l) = record.next(in: course) {
                Button("Next lesson: \(u.title), \(l.n)") { start(u, l, course) }.buttonStyle(CandleButton()).padding(.top, 6)
            }
        }
        .candleCard()
    }

    private func unitCard(_ u: CourseUnit, _ course: Course) -> some View {
        let open = record.isOpen(u, in: course), gold = record.isGold(u)
        return PCard(title: "\(u.n) \u{00b7} \(u.title)" + (gold ? "  \u{2726} gold" : ""), hint: u.about, id: "unit-\(u.n)") {
            if !u.guidebook.isEmpty {
                Text("Read").font(.system(size: 11)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.ink.opacity(0.5))
                ForEach(u.guidebook) { p in pageRow(p, u) }
            }
            if u.playableLessons.isEmpty {
                Text(u.waits_on.map { "Lessons wait on: \($0)." } ?? "No lessons yet.").candleHint()
            } else {
                Text("\(u.playableLessons.count - record.lessonsLeft(u)) of \(u.playableLessons.count) lessons drawn, in \(PracticeChapter.of(u).count) \(PracticeChapter.of(u).count == 1 ? "chapter" : "chapters") below.").candleHint().padding(.top, 4)
                if !open { Text("Opens when the unit before it has every lesson played.").candleHint() }
                if open && record.lessonsLeft(u) == 0 && !u.quiz.filter(\.isPlayable).isEmpty {
                    Button(record.quizPassed.contains(u.n) ? "Quiz passed \u{2713} \u{00b7} retake" : "Take the unit quiz") {
                        playing = LessonRun(unit: u, lesson: nil, exercises: u.quiz.filter(\.isPlayable), isQuiz: true)
                    }.buttonStyle(CandleGhost())
                }
                if gold { Button("Open your pack") { goldPack = GoldPack(unit: u.n) }.buttonStyle(CandleButton()) }
                if record.lessonsLeft(u) == 0 && record.quizPassed.contains(u.n) && record.pagesLeft(u) > 0 {
                    Text("\(record.pagesLeft(u)) \(record.pagesLeft(u) == 1 ? "page" : "pages") left to read for gold.").candleHint()
                }
            }
        }
        .opacity(open ? 1 : 0.6)
    }

    private func pageRow(_ p: CoursePage, _ u: CourseUnit) -> some View {
        Group {
            if let key = p.key {
                NavigationLink {
                    AcademyReaderView(doc: AcademyHTML.Doc(key: key, name: p.title), sectionTitle: u.title).osScreen()
                } label: {
                    HStack {
                        Image(systemName: Academy.read[key] == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(Candle.gold)
                        Text(p.title.capitalized).font(.system(size: 14)).foregroundStyle(Candle.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Candle.ink.opacity(0.4))
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(p.title.capitalized + " (not in the Academy yet)").candleHint()
            }
        }
    }

    private func start(_ u: CourseUnit, _ l: CourseLesson, _ course: Course) {
        var ex = l.exercises.filter(\.isPlayable)
        if (l.review_slots ?? 0) > 0, let r = record.review(for: u, in: course) { ex.insert(r, at: min(1, ex.count)) }
        playing = LessonRun(unit: u, lesson: l, exercises: ex, isQuiz: false)
    }
}

// MARK: - a lesson

struct GoldPack: Identifiable { let unit: Int; var id: Int { unit } }

struct LessonRun: Identifiable {
    let unit: CourseUnit
    let lesson: CourseLesson?
    let exercises: [CourseExercise]
    let isQuiz: Bool
    var id: String { "\(unit.n)-\(lesson?.n ?? 0)-\(isQuiz)" }
}

struct LessonView: View {
    let model: AppModel
    let run: LessonRun
    let close: () -> Void
    @State private var index = 0
    @State private var right = 0
    @State private var answered: Bool?
    @State private var finished = false
    @State private var pack: PracticePack?
    @State private var packNote: String?
    @State private var buddy = BuddyModel()
    @State private var streak = 0
    @State private var arcade: [ArcadeID] = []
    @State private var playingArcade: ArcadeID?
    private let record = CourseRecord.shared

    var body: some View {
        ZStack {
            CandleGround()
            VStack(spacing: 18) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Candle.ink).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close the lesson")
                    ProgressView(value: Double(index), total: Double(max(1, run.exercises.count))).tint(Candle.gold)
                    Text("\(min(index + 1, run.exercises.count)) / \(run.exercises.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Candle.ink.opacity(0.6))
                }
                if finished { done } else if index < run.exercises.count { exercise(run.exercises[index]) }
                Spacer(minLength: 0)
                // his ruling 11-15: Buddy lives down in the empty space under the exercise (never over it), as large as the room left
                // allows; a tap plays his next move
                Button { buddy.playNext() } label: { BuddyView(model: buddy).aspectRatio(590 / 663, contentMode: .fit).frame(maxWidth: 220, maxHeight: 240) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(-1)
                    .accessibilityHint("Tap for his next move")
            }
            .padding(20).frame(maxWidth: 640)
        }
        .preferredColorScheme(.dark)
        // his ask 11-15: Buddy watches your moves; every touch on the lesson tells his eyes where to look (never takes the touch)
        .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { buddy.look($0.location) })
        .sensoryFeedback(PLHaptic.success, trigger: right)
        .sensoryFeedback(PLHaptic.warning, trigger: answered == false)
        .onAppear { buddy.react(.open) }
        .task(id: index) {
            // Gemini: "think" once, after a reading pause of 8-12 s, never looped
            try? await Task.sleep(for: .seconds(10))
            if answered == nil, !finished { buddy.react(.reading) }
        }
        .task(id: finished) {
            // a finished lesson earns one card of his art; the Worker keeps one per lesson, so a replay shows the same card
            guard finished, !run.isQuiz, let l = run.lesson, pack == nil else { return }
            do { pack = try await Packs.open("lesson-\(run.unit.n)-\(l.n)", model: model) }
            catch { packNote = "Could not reach the practice, so no card was dealt. Play the lesson again when you are online and it will be." }
            // his ruling: an unlocked arcade game is offered as a break after the lesson
            if let c = await PracticeCards.load(model: model) { arcade = (c.games ?? []).compactMap(ArcadeID.init(rawValue:)) }
        }
        .fullScreenCover(item: $playingArcade) { g in
            GameShell(title: g.title) { playingArcade = nil } content: { arcadeGame(g, seeds: []) }
        }
    }

    @ViewBuilder private func exercise(_ e: CourseExercise) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(e.prompt).font(.system(size: 13)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
            ExerciseBody(exercise: e, locked: answered != nil) { ok in
                answered = ok
                if ok { right += 1; streak += 1; buddy.react(streak % 3 == 0 ? .streak : .right); Task { await BuddyIsland.show("open", "Right.") } }
                else { record.miss(e.item); streak = 0; buddy.react(.wrong); Task { await BuddyIsland.show("clench", "It comes back later.") } }
                PracticeSound.play(ok ? .right : .wrong)   // his picks by ear 11-15
            }
            .id(e.id + "\(index)")
            if let answered {
                VStack(alignment: .leading, spacing: 8) {
                    Text(answered ? "Right." : "Not this time. It comes back later.").font(.system(size: 15, weight: .medium)).foregroundStyle(answered ? Candle.goldHi : Candle.ink)
                    if !answered, let a = shown(e) { Text(a).font(.system(size: 14)).foregroundStyle(Candle.ink) }
                    if let why = e.why { Text(why).font(.system(size: 14, design: .serif).italic()).foregroundStyle(Candle.goldHi).lineSpacing(3) }
                    Button(index + 1 < run.exercises.count ? "Continue" : "Finish") { advance() }.buttonStyle(CandleButton())
                }
                .candleCard()
            }
        }
    }

    private func shown(_ e: CourseExercise) -> String? {
        guard let a = e.answer else { return nil }
        switch a {
        case .number(let n): return "The \(["", "First", "Second", "Third"][max(0, min(3, n))]) Truth."
        case .text(let s): return s
        case .list(let l): return l.isEmpty ? "Nothing to tap: the passage is clean." : l.joined(separator: " \u{00b7} ")
        }
    }

    private func advance() {
        answered = nil
        if index + 1 < run.exercises.count { index += 1; return }
        // a lesson counts once it is played through; the quiz passes at four in five (or all, when it is shorter)
        if run.isQuiz { if right >= max(1, run.exercises.count - 1) { record.passQuiz(run.unit.n) } }
        else if let l = run.lesson { record.finish(unit: run.unit.n, lesson: l.n); BuddyIsland.lessonDone() }
        finished = true
        PracticeSound.play(.done)
        buddy.react(.finish)
    }

    private var done: some View {
        let passed = !run.isQuiz || right >= max(1, run.exercises.count - 1)
        return VStack(spacing: 14) {
            Text(run.isQuiz ? (passed ? "Quiz passed." : "Not yet. Take it again when you like.") : "Lesson done.")
                .plHand(26, relativeTo: .title).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
            Text("\(right) of \(run.exercises.count) right").candleHint()
            if let pack { PackOpening(model: model, cards: pack.cards, animate: pack.new).frame(height: 380) }
            else if let packNote { Text(packNote).candleHint().multilineTextAlignment(.center) }
            if let g = arcade.randomElement() { Button("Take a break: \(g.title)") { playingArcade = g }.buttonStyle(CandleGhost()) }
            Button("Back to the path") { close() }.buttonStyle(CandleButton())
        }
        .frame(maxWidth: .infinity).padding(.top, 20)
    }
}

// MARK: - the exercise kinds (each one a snippet of a game)

struct ExerciseBody: View {
    let exercise: CourseExercise
    let locked: Bool
    let answer: (Bool) -> Void

    var body: some View {
        switch exercise.kind {
        case "which-truth":
            OptionExercise(text: exercise.text, options: ["1 \u{00b7} Prepared for luxury", "2 \u{00b7} You are in control of your reality", "3 \u{00b7} What persists in the mind becomes your reality"],
                           correct: (Int(exercise.answer?.string ?? "") ?? 1) - 1, locked: locked, answer: answer)
        case "complete-phrase", "match-glyph", "choose":
            let opts = exercise.options ?? []
            OptionExercise(text: exercise.text ?? exercise.glyph, options: opts, correct: opts.firstIndex(of: exercise.answer?.string ?? "") ?? -1, locked: locked, answer: answer)
        case "order-truths":
            TileExercise(shownFirst: nil, target: exercise.answer?.strings ?? [], separator: "\n", locked: locked, answer: answer)
        case "rebuild-phrase":
            TileExercise(shownFirst: nil, target: (exercise.answer?.string ?? "").split(separator: " ").map(String.init), separator: " ", locked: locked, answer: answer)
        case "recall-phrase":
            TileExercise(shownFirst: exercise.answer?.string, target: (exercise.answer?.string ?? "").split(separator: " ").map(String.init), separator: " ", locked: locked, answer: answer)
        case "find-banned-word":
            BannedWordExercise(text: exercise.text ?? "", banned: exercise.answer?.strings ?? [], locked: locked, answer: answer)
        case "rewrite":
            RewriteExercise(original: exercise.text ?? "", locked: locked, answer: answer)
        case "say-it":
            SayItExercise(target: exercise.answer?.string ?? exercise.text ?? "", locked: locked, answer: answer)
        case "draw-it":
            DrawItExercise(glyphName: exercise.glyph ?? "", locked: locked, answer: answer)
        default:
            ReflectExercise(text: exercise.text ?? "", locked: locked, answer: answer)
        }
    }
}

/// Pick one of the answers (which Truth, the missing word, the glyph's meaning).
struct OptionExercise: View {
    let text: String?
    let options: [String]
    let correct: Int
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text { Text(text).font(.system(size: 19)).foregroundStyle(Candle.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { guard !locked else { return }; picked = i; answer(i == correct) } label: {
                    Text(o).font(.system(size: 15)).foregroundStyle(Candle.ink).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 6)
                        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(line(i), lineWidth: locked && i == correct ? 2 : 1) }
                }
                .buttonStyle(.plain).disabled(locked)
            }
        }
    }
    private func line(_ i: Int) -> Color {
        guard locked else { return Candle.pillLine }
        if i == correct { return Candle.gold }
        return i == picked ? Candle.ink.opacity(0.6) : Candle.pillLine
    }
}

/// Put the pieces back in order (a seed word by word, the three Truths). With `shownFirst`, read it, hide it, then rebuild it.
struct TileExercise: View {
    let shownFirst: String?
    let target: [String]
    let separator: String
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var pool: [(id: Int, word: String)] = []
    @State private var built: [(id: Int, word: String)] = []
    @State private var hidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let shownFirst, !hidden {
                Text(shownFirst).font(.system(size: 20)).foregroundStyle(Candle.goldHi).lineSpacing(4)
                Button("Hide it") { hidden = true }.buttonStyle(CandleGhost())
            } else {
                Text(built.isEmpty ? "Tap the pieces in order." : built.map(\.word).joined(separator: separator))
                    .font(.system(size: 19)).foregroundStyle(built.isEmpty ? Candle.ink.opacity(0.4) : Candle.ink).lineSpacing(4)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading).padding(12)
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Candle.fieldLine, lineWidth: 1) }
                PracticeFlow(spacing: 8) {
                    ForEach(pool, id: \.id) { t in
                        Button(t.word) { guard !locked else { return }; built.append(t); pool.removeAll { $0.id == t.id }; check() }.buttonStyle(CandleGhost())
                    }
                }
                if !built.isEmpty && !locked { Button("Undo") { if let l = built.popLast() { pool.append(l) } }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Candle.ink.opacity(0.6)).frame(minHeight: 44) }
            }
        }
        .onAppear { if pool.isEmpty && built.isEmpty { pool = Array(target.enumerated()).map { (id: $0.offset, word: $0.element) }.shuffled() } }
    }
    private func check() { if pool.isEmpty { answer(built.map(\.word) == target) } }
}

/// The Purge: tap every word the house never says, then check. A clean passage has none.
struct BannedWordExercise: View {
    let text: String
    let banned: [String]
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var picked: Set<Int> = []
    private var words: [String] { text.split(separator: " ").map(String.init) }
    private func bare(_ w: String) -> String { w.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PracticeFlow(spacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    Button { guard !locked else { return }; if picked.contains(i) { picked.remove(i) } else { picked.insert(i) } } label: {
                        Text(w).font(.system(size: 17)).foregroundStyle(picked.contains(i) ? Color.black : Candle.ink)
                            .padding(.horizontal, 6).frame(minHeight: 44)
                            .background(picked.contains(i) ? Candle.gold : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !locked { Button(picked.isEmpty ? "It is clean" : "Check") { check() }.buttonStyle(CandleButton()) }
        }
    }
    private func check() {
        let want = Set(banned.flatMap { $0.lowercased().split(separator: " ").map(String.init) })
        let got = Set(picked.map { bare(words[$0]) })
        answer(got == want)
    }
}

/// A doctrine question to sit with: one written line completes it. Nothing is graded and nothing leaves the phone.
struct ReflectExercise: View {
    let text: String
    let locked: Bool
    let answer: (Bool) -> Void
    @State private var line = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.system(size: 19)).foregroundStyle(Candle.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            PField(prompt: "One line.", text: $line, lines: 3)
            if !locked { Button("Done") { answer(true) }.buttonStyle(CandleButton()).disabled(line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }
}

/// Words that wrap onto the next line.
struct PracticeFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}
