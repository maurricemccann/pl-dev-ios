import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Getting the picture out: PNG, JPEG, PSD with its layers, two kinds of SVG (each layer as an image, or the strokes as vector paths: ports of
/// `svg.js`), and the work file itself. Everything leaves through the share sheet, so Files, AirDrop, Photos and other apps all work.
@MainActor enum NativeExport {
    static func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmm"; return f.string(from: .now) }

    static func png(_ d: NativeDoc) -> Data? { d.flatPNG() }

    /// A one-page PDF at the picture's pixel size (a page point per pixel), the picture on its paper, transparent where the paper is hidden.
    static func pdf(_ d: NativeDoc) -> Data? {
        // Plain Core Graphics, no renderer closure: PDF export killed the app in every simulator run 11-14 (Export and Gallery share,
        // both right after the PDF tap) while PNG/JPEG/PSD passed; the UIKit renderer's actions closure was the one PDF-only piece.
        guard let png = d.flatPNG(), let img = UIImage(data: png)?.cgImage else { return nil }
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: d.w, height: d.h)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextCreator as String: "PL Paint"] as CFDictionary) else { return nil }
        ctx.beginPDFPage(nil); ctx.draw(img, in: box); ctx.endPDFPage(); ctx.closePDF()
        return out as Data
    }

    /// A JPEG has no transparency, so a hidden paper goes onto white.
    static func jpeg(_ d: NativeDoc) -> Data? {
        guard let flat = d.compositeBuffer(includeBackground: false), let out = PixelBuffer(w: d.w, h: d.h) else { return nil }
        out.ctx.setFillColor(d.bgVis ? (Hex.color(d.bg) ?? CGColor(gray: 1, alpha: 1)) : CGColor(gray: 1, alpha: 1)); out.ctx.fill(CGRect(x: 0, y: 0, width: d.w, height: d.h))
        if let img = flat.image() { out.drawUpright(img, in: CGRect(x: 0, y: 0, width: d.w, height: d.h)) }
        return out.image().flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.92) }
    }

    /// Straight (not premultiplied) RGBA of an image the size of the canvas.
    static func straight(_ img: CGImage, w: Int, h: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        for i in 0..<(w * h) {
            let a = Int(px[i * 4 + 3]); if a == 0 || a == 255 { continue }
            for c in 0..<3 { px[i * 4 + c] = UInt8(min(255, (Int(px[i * 4 + c]) * 255 + a / 2) / a)) }
        }
        return px
    }

    static func psd(_ d: NativeDoc) -> Data? {
        guard let flatBuf = d.compositeBuffer(includeBackground: false), let flatImg = flatBuf.image() else { return nil }
        // the merged preview other apps show, on white where the paper is hidden
        guard let onWhite = PixelBuffer(w: d.w, h: d.h) else { return nil }
        onWhite.ctx.setFillColor(CGColor(gray: 1, alpha: 1)); onWhite.ctx.fill(CGRect(x: 0, y: 0, width: d.w, height: d.h))
        if d.bgVis, let col = Hex.color(d.bg) { onWhite.ctx.setFillColor(col); onWhite.ctx.fill(CGRect(x: 0, y: 0, width: d.w, height: d.h)) }
        onWhite.drawUpright(flatImg, in: CGRect(x: 0, y: 0, width: d.w, height: d.h))
        guard let wi = onWhite.image() else { return nil }
        var items: [NativePSD.Item] = []
        if d.bgVis, let bg = PixelBuffer(w: d.w, h: d.h), let col = Hex.color(d.bg) {
            bg.ctx.setFillColor(col); bg.ctx.fill(CGRect(x: 0, y: 0, width: d.w, height: d.h))
            if let bi = bg.image() { items.append(.layer(name: "Background colour", vis: true, op: 1, blend: "source-over", rgba: straight(bi, w: d.w, h: d.h))) }
        }
        for (i, L) in d.layers.enumerated() {
            let g = d.groupID(i), first = g != 0 && (i == 0 || d.groupID(i - 1) != g), last = g != 0 && (i == d.layers.count - 1 || d.groupID(i + 1) != g)
            if first { items.append(.groupEnd) }
            if let img = d.effectiveImage(of: i) {   // masks and clipping are baked into the layer's pixels in a PSD
                items.append(.layer(name: L.name, vis: L.visible, op: L.opacity, blend: L.meta["blend"] as? String ?? "source-over", rgba: straight(img, w: d.w, h: d.h)))
            }
            if last, let gr = d.group(g) {
                let op = (gr["op"] as? Double) ?? Double(gr["op"] as? Int ?? 1)
                items.append(.groupStart(name: gr["name"] as? String ?? "Group", open: gr["open"] as? Bool ?? true, vis: gr["vis"] as? Bool ?? true, op: op, blend: gr["blend"] as? String ?? "source-over"))
            }
        }
        return NativePSD.write(w: d.w, h: d.h, items: items, flat: straight(wi, w: d.w, h: d.h))
    }

    // MARK: SVG

    private static func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    private static func r1(_ n: Double) -> String { String(format: "%.1f", (n * 10).rounded() / 10) }
    private static let cssBlend = Set(["multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion", "hue", "saturation", "color", "luminosity"])
    private static func svgHead(_ d: NativeDoc, _ note: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(d.w)\" height=\"\(d.h)\" viewBox=\"0 0 \(d.w) \(d.h)\">\n<desc>\(esc(note))</desc>\n"
            + (d.bgVis ? "<rect width=\"\(d.w)\" height=\"\(d.h)\" fill=\"\(esc(d.bg))\"/>\n" : "")
    }
    private static func svgGroup(_ d: NativeDoc, _ i: Int, _ inner: String) -> String {
        let L = d.layers[i], b = L.meta["blend"] as? String ?? "source-over"
        return "<g id=\"\(esc(L.name))\" inkscape:label=\"\(esc(L.name))\" opacity=\"\(d.shownOpacity(L))\" style=\"mix-blend-mode:\(cssBlend.contains(b) ? b : "normal")\"\(d.isShown(L) ? "" : " display=\"none\"")>\(inner)</g>\n"
    }

    static func svgLayers(_ d: NativeDoc) -> Data {
        var out = svgHead(d, "PL Paint. Each layer is an embedded image; transparent areas are transparent.")
        for i in d.layers.indices {
            var href = ""
            if let img = d.effectiveImage(of: i), let png = UIImage(cgImage: img).pngData() { href = "data:image/png;base64," + png.base64EncodedString() }
            out += svgGroup(d, i, "<image width=\"\(d.w)\" height=\"\(d.h)\" xlink:href=\"\(href)\"/>")
        }
        return Data((out + "</svg>\n").utf8)
    }

    private struct Opt { var caps = false, k = 1.0, pc = 0.8, line = 0.0, lineGap = 0.0, twinR = 0.0, twinGapPx = 0.0, scale = 1.0, side = 0.0, twin = 0.0, gap = 0.0, grow = 0.0 }

    /// A stroke as one filled polygon: its width follows pressure; round brushes get a dot at each end.
    private static func outline(_ pts: [(Double, Double, Double)], size: Double, ps: Double, _ o: Opt) -> String {
        var P: [(Double, Double, Double)] = []
        for q in pts { if let l = P.last, hypot(q.0 - l.0, q.1 - l.1) <= 0.8 { continue }; P.append(q) }
        func wAt(_ q: (Double, Double, Double)) -> Double { max(0.6, size * (1 - ps + ps * pow(max(0.05, q.2), o.pc))) / 2 }
        guard !P.isEmpty else { return "" }
        if P.count < 2 { let q = P[0]; return "<circle cx=\"\(r1(q.0))\" cy=\"\(r1(q.1))\" r=\"\(r1(wAt(q) * o.k * o.scale + o.grow))\"/>" }
        var L: [(Double, Double)] = [], R: [(Double, Double)] = []
        for i in P.indices {
            let a = P[max(0, i - 1)], b = P[min(P.count - 1, i + 1)]
            var dx = b.0 - a.0, dy = b.1 - a.1; let d = hypot(dx, dy); let dd = d == 0 ? 1 : d; dx /= dd; dy /= dd
            let rm = wAt(P[i])
            let lineShift = o.line != 0 ? o.line * (2 * rm + (o.twinR > 0 ? o.twinGapPx + 2 * rm * o.twinR : 0) + o.lineGap) : 0
            let shift = lineShift + (o.side != 0 ? o.side * (rm * (1 + o.twin) + o.gap) : 0), half = rm * o.k * o.scale + o.grow
            let cx = P[i].0 - dy * shift, cy = P[i].1 + dx * shift
            L.append((cx - dy * half, cy + dx * half)); R.append((cx + dy * half, cy - dx * half))
        }
        func pt(_ q: (Double, Double)) -> String { "\(r1(q.0)) \(r1(q.1))" }
        let n = L.count - 1
        var caps = ""
        if o.caps {
            let h0 = hypot(L[0].0 - R[0].0, L[0].1 - R[0].1) / 2, h1 = hypot(L[n].0 - R[n].0, L[n].1 - R[n].1) / 2
            caps = "<circle cx=\"\(r1((L[0].0 + R[0].0) / 2))\" cy=\"\(r1((L[0].1 + R[0].1) / 2))\" r=\"\(r1(h0))\"/><circle cx=\"\(r1((L[n].0 + R[n].0) / 2))\" cy=\"\(r1((L[n].1 + R[n].1) / 2))\" r=\"\(r1(h1))\"/>"
        }
        return "<path d=\"M\(L.map(pt).joined(separator: "L"))L\(R.reversed().map(pt).joined(separator: "L"))Z\"/>" + caps
    }

    /// The brush strokes as paths. Fills, filters, pasted images and transforms are pixel edits and are not in it.
    static func svgVector(_ d: NativeDoc) -> (data: Data, strokes: Int, skipped: Int) {
        var defs: [String] = [], body = "", nm = 0, used = 0, skipped = 0
        func cut(_ inner: String, _ shape: String, _ op: Double) -> String {
            nm += 1; let id = "m\(nm)"
            defs.append("<mask id=\"\(id)\" maskUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"\(d.w)\" height=\"\(d.h)\"><rect width=\"\(d.w)\" height=\"\(d.h)\" fill=\"#fff\"/><g fill=\"#000\" fill-opacity=\"\(op)\">\(shape)</g></mask>")
            return "<g mask=\"url(#\(id))\">\(inner)</g>"
        }
        func num(_ v: Any?) -> Double { (v as? Double) ?? Double(v as? Int ?? 0) }
        for (li, L) in d.layers.enumerated() {
            let lid = L.meta["id"] as? Int ?? (li + 1)
            var inner = ""
            for s in d.log {
                guard (s["layer"] as? Int) == lid, s["dead"] as? Bool != true, s["onMask"] as? Bool != true else { continue }
                let tool = s["tool"] as? String ?? "paint"
                guard tool != "smudge" else { skipped += 1; continue }
                guard let raw = s["pts"] as? [[Any]], !raw.isEmpty else { continue }
                let pts = raw.compactMap { r -> (Double, Double, Double)? in r.count >= 3 ? (num(r[0]), num(r[1]), num(r[2])) : nil }
                guard !pts.isEmpty else { continue }
                let bs = s["bs"] as? [String: Any] ?? [:], size = num(s["size"]), op = num(s["op"])
                let color = s["color"] as? String ?? "#000000", color2 = s["color2"] as? String
                let ps = num(bs["ps"]), twin = num(bs["twin"])
                let round = bs["round"] as? Bool ?? true, kk = num(bs["k"]) == 0 ? 1 : num(bs["k"]), pcRaw = num(bs["pc"]), pc = pcRaw == 0 ? 0.8 : pcRaw
                let N = max(1, Int(num(bs["lines"]).rounded()))
                var base = Opt(); base.caps = round; base.k = kk; base.pc = pc; base.lineGap = num(bs["lineGap"]) * size; base.twinR = twin; base.twinGapPx = num(bs["gap"]) * size
                var tw = base; let hasTwin = twin > 0 && color2 != nil
                if hasTwin { tw.scale = twin; tw.side = (bs["side"] as? String) == "left" ? -1 : 1; tw.twin = twin; tw.gap = num(bs["gap"]) * size }
                var plain = Opt(); plain.caps = round; plain.k = kk; plain.pc = pc
                let shape = outline(pts, size: size, ps: ps, plain)
                if shape.isEmpty { continue }
                used += 1
                if tool == "erase" { inner = cut(inner, shape, op); continue }
                let lines = (0..<N).map { Double($0) - Double(N - 1) / 2 }
                let ch = num(bs["ch"])
                if ch > 0 {
                    let g = ch * size
                    let halo = lines.map { l -> String in
                        var a = base; a.line = l; a.grow = g
                        var s2 = outline(pts, size: size, ps: ps, a)
                        if hasTwin { var b = tw; b.line = l; b.grow = g; s2 += outline(pts, size: size, ps: ps, b) }
                        return s2
                    }.joined()
                    inner = cut(inner, halo, 1)
                }
                for l in lines {
                    if hasTwin, let c2 = color2 { var b = tw; b.line = l; inner += "<g fill=\"\(esc(c2))\" fill-opacity=\"\(op)\">\(outline(pts, size: size, ps: ps, b))</g>" }
                    var a = base; a.line = l
                    inner += "<g fill=\"\(esc(color))\" fill-opacity=\"\(op)\">\(outline(pts, size: size, ps: ps, a))</g>"
                }
            }
            body += svgGroup(d, li, inner)
        }
        let out = svgHead(d, "PL Paint. Brush strokes as vector paths (pressure becomes width). Fills, filters, pasted images and transforms are not included.")
            + (defs.isEmpty ? "" : "<defs>\(defs.joined())</defs>\n") + body + "</svg>\n"
        return (Data(out.utf8), used, skipped)
    }
}

