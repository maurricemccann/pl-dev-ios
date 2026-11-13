import CoreGraphics
import Foundation

/// One layer's pixels: premultiplied RGBA, row 0 on top, y-down like the laptop's canvas (his file stores the same pixels).
/// Undo is a patch stack of tiles (before and after), so a stroke on a 16 MP canvas costs the strokes' own area, not the canvas.
@MainActor final class PixelBuffer {
    static let tile = 128
    let w: Int, h: Int
    let ptr: UnsafeMutablePointer<UInt8>
    let ctx: CGContext

    init?(w: Int, h: Int) {
        guard w > 0, h > 0, w * h <= 16_777_216 else { return nil }
        self.w = w; self.h = h
        ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        ptr.initialize(repeating: 0, count: w * h * 4)
        guard let c = CGContext(data: ptr, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { ptr.deallocate(); return nil }
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)   // doc space is y-down
        c.interpolationQuality = .high
        ctx = c
    }
    deinit { ptr.deallocate() }

    /// An image over the same memory (no copy). Make a new one after every change so Core Animation uploads it again.
    func image() -> CGImage? {
        guard let p = CGDataProvider(dataInfo: nil, data: ptr, size: w * h * 4, releaseData: { _, _, _ in }) else { return nil }
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

/// What one stroke changed on one layer: each touched tile before and after.
struct Patch {
    struct T { let key: TileKey; let before: Data; var after: Data }
    let layer: Int
    var tiles: [T]
}

/// Undo and redo as a patch stack of 250, the laptop's MAX_UNDO. Blocked mid-stroke by the caller.
@MainActor final class UndoStack {
    static let limit = 250
    private(set) var done: [Patch] = [], undone: [Patch] = []
    var canUndo: Bool { !done.isEmpty }
    var canRedo: Bool { !undone.isEmpty }
    func push(_ p: Patch) { done.append(p); undone.removeAll(); if done.count > Self.limit { done.removeFirst() } }
    func undo(_ layers: [PixelBuffer]) -> Patch? {
        guard let p = done.popLast(), p.layer < layers.count else { return nil }
        for t in p.tiles { layers[p.layer].setTile(tx: t.key.tx, ty: t.key.ty, t.before) }
        undone.append(p); return p
    }
    func redo(_ layers: [PixelBuffer]) -> Patch? {
        guard let p = undone.popLast(), p.layer < layers.count else { return nil }
        for t in p.tiles { layers[p.layer].setTile(tx: t.key.tx, ty: t.key.ty, t.after) }
        done.append(p); return p
    }
    func reset() { done.removeAll(); undone.removeAll() }
}
