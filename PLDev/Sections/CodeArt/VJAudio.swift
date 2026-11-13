import Accelerate
import AVFoundation
import Foundation
import QuartzCore

/// `window.__VJ_AUDIO` for the native runtime: bass, mid, high (0 to 1) and a beat flag, from the microphone or a track.
/// The maths is the browser's AnalyserNode (2048-point FFT, Hann window, 0.82 smoothing, -100 to -30 dB mapped to a byte)
/// and VJEngine's band split (bass under 200 Hz, mid under 4 kHz, high under 12 kHz, gain 1.7), so a piece reacts the same here.
final class VJAudio: @unchecked Sendable {
    static let shared = VJAudio()

    struct Bands: Sendable { var bass = 0.0, mid = 0.0, high = 0.0, beat = false }
    enum Source: Sendable, Equatable { case off, mic, track(String) }

    private let lock = NSLock()
    private var bass = 0.0, mid = 0.0, high = 0.0
    private var prevBass = 0.0
    private var lastBeat = 0.0
    private var lastTapBeat = 0.0
    private var tapBPM = 0.0
    private var synthetic = false

    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var generation = 0
    private var micTap = false   // touching engine.inputNode before a mic is wanted makes a later track fail to start
    private(set) var source: Source = .off
    private(set) var isPlaying = false

    private static let n = 2048
    private let log2n = vDSP_Length(11)
    private let fft: FFTSetup
    private var window = [Float](repeating: 0, count: 2048)
    private var smooth = [Float](repeating: 0, count: 1024)
    private var ring = [Float](repeating: 0, count: 2048)
    private var ringFill = 0

