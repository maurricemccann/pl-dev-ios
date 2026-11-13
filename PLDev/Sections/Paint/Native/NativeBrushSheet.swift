import SwiftUI
import UIKit

/// A sample stroke for the brush list: an S curve with a pressure swell, drawn by the same stroker and stamper as the canvas
/// (the laptop's `preview`). A brush that cannot draw shows an empty box, never a crash.
@MainActor enum NativeBrushPreview {
    private static var cache: [String: UIImage] = [:]

    static func image(_ B: Brush, color: String, color2: String, size: Double = 22, w: Int = 300, h: Int = 80) -> UIImage? {
        let key = "\(B.id)|\(color)|\(color2)|\(size)"
        if let c = cache[key] { return c }
        guard let buf = PixelBuffer(w: w, h: h) else { return nil }
        let W = Double(w), H = Double(h)
        var pts: [(Double, Double, Double)] = []
        for i in 0...60 { let u = Double(i) / 60; pts.append((W * 0.08 + u * W * 0.84, H / 2 + sin(u * 6.2) * H * 0.26, 0.15 + sin(u * .pi) * 0.85)) }
        var total = 0.0
        for i in 1..<pts.count { total += hypot(pts[i].0 - pts[i - 1].0, pts[i].1 - pts[i - 1].1) }
        var st = NativeStroker(B, size: size, total: total)
        func lay(_ dabs: [Dab]) {
            for d in dabs {
                if d.span > 0 { NativeStamp.drawFill(buf.ctx, B, color: B.t("gapFillColor").isEmpty ? color2 : B.t("gapFillColor"), size: size, d) }
                else { NativeStamp.drawWithTwin(buf.ctx, B, color: color, color2: color2, size: size, d) }
            }
        }
        for (i, q) in pts.enumerated() { lay(st.add(x: q.0, y: q.1, p: q.2, t: Double(i) * 16)) }
        lay(st.flush())
        NativeStamp.applyGrain(buf.ctx, B, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let img = buf.ctx.makeImage() else { return nil }   // a copy: the buffer goes away with this function
        let ui = UIImage(cgImage: img)
        cache[key] = ui
        return ui
    }
}

/// The brush list: the packs, each brush with its sample stroke. A tap picks it.
struct NativeBrushSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(NativeToolkit.packs) { pack in
                    Section(pack.name) {
                        ForEach(pack.brushes) { b in
                            Button { canvas.brush = b; canvas.say("\(b.name).") ; dismiss() } label: {
                                HStack(spacing: 12) {
                                    Group {
                                        if let ui = NativeBrushPreview.image(b, color: UIColor(canvas.color).hex, color2: UIColor(canvas.color2).hex) {
                                            Image(uiImage: ui).resizable().scaledToFit()
                                        } else { Color.clear }
                                    }
                                    .frame(width: 150, height: 40)
                                    .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.name).foregroundStyle(.primary)
                                        if let n = b.note { Text(n).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                    Spacer(minLength: 0)
                                    if b.id == canvas.brush.id { Image(systemName: "checkmark").foregroundStyle(Wallpaper.line) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Brushes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
