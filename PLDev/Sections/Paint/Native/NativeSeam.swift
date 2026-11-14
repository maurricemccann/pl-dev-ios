import CoreGraphics
import CoreImage
import Foundation
import UIKit

/// SEAM MODE (the laptop's S348 build, `app.js` seamLoad ... seamLines). A garment's flat pieces on one sheet (`Seam717.json` and `.png`, made by
/// the week 3 seam_sheet.py from Printful's cut templates). A mark that runs off a sewn edge carries on at the same place on the edge it is
/// sewn to, turned to that edge's direction and never mirrored, so the drawing is continuous on the finished garment.
final class SeamSide {
    let p: [CGPoint], n: [CGPoint], t: [CGPoint]
    let k: Int
    let x0: Double, y0: Double, x1: Double, y1: Double
    var piece = -1
    weak var to: SeamSide?   // its partner; the sheet holds both
    init(p: [CGPoint], n: [CGPoint], k: Int) {
        self.p = p; self.n = n; self.k = k
        t = p.indices.map { i in
            let a = p[max(0, i - 1)], b = p[min(p.count - 1, i + 1)]
            let l = max(1e-9, hypot(Double(b.x - a.x), Double(b.y - a.y)))
            return CGPoint(x: Double(b.x - a.x) / l, y: Double(b.y - a.y) / l)
        }
        x0 = p.map { Double($0.x) }.min() ?? 0; x1 = p.map { Double($0.x) }.max() ?? 0
        y0 = p.map { Double($0.y) }.min() ?? 0; y1 = p.map { Double($0.y) }.max() ?? 0
    }
}

struct SeamFrame { let yp: Int; let pX: CGPoint, tX: CGPoint, nX: CGPoint, pY: CGPoint, tY: CGPoint, nY: CGPoint; let turn: Double }
struct SeamCopy { var x: Double, y: Double, turn: Double, cx: Double, cy: Double }
struct SeamOut { var skip = false; var items: [SeamCopy] = [] }
struct SeamLevel { var home = -1; var exit: (d: Double, f: SeamFrame)? }
struct SeamStroke { var lv: [SeamLevel] = []; var skip = false; var fs: [SeamFrame] = []; var piece = -1 }

final class SeamSheet {
    let id: String, name: String
    let image: CGImage
    var darkImage: CGImage?
    let pieces: [[CGPoint]]
    let sides: [SeamSide]
    let files: [(name: String, rect: CGRect)]
    let printW: Int, printH: Int

