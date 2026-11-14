import AVFoundation
import SwiftUI

/// The Interviewer's voice, native (pl-interview `public/app.html`: the voice orb, hands free vs push to talk, the voice picker, pause
/// and speed, and the engine settings). Differences from the page, each on purpose:
/// - Speech in is Apple's, on the phone (`CaptureDictation`: on-device recognition where the phone has it). No audio leaves the phone for it.
/// - Speech out is **Apple's voices only**: the page's cloud voices (orion, luna...) are not offered. Personal Voice is never listed, never
///   requested and never used here (his rule: no synthesised founder voice but Voicebox, one ruled exception that is not this screen).
/// Settings live on the phone (UserDefaults), as the page keeps them in localStorage.
enum InterviewPrefs {
    private static var d: UserDefaults { .standard }
    private static func key(_ k: String) -> String { "pldev.interview." + k }

    static var voiceID: String { get { d.string(forKey: key("voice")) ?? "" } set { d.set(newValue, forKey: key("voice")) } }
    static var pauseMs: Int { get { d.object(forKey: key("pause")) as? Int ?? 2500 } set { d.set(newValue, forKey: key("pause")) } }
    static var speed: Double { get { d.object(forKey: key("speed")) as? Double ?? 1 } set { d.set(newValue, forKey: key("speed")) } }
    static var pushToTalk: Bool { get { d.bool(forKey: key("ptt")) } set { d.set(newValue, forKey: key("ptt")) } }
    static var voiceOn: Bool { get { d.bool(forKey: key("voiceOn")) } set { d.set(newValue, forKey: key("voiceOn")) } }
    static var model: String { get { d.string(forKey: key("model")) ?? "auto" } set { d.set(newValue, forKey: key("model")) } }
    static var adventure: Double { get { d.object(forKey: key("adv")) as? Double ?? 0.5 } set { d.set(newValue, forKey: key("adv")) } }
    static var maxLen: Int { get { d.object(forKey: key("len")) as? Int ?? 400 } set { d.set(newValue, forKey: key("len")) } }
    static var bank: String { get { d.string(forKey: key("bank")) ?? "start" } set { d.set(newValue, forKey: key("bank")) } }

    /// What the engine adds to every turn beyond pressure, length and depth (those stay on the setup form).
    static func apply(to s: inout GlyphBot.Settings) {
        s.model = model; s.adventure = adventure; s.maxLen = maxLen; s.bank = bank
    }
}

/// Apple's English voices, best first. Personal Voices and novelty voices are left out.
enum AppleVoices {
    struct Item: Identifiable, Hashable {
        let id: String; let name: String; let quality: String; let rank: Int
    }

    static func list() -> [Item] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .map { v in
                let q: (String, Int) = v.quality == .premium ? ("premium", 0) : v.quality == .enhanced ? ("enhanced", 1) : ("standard", 2)
                return Item(id: v.identifier, name: "\(v.name) · \(region(v.language))", quality: q.0, rank: q.1)
            }
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    private static func region(_ lang: String) -> String {
        switch lang { case "en-US": return "US"; case "en-GB": return "UK"; case "en-AU": return "Australia"; case "en-IE": return "Ireland"; case "en-ZA": return "South Africa"
        case "en-IN": return "India"; default: return lang }
    }

    /// The chosen voice, else the best Apple has installed (premium, then enhanced, then the first US English one).
    static func chosen() -> AVSpeechSynthesisVoice? {
        if !InterviewPrefs.voiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: InterviewPrefs.voiceID), !v.voiceTraits.contains(.isPersonalVoice) { return v }
        if let best = list().first, let v = AVSpeechSynthesisVoice(identifier: best.id) { return v }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

/// One sitting's voice: it speaks each question aloud, then listens (hands free) or waits for the held button (push to talk).
/// Phase is the page's own: idle, listening, thinking, speaking.
@MainActor @Observable final class InterviewTalk: NSObject, AVSpeechSynthesizerDelegate {
    enum Phase { case idle, listening, thinking, speaking }
    var phase: Phase = .idle
    var heard = ""
    var note: String?
    private(set) var on = InterviewPrefs.voiceOn
    func setOn(_ v: Bool) { on = v; InterviewPrefs.voiceOn = v; if !v { stopAll() } }

    private let synth = AVSpeechSynthesizer()
    private let dictation = CaptureDictation()
    private var quiet: Task<Void, Never>?
    private var spoken: String?
    private var onAnswer: ((String) -> Void)?
    private var held = false

    override init() {
        super.init()
        synth.delegate = self
    }

    var supported: Bool { CaptureDictation.available }

    /// What the page shows under the orb.
    var statusLine: String {
        if let note { return note }
        switch phase {
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return ""
        case .idle: return InterviewPrefs.pushToTalk ? "Hold the gold to answer" : "Tap the gold to answer"
        }
    }

