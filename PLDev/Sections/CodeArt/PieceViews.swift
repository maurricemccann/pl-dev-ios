import AVKit
import SwiftUI
import UIKit

// The views that show a piece the native runtime is drawing. No web view anywhere.

final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ v: T) { value = v }
}

/// Boots the runtime once for every room: the piece files from the gallery (or the copy kept on the phone), JavaScriptCore, the list.
@MainActor @Observable final class CodeArtBoot {
    static let shared = CodeArtBoot()
    enum State: Equatable { case idle, loading, ready, failed(String) }
    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func ensure(model: AppModel) async {
        if state == .ready { return }
        if let t = task { await t.value; return }
        state = .loading
        FontResolver.handName = HouseKit.shared.titleFont
        let fetch = CodeArtNet.fetcher(for: model)
        let t = Task { @MainActor in
            let ok = await PieceRuntime.shared.boot(fetch: fetch)
            self.state = ok ? .ready : .failed(PieceRuntime.shared.lastError ?? "The pieces did not load.")
            self.task = nil
        }
        task = t
        await t.value
    }

    func retry(model: AppModel) async {
        if case .failed = state { state = .idle }
        await ensure(model: model)
    }
}

/// Every code-art room sits behind this: a spinner while the pieces load, one sentence and a retry when they cannot.
struct CodeArtGate<Content: View>: View {
    let model: AppModel
    @ViewBuilder let content: () -> Content
    @State private var boot = CodeArtBoot.shared

