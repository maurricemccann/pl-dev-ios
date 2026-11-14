import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Echo Fill, Lights off, Light one and Other ground (the laptop's `echoFill`, `edtMask`, `echoAlpha`, `lightOne`, `lightsOff`, `otherGround`).
/// Echo Fill fills a closed shape with concentric lines, the way his spec describes: the first starts a little inside the edge, then one every
/// step, each a set thickness, as many as asked (or all the way to the middle).
struct EchoSettings { var step = 14.0, weight = 3.0, count = 40.0, first = 8.0 }

enum NativeEDT {
    /// Distance in pixels from every pixel of a mask to the nearest pixel outside it (chamfer 3-4); `inside[i]` is the mask; the picture's border counts as outside.
    static func distance(_ inside: [Bool], _ w: Int, _ h: Int) -> [Float] {
        let INF: Float = 1e8
        var d = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) where inside[i] { d[i] = INF }
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            if d[i] == 0 { continue }
            var v = d[i]
            v = min(v, (x > 0 ? d[i - 1] : 0) + 3, (y > 0 ? d[i - w] : 0) + 3, (x > 0 && y > 0 ? d[i - w - 1] : 0) + 4, (x < w - 1 && y > 0 ? d[i - w + 1] : 0) + 4)
            d[i] = v
        } }
        for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            if d[i] == 0 { continue }
            var v = d[i]
            v = min(v, (x < w - 1 ? d[i + 1] : 0) + 3, (y < h - 1 ? d[i + w] : 0) + 3, (x < w - 1 && y < h - 1 ? d[i + w + 1] : 0) + 4, (x > 0 && y < h - 1 ? d[i + w - 1] : 0) + 4)
            d[i] = v
        } }
        for i in 0..<(w * h) { d[i] /= 3 }
        return d
    }

    /// Concentric lines: the first starts `first` px inside the edge, then every `step`, each `lw` thick, `count` of them.
    static func alpha(_ dist: [Float], first: Double, step: Double, lw: Double, count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: dist.count)
        for i in 0..<dist.count {
            let dv = Double(dist[i])
            if dv <= 0 { continue }
            let k = ((dv - first - lw / 2) / step).rounded()
            if k < 0 || Int(k) >= count { continue }
            let c = first + lw / 2 + k * step
            out[i] = UInt8(max(0, min(255, (lw / 2 + 0.5 - abs(dv - c)) * 255)))
        }
        return out
    }
}

