import AVFoundation
import SwiftUI

// The affirmations shuffled deck and his own live recording (his clips are played as they are, never generated).

// MARK: - A shuffled deck: no repeat until every line has been shown

enum PracticeDeck {
    /// Picks a key not shown yet; when all have been shown, the deck reshuffles and the key just shown never opens the new deck
    /// (his rule 11-13: random means a shuffled deck). `deck` names the saved deck, so two places never share one. Kept on the phone.
    static func next(of keys: [String], deck: String = "practice.deck.shown") -> String? {
        guard !keys.isEmpty else { return nil }
        let store = UserDefaults.standard
        let last = store.string(forKey: deck + ".last")
        var shown = Set(store.stringArray(forKey: deck) ?? []).intersection(keys)
        let fresh = shown.count >= keys.count
        if fresh { shown = [] }
        // a fresh deck: the key just shown is barred only from opening it
        let bar: Set<String> = fresh && keys.count > 1 ? Set([last].compactMap { $0 }) : []
        guard let pick = keys.filter({ !shown.contains($0) && !bar.contains($0) }).randomElement() else { return nil }
        shown.insert(pick)
        store.set(Array(shown), forKey: deck)
        store.set(pick, forKey: deck + ".last")
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
            try PLAudio.listening()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("practice-\(UUID().uuidString).m4a")
            let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard r.record() else { return "Recording would not start." }
            recorder = r; file = url; recordingKey = key
            return nil
        } catch { return "Recording would not start. \(plainSentence(error))" }
    }

    /// Stops and returns the recording's bytes. The file stays until `discard()` (called once the upload has landed),
    /// so a failed upload loses nothing: the next tap tries again with the same take.
    func stop() -> Data? {
        recorder?.stop(); recorder = nil; recordingKey = nil; PLAudio.release()
        guard let file, let d = try? Data(contentsOf: file), !d.isEmpty else { return nil }
        return d
    }

    func discard() { if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
}

