import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UIKit

enum NativeTool: String, CaseIterable, Sendable { case paint, erase, smudge }
enum CanvasMode: String, Sendable { case draw, select, transform, eyedrop, fill }
enum SymMode: String, CaseIterable, Sendable { case off, v, h, quad, radial
    var label: String { switch self { case .off: "Off"; case .v: "Mirror, left and right"; case .h: "Mirror, top and bottom"; case .quad: "Four ways"; case .radial: "Eight ways, round" } }
}
enum GuideKind: String, CaseIterable, Sendable { case off, grid, iso, persp, persp2, persp3
    var label: String { switch self { case .off: "Off"; case .grid: "Grid"; case .iso: "Isometric"; case .persp: "One point"; case .persp2: "Two point"; case .persp3: "Three point" } }
    var points: Int { switch self { case .persp: 1; case .persp2: 2; case .persp3: 3; default: 0 } }
}
enum TileMode: String, CaseIterable, Sendable { case off, x, both
    var label: String { switch self { case .off: "Off"; case .x: "Across"; case .both: "Across and down" } }
}

struct LayerRow: Identifiable { let id: Int; let name: String; let visible: Bool; let opacity: Double; let blend: String; let lock: Bool; let clip: Bool; let group: Int; let ref: Bool; let hasMask: Bool; let raw: Bool; let glow: Double; let assist: Bool? }
struct GroupRow: Identifiable { let id: Int; let name: String; let visible: Bool; let opacity: Double; let blend: String; let open: Bool }

/// The painter's state: the open work, the stroke being drawn, undo, autosave. The stage view feeds it touches and shows what it draws.
/// This file is the core (tools, strokes, history, preferences); selection, transform, layers, assists and files are extensions beside it.
@MainActor @Observable final class NativeCanvasModel {
    // what the toolbar shows
    var tool: NativeTool = .paint { didSet { if tool != oldValue { savePrefs() } } }
    var mode: CanvasMode = .draw
    var sizes: [String: [Double]] = ["paint": [28, 100], "smudge": [44, 60], "erase": [40, 100]]   // size, opacity %: the laptop's defaults
    var color: Color = Color(red: 0.788, green: 0.659, blue: 0.298)   // #c9a84c, his gold
    var color2 = Color(red: 1, green: 1, blue: 1)
    var brush = NativeToolkit.round
    var brushColors = true            // choosing a brush also chooses its colours
    var fingerPaints = false          // fingers draw only if "Finger paints" (the laptop's rule)
    var palmGuard = true              // fingers are not gestures while the Pencil is down or just lifted
    var stabAll = 0.0                 // Stabilization for every brush (0 to 1)
    var sym: SymMode = .off
    var guide: GuideKind = .off
    var guideSize = 128.0
    var assist = false
    var quickShape = true
    var tile: TileMode = .off
    var vpEdit = false
    var rapidMs = 650.0
    var paper = "plain"
    var tangentLock = false
    var name = "Untitled"
    var line: String?                 // the one-line result under the toolbar
    var canUndo = false
    var canRedo = false
    var layerRows: [LayerRow] = []
    var groupRows: [GroupRow] = []
    var activeLayer = 0
    var selectedGroup = 0
    var maskEditing = false
    var hasDoc = false
    var docSize = ""
    var hasSelection = false
    var selShape: SelShape = .rect
    var selOp: SelOp = .replace
    var selFeather = 0
    var selTolerance = 32
    var trMode: NativeTransform.Mode = .free
    var trActive = false
    var fillThreshold = 12.0
    var recent: [String] = []
    var gestures: [String: String] = [:]
    var quick: [NativeToolkit.Profile] = NativeToolkit.quickProfiles
    var quickAt = 0
    var uiHidden = false
    var debug = false
    var syncText = "Not connected"
    var docVersion = 0
    var passPalette = -1              // Passes: each stroke takes the next colour of this palette (-1 = off)
    var facet = false                 // Facet and Curve: every stroke is straight segments with rounded corners
    var facetNext = false             // only the next stroke (the laptop's Shift)
    var tileGuides = true             // smart tile guides: the middle cross, gates, the live ghost
    var tilePrev = false              // show the tiles around the picture
    var echoOn = false                // Echo Fill: tap inside a closed shape
    var echo = EchoSettings()
    var lightOneOn = false            // Light one: tap inside a closed shape
    var lightsOff = false { didSet { if lightsOff != oldValue { stage?.rebuild() } } }
    var nodeOn = false                // Node mode: nodes on the stroke just drawn
    var nodeMax = 12
    var seamID: String?               // a garment template is under the art
    var seamOn = true
    var swapPencil = false            // the Pencil's tap and squeeze run each other's action
    var nodeBar = false               // "Finish this line?"
    var shareURLs: [URL] = []         // files waiting for the share sheet (print files, the hand trace)
    @ObservationIgnored var bgAlt: String?