extension NativeCanvasModel {
    /// The tapped region (a closed shape on the reference layer, or the active one): its mask and its box, or nil with a word.
    private func shapeUnder(_ p: CGPoint) -> (mask: [UInt8], box: CGRect)? {
        guard let d = doc else { return nil }
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < d.w, y < d.h else { return nil }
        let L = d.layers[d.active]
        let ref = d.layers.enumerated().first { $0.element.meta["ref"] as? Bool == true && $0.offset != d.active }?.element
        let m = NativeFlood.mask(ref?.pixels ?? L.pixels, x: x, y: y, tolerance: 24)
        guard m.count == d.w * d.h else { return nil }
        var x0 = d.w, y0 = d.h, x1 = -1, y1 = -1
        for yy in 0..<d.h { for xx in 0..<d.w where m[yy * d.w + xx] != 0 { x0 = min(x0, xx); x1 = max(x1, xx); y0 = min(y0, yy); y1 = max(y1, yy) } }
        guard x1 >= 0 else { return nil }
        if x0 == 0 && y0 == 0 && x1 == d.w - 1 && y1 == d.h - 1 { say("That area is the whole canvas: tap inside a closed shape."); return nil }
        return (m, CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))
    }

    func toggleEcho(_ on: Bool? = nil) {
        echoOn = on ?? !echoOn
        if echoOn { lightOneOn = false; nodeOn = false; say("Echo Fill: tap inside a closed shape.") }
    }
    func toggleLightOne(_ on: Bool? = nil) {
        lightOneOn = on ?? !lightOneOn
        if lightOneOn { echoOn = false; nodeOn = false; say("Light one: tap inside a closed shape.") }
    }
    func toggleLightsOff() {
        lightsOff.toggle()
        say(lightsOff ? "Lights off: only glowing layers show. Turn them on in the Layers list (Glow)." : "Lights on.")
    }

    func echoFill(at p: CGPoint) {
        guard live == nil, !trActive, let d = doc else { return }
        let L = d.layers[d.active]
        guard d.isShown(L) else { say("This layer is hidden."); return }
        guard let (m, region) = shapeUnder(p) else { return }
        let pad = 3
        let bx = max(0, Int(region.minX) - pad), by = max(0, Int(region.minY) - pad)
        let bw = min(d.w, Int(region.maxX) + pad) - bx, bh = min(d.h, Int(region.maxY) + pad) - by
        guard bw >= 6, bh >= 6 else { say("Tap inside a closed shape."); return }
        var inside = [Bool](repeating: false, count: bw * bh)
        for yy in 0..<bh { for xx in 0..<bw { inside[yy * bw + xx] = m[(by + yy) * d.w + bx + xx] != 0 } }
        let dist = NativeEDT.distance(inside, bw, bh)
        let a = NativeEDT.alpha(dist, first: echo.first, step: echo.step, lw: echo.weight, count: Int(echo.count))
        let px = L.pixels
        let box = CGRect(x: bx, y: by, width: bw, height: bh)
        var before: [TileKey: Data] = [:]
        for k in px.tiles(in: box) { before[k] = px.tilePixels(tx: k.tx, ty: k.ty) }
        let c = UIColor(color).rgb
        let sel = selection?.has == true ? selection?.mask : nil
        for yy in 0..<bh { for xx in 0..<bw {
            var w = Double(a[yy * bw + xx]) / 255
            if w <= 0 { continue }
            let i = ((by + yy) * d.w + bx + xx) * 4
            if let sel { w *= Double(sel.ptr[i + 3]) / 255; if w <= 0 { continue } }
            let dstA = Double(px.ptr[i + 3]) / 255
            if L.alphaLock {   // source-atop: only where the layer already has ink, and its alpha stays
                if dstA <= 0 { continue }
                px.ptr[i] = UInt8(max(0, min(255, c.0 * 255 * dstA * w + Double(px.ptr[i]) * (1 - w))))
                px.ptr[i + 1] = UInt8(max(0, min(255, c.1 * 255 * dstA * w + Double(px.ptr[i + 1]) * (1 - w))))
                px.ptr[i + 2] = UInt8(max(0, min(255, c.2 * 255 * dstA * w + Double(px.ptr[i + 2]) * (1 - w))))
            } else {
                px.ptr[i] = UInt8(max(0, min(255, c.0 * 255 * w + Double(px.ptr[i]) * (1 - w))))
                px.ptr[i + 1] = UInt8(max(0, min(255, c.1 * 255 * w + Double(px.ptr[i + 1]) * (1 - w))))
                px.ptr[i + 2] = UInt8(max(0, min(255, c.2 * 255 * w + Double(px.ptr[i + 2]) * (1 - w))))
                px.ptr[i + 3] = UInt8(max(0, min(255, 255 * w + Double(px.ptr[i + 3]) * (1 - w))))
            }
        } }
        L.meta["raw"] = true
        let tiles = before.keys.sorted { ($0.ty, $0.tx) < ($1.ty, $1.tx) }.map { k in (k, before[k]!, px.tilePixels(tx: k.tx, ty: k.ty)) }
        pushTiles(px, tiles, label: "Echo Fill", layer: d.active)
        stage?.refresh(active: d.active, wetOpacity: 0)
        syncFlags(); markChanged()
        say("Echo Fill: \(Int(echo.count)) lines at most, every \(Int(echo.step)) px.")
    }

    /// One region becomes the lit cell: a new layer above, filled, glowing; nothing else changes.
    func lightOne(at p: CGPoint) {
        guard live == nil, !trActive, let d = doc else { return }
        guard let (m, _) = shapeUnder(p) else { return }
        let c = UIColor(color).rgb
        structDo("Light one") {
            guard d.layers.count < 40, let px = PixelBuffer(w: d.w, h: d.h) else { say("This phone holds no more layers at this size."); return false }
            let r = UInt8(c.0 * 255), g = UInt8(c.1 * 255), b = UInt8(c.2 * 255)
            for i in 0..<(d.w * d.h) where m[i] != 0 { px.ptr[i * 4] = r; px.ptr[i * 4 + 1] = g; px.ptr[i * 4 + 2] = b; px.ptr[i * 4 + 3] = 255 }
            var meta = NativeLayer.defaultMeta("Lit cell")
            meta["grp"] = d.layers[d.active].meta["grp"] as? Int ?? 0; meta["id"] = d.freshLayerID(); meta["glow"] = 1.0; meta["raw"] = true
            d.layers.insert(NativeLayer(meta: meta, maskPx: nil, pixels: px), at: d.active + 1); d.active += 1
            return true
        }
        lightOneOn = false
        say("The lit cell: it glows. Turn Lights off to see it carry the piece.")
    }

    /// The same marks on the other ground: cream to black and back, the channel shows through.
    func otherGround() {
        guard let d = doc else { return }
        func lum(_ hex: String) -> Double { Hex.rgb(hex).map { $0.0 * 0.299 + $0.1 * 0.587 + $0.2 * 0.114 } ?? 1 }
        let old = (bg: d.bg, vis: d.bgVis), dark = lum(d.bg) < 0.45 && d.bgVis
        if bgAlt == nil { bgAlt = dark ? "#efe9dc" : "#0e0c08" }
        let next = bgAlt ?? "#efe9dc"
        bgAlt = old.vis ? old.bg : (dark ? "#efe9dc" : "#0e0c08")
        d.bg = next; d.bgVis = true
        stage?.rebuild()
        record("Other ground", undo: { [weak self] in d.bg = old.bg; d.bgVis = old.vis; self?.stage?.rebuild() },
               redo: { [weak self] in d.bg = next; d.bgVis = true; self?.stage?.rebuild() })
        say("The same marks on the other ground.")
    }
}

/// The bar while Echo Fill is on: the four numbers it takes.
struct NativeEchoBar: View {
    @Bindable var canvas: NativeCanvasModel
    var body: some View {
        VStack(spacing: 6) {
            HStack { Image(systemName: "circle.dashed.inset.filled"); Text("Echo Fill: tap inside a closed shape").font(.footnote); Spacer(); Button("Done") { canvas.toggleEcho(false) }.buttonStyle(.borderedProminent).controlSize(.small) }
            row("Spacing", $canvas.echo.step, 3...60)
            row("Line weight", $canvas.echo.weight, 1...20)
            row("Lines", $canvas.echo.count, 1...100)
            row("Start inside", $canvas.echo.first, 0...60)
        }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    private func row(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        HStack { Text(t).font(.caption).frame(width: 86, alignment: .leading); Slider(value: v, in: r, step: 1); Text("\(Int(v.wrappedValue))").font(.caption.monospacedDigit()).frame(width: 30) }
    }
}
