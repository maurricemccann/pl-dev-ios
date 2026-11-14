import CoreGraphics
import CoreImage
import Foundation
import SwiftUI
import UIKit

/// Adjustments and filters: the port of `adjust.js`. Each one takes the active layer and returns the layer with the effect, and at its
/// defaults changes nothing. The sheet previews on a small copy of the layer and applies to the full one (inside the selection if there
/// is one, keeping the shape if the layer is alpha-locked), as one undo step.
@MainActor enum NativeAdjust {
    struct Param: Identifiable {
        let key: String; let label: String
        var lo = 0.0, hi = 1.0, step = 1.0, def = 0.0
        var options: [String] = []
        var palettes = false
        var id: String { key }
        var isChoice: Bool { palettes || !options.isEmpty }
        var defText: String { palettes ? "0" : (options.first ?? "") }
    }
    struct Def: Identifiable { let id: String; let group: String; let name: String; let params: [Param] }
    struct Values {
        var n: [String: Double] = [:]
        var s: [String: String] = [:]
        init(_ d: Def) { for p in d.params { if p.isChoice { s[p.key] = p.defText } else { n[p.key] = p.def } } }
        func num(_ k: String) -> Double { n[k] ?? 0 }
        func str(_ k: String) -> String { s[k] ?? "" }
    }

    private static func num(_ k: String, _ l: String, _ lo: Double, _ hi: Double, _ def: Double = 0, step: Double = 1) -> Param { Param(key: k, label: l, lo: lo, hi: hi, step: step, def: def) }
    private static func pick(_ k: String, _ l: String, _ opts: [String], def: String) -> Param {
        var o = opts; if let i = o.firstIndex(of: def) { o.remove(at: i); o.insert(def, at: 0) }
        return Param(key: k, label: l, options: o)
    }

    static let defs: [Def] = [
        Def(id: "hsb", group: "Adjustments", name: "Hue, Saturation, Brightness", params: [num("hue", "Hue", -180, 180), num("sat", "Saturation", -100, 100), num("bri", "Brightness", -100, 100)]),
        Def(id: "balance", group: "Adjustments", name: "Colour Balance", params: [pick("range", "Tones", ["shadows", "midtones", "highlights"], def: "midtones"), num("cr", "Cyan - Red", -100, 100), num("mg", "Magenta - Green", -100, 100), num("yb", "Yellow - Blue", -100, 100)]),
        Def(id: "curves", group: "Adjustments", name: "Curves", params: [pick("channel", "Channel", ["all", "red", "green", "blue"], def: "all"), num("gamma", "Gamma", 0.3, 3, 1, step: 0.01), num("contrast", "Contrast", -100, 100)]),
        Def(id: "gradmap", group: "Adjustments", name: "Gradient Map", params: [Param(key: "palette", label: "Gradient", palettes: true), num("amount", "Strength", 0, 100)]),
        Def(id: "blur", group: "Effects", name: "Gaussian Blur", params: [num("radius", "Radius", 0, 60, 0, step: 0.5)]),
        Def(id: "motion", group: "Effects", name: "Motion Blur", params: [num("angle", "Angle", 0, 180), num("dist", "Distance", 0, 160)]),
        Def(id: "noise", group: "Effects", name: "Noise", params: [num("amount", "Amount", 0, 100), pick("mono", "Colour", ["colour", "grey"], def: "grey")]),
        Def(id: "sharpen", group: "Effects", name: "Sharpen", params: [num("amount", "Amount", 0, 200)]),
        Def(id: "bloom", group: "Effects", name: "Bloom", params: [num("size", "Size", 2, 80, 20), num("amount", "Strength", 0, 100)]),
        Def(id: "halftone", group: "Effects", name: "Halftone", params: [num("size", "Dot size", 4, 40, 12), pick("mode", "Style", ["newspaper", "colour"], def: "newspaper"), num("amount", "Strength", 0, 100)]),
        Def(id: "chroma", group: "Effects", name: "Chromatic Aberration", params: [num("shift", "Shift", 0, 30)]),
    ]

    // MARK: pixels

