import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UIKit

enum NativeTool: String, CaseIterable, Sendable { case paint, erase }

/// The painter's state: the open work, the stroke being drawn, undo, autosave. The stage view feeds it touches and shows what it draws.
@MainActor @Observable final class NativeCanvasModel {
    // what the toolbar shows
    var tool: NativeTool = .paint
    var size: Double = 28            // the laptop's paint default
    var opacity: Double = 1          // the laptop keeps 100 %
    var color: Color = .black
    var color2 = Color(red: 0.478, green: 0.627, blue: 0.784)   // the companion colour of twin brushes (the laptop's preview blue)
    var brush = NativeToolkit.round
    var fingerPaints = false         // fingers draw only if "Finger paints" (the laptop's rule)
    var name = "Untitled"
    var line: String?                // the one-line result under the toolbar
    var canUndo = false
    var canRedo = false
    var layerNames: [(name: String, visible: Bool)] = []
    var activeLayer = 0
    var hasDoc = false
    var docSize = ""

    @ObservationIgnored private(set) var doc: NativeDoc?
    @ObservationIgnored private(set) var workID: String?
    @ObservationIgnored let undo = UndoStack()
    @ObservationIgnored weak var stage: CanvasStage?
    @ObservationIgnored private var wet: PixelBuffer?
    @ObservationIgnored private var live: Live?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var firstDirty: Date?
    @ObservationIgnored private var dirty = false

    private struct Live {
        var stroker: NativeStroker
        let brush: Brush
        let tool: NativeTool
        let layer: Int
        let color: String
        let color2: String
        let op: Double
        let size: Double
        let t0: TimeInterval
        var pAvg: Double?
        var pts: [[Any]] = []
        var raw: [(x: Double, y: Double, p: Double, t: Double, tilt: (Double, Double)?)] = []
        var dirty: CGRect?
        var before: [TileKey: Data] = [:]
    }

    var drawing: Bool { live != nil }
    var wetBuffer: PixelBuffer? { wet }

    // MARK: works

    func startNew(w: Int, h: Int) {
        guard live == nil else { return }
        saveNow()
        do {
            let d = try NativeDoc(w: w, h: h)
            adopt(d, id: NativeStore.newID(), name: "Untitled")
            say("New canvas, \(w) by \(h).")
            markChanged()
        } catch let e as WorkFileError { say("Not made. \(e.why)") } catch { say("Not made.") }
    }

    func open(id: String) {
        guard live == nil else { return }
        saveNow()
        do {
            let d = try NativeStore.load(id)
            let n = NativeStore.loadIndex().list.first { ($0["id"] as? String) == id }?["name"] as? String ?? "Untitled"
            adopt(d, id: id, name: n)
            say("Opened \(n).")
        } catch let e as WorkFileError { say("Not opened. \(e.why)") } catch { say("Not opened. The file is missing.") }
    }

    private func adopt(_ d: NativeDoc, id: String, name: String) {
        doc = d; workID = id; self.name = name; wet = nil; undo.reset(); live = nil
        hasDoc = true; docSize = "\(d.w) × \(d.h)"
        syncFlags(); stage?.rebuild(); stage?.fit()
    }

    /// Writes the open work to the phone now. Returns false (and says why) when it could not.
    @discardableResult func saveNow() -> Bool {
        saveTask?.cancel(); saveTask = nil; firstDirty = nil
        guard dirty, live == nil, let d = doc, let id = workID else { return true }
        do { try NativeStore.save(d, id: id, name: name); dirty = false; return true }
        catch { say("Not saved. \((error as? WorkFileError)?.why ?? "The phone refused the file.")"); return false }
    }

    func delete(id: String) {
        do {
            try NativeStore.delete(id)
            if id == workID { doc = nil; workID = nil; hasDoc = false; stage?.rebuild() }
            say("Deleted.")
        } catch { say("Not deleted.") }
    }

    // MARK: autosave (3 s after the last change, never more than 12 s of continuous drawing without a save: the laptop's rule)

