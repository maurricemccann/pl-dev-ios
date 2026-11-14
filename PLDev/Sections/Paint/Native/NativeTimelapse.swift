import AVFoundation
import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UIKit

/// The Timelapse: a small picture after every change (the laptop's `tlCapture`), kept on the phone beside the work; replay it, or make a
/// video of it. Frames are JPEGs 960 px wide in a folder per work, so a long session costs disk, not memory.
@MainActor @Observable final class NativeTimelapse {
    static let shared = NativeTimelapse()
    static let cap = 2400
    var count = 0
    var recording = true { didSet { UserDefaults.standard.set(recording, forKey: "plpaint-tl-rec") } }
    @ObservationIgnored private var workID: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init() { recording = UserDefaults.standard.object(forKey: "plpaint-tl-rec") as? Bool ?? true }

    static func folder(_ id: String) -> URL {
        let u = NativeStore.dir.appendingPathComponent("timelapse-\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    /// Colour passes: the picture built one colour at a time, drawn again from the stroke log (the laptop's `tlBuildPasses`). Replay and the video use them when `byPass` is on.
    var passFrames: [URL] = []
    var byPass = false
    var busyNote: String?
    func files() -> [URL] {
        if byPass && !passFrames.isEmpty { return passFrames }
        return recordedFiles()
    }
    func recordedFiles() -> [URL] {
        guard let id = workID else { return [] }
        let list = (try? FileManager.default.contentsOfDirectory(at: Self.folder(id), includingPropertiesForKeys: nil)) ?? []
        return list.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    /// A work was opened: count what it already has.
    func attach(_ id: String?) { task?.cancel(); workID = id; passFrames = []; byPass = false; count = recordedFiles().count }
    func discard(_ id: String) { try? FileManager.default.removeItem(at: NativeStore.dir.appendingPathComponent("timelapse-\(id)", isDirectory: true)); if id == workID { count = 0 } }
    func clear() { if let id = workID { discard(id); count = 0 } }

    /// The work changed: one frame, a moment after the last change (changes close together make one frame).
    func changed(_ canvas: NativeCanvasModel) {
        guard recording, workID != nil, canvas.doc != nil else { return }
        task?.cancel()
        task = Task { [weak self, weak canvas] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, let canvas else { return }
            if canvas.live != nil { self.changed(canvas); return }
            self.capture(canvas)
        }
    }

    func capture(_ canvas: NativeCanvasModel) {
        guard let id = workID, let d = canvas.doc, let jpg = d.timelapseFrame() else { return }
        let n = recordedFiles().count
        if n >= Self.cap { thin() }
        let name = String(format: "%05d.jpg", (recordedFiles().last.flatMap { Int($0.deletingPathExtension().lastPathComponent) } ?? -1) + 1)
        try? jpg.write(to: Self.folder(id).appendingPathComponent(name), options: .atomic)
        count = recordedFiles().count
    }

    /// Over the cap: every other frame goes, so a very long session still plays from the first stroke to the last.
    private func thin() {
        for (i, u) in recordedFiles().enumerated() where i % 2 == 1 { try? FileManager.default.removeItem(at: u) }
    }

    // MARK: the video

    nonisolated static func writeVideo(frames: [URL], fps: Int, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let first = frames.first, let probe = UIImage(contentsOfFile: first.path), let cg0 = probe.cgImage else { throw NativeTimelapseError.empty }
        let W = cg0.width & ~1, H = cg0.height & ~1
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                                                                          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NativeTimelapseError.empty }
        writer.startSession(atSourceTime: .zero)
        for (i, f) in frames.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
            guard let cg = UIImage(contentsOfFile: f.path)?.cgImage, let pool = adaptor.pixelBufferPool else { continue }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let buf = pb else { continue }
            CVPixelBufferLockBaseAddress(buf, [])
            if let c = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                c.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            adaptor.append(buf, withPresentationTime: CMTime(value: Int64(i), timescale: Int32(fps)))
            if i % 8 == 0 { progress(Double(i) / Double(frames.count)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? NativeTimelapseError.empty }
    }

    /// `seconds` = 0: every frame at 30 fps; otherwise exactly that long, picking frames evenly.
    static func pick(_ all: [URL], seconds: Int, fps: Int = 30) -> [URL] {
        guard seconds > 0, !all.isEmpty else { return all }
        let n = seconds * fps
        return (0..<n).map { all[min(all.count - 1, $0 * all.count / n)] }
    }
}

enum NativeTimelapseError: Error { case empty }

extension NativeDoc {
    /// The picture at 960 px wide for the timelapse: groups' visibility and opacity, blends the system has, masks and clips.
    func timelapseFrame(width W: Int = 960) -> Data? {
        let k = Double(W) / Double(w), H = max(2, Int((Double(h) * k).rounded()) & ~1)
        guard let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: W, height: H)
        c.setFillColor(bgVis ? (Hex.color(bg) ?? CGColor(gray: 1, alpha: 1)) : CGColor(gray: 1, alpha: 1)); c.fill(rect)
        c.interpolationQuality = .medium
        for i in layers.indices where isShown(layers[i]) {
            let l = layers[i]
            let needs = l.maskPx != nil || clipBase(of: i) != nil
            guard let img = needs ? effectiveImage(of: i) : l.pixels.image() else { continue }
            c.saveGState()
            c.setAlpha(CGFloat(shownOpacity(l))); c.setBlendMode(NativeBlend.mode(l.meta["blend"] as? String).cg ?? .normal)
            c.draw(img, in: rect)
            c.restoreGState()
        }
        return c.makeImage().flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.72) }
    }
}