    static func copy(_ src: PixelBuffer) -> PixelBuffer? {
        guard let o = PixelBuffer(w: src.w, h: src.h) else { return nil }
        memcpy(o.ptr, src.ptr, src.w * src.h * 4); return o
    }

    /// Runs `fn` on every pixel that has alpha, in straight (not premultiplied) 0...255 colour, and writes the result back premultiplied.
    private static func mapPixels(_ src: PixelBuffer, _ fn: (inout Double, inout Double, inout Double) -> Void) -> PixelBuffer? {
        guard let o = copy(src) else { return nil }
        let p = o.ptr
        for i in 0..<(o.w * o.h) {
            let j = i * 4, a = Int(p[j + 3]); if a == 0 { continue }
            let k = 255.0 / Double(a)
            var r = Double(p[j]) * k, g = Double(p[j + 1]) * k, b = Double(p[j + 2]) * k
            fn(&r, &g, &b)
            let f = Double(a) / 255
            p[j] = UInt8(max(0, min(255, (r * f).rounded()))); p[j + 1] = UInt8(max(0, min(255, (g * f).rounded()))); p[j + 2] = UInt8(max(0, min(255, (b * f).rounded())))
        }
        return o
    }

    private static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }
    private static func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { (0.299 * r + 0.587 * g + 0.114 * b) / 255 }

    static func rgb2hsv(_ r0: Double, _ g0: Double, _ b0: Double) -> (Double, Double, Double) {
        let r = r0 / 255, g = g0 / 255, b = b0 / 255, mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d != 0 { h = mx == r ? ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) : (mx == g ? (b - r) / d + 2 : (r - g) / d + 4) }
        return (h * 60, mx != 0 ? d / mx : 0, mx)
    }
    static func hsv2rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        func f(_ n: Double) -> Double { let k = (n + h / 60).truncatingRemainder(dividingBy: 6); return v - v * s * max(0, min(k, 4 - k, 1)) }
        return (f(5) * 255, f(3) * 255, f(1) * 255)
    }

    /// A Gaussian blur with the canvas filter's meaning of the number (it is the standard deviation, in pixels).
    static func gauss(_ src: PixelBuffer, _ sigma: Double) -> PixelBuffer? {
        guard sigma > 0, let img = src.image(), let o = PixelBuffer(w: src.w, h: src.h) else { return copy(src) }
        let rect = CGRect(x: 0, y: 0, width: src.w, height: src.h)
        let c = CIImage(cgImage: img).applyingGaussianBlur(sigma: sigma).cropped(to: rect)
        guard let out = NativeEffects.ci.createCGImage(c, from: rect) else { return copy(src) }
        o.drawUpright(out, in: rect)
        return o
    }

    /// `k` is the preview's scale (1 on the full layer), so a radius of 20 px looks the same on a small copy.
    static func run(_ d: Def, _ v: Values, on src: PixelBuffer, k: Double = 1) -> PixelBuffer? {
        let w = src.w, h = src.h
        switch d.id {
        case "hsb":
            let hue = v.num("hue"), sat = v.num("sat"), bri = v.num("bri")
            return mapPixels(src) { r, g, b in
                var (H, S, V) = rgb2hsv(r, g, b)
                H = (H + hue + 360).truncatingRemainder(dividingBy: 360); S = clamp(S * (1 + sat / 100), 0, 1); V = clamp(V + bri / 100, 0, 1)
                (r, g, b) = hsv2rgb(H, S, V)
            }
        case "balance":
            let range = v.str("range"), cr = v.num("cr"), mg = v.num("mg"), yb = v.num("yb")
            return mapPixels(src) { r, g, b in
                let l = lum(r, g, b)
                let wt = range == "shadows" ? (1 - l) * (1 - l) : (range == "highlights" ? l * l : 4 * l * (1 - l))
                r = clamp(r + cr * wt * 1.4, 0, 255); g = clamp(g + mg * wt * 1.4, 0, 255); b = clamp(b + yb * wt * 1.4, 0, 255)
            }
        case "curves":
            let gamma = max(0.05, v.num("gamma")), contrast = v.num("contrast"), ch = v.str("channel")
            let lut = (0..<256).map { i -> Double in
                var x = pow(Double(i) / 255, 1 / gamma); x = (x - 0.5) * (1 + contrast / 100 * 1.5) + 0.5
                return clamp(x, 0, 1) * 255
            }
            return mapPixels(src) { r, g, b in
                if ch == "all" || ch == "red" { r = lut[Int(clamp(r, 0, 255))] }
                if ch == "all" || ch == "green" { g = lut[Int(clamp(g, 0, 255))] }
                if ch == "all" || ch == "blue" { b = lut[Int(clamp(b, 0, 255))] }
            }
        case "gradmap":
            let pals = NativeToolkit.palettes, idx = Int(v.str("palette")) ?? 0
            let cols = (pals.indices.contains(idx) ? pals[idx].colors : (pals.first?.colors ?? ["#000000", "#ffffff"]))
                .compactMap { Hex.rgb($0) }.map { ($0.0 * 255, $0.1 * 255, $0.2 * 255) }.sorted { lum($0.0, $0.1, $0.2) < lum($1.0, $1.1, $1.2) }
            let amt = v.num("amount") / 100
            guard cols.count >= 2 else { return copy(src) }
            return mapPixels(src) { r, g, b in
                let t = lum(r, g, b) * Double(cols.count - 1), kk = min(cols.count - 2, Int(floor(t))), f = t - Double(kk), c0 = cols[kk], c1 = cols[kk + 1]
                r = r * (1 - amt) + (c0.0 + (c1.0 - c0.0) * f) * amt
                g = g * (1 - amt) + (c0.1 + (c1.1 - c0.1) * f) * amt
                b = b * (1 - amt) + (c0.2 + (c1.2 - c0.2) * f) * amt
            }
        case "blur":
            let r = v.num("radius") * k
            return r > 0 ? gauss(src, r) : copy(src)
        case "motion":
            let dist = v.num("dist") * k
            guard dist > 0, let o = PixelBuffer(w: w, h: h), let img = src.image() else { return copy(src) }
            let a = v.num("angle") * .pi / 180, n = 16
            for i in 0..<n {
                let off = (Double(i) / Double(n - 1) - 0.5) * dist
                NativeEffects.put(img, into: o, x: cos(a) * off, y: sin(a) * off, alpha: 1 / Double(i + 1))
            }
            return o
        case "noise":
            let amp = v.num("amount") * 2.55, grey = v.str("mono") == "grey"
            var seed = 99991.0
            func rnd() -> Double { seed = (seed * 16807).truncatingRemainder(dividingBy: 2147483647); return seed / 2147483647 }
            guard amp > 0 else { return copy(src) }
            return mapPixels(src) { r, g, b in
                if grey { let n = (rnd() - 0.5) * 2 * amp; r = clamp(r + n, 0, 255); g = clamp(g + n, 0, 255); b = clamp(b + n, 0, 255) }
                else { r = clamp(r + (rnd() - 0.5) * 2 * amp, 0, 255); g = clamp(g + (rnd() - 0.5) * 2 * amp, 0, 255); b = clamp(b + (rnd() - 0.5) * 2 * amp, 0, 255) }
            }
        case "sharpen":
            let amount = v.num("amount")
            guard amount > 0, let bl = gauss(src, 1.6 * k), let o = copy(src) else { return copy(src) }
            let kk = amount / 100, p = o.ptr, q = bl.ptr
            for i in 0..<(w * h) {
                let j = i * 4, a = Int(p[j + 3]); if a == 0 { continue }
                let f = 255.0 / Double(a), qa = Int(q[j + 3])
                let g = qa == 0 ? 0.0 : 255.0 / Double(qa)
                for c in 0..<3 {
                    let s = Double(p[j + c]) * f, bv = Double(q[j + c]) * g
                    p[j + c] = UInt8(max(0, min(255, ((s + (s - bv) * kk) * Double(a) / 255).rounded())))
                }
            }
            return o
        case "bloom":
            let amount = v.num("amount")
            guard amount > 0, let o = copy(src), let bl = gauss(src, v.num("size") * k), let img = bl.image() else { return copy(src) }
            NativeEffects.put(img, into: o, x: 0, y: 0, alpha: amount / 100, blend: .screen)
            return o
        case "halftone":
            let amount = v.num("amount"), size = max(2, v.num("size") * k)
            guard amount > 0, let img = src.image(), let o = copy(src) else { return copy(src) }
            let sw = Int(ceil(Double(w) / size)), sh = Int(ceil(Double(h) / size))
            guard let sm = PixelBuffer(w: sw, h: sh), let ht = PixelBuffer(w: w, h: h) else { return o }
            sm.ctx.interpolationQuality = .high
            sm.drawUpright(img, in: CGRect(x: 0, y: 0, width: sw, height: sh))
            let colour = v.str("mode") == "colour"
            for cy in 0..<sh { for cx in 0..<sw {
                let i = (cy * sw + cx) * 4, a = Double(sm.ptr[i + 3]) / 255
                if a < 0.05 { continue }
                let f = 255.0 / Double(sm.ptr[i + 3])
                let r = Double(sm.ptr[i]) * f, g = Double(sm.ptr[i + 1]) * f, b = Double(sm.ptr[i + 2]) * f
                let rad = max(0.3, sqrt(1 - lum(r, g, b)) * size * 0.72)
                ht.ctx.setFillColor(colour ? CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a) : CGColor(red: 0, green: 0, blue: 0, alpha: a))
                ht.ctx.fillEllipse(in: CGRect(x: Double(cx) * size + size / 2 - rad, y: Double(cy) * size + size / 2 - rad, width: rad * 2, height: rad * 2))
            } }
            if let hi = ht.image() { NativeEffects.put(hi, into: o, x: 0, y: 0, alpha: amount / 100) }
            return o
        case "chroma":
            let s = Int((v.num("shift") * k).rounded())
            guard s > 0, let o = copy(src) else { return copy(src) }
            let sp = src.ptr, p = o.ptr
            func straight(_ i: Int, _ c: Int) -> Double { let a = Double(sp[i + 3]); return a == 0 ? 0 : Double(sp[i + c]) * 255 / a }
            for y in 0..<h { for x in 0..<w {
                let i = (y * w + x) * 4, xr = min(w - 1, x + s), xb = max(0, x - s), ir = (y * w + xr) * 4, ib = (y * w + xb) * 4
                let a = max(Int(sp[i + 3]), max(Int(sp[ir + 3]), Int(sp[ib + 3])))
                let r = straight(ir, 0), g = straight(i, 1), b = straight(ib, 2), f = Double(a) / 255
                p[i] = UInt8(max(0, min(255, (r * f).rounded()))); p[i + 1] = UInt8(max(0, min(255, (g * f).rounded()))); p[i + 2] = UInt8(max(0, min(255, (b * f).rounded()))); p[i + 3] = UInt8(a)
            } }
            return o
        default: return copy(src)
        }
    }
}

