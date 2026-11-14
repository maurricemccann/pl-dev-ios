import CoreGraphics
import CryptoKit
import Foundation
import UIKit

/// HAND TRACE (the laptop's `traceData` and `handTrace`): a one-page record of how a piece was drawn, made from its own stroke log. It shows the
/// hand at work. It does not prove who drew it, and it is not a signature. The page (PNG) and its numbers (JSON) leave through the share sheet.
extension NativeCanvasModel {
    struct Trace {
        var strokes = 0, penSeconds = 0.0, pathPx = 0.0, medianSpeed = 0.0, meanPressure = 0.0
        var medianTremor: Double?
        var histogram = [Int](repeating: 0, count: 10)
        var brushes: [String: Int] = [:]
        var size = (0, 0)
        var digest = ""
        var speeds: [Double] = []
    }

    /// The shake: how far the path wanders from its own smoothed self, in pixels (RMS), from the logged points.
    static func tremorOf(_ pts: [[Any]]) -> Double? {
        let n = pts.count
        guard n >= 40, num(pts[n - 1][3]) - num(pts[0][3]) >= 300 else { return nil }
        let xs = pts.map { num($0[0]) }, ys = pts.map { num($0[1]) }
        var sx = [Double](repeating: 0, count: n), sy = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var a = 0.0, b = 0.0, c = 0.0
            for k in max(0, i - 6)...min(n - 1, i + 6) { a += xs[k]; b += ys[k]; c += 1 }
            sx[i] = a / c; sy[i] = b / c
        }
        var s = 0.0, c = 0.0
        for i in 7..<(n - 7) {
            let tx = sx[i + 3] - sx[i - 3], ty = sy[i + 3] - sy[i - 3], m = max(1e-9, hypot(tx, ty))
            let r = ((xs[i] - sx[i]) * -ty + (ys[i] - sy[i]) * tx) / m
            s += r * r; c += 1
        }
        return c > 0 ? (s / c).squareRoot() : nil
    }

    func traceData() -> Trace? {
        guard let d = doc else { return nil }
        let recs = d.log.filter { r in
            r["dead"] as? Bool != true && r["onMask"] as? Bool != true && (r["tool"] as? String) == "paint" && ((r["pts"] as? [[Any]])?.count ?? 0) > 1
        }
        guard !recs.isEmpty else { return nil }
        var t = Trace(), ms = 0.0, pr = 0.0, prn = 0.0, trem: [Double] = []
        for r in recs {
            guard let p = r["pts"] as? [[Any]] else { continue }
            let dt = max(1, Self.num(p[p.count - 1][3]) - Self.num(p[0][3]))
            ms += dt
            var l = 0.0
            for i in 1..<p.count { l += hypot(Self.num(p[i][0]) - Self.num(p[i - 1][0]), Self.num(p[i][1]) - Self.num(p[i - 1][1])) }
            t.pathPx += l; t.speeds.append(l / dt)
            for q in p { let v = Self.num(q[2]); pr += v; prn += 1; t.histogram[min(9, Int(floor(v * 10)))] += 1 }
            if let tr = Self.tremorOf(p) { trem.append(tr) }
            t.brushes[r["brush"] as? String ?? "", default: 0] += 1
        }
        func med(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.sorted()[a.count >> 1] }
        t.strokes = recs.count; t.penSeconds = (ms / 100).rounded() / 10; t.pathPx = t.pathPx.rounded()
        t.medianSpeed = ((med(t.speeds) ?? 0) * 1000).rounded() / 1000
        t.meanPressure = (pr / max(1, prn) * 100).rounded() / 100
        t.medianTremor = med(trem).map { ($0 * 100).rounded() / 100 }
        t.size = (d.w, d.h)
        let compact = recs.map { r -> String in
            let pts = (r["pts"] as? [[Any]] ?? []).map { $0.map { "\($0)" }.joined(separator: ",") }.joined(separator: ";")
            return [r["brush"] as? String ?? "", "\(r["size"] ?? "")", r["color"] as? String ?? "", pts].joined(separator: "|")
        }.joined(separator: "\n")
        t.digest = "sha256:" + SHA256.hash(data: Data(compact.utf8)).map { String(format: "%02x", $0) }.joined()
        return t
    }

    /// Makes the page and the numbers, and hands them to the share sheet.
    func handTrace() {
        guard let d = doc else { return }
        guard let T = traceData() else { say("Hand trace: no strokes to trace yet."); return }
        let W = 1240.0, H = 1754.0
        let ink = UIColor(red: 0.082, green: 0.071, blue: 0.043, alpha: 1), mute = UIColor(red: 0.42, green: 0.384, blue: 0.329, alpha: 1), gold = UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let isoDay = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: .now) }()
        let page = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { rc in
            let c = rc.cgContext
            UIColor(red: 0.937, green: 0.914, blue: 0.863, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
            func text(_ s: String, _ x: Double, _ y: Double, size: Double, weight: UIFont.Weight = .regular, color: UIColor) {
                NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: CGPoint(x: x, y: y - size))
            }
            text("Hand trace", 70, 110, size: 54, weight: .semibold, color: ink)
            text("\(name)  ·  \(isoDay)", 70, 156, size: 26, color: ink)
            var y = 200.0
            if let flat = d.compositeBuffer(includeBackground: true)?.ctx.makeImage() {
                let k = min(1100 / Double(flat.width), 640 / Double(flat.height)), tw = Double(flat.width) * k, th = Double(flat.height) * k
                c.saveGState(); c.setShadow(offset: .zero, blur: 16, color: UIColor(white: 0, alpha: 0.25).cgColor); UIColor.white.setFill(); c.fill(CGRect(x: 70, y: y, width: tw, height: th)); c.restoreGState()
                UIImage(cgImage: flat).draw(in: CGRect(x: 70, y: y, width: tw, height: th))
                y += th + 70
            }
            func row(_ a: String, _ b: String) {
                text(a, 70, y, size: 24, color: mute); text(b, 480, y, size: 28, weight: .semibold, color: ink); y += 46
            }
            row("Strokes", "\(T.strokes)")
            row("Pen time", "\(Int(T.penSeconds) / 60) min \(Int(T.penSeconds.rounded()) % 60) s")
            row("Path drawn", "\(Int(T.pathPx)) px")
            row("Median speed", "\(T.medianSpeed) px per ms")
            row("Mean pressure", "\(T.meanPressure)")
            row("Median shake (tremor)", T.medianTremor.map { "\($0) px" } ?? "too few long strokes")
            row("Brushes", T.brushes.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            y += 20
            text("Pressure, from light to heavy", 70, y, size: 22, color: mute)
            let mx = Double(max(T.histogram.max() ?? 1, 1))
            ink.setFill()
            for (i, v) in T.histogram.enumerated() { let h = 150 * Double(v) / mx; c.fill(CGRect(x: 70 + Double(i) * 56, y: y + 20 + (150 - h), width: 44, height: h)) }
            y += 220
            text("Speed of the first strokes (each bar one stroke)", 70, y, size: 22, color: mute)
            let sp = Array(T.speeds.prefix(40)), sm = max(sp.max() ?? 0.001, 0.001)
            gold.setFill()
            for (i, v) in sp.enumerated() { let h = 110 * v / sm; c.fill(CGRect(x: 70 + Double(i) * 27, y: y + 20 + (110 - h), width: 20, height: h)) }
            y += 170
            text("Record: \(T.digest.prefix(40))…", 70, y, size: 20, color: ink); y += 34
            for l in ["A record of process, made from this app’s stroke log: how the piece was drawn, in time.", "It shows the hand at work. It does not prove who drew it, and it is not a signature."] {
                text(l, 70, y, size: 22, color: mute); y += 30
            }
        }
        let json: [String: Any] = ["name": name, "strokes": T.strokes, "pen_seconds": T.penSeconds, "path_px": Int(T.pathPx), "median_speed_px_ms": T.medianSpeed,
                                   "mean_pressure": T.meanPressure, "median_tremor_px": T.medianTremor.map { $0 as Any } ?? NSNull(), "pressure_histogram": T.histogram,
                                   "brushes": T.brushes, "size": [T.size.0, T.size.1], "digest": T.digest]
        let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmm"
        let stamp = f.string(from: .now)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        let pu = dir.appendingPathComponent("PL Paint hand trace \(stamp).png"), ju = dir.appendingPathComponent("PL Paint hand trace \(stamp).json")
        if let png = page.pngData(), (try? png.write(to: pu)) != nil { urls.append(pu) }
        if let jd = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]), (try? jd.write(to: ju)) != nil { urls.append(ju) }
        guard !urls.isEmpty else { say("Hand trace not made."); return }
        shareURLs = urls
        panel = .shareFiles
        say("Hand trace made: \(T.strokes) strokes.")
    }
}
