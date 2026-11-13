import AVFoundation
import SwiftUI

// The affirmations (his clips, played as they are) and the rehearsal (the breath, five senses, an intensity at the end).

// MARK: - A shuffled deck: no repeat until every line has been shown

enum PracticeDeck {
    /// Picks a key not shown yet; when all have been shown, the deck reshuffles. Kept on the phone.
    static func next(of keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        let store = UserDefaults.standard
        var shown = Set(store.stringArray(forKey: "practice.deck.shown") ?? []).intersection(keys)
        if shown.count >= keys.count { shown = [] }
        guard let pick = keys.filter({ !shown.contains($0) }).randomElement() else { return nil }
        shown.insert(pick)
        store.set(Array(shown), forKey: "practice.deck.shown")
        return pick
    }

    /// The lines kept for offline use (the evening notice reads from these).
    static func cache(_ items: [PracticeAffirmation]) {
        let pairs = items.map { ["k": $0.key, "t": $0.text] }
        if let d = try? JSONSerialization.data(withJSONObject: pairs) { UserDefaults.standard.set(d, forKey: "practice.lines") }
    }

    static func cached() -> [(key: String, text: String)] {
        guard let d = UserDefaults.standard.data(forKey: "practice.lines"),
              let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: String]] else { return [] }
        return a.compactMap { x in x["k"].flatMap { k in x["t"].map { (k, $0) } } }
    }
}

// MARK: - His own recording (live, on his phone, never generated)

@MainActor @Observable final class PracticeRecorder: NSObject {
    private(set) var recordingKey: String?
    private var recorder: AVAudioRecorder?
    private var file: URL?

    /// The microphone is offered only when the app declares why it needs it; a build without the line never asks.
    static var available: Bool { Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil }

    func start(_ key: String) async -> String? {
        guard Self.available else { return "This build has no microphone line yet." }
        guard await AVAudioApplication.requestRecordPermission() else { return "The microphone is off for PL DEV in Settings." }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("practice-\(UUID().uuidString).m4a")
            let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard r.record() else { return "Recording would not start." }
            recorder = r; file = url; recordingKey = key
            return nil
        } catch { return "Recording would not start. \(plainSentence(error))" }
    }

    /// Stops and returns the recording's bytes, then removes the file.
    func stop() -> Data? {
        recorder?.stop(); recorder = nil; recordingKey = nil
        defer { if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
        guard let file, let d = try? Data(contentsOf: file), !d.isEmpty else { return nil }
        return d
    }
}

// MARK: - Affirmations

struct AffirmationsView: View {
    let model: AppModel
    @State private var items: [PracticeAffirmation] = []
    @State private var search = ""
    @State private var text = ""
    @State private var result: String?
    @State private var loaded = false
    @State private var line: PracticeAffirmation?
    private let clips = PracticeClips.shared
    @State private var recorder = PracticeRecorder()

