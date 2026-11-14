import CoreGraphics
import Foundation
import SwiftUI
import UIKit

extension NativeDoc {
    /// A phone has less memory for pictures than a laptop, so the layers it holds depend on the canvas size (his handbook, ch. 10: "about seven
    /// at 2048 x 1536"). About 100 MB of layer pixels: seven at 2048 x 1536, five at 2048 x 2048, twenty-three at 1024 x 1024; never under 2 or over 40.
    static func layerCap(w: Int, h: Int) -> Int { max(2, min(40, 100_000_000 / max(1, w * h * 4))) }
    /// What it says when the cap is reached.
    var fullNote: String { "This canvas holds \(NativeDoc.layerCap(w: w, h: h)) layers at this size. Merge some layers, or start smaller." }
    /// A new empty layer above the active one; inside a group when the layer under it is in one.
    func addLayer() -> Bool {
        guard layers.count < NativeDoc.layerCap(w: w, h: h), let px = PixelBuffer(w: w, h: h) else { return false }
        layerSeq += 1
        var meta = NativeLayer.defaultMeta("Layer \(layerSeq)")
        meta["grp"] = layers[active].meta["grp"] as? Int ?? 0
        meta["id"] = freshLayerID()
        layers.insert(NativeLayer(meta: meta, maskPx: nil, pixels: px), at: active + 1); active += 1
        return true
    }
    func duplicateActive() -> Bool {
        guard layers.count < NativeDoc.layerCap(w: w, h: h), let px = PixelBuffer(w: w, h: h) else { return false }
        let src = layers[active]
        memcpy(px.ptr, src.pixels.ptr, w * h * 4)
        var meta = src.meta; meta["name"] = String((src.name + " copy").prefix(40)); meta["raw"] = true; meta["id"] = freshLayerID()
        var mk: PixelBuffer?
        if let m = src.maskPx, let nb = PixelBuffer(w: w, h: h) { memcpy(nb.ptr, m.ptr, w * h * 4); mk = nb }
        layers.insert(NativeLayer(meta: meta, maskPx: mk, pixels: px), at: active + 1); active += 1
        return true
    }
}

/// Layers, groups and masks, each undoable. A structural change keeps the layer list before and after (the layer objects live on in the
/// history, so a deleted layer comes back whole).
extension NativeCanvasModel {
    struct StructSnap { let layers: [NativeLayer]; let metas: [[String: Any]]; let groups: [[String: Any]]; let active: Int }

    func structSnap() -> StructSnap? {
        guard let d = doc else { return nil }
        return StructSnap(layers: d.layers, metas: d.layers.map(\.meta), groups: d.groups, active: d.active)
    }
    func structRestore(_ s: StructSnap) {
        guard let d = doc else { return }
        d.layers = s.layers
        for (i, l) in d.layers.enumerated() { l.meta = s.metas[i] }
        d.groups = s.groups; d.active = s.active
        maskEditing = false; selectedGroup = 0
    }

    /// Runs a layer edit and records it. `pixels` lists layers whose pixels the edit changes, to be kept before and after.
    func structDo(_ label: String, pixels: [NativeLayer] = [], _ fn: () -> Bool) {
        guard live == nil, !trActive, let before = structSnap() else { return }
        let pxBefore = pixels.map { $0.pixels.snapshot() }
        guard fn(), let after = structSnap() else { return }
        let pxAfter = pixels.map { $0.pixels.snapshot() }
        record(label, structural: true,
               undo: { [weak self] in for (i, l) in pixels.enumerated() { l.pixels.restore(pxBefore[i]) }; self?.structRestore(before) },
               redo: { [weak self] in for (i, l) in pixels.enumerated() { l.pixels.restore(pxAfter[i]) }; self?.structRestore(after) })
        stage?.rebuild()
    }

    func recordAdded(_ n: NativeLayer, at i: Int, label: String) {
        guard let d = doc else { return }
        record(label, structural: true,
               undo: { d.layers.removeAll { $0 === n }; d.active = max(0, min(d.layers.count - 1, i - 1)) },
               redo: { if !d.layers.contains(where: { $0 === n }) { d.layers.insert(n, at: min(i, d.layers.count)) }; d.active = i })
        stage?.rebuild()
    }

    func setActive(_ i: Int) {
        guard live == nil, let d = doc, d.layers.indices.contains(i) else { return }
        commitTransform()
        d.active = i; selectedGroup = 0; maskEditing = false
        syncFlags(); stage?.rebuild(); markChanged()
    }

