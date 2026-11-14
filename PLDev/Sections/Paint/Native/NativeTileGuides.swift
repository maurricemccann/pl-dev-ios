import CoreGraphics
import Foundation
import UIKit

/// SMART TILE GUIDES (the laptop's `tileGuides`, `tilePorts`, `ghostGeom`, `tileSheet`). In tile mode a line that leaves one edge comes back on the
/// opposite edge, so the app shows where it will come out and where an end is missing its partner:
///   the live ghost: the pen's heading, carried through the nearest edge and drawn (dashed, with a ring) on the opposite side; a stroke that starts
///     near an edge also shows where an arriving line must end;
///   the tile gate: art that touches an edge with nothing meeting it on the opposite edge gets a gate there (the ends that still need connecting);
///   the middle cross: after Make tile the old edges (the seams) lie along it;
///   Show the tiles around: the picture drawn faintly on the eight sides of itself.
struct TilePort { let side: Character; let a: Int; let b: Int }
struct TileScan { var ports: [TilePort] = []; var stamp = -1; var busy = false }

extension NativeCanvasModel {
    /// From point P heading u (unit), the first edge it meets within `reach`, and where that comes back in on the opposite side.
    static func ghostGeom(_ P: CGPoint, _ u: CGPoint, _ W: Double, _ H: Double, both: Bool, reach: Double) -> (t: Double, exit: CGPoint, entry: CGPoint)? {
        var best: (t: Double, exit: CGPoint, entry: CGPoint)?
        func tryEdge(_ t: Double, _ wx: Double, _ wy: Double) {
            guard t > 0, t <= reach, best == nil || t < best!.t else { return }
            let ex = Double(P.x) + Double(u.x) * t, ey = Double(P.y) + Double(u.y) * t
            best = (t, CGPoint(x: ex, y: ey), CGPoint(x: ex + wx, y: ey + wy))
        }
        let ux = Double(u.x), uy = Double(u.y)
        if ux < -1e-6 { tryEdge((0 - Double(P.x)) / ux, W, 0) }
        if ux > 1e-6 { tryEdge((W - Double(P.x)) / ux, -W, 0) }
        if both {
            if uy < -1e-6 { tryEdge((0 - Double(P.y)) / uy, 0, H) }
            if uy > 1e-6 { tryEdge((H - Double(P.y)) / uy, 0, -H) }
        }
        return best
    }

    /// The picture as one tile, kept so the neighbours around it can be drawn without composing every layer again.
    func tileSheetImage() -> CGImage? {
        if let t = tileSheet, t.version == docVersion { return t.image }
        guard live == nil, let d = doc, let img = d.compositeBuffer(includeBackground: true)?.heldImage() else { return tileSheet?.image }
        tileSheet = (docVersion, img)
        return img
    }

    private var tileStampKey: Int { docVersion * 4 + (tile == .off ? 0 : tile == .x ? 1 : 2) }

    /// A scan of the edges, a moment after the picture stops changing (the laptop waits 120 ms).
    func scheduleTileScan() {
        guard tile != .off, tileGuides, live == nil, tileScan.stamp != tileStampKey, !tileScan.busy, doc != nil else { return }
        tileScan.busy = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            self.tileScan.ports = self.scanTilePorts()
            self.tileScan.stamp = self.tileStampKey
            self.tileScan.busy = false
            self.stage?.updateOverlay()
        }
    }

    /// Runs of art that touch an edge with nothing meeting them on the opposite edge, on the side where the art is.
    func scanTilePorts() -> [TilePort] {
        guard let d = doc, let flat = d.compositeBuffer(includeBackground: false) else { return [] }
        let W = d.w, H = d.h, st = 2
        let ptr = flat.ptr
        func alpha(_ x: Int, _ y: Int) -> UInt8 { ptr[(y * W + x) * 4 + 3] }
        var ports: [TilePort] = []
        func pair(_ da: [UInt8], _ db: [UInt8], _ sa: Character, _ sb: Character) {
            let A = stride(from: 0, to: da.count, by: st).map { da[$0] > 36 }, B = stride(from: 0, to: db.count, by: st).map { db[$0] > 36 }
            func near(_ arr: [Bool], _ k: Int) -> Bool {
                var j = max(0, k - 3)
                while j <= min(arr.count - 1, k + 3) { if arr[j] { return true }; j += 1 }
                return false
            }
            for (X, Y, side) in [(A, B, sa), (B, A, sb)] {
                var s = -1
                for k in 0...X.count {
                    let bad = k < X.count && X[k] && !near(Y, k)
                    if bad && s < 0 { s = k }
                    if !bad && s >= 0 {
                        if (k - s) * st >= 4 { ports.append(TilePort(side: side, a: s * st, b: k * st)) }
                        s = -1
                    }
                }
            }
        }
        let left = (0..<H).map { max(alpha(0, $0), alpha(1, $0)) }, right = (0..<H).map { max(alpha(W - 2, $0), alpha(W - 1, $0)) }
        pair(left, right, "L", "R")
        if tile == .both {
            let top = (0..<W).map { max(alpha($0, 0), alpha($0, 1)) }, bottom = (0..<W).map { max(alpha($0, H - 2), alpha($0, H - 1)) }
            pair(top, bottom, "T", "B")
        }
        return ports
    }
}

