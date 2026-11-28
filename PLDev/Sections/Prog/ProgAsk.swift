import SwiftUI

/// PL Prog Ask (S356·c41f, his ask 11-28: "can we use on device models or console model to answer any questions I have").
/// A question about the lesson on screen goes to the practice server (`POST /api/prog-ask`: Claude first, llama fallback); offline
/// or refused, the phone's own model answers and says so. The thread lives for this lesson while the sheet is open.
/// Spec: vault Plans/SPEC - PL PROG ASK (S356).
struct ProgAskSheet: View {
    let model: AppModel
    let lesson: ProgLesson
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [Turn] = []
    @State private var q = ""
    @State private var busy = false
    @FocusState private var typing: Bool

    struct Turn: Identifiable { let id = UUID(); let you: Bool; let text: String; var via: String = "" }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if turns.isEmpty {
                            Text("Ask anything about \(lesson.title): a word you don't know, a command that did something odd, what to type next.")
                                .font(Font.pl(.body)).foregroundStyle(.secondary)
                        }
                        ForEach(turns) { t in bubble(t).id(t.id) }
                        if busy { ProgressView().frame(maxWidth: .infinity).id("busy") }
                    }
                    .padding()
                }
                .onChange(of: turns.count) { _, _ in withAnimation { proxy.scrollTo(turns.last?.id, anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { typing = true }
    }

    private func bubble(_ t: Turn) -> some View {
        VStack(alignment: t.you ? .trailing : .leading, spacing: 4) {
            Text(Self.rich(t.text))
                .font(Font.pl(.body)).textSelection(.enabled)
                .padding(12)
                .background(t.you ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            if !t.via.isEmpty { Text(t.via).font(Font.pl(.caption)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: t.you ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Your question", text: $q, axis: .vertical)
                .lineLimit(1...4).focused($typing)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.send).onSubmit { Task { await send() } }
            Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(busy || q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send the question")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() async {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        let history = turns.suffix(6).map { ["you": $0.you, "text": $0.text] as [String: Any] }
        q = ""; busy = true; defer { busy = false }
        turns.append(Turn(you: true, text: question))
        let body: [String: Any] = ["question": question, "history": history,
                                   "lesson": ["title": lesson.title, "text": lesson.text, "run": lesson.run, "code": lesson.code]]
        do {
            let data = try await Practice.post("prog-ask", body, model: model, timeout: 90)
            let o = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let a = o["answer"] as? String, !a.isEmpty {
                let engine = (o["engine"] as? String) ?? ""
                turns.append(Turn(you: false, text: a, via: engine.hasPrefix("claude") ? "" : "answered by the backup model"))
                return
            }
        } catch {}
        // the server could not answer: the phone's own model, labelled, or a plain line
        let ctx = [lesson.title, lesson.text, lesson.run.joined(separator: "\n"), lesson.code].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if let a = await PLIntelligence.progAnswer(question: question, lesson: ctx) {
            turns.append(Turn(you: false, text: a, via: "phone's answer (offline)"))
        } else {
            turns.append(Turn(you: false, text: "No answer: the server could not be reached and Apple Intelligence is off on this phone. Try again on Wi-Fi."))
        }
    }

    /// Markdown from the answer (bold, `code`), keeping its line breaks and code blocks as plain lines.
    static func rich(_ s: String) -> AttributedString {
        let plain = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }   // fence lines read as noise; the command lines stay
            .joined(separator: "\n")
        return (try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(plain)
    }
}