    var size: Double {
        get { sizes[tool.rawValue]?[0] ?? 28 }
        set { sizes[tool.rawValue] = [max(1, min(400, newValue)), opacityPct]; prefsSoon() }
    }
    var opacityPct: Double { sizes[tool.rawValue]?[1] ?? 100 }
    var opacity: Double {
        get { opacityPct / 100 }
        set { sizes[tool.rawValue] = [size, max(5, min(100, newValue * 100))]; prefsSoon() }
    }

    @ObservationIgnored var doc: NativeDoc?
    @ObservationIgnored var workID: String?
    @ObservationIgnored let undo = UndoStack()
    @ObservationIgnored weak var stage: CanvasStage?
    @ObservationIgnored var wet: PixelBuffer?
    @ObservationIgnored var live: Live?
    @ObservationIgnored var selection: NativeSelection?
    @ObservationIgnored var transform: NativeTransform?
    @ObservationIgnored var selDrag: SelDrag?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var holdTask: Task<Void, Never>?
    @ObservationIgnored var firstDirty: Date?
    @ObservationIgnored var dirty = false
    @ObservationIgnored var lastSelection: NativeSelection.Snap?
    @ObservationIgnored var vps: [String: [CGPoint]] = [:]
    @ObservationIgnored var prefsTask: Task<Void, Never>?
    @ObservationIgnored var toolBeforeErase: NativeTool = .paint
    @ObservationIgnored var pencilDownAt: TimeInterval = 0
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var chan1: PixelBuffer?
    @ObservationIgnored var chan2: PixelBuffer?
    @ObservationIgnored var haloBrush: Brush?
    @ObservationIgnored var clipImage: CGImage?
    @ObservationIgnored var clipOrigin = CGPoint.zero
    @ObservationIgnored var propBefore: (Int, String, Any?)?
    @ObservationIgnored var soloPrev: [Bool]?
    @ObservationIgnored var vpDrag: Int?
    @ObservationIgnored var lastStroke: LastStroke?
    @ObservationIgnored var replaying = false
    @ObservationIgnored var passIndex = 0
    @ObservationIgnored var scratch = false          // a model that only redraws strokes off screen (the colour passes): it never saves, records or counts
    var seam: SeamSheet?
    @ObservationIgnored var seamStroke = SeamStroke()
    var nodes: NodeState?
    @ObservationIgnored var nodeDrag: NodeDrag?
    @ObservationIgnored var tileScan: TileScan = TileScan()
    @ObservationIgnored var tileSheet: (version: Int, image: CGImage)?
    var panel: NativePanel?

    struct SelDrag { var shape: SelShape; var p0: CGPoint; var p1: CGPoint; var pts: [CGPoint] }

    struct Live {
        var stroker: NativeStroker
        let brush: Brush
        let tool: NativeTool
        let layer: Int
        let target: PixelBuffer            // the layer's pixels, or its mask
        let onMask: Bool
        let maskHide: Bool
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
        var start: CGPoint?                 // assisted drawing: where the stroke began
        var dir: (Double, Double)?          // and the guide direction it locked to
        var snapped = false                 // QuickShape took the stroke
        var shape: (kind: String, path: [CGPoint])?
        var perfect = false
        var carry: PixelBuffer?             // smudge: the paint on the finger
        var wetRGB: [Double]?               // wet mix: the colour now on the brush
        var wetBase: [Double] = []
        var tangentOffset: (Double, Double)?
        var tangentDist = 0.0
        var tangentPrev: CGPoint?
        var tangentChecked = false
    }

    var drawing: Bool { live != nil }
    var wetBuffer: PixelBuffer? { wet }
    var scale: Double { stage?.zoom ?? 1 }

    init() { loadPrefs() }

    // MARK: works

    func startNew(w: Int, h: Int, transparent: Bool = false, paperID: String? = nil) {
        guard live == nil else { return }
        commitTransform()
        saveNow()
        do {
            let d = try NativeDoc(w: w, h: h)
            d.bgVis = !transparent
            let pid = paperID ?? "plain"
            if let p = NativeToolkit.papers.first(where: { $0.id == pid }), let g = p.ground { d.bg = g }
            d.guide["paper"] = pid
            adopt(d, id: NativeStore.newID(), name: "Untitled")
            paper = pid
            say("New canvas, \(w) by \(h).")
            markChanged()
        } catch let e as WorkFileError { say("Not made. \(e.why)") } catch { say("Not made.") }
    }

