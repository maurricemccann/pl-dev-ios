import SwiftUI

/// One passage a lesson tests, word for word from the canon (course.json `read`, S349).
struct CourseRead: Decodable, Sendable, Hashable {
    let text: String
    let source: String
    let from: String?
}

/// His ruling 11-17: "the path doesn't open until you're prepared and have read all the passages so you're not just guessing."
/// Every lesson opens on the passages its exercises test. The way on sits after the last one, so reaching it means reading through.
struct LessonReadStep: View {
    let passages: [CourseRead]
    let onReady: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Read first").font(Font.pl(size: 12, weight: .medium)).textCase(.uppercase).tracking(1.2).foregroundStyle(Candle.gold)
                ForEach(Array(passages.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(p.text).font(Font.pl(size: 19, design: .serif)).foregroundStyle(Candle.ink).plReading().textSelection(.enabled)
                        Text(p.from ?? "The canon").font(Font.pl(size: 12)).foregroundStyle(Candle.ink.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) { Rectangle().fill(Candle.gold.opacity(0.5)).frame(width: 2) }
                }
                Button("I have read it") { onReady() }.buttonStyle(CandleButton()).padding(.top, 8)
                    .accessibilityHint("Starts the lesson")
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}
