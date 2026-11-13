import SwiftUI
import AVFoundation

private final class WindState: @unchecked Sendable { var last: Float = 0; var phase: Float = 0 }

/// Wind always, crickets after dark: made live, no files (as the web's SND button).
@MainActor final class TownSound {
    private let engine = AVAudioEngine()
    private var running = false
    private var dark = false
    private var timer: Timer?
    private let chirper = AVAudioPlayerNode()   // one player for every cricket, attached once

    func start(dark: Bool) {
        guard !running else { return }
        self.dark = dark
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let fmt = engine.outputNode.inputFormat(forBus: 0)
        let sr = fmt.sampleRate
        let wind = Self.makeWind(sr: sr)   // built outside the main actor: it runs on the audio thread
        engine.attach(wind)
        engine.connect(wind, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1))
        engine.attach(chirper)
        engine.connect(chirper, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1))
        do { try engine.start() } catch { return }
        chirper.play()
        running = true
        if dark { timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.chirp(sr) } } }
    }

    nonisolated private static func makeWind(sr: Double) -> AVAudioSourceNode {
        let st = WindState()
        return AVAudioSourceNode { _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            for i in 0..<Int(frames) {
                st.last = (st.last + 0.02 * (Float.random(in: -1...1))) / 1.02
                st.phase += 0.07 / Float(sr)
                let v = st.last * 3.5 * 0.18 * (0.55 + 0.45 * sin(st.phase * 2 * .pi))
                for b in list { b.mData?.assumingMemoryBound(to: Float.self)[i] = v }
            }
            return noErr
        }
    }

    private func chirp(_ sr: Double) {
        guard running else { return }
        let n = Int(sr * 0.22)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1), let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let f = Float(4300 + Double.random(in: 0...200))
        for i in 0..<n {
            let t = Float(i) / Float(sr)
            let burst = Float(Int(t / 0.07) < 3 ? 1 : 0) * max(0, 1 - Float((t.truncatingRemainder(dividingBy: 0.07)) / 0.05))
            buf.floatChannelData?[0][i] = sin(2 * .pi * f * t) * 0.025 * burst
        }
        chirper.scheduleBuffer(buf, completionHandler: nil)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if running { engine.stop() }
        running = false
    }
}