    func addLayer() {
        guard let d = doc else { return }
        structDo("Layer added") { d.addLayer() ? true : { say(d.fullNote); return false }() }
        if !layerRows.isEmpty { say("Layer added.") }
    }
    func duplicateLayer() { guard let d = doc else { return }; structDo("Layer duplicated") { d.duplicateActive() } }
    func deleteLayer() {
        guard let d = doc else { return }
        if selectedGroup != 0 { deleteGroup(); return }
        structDo("Layer deleted") {
            guard d.layers.count > 1 else { say("Keep at least one layer."); return false }
            d.layers.remove(at: d.active); d.active = min(d.active, d.layers.count - 1); tidyGroups(d); return true
        }
    }
    func tidyGroups(_ d: NativeDoc) {
        d.groups = d.groups.filter { g in d.layers.contains { ($0.meta["grp"] as? Int ?? 0) == (g["id"] as? Int ?? -1) } }
    }

    func moveLayer(_ n: Int) {
        guard let d = doc else { return }
        if selectedGroup != 0 { moveGroup(n); return }
        structDo("Layer moved") {
            let i = d.active, j = i + n
            guard d.layers.indices.contains(j) else { return false }
            let A = d.layers[i], B = d.layers[j]
            let gA = A.meta["grp"] as? Int ?? 0, gB = B.meta["grp"] as? Int ?? 0
            let join = gA != gB && gB != 0   // stepping onto a group's edge goes into the group where it stands; from a group onto a plain layer goes out of it
            if !join { d.layers.swapAt(i, j); d.active = j }
            A.meta["grp"] = gA == gB ? gA : gB
            tidyGroups(d)
            return true
        }
    }

    /// Reorders by dragging in the list: `from` and `to` are positions in the layer list.
    func reorderLayer(from: Int, to: Int) {
        guard let d = doc, d.layers.indices.contains(from), d.layers.indices.contains(to), from != to else { return }
        structDo("Layer moved") {
            let l = d.layers.remove(at: from)
            d.layers.insert(l, at: to)
            d.active = to
            return true
        }
    }

    // MARK: properties

    func setLayer(_ key: String, _ value: Any, at i: Int? = nil, history: Bool = true) {
        guard live == nil, let d = doc else { return }
        let k = i ?? d.active
        guard d.layers.indices.contains(k) else { return }
        let l = d.layers[k]
        let old = l.meta[key]
        l.meta[key] = value
        if history {
            let was = old
            record("Layer", structural: true,
                   undo: { if let was { l.meta[key] = was } else { l.meta.removeValue(forKey: key) } },
                   redo: { l.meta[key] = value })
        }
        syncFlags(); stage?.rebuild(); markChanged()
    }

    /// A slider changes a property live, and one history step is recorded when the finger lifts.
    func beginLayerEdit(_ key: String, at i: Int) {
        guard let d = doc, d.layers.indices.contains(i) else { return }
        propBefore = (i, key, d.layers[i].meta[key])
    }
    func endLayerEdit() {
        guard let (i, key, was) = propBefore, let d = doc, d.layers.indices.contains(i) else { propBefore = nil; return }
        propBefore = nil
        let l = d.layers[i], now = l.meta[key]
        record("Layer", structural: true, undo: { if let was { l.meta[key] = was } }, redo: { if let now { l.meta[key] = now } })
    }

    func toggleVisible(_ i: Int) { guard let d = doc, d.layers.indices.contains(i) else { return }; setLayer("vis", !d.layers[i].visible, at: i) }

    /// Hold the eye of a layer: only that layer shows; hold it again and everything comes back as it was.
    func soloLayer(_ i: Int) {
        guard let d = doc, d.layers.indices.contains(i) else { return }
        let solo = d.layers[i].visible && d.layers.enumerated().allSatisfy { $0.offset == i || !$0.element.visible }
        if solo, let prev = soloPrev, prev.count == d.layers.count {
            for (j, l) in d.layers.enumerated() { l.meta["vis"] = prev[j] }
            soloPrev = nil; say("Every layer is back as it was.")
        } else {
            soloPrev = d.layers.map(\.visible)
            for (j, l) in d.layers.enumerated() { l.meta["vis"] = j == i }
            say("Solo: only this layer shows. Hold its eye again to bring the rest back.")
        }
        syncFlags(); stage?.rebuild(); markChanged()
    }

