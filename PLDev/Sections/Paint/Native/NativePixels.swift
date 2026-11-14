import CoreGraphics
import Foundation

/// Core Graphics calls this when an image over a layer's pixels is freed, on whatever thread drops it last (often SwiftUI's
/// render thread). A closure written inside the @MainActor class inherits main-actor isolation and Swift 6 traps off the main
/// thread: his crash 11-14 05:09 PT, build 163, adjusting the last stroke. A free function has no isolation. Nothing to free: the buffer owns the memory.
private func plReleaseMemory(_ info: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer, _ size: Int) {
    if let info { Unmanaged<PixelMemory>.fromOpaque(info).release() }
}

/// The pixels' own owner. Each image made over them holds one retain until Core Graphics lets the image go, so a picture
/// still on screen never points at freed memory after its layer is deleted or the canvas closes (Apple's Swift security
/// talk, 11-14: an image outliving its buffer is the dangling-pointer case; ours had an empty release, nothing kept the memory alive).
final class PixelMemory: @unchecked Sendable {   // immutable after init; freed once, by whoever holds the last retain
    let p: UnsafeMutablePointer<UInt8>
    init(count: Int) { p = .allocate(capacity: count); p.initialize(repeating: 0, count: count) }
    deinit { p.deallocate() }
}

/// One layer's pixels: premultiplied RGBA, row 0 on top, y-down like the laptop's canvas (his file stores the same pixels).
/// Undo is a patch stack of tiles (before and after), so a stroke on a 16 MP canvas costs the strokes' own area, not the canvas.
@MainActor final class PixelBuffer {
    static let tile = 128
    let w: Int, h: Int
    private let mem: PixelMemory   // this buffer and every image() over it keep it alive (the context does not: use snapshot())
    nonisolated(unsafe) let ptr: UnsafeMutablePointer<UInt8>
    let ctx: CGContext

    init?(w: Int, h: Int) {
        guard w > 0, h > 0, w * h <= 16_777_216 else { return nil }
        self.w = w; self.h = h
        mem = PixelMemory(count: w * h * 4)
        ptr = mem.p
        guard let c = CGContext(data: ptr, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)   // doc space is y-down
        c.interpolationQuality = .high
        ctx = c
    }

    /// A copied image of the pixels, made while this buffer is certainly alive. `compositeBuffer()?.ctx.makeImage()` let a
    /// temporary buffer free its memory while the context still drew from it: every export, the hand trace and the tile guides
    /// crashed in CGBitmapContextCreateImage (simulator crash report 11-14 07:10, EXC_BAD_ACCESS in memmove).
    func heldImage() -> CGImage? { withExtendedLifetime(self) { ctx.makeImage() } }

