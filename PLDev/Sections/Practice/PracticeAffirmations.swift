import SwiftUI
import UserNotifications

// The Affirmations card (the web's "Affirmations — the founder's voice") and the controls it needs.

// MARK: - The audio player (the web's `<audio controls>`)

/// A play button, a thin progress bar you can drag, and "0:00 / 0:00". Plays only the clip it is given.
struct PracticePlayer: View {
    let key: String
    let path: String
    let model: AppModel
    var onError: (String?) -> Void = { _ in }
    private let clips = PracticeClips.shared
    @State private var dragging: Double?

    private func clock(_ t: TimeInterval) -> String { "\(Int(t) / 60):" + String(format: "%02d", Int(t) % 60) }

    var body: some View {
        let on = clips.playing == key
        HStack(spacing: 10) {
            Button { Task { onError(await clips.toggle(key, path: path, model: model)) } } label: {
                Image(systemName: on ? "pause.fill" : "play.fill").font(.system(size: 16)).foregroundStyle(Candle.bg)
                    .frame(width: 36, height: 36).background(Candle.gold, in: Circle()).contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).accessibilityLabel(on ? "Pause" : "Play this line")
            TimelineView(.animation(minimumInterval: 0.25, paused: !on)) { _ in
                let len = max(clips.length, 0.01), pos = on ? clips.position : 0
                HStack(spacing: 10) {
                    Text("\(clock(dragging.map { $0 * len } ?? pos)) / \(clock(on ? clips.length : 0))")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Candle.ink.opacity(0.75))
                    Slider(value: Binding(get: { dragging ?? (on ? pos / len : 0) }, set: { dragging = $0 }), in: 0...1) { editing in
                        if !editing, let d = dragging { clips.seek(to: d * len); dragging = nil }
                    }
                    .tint(Candle.gold).disabled(!on)
                }
            }
        }
        .padding(.horizontal, 10).frame(minHeight: 48)
        .background(Candle.ink.opacity(0.1), in: Capsule())
    }
}

// MARK: - Wrapping pills (`flex-wrap`)

struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Affirmations: the founder's voice

/// The day's line (the same one all day, a new one tomorrow), "another" from a shuffled deck, the library, his own lines and
/// his own live recordings. A clip plays only where it already exists in his voice; with none, the line says "voice not recorded yet".
struct AffirmationsCard: View {
    let model: AppModel
    let state: PracticeModel
    @State private var items: [PracticeAffirmation] = []
    @State private var line: PracticeAffirmation?
    @State private var browsing = false
    @State private var own = false
    @State private var text = ""
    @State private var result: String?
    @State private var failed = false
    @State private var lastOwn: String?
    @State private var lastTake: (String, Data)?
    @State private var recorder = PracticeRecorder()
    @State private var denied = false
    @AppStorage("practice.remind") private var remind = true

    private func word(_ a: PracticeAffirmation) -> String { a.text + (a.mine ? "  \u{2014} yours" : "") }