struct NativeTimelapseSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var tl = NativeTimelapse.shared
    @State private var frames: [URL] = []
    @State private var at = 0.0
    @State private var playing = false
    @State private var player: Task<Void, Never>?
    @State private var seconds = 20
    @State private var making: Double?
    @State private var shareURL: URL?
    @State private var line: String?
    @State private var confirmClear = false
    @State private var passBusy: Double?
    @State private var aliveBusy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Record as I draw", isOn: $tl.recording)
                    LabeledContent("Frames", value: "\(tl.count)")
                } footer: { Text("A small picture is kept after every change. The recording stays on this iPhone, beside the work.") }
                if frames.count > 1 {
                    Section("Replay") {
                        Group {
                            if let img = UIImage(contentsOfFile: frames[min(frames.count - 1, Int(at))].path) { Image(uiImage: img).resizable().scaledToFit() } else { Color.clear }
                        }
                        .frame(maxWidth: .infinity).frame(height: 230).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        HStack {
                            Button { playing ? stop() : play() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 34) }.buttonStyle(.bordered)
                            Slider(value: $at, in: 0...Double(frames.count - 1))
                        }
                    }
                    Section("Video") {
                        Picker("Length", selection: $seconds) {
                            Text("Every frame").tag(0); Text("10 seconds").tag(10); Text("20 seconds").tag(20); Text("30 seconds").tag(30); Text("60 seconds").tag(60)
                        }
                        Button { Task { await make() } } label: { Label(making == nil ? "Make the video" : "Making the video…", systemImage: "film") }.disabled(making != nil)
                        if making != nil { ProgressView() }
                    }
                    Section {
                        Toggle("By colour pass", isOn: Binding(get: { tl.byPass }, set: { on in Task { await setPass(on) } })).disabled(passBusy != nil)
                        if let pb = passBusy { ProgressView(value: pb) }
                        Button { Task { await makeAlive() } } label: { Label(aliveBusy ? "Making the loop…" : "Make the alive loop", systemImage: "wind") }.disabled(aliveBusy || passBusy != nil)
                    } header: { Text("Passes and the loop") } footer: { Text("By colour pass builds the picture one colour at a time, in the order the colours first appeared, from the stroke log; replay and the video then follow it. The alive loop is a few seconds of the build, then the finished picture breathing.") }
                    Section { Button("Clear the recording", role: .destructive) { confirmClear = true } }
                } else {
                    Section { ContentUnavailableView("Nothing recorded yet", systemImage: "play.rectangle", description: Text("Draw a little. Each change keeps a small picture, and they play back here.")) }
                }
                if let line { Section { ResultLine(text: line) } }
            }
            .navigationTitle("Timelapse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); dismiss() } } }
            .confirmationDialog("Clear this work's timelapse?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear the recording", role: .destructive) { stop(); tl.clear(); frames = []; at = 0 }
            } message: { Text("The frames are deleted. The work itself is not touched.") }
            .sheet(item: Binding(get: { shareURL.map { TLURL(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { ShareSheet(items: [$0.url]) }
            .task { frames = tl.files(); at = Double(max(0, frames.count - 1)) }
            .onDisappear { stop() }
        }
    }

    private func setPass(_ on: Bool) async {
        stop()
        if !on { tl.byPass = false; frames = tl.files(); at = 0; return }
        passBusy = 0
        let n = await canvas.buildPasses { passBusy = $0 }
        passBusy = nil
        if let n { tl.byPass = true; frames = tl.files(); at = 0; line = "Replay and the video now run by colour pass: \(n) colour\(n == 1 ? "" : "s")." }
        else { line = canvas.line ?? "Passes could not be built." }
    }

    private func makeAlive() async {
        stop()
        aliveBusy = true; line = nil
        let url = await canvas.makeAliveVideo { _ in }
        aliveBusy = false
        if let url { shareURL = url } else { line = canvas.line ?? "The loop could not be made." }
    }

    private struct TLURL: Identifiable { let url: URL; var id: String { url.path } }

    private func play() {
        guard frames.count > 1 else { return }
        if at >= Double(frames.count - 1) { at = 0 }
        playing = true
        let step = max(1, frames.count / 600)   // a long recording is stepped, so it plays in about 20 seconds at most
        player = Task {
            while !Task.isCancelled, at < Double(frames.count - 1) {
                try? await Task.sleep(for: .milliseconds(33))
                at = min(Double(frames.count - 1), at + Double(step))
            }
            playing = false
        }
    }
    private func stop() { player?.cancel(); playing = false }

    private func make() async {
        stop()
        let list = NativeTimelapse.pick(frames, seconds: seconds)
        guard !list.isEmpty else { return }
        making = 0; line = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(canvas.name) timelapse.mp4")
        do {
            try await NativeTimelapse.writeVideo(frames: list, fps: 30, to: url) { _ in }
            making = nil; shareURL = url
        } catch { making = nil; line = "Not made. The video could not be written." }
    }
}
