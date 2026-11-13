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
    var fingerPaints = false         // fingers draw only if "Finger paints" (the laptop's rule)
    var name = "Untitled"
    var line: String?                // the one-line result under the toolbar
    var canUndo = false, canRedo = false
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
    @ObservationIgnored private let brush = RoundBrush()

    private struct Live {
        var stroker: Stroker
        var tool: NativeTool
        var layer: Int
        var rgb: (Double, Double, Double)
        var op: Double
        var size: Double
        var t0: TimeInterval
        var pts: [[Any]] = []
        var dirty: CGRect?
        var before: [TileKey: Data] = [:]
        var grads: [Int: CGGradient] = [:]
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
        let L = d.layers[d.active]
        guard L.visible else { say("This layer is hidden."); return }
        let rgb = UIColor(color).rgb
        if tool == .paint, wet == nil { wet = PixelBuffer(w: d.w, h: d.h) }
        if tool == .paint, wet == nil { say("Not drawn. This phone has no room for the stroke buffer."); return }
        live = Live(stroker: Stroker(brush: brush, size: size), tool: tool, layer: d.active, rgb: rgb, op: tool == .erase ? 1 : opacity, size: size, t0: time)
        extend(to: p, pressure: pressure, time: time, tilt: tilt)
    }

    func extend(to p: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?) {
        guard var s = live, let d = doc else { return }
        let sm = s.stroker.smooth(max(0.02, min(1, pressure)))
        // the log: x, y (0.1), pressure (0.01), ms since the stroke began; tilt only when the brush uses it (this brush does not)
        s.pts.append([(p.x * 10).rounded() / 10, (p.y * 10).rounded() / 10, (sm * 100).rounded() / 100, Int(((time - s.t0) * 1000).rounded())])
        let stamps = s.stroker.add(x: Double(p.x), y: Double(p.y), p: sm)
        let L = d.layers[s.layer].pixels
        for st in stamps {
            let r = CGRect(x: st.x - st.r - 1, y: st.y - st.r - 1, width: st.r * 2 + 2, height: st.r * 2 + 2)
            s.dirty = s.dirty.map { $0.union(r) } ?? r
            if s.tool == .erase {
                for k in L.tiles(in: r) where s.before[k] == nil { s.before[k] = L.tilePixels(tx: k.tx, ty: k.ty) }
                stamp(st, into: L.ctx, rgb: (0, 0, 0), erase: true, live: &s)
            } else if let w = wet {
                stamp(st, into: w.ctx, rgb: s.rgb, erase: false, live: &s)
            }
        }
        live = s
        stage?.refresh(active: s.layer, wetOpacity: s.tool == .paint ? s.op : 0)
    }

    func end() {
        guard let s = live, let d = doc else { return }
        live = nil
        let L = d.layers[s.layer]
        guard let box = s.dirty?.integral else { return }
        var before = s.before
        if s.tool == .paint, let w = wet {
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
        let b = brush
        return ["tool": s.tool.rawValue, "color": Hex.string(r: s.rgb.0, g: s.rgb.1, b: s.rgb.2), "color2": NSNull(), "size": s.size, "op": s.op,
                "brush": b.id, "layer": s.layer + 1, "onMask": false, "t": Int((s.t0 * 1000).rounded()), "pts": s.pts,
                "bs": ["ps": b.pressSize, "twin": 0, "gap": 0, "side": "right", "ch": 0, "lines": 1, "lineGap": 0.15, "wet": 0, "round": true, "k": 1, "pc": b.pressCurve] as [String: Any],
                "snapped": false, "sym": "off"]
    }

    private func stamp(_ st: Stamp, into ctx: CGContext, rgb: (Double, Double, Double), erase: Bool, live s: inout Live) {
        let key = Int((st.a * 200).rounded())
        let g: CGGradient
        if let c = s.grads[key] { g = c } else {
            let a = CGFloat(min(1, max(0, Double(key) / 200)))
            let c = CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: a), z = CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0)
            let hard = CGFloat(min(0.995, max(0, brush.hard)))
            g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c, c, z] as CFArray, locations: [0, hard, 1])!
            s.grads[key] = g
        }
        ctx.saveGState()
        if erase { ctx.setBlendMode(.destinationOut) }
        ctx.translateBy(x: st.x, y: st.y); ctx.scaleBy(x: st.r, y: st.r)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
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
    var rgb: (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