extension NativeCanvasModel {
    /// Puts an adjusted copy of the active layer back: inside the selection if there is one, keeping the layer's shape if it is alpha-locked.
    func applyAdjust(_ def: NativeAdjust.Def, _ v: NativeAdjust.Values) {
        guard live == nil, let d = doc, d.layers.indices.contains(d.active) else { return }
        let L = d.layers[d.active]
        let sel = (selection?.has == true) ? selection : nil
        structDo(def.name, pixels: [L]) {
            guard let out = NativeAdjust.run(def, v, on: L.pixels) else { return false }
            let base = L.pixels.ptr, o = out.ptr, lock = L.alphaLock, sm = sel?.mask.ptr
            for i in 0..<(d.w * d.h) {
                let j = i * 4
                var r = Double(o[j]), g = Double(o[j + 1]), b = Double(o[j + 2]), a = Double(o[j + 3])
                if lock {
                    let ba = Double(base[j + 3])
                    if a > 0 { let k = ba / a; r *= k; g *= k; b *= k } else { r = 0; g = 0; b = 0 }
                    a = ba
                }
                if let sm {
                    let s = Double(sm[j + 3]) / 255
                    if s < 1 { r = Double(base[j]) * (1 - s) + r * s; g = Double(base[j + 1]) * (1 - s) + g * s; b = Double(base[j + 2]) * (1 - s) + b * s; a = Double(base[j + 3]) * (1 - s) + a * s }
                }
                base[j] = UInt8(max(0, min(255, r.rounded()))); base[j + 1] = UInt8(max(0, min(255, g.rounded()))); base[j + 2] = UInt8(max(0, min(255, b.rounded()))); base[j + 3] = UInt8(max(0, min(255, a.rounded())))
            }
            return true
        }
        stage?.refreshAll()
        say("\(def.name) applied.")
    }
}

