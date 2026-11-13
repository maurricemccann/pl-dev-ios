import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A sample stroke for the brush list: an S curve with a pressure swell, drawn by the same stroker and stamper as the canvas
/// (the laptop's `preview`). A brush that cannot draw shows an empty box, never a crash.
@MainActor enum NativeBrushPreview {
    private static var cache: [String: UIImage] = [:]

    static func image(_ B: Brush, color: String, color2: String, size: Double = 22, w: Int = 300, h: Int = 80, cached: Bool = true) -> UIImage? {
        let key = "\(B.id)|\(color)|\(color2)|\(size)|\(w)"
        if cached, let c = cache[key] { return c }
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
        if cached { if cache.count > 300 { cache.removeAll() }; cache[key] = ui }
        return ui
    }
}

/// The brush list: the packs and his own brushes (Mine), each with its sample stroke. A tap picks it; touch and hold edits, copies or removes.
struct NativeBrushSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var importing = false
    @State private var markName = ""
    @State private var askMark = false
    @State private var shareURL: URL?
    @State private var message: String?
    @State private var tick = 0

    var body: some View {
        NavigationStack {
            List {
                if let m = message { Section { ResultLine(text: m) } }
                ForEach(packs) { pack in
                    Section(pack.name) {
                        ForEach(pack.brushes.filter(matches)) { b in
                            Button { canvas.selectBrush(b); canvas.tool = canvas.tool == .smudge ? .paint : canvas.tool; if canvas.tool == .erase { canvas.tool = .paint }; canvas.say("\(b.name)."); dismiss() } label: { row(b) }
                                .contextMenu {
                                    Button { canvas.selectBrush(b); dismiss(); canvas.panel = .studio } label: { Label("Edit in Brush Studio", systemImage: "slider.horizontal.3") }
                                    Button { copyToMine(b) } label: { Label("Copy to Mine", systemImage: "plus.square.on.square") }
                                    if b.pack == "Mine" { Button(role: .destructive) { NativeMine.remove(b.id); tick += 1 } label: { Label("Delete", systemImage: "trash") } }
                                }
                        }
                    }
                }
                Section {
                    Toggle("Brushes bring their own colours", isOn: $canvas.brushColors)
                } footer: { Text("With this on, choosing a brush also chooses the colours it was made with.") }
                Section("More") {
                    Button { askMark = true } label: { Label("Make a brush from this layer", systemImage: "stamp") }
                    Button { importing = true } label: { Label("Import a brush pack", systemImage: "square.and.arrow.down") }
                    Button { exportPack() } label: { Label("Export \"Mine\" as a pack", systemImage: "square.and.arrow.up") }.disabled(NativeMine.brushes.isEmpty)
                }
            }
            .id(tick)
            .searchable(text: $query, prompt: "Find a brush")
            .navigationTitle("Brushes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss(); canvas.panel = .studio } label: { Label("Brush Studio", systemImage: "slider.horizontal.3") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in importPack(r) }
            .alert("Name the brush", isPresented: $askMark) {
                TextField("My mark", text: $markName)
                Button("Make it") { makeFromLayer(markName.isEmpty ? "My mark" : markName); markName = "" }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The layer becomes a stamp: tap to place it, Size sets how big.") }
            .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { s in ShareSheet(items: [s.url]) }
        }
    }

    private struct ShareItem: Identifiable { let url: URL; var id: String { url.path } }
    private var packs: [NativeToolkit.Pack] { NativeMine.all }
    private func matches(_ b: Brush) -> Bool { query.isEmpty || b.name.lowercased().contains(query.lowercased()) || (b.note ?? "").lowercased().contains(query.lowercased()) }

    private func row(_ b: Brush) -> some View {
        HStack(spacing: 12) {
            Group {
                if let ui = NativeBrushPreview.image(b, color: UIColor(canvas.color).hex, color2: UIColor(canvas.color2).hex) { Image(uiImage: ui).resizable().scaledToFit() } else { Color.clear }
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

    private func copyToMine(_ b: Brush) {
        let id = "mine-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        NativeMine.upsert(b.renamed(id, String((b.name + " copy").prefix(20)), pack: "Mine"))
        message = "Copied into Mine."; tick += 1
    }

    /// Any layer becomes a stamp brush: his signature or mark, drawn once, then stamped anywhere, in any colour.
    private func makeFromLayer(_ name: String) {
        guard let d = canvas.doc else { return }
        let L = d.layers[d.active]
        guard let box = L.pixels.contentBounds(), let part = L.pixels.image()?.cropping(to: box) else { message = "This layer is empty: draw the mark first."; return }
        let k = 128 / Double(max(box.width, box.height)), cw = max(1, Int((box.width * k).rounded())), ch = max(1, Int((box.height * k).rounded()))
        guard let c = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        c.interpolationQuality = .high
        c.draw(part, in: CGRect(x: (128 - cw) / 2, y: (128 - ch) / 2, width: cw, height: ch))
        guard let tipImg = c.makeImage(), let png = UIImage(cgImage: tipImg).pngData() else { return }
        let id = "mine-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let b = Brush(["id": id, "name": String(name.prefix(20)), "shape": "tip", "tip": "data:image/png;base64," + png.base64EncodedString(), "hard": 1.0, "flow": 1.0, "spacing": 2.0, "pressSize": 0.0, "rotMode": "fixed"], defaults: NativeToolkit.defaults, pack: "Mine")
        NativeMine.upsert(b)
        canvas.selectBrush(NativeMine.brushes.first { $0.id == id } ?? b)
        message = "\"\(name)\" is now a brush in Mine: tap to stamp it, Size sets how big."; tick += 1
    }

    private func importPack(_ r: Result<URL, Error>) {
        guard case .success(let url) = r else { return }
        let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = o["brushes"] as? [[String: Any]], !list.isEmpty else { message = "Import failed. This is not a brush pack."; return }
        var n = 0
        for var b in list {
            guard b["name"] is String else { continue }
            b["id"] = "imp-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + "\(n)"
            NativeMine.upsert(Brush(b, defaults: NativeToolkit.defaults, pack: "Mine")); n += 1
        }
        message = "Imported \(n) brushes into Mine."; tick += 1
    }

    private func exportPack() {
        let o: [String: Any] = ["pack": "Mine", "from": "PL Paint", "brushes": NativeMine.brushes.map { $0.dictionary() }]
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: .prettyPrinted) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mine brush pack.json")
        try? d.write(to: url)
        shareURL = url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ v: UIActivityViewController, context: Context) {}
}

/// Brush Studio: every parameter of the brush on a slider or a menu, a live sample stroke, and a place in Mine to keep it.
struct NativeStudioSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var edited: Brush?
    @State private var name = ""
    @State private var saved: String?

    private var B: Brush { edited ?? canvas.brush }
    private let groups: [(String, [String])] = [
        ("Shape", ["shape", "hard", "round", "rotMode", "angle", "scatter"]),
        ("Spacing", ["spacing", "spacingJit", "jitLat", "jitLin", "fall"]),
        ("Line", ["stream", "stab", "taperStart", "taperEnd", "flareStart", "flareEnd", "capStart", "capEnd", "tremor", "swell", "swellLen"]),
        ("Pressure and speed", ["flow", "pressSize", "pressOp", "pressCurve", "speedSize", "tiltSize", "tiltAngle"]),
        ("Grain", ["grain", "grainMode", "grainScale", "grainDepth", "grainDrift", "pressGrain", "grainStretch"]),
        ("Paired bands", ["twin", "twinGap", "twinSide", "twinMode", "lines", "lineGap", "gapFill", "gapFillColor", "light"]),
        ("Channel", ["channel", "channel2", "channelEnds", "channelFill", "channel2Fill", "channelColor", "channel2Color", "channelAsym"]),
        ("Wet and colour", ["wet", "wetPull", "hueJit", "satJit", "briJit", "color", "color2"]),
        ("Edge and join", ["edge", "edgeRound", "edgeSwell", "join", "joinMode"]),
        ("Effects", ["wick", "satellites", "echo", "echoStep", "echoGap", "weave"]),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let ui = NativeBrushPreview.image(B, color: UIColor(canvas.color).hex, color2: UIColor(canvas.color2).hex, size: canvas.size, w: 600, h: 140, cached: false) {
                        Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: .infinity).listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                    TextField("Name", text: $name)
                    if let n = B.note { Text(n).font(.footnote).foregroundStyle(.secondary) }
                }
                ForEach(groups, id: \.0) { g in
                    Section(g.0) { ForEach(g.1, id: \.self) { control($0) } }
                }
                Section {
                    Button { save() } label: { Label("Keep in Mine", systemImage: "square.and.arrow.down") }
                    Button { canvas.selectBrush(B); canvas.say("\(B.name) in use."); dismiss() } label: { Label("Use it without keeping", systemImage: "paintbrush") }
                    if edited != nil { Button("Back to how it was", role: .destructive) { edited = nil; name = canvas.brush.name } }
                    if let s = saved { ResultLine(text: s) }
                }
            }
            .navigationTitle("Brush Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { name = canvas.brush.name }
        }
    }

    @ViewBuilder private func control(_ key: String) -> some View {
        if let p = NativeToolkit.params.first(where: { $0.key == key }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text(label(key)).font(.subheadline); Spacer(); Text(format(B.n(key), p)).font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: Binding(get: { B.n(key) }, set: { edited = B.setting(key, ($0 / p.step).rounded() * p.step) }), in: p.min...p.max)
            }
        } else if let c = NativeToolkit.choices.first(where: { $0.key == key }) {
            Picker(label(key), selection: Binding(get: { B.t(key).isEmpty ? c.def : B.t(key) }, set: { edited = B.setting(key, $0) })) { ForEach(c.options, id: \.self) { Text($0.capitalized).tag($0) } }
        } else if key == "color" || key == "color2" || key == "gapFillColor" || key == "channelColor" || key == "channel2Color" {
            let hex = B.t(key)
            HStack {
                Text(label(key)).font(.subheadline); Spacer()
                ColorPicker("", selection: Binding(get: { Hex.rgb(hex).map { Color(red: $0.0, green: $0.1, blue: $0.2) } ?? .clear }, set: { edited = B.setting(key, UIColor($0).hex) }), supportsOpacity: false).labelsHidden()
                if !hex.isEmpty { Button { edited = B.setting(key, "") } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain) }
            }
        }
    }

    private func label(_ k: String) -> String {
        let m: [String: String] = ["hard": "Hardness", "round": "Roundness", "rotMode": "Rotation", "spacingJit": "Spacing jitter", "jitLat": "Sideways jitter", "jitLin": "Lengthways jitter", "fall": "Fall-off",
            "stream": "StreamLine", "stab": "Stabilization", "pressSize": "Pressure → size", "pressOp": "Pressure → opacity", "pressCurve": "Pressure curve", "speedSize": "Speed → size",
            "tiltSize": "Tilt → size", "tiltAngle": "Tilt → angle", "grainMode": "Grain mode", "grainScale": "Grain scale", "grainDepth": "Grain depth", "grainDrift": "Grain drift",
            "pressGrain": "Pressure grain", "grainStretch": "Grain stretch", "twinGap": "Gap", "twinSide": "Side", "twinMode": "Companion order", "lineGap": "Line gap", "gapFill": "Fill the middle",
            "gapFillColor": "Fill colour", "channelEnds": "Clear at", "channelFill": "Channel fill", "channel2Fill": "Outer channel fill", "channelColor": "Channel colour", "channel2Color": "Outer channel colour",
            "channelAsym": "Channel asymmetry", "wetPull": "Pull back", "hueJit": "Hue jitter", "satJit": "Saturation jitter", "briJit": "Lightness jitter", "edgeRound": "Edge rounding", "edgeSwell": "Edge swell",
            "joinMode": "Join", "echoStep": "Echo step", "echoGap": "Echo gap", "taperStart": "Taper start", "taperEnd": "Taper end", "flareStart": "Flare start", "flareEnd": "Flare end", "capStart": "Start cap", "capEnd": "End cap", "swellLen": "Swell length", "color2": "Companion colour"]
        return m[k] ?? k.prefix(1).uppercased() + k.dropFirst()
    }
    private func format(_ v: Double, _ p: NativeToolkit.Param) -> String { p.max - p.min > 20 ? String(Int(v.rounded())) : String(format: "%.2f", v) }

    private func save() {
        let id = canvas.brush.pack == "Mine" ? canvas.brush.id : "mine-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(20))
        let b = B.renamed(id, n.isEmpty ? "My brush" : n, pack: "Mine")
        NativeMine.upsert(b)
        canvas.selectBrush(NativeMine.brushes.first { $0.id == id } ?? b)
        edited = nil
        saved = "Kept in Mine."
        NativeSync.shared.noteMineChanged()
    }
}

extension NativeSync { func noteMineChanged() { /* the next save syncs it */ } }
