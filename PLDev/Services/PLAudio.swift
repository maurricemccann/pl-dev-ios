import AVFoundation

/// One audio manner for the whole app (his report 11-13: "before, AirPods would work even with music playing").
/// Nothing in PL DEV takes the phone's audio for itself: sounds mix under his music, a spoken reply lowers the music
/// and gives it back, and voice input uses the AirPods mic while the music keeps playing.
enum PLAudio {
    private static var s: AVAudioSession { .sharedInstance() }

    /// Small sounds (Curate stamps, Town): under whatever is playing, silent with the ringer switch.
    static func ambient() { try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers]); try? s.setActive(true) }

    /// A voice speaking (GlyphBot, Practice): the music dips while it talks. Call release() when it finishes.
    static func speaking() throws { try s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]); try s.setActive(true) }

    /// Listening (Capture, Practice voice, VJ): the AirPods high-quality mic (iOS 26), music keeps playing, speaker otherwise.
    static func listening() throws {
        try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .bluetoothHighQualityRecording, .defaultToSpeaker])   // the setting his call app proved with music playing
        try s.setActive(true)
    }

    /// Music playback that owns nothing (VJ playing a track): mixes with his music.
    static func playing() throws { try s.setCategory(.playback, mode: .default, options: [.mixWithOthers]); try s.setActive(true) }

    /// Hands the audio back so his music comes back to full volume.
    static func release() { try? s.setActive(false, options: .notifyOthersOnDeactivation) }
}