    init?(id: String) {
        guard let ju = Bundle.main.url(forResource: "Seam\(id)", withExtension: "json"), let jd = try? Data(contentsOf: ju),
              let o = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
              let pu = Bundle.main.url(forResource: "Seam\(id)", withExtension: "png"), let img = UIImage(contentsOfFile: pu.path)?.cgImage,
              let ps = o["pieces"] as? [[String: Any]], let ss = o["seams"] as? [[String: Any]] else { return nil }
        func pts(_ v: Any?) -> [CGPoint] { (v as? [[Double]] ?? []).compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } }
        self.id = id
        name = o["name"] as? String ?? id
        image = img
        pieces = ps.map { pts($0["p"]) }
        var sd: [SeamSide] = []
        for (k, s) in ss.enumerated() {
            guard let a = s["a"] as? [String: Any], let b = s["b"] as? [String: Any] else { continue }
            let A = SeamSide(p: pts(a["p"]), n: pts(a["n"]), k: k), B = SeamSide(p: pts(b["p"]), n: pts(b["n"]), k: k)
            guard A.p.count > 1, A.p.count == A.n.count, B.p.count > 1, B.p.count == B.n.count else { continue }
            A.to = B; B.to = A
            sd.append(A); sd.append(B)
        }
        sides = sd
        let pr = o["print"] as? [Any] ?? []
        printW = (pr.first as? Int) ?? 5250
        printH = pr.count > 1 ? ((pr[1] as? Int) ?? 6000) : 6000
        let fl = o["files"] as? [String: [String: Any]] ?? [:]
        func dbl(_ v: Any?) -> Double { (v as? Double) ?? Double(v as? Int ?? 0) }
        files = fl.map { entry in
            let r = entry.value
            return (name: entry.key, rect: CGRect(x: dbl(r["x"]), y: dbl(r["y"]), width: dbl(r["w"]), height: dbl(r["h"])))
        }.sorted { $0.name < $1.name }
        for X in sides {   // the piece each edge belongs to
            let i = X.p.count >> 1
            X.piece = piece(at: CGPoint(x: Double(X.p[i].x) + Double(X.n[i].x) * 6, y: Double(X.p[i].y) + Double(X.n[i].y) * 6))
        }
        let ci = CIImage(cgImage: img)
        if let f = CIFilter(name: "CIColorInvert") {   // a dark ground: the template lines in light
            f.setValue(ci, forKey: kCIInputImageKey)
            if let out = f.outputImage { darkImage = CIContext().createCGImage(out, from: ci.extent) }
        }
    }

    /// Which piece of fabric this spot is on, or -1 on the empty sheet between pieces.
    func piece(at q: CGPoint) -> Int {
        for (k, p) in pieces.enumerated() {
            var inn = false
            var j = p.count - 1
            for i in 0..<p.count {
                if (p[i].y > q.y) != (p[j].y > q.y), Double(q.x) < Double(p[j].x - p[i].x) * Double(q.y - p[i].y) / Double(p[j].y - p[i].y) + Double(p[i].x) { inn.toggle() }
                j = i
            }
            if inn { return k }
        }
        return -1
    }
}

extension NativeCanvasModel {
    static let seamFar = 3000.0
    static let seamHops = 6

    func loadSeam(_ id: String?) {
        guard let id else { seam = nil; seamID = nil; stage?.updateOverlay(); return }
        if let s = SeamSheet(id: id) { seam = s; seamID = id; seamOn = true } else { seam = nil; seamID = nil; say("The seam template \(id) is missing.") }
        stage?.updateOverlay()
    }

    func toggleSeam() {
        guard seam != nil else { say("Seam mode needs a garment template: New canvas, then Hoodie 717."); return }
        seamOn.toggle(); stage?.updateOverlay()
        say("Seam mode \(seamOn ? "on: marks carry across sewn edges" : "off").")
    }

    /// q (and companion c) carried across side X to its partner.
    private func seamMap(_ X: SeamSide, _ q: CGPoint, _ c: CGPoint?, _ lim: Double) -> (d: Double, f: SeamFrame, m: SeamCopy)? {
        let qx = Double(q.x), qy = Double(q.y)
        if qx < X.x0 - lim || qy < X.y0 - lim || qx > X.x1 + lim || qy > X.y1 + lim { return nil }
        var best = 1e18, u = -1.0
        let P = X.p
        for i in 0..<(P.count - 1) {   // nearest point on the edge, as a fractional index (both sides share the index: equal arc steps)
            let ax = Double(P[i].x), ay = Double(P[i].y), dx = Double(P[i + 1].x) - ax, dy = Double(P[i + 1].y) - ay
            let L2 = max(1e-9, dx * dx + dy * dy), f = max(0, min(1, ((qx - ax) * dx + (qy - ay) * dy) / L2))
            let ex = ax + dx * f - qx, ey = ay + dy * f - qy, dd = ex * ex + ey * ey
            if dd < best { best = dd; u = Double(i) + f }
        }
        if u < 0 || best > lim * lim { return nil }
        func at(_ arr: [CGPoint], _ v: Double) -> CGPoint {
            let i = min(arr.count - 2, Int(floor(v))), f = v - Double(i)
            return CGPoint(x: Double(arr[i].x) + Double(arr[i + 1].x - arr[i].x) * f, y: Double(arr[i].y) + Double(arr[i + 1].y - arr[i].y) * f)
        }
        let pX = at(X.p, u), nX = at(X.n, u), tX = at(X.t, u)
        guard let Y = X.to else { return nil }
        let pY = at(Y.p, u), nY = at(Y.n, u), tY = at(Y.t, u)
        let along = (qx - Double(pX.x)) * Double(tX.x) + (qy - Double(pX.y)) * Double(tX.y)
        if abs(along) > 2 { return nil }   // past the end of the edge (a corner): the next seam takes it
        let f = SeamFrame(yp: Y.piece, pX: pX, tX: tX, nX: nX, pY: pY, tY: tY, nY: nY, turn: atan2(Double(tY.y), Double(tY.x)) - atan2(Double(tX.y), Double(tX.x)))
        return (best, f, seamFrame(f, q, c))
    }

