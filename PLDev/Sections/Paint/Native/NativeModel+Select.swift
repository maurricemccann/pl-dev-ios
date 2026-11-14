import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Selecting (automatic, freehand, rectangle, ellipse; add, remove, invert, feather, bring the last one back), copy, cut and paste,
/// and the transform session. Ports of the selection and transform sections of the laptop's `app.js`.
extension NativeCanvasModel {
    // MARK: selecting

    @discardableResult func ensureSelection() -> NativeSelection? {
        guard let d = doc else { return nil }
        if selection == nil || selection?.w != d.w || selection?.h != d.h { selection = NativeSelection(w: d.w, h: d.h) }
        return selection
    }

    func setMode(_ m: CanvasMode) {
        guard live == nil, doc != nil else { return }
        if m != .transform { commitTransform() }
        mode = m
        selDrag = nil
        if m == .select { ensureSelection() }
        stage?.updateOverlay()
        if m == .select { say("Select: drag a shape, or tap a colour in Automatic.") }
        if m == .eyedrop { say("Touch the picture to pick a colour.") }
        if m == .fill { say("ColorDrop: touch an area to fill it. The threshold sets how far one colour reaches.") }
    }

    /// A selection change is an undo step, like any other edit.
    func selHist(_ fn: () -> Void) {
        guard let sel = ensureSelection() else { return }
        let b = sel.snapshot()
        fn()
        let a = sel.snapshot()
        if !b.has && !a.has { return }
        if b.has { lastSelection = b }
        record("Selection", undo: { sel.restore(b) }, redo: { sel.restore(a) })
        hasSelection = sel.has
        stage?.refreshSelection()
    }

    func selectDown(_ p: CGPoint) {
        guard let sel = ensureSelection(), let d = doc else { return }
        sel.shape = selShape; sel.op = selOp; sel.tolerance = selTolerance
        if selShape == .auto {
            selHist { sel.auto(from: d.layers[d.active].pixels, x: Int(p.x), y: Int(p.y)) }
            return
        }
        selDrag = SelDrag(shape: selShape, p0: p, p1: p, pts: [p])
        stage?.updateOverlay()
    }
    func selectMove(_ p: CGPoint) {
        guard selDrag != nil else { return }
        selDrag?.p1 = p
        if selDrag?.shape == .free { selDrag?.pts.append(p) }
        stage?.updateOverlay()
    }
    func selectUp() {
        guard let dr = selDrag, let sel = ensureSelection() else { return }
        selDrag = nil
        sel.shape = selShape; sel.op = selOp
        switch dr.shape {
        case .free:
            if dr.pts.count >= 3 { selHist { sel.polygon(dr.pts) } }
        case .rect, .ellipse:
            let r = CGRect(x: min(dr.p0.x, dr.p1.x), y: min(dr.p0.y, dr.p1.y), width: abs(dr.p1.x - dr.p0.x), height: abs(dr.p1.y - dr.p0.y))
            if r.width >= 3 && r.height >= 3 { selHist { if dr.shape == .rect { sel.rect(r) } else { sel.ellipse(r) } } }
        case .auto: break
        }
        stage?.updateOverlay()
    }

    func selectNothing() { guard hasSelection, let sel = selection else { return }; selHist { sel.clear() }; say("Selection cleared.") }
    func selectInvert() { guard let sel = ensureSelection() else { return }; selHist { sel.invert() }; say("Selection inverted.") }
    func selectAll() { guard let sel = ensureSelection(), let d = doc else { return }; selHist { sel.op = .replace; sel.rect(CGRect(x: 0, y: 0, width: d.w, height: d.h)) }; say("Everything is selected.") }
    func cycleFeather() {
        let a = [0, 8, 20, 40]
        guard let sel = ensureSelection() else { return }
        let n = a[((a.firstIndex(of: selFeather) ?? 0) + 1) % a.count]
        selHist { sel.setFeather(n) }
        selFeather = n
        say("Feather \(n).")
    }
    func bringBackSelection() {
        guard let sel = ensureSelection() else { return }
        if sel.has { say("A selection is already there."); return }
        guard let last = lastSelection else { say("There is no earlier selection to bring back."); return }
        let b = sel.snapshot()
        sel.restore(last)
        let a = sel.snapshot()
        record("Selection", undo: { sel.restore(b) }, redo: { sel.restore(a) })
        hasSelection = true; selFeather = last.feather
        stage?.refreshSelection(); say("The last selection is back.")
    }

