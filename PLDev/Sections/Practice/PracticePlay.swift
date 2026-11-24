import SwiftUI

// Phase 5 (S349, the practice spec): two ways to play, fed only from the course file and only from lessons he has already played,
// so nothing here teaches ahead of the reading. Match pairs: glyph to meaning (the course's `match-glyph` items).
// Sort cards: a scenario to the Truth it belongs to (the course's `which-truth` items). Neither is ever shown as a score or a debt;
// a miss comes back later on the review schedule, the same as in a lesson.

enum PracticePlayKind: String, Identifiable { case pairs, sort; var id: String { rawValue } }

struct PracticePlayRun: Identifiable {
    let kind: PracticePlayKind
    let exercises: [CourseExercise]
    var id: String { kind.rawValue }
}

@MainActor enum PracticePlayDeck {
    /// Exercises of one kind from lessons he has finished, one per item, shuffled.
    private static func met(_ kind: String, in course: Course) -> [CourseExercise] {
        let record = CourseRecord.shared
        var seen = Set<String>()
        return course.units.flatMap { u in u.lessons.filter { record.isDone(u.n, $0.n) }.flatMap(\.exercises) }
            .filter { $0.kind == kind && $0.isPlayable && seen.insert($0.item).inserted }.shuffled()
    }
    static func pairs(in course: Course) -> PracticePlayRun? {
        let e = met("match-glyph", in: course).filter { $0.glyph != nil && $0.answer?.string.isEmpty == false }
        return e.count >= 3 ? PracticePlayRun(kind: .pairs, exercises: Array(e.prefix(4))) : nil
    }
    static func sort(in course: Course) -> PracticePlayRun? {
        let e = met("which-truth", in: course).filter { $0.text != nil && $0.answer != nil }
        return e.count >= 3 ? PracticePlayRun(kind: .sort, exercises: Array(e.prefix(5))) : nil
    }
}

/// The Path's play card: a button for each way that has material. Absent when neither does.
struct PracticePlayCard: View {
    let course: Course
    let start: (PracticePlayRun) -> Void
    var body: some View {
        let pairs = PracticePlayDeck.pairs(in: course), sort = PracticePlayDeck.sort(in: course)
        if pairs != nil || sort != nil {
            PCard(title: "Play", hint: "From the lessons you have played.") {
                HStack(spacing: 8) {
                    if let pairs { Button("Match pairs") { start(pairs) }.buttonStyle(CandleGhost()).frame(minHeight: 44) }
                    if let sort { Button("Sort cards") { start(sort) }.buttonStyle(CandleGhost()).frame(minHeight: 44) }
                }
            }
        }
    }
}