    /// q in the frame of this edge (along it, depth into it) laid down in the partner's frame, depth turned outward: rotation only, never a mirror.
    private func seamFrame(_ f: SeamFrame, _ q: CGPoint, _ c: CGPoint?) -> SeamCopy {
        let vx = Double(q.x - f.pX.x), vy = Double(q.y - f.pX.y)
        let along = vx * Double(f.tX.x) + vy * Double(f.tX.y), h = vx * Double(f.nX.x) + vy * Double(f.nX.y)
        let x = Double(f.pY.x) + Double(f.tY.x) * along - Double(f.nY.x) * h
        let y = Double(f.pY.y) + Double(f.tY.y) * along - Double(f.nY.y) * h
        var cx = x, cy = y
        if let c {
            let ux = Double(c.x - q.x), uy = Double(c.y - q.y), cs = cos(f.turn), sn = sin(f.turn)
            cx = x + ux * cs - uy * sn; cy = y + ux * sn + uy * cs
        }
        return SeamCopy(x: x, y: y, turn: f.turn, cx: cx, cy: cy)
    }

    /// The copies of one dab (and its companion) on the pieces it is sewn into. A chain of pens: the real pen on the piece the stroke started on;
    /// when it leaves through a sewn edge a carried pen goes on, in the frame of that crossing, on the partner piece, and so on round the garment.
    /// A pen that leaves through an unsewn edge (zip end, hem, cuff, the hood's face) ends there.
    func seamCopies(q: CGPoint, c: CGPoint?, reach: Double) -> SeamOut {
        var out = SeamOut()
        guard let S = seam, seamOn else { return out }
        var p = q, cc = c, turn = 0.0
        var fs: [SeamFrame] = []
        seamStroke.skip = false; seamStroke.piece = -1
        defer { seamStroke.fs = fs }
        for i in 0..<Self.seamHops {
            if seamStroke.lv.count <= i { seamStroke.lv.append(SeamLevel()) }
            let k = S.piece(at: p)
            if seamStroke.lv[i].home < 0 { seamStroke.lv[i].home = k }   // the real pen's piece is where it starts, or the first it reaches
            if seamStroke.lv[i].home >= 0 && k != seamStroke.lv[i].home {   // this pen has left its piece: never drawn on the neighbour on the sheet
                if i == 0 { out.skip = true; seamStroke.skip = true }
                guard let e = seamStroke.lv[i].exit, hypot(Double(p.x - e.f.pX.x), Double(p.y - e.f.pX.y)) <= Self.seamFar else { break }
                fs.append(e.f)
                let m = seamFrame(e.f, p, cc)
                p = CGPoint(x: m.x, y: m.y)
                if cc != nil { cc = CGPoint(x: m.cx, y: m.cy) }
                turn += m.turn
                if seamStroke.lv.count <= i + 1 { seamStroke.lv.append(SeamLevel(home: e.f.yp, exit: nil)) }
                continue
            }
            if k < 0 { break }   // not on fabric yet
            seamStroke.piece = k
            if i > 0 { out.items.append(SeamCopy(x: Double(p.x), y: Double(p.y), turn: turn, cx: Double(cc?.x ?? p.x), cy: Double(cc?.y ?? p.y))) }
            var near: (d: Double, f: SeamFrame)?   // every sewn edge of this piece within a dab's reach gets the overhang, and the nearest is the way out
            for X in S.sides where X.piece == k {
                if let r = seamMap(X, p, cc, reach) {
                    if S.piece(at: CGPoint(x: r.m.x, y: r.m.y)) < 0 { out.items.append(SeamCopy(x: r.m.x, y: r.m.y, turn: turn + r.m.turn, cx: r.m.cx, cy: r.m.cy)) }   // bleed only
                    if near == nil || r.d < near!.d { near = (r.d, r.f) }
                }
            }
            seamStroke.lv[i].exit = near
            if seamStroke.lv.count > i + 1 { seamStroke.lv.removeSubrange((i + 1)...) }
            break
        }
        return out
    }

