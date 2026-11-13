import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// His work file, read and written exactly as the laptop does (`work-<id>.json`, v:1): size, background, layers as PNG data URLs, the
/// guide state, the groups, and the stroke log (last 4,000 strokes). Fields this engine does not use yet are carried through untouched,
/// so a work opened here and saved goes back to the laptop whole.
struct WorkFileError: Error { let why: String }

@MainActor final class NativeLayer {
    var meta: [String: Any]        // everything in the file's layer record except the pixels
    var maskPx: PixelBuffer?       // the layer mask: white with alpha; alpha says how much of the layer shows
    let pixels: PixelBuffer
    var name: String { meta["name"] as? String ?? "Layer" }
    var visible: Bool { meta["vis"] as? Bool ?? true }
    var opacity: Double { (meta["op"] as? Double) ?? Double(meta["op"] as? Int ?? 1) }
    var alphaLock: Bool { meta["lock"] as? Bool ?? false }
    init(meta: [String: Any], maskPx: PixelBuffer?, pixels: PixelBuffer) { self.meta = meta; self.maskPx = maskPx; self.pixels = pixels }
    static func defaultMeta(_ name: String) -> [String: Any] {
        ["name": name, "vis": true, "op": 1, "blend": "source-over", "lock": false, "clip": false, "grp": 0, "ref": false, "raw": false, "glow": 0]
    }
}

@MainActor final class NativeDoc {
    let w: Int, h: Int
    var bg: String, bgVis: Bool
    var layers: [NativeLayer]
    var active: Int
    var groups: [[String: Any]]
    var guide: [String: Any]
    var groupSeq = 0
    var log: [[String: Any]]
    var layerSeq: Int

    /// The number a stroke in the log uses to name this layer; it does not change when layers are moved.
    func layerID(_ i: Int) -> Int { layers.indices.contains(i) ? (layers[i].meta["id"] as? Int ?? i + 1) : i + 1 }
    func freshLayerID() -> Int { (layers.compactMap { $0.meta["id"] as? Int }.max() ?? 0) + 1 }

    init(w: Int, h: Int, bg: String = "#ffffff") throws {
        guard w >= 64, h >= 64, let px = PixelBuffer(w: w, h: h) else { throw WorkFileError(why: "That size is outside what this phone holds.") }
        self.w = w; self.h = h; self.bg = bg; bgVis = true; active = 0
        layers = [NativeLayer(meta: NativeLayer.defaultMeta("Layer 1"), maskPx: nil, pixels: px)]
        groups = []
        guide = ["g": "off", "vps": NSNull(), "size": 128, "tile": "off", "paper": "plain", "seam": NSNull()]
        log = []; layerSeq = 1
    }

    /// Reads a work file. Throws a plain sentence when the file is not one.
    init(file: Data) throws {
        guard let d = try? JSONSerialization.jsonObject(with: file) as? [String: Any], let ls = d["layers"] as? [[String: Any]], !ls.isEmpty else { throw WorkFileError(why: "This is not a PL Paint work.") }
        let w = d["w"] as? Int ?? 0, h = d["h"] as? Int ?? 0
        guard w >= 64, h >= 64, w * h <= 16_777_216 else { throw WorkFileError(why: "This work's size is outside what PL Paint holds.") }
        self.w = w; self.h = h
        bg = d["bg"] as? String ?? "#ffffff"; bgVis = d["bgVis"] as? Bool ?? true
        groups = d["groups"] as? [[String: Any]] ?? []; guide = d["guide"] as? [String: Any] ?? ["g": "off"]
        groupSeq = groups.map { $0["id"] as? Int ?? 0 }.max() ?? 0
        log = d["log"] as? [[String: Any]] ?? []
        var out: [NativeLayer] = []
        for l in ls {
            guard let px = PixelBuffer(w: w, h: h) else { throw WorkFileError(why: "This work is too large for this phone.") }
            if let png = l["png"] as? String, let img = Self.image(fromDataURL: png) { px.drawUpright(img, in: CGRect(x: 0, y: 0, width: w, height: h)) }
            var meta = l; meta.removeValue(forKey: "png"); meta.removeValue(forKey: "mask")
            var mpx: PixelBuffer?
            if let m = l["mask"] as? String, let img = Self.image(fromDataURL: m), let mb = PixelBuffer(w: w, h: h) { mb.drawUpright(img, in: CGRect(x: 0, y: 0, width: w, height: h)); mpx = mb }
            if let g = meta["grp"] as? Int, g != 0, !groups.contains(where: { ($0["id"] as? Int) == g }) { meta["grp"] = 0 }
            out.append(NativeLayer(meta: meta, maskPx: mpx, pixels: px))
        }
        for (i, l) in out.enumerated() where l.meta["id"] as? Int == nil { l.meta["id"] = i + 1 }   // the laptop's numbering: a stroke in the log names its layer by this
        layers = out
        active = max(0, min(out.count - 1, d["active"] as? Int ?? 0))
        layerSeq = out.count
    }

