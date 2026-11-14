import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// NODE MODE (the laptop's S335/S336 Assist, `nodeFit` ... `nodeUp`). Nodes sit on the stroke just drawn; drag one and the stroke is drawn again
/// through the new path. A touch on another line of the layer gives that line the nodes. Only strokes the layer is made of can be bent.
struct NodeState {
    var logIndex: Int
    var pts: [[Any]]      // the stroke's pen points as logged
    var idx: [Int]        // the points that carry a node
    var xy: [CGPoint] { pts.map { CGPoint(x: NativeCanvasModel.num($0[0]), y: NativeCanvasModel.num($0[1])) } }
}
struct NodeDrag { var k: Int; var x0: Double; var y0: Double; var base: [CGPoint]; var work: [CGPoint] }

extension NativeCanvasModel {
    /// Ramer-Douglas-Peucker on the pen path, widened until no more than `maxN` nodes remain; the first and last point always stay.
    static func nodeFit(_ pts: [CGPoint], _ maxN: Int) -> [Int] {
        let n = pts.count
        guard n >= 2 else { return [] }
        func run(_ eps: Double) -> [Int] {
            var keep: Set<Int> = [0, n - 1]
            var st: [(Int, Int)] = [(0, n - 1)]
            while let (s, e) = st.popLast() {
                var md = 0.0, mi = -1
                let x1 = Double(pts[s].x), y1 = Double(pts[s].y), dx = Double(pts[e].x) - x1, dy = Double(pts[e].y) - y1, L = max(1e-9, hypot(dx, dy))
                if e - s > 1 { for i in (s + 1)..<e {
                    let d = abs(dy * (Double(pts[i].x) - x1) - dx * (Double(pts[i].y) - y1)) / L
                    if d > md { md = d; mi = i }
                } }
                if mi >= 0 && md > eps { keep.insert(mi); st.append((s, mi)); st.append((mi, e)) }
            }
            return keep.sorted()
        }
        var eps = 1.5, k = run(eps)
        while k.count > maxN && eps < 4000 { eps *= 1.4; k = run(eps) }
        return k
    }

    /// The log records of the active layer's strokes, in the order they were drawn: what a bend redraws.
    private func layerStrokeIndices(_ d: NativeDoc) -> [Int] {
        let lid = d.layerID(d.active)
        return d.log.indices.filter { i in
            let r = d.log[i]
            return (r["layer"] as? Int) == lid && r["dead"] as? Bool != true && r["onMask"] as? Bool != true && ["paint", "erase"].contains(r["tool"] as? String ?? "")
        }
    }

    var nodesLive: Bool {
        guard nodeOn, let n = nodes, let d = doc, d.log.indices.contains(n.logIndex) else { return false }
        return d.log[n.logIndex]["dead"] as? Bool != true
    }

    func toggleNodes(_ on: Bool? = nil) {
        nodeOn = on ?? !nodeOn; nodes = nil; nodeDrag = nil; nodeBar = false
        if nodeOn { echoOn = false; lightOneOn = false; say("Node mode: draw a line, then drag the yellow nodes.") }
        stage?.updateOverlay()
    }

    /// A stroke just ended in node mode: it gets its nodes. A tap on an older line gives that line the nodes (the dot the tap drew is taken back).
    func nodeAttach(tapAt p: CGPoint, stroke s: Live) {
        guard let d = doc else { return }
        nodeDrag = nil
        var len = 0.0
        for i in 1..<max(1, s.pts.count) { len += hypot(Self.num(s.pts[i][0]) - Self.num(s.pts[i - 1][0]), Self.num(s.pts[i][1]) - Self.num(s.pts[i - 1][1])) }
        if len * scale < 8 {
            let a = CGPoint(x: Self.num(s.pts[0][0]), y: Self.num(s.pts[0][1]))
            undoStroke()
            if nodePick(a) { return }
            redoStroke()
        }
        guard let l = tweakable, d.log.indices.contains(l.logIndex), l.pts.count >= 3 else { nodes = nil; stage?.updateOverlay(); return }
        let xy = l.pts.map { CGPoint(x: Self.num($0[0]), y: Self.num($0[1])) }
        nodes = NodeState(logIndex: l.logIndex, pts: l.pts, idx: Self.nodeFit(xy, nodeMax))
        stage?.updateOverlay()
    }