extension CanvasStage {
    /// The document's own space on the screen: x across, y down, one unit a picture pixel.
    var docTransform: CGAffineTransform {
        let o = toScreen(.zero), ex = toScreen(CGPoint(x: 1, y: 0)), ey = toScreen(CGPoint(x: 0, y: 1))
        return CGAffineTransform(a: ex.x - o.x, b: ex.y - o.y, c: ey.x - o.x, d: ey.y - o.y, tx: o.x, ty: o.y)
    }

    /// The tiles around the picture, faint (drawn outside the picture only, so the art on top stays itself).
    func drawTilePreview(_ c: CGContext, _ d: NativeDoc) {
        guard model.tilePrev, model.tile != .off, let img = model.tileSheetImage() else { return }
        let W = Double(d.w), H = Double(d.h)
        c.saveGState(); c.concatenate(docTransform); c.setAlpha(0.42)
        for (dx, dy) in [(-1, 0), (1, 0), (-1, -1), (0, -1), (1, -1), (-1, 1), (0, 1), (1, 1)] {
            if model.tile == .x && dy != 0 { continue }
            c.saveGState()
            c.translateBy(x: Double(dx) * W, y: Double(dy) * H + H); c.scaleBy(x: 1, y: -1)   // the image is upright; the document is y-down
            c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
            c.restoreGState()
        }
        c.restoreGState()
    }