struct PracticePlayView: View {
    let run: PracticePlayRun
    let close: () -> Void
    var body: some View {
        ZStack {
            CandleGround()
            VStack(spacing: 16) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(Font.pl(size: 15, weight: .medium)).foregroundStyle(Candle.ink).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close")
                    Spacer()
                    Text(run.kind == .pairs ? "Match pairs" : "Sort cards").font(Font.pl(size: 13)).textCase(.uppercase).tracking(1).foregroundStyle(Candle.gold)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                if run.kind == .pairs { MatchPairsBoard(exercises: run.exercises, close: close) } else { SortCardsBoard(exercises: run.exercises, close: close) }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: 640)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - match pairs

struct MatchPairsBoard: View {
    let exercises: [CourseExercise]
    let close: () -> Void
    @State private var rights: [Int] = []
    @State private var left: Int?
    @State private var matched: Set<Int> = []
    @State private var missed: Set<Int> = []
    @State private var recorded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tap a glyph, then what it means.").candleHint()
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) { ForEach(exercises.indices, id: \.self) { i in tile(exercises[i].glyph ?? "", id: i, isLeft: true) } }
                    VStack(spacing: 10) { ForEach(rights, id: \.self) { i in tile(exercises[i].answer?.string ?? "", id: i, isLeft: false) } }
                }
                if matched.count == exercises.count {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Every pair is home.").font(Font.pl(size: 15, weight: .medium)).foregroundStyle(Candle.goldHi)
                        Button("Done") { close() }.buttonStyle(CandleButton())
                    }.candleCard()
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { if rights.isEmpty { rights = Array(exercises.indices).shuffled() } }
        .sensoryFeedback(.selection, trigger: left)
        .sensoryFeedback(PLHaptic.success, trigger: matched.count)
        .onChange(of: matched.count) { _, n in
            guard n == exercises.count, !recorded else { return }
            recorded = true; PracticeSound.play(.done)
            for (i, e) in exercises.enumerated() { SpacedReview.record(e.item, right: !missed.contains(i)) }
        }
    }

    private func tile(_ text: String, id: Int, isLeft: Bool) -> some View {
        let done = matched.contains(id), picked = isLeft && left == id
        return Button {
            guard !done else { return }
            if isLeft { withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { left = left == id ? nil : id }; return }
            guard let l = left else { return }
            if l == id { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { _ = matched.insert(id) }; PracticeSound.play(.right) }
            else { missed.insert(l); CourseRecord.shared.miss(exercises[l].item) }
            left = nil
        } label: {
            Text(text).font(Font.pl(size: 15, weight: done ? .semibold : .regular)).foregroundStyle(done ? Candle.bg : Candle.ink).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
                .background { RoundedRectangle(cornerRadius: 14 * PLStyle.radius, style: .continuous).fill(done ? Candle.gold : Candle.ink.opacity(picked ? 0.12 : 0.03)) }
                .overlay { RoundedRectangle(cornerRadius: 14 * PLStyle.radius, style: .continuous).strokeBorder(picked ? Candle.gold : Candle.pillLine, lineWidth: picked ? 2 : 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(done)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: - sort cards

struct SortCardsBoard: View {
    let exercises: [CourseExercise]
    let close: () -> Void
    private static let truths = ["Prepared for luxury", "You are in control of your reality", "What persists in the mind becomes your reality"]
    @State private var index = 0
    @State private var picked: Int?
    @State private var finished = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if finished {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Every card is placed.").font(Font.pl(size: 15, weight: .medium)).foregroundStyle(Candle.goldHi)
                        Button("Done") { close() }.buttonStyle(CandleButton())
                    }.candleCard()
                } else {
                    let e = exercises[index], correct = (Int(e.answer?.string ?? "") ?? 1) - 1
                    Text("Card \(index + 1) of \(exercises.count). Which Truth does it belong to?").candleHint()
                    Text(e.text ?? "").font(Font.pl(size: 19)).foregroundStyle(Candle.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).candleCard(padding: 18)
                    ForEach(Self.truths.indices, id: \.self) { i in
                        let shown = picked != nil && i == correct
                        Button { place(i, correct: correct, e) } label: {
                            Text("\(i + 1) \u{00b7} \(Self.truths[i])").font(Font.pl(size: 16, weight: shown ? .semibold : .regular))
                                .foregroundStyle(shown ? Candle.bg : Candle.ink).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
                                .background { RoundedRectangle(cornerRadius: 14 * PLStyle.radius, style: .continuous).fill(shown ? Candle.gold : Candle.ink.opacity(i == picked ? 0.1 : 0.03)) }
                                .overlay { RoundedRectangle(cornerRadius: 14 * PLStyle.radius, style: .continuous).strokeBorder(shown ? Candle.gold : Candle.pillLine, lineWidth: 1) }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(picked != nil)
                    }
                    if let picked {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(picked == correct ? "Right." : "Not this one. It comes back later.").font(Font.pl(size: 15, weight: .medium)).foregroundStyle(picked == correct ? Candle.goldHi : Candle.ink)
                            if let why = e.why { Text(why).font(Font.pl(size: 14, design: .serif).italic()).foregroundStyle(Candle.goldHi).lineSpacing(3) }
                            Button(index + 1 < exercises.count ? "Next card" : "Finish") { next() }.buttonStyle(CandleButton())
                        }.candleCard()
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: picked)
    }

    private func place(_ i: Int, correct: Int, _ e: CourseExercise) {
        guard picked == nil else { return }
        picked = i
        let ok = i == correct
        if !ok { CourseRecord.shared.miss(e.item) }
        SpacedReview.record(e.item, right: ok)
        PracticeSound.play(ok ? .right : .wrong)
    }
    private func next() {
        picked = nil
        if index + 1 < exercises.count { index += 1 } else { finished = true; PracticeSound.play(.done) }
    }
}