    func toggleClip() {
        guard let d = doc else { return }
        let L = d.layers[d.active]
        if d.clipBase(of: d.active) == nil && L.meta["clip"] as? Bool != true && d.active == 0 { say("A clipping layer needs a layer below it."); return }
        setLayer("clip", !(L.meta["clip"] as? Bool ?? false))
    }
    func toggleRef() {
        guard let d = doc else { return }
        let on = !(d.layers[d.active].meta["ref"] as? Bool ?? false)
        structDo("Reference layer") {
            for l in d.layers { l.meta["ref"] = false }
            d.layers[d.active].meta["ref"] = on
            return true
        }
        say(on ? "Reference layer: ColorDrop fills stop at this layer's lines." : "Reference layer off.")
    }
    func toggleLayerAssist(_ i: Int) {
        guard let d = doc, d.layers.indices.contains(i) else { return }
        let cur = (d.layers[i].meta["assist"] as? Bool) ?? assist
        setLayer("assist", !cur, at: i)
        say("Assisted drawing \(!cur ? "on" : "off") for \(d.layers[i].name).")
    }

    // MARK: groups

    var selGroupRecord: [String: Any]? { doc?.groups.first { ($0["id"] as? Int) == selectedGroup } }

    func selectGroup(_ id: Int) { selectedGroup = selectedGroup == id ? 0 : id; maskEditing = false; syncFlags() }

    func groupButton() {
        guard let d = doc else { return }
        let activeGroup = d.layers[d.active].meta["grp"] as? Int ?? 0
        let gid = selectedGroup != 0 ? selectedGroup : activeGroup
        structDo(gid != 0 ? "Ungroup" : "Group") {
            if gid != 0, let g = d.group(gid) {
                let gv = g["vis"] as? Bool ?? true, go = (g["op"] as? Double) ?? Double(g["op"] as? Int ?? 1)
                for l in d.layers where (l.meta["grp"] as? Int ?? 0) == gid {
                    l.meta["grp"] = 0; l.meta["vis"] = l.visible && gv; l.meta["op"] = l.opacity * go
                }
                d.groups.removeAll { ($0["id"] as? Int) == gid }
                selectedGroup = 0
                return true
            }
            d.groupSeq += 1
            d.groups.append(["id": d.groupSeq, "name": "Group \(d.groupSeq)", "open": true, "vis": true, "op": 1, "blend": "source-over"])
            d.layers[d.active].meta["grp"] = d.groupSeq
            return true
        }
    }

    private func memberRange(_ gid: Int) -> ClosedRange<Int>? {
        guard let d = doc, let lo = d.layers.firstIndex(where: { ($0.meta["grp"] as? Int ?? 0) == gid }) else { return nil }
        var hi = lo
        while hi + 1 < d.layers.count, (d.layers[hi + 1].meta["grp"] as? Int ?? 0) == gid { hi += 1 }
        return lo...hi
    }

    func setGroup(_ id: Int, _ key: String, _ value: Any, history: Bool = true) {
        guard let d = doc, let k = d.groups.firstIndex(where: { ($0["id"] as? Int) == id }) else { return }
        let was = d.groups[k][key]
        d.groups[k][key] = value
        if history {
            record("Group", structural: true,
                   undo: { if let i = d.groups.firstIndex(where: { ($0["id"] as? Int) == id }) { if let was { d.groups[i][key] = was } else { d.groups[i].removeValue(forKey: key) } } },
                   redo: { if let i = d.groups.firstIndex(where: { ($0["id"] as? Int) == id }) { d.groups[i][key] = value } })
        }
        syncFlags(); stage?.rebuild(); markChanged()
    }