    func open(id: String) {
        guard live == nil else { return }
        commitTransform()
        saveNow()
        do {
            let d = try NativeStore.load(id)
            let n = NativeStore.loadIndex().list.first { ($0["id"] as? String) == id }?["name"] as? String ?? "Untitled"
            adopt(d, id: id, name: n)
            say("Opened \(n).")
        } catch let e as WorkFileError { say("Not opened. \(e.why)") } catch { say("Not opened. The file is missing.") }
    }

    func adopt(_ d: NativeDoc, id: String, name: String) {
        doc = d; workID = id; self.name = name; wet = nil; undo.reset(); live = nil; selection = nil; transform = nil; trActive = false
        hasDoc = true; docSize = "\(d.w) × \(d.h)"; hasSelection = false; maskEditing = false; selectedGroup = 0; mode = .draw
        if let g = d.guide["g"] as? String, let k = GuideKind(rawValue: g) { guide = k } else { guide = .off }
        if let t = d.guide["tile"] as? String, let k = TileMode(rawValue: t) { tile = k } else { tile = .off }
        if let s = d.guide["size"] as? Double { guideSize = s } else if let s = d.guide["size"] as? Int { guideSize = Double(s) }
        paper = d.guide["paper"] as? String ?? "plain"
        loadSeam(d.guide["seam"] as? String)
        vps = [:]
        if let o = d.guide["vps"] as? [String: Any] {
            for (k, v) in o { if let a = v as? [[Double]] { vps[k] = a.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } } }
        }
        syncFlags(); stage?.rebuild(); stage?.fit(); stage?.refreshSelection()
        NativeStore.rememberCurrent(id)
        NativeTimelapse.shared.attach(id)
    }

    /// Writes the open work to the phone now. Returns false (and says why) when it could not.
    @discardableResult func saveNow() -> Bool {
        saveTask?.cancel(); saveTask = nil; firstDirty = nil
        guard dirty, live == nil, let d = doc, let id = workID else { return true }
        writeGuide(into: d)
        do { try NativeStore.save(d, id: id, name: name); dirty = false; onChange?(); return true }
        catch { say("Not saved. \((error as? WorkFileError)?.why ?? "The phone refused the file.")"); return false }
    }

    func delete(id: String) {
        do {
            try NativeStore.delete(id)
            NativeTimelapse.shared.discard(id)
            if id == workID { doc = nil; workID = nil; hasDoc = false; stage?.rebuild() }
            say("Deleted.")
            onChange?()
        } catch { say("Not deleted.") }
    }

    func rename(_ n: String) {
        let t = String(n.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !t.isEmpty else { return }
        name = t
        if let id = workID {
            var ix = NativeStore.loadIndex()
            if let k = ix.list.firstIndex(where: { ($0["id"] as? String) == id }) {
                ix.list[k]["name"] = t; ix.list[k]["updated"] = Date().timeIntervalSince1970 * 1000
                try? NativeStore.saveIndex(ix)
            }
        }
        markChanged(); onChange?()
    }

    // MARK: autosave (3 s after the last change, never more than 12 s of continuous drawing without a save: the laptop's rule)

    func markChanged() {
        if scratch { return }
        dirty = true; docVersion += 1
        NativeTimelapse.shared.changed(self)
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

    // MARK: touches

    /// Fingers draw only if "Finger paints"; in every other mode a single finger is the tool (select, transform, pick, fill).
    func accepts(pencil: Bool) -> Bool {
        guard doc != nil else { return false }
        if mode == .draw { return pencil || fingerPaints || echoOn || lightOneOn || (nodeOn && nodes != nil) }
        return true
    }

    func touchBegan(_ p: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?, pencil: Bool) {
        if pencil { pencilDownAt = time }
        switch mode {
        case .draw:
            if echoOn { echoFill(at: p); return }
            if lightOneOn { lightOne(at: p); return }
            if nodeOn, nodeDown(p) { return }
            if vpBegin(at: p) { return }
            begin(at: p, pressure: pressure, time: time, tilt: tilt)
        case .select: selectDown(p)
        case .transform: transform?.down(p, scale: scale); stage?.refreshFloat()
        case .eyedrop: pick(at: p)
        case .fill: fillDrop(at: p)
        }
    }
    func touchMoved(_ p: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?) {
        switch mode {
        case .draw:
            if nodeDrag != nil { nodeMove(p); return }
            if vpDrag != nil { vpMove(to: p); return }
            extend(to: p, pressure: pressure, time: time, tilt: tilt)
        case .select: selectMove(p)
        case .transform: transform?.move(p, scale: scale); stage?.refreshFloat()
        case .eyedrop: pick(at: p)
        case .fill: break
        }
    }
    func touchEnded(_ p: CGPoint) {
        switch mode {
        case .draw:
            if nodeDrag != nil { nodeUp(); return }
            if vpDrag != nil { vpEnd(); return }
            let had = live
            end()
            if nodeOn, let h = had, h.tool == .paint, !h.onMask { nodeAttach(tapAt: p, stroke: h) }
        case .select: selectUp()
        case .transform:
            if let t = transform, let d = t.drag, case .outside = d.kind, !d.moved { t.nudge(toward: p) }
            transform?.up(); stage?.refreshFloat()
        case .eyedrop, .fill: break
        }
    }
    func touchCancelled() {
        switch mode {
        case .draw: nodeDrag = nil; cancel()
        case .select: selDrag = nil; stage?.updateOverlay()
        case .transform: transform?.drag = nil
        default: break
        }
    }

    // MARK: strokes

    func begin(at p: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?) {
        guard let d = doc, live == nil else { return }
        let L = d.layers[d.active]
        guard d.isShown(L) else { say("This layer is hidden."); return }
        let onMask = maskEditing && L.maskPx != nil
        if tool == .paint, !onMask, passPalette >= 0 { nextPassColour() }
        if tool == .smudge && onMask { say("Smudge is not available on a mask."); return }
        let direct = tool != .paint || onMask
        haloBrush = nil
        if !direct, wet == nil { wet = PixelBuffer(w: d.w, h: d.h) }
        if !direct, wet == nil { say("Not drawn. This phone has no room for the stroke buffer."); return }
        let B = tool == .smudge ? Brush.plain(defaults: NativeToolkit.defaults) : brush
        let lum: Double = { let c = UIColor(color).rgb; return c.0 * 0.299 + c.1 * 0.587 + c.2 * 0.114 }()
        let hide = onMask && (tool == .erase || lum < 0.5)
        let col = onMask ? "#ffffff" : tool == .erase ? "#000000" : UIColor(color).hex
        var st = NativeStroker(B, size: size)
        st.global = stabAll
        live = Live(stroker: st, brush: B, tool: tool, layer: d.active, target: onMask ? L.maskPx! : L.pixels, onMask: onMask, maskHide: hide,
                    color: col, color2: UIColor(color2).hex, op: opacity, size: size, t0: time)
        wetState = WetState(); seamStroke = SeamStroke()
        if tool == .paint, !onMask { pushRecent(UIColor(color).hex) }
        extend(to: p, pressure: pressure, time: time, tilt: tilt)
    }

    func extend(to pIn: CGPoint, pressure: Double, time: TimeInterval, tilt: (Double, Double)?) {
        guard var s = live, let d = doc, !s.snapped else { return }
        var x = Double(pIn.x), y = Double(pIn.y)
        // Tangent lock: the start slides onto the line of an earlier stroke it continues
        if tangentLock, s.tool == .paint, !s.onMask { (x, y) = tangentAdjust(&s, x, y) }
        // assisted drawing: the stroke locks to the nearest guide direction once it has moved a little
        if assistActive(layer: d.active), guide != .off {
            let q = assistPoint(&s, x, y); x = q.0; y = q.1
        }
        let raw = max(0.02, min(1, pressure))
        let sm = s.pAvg.map { $0 * 0.5 + raw * 0.5 } ?? raw   // the laptop's pAvg: pressure averaged half and half with the last value
        s.pAvg = sm
        let ms = ((time - s.t0) * 1000).rounded()
        let tl: (Double, Double)? = s.brush.usesTilt ? tilt.map { (Double(Int($0.0)), Double(Int($0.1))) } : nil   // tilt is kept in the log only when the brush uses it
        var pt: [Any] = [(x * 10).rounded() / 10, (y * 10).rounded() / 10, (sm * 100).rounded() / 100, Int(ms)]
        if let tl { pt.append(Int(tl.0)); pt.append(Int(tl.1)) }
        s.pts.append(pt)
        s.raw.append((x: x, y: y, p: sm, t: ms, tilt: tl))
        let dabs = s.stroker.add(x: x, y: y, p: sm, t: ms, tilt: tl)
        lay(dabs, &s, on: d)
        live = s
        refreshLive(s)
        armHold()
    }

    func refreshLive(_ s: Live) {
        let direct = s.tool != .paint || s.onMask
        stage?.refresh(active: s.layer, wetOpacity: direct ? 0 : s.op)
        if tile != .off && tileGuides { stage?.updateOverlay() }
    }

    /// Hold still at the end and QuickShape takes the stroke (0.6 s, the laptop's).
    private func armHold() {
        holdTask?.cancel()
        guard quickShape, let s = live, s.tool != .smudge, !s.snapped else { return }
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.snapShape()
        }
    }

    /// Dabs (with their symmetric and tile copies) onto the wet buffer (paint) or straight onto the layer (erase, smudge, mask).
    func lay(_ dabs: [Dab], _ s: inout Live, on d: NativeDoc) {
        let B = s.brush
        for dab0 in dabs {
            for dab in copies(of: dab0, brush: B, size: s.size, in: d) {
                let r = B.radius(size: s.size, pressure: dab.p, f: dab.f)
                let reach = r * 1.5 + 4 + (dab.span / 2) + (B.n("channel") > 0 ? B.n("channel") * s.size * 2 : 0)
                var box = CGRect(x: dab.x - reach, y: dab.y - reach, width: reach * 2, height: reach * 2)
                if let tw = dab.tw { box = box.union(CGRect(x: dab.x + tw.dx - reach, y: dab.y + tw.dy - reach, width: reach * 2, height: reach * 2)) }
                if s.tool == .smudge {
                    smudgeDab(dab, &s, d)
                    continue
                }
                s.dirty = s.dirty.map { $0.union(box) } ?? box
                if s.tool == .erase || s.onMask {
                    for k in s.target.tiles(in: box) where s.before[k] == nil { s.before[k] = s.target.tilePixels(tx: k.tx, ty: k.ty) }
                    let c = s.target.ctx
                    c.saveGState()
                    selection?.clip(c)
                    c.setBlendMode(s.tool == .erase || s.maskHide ? .destinationOut : .normal)
                    var dd = dab; dd.am *= s.op
                    paintDab(dd, B, s, into: c, ink: s.tool == .erase || s.maskHide ? "#000000" : "#ffffff")
                    c.restoreGState()
                } else if let w = wet {
                    w.ctx.saveGState()
                    selection?.clip(w.ctx)
                    paintDab(dab, B, s, into: w.ctx, ink: nil)
                    w.ctx.restoreGState()
                    if B.n("channel") > 0, B.t("channelEnds") != "all" { sideStamp(dab, B, size: s.size, doc: d) }
                }
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
        if ink == nil, B.n("wet") > 0, let d = doc {
            col = wetColour(&wetState, at: dab.x, y: dab.y, radius: B.radius(size: s.size, pressure: dab.p, f: dab.f), B, base: s.color, layer: d.layers[s.layer].pixels)
        }
        if ink == nil, B.n("hueJit") > 0 || B.n("satJit") > 0 || B.n("briJit") > 0 {
            col = NativeStamp.jitterColour(col, hue: B.n("hueJit"), sat: B.n("satJit"), bri: B.n("briJit"), x: dab.x, y: dab.y)
        }
        NativeStamp.drawWithTwin(ctx, B, color: col, color2: ink ?? s.color2, size: s.size, dab)
    }

    /// The line catches up with the pen after release (StreamLine lags it).
    private func catchUp(_ st: inout NativeStroker, _ s: Live) -> [Dab] {
        guard max(st.B.n("stream"), stabAll * 0.7) > 0, let q = s.raw.last else { return [] }
        var out: [Dab] = []
        for _ in 0..<14 { out += st.add(x: q.x, y: q.y, p: s.pAvg ?? 1, t: q.t, tilt: nil) }
        return out
    }

    func end() {
        holdTask?.cancel()
        guard var s = live, let d = doc else { return }
        let L = d.layers[s.layer]
        if s.tool == .smudge {
            live = nil
            finishDirect(s, d, L)
            return
        }
        if !s.snapped, s.tool == .paint, !s.onMask, facet || facetNext {
            facetNext = false
            facetApply(&s, d)
        }
        if !s.snapped {
            // the line catches up with the pen, and an end taper needs the whole length, so the stroke is laid down once more (the laptop's `finishStroke`)
            var st = s.stroker
            let flushed = st.flush()
            lay(flushed, &s, on: d)
            let caught = catchUp(&st, s)
            lay(caught, &s, on: d)
            s.stroker = st
            if s.brush.needsLength, s.stroker.dist > 8, let box = s.dirty?.integral {
                if s.tool == .paint, !s.onMask { wet?.clear(box) } else { for (k, data) in s.before { s.target.setTile(tx: k.tx, ty: k.ty, data) } }
                seamStroke = SeamStroke()
                var again = NativeStroker(s.brush, size: s.size, total: s.stroker.dist)
                again.global = stabAll
                for q in s.raw { let dabs = again.add(x: q.x, y: q.y, p: q.p, t: q.t, tilt: q.tilt); lay(dabs, &s, on: d) }
                let tail = again.flush()
                lay(tail, &s, on: d)
                let more = catchUp(&again, s)
                lay(more, &s, on: d)
            }
        }
        live = nil
        if s.tool == .paint, !s.onMask, s.brush.n("satellites") > 0, let w = wet,
           let extra = NativeEffects.satellites(s.brush, pts: s.pts, size: s.size, color: s.color, wet: w, selection: selection) { s.dirty = s.dirty.map { $0.union(extra) } ?? extra }
        guard let box = s.dirty?.integral else { stage?.refresh(active: s.layer, wetOpacity: 0); return }
        if s.tool == .paint, !s.onMask, let w = wet {
            var before = s.before
            let B = s.brush
            if B.n("weave") > 0 { weaveCut(wet: w, layer: L.pixels, brush: B, size: s.size, pts: s.pts, box: box) }
            // the channels are measured before the paper grain touches the stroke, so the clearance is the whole band
            let rings = B.n("channel") > 0 && !L.alphaLock ? NativeEffects.rings(B, size: s.size, wet: w, side1: chan1, side2: chan2, dirty: box, fallback: s.color2, docW: d.w, docH: d.h) : []
            if B.t("grain") != "none", B.t("grainMode") == "texturised" { NativeStamp.applyGrain(w.ctx, B, in: box) }
            if B.n("wick") > 0 { NativeEffects.wick(w, B, size: s.size, box: box) }
            if B.n("echo") > 0 { NativeEffects.echoInside(w, B, size: s.size, box: box) }
            let wide = rings.first.map { box.union($0.box) } ?? box
            for k in L.pixels.tiles(in: wide) where before[k] == nil { before[k] = L.pixels.tilePixels(tx: k.tx, ty: k.ty) }
            NativeEffects.applyRings(rings, to: L.pixels, wet: w, selection: selection)
            if let img = w.image() {
                L.pixels.ctx.saveGState()
                L.pixels.drawUpright(img, in: box, alpha: CGFloat(s.op), blend: L.alphaLock ? .sourceAtop : .normal)
                L.pixels.ctx.restoreGState()
            }
            w.clear(box.union(wide)); clearSideBuffers(wide)
            s.before = before
        }
        finishDirect(s, d, L)
    }

    /// The common end of every stroke: history, the log, the Daily Mark.
    private func finishDirect(_ s0: Live, _ d: NativeDoc, _ L: NativeLayer) {
        let s = s0
        guard !s.before.isEmpty else { stage?.refresh(active: s.layer, wetOpacity: 0); return }
        let px = s.target
        let tiles = s.before.keys.sorted { ($0.ty, $0.tx) < ($1.ty, $1.tx) }.map { k in (k, s.before[k]!, px.tilePixels(tx: k.tx, ty: k.ty)) }
        var logIdx: Int?
        if s.tool != .smudge {
            d.log.append(logRecord(s)); logIdx = d.log.count - 1
            if !replaying { NativeDaily.bump() }
        } else { d.layers[s.layer].meta["raw"] = true }
        let label = s.tool == .paint ? "Stroke" : s.tool == .erase ? "Erase" : "Smudge"
        undo.push(HistoryEntry(label: label, structural: false,
                               undo: { for t in tiles { px.setTile(tx: t.0.tx, ty: t.0.ty, t.1) }; if let i = logIdx, d.log.indices.contains(i) { d.log[i]["dead"] = true } },
                               redo: { for t in tiles { px.setTile(tx: t.0.tx, ty: t.0.ty, t.2) }; if let i = logIdx, d.log.indices.contains(i) { d.log[i]["dead"] = false } }))
        if s.tool == .paint, !s.onMask, !s.snapped, let li = logIdx {
            lastStroke = LastStroke(brush: s.brush, size: s.size, op: s.op, color: s.color, color2: s.color2, layer: s.layer, pts: s.pts, depth: undo.done.count, logIdx: li)
        } else { lastStroke = nil }
        if !scratch { NativeStudy.shared.stroke(s, doc: d, canvas: self) }
        syncFlags()
        stage?.refresh(active: s.layer, wetOpacity: 0)
        if s.onMask { stage?.refreshAll() }
        markChanged()
        _ = L
    }

    func pushTiles(_ px: PixelBuffer, _ tiles: [(TileKey, Data, Data)], label: String, layer: Int) {
        undo.push(HistoryEntry(label: label, structural: false,
                               undo: { for t in tiles { px.setTile(tx: t.0.tx, ty: t.0.ty, t.1) } },
                               redo: { for t in tiles { px.setTile(tx: t.0.tx, ty: t.0.ty, t.2) } }))
    }

    /// A second finger landed or the system took the touch: the stroke is taken back as if it never began.
    func cancel() {
        holdTask?.cancel()
        guard let s = live, doc != nil else { return }
        live = nil
        if s.tool == .paint, !s.onMask { if let w = wet, let box = s.dirty?.integral { w.clear(box); clearSideBuffers(box) } }
        else { for (k, data) in s.before { s.target.setTile(tx: k.tx, ty: k.ty, data) } }
        stage?.refresh(active: s.layer, wetOpacity: 0)
        if s.onMask { stage?.refreshAll() }
    }

    /// One stroke in the laptop's log shape (`app.js`, the `rec` in the stroke-commit function).
    private func logRecord(_ s: Live) -> [String: Any] {
        let B = s.brush
        let bs: [String: Any] = ["ps": B.n("pressSize"), "twin": B.n("twin"), "gap": B.n("twinGap"), "side": B.t("twinSide"), "ch": B.n("channel"), "lines": B.n("lines"),
                                 "lineGap": B.n("lineGap"), "wet": B.n("wet"), "round": B.shape != "square" && B.shape != "tube", "k": B.shape == "square" ? 0.72 : B.shape == "tube" ? 0.92 : 1, "pc": B.n("pressCurve")]
        let c2: Any = B.n("twin") > 0 ? s.color2 : NSNull()
        return ["tool": s.tool.rawValue, "color": s.color, "color2": c2, "size": s.size, "op": s.op, "brush": B.id, "layer": doc?.layerID(s.layer) ?? (s.layer + 1), "onMask": s.onMask,
                "t": Int((s.t0 * 1000).rounded()), "pts": s.pts, "bs": bs, "snapped": s.snapped, "sym": sym.rawValue]
    }

    // MARK: wet mix state (kept beside the live stroke because the dab painter only receives a copy of it)

    @ObservationIgnored var wetState: WetState = WetState()
    struct WetState { var rgb: [Double]?; var base: [Double] = [] }

    // MARK: history

    func undoStroke() {
        guard live == nil else { return }
        if trActive { cancelTransform(); return }
        guard let e = undo.undo() else { say("Nothing to undo."); return }
        afterHistory(e)
    }
    func redoStroke() {
        guard live == nil, !trActive else { return }
        guard let e = undo.redo() else { say("Nothing to redo."); return }
        afterHistory(e)
    }
    func afterHistory(_ e: HistoryEntry) {
        selection.map { hasSelection = $0.has } ?? { hasSelection = false }()
        if e.structural { stage?.rebuild() } else { stage?.refreshAll() }
        syncFlags(); stage?.refreshSelection(); markChanged()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Adds a finished edit to the history. The closures are run by undo and redo, so they hold what they need.
    func record(_ label: String, structural: Bool = false, undo u: @escaping () -> Void, redo r: @escaping () -> Void) {
        undo.push(HistoryEntry(label: label, structural: structural, undo: u, redo: r))
        syncFlags(); markChanged()
    }

    func syncFlags() {
        canUndo = undo.canUndo; canRedo = undo.canRedo
        if let d = doc {
            layerRows = d.layers.enumerated().map { i, l in
                LayerRow(id: i, name: l.name, visible: l.visible, opacity: l.opacity, blend: l.meta["blend"] as? String ?? "source-over", lock: l.alphaLock, clip: l.meta["clip"] as? Bool ?? false,
                         group: l.meta["grp"] as? Int ?? 0, ref: l.meta["ref"] as? Bool ?? false, hasMask: l.maskPx != nil, raw: l.meta["raw"] as? Bool ?? true, glow: (l.meta["glow"] as? Double) ?? Double(l.meta["glow"] as? Int ?? 0), assist: l.meta["assist"] as? Bool)
            }
            groupRows = d.groups.map { g in
                GroupRow(id: g["id"] as? Int ?? 0, name: g["name"] as? String ?? "Group", visible: g["vis"] as? Bool ?? true,
                         opacity: (g["op"] as? Double) ?? Double(g["op"] as? Int ?? 1), blend: g["blend"] as? String ?? "source-over", open: g["open"] as? Bool ?? true)
            }
            activeLayer = d.active
            hasSelection = selection?.has ?? false
        } else { layerRows = []; groupRows = []; activeLayer = 0; hasSelection = false }
    }

    func say(_ s: String?) { line = s }

    // MARK: colours

    func pushRecent(_ hex: String) {
        guard recent.first != hex else { return }
        recent = Array(([hex] + recent.filter { $0 != hex }).prefix(24))
        prefsSoon()
    }
    func setColour(hex: String) {
        guard let c = Hex.rgb(hex) else { return }
        color = Color(red: c.0, green: c.1, blue: c.2)
    }
    func swapColours() { let t = color; color = color2; color2 = t }

    func selectBrush(_ b: Brush) {
        brush = NativeBrushColours.apply(b)
        if brushColors {
            if !brush.t("color").isEmpty { setColour(hex: brush.t("color")) }
            if !brush.t("color2").isEmpty, let c = Hex.rgb(brush.t("color2")) { color2 = Color(red: c.0, green: c.1, blue: c.2) }
        }
        savePrefs()
    }

    // MARK: preferences (this phone only)

    func prefsSoon() {
        prefsTask?.cancel()
        prefsTask = Task { [weak self] in try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { self?.savePrefs() } }
    }
    func savePrefs() {
        let o: [String: Any] = ["tool": tool.rawValue, "sizes": sizes, "color": UIColor(color).hex, "color2": UIColor(color2).hex, "brush": brush.id, "finger": fingerPaints, "palm": palmGuard,
                                "stab": stabAll, "quickShape": quickShape, "assist": assist, "rapid": rapidMs, "gest": gestures, "recent": recent, "brushColors": brushColors, "tangent": tangentLock,
                                "quickAt": quickAt, "debug": debug, "facet": facet, "tileGuides": tileGuides, "tilePrev": tilePrev, "swapPencil": swapPencil, "nodeMax": nodeMax, "echo": [echo.step, echo.weight, echo.count, echo.first], "fillThreshold": fillThreshold, "quick": quick.map { ["name": $0.name, "slots": $0.slots] }]
        if let d = try? JSONSerialization.data(withJSONObject: o) { UserDefaults.standard.set(d, forKey: "plpn-prefs") }
    }
    func loadPrefs() {
        gestures = Dictionary(uniqueKeysWithValues: NativeToolkit.gestures.map { ($0.id, $0.def) })
        guard let d = UserDefaults.standard.data(forKey: "plpn-prefs"), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if let t = o["tool"] as? String, let k = NativeTool(rawValue: t) { tool = k }
        if let s = o["sizes"] as? [String: [Double]] { sizes.merge(s) { _, n in n } }
        if let c = o["color"] as? String { setColour(hex: c) }
        if let c = o["color2"] as? String, let r = Hex.rgb(c) { color2 = Color(red: r.0, green: r.1, blue: r.2) }
        if let id = o["brush"] as? String, let b = (NativeToolkit.all + NativeMine.brushes).first(where: { $0.id == id }) { brush = NativeBrushColours.apply(b) }
        fingerPaints = o["finger"] as? Bool ?? false; palmGuard = o["palm"] as? Bool ?? true
        stabAll = o["stab"] as? Double ?? 0; quickShape = o["quickShape"] as? Bool ?? true; assist = o["assist"] as? Bool ?? false
        rapidMs = o["rapid"] as? Double ?? 650; recent = o["recent"] as? [String] ?? []; brushColors = o["brushColors"] as? Bool ?? true
        tangentLock = o["tangent"] as? Bool ?? false; quickAt = o["quickAt"] as? Int ?? 0; debug = o["debug"] as? Bool ?? false
        fillThreshold = o["fillThreshold"] as? Double ?? 12
        facet = o["facet"] as? Bool ?? false; tileGuides = o["tileGuides"] as? Bool ?? true; tilePrev = o["tilePrev"] as? Bool ?? false
        swapPencil = o["swapPencil"] as? Bool ?? false; nodeMax = o["nodeMax"] as? Int ?? 12
        if let e = o["echo"] as? [Double], e.count == 4 { echo = EchoSettings(step: e[0], weight: e[1], count: e[2], first: e[3]) }
        if let g = o["gest"] as? [String: String] { gestures.merge(g) { _, n in n } }
        if let q = o["quick"] as? [[String: Any]], !q.isEmpty { quick = q.map { NativeToolkit.Profile(name: $0["name"] as? String ?? "Profile", slots: $0["slots"] as? [String] ?? []) } }
    }
}

extension UIColor {
    var hex: String { let c = rgb; return Hex.string(r: c.0, g: c.1, b: c.2) }
    var rgb: (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