    /// A press on another stroke of the active layer gives that stroke the nodes (nearest to the press, the latest drawn wins a tie).
    @discardableResult func nodePick(_ q: CGPoint) -> Bool {
        guard let d = doc else { return false }
        let lid = d.layerID(d.active), reach = max(14 / max(0.05, scale), 6)
        var best: Int?, bd = 1e9
        for i in d.log.indices {
            let r = d.log[i]
            guard (r["layer"] as? Int) == lid, r["dead"] as? Bool != true, r["onMask"] as? Bool != true, (r["tool"] as? String) == "paint",
                  let pts = r["pts"] as? [[Any]], pts.count >= 3, i != nodes?.logIndex else { continue }
            let half = Self.num(r["size"] ?? 8) / 2
            for j in 1..<pts.count {
                let x1 = Self.num(pts[j - 1][0]), y1 = Self.num(pts[j - 1][1]), x2 = Self.num(pts[j][0]), y2 = Self.num(pts[j][1])
                let dx = x2 - x1, dy = y2 - y1, l2 = max(1e-9, dx * dx + dy * dy)
                let t = max(0, min(1, ((Double(q.x) - x1) * dx + (Double(q.y) - y1) * dy) / l2))
                let dd = hypot(Double(q.x) - (x1 + t * dx), Double(q.y) - (y1 + t * dy)) - half
                if dd < bd || (dd == bd && best != i) { bd = dd; best = i }
            }
        }
        guard let b = best, bd <= reach, let pts = d.log[b]["pts"] as? [[Any]] else { return false }
        let xy = pts.map { CGPoint(x: Self.num($0[0]), y: Self.num($0[1])) }
        nodes = NodeState(logIndex: b, pts: pts, idx: Self.nodeFit(xy, nodeMax))
        nodeDrag = nil
        stage?.updateOverlay()
        return true
    }

    /// True when the press took hold of a node (or was spent asking to finish the line); nodes showing means the press never draws.
    func nodeDown(_ p: CGPoint) -> Bool {
        guard nodesLive, let n = nodes else { nodes = nil; return false }
        let xy = n.xy, hit = max(18 / max(0.05, scale), 10)
        var best = -1, bd = 1e9
        for (k, i) in n.idx.enumerated() {
            let d = hypot(Double(xy[i].x - p.x), Double(xy[i].y - p.y))
            if d < bd { bd = d; best = k }
        }
        if best < 0 || bd > hit {
            if nodePick(p) { return true }
            nodeBar = true   // a press anywhere else only asks "Finish this line?": the nodes stay until Done
            return true
        }
        nodeBar = false
        nodeDrag = NodeDrag(k: best, x0: Double(p.x), y0: Double(p.y), base: xy, work: xy)
        stage?.updateOverlay()
        return true
    }

    /// The stroke bends between this node's neighbours and stays put beyond them.
    func nodeMove(_ p: CGPoint) {
        guard var dr = nodeDrag, let n = nodes else { return }
        let dx = Double(p.x) - dr.x0, dy = Double(p.y) - dr.y0, I = n.idx, k = dr.k, c = I[k]
        let lo = k > 0 ? I[k - 1] : c, hi = k < I.count - 1 ? I[k + 1] : c
        if lo <= hi { for i in lo...hi {
            let t: Double = i <= c ? (c == lo ? 1 : Double(i - lo) / Double(c - lo)) : (hi == c ? 1 : Double(hi - i) / Double(hi - c))
            let w = t * t * (3 - 2 * t)
            dr.work[i] = CGPoint(x: Double(dr.base[i].x) + dx * w, y: Double(dr.base[i].y) + dy * w)
        } }
        nodeDrag = dr
        stage?.updateOverlay()
    }

