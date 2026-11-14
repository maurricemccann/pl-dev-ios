import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// Lift: the ink off a photo of a physical piece, onto a transparent layer with the edge kept as drawn (port of `lift.js`). Ink = how much
/// darker than the paper; the paper is found per 16 px block (the lightest part of each, smoothed) so a shadow across the photo is not ink.
@MainActor enum NativeLift {
    struct Options { var thr = 0.16, soft = 0.14, gain = 1.35, specks = 40.0, invert = false, colours = true, fit = true }

    private static func lum(_ p: UnsafeMutablePointer<UInt8>, _ i: Int) -> Double { Double(p[i]) * 0.299 + Double(p[i + 1]) * 0.587 + Double(p[i + 2]) * 0.114 }

    private struct Paper {
        var g: [Float]; let gw: Int, gh: Int, B: Int
        func at(_ x: Double, _ y: Double) -> Double {
            let fx = min(Double(gw) - 1.001, max(0, x / Double(B) - 0.5)), fy = min(Double(gh) - 1.001, max(0, y / Double(B) - 0.5))
            let x0 = Int(fx), y0 = Int(fy), tx = fx - Double(x0), ty = fy - Double(y0)
            func v(_ xx: Int, _ yy: Int) -> Double { Double(g[yy * gw + xx]) }
            return (v(x0, y0) * (1 - tx) + v(x0 + 1, y0) * tx) * (1 - ty) + (v(x0, y0 + 1) * (1 - tx) + v(x0 + 1, y0 + 1) * tx) * ty
        }
    }

    private static func paperField(_ src: PixelBuffer, invert: Bool) -> Paper {
        let w = src.w, h = src.h, p = src.ptr, B = 16, gw = max(2, Int(ceil(Double(w) / Double(B)))), gh = max(2, Int(ceil(Double(h) / Double(B))))
        var g = [Float](repeating: 0, count: gw * gh)
        for by in 0..<gh { for bx in 0..<gw {
            var vals: [Double] = []
            var y = by * B
            while y < min(h, by * B + B) { var x = bx * B; while x < min(w, bx * B + B) { vals.append(lum(p, (y * w + x) * 4)); x += 2 }; y += 2 }
            if vals.isEmpty { g[by * gw + bx] = invert ? 0 : 255; continue }
            vals.sort()
            g[by * gw + bx] = Float(invert ? vals[Int(Double(vals.count) * 0.1)] : vals[min(vals.count - 1, Int(Double(vals.count) * 0.9))])
        } }
        for _ in 0..<2 {
            let c = g
            for y in 0..<gh { for x in 0..<gw {
                var s: Float = 0, n: Float = 0
                for dy in -1...1 { for dx in -1...1 { let xx = x + dx, yy = y + dy; if xx < 0 || yy < 0 || xx >= gw || yy >= gh { continue }; s += c[yy * gw + xx]; n += 1 } }
                g[y * gw + x] = s / n
            } }
        }
        return Paper(g: g, gw: gw, gh: gh, B: B)
    }

    /// `src` holds the photo (opaque); the result is the ink alone, premultiplied, in its own colours or in `colour`.
    static func process(_ src: PixelBuffer, _ o: Options, colour: (Double, Double, Double), specks: Double? = nil) -> PixelBuffer? {
        let w = src.w, h = src.h, d = src.ptr
        guard let out = PixelBuffer(w: w, h: h) else { return nil }
        let P = paperField(src, invert: o.invert), thr = o.thr, soft = max(0.01, o.soft)
        var a = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4, L = lum(d, i), bg = P.at(Double(x), Double(y))
            var k = o.invert ? (L - bg) / max(30, 255 - bg) : (bg - L) / max(30, bg)
            k = max(0, k * o.gain)
            let t = max(0, min(1, (k - thr) / soft))
            a[y * w + x] = UInt8((t * t * (3 - 2 * t) * 255).rounded())
        } }
        let minBlob = Int(specks ?? o.specks)
        if minBlob > 0 {   // little blobs are dust, not ink
            var seen = [Bool](repeating: false, count: w * h)
            for s0 in 0..<(w * h) {
                if seen[s0] || a[s0] < 40 { continue }
                var stack = [s0], comp = [s0]; seen[s0] = true
                while let p = stack.popLast() {
                    let x = p % w
                    for q in [p - 1, p + 1, p - w, p + w] {
                        if q < 0 || q >= w * h || seen[q] || a[q] < 40 { continue }
                        if (q == p - 1 && x == 0) || (q == p + 1 && x == w - 1) { continue }
                        seen[q] = true; stack.append(q); comp.append(q)
                    }
                }
                if comp.count < minBlob { for q in comp { a[q] = 0 } }
            }
        }
        let o4 = out.ptr
        for i in 0..<(w * h) {
            let j = i * 4, al = Double(a[i]) / 255
            if al == 0 { continue }
            if o.colours { o4[j] = UInt8((Double(d[j]) * al).rounded()); o4[j + 1] = UInt8((Double(d[j + 1]) * al).rounded()); o4[j + 2] = UInt8((Double(d[j + 2]) * al).rounded()) }
            else { o4[j] = UInt8((colour.0 * 255 * al).rounded()); o4[j + 1] = UInt8((colour.1 * 255 * al).rounded()); o4[j + 2] = UInt8((colour.2 * 255 * al).rounded()) }
            o4[j + 3] = a[i]
        }
        return out
    }

    /// A photo drawn into a buffer of the size it will be lifted at (the longest side is cut to `maxSide`).
    static func buffer(from img: UIImage, maxSide: Double) -> PixelBuffer? {
        guard let cg = (img.imageOrientation == .up ? img.cgImage : redraw(img)) else { return nil }
        let k = min(1, maxSide / Double(max(cg.width, cg.height)))
        let w = max(8, Int((Double(cg.width) * k).rounded())), h = max(8, Int((Double(cg.height) * k).rounded()))
        guard let b = PixelBuffer(w: w, h: h) else { return nil }
        b.ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); b.ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        b.drawUpright(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return b
    }
    /// The pixels as the eye sees the photo (the camera's turn applied).
    static func redraw(_ img: UIImage) -> CGImage? {
        let r = UIGraphicsImageRenderer(size: img.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.image { _ in img.draw(at: .zero) }.cgImage
    }
}