    /// Speaks a question in the chosen Apple voice. When it ends, hands free starts listening.
    func speak(_ text: String, onAnswer: @escaping (String) -> Void) {
        guard on, !text.isEmpty else { return }
        self.onAnswer = onAnswer
        stopListening()
        synth.stopSpeaking(at: .immediate)
        spoken = text
        let u = AVSpeechUtterance(string: text)
        u.voice = AppleVoices.chosen()
        // Apple's default rate is 0.5; the page's speed (0.85 to 1.3) scales it, inside Apple's own limits.
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(InterviewPrefs.speed)))
        try? PLAudio.speaking()
        phase = .speaking
        synth.speak(u)
    }

    /// Plays one voice's sample for the picker.
    func sample(_ id: String) {
        stopAll()
        let u = AVSpeechUtterance(string: "Where were you the first time you drew it? Take me to the room.")
        u.voice = AVSpeechSynthesisVoice(identifier: id)
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(InterviewPrefs.speed)))
        try? PLAudio.speaking()
        spoken = nil
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.phase == .speaking || self.spoken == nil else { return }
            if self.spoken == nil { PLAudio.release(); return }   // a picker sample
            self.phase = .idle
            if !InterviewPrefs.pushToTalk, self.on {
                try? await Task.sleep(for: .milliseconds(350))
                if self.phase == .idle { await self.listen() }
            }
        }
    }

    func thinking() { phase = .thinking }
    func idle(_ message: String? = nil) { phase = .idle; note = message }

    func listen() async {
        guard on, phase != .listening else { return }
        stopSpeaking()
        heard = ""; note = nil
        let why = await dictation.start(
            onText: { [weak self] t in Task { @MainActor in self?.partial(t) } },
            onEnd: { [weak self] in Task { @MainActor in self?.ended() } })
        if let why { phase = .idle; note = why } else { phase = .listening }
    }

    private func partial(_ t: String) {
        guard phase == .listening else { return }
        heard = t
        quiet?.cancel()
        guard !InterviewPrefs.pushToTalk else { return }   // push to talk ends on release, never on a pause
        let ms = InterviewPrefs.pauseMs
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            if !Task.isCancelled { self?.finish() }
        }
    }

    private func ended() {
        guard phase == .listening else { return }
        if InterviewPrefs.pushToTalk && held { Task { await listen() }; return }
        heard.trimmingCharacters(in: .whitespaces).isEmpty ? idle("Did not hear you. Tap the gold to answer.") : finish()
    }

    /// Sends what he said: a pause (hands free), a tap on the gold while listening, or letting go of it (push to talk).
    func finish() {
        quiet?.cancel()
        let t = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        dictation.stop()
        guard !t.isEmpty else { phase = .idle; return }
        phase = .thinking
        onAnswer?(t)
    }

    // MARK: the gold button

    func tap() async {
        guard !InterviewPrefs.pushToTalk else { return }
        switch phase {
        case .listening: finish()
        case .speaking: stopSpeaking(); await listen()
        case .idle: await listen()
        case .thinking: break
        }
    }

    func press() async {
        guard InterviewPrefs.pushToTalk, phase != .thinking else { return }
        held = true; stopSpeaking(); await listen()
    }

    func release() {
        guard InterviewPrefs.pushToTalk, held else { return }
        held = false
        Task { try? await Task.sleep(for: .milliseconds(350)); if phase == .listening { finish() } }
    }

    // MARK: stopping

    private func stopSpeaking() { spoken = nil; if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }; if phase == .speaking { phase = .idle } }
    private func stopListening() { quiet?.cancel(); dictation.stop(); if phase == .listening { phase = .idle } }
    func stopAll() { stopSpeaking(); stopListening(); heard = ""; if phase != .thinking { phase = .idle }; PLAudio.release() }
}

/// The page's gold orb: tap to answer (hands free), hold to answer (push to talk).
struct InterviewOrb: View {
    @Bindable var talk: InterviewTalk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        let listening = talk.phase == .listening
        ZStack {
            Circle().fill(PLOS.gold.opacity(listening ? 0.28 : 0.12)).frame(width: 118, height: 118)
                .scaleEffect(listening && !reduceMotion ? 1.12 : 1).animation(listening && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: listening)
            Circle().fill(PLOS.gold).frame(width: 86, height: 86).opacity(talk.phase == .thinking ? 0.5 : 1)
            Image(systemName: listening ? "waveform" : talk.phase == .speaking ? "speaker.wave.2.fill" : "mic.fill")
                .font(.system(size: 28, weight: .medium)).foregroundStyle(.black.opacity(0.75)).symbolEffect(.variableColor, isActive: listening)
        }
        .frame(width: 124, height: 124)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !down { down = true; Task { await talk.press() } } }
            .onEnded { _ in down = false; talk.release(); if !InterviewPrefs.pushToTalk { Task { await talk.tap() } } })
        .accessibilityElement().accessibilityLabel(InterviewPrefs.pushToTalk ? "Hold to answer" : listening ? "Tap to send now" : "Tap to answer")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await talk.tap() } }
    }
}

