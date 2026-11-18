import SwiftUI

/// One unit's fields on the Path. Only the chapter holding his next lesson is drawn; the rest of the unit opens on tap
/// (Codex review 11-17: every unit drew every chapter at once, 41 animated fields for 216 lessons).
struct PathUnitFields: View {
    let unit: CourseUnit
    let open: Bool
    /// The lesson number of his next lesson when it is in this unit.
    let focus: Int?
    let play: (CourseLesson) -> Void
    @State private var all = false

    var body: some View {
        let chapters = PracticeChapter.of(unit)
        let shown = all ? chapters : chapters.filter { ch in focus.map { n in ch.lessons.contains { $0.n == n } } ?? false }
        ForEach(shown) { ch in PracticeField(unit: unit, chapter: ch, open: open, play: play) }
        if chapters.count > shown.count || all, chapters.count > 1 {
            Button(all ? "Show less" : "All \(chapters.count) chapters") { withAnimation(.snappy) { all.toggle() } }
                .buttonStyle(CandleGhost())
                .frame(minHeight: 44)
        }
    }
}