extension NativeCanvasModel {
    /// A picture on a new layer above the active one, centred, shrunk to fit if it is larger than the canvas. One undo step.
    func addPictureLayer(_ img: CGImage, name: String, fit: Bool = true) {
        guard live == nil, let d = doc else { return }
        commitTransform()
        guard d.addLayer() else { say(d.fullNote); return }
        let N = d.layers[d.active]
        N.meta["name"] = name; N.meta["raw"] = true
        let k = fit ? min(1, min(Double(d.w) / Double(img.width), Double(d.h) / Double(img.height))) : 1
        let pw = Double(img.width) * k, ph = Double(img.height) * k
        N.pixels.ctx.saveGState()
        N.pixels.ctx.translateBy(x: (Double(d.w) - pw) / 2, y: (Double(d.h) - ph) / 2 + ph); N.pixels.ctx.scaleBy(x: 1, y: -1)
        N.pixels.ctx.draw(img, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        N.pixels.ctx.restoreGState()
        recordAdded(N, at: d.active, label: name)
        enterTransform()
        say("\(name) is on its own layer: move it, then Done.")
    }
}

struct NativeLiftSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var small: PixelBuffer?
    @State private var o = NativeLift.Options()
    @State private var preview: UIImage?
    @State private var busy = false
    @State private var failed: String?
    @State private var job: Task<Void, Never>?

    private var ink: (Double, Double, Double) { UIColor(canvas.color).rgb }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $item, matching: .images) { Label(photo == nil ? "Choose a photo of the piece" : "Choose another photo", systemImage: "photo.on.rectangle") }
                    if photo != nil {
                        ZStack { NativeChecker(); if let preview { Image(uiImage: preview).resizable().scaledToFit() } else { PLLoader() } }
                            .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } footer: { Text("Lifts the ink off the paper onto a layer of its own. The edge stays as drawn.") }
                if photo != nil {
                    Section {
                        slider("Threshold", $o.thr, 0...0.8, 0.01)
                        slider("Softness", $o.soft, 0.02...0.6, 0.01)
                        slider("Gain", $o.gain, 0.5...3, 0.05)
                        slider("Remove specks", $o.specks, 0...400, 2)
                        Toggle("Light ink on dark paper", isOn: $o.invert)
                        Toggle("Keep the ink's own colours", isOn: $o.colours)
                    } header: { Text("How much counts as ink") } footer: { Text(o.colours ? "" : "Off: the ink takes your current colour.") }
                    Section { Toggle("Fit to the canvas", isOn: $o.fit) }
                }
                if let failed { Section { Text(failed).foregroundStyle(.red) } }
            }
            .navigationTitle("Lift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "Lifting…" : "Lift the ink") { Task { await apply() } }.disabled(photo == nil || busy) }
            }
            .onChange(of: item) { _, it in Task { await load(it) } }
            .onChange(of: o.thr) { _, _ in refresh() }
            .onChange(of: o.soft) { _, _ in refresh() }
            .onChange(of: o.gain) { _, _ in refresh() }
            .onChange(of: o.specks) { _, _ in refresh() }
            .onChange(of: o.invert) { _, _ in refresh() }
            .onChange(of: o.colours) { _, _ in refresh() }
        }
    }

    private func slider(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ step: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(t); Spacer(); Text(String(format: step < 1 ? "%.2f" : "%.0f", v.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: v, in: r, step: step)
        }
    }

    private func load(_ it: PhotosPickerItem?) async {
        guard let it else { return }
        failed = nil
        guard let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) else { failed = "That picture did not open."; return }
        photo = img
        small = NativeLift.buffer(from: img, maxSide: 480)
        refresh()
    }

    private func refresh() {
        job?.cancel()
        job = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let s = small else { return }
            let sp = o.specks * 0.18
            if let out = NativeLift.process(s, o, colour: ink, specks: sp), let img = out.image() { preview = UIImage(cgImage: img) }
        }
    }

    private func apply() async {
        guard let d = canvas.doc, let photo else { return }
        busy = true; defer { busy = false }
        await Task.yield()
        let longest = Double(max(photo.size.width * photo.scale, photo.size.height * photo.scale))
        var side = o.fit ? min(longest, Double(max(d.w, d.h))) : longest
        // the lifted picture must stay within what a layer can hold
        while side > 64, Int((photo.size.width * photo.scale) * side / longest) * Int((photo.size.height * photo.scale) * side / longest) > 12_000_000 { side *= 0.9 }
        guard let big = NativeLift.buffer(from: photo, maxSide: side) else { failed = "That picture is too large to lift at this size. Turn on Fit to the canvas."; return }
        guard let out = NativeLift.process(big, o, colour: ink), let img = out.image() else { failed = "The ink could not be lifted."; return }
        canvas.addPictureLayer(img, name: "Lifted ink", fit: o.fit)
        dismiss()
    }
}