/// The page's Settings: the voice, the pause, the speed, the mode, the model and the follow-ups.
struct InterviewSettingsView: View {
    @Bindable var sitting: SittingModel
    @State private var talk = InterviewTalk()
    @State private var voice = InterviewPrefs.voiceID
    @State private var pause = InterviewPrefs.pauseMs
    @State private var speed = InterviewPrefs.speed
    @State private var ptt = InterviewPrefs.pushToTalk
    @State private var model = InterviewPrefs.model
    @State private var adventure = InterviewPrefs.adventure
    @State private var maxLen = InterviewPrefs.maxLen
    @State private var bank = InterviewPrefs.bank
    private let voices = AppleVoices.list()

    var body: some View {
        Form {
            Section {
                if voices.isEmpty {
                    Text("This iPhone has no English voices installed. Add one in Settings, Accessibility, Spoken Content, Voices.").font(.footnote).foregroundStyle(.secondary)
                }
                Button { voice = ""; InterviewPrefs.voiceID = "" } label: { row("Best installed", sub: "the highest quality Apple voice on this iPhone", chosen: voice.isEmpty) }
                ForEach(voices) { v in
                    Button { voice = v.id; InterviewPrefs.voiceID = v.id; talk.sample(v.id) } label: { row(v.name, sub: v.quality, chosen: voice == v.id) }
                }
            } header: { Text("GlyphBot's voice") } footer: { Text("Tap to hear one and choose it. Apple's own voices, spoken on this iPhone: free, instant, nothing leaves the phone. Premium and enhanced ones are a download in Settings, Accessibility, Spoken Content, Voices.") }
            .buttonStyle(.plain)

            Section("How long you can pause before it takes its turn") {
                Picker("Pause", selection: $pause) { Text("Short").tag(1500); Text("Normal").tag(2500); Text("Long").tag(4000); Text("Thinker").tag(7000) }
                    .pickerStyle(.segmented).onChange(of: pause) { InterviewPrefs.pauseMs = pause }
            }
            Section("Speed") {
                Picker("Speed", selection: $speed) { Text("Slow").tag(0.85); Text("Normal").tag(1.0); Text("Quick").tag(1.15); Text("Fast").tag(1.3) }
                    .pickerStyle(.segmented).onChange(of: speed) { InterviewPrefs.speed = speed }
            }
            Section {
                Picker("Mode", selection: $ptt) { Text("Hands free").tag(false); Text("Push to talk").tag(true) }
                    .pickerStyle(.segmented).onChange(of: ptt) { InterviewPrefs.pushToTalk = ptt }
            } header: { Text("Mode") } footer: { Text(ptt ? "Hold the gold button to speak, let go to send." : "It listens after it speaks and takes its turn when you pause. Best somewhere quiet.") }

            Section("Model") {
                Picker("Model", selection: $model) { Text("Auto").tag("auto"); Text("Haiku 5.5").tag("haiku"); Text("Sonnet 5.5").tag("sonnet"); Text("Opus 5.5").tag("opus") }
                    .pickerStyle(.segmented).onChange(of: model) { InterviewPrefs.model = model }
                Toggle("Deep: Opus on rich answers", isOn: $sitting.settings.deep)
                Text(estimate).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Follow-ups") {
                Picker("Pressure", selection: $sitting.settings.boldness) { Text("Gentle").tag("gentle"); Text("Normal").tag("light"); Text("Probing").tag("probing") }.pickerStyle(.segmented)
                Picker("Adventure", selection: $adventure) { Text("Close to the thread").tag(0.2); Text("Balanced").tag(0.5); Text("Adventurous").tag(0.9) }
                    .onChange(of: adventure) { InterviewPrefs.adventure = adventure }
                Picker("Reply length", selection: $maxLen) { Text("Short").tag(200); Text("Normal").tag(400); Text("Long").tag(900) }
                    .pickerStyle(.segmented).onChange(of: maxLen) { InterviewPrefs.maxLen = maxLen }
            }
            Section("Session") {
                Picker("The 501 bank", selection: $bank) { Text("As starting points").tag("start"); Text("Off").tag("off") }
                    .pickerStyle(.segmented).onChange(of: bank) { InterviewPrefs.bank = bank }
                Picker("Length", selection: $sitting.settings.targetMin) { Text("Open ended").tag(0); Text("15 min").tag(15); Text("30 min").tag(30); Text("60 min").tag(60) }
            }
        }
        .glyphList()
        .navigationTitle("Voice and answers").navigationBarTitleDisplayMode(.inline)
        .onDisappear { talk.stopAll() }
    }

    private var estimate: String {
        let per: [String: Double] = ["auto": 0.9, "haiku": 0.25, "sonnet": 0.9, "opus": 2.6]
        let t = sitting.settings.targetMin
        let cost = (per[model] ?? 0.9) * (t > 0 ? Double(t) / 30 : 1)
        return "About $\(String(format: "%.2f", cost)) per \(t > 0 ? t : 30)-minute sitting on \(model)\(sitting.settings.deep ? " with deep" : ""). Monthly cap $65."
    }

    private func row(_ title: String, sub: String, chosen: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) { Text(title).foregroundStyle(.primary); Text(sub).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if chosen { Image(systemName: "checkmark").foregroundStyle(PLOS.gold) }
        }
        .frame(minHeight: 44).contentShape(Rectangle())
    }
}