    func mergeGroup() {
        guard let d = doc, selectedGroup != 0, let g = selGroupRecord, let r = memberRange(selectedGroup), let merged = d.compositeBuffer(includeBackground: false, only: r.lowerBound..<(r.upperBound + 1)) else { return }
        let old = Array(d.layers[r])
        structDo("Merge group") {
            guard let px = PixelBuffer(w: d.w, h: d.h) else { return false }
            memcpy(px.ptr, merged.ptr, d.w * d.h * 4)
            var meta = NativeLayer.defaultMeta(String((g["name"] as? String ?? "Group").prefix(24)))
            meta["raw"] = true
            let M = NativeLayer(meta: meta, maskPx: nil, pixels: px)
            d.layers.replaceSubrange(r, with: [M])
            d.groups.removeAll { ($0["id"] as? Int) == selectedGroup }
            d.active = r.lowerBound; selectedGroup = 0
            return true
        }
        _ = old
        say("Merged the group into one layer.")
    }
    func deleteGroup() {
        guard let d = doc, selectedGroup != 0, let r = memberRange(selectedGroup) else { return }
        structDo("Group deleted") {
            if r.count >= d.layers.count { say("Keep at least one layer."); return false }
            d.layers.removeSubrange(r)
            d.groups.removeAll { ($0["id"] as? Int) == selectedGroup }
            d.active = max(0, min(r.lowerBound, d.layers.count - 1)); selectedGroup = 0
            return true
        }
    }
    func moveGroup(_ n: Int) {
        guard let d = doc, let r = memberRange(selectedGroup) else { return }
        structDo("Group moved") {
            if n > 0 ? r.upperBound >= d.layers.count - 1 : r.lowerBound == 0 { return false }
            let seg = Array(d.layers[r])
            d.layers.removeSubrange(r)
            // jump over the neighbouring layer (or its whole group)
            var at = n > 0 ? r.lowerBound + 1 : r.lowerBound - 1
            let nb = d.layers.indices.contains(at) ? d.layers[at] : nil
            if let nb, let ng = nb.meta["grp"] as? Int, ng != 0 {
                if n > 0 { while at + 1 < d.layers.count, (d.layers[at + 1].meta["grp"] as? Int ?? 0) == ng { at += 1 }; at += 1 }
                else { while at - 1 >= 0, (d.layers[at - 1].meta["grp"] as? Int ?? 0) == ng { at -= 1 } }
            } else if n > 0 { at += 1 }
            d.layers.insert(contentsOf: seg, at: max(0, min(at, d.layers.count)))
            d.active = d.layers.firstIndex { $0 === seg.last } ?? 0
            return true
        }
    }

    // MARK: masks

    func maskButton() {
        guard live == nil, let d = doc else { return }
        let L = d.layers[d.active]
        if L.maskPx == nil {
            guard let m = PixelBuffer(w: d.w, h: d.h) else { say("Not made. This phone has no room for a mask."); return }
            m.ctx.setFillColor(CGColor(gray: 1, alpha: 1)); m.ctx.fill(CGRect(x: 0, y: 0, width: d.w, height: d.h))
            L.maskPx = m
            maskEditing = true
            record("Mask added", structural: true, undo: { [weak self] in L.maskPx = nil; self?.maskEditing = false }, redo: { [weak self] in L.maskPx = m; self?.maskEditing = true })
            stage?.rebuild()
            say("Mask added: paint white to show, black to hide.")
        } else {
            maskEditing.toggle()
            say(maskEditing ? "Painting the mask." : "Painting the layer.")
        }
        syncFlags()
    }
    func deleteMask() {
        guard live == nil, let d = doc, let m = d.layers[d.active].maskPx else { return }
        let L = d.layers[d.active]
        L.maskPx = nil; maskEditing = false
        record("Mask deleted", structural: true, undo: { L.maskPx = m }, redo: { L.maskPx = nil })
        stage?.rebuild(); syncFlags()
    }
    /// Bakes the mask into the layer's pixels and removes the mask.
    func applyMask() {
        guard let d = doc, let m = d.layers[d.active].maskPx, let mi = m.image() else { return }
        let L = d.layers[d.active]
        let before = L.pixels.snapshot()
        L.pixels.drawUpright(mi, in: CGRect(x: 0, y: 0, width: d.w, height: d.h), blend: .destinationIn)
        let after = L.pixels.snapshot()
        L.maskPx = nil; maskEditing = false
        record("Mask applied", structural: true, undo: { L.pixels.restore(before); L.maskPx = m }, redo: { L.pixels.restore(after); L.maskPx = nil })
        stage?.rebuild(); syncFlags()
        say("The mask is part of the layer now.")
    }
    func invertMask() {
        guard let d = doc, let m = d.layers[d.active].maskPx else { return }
        let before = m.snapshot()
        let n = d.w * d.h
        for i in 0..<n { let a = 255 - m.ptr[i * 4 + 3]; m.ptr[i * 4] = a; m.ptr[i * 4 + 1] = a; m.ptr[i * 4 + 2] = a; m.ptr[i * 4 + 3] = a }
        let after = m.snapshot()
        record("Mask inverted", structural: false, undo: { m.restore(before) }, redo: { m.restore(after) })
        stage?.rebuild()
    }

    // MARK: merge, clear

    func mergeDown() {
        guard live == nil, let d = doc else { return }
        if selectedGroup != 0 { mergeGroup(); return }
        let i = d.active
        guard i > 0 else { say("There is no layer below to merge into."); return }
        let L = d.layers[i], B = d.layers[i - 1]
        structDo("Merge down", pixels: [B]) {
            guard let img = d.effectiveImage(of: i), let tmp = PixelBuffer(w: d.w, h: d.h) else { return false }
            let full = CGRect(x: 0, y: 0, width: d.w, height: d.h)
            let mode = L.meta["blend"] as? String ?? "source-over"
            if mode.hasPrefix("x-") {
                tmp.drawUpright(img, in: full)
                NativeBlendCPU.apply(mode: mode, into: B.pixels, from: UnsafePointer(tmp.ptr), opacity: L.opacity)
            } else {
                B.pixels.drawUpright(img, in: full, alpha: CGFloat(L.opacity), blend: NativeBlend.mode(mode).cg ?? .normal)
            }
            B.meta["raw"] = true
            d.layers.remove(at: i); d.active = i - 1; maskEditing = false
            tidyGroups(d)
            return true
        }
    }

