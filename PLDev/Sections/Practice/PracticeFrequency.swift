import SwiftUI
import AVFoundation

/// Frequency Lab (his ask 11-26: "build a few things on the Hz frequency chart and the claims about bending time or commanding reality.
/// From a scientific pov"). The released Gateway papers inspired the shape; the words are ours and every claim is tested here, on him:
/// a coin-flipped plain tone as the control, his step before and after, felt time against real time, and a ledger of what came true.
/// Nothing leaves the phone.

enum FrequencyTone: String, CaseIterable, Codable {
    case settle, focus, sleep
    var title: String { switch self { case .settle: "Settle · 6 Hz"; case .focus: "Focus · 10 Hz"; case .sleep: "Sleep · 2 Hz" } }
    var beat: Double { switch self { case .settle: 6; case .focus: 10; case .sleep: 2 } }

    /// Ten seconds of 16-bit stereo as a WAV, left ear at 200 Hz and right at 200 + `beat` (0 = the same tone in both ears).
    /// Whole cycles in every ten seconds, so it loops without a click.
    static func wav(beat: Double) -> Data {
        let rate = 44_100, seconds = 10, frames = rate * seconds
        var pcm = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            let t = Double(i) / Double(rate)
            pcm[i * 2] = Int16(sin(2 * .pi * 200 * t) * 5_000)
            pcm[i * 2 + 1] = Int16(sin(2 * .pi * (200 + beat) * t) * 5_000)
        }
        var d = Data()
        func word<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(frames * 4)
        d.append(contentsOf: Array("RIFF".utf8)); word(UInt32(36) + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(2)); word(UInt32(rate)); word(UInt32(rate * 4)); word(UInt16(4)); word(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); word(bytes)
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }   // iPhone is little endian
        return d
    }
}

struct FrequencyRun: Codable { let at: Date; let tone: FrequencyTone; let beats: Bool; let before: Band; let after: Band; let seconds: Int; let feltMinutes: Int }
struct FrequencyWish: Codable, Identifiable { var id = UUID(); let text: String; let until: Date; var happened: Bool? }

@MainActor @Observable final class FrequencyLog {
    struct Saved: Codable { var runs: [FrequencyRun] = []; var wishes: [FrequencyWish] = [] }
    private(set) var saved = Saved()
    private(set) var readable = true   // a file that could not be read (locked phone) is never written over

    private static var url: URL { URL.applicationSupportDirectory.appending(path: "frequency.json") }

    func load() {
        guard FileManager.default.fileExists(atPath: Self.url.path) else { readable = true; return }
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s; readable = true }
        else { readable = false }
    }

    func change(_ edit: (inout Saved) -> Void) {
        guard readable else { return }
        edit(&saved)
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.url, options: [.atomic, .completeFileProtection])
    }

    /// "Beats: +0.8 steps over 6" for one arm of the test.
    func line(beats: Bool) -> String {
        let r = saved.runs.filter { $0.beats == beats }
        let name = beats ? "Beats" : "Plain tone"
        guard !r.isEmpty else { return "\(name): none yet" }
        let mean = Double(r.map { $0.after.rawValue - $0.before.rawValue }.reduce(0, +)) / Double(r.count)
        return "\(name): \(String(format: "%+.1f", mean)) steps over \(r.count)"
    }

    var enough: Bool { saved.runs.filter(\.beats).count >= 10 && saved.runs.filter { !$0.beats }.count >= 10 }
}

struct FrequencyCard: View {
    @State private var log = FrequencyLog()
    @State private var running = false

    var body: some View {
        PCard(title: "Frequency Lab", hint: "Tones and the Gateway ideas, tested on you instead of taken on trust.", id: "frequency") {
            Button("Start a session") { running = true }.buttonStyle(CandleButton()).disabled(!log.readable)
            if !log.saved.runs.isEmpty {
                Text(log.line(beats: true)).candleHint()
                Text(log.line(beats: false)).candleHint()
                Text(log.enough ? "Ten or more of each: compare the two." : "A hint, not a finding, until there are 10 of each.").candleHint()
            }
            if !log.saved.wishes.isEmpty { ledger }
        }
        .onAppear { log.load() }
        .sheet(isPresented: $running) { FrequencySession(log: log) }
    }

    private var ledger: some View {
        let judged = log.saved.wishes.compactMap(\.happened)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Did it happen?").candleH2()
            if !judged.isEmpty { Text("\(judged.filter { $0 }.count) of \(judged.count) happened.").candleHint() }
            ForEach(log.saved.wishes.reversed()) { w in
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.text).font(Font.pl(size: 14)).foregroundStyle(Candle.ink)
                    Text(w.happened.map { $0 ? "Happened" : "Did not" } ?? "By \(w.until.formatted(date: .abbreviated, time: .omitted))").candleHint()
                    if w.happened == nil {
                        HStack(spacing: 8) {
                            Button("Happened") { judge(w.id, true) }.buttonStyle(CandleGhost())
                            Button("Did not") { judge(w.id, false) }.buttonStyle(CandleGhost())
                        }
                    }
                }
                .contextMenu { Button("Remove", role: .destructive) { log.change { s in s.wishes.removeAll { $0.id == w.id } } } }
            }
        }
    }

    private func judge(_ id: UUID, _ yes: Bool) {
        log.change { s in if let i = s.wishes.firstIndex(where: { $0.id == id }) { s.wishes[i].happened = yes } }
    }
}