    /// A band's rails follow its centre: the same carry (same frames) and the same keep-or-skip, so the two outlines of one band never disagree at a seam.
    func seamReplay(q: CGPoint, c: CGPoint?, reach: Double) -> SeamOut {
        var out = SeamOut()
        guard let S = seam, seamOn else { return out }
        out.skip = seamStroke.skip
        var p = q, cc = c, turn = 0.0
        for f in seamStroke.fs {
            let m = seamFrame(f, p, cc)
            p = CGPoint(x: m.x, y: m.y)
            if cc != nil { cc = CGPoint(x: m.cx, y: m.cy) }
            turn += m.turn
        }
        if seamStroke.piece < 0 { return out }
        if !seamStroke.fs.isEmpty { out.items.append(SeamCopy(x: Double(p.x), y: Double(p.y), turn: turn, cx: Double(cc?.x ?? p.x), cy: Double(cc?.y ?? p.y))) }
        for X in S.sides where X.piece == seamStroke.piece {
            if let r = seamMap(X, p, cc, reach), S.piece(at: CGPoint(x: r.m.x, y: r.m.y)) < 0 { out.items.append(SeamCopy(x: r.m.x, y: r.m.y, turn: turn + r.m.turn, cx: r.m.cx, cy: r.m.cy)) }
        }
        return out
    }

    // MARK: print files

    /// Each piece's file cut from the sheet and scaled to the print size Printful takes (the template guide is never in it), as PNGs to share.
    func seamPrintFiles() {
        guard let S = seam, let d = doc else { say("Seam files need a garment template: New canvas, then Hoodie 717."); return }
        guard let flat = d.compositeBuffer(includeBackground: true)?.heldImage() else { say("Print files not made. The picture could not be flattened."); return }
        func cut(_ r: CGRect, _ w: Int, _ h: Int) -> CGImage? {
            guard let part = flat.cropping(to: r), let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            c.interpolationQuality = .high
            c.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
            return c.makeImage()
        }
        var out: [(String, CGImage)] = []
        for f in S.files { if let i = cut(f.rect, S.printW, S.printH) { out.append((f.name, i)) } }
        if let fr = S.files.first(where: { $0.name == "front" })?.rect {
            let k = { (r: Double) in r * Double(fr.width) / Double(S.printW) }   // the kangaroo pocket: the same stretch of the front it is sewn over
            if let i = cut(CGRect(x: fr.minX, y: fr.minY + k(2086), width: fr.width, height: k(3876)), S.printW, 3750) { out.append(("pocket", i)) }
        }
        if let back = out.first(where: { $0.0 == "back" }) { out.append(("ground", back.1)) }   // the inside/ground file takes the back
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        let stamp = f.string(from: .now)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seam-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, img) in out {
            let u = dir.appendingPathComponent("PL Paint \(S.id) \(name) \(stamp).png")
            if let png = UIImage(cgImage: img).pngData(), (try? png.write(to: u)) != nil { urls.append(u) }
        }
        guard !urls.isEmpty else { say("Print files not made."); return }
        shareURLs = urls
        panel = .shareFiles
        say("\(urls.count) print files (\(S.printW) × \(S.printH)) ready for Printful.")
    }
}
