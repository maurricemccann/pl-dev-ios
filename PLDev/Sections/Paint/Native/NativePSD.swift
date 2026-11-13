import CoreGraphics
import Foundation
import UIKit

/// PSD read and write (8-bit RGB, raster layers): the port of `psd.js`, written from the published file format. Layers run bottom to top;
/// a group is a divider record first, its layers, then the folder record last.
enum NativePSD {
    static let key: [String: String] = [
        "source-over": "norm", "multiply": "mul ", "screen": "scrn", "overlay": "over", "darken": "dark", "lighten": "lite", "color-dodge": "div ", "color-burn": "idiv",
        "hard-light": "hLit", "soft-light": "sLit", "difference": "diff", "exclusion": "smud", "hue": "hue ", "saturation": "sat ", "color": "colr", "luminosity": "lum ", "lighter": "lddg",
        "x-linear-burn": "lbrn", "x-darker-color": "dkCl", "x-lighter-color": "lgCl", "x-vivid-light": "vLit", "x-linear-light": "lLit", "x-pin-light": "pLit", "x-hard-mix": "hMix", "x-subtract": "fsub", "x-divide": "fdiv",
    ]
    static var reverse: [String: String] {
        var r = Dictionary(uniqueKeysWithValues: key.map { ($0.value, $0.key) }); r["pass"] = "source-over"; return r
    }

    enum Item {
        case layer(name: String, vis: Bool, op: Double, blend: String, rgba: [UInt8])   // straight RGBA, the full canvas
        case groupEnd
        case groupStart(name: String, open: Bool, vis: Bool, op: Double, blend: String)
    }