    /// The middle cross, the gates, and the live ghost, in document space on top of the art.
    func drawTileGuides(_ c: CGContext, _ d: NativeDoc) {
        guard model.tileGuides, model.tile != .off else { return }
        model.scheduleTileScan()
        let W = Double(d.w), H = Double(d.h), both = model.tile == .both, px = 1 / max(0.001, zoom)
        let gold = UIColor(red: 0.906, green: 0.812, blue: 0.525, alpha: 1)
        c.saveGState(); c.concatenate(docTransform); c.setLineCap(.round)
        var lw: CGFloat = 1   // the width sk() halos (CGContext keeps no readable line width)
        func sk() {   // a dark halo so the gold reads on any ground
            guard let path = c.path else { return }
            let w = lw
            c.setStrokeColor(UIColor(red: 0.08, green: 0.063, blue: 0.04, alpha: 0.65).cgColor); c.setLineWidth(w + 3 * px); c.strokePath()
            c.addPath(path); c.setStrokeColor(gold.cgColor); c.setLineWidth(w); c.strokePath()
        }
        c.setAlpha(0.28); c.setLineDash(phase: 0, lengths: [3 * px, 9 * px]); lw = 1.6 * px; c.setLineWidth(lw); c.setStrokeColor(gold.cgColor)
        c.move(to: CGPoint(x: W / 2, y: 0)); c.addLine(to: CGPoint(x: W / 2, y: H))
        if both { c.move(to: CGPoint(x: 0, y: H / 2)); c.addLine(to: CGPoint(x: W, y: H / 2)) }
        c.strokePath()
        c.setAlpha(1); c.setLineDash(phase: 0, lengths: [9 * px, 6 * px]); lw = 2.2 * px; c.setLineWidth(lw); c.setStrokeColor(gold.cgColor); c.setFillColor(gold.cgColor)
        for q in model.tileScan.ports {   // a gate on the opposite edge where the art is missing, and a dot where it is
            let horiz = q.side == "T" || q.side == "B", mid = Double(q.a + q.b) / 2, len = max(10, Double(q.b - q.a))
            let here: CGPoint, there: CGPoint
            switch q.side {
            case "L": here = CGPoint(x: 0, y: mid); there = CGPoint(x: W, y: mid)
            case "R": here = CGPoint(x: W, y: mid); there = CGPoint(x: 0, y: mid)
            case "T": here = CGPoint(x: mid, y: 0); there = CGPoint(x: mid, y: H)
            default: here = CGPoint(x: mid, y: H); there = CGPoint(x: mid, y: 0)
            }
            c.beginPath()
            if horiz { c.move(to: CGPoint(x: Double(there.x) - len / 2, y: Double(there.y))); c.addLine(to: CGPoint(x: Double(there.x) + len / 2, y: Double(there.y))) }
            else { c.move(to: CGPoint(x: Double(there.x), y: Double(there.y) - len / 2)); c.addLine(to: CGPoint(x: Double(there.x), y: Double(there.y) + len / 2)) }
            lw = 5 * px; c.setLineWidth(lw); sk()
            c.beginPath(); c.addArc(center: here, radius: 5.5 * px, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            c.setLineDash(phase: 0, lengths: []); c.setStrokeColor(UIColor(red: 0.08, green: 0.063, blue: 0.04, alpha: 0.65).cgColor); lw = 2.5 * px; c.setLineWidth(lw)
            c.drawPath(using: .fillStroke)
            c.setStrokeColor(gold.cgColor); c.setLineDash(phase: 0, lengths: [9 * px, 6 * px])
        }
        if let s = model.live, s.pts.count > 1, s.tool != .smudge, !s.onMask {   // the live ghost for the stroke in hand
            let sz = max(10, s.size), reach = max(70, sz * 2.4)
            let pts = s.pts.map { CGPoint(x: NativeCanvasModel.num($0[0]), y: NativeCanvasModel.num($0[1])) }
            let last = pts[pts.count - 1]
            func ring(_ p: CGPoint, _ r: Double) {
                c.saveGState(); c.setLineDash(phase: 0, lengths: []); lw = 2.4 * px; c.setLineWidth(lw)
                c.beginPath(); c.addArc(center: p, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false); sk()
                c.restoreGState()
            }
            if let back = pts.dropLast().last(where: { hypot(Double(last.x - $0.x), Double(last.y - $0.y)) > sz * 0.7 }) {
                let dl = max(1e-9, hypot(Double(last.x - back.x), Double(last.y - back.y)))
                let u = CGPoint(x: Double(last.x - back.x) / dl, y: Double(last.y - back.y) / dl)
                if let g = NativeCanvasModel.ghostGeom(last, u, W, H, both: both, reach: reach) {   // where it comes back in, and the way it would go
                    c.beginPath(); c.move(to: g.entry); c.addLine(to: CGPoint(x: Double(g.entry.x) + Double(u.x) * sz * 4, y: Double(g.entry.y) + Double(u.y) * sz * 4)); sk()
                    ring(g.entry, max(8 * px, sz * 0.6))
                }
            }
            let first = pts[0]
            if let fwd = pts.dropFirst().first(where: { hypot(Double($0.x - first.x), Double($0.y - first.y)) > sz * 0.7 }) {   // a stroke that starts near an edge: where an arriving line has to end
                let dl = max(1e-9, hypot(Double(fwd.x - first.x), Double(fwd.y - first.y)))
                let u = CGPoint(x: Double(first.x - fwd.x) / dl, y: Double(first.y - fwd.y) / dl)   // looking backwards from the start
                if let g = NativeCanvasModel.ghostGeom(first, u, W, H, both: both, reach: reach) {
                    c.beginPath(); c.move(to: CGPoint(x: Double(g.entry.x) + Double(u.x) * sz * 4, y: Double(g.entry.y) + Double(u.y) * sz * 4)); c.addLine(to: g.entry); sk()
                    ring(g.entry, max(8 * px, sz * 0.6))
                }
            }
        }
        c.restoreGState()
    }

    /// Printful's template over the art, then each seam pair in its own colour with its number at both sides.
    func drawSeam(_ c: CGContext, _ d: NativeDoc) {
        guard let S = model.seam else { return }
        let W = Double(d.w), H = Double(d.h), px = 1 / max(0.001, zoom)
        let dark = d.bgVis && (Hex.rgb(d.bg).map { ($0.0 + $0.1 + $0.2) * 255 < 300 } ?? false)
        c.saveGState(); c.concatenate(docTransform)
        c.saveGState(); c.setAlpha(dark ? 0.9 : 0.6)
        c.translateBy(x: 0, y: H); c.scaleBy(x: 1, y: -1)
        c.draw((dark ? S.darkImage : nil) ?? S.image, in: CGRect(x: 0, y: 0, width: W, height: H))
        c.restoreGState()
        c.setLineCap(.round); c.setLineWidth(3 * px)
        for X in S.sides {
            let col = UIColor(hue: CGFloat((Double(X.k) * 137.5).truncatingRemainder(dividingBy: 360) / 360), saturation: 0.85, brightness: 0.95, alpha: 1)
            c.setAlpha(model.seamOn ? 0.9 : 0.35); c.setStrokeColor(col.cgColor)
            c.beginPath(); c.move(to: X.p[0]); for q in X.p.dropFirst() { c.addLine(to: q) }; c.strokePath()
            let m = X.p[X.p.count >> 1], n = X.n[X.n.count >> 1]
            let lx = Double(m.x) + Double(n.x) * 16 * px, ly = Double(m.y) + Double(n.y) * 16 * px
            c.setFillColor(UIColor(red: 0.06, green: 0.047, blue: 0.04, alpha: 0.8).cgColor)
            c.fillEllipse(in: CGRect(x: lx - 11 * px, y: ly - 11 * px, width: 22 * px, height: 22 * px))
            let label = NSAttributedString(string: String(X.k + 1), attributes: [.font: UIFont.systemFont(ofSize: 15 * px), .foregroundColor: col])
            UIGraphicsPushContext(c)
            let sz = label.size()
            label.draw(at: CGPoint(x: lx - Double(sz.width) / 2, y: ly - Double(sz.height) / 2))
            UIGraphicsPopContext()
        }
        c.restoreGState()
    }
}
