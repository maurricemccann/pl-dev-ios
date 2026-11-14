import AVFoundation
import CoreGraphics
import Foundation
import UIKit

/// Timelapse by colour pass, and the "alive" breathing loop (the laptop's `tlBuildPasses`, `breatheFrames`, `tlSave(0, 'alive')`).
/// A pass is one colour: the picture is built one colour at a time, in the order the colours first appeared (the screen-print pass order), every
/// stroke drawn again from the log on a scratch canvas that never saves or counts. The alive loop is the finished picture breathing: each part
/// of it on its own slow cycle, looping with no seam, after the build.
struct NativeFrameBox: @unchecked Sendable { let image: CGImage }

extension NativeCanvasModel {
    /// Draws the log again one colour at a time and keeps a frame as each colour fills in. Returns the number of colours, or nil with a word.
    func buildPasses(progress: @escaping (Double) -> Void) async -> Int? {
        guard live == nil, let d = doc else { return nil }
        let recs = d.log.filter { r in r["dead"] as? Bool != true && r["onMask"] as? Bool != true && (r["tool"] as? String) == "paint" && ((r["pts"] as? [[Any]])?.isEmpty == false) }
        guard !recs.isEmpty else { say("Passes: no strokes to build passes from."); return nil }
        var order: [String] = [], groups: [String: [[String: Any]]] = [:]
        for r in recs {
            let k = (r["color"] as? String ?? "#000000").lowercased()
            if groups[k] == nil { groups[k] = []; order.append(k) }
            groups[k]?.append(r)
        }
        guard let nd = try? NativeDoc(w: d.w, h: d.h, bg: d.bg) else { say("Passes: this phone has no room for the scratch canvas."); return nil }
        nd.bgVis = d.bgVis
        let sm = NativeCanvasModel()
        sm.scratch = true; sm.replaying = true; sm.doc = nd; sm.hasDoc = true
        sm.tile = tile; sm.stabAll = stabAll; sm.seam = seam; sm.seamOn = seamOn
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("passes-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var frames: [URL] = []
        var n = 0
        func grab() {
            guard let jpg = nd.timelapseFrame() else { return }
            let u = dir.appendingPathComponent(String(format: "%05d.jpg", n)); n += 1
            if (try? jpg.write(to: u)) != nil { frames.append(u) }
        }
        let all = NativeToolkit.all + NativeMine.brushes
        grab()
        var done = 0
        for k in order {
            let g = groups[k] ?? []
            let every = max(1, Int((Double(g.count) / 5).rounded(.up)))
            for (i, r) in g.enumerated() {
                guard let pts = r["pts"] as? [[Any]] else { continue }
                let B = all.first { $0.id == (r["brush"] as? String ?? "") } ?? brush
                sm.sym = SymMode(rawValue: r["sym"] as? String ?? "off") ?? .off
                sm.replay(brush: B, size: max(1, Self.num(r["size"] ?? 8)), op: Self.num(r["op"] ?? 1), color: r["color"] as? String ?? "#000000",
                          color2: (r["color2"] as? String) ?? "#ffffff", layer: 0, pts: pts, tool: .paint)
                done += 1
                if (i + 1) % every == 0 || i == g.count - 1 { grab() }
                if done % 4 == 0 { progress(Double(done) / Double(recs.count)); await Task.yield() }
            }
            if let last = frames.last { for _ in 0..<6 { frames.append(last) } }   // each pass is held a moment before the next colour starts
        }
        let tl = NativeTimelapse.shared
        tl.passFrames = frames
        return order.count
    }
}

/// The breathing loop.
enum NativeAlive {
    /// `seconds` of the finished picture drifting: built by accumulation, then drift, never freeze. Frames are JPEGs in `dir`, the same size the timelapse frames are.
    nonisolated static func frames(flat: NativeFrameBox, width W: Int, height H: Int, bg: (Double, Double, Double), seconds: Double, fps: Int, dir: URL) -> [URL] {
        let N = Int(seconds * Double(fps)), amp = Double(W) * 0.0042, M = 22
        var out: [URL] = []
        for i in 0..<N {
            guard let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            c.interpolationQuality = .high
            c.setFillColor(CGColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
            c.draw(flat.image, in: CGRect(x: 0, y: 0, width: W, height: H))   // the still picture underneath, so no hairline shows between the pieces of the mesh
            c.translateBy(x: 0, y: Double(H)); c.scaleBy(x: 1, y: -1)         // the mesh works in picture space, y down
            let t = Double(i) / Double(N), TWO = Double.pi * 2
            func map(_ u: Double, _ v: Double) -> CGPoint {
                let x = u * Double(W), y = v * Double(H), edge = min(1, u * 8, (1 - u) * 8, v * 8, (1 - v) * 8)
                return CGPoint(x: x + edge * amp * (sin(TWO * t + x * 0.013 + y * 0.019) + 0.55 * sin(TWO * 2 * t + x * 0.027 - y * 0.011)),
                               y: y + edge * amp * (cos(TWO * t + y * 0.015 - x * 0.012) + 0.55 * cos(TWO * 2 * t + y * 0.021 + x * 0.017)))
            }
            var P: [[CGPoint]] = []
            for j in 0...M { P.append((0...M).map { map(Double($0) / Double(M), Double(j) / Double(M)) }) }
            for j in 0..<M { for k in 0..<M {
                let s0 = CGPoint(x: Double(k) / Double(M) * Double(W), y: Double(j) / Double(M) * Double(H)), s1 = CGPoint(x: Double(k + 1) / Double(M) * Double(W), y: s0.y)
                let s2 = CGPoint(x: s1.x, y: Double(j + 1) / Double(M) * Double(H)), s3 = CGPoint(x: s0.x, y: s2.y)
                tri(c, flat.image, W, H, s0, s1, s3, P[j][k], P[j][k + 1], P[j + 1][k])
                tri(c, flat.image, W, H, s1, s2, s3, P[j][k + 1], P[j + 1][k + 1], P[j + 1][k])
            } }
            guard let img = c.makeImage(), let jpg = UIImage(cgImage: img).jpegData(compressionQuality: 0.78) else { continue }
            let u = dir.appendingPathComponent(String(format: "alive-%05d.jpg", i))
            if (try? jpg.write(to: u)) != nil { out.append(u) }
        }
        return out
    }

    /// One triangle of the picture laid on its moved place: an affine map from the three source corners to the three destination corners.
    nonisolated private static func tri(_ c: CGContext, _ img: CGImage, _ W: Int, _ H: Int, _ s0: CGPoint, _ s1: CGPoint, _ s2: CGPoint, _ d0: CGPoint, _ d1: CGPoint, _ d2: CGPoint) {
        let det = Double((s1.x - s0.x) * (s2.y - s0.y) - (s2.x - s0.x) * (s1.y - s0.y))
        guard abs(det) > 1e-9 else { return }
        let a = Double((d1.x - d0.x) * (s2.y - s0.y) - (d2.x - d0.x) * (s1.y - s0.y)) / det
        let cc = Double((d2.x - d0.x) * (s1.x - s0.x) - (d1.x - d0.x) * (s2.x - s0.x)) / det
        let b = Double((d1.y - d0.y) * (s2.y - s0.y) - (d2.y - d0.y) * (s1.y - s0.y)) / det
        let dd = Double((d2.y - d0.y) * (s1.x - s0.x) - (d1.y - d0.y) * (s2.x - s0.x)) / det
        let tx = Double(d0.x) - a * Double(s0.x) - cc * Double(s0.y), ty = Double(d0.y) - b * Double(s0.x) - dd * Double(s0.y)
        c.saveGState()
        c.move(to: d0); c.addLine(to: d1); c.addLine(to: d2); c.closePath(); c.clip()
        c.concatenate(CGAffineTransform(a: a, b: b, c: cc, d: dd, tx: tx, ty: ty))
        c.translateBy(x: 0, y: Double(H)); c.scaleBy(x: 1, y: -1)   // the picture is upright; the mesh is y-down
        c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        c.restoreGState()
    }
}

extension NativeCanvasModel {
    /// The build (a few seconds of the timelapse) and then the breathing loop, as one video to share.
    func makeAliveVideo(progress: @escaping @Sendable (Double) -> Void) async -> URL? {
        guard live == nil, let d = doc else { return nil }
        let tl = NativeTimelapse.shared
        let recorded = tl.recordedFiles()
        let build = NativeTimelapse.pick(recorded, seconds: 4, fps: 24)
        let W = 960, H = max(2, Int((Double(d.h) * Double(W) / Double(d.w)).rounded()) & ~1)
        guard let flat = d.compositeBuffer(includeBackground: true)?.heldImage() else { say("The picture could not be flattened."); return nil }
        let bgc = d.bgVis ? (Hex.rgb(d.bg) ?? (1, 1, 1)) : (1, 1, 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("alive-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let box = NativeFrameBox(image: flat)
        let alive = await Task.detached(priority: .userInitiated) { NativeAlive.frames(flat: box, width: W, height: H, bg: bgc, seconds: 6, fps: 24, dir: dir) }.value
        guard !alive.isEmpty else { say("The loop could not be made."); return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) alive.mp4")
        do {
            try await NativeTimelapse.writeVideo(frames: build + alive, fps: 24, to: url, progress: progress)
            return url
        } catch { say("The video could not be written."); return nil }
    }
}
