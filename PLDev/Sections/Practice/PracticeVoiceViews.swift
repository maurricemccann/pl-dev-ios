import AVFoundation
import SwiftUI

// The affirmations shuffled deck and his own live recording (his clips are played as they are, never generated).

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

    /// Stops and returns the recording's bytes. The file stays until `discard()` (called once the upload has landed),
    /// so a failed upload loses nothing: the next tap tries again with the same take.
    func stop() -> Data? {
        recorder?.stop(); recorder = nil; recordingKey = nil
        guard let file, let d = try? Data(contentsOf: file), !d.isEmpty else { return nil }
        return d
    }

    func discard() { if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
}