// MARK: bringing things in

extension NativeCanvasModel {
    /// A PSD opened as layers above the active one (groups kept, the paper layer we write goes back to being the paper).
    @discardableResult func importPSD(_ data: Data) -> String {
        guard live == nil, let d = doc else { return "Open or make a canvas first." }
        let psd: NativePSD.Doc
        do { psd = try NativePSD.read(data) } catch let e as NativePSD.Bad { return "Not opened. \(e.why)" } catch { return "Not opened. That file is not a PSD." }
        commitTransform()
        var n = 0, depth = 0, nested = false, openID = 0, openCount = 0, skippedBlend = 0, full = false
        let clipped = psd.w > d.w || psd.h > d.h
        structDo("PSD opened") {
            for it in psd.items {
                switch it {
                case .end:
                    if depth == 0 { d.groupSeq += 1; openID = d.groupSeq; openCount = 0; d.groups.append(["id": openID, "name": "Group", "open": true, "vis": true, "op": 1, "blend": "source-over"]) } else { nested = true }
                    depth += 1
                case .start(let name, let open, let op, let blend, let vis):
                    depth -= 1
                    if depth == 0, openID != 0, let k = d.groups.firstIndex(where: { ($0["id"] as? Int) == openID }) {
                        if openCount == 0 { d.groups.remove(at: k) } else { d.groups[k] = ["id": openID, "name": String(name.prefix(24)).isEmpty ? "Group" : String(name.prefix(24)), "open": open, "vis": vis, "op": op, "blend": blend] }
                        openID = 0
                    }
                case .layer(let l):
                    if l.name == "Background colour", l.w == d.w, l.h == d.h, l.rgba.count >= 3 { d.bg = Hex.string(r: Double(l.rgba[0]) / 255, g: Double(l.rgba[1]) / 255, b: Double(l.rgba[2]) / 255); d.bgVis = true; continue }
                    guard d.addLayer() else { full = true; continue }
                    let N = d.layers[d.active]
                    N.meta["name"] = String((l.name.isEmpty ? "Layer" : l.name).prefix(24)); N.meta["raw"] = true
                    N.meta["op"] = l.op; N.meta["blend"] = l.blend; N.meta["vis"] = l.vis; N.meta["grp"] = openID
                    if l.skippedBlend != nil { skippedBlend += 1 }
                    if openID != 0 { openCount += 1 }
                    if l.w > 0, l.h > 0 {
                        var px = l.rgba
                        for i in 0..<(l.w * l.h) { let a = Int(px[i * 4 + 3]); if a < 255 { for c in 0..<3 { px[i * 4 + c] = UInt8((Int(px[i * 4 + c]) * a + 127) / 255) } } }
                        px.withUnsafeMutableBytes { raw in
                            if let c = CGContext(data: raw.baseAddress, width: l.w, height: l.h, bitsPerComponent: 8, bytesPerRow: l.w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let img = c.makeImage() {
                                NativeEffects.put(img, into: N.pixels, x: Double(l.x), y: Double(l.y))
                            }
                        }
                    }
                    n += 1
                }
            }
            return n > 0
        }
        guard n > 0 else { return "That PSD had no layers to bring in." }
        var note = "\(n) layer\(n == 1 ? "" : "s") from the PSD."
        if clipped { note += " The parts outside the canvas were cut off." }
        if nested { note += " Groups inside groups were folded into the outer group." }
        if full { note += " This canvas holds only \(NativeDoc.layerCap(w: d.w, h: d.h)) layers at this size, so the rest were left out." }
        if skippedBlend > 0 { note += " \(skippedBlend) used a blend mode PL Paint does not have; they are Normal." }
        syncFlags(); stage?.rebuild()
        say(note)
        return note
    }

    /// A work file from the laptop (or a copy of one) opened as a new work on this phone.
    @discardableResult func importWorkFile(_ data: Data, name: String) -> String {
        do {
            let nd = try NativeDoc(file: data)
            saveNow()
            adopt(nd, id: NativeStore.newID(), name: String(name.prefix(40)))
            markChanged(); onChange?()
            say("Opened \(name).")
            return "Opened \(name)."
        } catch let e as WorkFileError { return "Not opened. \(e.why)" } catch { return "Not opened. That is not a PL Paint work." }
    }

    /// Photoshop brush tips (`.abr`) and a brush pack (`.json`) into Mine.
    @discardableResult func importBrushes(_ data: Data, fileName: String) -> String {
        if fileName.lowercased().hasSuffix(".abr") {
            do {
                let r = try NativeABR.parse(data)
                guard !r.tips.isEmpty else { return "Not imported. No brush tips were found in this file" + (r.skipped > 0 ? " (\(r.skipped) brushes had no bitmap)." : ".") }
                let base = String(fileName.dropLast(4).prefix(18)), stampID = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
                var n = 0
                for (i, t) in r.tips.prefix(120).enumerated() {
                    guard let tip = NativeABR.tipPNG(t) else { continue }
                    let name = String((t.name.unicodeScalars.filter { $0.value >= 32 && $0.value < 127 }.map(String.init).joined().trimmingCharacters(in: .whitespaces)).prefix(20))
                    let d: [String: Any] = ["id": "abr-\(stampID)-\(i)", "name": name.isEmpty ? "Tip \(i + 1)" : name, "shape": "tip", "tip": tip, "hard": 1, "flow": 1,
                                            "spacing": min(2, max(0.02, t.spacing > 0 ? t.spacing : 0.25)), "pressSize": 0.5, "rotMode": "fixed", "note": "From \(base)"]
                    NativeMine.upsert(Brush(d, defaults: NativeToolkit.defaults, pack: "Mine")); n += 1
                }
                let msg = "Imported \(n) tips from \(fileName) into Mine" + (r.tips.count > 120 ? "; only the first 120 were taken" : "") + (r.skipped > 0 ? "; \(r.skipped) had no bitmap or could not be read" : "") + ". Photoshop dynamics and scatter are not carried over."
                say(msg); return msg
            } catch let e as NativeABR.Bad { return "Not imported. \(e.why)" } catch { return "Not imported. That is not a brush file." }
        }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let bs = o["brushes"] as? [[String: Any]], !bs.isEmpty else { return "Not imported. That is not a brush pack." }
        var n = 0
        for var b in bs {
            guard let name = b["name"] as? String, !name.isEmpty else { continue }
            b["id"] = "imp-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + "\(n)"; b["name"] = String(name.prefix(20))
            NativeMine.upsert(Brush(b, defaults: NativeToolkit.defaults, pack: "Mine")); n += 1
        }
        let msg = "Imported \(n) brush\(n == 1 ? "" : "es") into Mine."
        say(msg); return msg
    }

    /// The active layer becomes a stamp brush in Mine: draw a mark once, stamp it anywhere in any colour.
    func brushFromLayer(named n: String) {
        guard let d = doc, d.layers.indices.contains(d.active) else { return }
        let L = d.layers[d.active].pixels
        guard let box = L.contentBounds(), let part = L.image()?.cropping(to: box) else { say("This layer is empty: draw the mark first."); return }
        let N = 128, k = Double(N) / Double(max(part.width, part.height))
        let cw = max(1, Int((Double(part.width) * k).rounded())), ch = max(1, Int((Double(part.height) * k).rounded()))
        guard let c = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        c.interpolationQuality = .high
        c.draw(part, in: CGRect(x: (N - cw) / 2, y: (N - ch) / 2, width: cw, height: ch))
        guard let img = c.makeImage(), let png = UIImage(cgImage: img).pngData() else { return }
        let id = "mine-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36), name = String((n.isEmpty ? "My mark" : n).prefix(20))
        let b = Brush(["id": id, "name": name, "shape": "tip", "tip": "data:image/png;base64," + png.base64EncodedString(), "hard": 1, "flow": 1, "spacing": 2, "pressSize": 0, "rotMode": "fixed"], defaults: NativeToolkit.defaults, pack: "Mine")
        NativeMine.upsert(b)
        brush = b
        say("\"\(name)\" is now a brush in Mine: tap to stamp it, Size sets how big.")
    }
}

// MARK: Photoshop brush tips

/// `.abr` files, read for their tips (port of `abr.js`): versions 1 and 2 (the old layout) and 6, 7 and 10 (the 8BIM layout).
enum NativeABR {
    struct Tip { var name: String; var spacing: Double; var w: Int; var h: Int; var a: [UInt8] }
    struct Result { var tips: [Tip] = []; var skipped = 0 }
    struct Bad: Error { let why: String }