    func nodeUp() {
        guard let dr = nodeDrag, var n = nodes, let d = doc else { nodeDrag = nil; return }
        nodeDrag = nil
        let c = n.idx[dr.k]
        if abs(Double(dr.work[c].x - dr.base[c].x)) + abs(Double(dr.work[c].y - dr.base[c].y)) < 0.5 { stage?.updateOverlay(); return }   // a tap that moved nothing changes nothing
        var newPts = n.pts
        for i in newPts.indices {
            var r = newPts[i]
            r[0] = (Double(dr.work[i].x) * 10).rounded() / 10; r[1] = (Double(dr.work[i].y) * 10).rounded() / 10
            newPts[i] = r
        }
        let keep = n.idx
        if let l = tweakable, l.logIndex == n.logIndex {
            tweakLast(size: nil, [:], pts: newPts)
            n.logIndex = d.log.count - 1
        } else {
            let list = layerStrokeIndices(d)
            guard let at = list.firstIndex(of: n.logIndex) else { nodes = nil; return }
            if d.layers[d.active].meta["raw"] as? Bool == true { say("This layer has fills, pasted or smudged parts. Only its last stroke can be bent."); nodes = nil; return }
            restyleLayer(scale: 1, [:], bend: (logIndex: n.logIndex, pts: newPts))
            let after = layerStrokeIndices(d)
            guard after.indices.contains(at) else { nodes = nil; return }
            n.logIndex = after[at]
        }
        n.pts = newPts; n.idx = keep
        nodes = n
        stage?.updateOverlay()
    }
}

extension CanvasStage {
    /// The nodes: a dashed line through them, the stroke in gold while one is dragged, a dot at each.
    func drawNodes(_ c: CGContext) {
        guard model.nodesLive, let n = model.nodes else { return }
        let pts = model.nodeDrag?.work ?? n.xy, r = 8.0
        c.saveGState()
        c.setLineWidth(1.5); c.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor); c.setLineDash(phase: 0, lengths: [6, 5])
        for (k, i) in n.idx.enumerated() { let s = toScreen(pts[i]); if k == 0 { c.move(to: s) } else { c.addLine(to: s) } }
        c.strokePath(); c.setLineDash(phase: 0, lengths: [])
        if model.nodeDrag != nil {
            c.setStrokeColor(UIColor(red: 0.96, green: 0.77, blue: 0.26, alpha: 0.9).cgColor)
            for (i, q) in pts.enumerated() { let s = toScreen(q); if i == 0 { c.move(to: s) } else { c.addLine(to: s) } }
            c.strokePath()
        }
        c.setLineWidth(2); c.setStrokeColor(UIColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 1).cgColor)
        for (k, i) in n.idx.enumerated() {
            let s = toScreen(pts[i])
            c.setFillColor((model.nodeDrag?.k == k ? UIColor.white : UIColor(red: 0.96, green: 0.77, blue: 0.26, alpha: 1)).cgColor)
            let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
            c.fillEllipse(in: rect); c.strokeEllipse(in: rect)
        }
        c.restoreGState()
    }
}

/// The bar while Node mode is on.
struct NativeNodeBar: View {
    @Bindable var canvas: NativeCanvasModel
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            Text(canvas.nodeBar ? "Finish this line?" : canvas.nodes == nil ? "Draw a line, or touch one, then drag the yellow nodes." : "Drag a yellow node.").font(.footnote)
            Spacer(minLength: 0)
            if canvas.nodeBar || canvas.nodes != nil {
                Button("Done") { canvas.nodes = nil; canvas.nodeBar = false; canvas.stage?.updateOverlay() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            if canvas.nodeBar { Button("Keep going") { canvas.nodeBar = false }.buttonStyle(.bordered).controlSize(.small) }
            Button { canvas.toggleNodes(false) } label: { Image(systemName: "xmark") }.buttonStyle(.bordered).controlSize(.small).accessibilityLabel("Leave Node mode")
        }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