    /// The selected part of the layer on a new layer (the laptop's "From selection").
    func selectionToLayer() {
        guard live == nil, let d = doc, let sel = selection, sel.has else { say("Select something first."); return }
        let src = d.layers[d.active].pixels
        guard d.addLayer() else { say(d.fullNote); return }
        let N = d.layers[d.active]
        N.meta["name"] = "From selection"; N.meta["raw"] = true
        if let img = src.image() { N.pixels.drawUpright(img, in: CGRect(x: 0, y: 0, width: d.w, height: d.h)) }
        if let m = sel.mask.image() { N.pixels.drawUpright(m, in: CGRect(x: 0, y: 0, width: d.w, height: d.h), blend: .destinationIn) }
        recordAdded(N, at: d.active, label: "Layer from selection")
        say("The selection is on its own layer.")
    }

    // MARK: copy, cut, paste

    func clipCopy(cut: Bool) {
        guard live == nil, let d = doc else { return }
        let L = d.layers[d.active]
        guard let tmp = PixelBuffer(w: d.w, h: d.h), let img = L.pixels.image() else { return }
        tmp.drawUpright(img, in: CGRect(x: 0, y: 0, width: d.w, height: d.h))
        if let sel = selection, sel.has, let m = sel.mask.image() { tmp.drawUpright(m, in: CGRect(x: 0, y: 0, width: d.w, height: d.h), blend: .destinationIn) }
        guard let box = tmp.contentBounds(), let part = tmp.image()?.cropping(to: box) else { say("There is nothing here to \(cut ? "cut" : "copy")."); return }
        UIPasteboard.general.image = UIImage(cgImage: part)
        clipOrigin = box.origin
        clipImage = part
        if cut { clearLayer() }
        say(cut ? "Cut." : "Copied.")
    }

    func clipPaste() {
        guard live == nil, let d = doc else { return }
        var img = clipImage, origin = clipOrigin
        if img == nil, let ui = UIPasteboard.general.image?.cgImage {
            img = ui
            origin = CGPoint(x: ((d.w - ui.width) / 2), y: ((d.h - ui.height) / 2))
        }
        guard let pic = img else { say("There is nothing to paste."); return }
        commitTransform()
        guard d.addLayer() else { say(d.fullNote); return }
        let N = d.layers[d.active]
        N.meta["name"] = "Pasted"; N.meta["raw"] = true
        NativeEffects.put(pic, into: N.pixels, x: Double(origin.x), y: Double(origin.y))
        recordAdded(N, at: d.active, label: "Paste")
        enterTransform()
        say("Pasted: move it, then Done.")
    }

    // MARK: transform

    func enterTransform() {
        guard live == nil, transform == nil, let d = doc else { return }
        let L = d.layers[d.active]
        guard d.isShown(L) else { say("This layer is hidden."); return }
        guard let tmp = PixelBuffer(w: d.w, h: d.h), let img = L.pixels.image() else { return }
        tmp.drawUpright(img, in: CGRect(x: 0, y: 0, width: d.w, height: d.h))
        let sel = selection?.has == true ? selection : nil
        if let sel, let m = sel.mask.image() { tmp.drawUpright(m, in: CGRect(x: 0, y: 0, width: d.w, height: d.h), blend: .destinationIn) }
        guard let box = tmp.contentBounds(), let part = tmp.image()?.cropping(to: box) else { say("Nothing to transform on this layer."); return }
        let before = L.pixels.snapshot()
        let snap = sel?.snapshot()
        if let sel, let m = sel.mask.image() { L.pixels.drawUpright(m, in: CGRect(x: 0, y: 0, width: d.w, height: d.h), blend: .destinationOut) }   // the pixels now float; the layer keeps the rest
        else { L.pixels.clear(CGRect(x: 0, y: 0, width: d.w, height: d.h)) }
        transform = NativeTransform(layer: d.active, src: part, box: box, before: before, selBefore: snap)
        transform?.docCentre = CGPoint(x: Double(d.w) / 2, y: Double(d.h) / 2)
        trMode = .free; trActive = true; mode = .transform
        stage?.refreshAll(); stage?.setFloat(transform)
        say("Transform: drag the corners to scale, the green dot to turn, the yellow square to move the pivot.")
    }

