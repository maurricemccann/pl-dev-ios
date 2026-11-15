import AudioToolbox
import Foundation

/// The course's three sounds, his picks by ear 11-15 from Kenney's Interface Sounds (CC0, licence beside the files in
/// Resources/Sounds): right = confirmation_001, wrong = drop_002, lesson done = glass_005. System sounds follow the silent switch.
/// If a file is ever missing the Apple tone plays instead, so a lesson is never silent by accident.
@MainActor enum PracticeSound {
    enum Kind: String { case right = "practice-right", wrong = "practice-wrong", done = "practice-done" }
    private static var ids: [Kind: SystemSoundID] = [:]
    private static let fallback: [Kind: SystemSoundID] = [.right: 1057, .wrong: 1104, .done: 1057]

    static func play(_ k: Kind) {
        if let id = ids[k] { AudioServicesPlaySystemSound(id); return }
        if let url = Bundle.main.url(forResource: k.rawValue, withExtension: "caf") {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError {
                ids[k] = id
                AudioServicesPlaySystemSound(id)
                return
            }
        }
        AudioServicesPlaySystemSound(fallback[k] ?? 1057)
    }
}