    private init() {
        fft = vDSP_create_fftsetup(vDSP_Length(11), FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.n), Int32(vDSP_HANN_NORM))
    }

    // MARK: reading

    /// What the pieces see this frame. A tapped tempo replaces the bass-transient detector, as in the browser.
    func read(now: Double = CACurrentMediaTime() * 1000) -> Bands {
        lock.lock(); defer { lock.unlock() }
        if synthetic {
            // no real input: a gentle moving signal so audio-reactive pieces still move in the room (the Forge preview does the same)
            let t = now / 1000
            let b = 0.35 + 0.25 * sin(t * 2.1), m = 0.3 + 0.2 * sin(t * 1.3 + 1), h = 0.25 + 0.15 * sin(t * 3.7)
            if sin(t * 2.1) > 0.97 && now - lastBeat > 280 { lastBeat = now }
            return Bands(bass: b, mid: m, high: h, beat: now - lastBeat < 110)
        }
        if tapBPM > 0, now - lastTapBeat >= 60000 / tapBPM { lastTapBeat = now; lastBeat = now }
        return Bands(bass: bass, mid: mid, high: high, beat: now - lastBeat < 110)
    }

    func setTapTempo(_ bpm: Double) { lock.lock(); tapBPM = bpm; lock.unlock() }
    func setSynthetic(_ on: Bool) { lock.lock(); synthetic = on; lock.unlock() }

    // MARK: sources

    private func configureSession(record: Bool) throws {
        let s = AVAudioSession.sharedInstance()
        if record { try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]) }
        else { try s.setCategory(.playback, mode: .default, options: []) }
        try s.setActive(true)
    }

    func stop() {
        generation += 1
        if engine.isRunning { engine.stop() }
        if micTap { engine.inputNode.removeTap(onBus: 0); micTap = false }
        engine.mainMixerNode.removeTap(onBus: 0)
        player.stop()
        if player.engine != nil { engine.detach(player) }
        player = AVAudioPlayerNode()
        file = nil
        isPlaying = false
        source = .off
        lock.lock(); bass = 0; mid = 0; high = 0; prevBass = 0; lock.unlock()
    }

    /// Microphone: analysed only, never played back.
    func startMic() async throws {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { throw VJAudioError.micDenied }
        stop()
        try configureSession(record: true)
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { throw VJAudioError.noInput }
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in self?.analyze(buf) }
        micTap = true
        engine.prepare()
        try engine.start()
        source = .mic
        isPlaying = true
        setSynthetic(false)
    }

    /// A track on disk, looped, through the speaker. The analysis taps the mix.
    func play(url: URL, label: String) throws {
        stop()
        try configureSession(record: false)
        let f = try AVAudioFile(forReading: url)
        file = f
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: f.processingFormat)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buf, _ in self?.analyze(buf) }
        engine.prepare()
        try engine.start()
        generation += 1
        schedule(f, generation)
        player.play()
        source = .track(label)
        isPlaying = true
        setSynthetic(false)
    }

    private func schedule(_ f: AVAudioFile, _ gen: Int) {
        player.scheduleFile(f, at: nil) { [weak self] in
            guard let self, gen == self.generation else { return }
            f.framePosition = 0
            self.schedule(f, gen)   // loop
        }
    }

    func pause() { if source != .off { player.pause(); isPlaying = false } }
    func resume() { if case .track = source { player.play(); isPlaying = true } }

    /// 0 to 1 along the loop, for the deck's progress line.
    var playhead: Double {
        guard let f = file, f.length > 0, let t = player.lastRenderTime, let pt = player.playerTime(forNodeTime: t) else { return 0 }
        return Double(pt.sampleTime).truncatingRemainder(dividingBy: Double(f.length)) / Double(f.length)
    }

    // MARK: analysis

    private func analyze(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData else { return }
        let frames = Int(buf.frameLength)
        let chans = Int(buf.format.channelCount)
        if frames == 0 || chans == 0 { return }
        // mono mix into the ring
        var mono = [Float](repeating: 0, count: frames)
        mono.withUnsafeMutableBufferPointer { mp in
            let p = mp.baseAddress!
            for c in 0..<chans { vDSP_vadd(p, 1, ch[c], 1, p, 1, vDSP_Length(frames)) }
            if chans > 1 { var k = 1 / Float(chans); vDSP_vsmul(p, 1, &k, p, 1, vDSP_Length(frames)) }
        }
        let n = Self.n
        if frames >= n {
            ring = Array(mono[(frames - n)..<frames])
        } else {
            ring.removeFirst(frames)
            ring.append(contentsOf: mono)
        }
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(ring, 1, window, 1, &windowed, 1, vDSP_Length(n))
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        // |X| / N, then the analyser's smoothing, then decibels to a 0...255 byte
        let sr = Float(buf.format.sampleRate)
        let binHz = sr / Float(n)
        var bS: Float = 0, bN: Float = 0, mS: Float = 0, mN: Float = 0, hS: Float = 0, hN: Float = 0
        for i in 0..<(n / 2) {
            let mag = mags[i].squareRoot() / 2 / Float(n)
            smooth[i] = 0.82 * smooth[i] + 0.18 * mag
            let db = 20 * log10(max(smooth[i], 1e-12))
            let byte = max(0, min(1, (db + 100) / 70))
            let hz = Float(i) * binHz
            if hz < 200 { bS += byte; bN += 1 } else if hz < 4000 { mS += byte; mN += 1 } else if hz < 12000 { hS += byte; hN += 1 }
        }
        func gain(_ v: Float) -> Double { v <= 0 ? 0 : Double(min(1, v * 1.7)) }
        let b = gain(bN > 0 ? bS / bN : 0), m = gain(mN > 0 ? mS / mN : 0), h = gain(hN > 0 ? hS / hN : 0)
        let now = CACurrentMediaTime() * 1000
        lock.lock()
        if tapBPM <= 0, b > 0.42, prevBass < 0.30, now - lastBeat > 280 { lastBeat = now }
        prevBass = b
        bass = b; mid = m; high = h
        lock.unlock()
    }
}

enum VJAudioError: LocalizedError {
    case micDenied, noInput
    var errorDescription: String? {
        switch self {
        case .micDenied: return "The microphone is off for PL DEV. Turn it on in Settings."
        case .noInput: return "This phone has no microphone input right now."
        }
    }
}
