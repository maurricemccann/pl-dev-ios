import SwiftUI

// The notes Capture writes into (his ask 11-17: "above Already sorted I should see a view of the obsidian notes that capture uses").
// Read-only, from the house board's api/note (the same door the House's Jarvis view opens reports with). Newest lines first.

struct CaptureNotesBlock: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var texts: [String: String] = [:]
    @State private var failed = false
    @State private var open: Note?

    struct Note: Identifiable, Hashable { let id: String; let title: String; let what: String }
    static let notes = [Note(id: "THOUGHTS.md", title: "Thoughts", what: "Thoughts and tasks, for every session to read"),
                        Note(id: "TODAY.md", title: "Today", what: "Today's list on the board"),
                        Note(id: "for-claude.md", title: "For Claude", what: "The inbox every session reads first")]

    var body: some View {
        Text("Your notes").osEyebrow(10).foregroundStyle(PLOS.dim(scheme)).captureRow()
        VStack(spacing: 0) {
            ForEach(Array(Self.notes.enumerated()), id: \.element.id) { i, n in
                if i > 0 { Divider().overlay(PLOS.dim(scheme).opacity(0.25)) }
                Button { open = n } label: { row(n) }.buttonStyle(.plain)
            }
        }
        .osCard(padding: 12).captureRow()
        .task { await load() }
        .sheet(item: $open) { n in CaptureNoteSheet(note: n, lines: Self.newestFirst(texts[n.id] ?? "")) }
    }

    private func row(_ n: Note) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title).font(Font.pl(size: 16, weight: .semibold)).foregroundStyle(PLOS.text(scheme))
                Text(preview(n)).font(Font.pl(size: 13)).foregroundStyle(PLOS.dim(scheme)).lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(Font.pl(size: 13, weight: .semibold)).foregroundStyle(PLOS.dim(scheme))
        }
        .frame(minHeight: 52).contentShape(Rectangle())
        .accessibilityElement(children: .combine).accessibilityHint("Opens the note")
    }

    private func preview(_ n: Note) -> String {
        if let t = texts[n.id] { return Self.newestFirst(t).first ?? "Empty" }
        return failed ? "Opens when the house board is reachable" : n.what
    }

    private func load() async {
        guard let http = model.http else { failed = true; return }
        var got: [String: String] = [:]
        for n in Self.notes {
            if let d = try? await http.send(RequestPlan(origin: "board", path: "api/note", query: ["f": n.id]), timeout: 15, cache: false),
               let t = String(data: d, encoding: .utf8) { got[n.id] = t }
        }
        texts = got
        failed = got.isEmpty
    }

    /// The last lines a capture appended come first. Frontmatter, rules and blank lines are left out; at most 200 lines.
    static func newestFirst(_ text: String) -> [String] {
        var lines = text.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }
        return Array(lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "---" }.suffix(200).reversed())
    }
}

struct CaptureNoteSheet: View {
    let note: CaptureNotesBlock.Note
    let lines: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(note.what + ". Newest first.").font(Font.pl(size: 13)).foregroundStyle(PLOS.dim(scheme))
                    if lines.isEmpty { Text("Nothing in this note yet.").foregroundStyle(PLOS.dim(scheme)) }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text((try? AttributedString(markdown: l)) ?? AttributedString(l)).font(Font.pl(size: 15)).foregroundStyle(PLOS.text(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .navigationTitle(note.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
