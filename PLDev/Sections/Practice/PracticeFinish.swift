import SwiftUI

/// The lesson-complete moment, as the council specified it 11-17 (Gemini second pass, Codex agreeing on restraint):
/// no invented numbers, no hype. What was kept, which Truth it serves, one sentence from the lesson's own reading.
struct LessonFinishCard: View {
    let unit: CourseUnit
    let lesson: CourseLesson
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private static let truths = ["Prepared for luxury", "You are in control of your reality", "What persists in the mind becomes your reality"]
    private var anchor: String { (1...3).contains(unit.n) ? "Truth \(unit.n) \u{00b7} \(Self.truths[unit.n - 1])" : unit.title }

    var body: some View {
        VStack(spacing: 10) {
            Text("Lesson complete").plHand(28, relativeTo: .title).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
            Text(anchor).font(Font.pl(.subheadline).weight(.medium)).foregroundStyle(Candle.gold).multilineTextAlignment(.center)
            if let line = lesson.read?.first?.text {
                Text(line).font(Font.pl(.callout, design: .serif)).foregroundStyle(Candle.ink).multilineTextAlignment(.center)
                    .lineLimit(3).lineSpacing(4).padding(.top, 6)
            }
            Rectangle().fill(Candle.ink.opacity(0.1)).frame(height: 1).padding(.top, 8)
            Text("Saved to your record").candleHint()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .candleCard(padding: 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
        .accessibilityElement(children: .combine)
    }
}