    nonisolated static func image(fromDataURL s: String) -> CGImage? {
        guard let c = s.firstIndex(of: ","), let data = Data(base64Encoded: String(s[s.index(after: c)...])),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Writes the work file. PNG-encodes every layer, so the caller does this when drawing has paused.
    func fileData(keepLog: Int = 4000) throws -> Data {
        var ls: [[String: Any]] = []
        for l in layers {
            guard let img = l.pixels.image(), let png = UIImage(cgImage: img).pngData() else { throw WorkFileError(why: "A layer could not be turned into a picture.") }
            var r = l.meta
            r["png"] = "data:image/png;base64," + png.base64EncodedString()
            if let m = l.maskPx?.image(), let mp = UIImage(cgImage: m).pngData() { r["mask"] = "data:image/png;base64," + mp.base64EncodedString() } else { r["mask"] = NSNull() }
            ls.append(r)
        }
        let o: [String: Any] = ["v": 1, "w": w, "h": h, "bg": bg, "bgVis": bgVis, "active": active, "groups": groups, "guide": guide, "layers": ls, "log": Array(log.suffix(keepLog))]
        return try JSONSerialization.data(withJSONObject: o)
    }

    /// The whole picture flattened onto white, long side `maxSide`, as JPEG: the work's thumbnail in the index.
    func thumbnailDataURL(maxSide: Int = 220) -> String? {
        let k = Double(maxSide) / Double(max(w, h)), tw = max(1, Int(Double(w) * k)), th = max(1, Int(Double(h) * k))
        guard let c = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: tw, height: th))
        c.interpolationQuality = .medium
        for l in layers where l.visible {
            if let img = l.pixels.image() { c.setAlpha(CGFloat(l.opacity)); c.draw(img, in: CGRect(x: 0, y: 0, width: tw, height: th)) }
        }
        guard let out = c.makeImage(), let jpg = UIImage(cgImage: out).jpegData(compressionQuality: 0.7) else { return nil }
        return "data:image/jpeg;base64," + jpg.base64EncodedString()
    }

    /// The flat picture for the share sheet: blends, groups and clips applied, transparent where the background is hidden.
    func flatPNG() -> Data? { flatImage().flatMap { UIImage(cgImage: $0).pngData() } }
}

enum Hex {
    static func rgb(_ s: String) -> (Double, Double, Double)? {
        var t = s.trimmingCharacters(in: .whitespaces); if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }
    static func color(_ s: String) -> CGColor? { rgb(s).map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) } }
    static func string(r: Double, g: Double, b: Double) -> String {
        String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// The works on this phone: files in the app's own folder, an index that keeps the sync fields (`sy`, `scu`, `sn`, `stack`) the laptop reads.
@MainActor enum NativeStore {
    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PLPaintNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static var indexURL: URL { dir.appendingPathComponent("works.json") }
    static func workURL(_ id: String) -> URL { dir.appendingPathComponent("work-\(id).json") }

    struct Index { var current: String?; var list: [[String: Any]]; var gone: [String: Any] }
    static func loadIndex() -> Index {
        guard let d = try? Data(contentsOf: indexURL), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return Index(current: nil, list: [], gone: [:]) }
        return Index(current: o["current"] as? String, list: o["list"] as? [[String: Any]] ?? [], gone: o["gone"] as? [String: Any] ?? [:])
    }
    static func saveIndex(_ i: Index) throws {
        var o: [String: Any] = ["v": 1, "list": i.list, "gone": i.gone]
        o["current"] = i.current ?? NSNull()
        try JSONSerialization.data(withJSONObject: o).write(to: indexURL, options: .atomic)
    }
    static func rememberCurrent(_ id: String) {
        var ix = loadIndex(); ix.current = id
        try? saveIndex(ix)
    }
    static func newID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String((0..<4).map { _ in chars.randomElement()! })
    }

    /// Saves a work and its index entry. The thumbnail and the times are the laptop's fields.
    static func save(_ doc: NativeDoc, id: String, name: String) throws {
        try doc.fileData().write(to: workURL(id), options: .atomic)
        var ix = loadIndex()
        let now = Date().timeIntervalSince1970 * 1000
        var e = ix.list.first { ($0["id"] as? String) == id } ?? ["id": id]
        e["name"] = name; e["w"] = doc.w; e["h"] = doc.h; e["updated"] = now; e["cu"] = now
        if let t = doc.thumbnailDataURL() { e["thumb"] = t }
        e["blank"] = doc.log.isEmpty
        if let k = ix.list.firstIndex(where: { ($0["id"] as? String) == id }) { ix.list[k] = e } else { ix.list.insert(e, at: 0) }
        ix.current = id
        try saveIndex(ix)
    }
    static func load(_ id: String) throws -> NativeDoc { try NativeDoc(file: Data(contentsOf: workURL(id))) }
    static func delete(_ id: String) throws {
        try? FileManager.default.removeItem(at: workURL(id))
        var ix = loadIndex(); ix.list.removeAll { ($0["id"] as? String) == id }
        ix.gone[id] = Date().timeIntervalSince1970 * 1000   // the laptop's tombstone
        if ix.current == id { ix.current = ix.list.first?["id"] as? String }
        try saveIndex(ix)
    }
}

