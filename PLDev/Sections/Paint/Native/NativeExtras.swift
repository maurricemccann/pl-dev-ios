import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The smaller things the laptop does that sit between the big ones: a ghost copy behind a layer, corner copies for a tile, the 3 x 3 repeat
/// check, Passes (each stroke takes the next colour of a palette), Name It, and Stacks of works.
extension NativeCanvasModel {
    /// A faint, softened copy of the layer's marks behind it, the way text sits over a ghost weave in his plates.
    func ghostBelow() {
        guard live == nil, let d = doc, d.layers.indices.contains(d.active), d.layers.count < NativeDoc.layerCap(w: d.w, h: d.h) else { say(doc?.fullNote ?? "No picture is open."); return }
        let src = d.layers[d.active]
        structDo("Ghost copy") {
            guard let soft = NativeAdjust.gauss(src.pixels, 2), let px = PixelBuffer(w: d.w, h: d.h), let img = soft.image() else { return false }
            px.drawUpright(img, in: CGRect(x: 0, y: 0, width: d.w, height: d.h))
            var meta = NativeLayer.defaultMeta(String("Ghost of \(src.name.prefix(14))"))
            meta["grp"] = src.meta["grp"] as? Int ?? 0; meta["id"] = d.freshLayerID(); meta["op"] = 0.22; meta["raw"] = true
            d.layers.insert(NativeLayer(meta: meta, maskPx: nil, pixels: px), at: d.active)
            d.active += 1
            return true
        }
        say("A ghost copy sits behind this layer, faint.")
    }

    /// A copy of the layer slides half way round: a motif in the middle gains its four quarter copies in the corners.
    func cornerCopies() {
        guard live == nil, let d = doc, d.layers.indices.contains(d.active), d.layers.count < NativeDoc.layerCap(w: d.w, h: d.h) else { say(doc?.fullNote ?? "No picture is open."); return }
        let srcName = d.layers[d.active].name
        structDo("Corner copies") {
            guard d.duplicateActive() else { return false }
            let L = d.layers[d.active]
            L.meta["name"] = String("\(srcName) corners".prefix(40)); L.meta["raw"] = true; L.meta["id"] = d.freshLayerID()
            let W = Double(d.w), H = Double(d.h)
            for b in [Optional(L.pixels), L.maskPx].compactMap({ $0 }) {
                guard let img = b.image(), let t = PixelBuffer(w: b.w, h: b.h) else { continue }
                for dx in [-W / 2, W / 2] { for dy in [-H / 2, H / 2] {
                    t.ctx.saveGState(); t.ctx.translateBy(x: dx, y: dy)
                    t.drawUpright(img, in: CGRect(x: -dx, y: -dy, width: W, height: H))
                    t.ctx.restoreGState()
                } }
                memcpy(b.ptr, t.ptr, b.w * b.h * 4)
            }
            if tile == .off { tile = .both }
            return true
        }
        say("A copy slid half way round: the corners now hold quarter copies of the middle. Draw into the gaps; wrapping is on.")
    }

    /// Passes: each stroke takes the next colour of the chosen palette, in order.
    func nextPassColour() {
        let pals = NativeToolkit.palettes
        guard passPalette >= 0, pals.indices.contains(passPalette), !pals[passPalette].colors.isEmpty else { return }
        let cols = pals[passPalette].colors
        setColour(hex: cols[passIndex % cols.count]); passIndex += 1
    }
}

/// The picture three by three, so a seam shows.
struct NativeRepeatSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let image {
                    Canvas { c, size in
                        let side = min(size.width, size.height) / 3
                        let ratio = image.size.width / max(1, image.size.height)
                        let tw = ratio >= 1 ? side : side * ratio, th = ratio >= 1 ? side / ratio : side
                        let ox = (size.width - tw * 3) / 2, oy = (size.height - th * 3) / 2
                        let img = Image(uiImage: image)
                        for i in 0..<3 { for j in 0..<3 { c.draw(img, in: CGRect(x: ox + Double(i) * tw, y: oy + Double(j) * th, width: tw + 0.5, height: th + 0.5)) } }
                    }
                    .aspectRatio(1, contentMode: .fit)
                } else { PLLoader() }
                Text("Nine copies side by side. Look along the lines where they meet: if you can see where one copy ends and the next begins, slide the picture half way round again and fill that seam.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
            .navigationTitle("Check the repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if let d = canvas.doc, let b = d.compositeBuffer(includeBackground: true), let i = b.image() { image = UIImage(cgImage: i) }
            }
        }
    }
}

/// Name It: a suggestion from his own words (the qualities he pairs with his piece names), and the name itself.
struct NativeRenameSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $text).focused($focus).submitLabel(.done).onSubmit { save() }
                    Button { text = Self.suggestion() } label: { Label("A name from my words", systemImage: "sparkles") }
                } footer: { Text("Offers a quality he names (Elegance, Mystery, Resilience…) with today's date. Tap again for another.") }
            }
            .navigationTitle("Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { text = canvas.name; focus = true }
        }
        .presentationDetents([.height(260)])
    }
    private func save() { canvas.rename(text); dismiss() }
    static func suggestion() -> String {
        let q = (NativeToolkit.raw["names"] as? [String: Any])?["qualities"] as? [String] ?? ["ELEGANCE", "MYSTERY", "RESILIENCE", "ARTISTRY", "DEFIANCE"]
        let f = DateFormatter(); f.dateFormat = "MM-dd"
        return "\(q.randomElement() ?? "PRESENCE") \(f.string(from: .now))"
    }
}

extension NativeCanvasModel {
    /// Puts a work in a stack (a name), or takes it out (nil). The next sync carries it to the laptop.
    func setStack(id: String, name: String?) {
        var ix = NativeStore.loadIndex()
        guard let k = ix.list.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { ix.list[k]["stack"] = String(n.prefix(24)) } else { ix.list[k].removeValue(forKey: "stack") }
        ix.list[k]["updated"] = Date().timeIntervalSince1970 * 1000
        try? NativeStore.saveIndex(ix)
        onChange?()
    }
}