    var body: some View {
        PCard(title: "Affirmations \u{2014} the founder\u{2019}s voice", id: "affirmations") {
            VStack(alignment: .leading, spacing: 8) {
                if let line {
                    Text(word(line)).plHand(21, relativeTo: .title3).foregroundStyle(Candle.ink).lineSpacing(4).textSelection(.enabled)
                    if let audio = line.audio { PracticePlayer(key: line.key, path: audio, model: model) { result = $0 } }
                    else { Text("voice not recorded yet \u{2014} text only").font(.system(size: 12)).foregroundStyle(Candle.ink.opacity(0.5)) }
                } else if failed { Text(PracticeWords.loadFailed("the lines")).candleHint() }
                else { Text("\u{2026}").candleHint() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            WrapLayout(spacing: 6) {
                Button("another") { shuffle() }.buttonStyle(CandleGhost())
                Button("browse the library") { withAnimation(.snappy) { browsing.toggle() } }.buttonStyle(CandleGhost())
                if !remind || denied { Button("send me tonight\u{2019}s line at \(Date.pl(hour: PracticeNotice.hour))") { Task { await arm() } }.buttonStyle(CandleGhost()) }
            }
            if denied { Text("notifications are off for PL DEV in Settings").candleHint() }
            else if remind { Text("tonight\u{2019}s line arrives at \(Date.pl(hour: PracticeNotice.hour))").candleHint() }
            if browsing {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { a in
                            CandleRule()
                            Button { line = a; withAnimation(.snappy) { browsing = false } } label: {
                                Text(a.text + (a.audio != nil ? " \u{25B8}" : "") + (a.mine ? " \u{00B7} yours" : ""))
                                    .plHand(19, relativeTo: .body).foregroundStyle(a.mine ? Candle.goldHi : Candle.ink.opacity(0.85))   // his words in his hand (his rule 11-13)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 256)
            }
            PDetails(summary: "+ write your own", open: $own) {
                PField(prompt: "Your line \u{2014} present tense, already true.", text: $text, lines: 2)
                HStack { Button("Keep it") { Task { await add() } }.buttonStyle(CandleButton()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Spacer(minLength: 0) }
                if let target = lastOwn ?? (line?.mine == true ? line?.key : nil), PracticeRecorder.available {
                    HStack(spacing: 8) {
                        Button(recorder.recordingKey == target ? "\u{25A0} stop" : "\u{25CF} record it in your voice") { Task { await record(target) } }.buttonStyle(CandleGhost())
                        if lastTake != nil { Button("send it again") { Task { await resend() } }.buttonStyle(CandleGhost()) }
                    }
                }
            }
            CandleResult(text: result)
        }
        .task(id: state.reload) { await load() }
        .onDisappear { PracticeClips.shared.stop() }
    }

    private func load() async {
        do {
            let l = try await Practice.get("affirmations", PracticeAffirmations.self, model: model)
            items = l.items; PracticeDeck.cache(l.items); failed = false
            // the day's line: the same all day, changes tomorrow (web: dayNum % count)
            if line == nil, !items.isEmpty { line = items[Int(Date().timeIntervalSince1970 / 86400) % items.count] }
        } catch { failed = true }
    }

    private func shuffle() {
        PracticeClips.shared.stop()
        guard let k = PracticeDeck.next(of: items.map(\.key)) else { return }
        withAnimation(.snappy) { line = items.first { $0.key == k } }
    }

    private func add() async {
        do {
            struct Row: Decodable { let id: String?; let text: String? }
            let d = try await Practice.post("custom-affirmations", ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)], model: model)
            let row = try? JSONDecoder().decode(Row.self, from: d)
            text = ""; result = PracticeRecorder.available ? "saved \u{2014} record it if you want it in your voice" : "Saved."; state.tick += 1
            await load()
            if let id = row?.id { lastOwn = "c-\(id)"; line = items.first { $0.key == "c-\(id)" } ?? line }
        } catch { result = error.localizedDescription }
    }

    private func resend() async {
        guard let (key, bytes) = lastTake else { return }
        let id = key.hasPrefix("c-") ? String(key.dropFirst(2)) : key
        do {
            try await Practice.upload("affirmation-audio", bytes, type: "audio/mp4", model: model, query: ["id": id])
            lastTake = nil; recorder.discard(); result = "recorded \u{2014} it plays in your voice now"; await load()
        } catch { result = "upload failed \u{2014} your take is kept, try again" }
    }

    /// Tap to start, tap again to save. The recording is his live voice on his phone, sent as it is.
    private func record(_ key: String) async {
        if recorder.recordingKey == key {
            guard let bytes = recorder.stop() else { result = "Nothing was recorded."; return }
            let id = key.hasPrefix("c-") ? String(key.dropFirst(2)) : key
            result = "uploading\u{2026}"
            do {
                try await Practice.upload("affirmation-audio", bytes, type: "audio/mp4", model: model, query: ["id": id])
                recorder.discard(); result = "recorded \u{2014} it plays in your voice now"; await load()
            } catch { lastTake = (key, bytes); result = "upload failed \u{2014} your take is kept, try again" }
        } else if let why = await recorder.start(key) { result = why } else { result = "recording\u{2026}" }
    }

    /// The web's "send me tonight's line": on the phone the evening line is a local notice at his hour.
    private func arm() async {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        denied = !ok
        if ok { remind = true; await PracticeNotice.reschedule(model: model) }
    }
}