struct FrequencySession: View {
    let log: FrequencyLog
    @Environment(\.dismiss) private var dismiss
    private enum Stage { case setup, live, after, done }
    @State private var stage = Stage.setup
    @State private var tone = FrequencyTone.settle
    @State private var minutes = 5
    @State private var before = Band.stuck
    @State private var after = Band.stuck
    @State private var felt = 5
    @State private var wish = ""
    @State private var days = 30
    @State private var beats = true
    @State private var step = ""
    @State private var started = Date()
    @State private var seconds = 0
    @State private var player: AVAudioPlayer?
    @State private var problem: String?

    init(log: FrequencyLog) { self.log = log }

    /// The session in our words, each line with its share of the time.
    private static let steps: [(String, Double)] = [
        ("Sit or lie back. Close the lid on a box and leave every worry in it.", 8),
        ("Breathe in and fill your head. Breathe out, slow, as if at a candle.", 3),
        ("Fill your chest and arms. Let it out.", 3),
        ("Fill your stomach. Let it out.", 3),
        ("Fill your hips. Let it out.", 3),
        ("Fill your thighs and knees. Let it out.", 3),
        ("Fill your legs and feet. Let it out.", 3),
        ("Count slowly to ten. At each number let one part of you go heavy.", 22),
        ("Body asleep, mind awake. Watch what comes. Do nothing with it.", 28),
        ("See the thing you want, already done. Then the one obstacle, and your move.", 16),
        ("Count back from ten to one. Move your fingers. Open your eyes.", 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch stage {
                    case .setup: setup
                    case .live: live
                    case .after: afterward
                    case .done: result
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .candleScreen()
            .navigationTitle("Frequency Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task(id: stage == .live) { if stage == .live { await run() } }
        .onDisappear { stop() }
    }

    @ViewBuilder private var setup: some View {
        Text("Headphones on. Keep it quiet.").candleH2()
        Text("Never while driving, on the floor at work or around machines. If you have epilepsy or seizures, ask a doctor first.").candleHint()
        Picker("Tone", selection: $tone) { ForEach(FrequencyTone.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        Picker("Length", selection: $minutes) { Text("5 minutes").tag(5); Text("10 minutes").tag(10) }.pickerStyle(.segmented)
        bandPicker("Where you are now", $before)
        Text("A coin flip gives you either real beats or a plain tone. The totals show which did more for you.").candleHint()
        if let problem { Text(problem).candleHint() }
        Button("Begin") { begin() }.buttonStyle(CandleButton())
    }

    @ViewBuilder private var live: some View {
        Text(step).font(Font.pl(size: 22, weight: .medium)).foregroundStyle(Candle.goldHi).frame(maxWidth: .infinity, minHeight: 220)
            .multilineTextAlignment(.center)
        Text("Move a finger or toe to come straight back.").candleHint()
        Button("Stop here") { finish() }.buttonStyle(CandleGhost())
    }

    @ViewBuilder private var afterward: some View {
        bandPicker("Where you are now", $after)
        Stepper("It felt like \(felt) minute\(felt == 1 ? "" : "s")", value: $felt, in: 1...40)
        TextField("What you are calling in (optional)", text: $wish, axis: .vertical).textFieldStyle(.roundedBorder)
        Picker("By", selection: $days) { Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90) }.pickerStyle(.segmented)
        Button("Save") { save() }.buttonStyle(CandleButton())
    }

    @ViewBuilder private var result: some View {
        Text("It ran \(seconds / 60):\(String(format: "%02d", seconds % 60)). It felt like \(felt):00.").candleH2()
        Text("\(before.title) to \(after.title). This one was \(beats ? "real beats" : "the plain tone").").candleHint()
        Text(log.line(beats: true)).candleHint()
        Text(log.line(beats: false)).candleHint()
        Button("Done") { dismiss() }.buttonStyle(CandleButton())
    }

    private func bandPicker(_ title: String, _ band: Binding<Band>) -> some View {
        HStack {
            Text(title).candleHint()
            Spacer()
            Picker(title, selection: band) { ForEach(Band.allCases.reversed(), id: \.self) { Text($0.title).tag($0) } }.labelsHidden().pickerStyle(.menu)
        }
        .frame(minHeight: 44)
    }

    private func begin() {
        beats = Bool.random()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)   // plays with the silent switch on
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: FrequencyTone.wav(beat: beats ? tone.beat : 0))
            p.numberOfLoops = -1
            p.volume = 0
            p.play()
            p.setVolume(1, fadeDuration: 4)
            player = p
        } catch {
            problem = "The tone did not start: \(error.localizedDescription)"
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true   // a locked screen would end the sound
        started = .now
        after = before
        felt = minutes
        step = Self.steps[0].0
        stage = .live
    }

    private func run() async {
        let total = Self.steps.map(\.1).reduce(0, +)
        for (text, share) in Self.steps {
            step = text
            do { try await Task.sleep(for: .seconds(Double(minutes * 60) * share / total)) } catch { return }
        }
        finish()
    }

    private func finish() {
        guard stage == .live else { return }
        seconds = Int(Date.now.timeIntervalSince(started))
        stop()
        stage = .after
    }

    private func stop() {
        player?.stop()
        player = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func save() {
        let text = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        log.change { s in
            s.runs.append(FrequencyRun(at: .now, tone: tone, beats: beats, before: before, after: after, seconds: seconds, feltMinutes: felt))
            if !text.isEmpty {
                s.wishes.append(FrequencyWish(text: text, until: Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now))
            }
        }
        stage = .done
    }
}