    private static func i16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 255), UInt8(v & 255)] }
    private static func i32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
    private static func asc(_ s: String) -> [UInt8] { s.unicodeScalars.map { UInt8($0.value & 255) } }
    private static func pascal(_ name: String) -> [UInt8] {
        let clean = String(name.unicodeScalars.map { $0.value >= 32 && $0.value < 127 ? Character($0) : "?" }.prefix(31))
        let b = asc(clean), len = 1 + b.count, pad = (4 - len % 4) % 4
        return [UInt8(b.count)] + b + [UInt8](repeating: 0, count: pad)
    }

    static func write(w: Int, h: Int, items: [Item], flat: [UInt8]) -> Data {
        var records: [[UInt8]] = [], data: [[UInt8]] = []
        var count = 0
        for it in items {
            count += 1
            switch it {
            case .groupEnd, .groupStart:
                var isEnd = false, name = "Group", op = 255, vis = true, bk = "norm", type = 3
                if case .groupStart(let n, let open, let v, let o, let b) = it {
                    name = n.isEmpty ? "Group" : n; vis = v; type = open ? 1 : 2
                    op = Int((max(0, min(1, o)) * 255).rounded()); bk = (b == "source-over" && o >= 1) ? "pass" : (key[b] ?? "norm")
                } else { isEnd = true; name = "</Layer group>" }
                var head: [UInt8] = i32(0) + i32(0) + i32(0) + i32(0) + i16(4)
                for id in [-1, 0, 1, 2] { head += i16(id & 0xffff) + i32(2) }
                head += asc("8BIM") + asc(bk) + [UInt8(isEnd ? 255 : op), 0, (isEnd || vis) ? 0 : 2, 0]
                let extra: [UInt8] = i32(0) + i32(0) + pascal(name) + asc("8BIM") + asc("lsct") + i32(4) + i32(type)
                records.append(head + i32(extra.count) + extra)
                for _ in 0..<4 { data.append(i16(0)) }
            case .layer(let name, let vis, let op, let blend, let px):
                var x0 = w, y0 = h, x1 = -1, y1 = -1
                for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] != 0 { if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y } } }
                let empty = x1 < 0, bw = empty ? 0 : x1 - x0 + 1, bh = empty ? 0 : y1 - y0 + 1
                var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: bw * bh), count: 4)
                for y in 0..<bh { for x in 0..<bw { let i = ((y0 + y) * w + x0 + x) * 4, o = y * bw + x; for c in 0..<4 { planes[c][o] = px[i + c] } } }
                let chLen = 2 + bw * bh
                var head: [UInt8] = i32(empty ? 0 : y0) + i32(empty ? 0 : x0) + i32(empty ? 0 : y0 + bh) + i32(empty ? 0 : x0 + bw) + i16(4)
                for id in [-1, 0, 1, 2] { head += i16(id & 0xffff) + i32(chLen) }
                head += asc("8BIM") + asc(key[blend] ?? "norm") + [UInt8((max(0, min(1, op)) * 255).rounded()), 0, vis ? 0 : 2, 0]
                let extra: [UInt8] = i32(0) + i32(0) + pascal(name.isEmpty ? "Layer" : name)
                records.append(head + i32(extra.count) + extra)
                for c in [3, 0, 1, 2] { data.append(i16(0) + planes[c]) }   // alpha first, then R G B, each raw
            }
        }
        var infoLen = 2
        for r in records { infoLen += r.count }
        for d in data { infoLen += d.count }
        let pad = infoLen % 2
        var layerInfo: [UInt8] = i32(infoLen + pad) + i16(count)
        for r in records { layerInfo += r }
        for d in data { layerInfo += d }
        layerInfo += [UInt8](repeating: 0, count: pad)
        let layerAndMask: [UInt8] = i32(layerInfo.count + 4) + layerInfo + i32(0)
        var out: [UInt8] = asc("8BPS") + i16(1) + [UInt8](repeating: 0, count: 6) + i16(3) + i32(h) + i32(w) + i16(8) + i16(3)
        out += i32(0) + i32(0) + layerAndMask
        out += i16(0)
        var planes = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) { planes[i] = flat[i * 4]; planes[w * h + i] = flat[i * 4 + 1]; planes[2 * w * h + i] = flat[i * 4 + 2] }
        out += planes
        return Data(out)
    }

    struct ReadLayer { var name: String; var x: Int; var y: Int; var w: Int; var h: Int; var rgba: [UInt8]; var op: Double; var blend: String; var vis: Bool; var skippedBlend: String? }
    enum ReadItem { case layer(ReadLayer), start(name: String, open: Bool, op: Double, blend: String, vis: Bool), end }
    struct Doc { var w: Int, h: Int, items: [ReadItem] }

    struct Bad: Error { let why: String }

    static func read(_ data: Data) throws -> Doc {
        let u = [UInt8](data); var p = 0
        func need(_ n: Int) throws { if p + n > u.count || p < 0 { throw Bad(why: "The file ends too early.") } }
        func s32() throws -> Int { try need(4); let v = Int(Int32(bitPattern: UInt32(u[p]) << 24 | UInt32(u[p + 1]) << 16 | UInt32(u[p + 2]) << 8 | UInt32(u[p + 3]))); p += 4; return v }
        func s16() throws -> Int { try need(2); let v = Int(Int16(bitPattern: UInt16(u[p]) << 8 | UInt16(u[p + 1]))); p += 2; return v }
        func u16(_ at: Int) -> Int { Int(u[at]) << 8 | Int(u[at + 1]) }
        func tag() throws -> String { try need(4); let t = String(decoding: u[p..<p + 4], as: UTF8.self); p += 4; return t }
        func skip() throws { let n = try s32(); p += n }
        guard try tag() == "8BPS" else { throw Bad(why: "This is not a PSD file.") }
        guard try s16() == 1 else { throw Bad(why: "Only PSD files are supported, not PSB.") }
        p += 6
        _ = try s16()
        let h = try s32(), w = try s32(), depth = try s16(), mode = try s16()
        guard depth == 8, mode == 3 else { throw Bad(why: "Only 8-bit RGB PSD files are supported (this one is \(depth)-bit, mode \(mode)).") }
        try skip(); try skip()
        let lmLen = try s32()
        var out = Doc(w: w, h: h, items: [])
        if lmLen == 0 { return out }
        _ = try s32()
        let count = abs(try s16())
        struct Rec { var top = 0, left = 0, bottom = 0, right = 0; var chans: [(id: Int, len: Int)] = []; var blend = "norm"; var op = 255; var flags = 0; var name = ""; var group = 0 }
        var recs: [Rec] = []
        let rev = reverse
        for _ in 0..<count {
            var r = Rec()
            r.top = try s32(); r.left = try s32(); r.bottom = try s32(); r.right = try s32()
            let nch = try s16()
            for _ in 0..<nch { let id = try s16(), len = try s32(); r.chans.append((id, len)) }
            guard try tag() == "8BIM" else { throw Bad(why: "A layer record is damaged.") }
            r.blend = try tag(); try need(4); r.op = Int(u[p]); r.flags = Int(u[p + 2]); p += 4
            let exLen = try s32(), exEnd = p + exLen
            try skip(); try skip()
            try need(1)
            let nl = Int(u[p]); try need(1 + nl)
            var name = ""; for i in 0..<nl { name.unicodeScalars.append(UnicodeScalar(u[p + 1 + i])) }
            p += 1 + nl; p += (4 - (1 + nl) % 4) % 4
            var uni: String?
            while p + 12 <= exEnd {
                let sig = try tag(); if sig != "8BIM" && sig != "8B64" { break }
                let k = try tag(), len = try s32()
                if k == "lsct", p + 4 <= u.count { r.group = Int(Int32(bitPattern: UInt32(u[p]) << 24 | UInt32(u[p + 1]) << 16 | UInt32(u[p + 2]) << 8 | UInt32(u[p + 3]))) }
                else if k == "luni", p + 4 <= u.count {
                    let c = Int(UInt32(u[p]) << 24 | UInt32(u[p + 1]) << 16 | UInt32(u[p + 2]) << 8 | UInt32(u[p + 3]))
                    if c > 0, p + 4 + c * 2 <= u.count { var t = String.UnicodeScalarView(); for i in 0..<c { if let sc = UnicodeScalar(UInt32(u16(p + 4 + i * 2))) { t.append(sc) } }; uni = String(t) }
                }
                p += len + (len % 2)
            }
            p = exEnd; r.name = uni ?? name
            recs.append(r)
        }
        for r in recs {
            let rw = r.right - r.left, rh = r.bottom - r.top
            var rgba = [UInt8](repeating: 0, count: max(0, rw * rh) * 4), hasAlpha = false
            for ch in r.chans {
                let end = p + ch.len, comp = try s16()
                var plane = [UInt8](repeating: 0, count: max(0, rw * rh))
                if rw > 0, rh > 0 {
                    if comp == 0 { try need(rw * rh); plane.replaceSubrange(0..<(rw * rh), with: u[p..<p + rw * rh]) }
                    else if comp == 1 {
                        try need(rh * 2)
                        var q = p + rh * 2
                        for y in 0..<rh {
                            var o = y * rw; let stop = q + u16(p + y * 2)
                            while q < stop && q < u.count {
                                let c = Int(Int8(bitPattern: u[q])); q += 1
                                if c >= 0 { for _ in 0...c where o < plane.count && q < u.count { plane[o] = u[q]; o += 1; q += 1 } }
                                else if c != -128, q < u.count { let v = u[q]; q += 1; for _ in 0..<(1 - c) where o < plane.count { plane[o] = v; o += 1 } }
                            }
                        }
                    } else { throw Bad(why: "This PSD uses a layer compression that is not supported (\(comp)).") }
                }
                p = end
                let slot = ch.id == 0 ? 0 : ch.id == 1 ? 1 : ch.id == 2 ? 2 : ch.id == -1 ? 3 : -1
                if slot < 0 { continue }
                if slot == 3 { hasAlpha = true }
                for i in 0..<(rw * rh) { rgba[i * 4 + slot] = plane[i] }
            }
            if !hasAlpha { for i in 0..<max(0, rw * rh) { rgba[i * 4 + 3] = 255 } }
            let blend = rev[r.blend] ?? "source-over", vis = (r.flags & 2) == 0
            if r.group == 3 { out.items.append(.end) }
            else if r.group == 1 || r.group == 2 { out.items.append(.start(name: r.name, open: r.group == 1, op: Double(r.op) / 255, blend: blend, vis: vis)) }
            else if r.group == 0 { out.items.append(.layer(ReadLayer(name: r.name, x: rw > 0 ? r.left : 0, y: rw > 0 ? r.top : 0, w: max(0, rw), h: max(0, rh), rgba: rgba, op: Double(r.op) / 255, blend: blend, vis: vis, skippedBlend: rev[r.blend] == nil ? r.blend : nil))) }
        }
        return out
    }
}