    var body: some View {
        Group {
            switch boot.state {
            case .ready: content()
            case .failed(let why):
                ContentUnavailableView {
                    Label("The pieces did not load", systemImage: "wifi.exclamationmark")
                } description: { Text(why) } actions: {
                    Button("Try again") { Task { await boot.retry(model: model) } }.buttonStyle(.borderedProminent)
                }
            default:
                VStack(spacing: 10) { ProgressView(); Text("Loading the pieces").font(.footnote).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { FontResolver.handName = HouseKit.shared.titleFont; await boot.ensure(model: model) }
    }
}

// MARK: - the drawing surface

/// One piece, drawn at display rate. Holds the instance, the display link and the layer; nothing else.
final class PieceDisplay: UIView {
    var pieceID = "" { didSet { if oldValue != pieceID { restart() } } }
    var fps = 60
    var running = true { didSet { link?.isPaused = !running } }
    var onSlow: (() -> Void)?
    var onBlank: (() -> Void)?
    var onInfo: ((PieceInfo) -> Void)?

    private var inst: PieceInstance?
    private var link: CADisplayLink?
    private var busy = false
    private var generation = 0
    private var frames = 0
    private var msSum = 0.0
    private var started = false
    private var lastSize = CGSize.zero
    private let runtime = PieceRuntime.shared

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .linear
        layer.minificationFilter = .trilinear
        backgroundColor = .black
        isOpaque = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = bounds.size
        if s.width < 2 || s.height < 2 { return }
        if !started { started = true; lastSize = s; restart(); return }
        if abs(s.width - lastSize.width) > 2 || abs(s.height - lastSize.height) > 2 {
            lastSize = s
            if let inst {
                let (pw, ph, dpr) = pixelSize()
                let rt = runtime
                rt.queue.async { rt.resize(inst, pxW: pw, pxH: ph, dpr: dpr) }
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else if started && inst == nil { restart() } else { link?.isPaused = !running }
    }

    private func pixelSize() -> (Int, Int, Double) {
        let dpr = min(Double(window?.screen.scale ?? UIScreen.main.scale), 2)
        return (max(2, Int(bounds.width * dpr)), max(2, Int(bounds.height * dpr)), dpr)
    }

    private func stop() {
        generation += 1
        link?.invalidate()
        link = nil
        inst = nil   // its deinit frees the JavaScript side
        busy = false
    }

    func restart() {
        stop()
        guard started, !pieceID.isEmpty, window != nil || superview != nil else { return }
        let gen = generation
        let (pw, ph, dpr) = pixelSize()
        let id = pieceID
        frames = 0
        msSum = 0
        Task { @MainActor [weak self] in
            guard let made = await PieceRuntime.shared.makeInstance(id, pxW: pw, pxH: ph, dpr: dpr) else { self?.fail(gen, blank: true); return }
            guard let self, gen == self.generation else { return }
            self.inst = made
            self.onInfo?(made.info)
            self.warmUp(made, gen)
        }
    }

    /// The warm-up frames run in slices so a heavy piece never freezes the screen before its first picture.
    private func warmUp(_ made: PieceInstance, _ gen: Int) {
        let rt = runtime
        let box = WeakBox(self)
        rt.queue.async {
            let t0 = CACurrentMediaTime()
            var left = made.warmLeft
            while left > 0 && CACurrentMediaTime() - t0 < 0.012 { left = rt.warm(made, frames: 4) }
            let img = rt.draw(made)
            let remaining = left
            Task { @MainActor in
                guard let v = box.value, gen == v.generation else { return }
                v.layer.contents = img
                if remaining > 0 { v.warmUp(made, gen) } else { v.begin(gen) }
            }
        }
    }

    private func begin(_ gen: Int) {
        guard gen == generation, link == nil else { return }
        let l = CADisplayLink(target: LinkProxy(self), selector: #selector(LinkProxy.tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps), maximum: Float(fps), preferred: Float(fps))
        l.add(to: .main, forMode: .common)
        l.isPaused = !running
        link = l
    }

    fileprivate func tick() {
        guard !busy, let made = inst, running else { return }
        busy = true
        let gen = generation
        let rt = runtime
        let box = WeakBox(self)
        rt.queue.async {
            let t0 = CACurrentMediaTime()
            rt.pushAudio(VJAudio.shared.read())
            rt.pump()
            let img = rt.draw(made)
            rt.collectIfHeavy()
            let ms = (CACurrentMediaTime() - t0) * 1000
            let flat = rt.world.surface(made.canvasID).map { Self.isFlat($0) } ?? false
            Task { @MainActor in
                guard let v = box.value, gen == v.generation else { return }
                v.busy = false
                v.layer.contents = img
                v.frames += 1
                if v.frames <= 60 { v.msSum += ms; if v.frames == 60, v.msSum / 60 > 40 { v.stop(); v.onSlow?(); return } }
                // a canvas of one flat colour is a failed draw, not a dark piece: checked twice (S308), as the web card does
                if (v.frames == 45 || v.frames == 300) && flat && v.frames == 300 { v.stop(); v.onBlank?() }
            }
        }
    }

    private func fail(_ gen: Int, blank: Bool) { if gen == generation { stop(); onBlank?() } }

    /// Samples the bitmap the way CurateDeck does: every 29th pixel against the first.
    nonisolated private static func isFlat(_ s: CanvasSurface) -> Bool {
        let p = s.data.assumingMemoryBound(to: UInt8.self)
        let n = s.w * s.h
        var i = 29
        while i < n {
            let o = i * 4
            if p[o] != p[0] || p[o + 1] != p[1] || p[o + 2] != p[2] { return false }
            i += 29
        }
        return true
    }

    /// The picture as it is now (SNAP, share).
    func snapshot() -> UIImage? {
        guard let inst, let img = runtime.world.surface(inst.canvasID)?.snapshot() else { return nil }
        return UIImage(cgImage: img)
    }

}

private final class LinkProxy: NSObject {
    weak var target: PieceDisplay?
    init(_ t: PieceDisplay) { target = t }
    @objc func tick() { target?.tick() }
}

struct LivePieceView: UIViewRepresentable {
    let pieceID: String
    var fps = 60
    var running = true
    var onSlow: (() -> Void)?
    var onBlank: (() -> Void)?
    var onInfo: ((PieceInfo) -> Void)?

    func makeUIView(context: Context) -> PieceDisplay {
        let v = PieceDisplay()
        v.fps = fps
        v.onSlow = onSlow
        v.onBlank = onBlank
        v.onInfo = onInfo
        v.pieceID = pieceID
        return v
    }

    func updateUIView(_ v: PieceDisplay, context: Context) {
        v.onSlow = onSlow
        v.onBlank = onBlank
        v.running = running
        if v.pieceID != pieceID { v.pieceID = pieceID }
    }

    static func dismantleUIView(_ v: PieceDisplay, coordinator: ()) { v.running = false }
}

// MARK: - the card (Curate, the Library)

/// A code piece as a card: the live piece, with the same fallbacks the web card has. A piece that cannot hold its frame rate plays its
/// recorded clip (the file that would post), else its capture; a piece that draws nothing shows its still.
struct LivePieceCard: View {
    let model: AppModel
    let pieceID: String
    var thumb: URL?
    @State private var slow = false
    @State private var blank = false
    @State private var recorded: URL?

    var body: some View {
        CodeArtGate(model: model) {
            ZStack {
                if let recorded, slow { RecordedClip(url: recorded) }
                else if slow || blank || PieceRuntime.shared.info(pieceID) == nil { still }
                else { LivePieceView(pieceID: pieceID, onSlow: { slow = true }, onBlank: { blank = true }) }
            }
            .task(id: pieceID) {
                slow = false; blank = false
                recorded = await Self.recording(for: pieceID, model: model)
            }
        }
    }

    @ViewBuilder private var still: some View {
        if let thumb {
            AsyncImage(url: thumb) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
        } else {
            ContentUnavailableView("No picture yet", systemImage: "photo", description: Text("This piece has not been captured."))
        }
    }

    /// piece id to its newest recorded clip, from the gallery's cinematic manifest (kept once per launch).
    private static func recording(for id: String, model: AppModel) async -> URL? {
        guard let http = model.http else { return nil }
        let map = await RecordingMap.shared.load(http: http)
        guard let file = map[id], var base = model.config?.origin("gallery")?.base else { return nil }
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/media/cinematic/" + file)
    }
}

actor RecordingMap {
    static let shared = RecordingMap()
    private var map: [String: String]?
    func load(http: HTTPClient) async -> [String: String] {
        if let map { return map }
        var out: [String: String] = [:]
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "cinematic/manifest.json"), timeout: 30),
           let any = try? JSONSerialization.jsonObject(with: d) {
            let items = (any as? [String: Any])?["items"] as? [[String: Any]] ?? (any as? [[String: Any]]) ?? []
            for it in items { if let p = it["piece"] as? String, let f = it["file"] as? String { out[p] = f } }   // later filings win: the newest recording
        }
        map = out
        return out
    }
}

/// A muted looping clip with a speaker toggle (an iPhone only plays sound after a tap).
struct RecordedClip: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var sound = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let player { VideoPlayer(player: player).disabled(true) }
            Button { sound.toggle(); player?.isMuted = !sound } label: { Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill").padding(10).background(.black.opacity(0.55), in: Circle()).foregroundStyle(.white) }
                .padding(10)
                .accessibilityLabel(sound ? "Sound off" : "Sound on")
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.isMuted = true
            p.actionAtItemEnd = .none
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in p.seek(to: .zero); p.play() }
            p.play()
            player = p
        }
        .onDisappear { player?.pause(); player = nil }
    }
}
