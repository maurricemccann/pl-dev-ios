import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The last stroke, kept so it can be drawn again from its pen path with a changed size, swell, clearance, companion or lines (the laptop's
/// "Adjust last stroke"), and a whole layer of strokes drawn again at once (its "restyle").
struct LastStroke {
    let brush: Brush; let size: Double; let op: Double; let color: String; let color2: String; let layer: Int; let pts: [[Any]]; let depth: Int; let logIdx: Int
}

extension NativeCanvasModel {
    /// The last stroke, if it is still the last thing that happened.
    var tweakable: LastStroke? {
        guard let l = lastStroke, let d = doc, live == nil, !trActive, undo.done.count == l.depth, d.log.indices.contains(l.logIdx), l.logIdx == d.log.count - 1, d.layers.indices.contains(l.layer) else { return nil }
        return l
    }

    /// One stroke laid down again from its recorded points. The path is fed to the engine as it was (already averaged), then finished the usual way.
    func replay(brush B: Brush, size: Double, op: Double, color: String, color2: String, layer: Int, pts: [[Any]], tool: NativeTool) {
        guard let d = doc, live == nil, d.layers.indices.contains(layer) else { return }
        let L = d.layers[layer]
        if tool == .paint, wet == nil { wet = PixelBuffer(w: d.w, h: d.h) }
        if tool == .paint, wet == nil { return }
        haloBrush = nil
        var st = NativeStroker(B, size: size); st.global = stabAll
        var s = Live(stroker: st, brush: B, tool: tool, layer: layer, target: L.pixels, onMask: false, maskHide: false, color: color, color2: color2, op: op, size: size, t0: 0)
        wetState = WetState(); seamStroke = SeamStroke()
        for r in pts where r.count >= 4 {
            let x = NativeCanvasModel.num(r[0]), y = NativeCanvasModel.num(r[1]), p = NativeCanvasModel.num(r[2]), t = NativeCanvasModel.num(r[3])
            let tilt: (Double, Double)? = r.count >= 6 ? (NativeCanvasModel.num(r[4]), NativeCanvasModel.num(r[5])) : nil
            s.pAvg = p; s.pts.append(r); s.raw.append((x: x, y: y, p: p, t: t, tilt: tilt))
            lay(s.stroker.add(x: x, y: y, p: p, t: t, tilt: tilt), &s, on: d)
        }
        live = s
        end()
    }

    /// The last stroke drawn again with new settings. `size` is in pixels; `over` holds brush parameters by their toolkit names.
    func tweakLast(size: Double?, _ over: [String: Double], pts newPts: [[Any]]? = nil) {
        guard let l = tweakable, let d = doc else { say("The last thing you did was not a stroke you can adjust."); return }
        var B = l.brush
        for (k, v) in over { B = B.setting(k, v) }
        replaying = true; defer { replaying = false }
        undoStroke()
        if d.log.indices.contains(l.logIdx) { d.log.remove(at: l.logIdx) }
        replay(brush: B, size: size ?? l.size, op: l.op, color: l.color, color2: l.color2, layer: l.layer, pts: newPts ?? l.pts, tool: .paint)
    }

    /// Makes what the last stroke was drawn with the brush's own setting.
    func keepTweak() {
        guard let l = tweakable else { return }
        brush = l.brush
        sizes["paint"] = [l.size, opacityPct]
        savePrefs()
        say("Kept as this brush's setting.")
    }

    /// Every paint and erase stroke on the active layer drawn again from its pen path, with a size scale and brush overrides: one undo step.
    func restyleLayer(scale k: Double, _ over: [String: Double], bend: (logIndex: Int, pts: [[Any]])? = nil) {
        guard live == nil, !trActive, let d = doc, d.layers.indices.contains(d.active) else { return }
        let L = d.layers[d.active], lid = d.layerID(d.active)
        guard L.meta["raw"] as? Bool != true else { say("This layer has fills, pasted or smudged parts. Restyle can only rebuild a layer made of strokes."); return }
        let idx = d.log.indices.filter { i in
            let r = d.log[i]
            return (r["layer"] as? Int) == lid && r["dead"] as? Bool != true && r["onMask"] as? Bool != true && ["paint", "erase"].contains(r["tool"] as? String ?? "")
        }
        guard !idx.isEmpty else { say("There are no strokes on this layer to restyle."); return }
        let all = NativeToolkit.all + NativeMine.brushes
        let recs = idx.map { d.log[$0] }
        let logBefore = d.log, pxBefore = L.pixels.snapshot()
        let drop = Set(idx)
        d.log = d.log.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
        let depth = undo.done.count, hadSel = selection, hadSym = sym
        selection = nil; replaying = true
        L.pixels.clear(CGRect(x: 0, y: 0, width: d.w, height: d.h))
        for (n, r) in recs.enumerated() {
            guard var pts = r["pts"] as? [[Any]], !pts.isEmpty else { continue }
            if let b = bend, b.logIndex == idx[n] { pts = b.pts }
            let tool: NativeTool = (r["tool"] as? String) == "erase" ? .erase : .paint
            var B = all.first { $0.id == (r["brush"] as? String ?? "") } ?? brush
            if tool == .paint { for (key, v) in over { B = B.setting(key, v) } }
            sym = SymMode(rawValue: r["sym"] as? String ?? "off") ?? .off
            let size = max(1, (NativeCanvasModel.num(r["size"] ?? 0) * k).rounded())
            replay(brush: B, size: size, op: NativeCanvasModel.num(r["op"] ?? 1), color: r["color"] as? String ?? "#000000", color2: (r["color2"] as? String) ?? "#ffffff", layer: d.active, pts: pts, tool: tool)
        }
        selection = hadSel; sym = hadSym; replaying = false
        undo.dropLast(undo.done.count - depth)
        let pxAfter = L.pixels.snapshot(), logAfter = d.log
        lastStroke = nil
        record("Restyle", undo: { L.pixels.restore(pxBefore); d.log = logBefore }, redo: { L.pixels.restore(pxAfter); d.log = logAfter })
        stage?.refreshAll()
        say("\(recs.count) stroke\(recs.count == 1 ? "" : "s") drawn again.")
    }
}

/// Adjust last stroke, and restyle the whole layer.
struct NativeTweakSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var scope = 0
    @State private var size = 28.0
    @State private var vals: [String: Double] = [:]
    @State private var layerK = 1.0
    @State private var layerOver: [String: Double] = [:]
    @State private var job: Task<Void, Never>?
    @State private var loaded = false

    static let rows: [(key: String, label: String, lo: Double, hi: Double, step: Double)] = [
        ("pressSize", "Width swell", 0, 1, 0.01), ("channel", "Clearance", 0, 1, 0.01), ("twin", "Companion width", 0, 1, 0.01),
        ("twinGap", "Companion gap", -0.5, 0.6, 0.01), ("lines", "Lines", 1, 3, 1), ("lineGap", "Space between lines", -0.3, 1.5, 0.01),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Scope", selection: $scope) { Text("Last stroke").tag(0); Text("Whole layer").tag(1) }.pickerStyle(.segmented)
                if scope == 0 { lastStroke } else { wholeLayer }
                if let l = canvas.line { Section { ResultLine(text: l) } }
            }
            .navigationTitle("Adjust strokes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { load() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var lastStroke: some View {
        if let l = canvas.tweakable {
            Section {
                slider("Size (px)", Binding(get: { size }, set: { size = $0; push() }), 4...300, 1, whole: true)
                ForEach(Self.rows, id: \.key) { r in
                    slider(r.label, Binding(get: { vals[r.key] ?? l.brush.n(r.key) }, set: { vals[r.key] = $0; push() }), r.lo...r.hi, r.step, whole: r.key == "lines")
                }
            } footer: { Text("The stroke is drawn again from your pen path as you move a slider.") }
            Section { Button("Keep as this brush's setting") { canvas.keepTweak() } }
        } else {
            Section { ContentUnavailableView("Draw a stroke first", systemImage: "scribble", description: Text("Then adjust it here: it is drawn again from your pen path as you move a slider.")) }
        }
    }

    @ViewBuilder private var wholeLayer: some View {
        Section {
            slider("Size of every stroke (×)", Binding(get: { layerK }, set: { layerK = $0 }), 0.3...3, 0.05, whole: false)
            ForEach(Self.rows, id: \.key) { r in
                HStack {
                    slider(r.label, Binding(get: { layerOver[r.key] ?? r.lo }, set: { layerOver[r.key] = $0 }), r.lo...r.hi, r.step, whole: r.key == "lines")
                    if layerOver[r.key] != nil { Button { layerOver[r.key] = nil } label: { Image(systemName: "arrow.uturn.backward.circle") }.buttonStyle(.plain).accessibilityLabel("Let go of \(r.label)") }
                }
            }
        } footer: { Text("Every stroke on this layer is drawn again from its pen path. A slider you leave alone keeps each stroke as it was drawn.") }
        Section {
            Button("Draw the strokes again") { canvas.restyleLayer(scale: layerK, layerOver) }.buttonStyle(.borderedProminent)
            Button("Reset the sliders") { layerK = 1; layerOver = [:] }
        }
    }

    private func slider(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ step: Double, whole: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(t); Spacer(); Text(String(format: whole ? "%.0f" : "%.2f", v.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: v, in: r, step: step)
        }
    }

    private func load() {
        guard !loaded, let l = canvas.tweakable else { return }
        loaded = true; size = l.size
    }

    private func push() {
        job?.cancel()
        job = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            canvas.tweakLast(size: size, vals)
        }
    }
}