    static func tipPNG(_ t: Tip) -> String? {
        var px = [UInt8](repeating: 0, count: t.w * t.h * 4)
        for i in 0..<(t.w * t.h) { px[i * 4 + 3] = t.a[i] }
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let src = CGImage(width: t.w, height: t.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: t.w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let c = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let k = 128 / Double(max(t.w, t.h)), cw = max(1, Int((Double(t.w) * k).rounded())), ch = max(1, Int((Double(t.h) * k).rounded()))
        c.interpolationQuality = .high
        c.draw(src, in: CGRect(x: (128 - cw) / 2, y: (128 - ch) / 2, width: cw, height: ch))   // the tip's longer side fills the square, so Size means the same as in Photoshop
        guard let img = c.makeImage(), let png = UIImage(cgImage: img).pngData(), png.count < 68000 else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    static func parse(_ data: Data) throws -> Result {
        let u = [UInt8](data)
        guard u.count > 8 else { throw Bad(why: "That file is empty.") }
        func i16(_ p: Int) -> Int { Int(Int16(bitPattern: UInt16(u[p]) << 8 | UInt16(u[p + 1]))) }
        func u16(_ p: Int) -> Int { Int(u[p]) << 8 | Int(u[p + 1]) }
        func i32(_ p: Int) -> Int { Int(Int32(bitPattern: UInt32(u[p]) << 24 | UInt32(u[p + 1]) << 16 | UInt32(u[p + 2]) << 8 | UInt32(u[p + 3]))) }
        func u32(_ p: Int) -> Int { Int(UInt32(u[p]) << 24 | UInt32(u[p + 1]) << 16 | UInt32(u[p + 2]) << 8 | UInt32(u[p + 3])) }
        struct Hdr { var w: Int, h: Int, depth: Int, comp: Int, at: Int }
        func header(_ p: Int, _ end: Int) -> Hdr? {
            guard p + 19 <= end, p + 19 <= u.count else { return nil }
            let t = i32(p), l = i32(p + 4), b = i32(p + 8), r = i32(p + 12), depth = i16(p + 16), comp = Int(u[p + 18]), w = r - l, h = b - t
            return (w > 0 && h > 0 && w < 12000 && h < 12000 && (depth == 8 || depth == 16) && (comp == 0 || comp == 1)) ? Hdr(w: w, h: h, depth: depth, comp: comp, at: p + 19) : nil
        }
        func pixels(_ p: Int, _ end: Int, _ w: Int, _ h: Int, _ depth: Int, _ comp: Int) throws -> [UInt8] {
            let bpp = depth == 16 ? 2 : 1
            var out = [UInt8](repeating: 0, count: w * h)
            if comp == 0 { guard p + w * h * bpp <= end, p + w * h * bpp <= u.count else { throw Bad(why: "data runs past the brush") }; for i in 0..<(w * h) { out[i] = u[p + i * bpp] }; return out }
            var q = p + h * 2; guard q <= end, q <= u.count else { throw Bad(why: "row table runs past the brush") }
            for y in 0..<h {
                let stop = min(end, q + u16(p + y * 2), u.count)
                var row = [UInt8](repeating: 0, count: w * bpp), o = 0
                while q < stop && o < row.count {
                    let c = Int(Int8(bitPattern: u[q])); q += 1
                    if c >= 0 { for _ in 0...c where o < row.count && q < u.count { row[o] = u[q]; o += 1; q += 1 } }
                    else if c != -128, q < u.count { let v = u[q]; q += 1; for _ in 0..<(1 - c) where o < row.count { row[o] = v; o += 1 } }
                }
                q = stop
                for x in 0..<w { out[y * w + x] = row[x * bpp] }
            }
            return out
        }
        func polarity(_ a: inout [UInt8], _ w: Int, _ h: Int) {   // tips are stored as paint = 255 or paint = 0; the corners of a tip are empty, so the border says which
            var sum = 0, n = 0
            for x in 0..<w { sum += Int(a[x]) + Int(a[(h - 1) * w + x]); n += 2 }
            if h > 2 { for y in 1..<(h - 1) { sum += Int(a[y * w]) + Int(a[y * w + w - 1]); n += 2 } }
            if n > 0, sum / n > 200 { for i in a.indices { a[i] = 255 - a[i] } }
        }
        var out = Result()
        let ver = i16(0)
        if ver == 1 || ver == 2 {
            let count = i16(2); var p = 4
            for i in 0..<max(0, count) {
                guard p + 6 <= u.count else { break }
                let type = i16(p), size = i32(p + 2), next = p + 6 + size; p += 6
                if type != 2 { out.skipped += 1; p = next; continue }   // computed brushes have no bitmap
                do {
                    p += 4; let spacing = i16(p); p += 2
                    var name = ""
                    if ver == 2 { let n = i32(p); p += 4; guard n >= 0, n <= 600, p + n * 2 <= u.count else { throw Bad(why: "bad name") }; for k in 0..<n { let c = u16(p + k * 2); if c != 0, let sc = UnicodeScalar(c) { name.unicodeScalars.append(sc) } }; p += n * 2 }
                    p += 1 + 8
                    guard let h0 = header(p, next) else { throw Bad(why: "no usable bounds") }
                    var a = try pixels(h0.at, next, h0.w, h0.h, h0.depth, h0.comp); polarity(&a, h0.w, h0.h)
                    out.tips.append(Tip(name: name.isEmpty ? "Tip \(out.tips.count + 1)" : name, spacing: Double(spacing) / 100, w: h0.w, h: h0.h, a: a))
                } catch { out.skipped += 1; _ = i }
                p = next
            }
            return out
        }
        guard ver == 6 || ver == 7 || ver == 10 else { throw Bad(why: "This does not look like an ABR brush file (version \(ver)).") }
        let sub = i16(2); var p = 4
        var names: [String: (name: String, spacing: Double?)] = [:]
        var samp: [(Int, Int)] = []
        while p + 12 <= u.count {
            if !(u[p] == 0x38 && u[p + 1] == 0x42 && u[p + 2] == 0x49 && u[p + 3] == 0x4d) { if u[p] == 0, p < u.count - 12 { p += 1; continue }; break }
            let key = String(decoding: u[p + 4..<p + 8], as: UTF8.self), len = u32(p + 8), body = p + 12, end = min(u.count, body + len)
            if key == "samp" { samp.append((body, end)) } else if key == "desc" { names = descNames(u, body, end) }
            p = end
        }
        for (from, end) in samp {
            var q = from
            while q + 4 < end {
                let size = u32(q), brushEnd = min(end, q + 4 + ((size + 3) & ~3))
                var at = q + 4
                do {
                    let kl = Int(u[at]); var key = ""; for i in 0..<kl { key.unicodeScalars.append(UnicodeScalar(u[at + 1 + i])) }
                    at += 1 + kl
                    var h0 = header(at + (sub == 1 ? 10 : 264), brushEnd)
                    if h0 == nil { for off in 0..<400 where h0 == nil { h0 = header(at + off, brushEnd) } }
                    guard let hh = h0 else { throw Bad(why: "no usable bounds") }
                    var a = try pixels(hh.at, brushEnd, hh.w, hh.h, hh.depth, hh.comp); polarity(&a, hh.w, hh.h)
                    let nm = names[key]
                    var name = nm?.name ?? ""
                    if name.hasPrefix("$$$"), let eq = name.firstIndex(of: "=") { name = String(name[name.index(after: eq)...]) }
                    out.tips.append(Tip(name: name.isEmpty ? "Tip \(out.tips.count + 1)" : name, spacing: nm?.spacing.map { $0 / 100 } ?? 0.25, w: hh.w, h: hh.h, a: a))
                } catch { out.skipped += 1 }
                q = brushEnd
            }
        }
        return out
    }

    /// The 'desc' section is a Photoshop descriptor; the brush names, spacings and sample keys are read out of it without a full parser.
    private static func descNames(_ u: [UInt8], _ from: Int, _ to: Int) -> [String: (name: String, spacing: Double?)] {
        func text(_ p: Int, _ n: Int) -> String { var s = String.UnicodeScalarView(); for i in 0..<n { let c = Int(u[p + i * 2]) << 8 | Int(u[p + i * 2 + 1]); if c != 0, let sc = UnicodeScalar(c) { s.append(sc) } }; return String(s) }
        func ascii(_ p: Int, _ s: String) -> Bool { let b = Array(s.utf8); guard p + b.count <= u.count else { return false }; for i in b.indices where u[p + i] != b[i] { return false }; return true }
        func i32(_ p: Int) -> Int { Int(Int32(bitPattern: UInt32(u[p]) << 24 | UInt32(u[p + 1]) << 16 | UInt32(u[p + 2]) << 8 | UInt32(u[p + 3]))) }
        var map: [String: (name: String, spacing: Double?)] = [:]
        var cur: (name: String, spacing: Double?)?
        var p = from
        let end = min(to, u.count)
        while p + 20 < end {
            if u[p] == 0x4e, ascii(p, "Nm  TEXT") {
                let n = i32(p + 8)
                if n > 0, n < 200, p + 12 + n * 2 <= end { cur = (text(p + 12, n), nil); p += 11 + n * 2 }
            } else if u[p] == 0x53, ascii(p, "SpcnUntF#Prc"), cur != nil {
                var bits: UInt64 = 0; for i in 0..<8 { bits = bits << 8 | UInt64(u[p + 12 + i]) }
                cur?.spacing = Double(bitPattern: bits); p += 19
            } else if u[p] == 0x73, ascii(p, "sampledDataTEXT") {
                let n = i32(p + 15)
                if n > 0, n < 100, p + 19 + n * 2 <= end { let key = text(p + 19, n); if let c = cur { map[key] = c }; cur = nil; p += 18 + n * 2 }
            }
            p += 1
        }
        return map
    }
}

// MARK: sheets

struct NativeExportSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var share: URL?
    @State private var busy: String?
    @State private var line: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("PNG", "photo", "The picture as you see it. Transparent where the background is hidden.", ext: "png") { d in NativeExport.png(d) }
                    row("JPEG", "photo.fill", "Smaller, no transparency: a hidden background goes onto white.", ext: "jpg") { d in NativeExport.jpeg(d) }
                    row("PDF", "doc.richtext.fill", "One page the size of the picture.", ext: "pdf") { d in NativeExport.pdf(d) }
                    row("Photoshop (PSD)", "square.3.layers.3d", "Every layer with its name, order, opacity, blend mode and visibility. Groups become folders; masks and clipping are baked in.", ext: "psd") { d in NativeExport.psd(d) }
                } header: { Text("Picture") }
                Section {
                    row("SVG, layers as images", "doc.richtext", "Each layer is an image inside its own group. Looks exactly like the canvas.", ext: "svg") { d in NativeExport.svgLayers(d) }
                    row("SVG, strokes as vectors", "scribble.variable", "The brush strokes as paths (pressure becomes width). Fills, filters, pasted images and transforms are not in it.", ext: "svg") { d in
                        let r = NativeExport.svgVector(d)
                        if r.strokes == 0 { return nil }
                        line = "\(r.strokes) strokes as vectors" + (r.skipped > 0 ? "; \(r.skipped) smudges left out." : ".")
                        return r.data
                    }
                } header: { Text("Vector") }
                Section {
                    row("The work file", "doc.zipper", "Everything, to open on the laptop or to keep. The stroke log goes with it.", ext: "json") { d in try? d.fileData() }
                } header: { Text("To keep") }
                Section {
                    Button { if let d = canvas.doc, let img = d.flatImage() { UIPasteboard.general.image = UIImage(cgImage: img); line = "Copied the picture." } } label: { Label("Copy the picture", systemImage: "doc.on.doc") }
                }
                if let line { Section { ResultLine(text: line) } }
            }
            .navigationTitle("Save or share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: Binding(get: { share.map { ExportURL(url: $0) } }, set: { if $0 == nil { share = nil } })) { ShareSheet(items: [$0.url]) }
            .overlay { if let busy { ProgressView(busy).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous)) } }
        }
    }

    private struct ExportURL: Identifiable { let url: URL; var id: String { url.path } }

    private func row(_ title: String, _ symbol: String, _ note: String, ext e: String, make: @escaping @MainActor (NativeDoc) -> Data?) -> some View {
        Button {
            Task {
                guard let d = canvas.doc else { return }
                canvas.saveNow()
                busy = "Making the \(title)…"; line = nil
                await Task.yield()
                let data = make(d)
                busy = nil
                guard let data else { line = title.contains("vector") ? "There are no brush strokes to turn into vectors yet." : "Not made. The picture could not be built."; return }
                let safe = canvas.name.replacingOccurrences(of: "/", with: "-")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe) \(NativeExport.stamp()).\(e)")
                do { try data.write(to: url, options: .atomic); share = url } catch { line = "Not saved. The phone refused the file." }
            }
        } label: {
            Label { VStack(alignment: .leading, spacing: 2) { Text(title); Text(note).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: symbol) }
        }
        .disabled(busy != nil)
    }
}