    /// Clears the layer, or only the selected part of it.
    func clearLayer() {
        guard live == nil, let d = doc else { return }
        let L = d.layers[d.active]
        let before = L.pixels.snapshot()
        if let sel = selection, sel.has, let m = sel.mask.image() { L.pixels.drawUpright(m, in: CGRect(x: 0, y: 0, width: d.w, height: d.h), blend: .destinationOut); L.meta["raw"] = true }
        else { L.pixels.clear(CGRect(x: 0, y: 0, width: d.w, height: d.h)) }
        let after = L.pixels.snapshot()
        var gone: [Int] = []
        if selection?.has != true { for (k, r) in d.log.enumerated() where (r["layer"] as? Int) == d.active + 1 && (r["dead"] as? Bool) != true { d.log[k]["dead"] = true; gone.append(k) } }
        record("Clear layer", undo: { L.pixels.restore(before); for k in gone where d.log.indices.contains(k) { d.log[k]["dead"] = false } },
               redo: { L.pixels.restore(after); for k in gone where d.log.indices.contains(k) { d.log[k]["dead"] = true } })
        stage?.refreshAll()
    }

    /// Fills the selection (or the layer) with the colour.
    func fillSelection() {
        guard live == nil, let d = doc else { return }
        let L = d.layers[d.active]
        let before = L.pixels.snapshot()
        let c = L.pixels.ctx
        c.saveGState()
        selection?.clip(c)
        c.setFillColor(UIColor(color).cgColor)
        if L.alphaLock { c.setBlendMode(.sourceAtop) }
        c.fill(CGRect(x: 0, y: 0, width: d.w, height: d.h))
        c.restoreGState()
        L.meta["raw"] = true
        let after = L.pixels.snapshot()
        record("Fill", undo: { L.pixels.restore(before) }, redo: { L.pixels.restore(after) })
        stage?.refreshAll()
        say("Filled.")
    }

    // MARK: the picture itself

    func setBackground(visible: Bool? = nil, hex: String? = nil) {
        guard let d = doc else { return }
        let ov = d.bgVis, oc = d.bg
        if let visible { d.bgVis = visible }
        if let hex { d.bg = hex }
        let nv = d.bgVis, nc = d.bg
        record("Background", structural: true, undo: { d.bgVis = ov; d.bg = oc }, redo: { d.bgVis = nv; d.bg = nc })
        stage?.rebuild()
    }

    func flipCanvas(horizontal: Bool) {
        guard live == nil, let d = doc else { return }
        var before: [Data] = [], masks: [Data?] = []
        for l in d.layers { before.append(l.pixels.snapshot()); masks.append(l.maskPx?.snapshot()) }
        func flip(_ b: PixelBuffer) {
            guard let img = b.image(), let t = PixelBuffer(w: b.w, h: b.h) else { return }
            t.ctx.saveGState()
            if horizontal { t.ctx.translateBy(x: Double(b.w), y: 0); t.ctx.scaleBy(x: -1, y: 1) } else { t.ctx.translateBy(x: 0, y: Double(b.h)); t.ctx.scaleBy(x: 1, y: -1) }
            t.drawUpright(img, in: CGRect(x: 0, y: 0, width: b.w, height: b.h))
            t.ctx.restoreGState()
            memcpy(b.ptr, t.ptr, b.w * b.h * 4)
        }
        for l in d.layers { flip(l.pixels); if let m = l.maskPx { flip(m) } }
        var after: [Data] = [], aMasks: [Data?] = []
        for l in d.layers { after.append(l.pixels.snapshot()); aMasks.append(l.maskPx?.snapshot()) }
        let layers = d.layers
        record("Flip canvas", structural: true,
               undo: { for (i, l) in layers.enumerated() { l.pixels.restore(before[i]); if let m = masks[i] { l.maskPx?.restore(m) } } },
               redo: { for (i, l) in layers.enumerated() { l.pixels.restore(after[i]); if let m = aMasks[i] { l.maskPx?.restore(m) } } })
        stage?.rebuild()
    }
}