    private var mine: [PracticeAffirmation] { items.filter(\.mine) }
    private var library: [PracticeAffirmation] { items.filter { !$0.mine && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search)) } }

    var body: some View {
        List {
            if let line {
                Section {
                    Text(line.text).font(.title3).plReading().frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6).textSelection(.enabled)
                    HStack {
                        if line.audio != nil { playButton(line) }
                        Spacer()
                        Button("Another line", systemImage: "shuffle") { shuffle() }
                    }
                } header: { Text("A line for now") }
            }
            Section {
                TextField("A line in your own words", text: $text, axis: .vertical).lineLimit(1...4)
                Button("Add it") { Task { await add() } }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                ResultLine(text: result)
            } header: { Text("Yours") } footer: { Text("Your lines lead the list. You can record each in your own voice.") }
            if !mine.isEmpty { Section { ForEach(mine) { row($0) } } header: { Text("Your lines · \(mine.count)") } }
            if loaded && items.isEmpty { ContentUnavailableView("No lines loaded", systemImage: "quote.bubble", description: Text("Pull down to try again.")) }
            Section { ForEach(library) { row($0) } } header: { Text("Library · \(library.count)") } footer: { Text("A play button shows only where a clip in your voice exists. The rest are text.") }
        }
        .searchable(text: $search, prompt: "Search the lines")
        .navigationTitle("Affirmations").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onDisappear { clips.stop() }
    }

    private func row(_ a: PracticeAffirmation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(a.text).plReading().frame(maxWidth: .infinity, alignment: .leading)
            if a.audio != nil { playButton(a) }
            if a.mine {
                Button { Task { await record(a) } } label: {
                    Image(systemName: recorder.recordingKey == a.key ? "stop.circle.fill" : "mic.circle").font(.title2)
                        .foregroundStyle(recorder.recordingKey == a.key ? .red : Wallpaper.line)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.recordingKey == a.key ? "Stop and save the recording" : "Record this line in your voice")
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = a.text }
            Button("Show as the line for now", systemImage: "quote.bubble") { line = a }
        }
    }

    private func playButton(_ a: PracticeAffirmation) -> some View {
        Button {
            Task { result = await clips.toggle(a.key, path: a.audio ?? "", model: model) }
        } label: {
            Image(systemName: clips.playing == a.key ? "stop.circle.fill" : "play.circle.fill").font(.title2).foregroundStyle(Wallpaper.line)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clips.playing == a.key ? "Stop" : "Play this line")
    }

    private func load() async {
        if let l = try? await Practice.get("affirmations", PracticeAffirmations.self, model: model) {
            items = l.items; PracticeDeck.cache(l.items)
            if line == nil { shuffle() }
        }
        loaded = true
    }

    private func shuffle() {
        guard let k = PracticeDeck.next(of: items.map(\.key)) else { return }
        line = items.first { $0.key == k }
    }

    private func add() async {
        do { try await Practice.post("custom-affirmations", ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)], model: model); text = ""; result = "Added."; await load() }
        catch { result = error.localizedDescription }
    }

    /// Tap to start, tap again to save. The recording is his live voice, sent as it is.
    private func record(_ a: PracticeAffirmation) async {
        if recorder.recordingKey == a.key {
            guard let bytes = recorder.stop() else { result = "Nothing was recorded."; return }
            let id = a.key.hasPrefix("c-") ? String(a.key.dropFirst(2)) : a.key
            do { try await Practice.upload("affirmation-audio", bytes, type: "audio/mp4", model: model, query: ["id": id]); result = "Saved in your voice."; await load() }
            catch { result = error.localizedDescription }
        } else if let why = await recorder.start(a.key) { result = why }
    }
}

// MARK: - Rehearsal and the breath

