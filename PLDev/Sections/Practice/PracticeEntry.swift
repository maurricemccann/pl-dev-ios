import SwiftUI

/// "It speaks first" (the web's speak-first entry, Phase 5 step 1): nothing on the screen but the line. One tap draws a line that has
/// his own recorded clip (never the same one twice running), shows it, plays it, and the practice fades in when the clip ends.
/// A second tap skips. Tap-to-speak on purpose: iOS will not play audio without a gesture. Only existing clips play; with none, the
/// line shows for four seconds, in text.
struct PracticeEntry: View {
    let model: AppModel
    let state: PracticeModel
    private enum Phase { case idle, speaking, done }
    @State private var phase: Phase = .idle
    @State private var line = ""
    @State private var hint = "touch to hear today\u{2019}s line"
    @State private var items: [PracticeAffirmation] = []
    private let clips = PracticeClips.shared

    var body: some View {
        ZStack {
            Candle.bg.ignoresSafeArea()
            VStack(spacing: 32) {
                Text(line).plHand(26, relativeTo: .title).foregroundStyle(Candle.goldHi).multilineTextAlignment(.center)
                    .frame(maxWidth: 320).fixedSize(horizontal: false, vertical: true).animation(.easeIn(duration: 0.4), value: line)
                Text(hint).font(.system(size: 13.6)).tracking(0.8).foregroundStyle(Candle.ink.opacity(0.45))
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await speak() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hear today\u{2019}s line").accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await speak() } }
        .task { if let l = try? await Practice.get("affirmations", PracticeAffirmations.self, model: model) { items = l.items; PracticeDeck.cache(l.items) } }
    }

    private func close() {
        guard phase != .done else { return }
        phase = .done
        clips.stop()
        withAnimation(.easeOut(duration: 0.6)) { state.entryDone = true }
    }

    private func pick() -> PracticeAffirmation? {
        let voiced = items.filter { $0.audio != nil }
        let pool = voiced.isEmpty ? items : voiced
        guard !pool.isEmpty else { return nil }
        let last = UserDefaults.standard.string(forKey: "practice.entry.last")
        let choices = pool.count > 1 ? pool.filter { $0.key != last } : pool
        let a = choices.randomElement()
        if let a { UserDefaults.standard.set(a.key, forKey: "practice.entry.last") }
        return a
    }

    private func speak() async {
        guard phase == .idle else { return close() }
        phase = .speaking
        if items.isEmpty, let l = try? await Practice.get("affirmations", PracticeAffirmations.self, model: model) { items = l.items }
        guard let a = pick() else { return close() }
        line = a.text; hint = ""
        guard let audio = a.audio else { try? await Task.sleep(for: .seconds(4)); return close() }
        if await clips.toggle(a.key, path: audio, model: model) != nil { try? await Task.sleep(for: .seconds(4)); return close() }
        clips.onFinish = { Task { try? await Task.sleep(for: .seconds(1.2)); close() } }
    }
}