    func toggleTransform() { if trActive { commitTransform() } else { enterTransform() } }

    func setTransformMode(_ m: NativeTransform.Mode) {
        guard let t = transform else { return }
        if t.mode == .distort || t.mode == .warp, m == .free || m == .uni { say("Back to the original shape.") }
        else if t.mode == .distort, m == .warp { say("Warp starts from the distorted shape.") }
        t.setMode(m); trMode = t.mode
        stage?.setFloat(t)
    }

    func transformFlip(horizontal: Bool) {
        guard let t = transform else { return }
        if !t.flip(horizontal: horizontal) { say("Flip before you warp.") }
        stage?.refreshFloat()
    }
    func transformTurn45() {
        guard let t = transform else { return }
        if !t.turn45() { say("Fit and Rotate 45 work before Distort or Warp.") }
        stage?.refreshFloat()
    }
    func transformFit() {
        guard let t = transform, let d = doc else { return }
        if !t.fit(docW: d.w, docH: d.h) { say("Fit and Rotate 45 work before Distort or Warp.") }
        stage?.refreshFloat()
    }
    func transformReset() { transform?.reset(); trMode = .free; if let t = transform { stage?.setFloat(t) } }

    func commitTransform() {
        guard let t = transform, let d = doc else { return }
        transform = nil; trActive = false; mode = .draw
        let L = d.layers[t.layer]
        let px = L.pixels
        t.paint(into: px.ctx, fine: true)
        L.meta["raw"] = true
        let before = t.before, after = px.snapshot()
        var selA: NativeSelection.Snap?
        if let sel = selection, sel.has {
            // the selection goes where the picture went (for the scale, rotate and flip transforms; a distort or warp clears it)
            if t.isPlain, let mask = PixelBuffer(w: d.w, h: d.h) {
                mask.ctx.saveGState()
                mask.ctx.translateBy(x: t.cx, y: t.cy); mask.ctx.rotate(by: t.rot); mask.ctx.scaleBy(x: t.fx * t.sx, y: t.fy * t.sy); mask.ctx.translateBy(x: -Double(t.home.x), y: -Double(t.home.y))
                if let si = sel.sharp.image() {
                    mask.ctx.translateBy(x: 0, y: Double(d.h)); mask.ctx.scaleBy(x: 1, y: -1)
                    mask.ctx.draw(si, in: CGRect(x: 0, y: 0, width: d.w, height: d.h))
                }
                mask.ctx.restoreGState()
                sel.sharp.clear(CGRect(x: 0, y: 0, width: d.w, height: d.h))
                if let mi = mask.image() { sel.sharp.drawUpright(mi, in: CGRect(x: 0, y: 0, width: d.w, height: d.h)) }
                sel.has = true; sel.refreshSoft(); selA = sel.snapshot()
            } else { sel.clear(); selA = nil }
        }
        let sb = t.selBefore, sel = selection
        record("Transform", undo: { px.restore(before); if let sb { sel?.restore(sb) } else if selA != nil { sel?.clear() } },
               redo: { px.restore(after); if let selA { sel?.restore(selA) } else if sb != nil { sel?.clear() } })
        hasSelection = sel?.has ?? false
        stage?.setFloat(nil); stage?.refreshAll(); stage?.refreshSelection()
        say("Transform applied.")
    }

    func cancelTransform() {
        guard let t = transform, let d = doc else { return }
        transform = nil; trActive = false; mode = .draw
        d.layers[t.layer].pixels.restore(t.before)
        stage?.setFloat(nil); stage?.refreshAll()
        say("Transform cancelled.")
    }
}

extension PixelBuffer {
    /// The box that holds every pixel with some alpha, or nil when the buffer is empty.
    func contentBounds() -> CGRect? {
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        for y in 0..<h {
            let row = ptr + y * w * 4
            var first = -1, last = -1
            for x in 0..<w where row[x * 4 + 3] != 0 { if first < 0 { first = x }; last = x }
            if first >= 0 { x0 = min(x0, first); x1 = max(x1, last); y0 = min(y0, y); y1 = y }
        }
        guard x1 >= 0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
}