/// Eleven seconds a breath, five and a half in and five and a half out: one cosine, so the turn is still, like a real breath.
struct BreathBloom: View {
    let start: Date
    let running: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !running || reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                let env = !running ? 0.15 : reduceMotion ? 0.55 : 0.5 - 0.5 * cos((t.truncatingRemainder(dividingBy: 11)) / 11 * 2 * .pi)
                let spin = running && !reduceMotion ? (t.truncatingRemainder(dividingBy: 90)) / 90 * 360 : 0
                let cx = size.width / 2, cy = size.height / 2, maxR = min(cx, cy) * 0.95
                let r = maxR * (0.3 + 0.7 * env)
                let n = 21
                for i in 0..<n {
                    let k = Double(i + 1) / Double(n)
                    var c = ctx
                    c.translateBy(x: cx, y: cy)
                    c.rotate(by: .degrees(spin + Double(i) * 137.5))
                    let len = r * (0.35 + 0.65 * k), wid = len * 0.34
                    var p = Path()
                    p.move(to: .zero)
                    p.addQuadCurve(to: CGPoint(x: 0, y: -len), control: CGPoint(x: wid, y: -len * 0.5))
                    p.addQuadCurve(to: .zero, control: CGPoint(x: -wid, y: -len * 0.5))
                    c.stroke(p, with: .color(Wallpaper.line.opacity(0.25 + 0.6 * k)), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct RehearsalView: View {
    let model: AppModel
    private static let stages = [
        "See it: the room, the light, where you are when it is true.",
        "Hear it: what is said around you, the sound of that day.",
        "Feel it: the fabric, the weight, the temperature of it.",
        "The emotion of it done: let it land in the chest.",
        "Hold the whole scene: you inside it, present tense.",
    ]
    private static let stageSeconds = 24

    enum Phase { case setup, live, rate, done }
    @State private var phase: Phase = .setup
    @State private var breatheOnly = false
    @State private var desires: [PracticeDesire] = []
    @State private var chosen = ""
    @State private var started = Date()
    @State private var elapsed = 0
    @State private var beat = 0
    @State private var result: String?

    private var stage: Int { min(elapsed / Self.stageSeconds, Self.stages.count - 1) }

    var body: some View {
        Group {
            switch phase {
            case .setup: setup
            case .live: live
            case .rate: rate
            case .done: ContentUnavailableView("Logged", systemImage: "checkmark.circle", description: Text("The scene compounds."))
            }
        }
        .navigationTitle("Rehearsal").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.open, trigger: beat)
        .sensoryFeedback(PLHaptic.success, trigger: phase == .done)
        .task { await loadDesires() }
        .onDisappear { if phase == .live { Task { await RehearsalLive.stop() } } }
    }

    private var setup: some View {
        Form {
            Section {
                Picker("Mode", selection: $breatheOnly) { Text("Rehearse a desire").tag(false); Text("Just breathe").tag(true) }.pickerStyle(.segmented)
                if !breatheOnly {
                    Picker("Desire", selection: $chosen) {
                        if desires.isEmpty { Text("No open desires").tag("") }
                        ForEach(desires) { Text($0.text).lineLimit(1).tag($0.id) }
                    }
                }
            } footer: { Text(breatheOnly ? "Coherent breathing: in for 5.5 seconds, out for 5.5. A tap marks each turn, so you can follow it with the screen face down." : "Two minutes: the breath, then five senses of the scene, then how strongly it landed.") }
            Section {
                Button { begin() } label: { Text(breatheOnly ? "Begin" : "Begin the rehearsal") }.disabled(!breatheOnly && chosen.isEmpty)
                ResultLine(text: result)
            }
        }
    }

    private var live: some View {
        VStack(spacing: 16) {
            BreathBloom(start: started, running: true).frame(height: 260)
            TimelineView(.periodic(from: started, by: 5.5)) { tl in
                let half = Int(tl.date.timeIntervalSince(started) / 5.5)
                Text(half % 2 == 0 ? "Breathe in" : "Breathe out").font(.title3.weight(.medium)).contentTransition(.opacity).animation(.smooth, value: half)
            }
            if !breatheOnly {
                Text(Self.stages[stage]).plReading().multilineTextAlignment(.center).padding(.horizontal, PLSpace.roomy).id(stage).transition(.opacity)
                ProgressView(value: Double(min(elapsed, Self.stageSeconds * Self.stages.count)), total: Double(Self.stageSeconds * Self.stages.count)).padding(.horizontal, PLSpace.block).tint(Wallpaper.line)
            }
            Spacer()
            Button(breatheOnly ? "Stop" : "End the rehearsal", role: .cancel) { finish() }.buttonStyle(.bordered)
        }
        .padding(PLSpace.margin)
        .animation(.smooth, value: stage)
        .task(id: phase) {
            while phase == .live, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsed = Int(Date().timeIntervalSince(started))
                beat = Int(Date().timeIntervalSince(started) / 5.5)   // one tap at each turn of the breath
                if !breatheOnly { await RehearsalLive.update(stage: stage, titles: Self.stages) }
                if !breatheOnly, elapsed >= Self.stageSeconds * Self.stages.count { finish() }
            }
        }
    }

    private var rate: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { n in
                        Button { Task { await save(n) } } label: { Text("\(n)").font(.title2.monospacedDigit()).frame(maxWidth: .infinity, minHeight: PLMetric.touch) }.buttonStyle(.bordered)
                    }
                }
                ResultLine(text: result)
            } header: { Text("How strongly did it land?") } footer: { Text("1 is faint, 5 is felt in the chest. The trend of this number is the record, not a streak.") }
        }
    }

    private func loadDesires() async {
        if let l = try? await Practice.get("scripts", [PracticeDesire].self, model: model) {
            desires = l.filter { $0.completed_at == nil }
            if chosen.isEmpty { chosen = desires.first?.id ?? "" }
        }
    }

    private func begin() {
        started = Date(); elapsed = 0; beat = 0; result = nil; phase = .live
        if !breatheOnly { RehearsalLive.start(desire: desires.first { $0.id == chosen }?.text ?? "A rehearsal", started: started, titles: Self.stages) }
    }

    private func finish() {
        Task { await RehearsalLive.stop() }
        phase = breatheOnly ? .setup : .rate
    }

    private func save(_ n: Int) async {
        do {
            try await Practice.post("sessions", ["script_id": chosen, "duration_s": max(elapsed, 1), "intensity": n], model: model)
            phase = .done
            try? await Task.sleep(for: .seconds(3)); phase = .setup
        } catch { result = error.localizedDescription }
    }
}