/// Reading his synced works from pl-cron: `index`, then `work/:id` (gzip when the server says so; the body's first two bytes say it too).
@MainActor enum NativeRemote {
    struct Entry: Identifiable { let id: String; let name: String; let w: Int; let h: Int; let updated: Double; let thumb: UIImage? }

    static func list(_ http: HTTPClient) async throws -> [Entry] {
        let d = try await http.send(RequestPlan(origin: "paint", path: "index"), timeout: 30)
        let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        let raw = o["works"] as? [String: [String: Any]] ?? [:]
        return raw.map { id, m in
            let thumb = (m["thumb"] as? String).flatMap { NativeDoc.image(fromDataURL: $0) }.map { UIImage(cgImage: $0) }
            let u = (m["updated"] as? Double) ?? Double(m["updated"] as? Int ?? 0)
            return Entry(id: id, name: m["name"] as? String ?? "Untitled", w: m["w"] as? Int ?? 0, h: m["h"] as? Int ?? 0, updated: u, thumb: thumb)
        }.sorted { $0.updated > $1.updated }
    }

    /// Downloads a work and keeps it on the phone under its own id, with the sync fields the laptop's `pullWork` sets.
    static func fetch(_ http: HTTPClient, entry: Entry) async throws -> String {
        let body = try await http.send(RequestPlan(origin: "paint", path: "work/\(entry.id)"), timeout: 120)
        let json = try Gzip.inflateIfNeeded(body)
        _ = try NativeDoc(file: json)   // refuse a file that is not a work before it is kept
        try json.write(to: NativeStore.workURL(entry.id), options: .atomic)
        var ix = NativeStore.loadIndex()
        var e: [String: Any] = ["id": entry.id, "name": entry.name, "w": entry.w, "h": entry.h, "updated": entry.updated, "cu": entry.updated, "sy": entry.updated, "scu": entry.updated, "sn": entry.name + "|", "blank": false]
        if let k = ix.list.firstIndex(where: { ($0["id"] as? String) == entry.id }) { e.merge(ix.list[k]) { fetched, _ in fetched }; ix.list[k] = e } else { ix.list.insert(e, at: 0) }
        try NativeStore.saveIndex(ix)
        return entry.id
    }
}

enum Gzip {
    /// gzip is a 10-byte header (plus optional parts), a raw deflate stream and an 8-byte trailer. Apple's `.zlib` is the raw deflate stream.
    static func inflateIfNeeded(_ d: Data) throws -> Data {
        let b = [UInt8](d)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b else { return d }
        let flg = b[3]
        var i = 10
        if flg & 4 != 0 { guard i + 2 <= b.count else { throw WorkFileError(why: "The work arrived damaged.") }; i += 2 + Int(b[i]) + (Int(b[i + 1]) << 8) }
        if flg & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flg & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flg & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { throw WorkFileError(why: "The work arrived damaged.") }
        let raw = Data(b[i..<(b.count - 8)])
        do { return try (raw as NSData).decompressed(using: .zlib) as Data } catch { throw WorkFileError(why: "The work arrived damaged.") }
    }
}