    /// An image over the same memory (no copy). Make a new one after every change so Core Animation uploads it again.
    func image() -> CGImage? {
        let info = Unmanaged.passRetained(mem).toOpaque()   // released by plReleaseMemory when Core Graphics frees the image
        guard let p = CGDataProvider(dataInfo: info, data: ptr, size: w * h * 4, releaseData: plReleaseMemory) else {
            Unmanaged<PixelMemory>.fromOpaque(info).release(); return nil
        }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: p, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func clear(_ r: CGRect) { ctx.clear(r) }

    /// Draws an upright image (row 0 on top) into this y-down context, limited to `clip`, with an opacity and a blend mode.
    func drawUpright(_ img: CGImage, in clip: CGRect, alpha: CGFloat = 1, blend: CGBlendMode = .normal) {
        ctx.saveGState()
        ctx.clip(to: clip)
        ctx.setAlpha(alpha); ctx.setBlendMode(blend)
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // the second flip: the image lands the right way up
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    /// Copy of the pixels of one tile (clipped to the canvas).
    func tilePixels(tx: Int, ty: Int) -> Data {
        let (x0, y0, tw, th) = bounds(tx, ty)
        var d = Data(count: tw * th * 4)
        d.withUnsafeMutableBytes { out in
            for row in 0..<th { memcpy(out.baseAddress! + row * tw * 4, ptr + ((y0 + row) * w + x0) * 4, tw * 4) }
        }
        return d
    }
    func setTile(tx: Int, ty: Int, _ d: Data) {
        let (x0, y0, tw, th) = bounds(tx, ty)
        guard d.count == tw * th * 4 else { return }
        d.withUnsafeBytes { src in
            for row in 0..<th { memcpy(ptr + ((y0 + row) * w + x0) * 4, src.baseAddress! + row * tw * 4, tw * 4) }
        }
    }
    func bounds(_ tx: Int, _ ty: Int) -> (Int, Int, Int, Int) {
        let x0 = tx * Self.tile, y0 = ty * Self.tile
        return (x0, y0, min(Self.tile, w - x0), min(Self.tile, h - y0))
    }
    /// Tile coordinates a rect touches, clamped to the canvas.
    func tiles(in r: CGRect) -> [TileKey] {
        let x0 = max(0, Int(floor(r.minX))), y0 = max(0, Int(floor(r.minY)))
        let x1 = min(w - 1, Int(ceil(r.maxX))), y1 = min(h - 1, Int(ceil(r.maxY)))
        guard x1 >= x0, y1 >= y0 else { return [] }
        var out: [TileKey] = []
        for ty in (y0 / Self.tile)...(y1 / Self.tile) { for tx in (x0 / Self.tile)...(x1 / Self.tile) { out.append(TileKey(tx: tx, ty: ty)) } }
        return out
    }
    func rect(of k: TileKey) -> CGRect { let b = bounds(k.tx, k.ty); return CGRect(x: b.0, y: b.1, width: b.2, height: b.3) }
}

struct TileKey: Hashable, Sendable { let tx: Int, ty: Int }

/// One step of history: what undoes it and what does it again. A stroke names its pixel tiles; a layer edit names the layer list; a
/// selection names a mask copy. `structural` means the layer tree on screen must be built again afterwards.
struct HistoryEntry {
    let label: String
    let structural: Bool
    let undo: () -> Void
    let redo: () -> Void
}

/// Undo and redo, 250 deep (the laptop's MAX_UNDO). Blocked mid-stroke by the caller.
@MainActor final class UndoStack {
    static let limit = 250
    private(set) var done: [HistoryEntry] = [], undone: [HistoryEntry] = []
    var canUndo: Bool { !done.isEmpty }
    var canRedo: Bool { !undone.isEmpty }
    func push(_ e: HistoryEntry) { done.append(e); undone.removeAll(); if done.count > Self.limit { done.removeFirst() } }
    func undo() -> HistoryEntry? {
        guard let e = done.popLast() else { return nil }
        e.undo(); undone.append(e); return e
    }
    func redo() -> HistoryEntry? {
        guard let e = undone.popLast() else { return nil }
        e.redo(); done.append(e); return e
    }
    func reset() { done.removeAll(); undone.removeAll() }
    /// Forgets the last `n` steps without undoing them (a restyle folds its many strokes into one step).
    func dropLast(_ n: Int) { if n > 0 { done.removeLast(min(n, done.count)) } }
}

extension PixelBuffer {
    /// Copies the whole buffer, packed with LZ4 (a layer is mostly empty, so a history step of a whole layer stays small).
    func snapshot() -> Data {
        let raw = Data(bytes: ptr, count: w * h * 4)
        return ((try? (raw as NSData).compressed(using: .lz4)) as Data?) ?? raw
    }
    func restore(_ d: Data) {
        var raw = d
        if d.count != w * h * 4 { guard let u = try? (d as NSData).decompressed(using: .lz4) as Data else { return }; raw = u }
        guard raw.count == w * h * 4 else { return }
        raw.withUnsafeBytes { memcpy(ptr, $0.baseAddress!, w * h * 4) }
    }
    /// The pixels of a rectangle as a tight copy, and the way back.
    func region(_ r: CGRect) -> (CGRect, Data)? {
        let b = r.integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !b.isNull, b.width >= 1, b.height >= 1 else { return nil }
        let x0 = Int(b.minX), y0 = Int(b.minY), rw = Int(b.width), rh = Int(b.height)
        var d = Data(count: rw * rh * 4)
        d.withUnsafeMutableBytes { out in for row in 0..<rh { memcpy(out.baseAddress! + row * rw * 4, ptr + ((y0 + row) * w + x0) * 4, rw * 4) } }
        return (b, d)
    }
    func put(region r: CGRect, _ d: Data) {
        let x0 = Int(r.minX), y0 = Int(r.minY), rw = Int(r.width), rh = Int(r.height)
        guard d.count == rw * rh * 4 else { return }
        d.withUnsafeBytes { src in for row in 0..<rh { memcpy(ptr + ((y0 + row) * w + x0) * 4, src.baseAddress! + row * rw * 4, rw * 4) } }
    }
}