    private func markChanged() {
        dirty = true
        let now = Date()
        if firstDirty == nil { firstDirty = now }
        saveTask?.cancel()
        let wait: Double = now.timeIntervalSince(firstDirty ?? now) > 12 ? 0 : 3
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            if self.live != nil { self.markChanged(); return }
            self.saveNow()
        }
    }

    // MARK: strokes

    func canPaint(_ touch: UITouch) -> Bool {
        guard doc != nil, live == nil else { return false }
        return touch.type == .pencil || fingerPaints
    }

    func begin(at p: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?) {
        guard let d = doc, live == nil else { return }
        guard d.layers[d.active].visible else { say("This layer is hidden."); return }
        if tool == .paint, wet == nil { wet = PixelBuffer(w: d.w, h: d.h) }
        if tool == .paint, wet == nil { say("Not drawn. This phone has no room for the stroke buffer."); return }
        live = Live(stroker: NativeStroker(brush, size: size), brush: brush, tool: tool, layer: d.active, color: UIColor(color).hex, color2: UIColor(color2).hex,
                    op: tool == .erase ? 1 : opacity, size: size, t0: time)
        extend(to: p, pressure: pressure, time: time, tilt: tilt)
    }

    func extend(to p: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?) {
        guard var s = live, let d = doc else { return }
        let raw = max(0.02, min(1, pressure))
        let sm = s.pAvg.map { $0 * 0.5 + raw * 0.5 } ?? raw   // the laptop's pAvg: pressure averaged half and half with the last value
        s.pAvg = sm
        let ms = ((time - s.t0) * 1000).rounded()
        let tl: (Double, Double)? = s.brush.usesTilt ? tilt.map { (Double(Int($0.0)), Double(Int($0.1))) } : nil   // tilt is kept in the log only when the brush uses it
        var pt: [Any] = [(Double(p.x) * 10).rounded() / 10, (Double(p.y) * 10).rounded() / 10, (sm * 100).rounded() / 100, Int(ms)]
        if let tl { pt.append(Int(tl.0)); pt.append(Int(tl.1)) }
        s.pts.append(pt)
        s.raw.append((x: Double(p.x), y: Double(p.y), p: sm, t: ms, tilt: tl))
        let dabs = s.stroker.add(x: Double(p.x), y: Double(p.y), p: sm, t: ms, tilt: tl)
        lay(dabs, &s, on: d)
        live = s
        stage?.refresh(active: s.layer, wetOpacity: s.tool == .paint ? s.op : 0)
    }

    /// Puts dabs on the stroke buffer (paint) or straight on the layer (erase), and grows the stroke's dirty box.
    private func lay(_ dabs: [Dab], _ s: inout Live, on d: NativeDoc) {
        let L = d.layers[s.layer].pixels
        let B = s.brush
        for dab in dabs {
            let r = B.radius(size: s.size, pressure: dab.p, f: dab.f)
            let reach = r * 1.5 + 4 + (dab.span / 2) + (B.n("channel") > 0 ? B.n("channel") * s.size * 2 : 0)
            var box = CGRect(x: dab.x - reach, y: dab.y - reach, width: reach * 2, height: reach * 2)
            if let tw = dab.tw { box = box.union(CGRect(x: dab.x + tw.dx - reach, y: dab.y + tw.dy - reach, width: reach * 2, height: reach * 2)) }
            s.dirty = s.dirty.map { $0.union(box) } ?? box
            if s.tool == .erase {
                for k in L.tiles(in: box) where s.before[k] == nil { s.before[k] = L.tilePixels(tx: k.tx, ty: k.ty) }
                L.ctx.saveGState(); L.ctx.setBlendMode(.destinationOut)
                paintDab(dab, B, s, into: L.ctx, ink: "#000000")
                L.ctx.restoreGState()
            } else if let w = wet {
                paintDab(dab, B, s, into: w.ctx, ink: nil)
            }
        }
    }

    private func paintDab(_ dab: Dab, _ B: Brush, _ s: Live, into ctx: CGContext, ink: String?) {
        if dab.span > 0 {
            let fill = ink ?? (B.t("gapFillColor").isEmpty ? s.color2 : B.t("gapFillColor"))
            NativeStamp.drawFill(ctx, B, color: fill, size: s.size, dab)
            return
        }
        var col = ink ?? s.color
        if ink == nil, B.n("hueJit") > 0 || B.n("satJit") > 0 || B.n("briJit") > 0 {
            col = NativeStamp.jitterColour(col, hue: B.n("hueJit"), sat: B.n("satJit"), bri: B.n("briJit"), x: dab.x, y: dab.y)
        }
        NativeStamp.drawWithTwin(ctx, B, color: col, color2: ink ?? s.color2, size: s.size, dab)
    }

    /// The line catches up with the pen after release (StreamLine lags it).
    private func catchUp(_ st: inout NativeStroker, _ s: Live) -> [Dab] {
        guard st.B.n("stream") > 0, let q = s.raw.last else { return [] }
        var out: [Dab] = []
        for _ in 0..<14 { out += st.add(x: q.x, y: q.y, p: s.pAvg ?? 1, t: q.t, tilt: nil) }
        return out
    }

    func end() {
        guard var s = live, let d = doc else { return }
        let L = d.layers[s.layer]
        // the line catches up with the pen, and an end taper needs the whole length, so the stroke is laid down once more (the laptop's `finishStroke`)
        var st = s.stroker
        let flushed = st.flush()
        lay(flushed, &s, on: d)
        let caught = catchUp(&st, s)
        lay(caught, &s, on: d)
        s.stroker = st
        if s.brush.needsLength, s.stroker.dist > 8, let box = s.dirty?.integral {
            if s.tool == .erase { for (k, data) in s.before { L.pixels.setTile(tx: k.tx, ty: k.ty, data) } } else { wet?.clear(box) }
            var again = NativeStroker(s.brush, size: s.size, total: s.stroker.dist)
            for q in s.raw { let dabs = again.add(x: q.x, y: q.y, p: q.p, t: q.t, tilt: q.tilt); lay(dabs, &s, on: d) }
            let tail = again.flush()
            lay(tail, &s, on: d)
            let more = catchUp(&again, s)
            lay(more, &s, on: d)
        }
        live = nil
        guard let box = s.dirty?.integral else { return }
        var before = s.before
        if s.tool == .paint, let w = wet {
            if s.brush.t("grain") != "none", s.brush.t("grainMode") == "texturised" { NativeStamp.applyGrain(w.ctx, s.brush, in: box) }
            for k in L.pixels.tiles(in: box) where before[k] == nil { before[k] = L.pixels.tilePixels(tx: k.tx, ty: k.ty) }
            if let img = w.image() { L.pixels.drawUpright(img, in: box, alpha: CGFloat(s.op), blend: L.alphaLock ? .sourceAtop : .normal) }
            w.clear(box)
        }
        let tiles = before.keys.sorted { ($0.ty, $0.tx) < ($1.ty, $1.tx) }.map { k in Patch.T(key: k, before: before[k]!, after: L.pixels.tilePixels(tx: k.tx, ty: k.ty)) }
        undo.push(Patch(layer: s.layer, tiles: tiles))
        d.log.append(record(s))
        syncFlags()
        stage?.refresh(active: s.layer, wetOpacity: 0)
        markChanged()
    }

    /// A second finger landed or the system took the touch: the stroke is taken back as if it never began.
    func cancel() {
        guard let s = live, let d = doc else { return }
        live = nil
        let L = d.layers[s.layer].pixels
        if s.tool == .erase { for (k, data) in s.before { L.setTile(tx: k.tx, ty: k.ty, data) } }
        else if let w = wet, let box = s.dirty?.integral { w.clear(box) }
        stage?.refresh(active: s.layer, wetOpacity: 0)
    }

    /// One stroke in the laptop's log shape (`app.js`, the `rec` in the stroke-commit function).
    private func record(_ s: Live) -> [String: Any] {
        let B = s.brush
        let bs: [String: Any] = ["ps": B.n("pressSize"), "twin": B.n("twin"), "gap": B.n("twinGap"), "side": B.t("twinSide"), "ch": B.n("channel"), "lines": B.n("lines"),
                                 "lineGap": B.n("lineGap"), "wet": B.n("wet"), "round": B.shape != "square" && B.shape != "tube",
                                 "k": B.shape == "square" ? 0.72 : B.shape == "tube" ? 0.92 : 1, "pc": B.n("pressCurve")]
        let c2: Any = B.n("twin") > 0 ? s.color2 : NSNull()
        return ["tool": s.tool.rawValue, "color": s.color, "color2": c2, "size": s.size, "op": s.op,
                "brush": B.id, "layer": s.layer + 1, "onMask": false, "t": Int((s.t0 * 1000).rounded()), "pts": s.pts, "bs": bs, "snapped": false, "sym": "off"]
    }

    // MARK: undo, redo, layers

    func undoStroke() {
        guard live == nil, let d = doc, let p = undo.undo(d.layers.map(\.pixels)) else { return }
        afterHistory(p)
    }
    func redoStroke() {
        guard live == nil, let d = doc, let p = undo.redo(d.layers.map(\.pixels)) else { return }
        afterHistory(p)
    }
    private func afterHistory(_ p: Patch) {
        syncFlags(); stage?.refresh(active: p.layer, wetOpacity: 0); markChanged()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setActive(_ i: Int) {
        guard live == nil, let d = doc, d.layers.indices.contains(i) else { return }
        d.active = i; syncFlags(); stage?.rebuild(); markChanged()
    }
    func toggleVisible(_ i: Int) {
        guard live == nil, let d = doc, d.layers.indices.contains(i) else { return }
        d.layers[i].meta["vis"] = !d.layers[i].visible
        syncFlags(); stage?.rebuild(); markChanged()
    }

    func syncFlags() {
        canUndo = undo.canUndo; canRedo = undo.canRedo
        if let d = doc { layerNames = d.layers.map { ($0.name, $0.visible) }; activeLayer = d.active } else { layerNames = []; activeLayer = 0 }
    }

    func say(_ s: String?) { line = s }
}

extension UIColor {
    var hex: String { let c = rgb; return Hex.string(r: c.0, g: c.1, b: c.2) }
    var rgb: (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