struct NativeAdjustSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var def = NativeAdjust.defs[0]
    @State private var values = NativeAdjust.Values(NativeAdjust.defs[0])
    @State private var small: PixelBuffer?
    @State private var scale = 1.0
    @State private var preview: UIImage?
    @State private var job: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        NativeChecker()
                        if let preview { Image(uiImage: preview).resizable().scaledToFit() } else { PLLoader() }
                    }
                    .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: { Text(canvas.hasSelection ? "Applies inside the selection." : "Applies to the whole layer.") }
                Section("Effect") {
                    Picker("Effect", selection: $def) {
                        ForEach(["Adjustments", "Effects"], id: \.self) { g in
                            Section(g) { ForEach(NativeAdjust.defs.filter { $0.group == g }) { Text($0.name).tag($0) } }
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: def) { _, d in values = NativeAdjust.Values(d); refresh() }
                }
                Section(def.name) {
                    ForEach(def.params) { p in
                        if p.palettes {
                            Picker(p.label, selection: Binding(get: { Int(values.str(p.key)) ?? 0 }, set: { values.s[p.key] = String($0); refresh() })) {
                                ForEach(Array(NativeToolkit.palettes.enumerated()), id: \.offset) { Text($0.element.name).tag($0.offset) }
                            }
                        } else if p.isChoice {
                            Picker(p.label, selection: Binding(get: { values.str(p.key) }, set: { values.s[p.key] = $0; refresh() })) {
                                ForEach(p.options, id: \.self) { Text($0.capitalized).tag($0) }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(p.label); Spacer(); Text(String(format: p.step < 1 ? "%.2f" : "%.0f", values.num(p.key))).foregroundStyle(.secondary).monospacedDigit() }
                                Slider(value: Binding(get: { values.num(p.key) }, set: { values.n[p.key] = $0; refresh() }), in: p.lo...p.hi, step: p.step)
                            }
                            .onTapGesture(count: 2) { values.n[p.key] = p.def; refresh() }
                        }
                    }
                    Button("Reset") { values = NativeAdjust.Values(def); refresh() }
                }
            }
            .navigationTitle("Adjustments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { canvas.applyAdjust(def, values); dismiss() } }
            }
            .task { prepare() }
        }
    }

    /// A small copy of the layer to preview on (at most 720 px on its long side).
    private func prepare() {
        guard let d = canvas.doc, d.layers.indices.contains(d.active), let img = d.layers[d.active].pixels.image() else { return }
        scale = min(1, 720 / Double(max(d.w, d.h)))
        let pw = max(8, Int(Double(d.w) * scale)), ph = max(8, Int(Double(d.h) * scale))
        if let s = PixelBuffer(w: pw, h: ph) { s.ctx.interpolationQuality = .high; s.drawUpright(img, in: CGRect(x: 0, y: 0, width: pw, height: ph)); small = s }
        refresh()
    }

    private func refresh() {
        job?.cancel()
        job = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, let s = small, let out = NativeAdjust.run(def, values, on: s, k: scale), let img = out.image() else { return }
            preview = UIImage(cgImage: img)
        }
    }
}

extension NativeAdjust.Def: Hashable {
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// The grey-and-white chequer that shows transparency.
struct NativeChecker: View {
    var body: some View {
        Canvas { c, size in
            let s: CGFloat = 12
            for y in 0..<Int(ceil(size.height / s)) { for x in 0..<Int(ceil(size.width / s)) {
                c.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)), with: .color((x + y) % 2 == 0 ? Color(white: 0.82) : Color(white: 0.95)))
            } }
        }
    }
}