/// Bringing things in: a photo as a layer, a PSD, a brush file, a work file from the laptop.
struct NativeBringInSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var files = false
    @State private var line: String?
    @State private var markName = ""
    @State private var naming = false

    var body: some View {
        NavigationStack {
            List {
                Section("Pictures") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("A photo, as a layer", systemImage: "photo.on.rectangle") }
                    Button { canvas.panel = .lift } label: { Label("Lift the ink off a photo", systemImage: "wand.and.stars") }
                }
                Section {
                    Button { files = true } label: { Label("Open a file: PSD, brushes (.abr), a work, a picture", systemImage: "folder") }
                } header: { Text("Files") } footer: { Text("A PSD comes in as layers. An .abr file gives its tips as brushes in Mine. A work file from the laptop opens as a new work. A picture comes in as a layer.") }
                Section {
                    Button { markName = ""; naming = true } label: { Label("Make a brush from this layer", systemImage: "stamp") }
                } header: { Text("Brushes") } footer: { Text("Draw a mark once (your signature, a stamp), then stamp it anywhere in any colour.") }
                if let line { Section { ResultLine(text: line) } }
            }
            .navigationTitle("Bring in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photo) { _, it in
                guard let it else { return }
                Task {
                    guard let data = try? await it.loadTransferable(type: Data.self), let ui = UIImage(data: data), let cg = (ui.imageOrientation == .up ? ui.cgImage : NativeLift.redraw(ui)) else { line = "That picture did not open."; return }
                    canvas.addPictureLayer(cg, name: "Photo"); dismiss()
                }
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: false) { r in
                guard case .success(let urls) = r, let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { line = "That file could not be read."; return }
                let name = url.lastPathComponent, low = name.lowercased(), base = url.deletingPathExtension().lastPathComponent
                if low.hasSuffix(".psd") { line = canvas.importPSD(data) }
                else if low.hasSuffix(".abr") { line = canvas.importBrushes(data, fileName: name) }
                else if low.hasSuffix(".json") {
                    if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["layers"] != nil { line = canvas.importWorkFile(data, name: base); if line?.hasPrefix("Opened") == true { dismiss() } }
                    else { line = canvas.importBrushes(data, fileName: name) }
                } else if let ui = UIImage(data: data), let cg = (ui.imageOrientation == .up ? ui.cgImage : NativeLift.redraw(ui)) { canvas.addPictureLayer(cg, name: String(base.prefix(24))); dismiss() }
                else { line = "PL Paint cannot open that kind of file." }
            }
            .alert("Name the brush", isPresented: $naming) {
                TextField("My mark", text: $markName)
                Button("Make it") { canvas.brushFromLayer(named: markName); line = canvas.line }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
