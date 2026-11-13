import CryptoKit
import SwiftUI
import UIKit

/// The screen's side of the VJ instrument: what the knobs say, the presets, SNAP and REC. The engine reads `p` each frame.
@MainActor @Observable final class VJModel {
    let engine = VJEngine()
    var p = VJParams() { didSet { engine.shared.set(p); save() } }
    var presets: [VJParams?] = Array(repeating: nil, count: 8)
    var nameA = ""
    var nameB = ""
    var bass = 0.0
    var mid = 0.0
    var high = 0.0
    var beat = false
    var playing = false
    var seqStep = 0
    var recording = false
    var line: String?
    var share: ShareItem?
    var pieces: [PieceInfo] = []
    private var taps: [Double] = []
    private var started = false

    private static let paramsKey = "pldev.vj.params"
    private static let presetsKey = "pldev.vj.presets"

    /// The pieces the instrument plays: the live set the gallery's /live uses, or every piece when the archive is included.
    func refreshPieces() {
        let all = PieceRuntime.shared.pieces
        pieces = p.includeArchive ? all : all.filter(\.live)
        engine.setOrder(pieces.map(\.id))
    }

    func start() {
        guard !started else { return }
        started = true
        if let d = UserDefaults.standard.data(forKey: Self.paramsKey), let v = try? JSONDecoder().decode(VJParams.self, from: d) { p = v }
        if let d = UserDefaults.standard.data(forKey: Self.presetsKey), let v = try? JSONDecoder().decode([VJParams?].self, from: d), v.count == 8 { presets = v }
        refreshPieces()
        if p.pieceA.isEmpty || PieceRuntime.shared.info(p.pieceA) == nil { p.pieceA = pieces.first?.id ?? "" }
        engine.shared.set(p)
        engine.onEvent = { [weak self] e in Task { @MainActor in self?.handle(e) } }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: Self.paramsKey) }
    }

    private func savePresets() {
        if let d = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(d, forKey: Self.presetsKey) }
    }

    private func handle(_ e: VJEvent) {
        switch e {
        case .levels(let b, let m, let h, let bt, let pl): bass = b; mid = m; high = h; beat = bt; playing = pl
        case .piece(let deck, let id, let name):
            if deck == 0 { nameA = name; if p.pieceA != id { p.pieceA = id } } else { nameB = name }
        case .seqStep(let i): seqStep = i
        case .problem(let s): line = "Not done. \(s)"
        }
    }

    // MARK: pieces

    func name(_ id: String) -> String { PieceRuntime.shared.info(id)?.name ?? (id.isEmpty ? "Empty" : id) }

    func choose(_ id: String, for target: VJTarget) {
        switch target {
        case .deckA: p.pieceA = id
        case .deckB: p.pieceB = id; p.layerBOn = true
        case .slot(let i): p.slots[i] = id
        case .step(let i): p.seq[i] = id
        }
    }

    func step(_ d: Int) {
        guard !pieces.isEmpty else { return }
        let i = pieces.firstIndex { $0.id == p.pieceA } ?? 0
        p.pieceA = pieces[(i + d + pieces.count) % pieces.count].id
    }

    func randomPiece() { if let r = pieces.randomElement() { p.pieceA = r.id } }

    // MARK: tempo

    func tapTempo() {
        let now = Date().timeIntervalSince1970
        if let last = taps.last, now - last > 2 { taps.removeAll() }
        taps.append(now)
        if taps.count > 5 { taps.removeFirst() }
        if taps.count >= 2 {
            let gaps = zip(taps.dropFirst(), taps).map { $0 - $1 }
            let avg = gaps.reduce(0, +) / Double(gaps.count)
            if avg > 0.2 && avg < 2 { p.bpm = (60 / avg).rounded() }
        }
    }

    func autoTempo() { p.bpm = 0; taps.removeAll() }

    // MARK: presets

    func savePreset(_ i: Int) {
        var s = p
        s.seqOn = false
        presets[i] = s
        savePresets()
        line = "Saved to set \(i + 1)."
    }

    func recall(_ i: Int) {
        guard let s = presets[i] else { return }
        let archive = p.includeArchive
        p = s
        p.includeArchive = archive
        line = "Set \(i + 1)."
    }

    func clearPreset(_ i: Int) { presets[i] = nil; savePresets(); line = "Set \(i + 1) cleared." }

    // MARK: SNAP and REC

    /// A still of the live output: shared (which can save it to Photos) and filed to the vault's snaps folder, as /live does.
    func snap(model: AppModel) {
        engine.snap { [weak self] data, w, h in
            guard let data, let img = VJModel.image(bgra: data, w: w, h: h) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.share = ShareItem(items: [img])
                self.line = "Saved a still."
                if let png = img.pngData() { await self.fileToVault(png, model: model) }
            }
        }
    }

    nonisolated static func image(bgra: Data, w: Int, h: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: bgra as CFData), let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func fileToVault(_ png: Data, model: AppModel) async {
        guard let http = model.http, let key = model.config?.key("vault") else { return }
        let token = SHA256.hash(data: Data("pl-lib-unlock:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
        let name = "snaps/pl-live-\(Int(Date().timeIntervalSince1970)).png"
        do {
            _ = try await http.send(RequestPlan(origin: "gallery", method: "PUT", path: "api/vault/upload", query: ["key": name],
                                                headers: ["content-type": "image/png", "Origin": LibraryData.shared.base(model)], body: png),
                                    idempotent: false, extraHeaders: ["Cookie": "pl_lib=\(token)"])
        } catch { line = "Saved a still. The vault did not take it." }
    }

    func toggleRecording() {
        if recording {
            recording = false
            engine.stopRecording { [weak self] url in
                Task { @MainActor in
                    guard let self else { return }
                    if let url { self.share = ShareItem(items: [url]); self.line = "Saved a clip." } else { self.line = "Not saved. The clip could not be written." }
                }
            }
        } else {
            engine.startRecording()
            recording = true
        }
    }
}

enum VJTarget: Identifiable, Hashable {
    case deckA, deckB, slot(Int), step(Int)
    var id: String {
        switch self { case .deckA: return "A"; case .deckB: return "B"; case .slot(let i): return "slot\(i)"; case .step(let i): return "step\(i)" }
    }
    var title: String {
        switch self { case .deckA: return "Deck A"; case .deckB: return "Deck B"; case .slot(let i): return "Pad \(i + 1)"; case .step(let i): return "Step \(i + 1)" }
    }
}
