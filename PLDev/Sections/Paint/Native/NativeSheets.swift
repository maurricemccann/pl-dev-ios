import SwiftUI
import TipKit
import UIKit

// MARK: colour

/// The colour card: the two colours, the colours he has used, his palettes from the Design Kit, harmonies and a value ramp, and what his
/// own writing says the colour means (the laptop's Colour Sense).
struct NativeColourSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var palette = 0
    @State private var pickingSecond = false
    // Classic (his handbook, ch. 4): three sliders. Kept as state so hue survives a grey or a black, where a colour alone forgets it.
    @State private var ch = 0.0
    @State private var cs = 0.0
    @State private var cv = 0.0

    private var hsv: (h: Double, s: Double, v: Double) {
        let c = UIColor(canvas.color); var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (Double(h) * 360, Double(s), Double(v))
    }
    private func hex(h: Double, s: Double, v: Double) -> Color { Color(hue: ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360, saturation: max(0, min(1, s)), brightness: max(0, min(1, v))) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        ColorPicker("Colour", selection: $canvas.color, supportsOpacity: false).labelsHidden().scaleEffect(1.4).frame(width: 52, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Painting with").font(.caption).foregroundStyle(.secondary)
                            Text(UIColor(canvas.color).hex.uppercased()).font(.headline.monospaced())
                        }
                        Spacer()
                        Button { canvas.swapColours() } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(.bordered).accessibilityLabel("Swap the two colours")
                        VStack(spacing: 2) {
                            ColorPicker("Companion", selection: $canvas.color2, supportsOpacity: false).labelsHidden()
                            Text("Companion").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    NativeBrushColourCard(canvas: canvas)
                    if let sense = NativeToolkit.sense(of: UIColor(canvas.color).hex) {
                        Text(sense).font(.footnote).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    section("Used lately") {
                        if canvas.recent.isEmpty { Text("The colours you paint with collect here.").font(.footnote).foregroundStyle(.secondary) }
                        else { swatches(canvas.recent) }
                    }
                    section("Classic") {
                        classicRow("Hue", $ch, 0...360, "\(Int(ch))°")
                        classicRow("Saturation", $cs, 0...1, "\(Int(cs * 100))%")
                        classicRow("Brightness", $cv, 0...1, "\(Int(cv * 100))%")
                    }
                    section("Harmony") {
                        let v = hsv
                        let sets: [(String, [Color])] = [   // the handbook's five schemes, by its names
                            ("Complementary", [hex(h: v.h + 180, s: v.s, v: v.v)]),
                            ("Split", [hex(h: v.h + 150, s: v.s, v: v.v), hex(h: v.h + 210, s: v.s, v: v.v)]),
                            ("Triad", [hex(h: v.h + 120, s: v.s, v: v.v), hex(h: v.h + 240, s: v.s, v: v.v)]),
                            ("Analogous", [hex(h: v.h - 30, s: v.s, v: v.v), hex(h: v.h + 30, s: v.s, v: v.v)]),
                            ("Tetrad", [hex(h: v.h + 90, s: v.s, v: v.v), hex(h: v.h + 180, s: v.s, v: v.v), hex(h: v.h + 270, s: v.s, v: v.v)]),
                        ]
                        ForEach(sets, id: \.0) { name, cols in
                            HStack { Text(name).font(.caption).frame(width: 104, alignment: .leading); ForEach(Array(cols.enumerated()), id: \.offset) { _, c in swatch(UIColor(c).hex) }; Spacer() }
                        }
                    }
                    section("Value") {   // the handbook: "from dark to light in ten steps"
                        let v = hsv
                        HStack(spacing: 3) { ForEach(1...10, id: \.self) { i in swatch(UIColor(hex(h: v.h, s: v.s, v: Double(i) / 10)).hex, size: 26) } }
                    }
                    section("Passes") {
                        Picker("Each stroke takes the next colour of", selection: $canvas.passPalette) {
                            Text("Off").tag(-1)
                            ForEach(Array(NativeToolkit.palettes.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                        }.pickerStyle(.menu)
                        Text("Use it to build a piece in colours, one stroke after another, in the palette's order.").font(.caption).foregroundStyle(.secondary)
                    }
                    section("His palettes") {
                        HStack {
                            Picker("Palette", selection: $palette) { ForEach(Array(NativeToolkit.palettes.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) } }.pickerStyle(.menu)
                            Button { NativeToolkit.shuffleRandoms(); palette = 1 } label: { Label("Shuffle", systemImage: "shuffle") }.buttonStyle(.bordered).controlSize(.small)
                        }
                        Text("The two Random palettes after the House one are new each time the app opens. Shuffle draws two more.").font(.caption).foregroundStyle(.secondary)
                        if NativeToolkit.palettes.indices.contains(palette) { swatches(NativeToolkit.palettes[palette].colors) }
                    }
                }.padding()
            }
            .navigationTitle("Colour")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { syncClassic() }
            .onChange(of: UIColor(canvas.color).hex) { _, now in if now != UIColor(hex(h: ch, s: cs, v: cv)).hex { syncClassic() } }   // a swatch or the wheel moved it
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func syncClassic() { let v = hsv; if v.s > 0.001 && v.v > 0.001 { ch = v.h }; cs = v.s; cv = v.v }
    private func classicRow(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ read: String) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.caption).frame(width: 78, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; canvas.setColour(hex: UIColor(hex(h: ch, s: cs, v: cv)).hex) }), in: range)
                .accessibilityLabel(name)
            Text(read).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }
    private func section(_ t: String, @ViewBuilder _ c: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(t).font(.subheadline.weight(.semibold)); c() }
    }
    private func swatch(_ hex: String, size: CGFloat = 32) -> some View {
        let rgb = Hex.rgb(hex) ?? (0, 0, 0)
        return Button { canvas.setColour(hex: hex) } label: {
            Circle().fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2)).frame(width: size, height: size).overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(hex)
    }
    private func swatches(_ list: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) { ForEach(Array(list.enumerated()), id: \.offset) { _, h in swatch(h) } }
    }
}

// MARK: assists

struct NativeAssistSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Symmetry") {
                    Picker("Repeat strokes", selection: $canvas.sym) { ForEach(SymMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                }
                Section {
                    Picker("Guide", selection: $canvas.guide) { ForEach(GuideKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if canvas.guide == .grid || canvas.guide == .iso {
                        Stepper("Spacing \(Int(canvas.guideSize)) px", value: $canvas.guideSize, in: 16...512, step: 16)
                    }
                    if canvas.guide.points > 0 { Toggle("Move the vanishing points", isOn: $canvas.vpEdit) }
                    Toggle("Assisted drawing", isOn: $canvas.assist)
                } header: { Text("Guides") } footer: { Text("With assisted drawing a stroke locks to the nearest guide direction once it has moved a little. Each layer can follow or ignore it in the Layers list.") }
                Section {
                    Picker("Tile mode", selection: $canvas.tile) { ForEach(TileMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                    Button("Make tile (slide half way round)") { canvas.makeTile(); dismiss() }
                    Toggle("Smart tile guides: the middle cross, gates, the live ghost", isOn: $canvas.tileGuides)
                    Toggle("Show the tiles around", isOn: $canvas.tilePrev)
                } header: { Text("Tile") } footer: { Text("With tile mode on, a mark that runs off one edge comes back on the other.") }
                Section("Strokes") {
                    Toggle("QuickShape: hold still and the stroke snaps", isOn: $canvas.quickShape)
                    Toggle("Tangent lock: a stroke continues the line it starts beside", isOn: $canvas.tangentLock)
                    Toggle("Facet and Curve: every stroke straight segments with rounded corners", isOn: $canvas.facet)
                    Button("More tools: echo, nodes, lights, seams") { dismiss(); canvas.panel = .tools2 }
                }
                Section("Paper") {
                    Picker("Stock", selection: $canvas.paper) { ForEach(NativeToolkit.papers) { Text($0.name).tag($0.id) } }
                    Text("The stock is kept with the work. A new canvas picks its ground colour from it.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Assists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { canvas.savePrefs(); canvas.stage?.updateOverlay(); canvas.markChanged(); dismiss() } } }
        }
    }
}

// MARK: settings, gestures, quick menu

struct NativeSettingsSheet: View {
    @Bindable var canvas: NativeCanvasModel
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Finger paints after the Pencil is used", isOn: $canvas.fingerPaints)   // a finger always paints until a Pencil touches (Procreate), 11-14
                    Toggle("Palm guard: the view stays still while the Pencil is down", isOn: $canvas.palmGuard)
                    HStack { Text("Stabilization"); Slider(value: $canvas.stabAll, in: 0...1); Text("\(Int(canvas.stabAll * 100))%").font(.caption).monospacedDigit().frame(width: 40) }
                    Toggle("Brushes bring their own colours", isOn: $canvas.brushColors)
                    HStack { Text("Hold time"); Slider(value: $canvas.rapidMs, in: 300...1200, step: 50); Text("\(Int(canvas.rapidMs)) ms").font(.caption).monospacedDigit().frame(width: 60) }
                } header: { Text("Drawing") } footer: { Text("Stabilization smooths every brush; a brush's own StreamLine and Stabilization still apply, the larger of the two wins.") }
                Section("Controls") {
                    Button("Gesture controls") { canvas.panel = .gestures }
                    Button("Quick menu") { canvas.panel = .quickEditor }
                    TipView(PaintPencilTip())
                    Toggle("Swap the Pencil's two buttons", isOn: $canvas.swapPencil)
                    Text("The Pencil's double tap runs the Pen side button's action; the squeeze of a Pencil Pro runs the Pen second button's. This trades them. Set what they run in Gesture controls.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Sync key", value: model.config?.key("paintSync") == nil ? "Not set" : "Set")
                    Toggle("Record a timelapse", isOn: Binding(get: { NativeTimelapse.shared.recording }, set: { NativeTimelapse.shared.recording = $0 }))
                } header: { Text("Keys and recording") } footer: { Text("The sync key comes with your config, so you never paste it. The look of the app (colours, glass, text size) follows PL DEV's Settings.") }
                Section("This device") {
                    LabeledContent("Memory", value: memoryNote)
                    Toggle("Debug mode", isOn: $canvas.debug)
                }
                Section {
                    Button("Open the handbook") { canvas.panel = .handbook }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { canvas.savePrefs(); dismiss() } } }
        }
    }

    private var memoryNote: String {
        guard let d = canvas.doc else { return "No work open" }
        let mb = Double(d.w * d.h * 4) / 1_048_576
        return "\(d.layers.count) layers · \(Int(mb)) MB each"
    }
}

struct NativeGestureSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(NativeToolkit.gestures) { g in
                        Picker(g.name, selection: Binding(get: { canvas.gestures[g.id] ?? g.def }, set: { canvas.gestures[g.id] = $0; canvas.savePrefs() })) {
                            Text("None").tag("None")
                            ForEach(NativeCanvasModel.actionNames, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } footer: { Text("A tap of two, three or four fingers, or holding two or three fingers still, runs the action you choose. Undo and Redo keep stepping while you hold.") }
                Section { Button("Back to the defaults") { canvas.gestures = Dictionary(uniqueKeysWithValues: NativeToolkit.gestures.map { ($0.id, $0.def) }); canvas.savePrefs() } }
            }
            .navigationTitle("Gesture controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct NativeQuickEditorSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    Picker("Using", selection: $canvas.quickAt) { ForEach(Array(canvas.quick.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) } }
                }
                if canvas.quick.indices.contains(canvas.quickAt) {
                    Section {
                        ForEach(0..<6, id: \.self) { i in
                            Picker("Button \(i + 1)", selection: Binding(
                                get: { canvas.quick[canvas.quickAt].slots.indices.contains(i) ? canvas.quick[canvas.quickAt].slots[i] : "None" },
                                set: { v in
                                    while canvas.quick[canvas.quickAt].slots.count < 6 { canvas.quick[canvas.quickAt].slots.append("None") }
                                    canvas.quick[canvas.quickAt].slots[i] = v; canvas.savePrefs()
                                })) {
                                Text("None").tag("None")
                                ForEach(NativeCanvasModel.actionNames, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    } header: { Text("Six buttons") } footer: { Text("The bolt in the dock opens these six. Hold it to change profile.") }
                }
                Section {
                    Button("Add a profile") { canvas.quick.append(NativeToolkit.Profile(name: "Profile \(canvas.quick.count + 1)", slots: Array(repeating: "None", count: 6))); canvas.quickAt = canvas.quick.count - 1; canvas.savePrefs() }
                    if canvas.quick.count > 1 { Button("Delete this profile", role: .destructive) { canvas.quick.remove(at: canvas.quickAt); canvas.quickAt = 0; canvas.savePrefs() } }
                }
            }
            .navigationTitle("Quick menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { canvas.savePrefs(); dismiss() } } }
        }
    }
}

/// The six buttons in a hexagon: the Quick menu's profile, over the picture.
struct NativeQuickMenu: View {
    let canvas: NativeCanvasModel
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture(perform: close)
            let slots = canvas.quick.indices.contains(canvas.quickAt) ? canvas.quick[canvas.quickAt].slots : []
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let a = Double(i) / 6 * .pi * 2 - .pi / 2
                    let name = slots.indices.contains(i) ? slots[i] : "None"
                    Button { close(); canvas.run(action: name) } label: {
                        Text(name == "None" ? "·" : name).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3).padding(6).frame(width: 84, height: 84)
                    }
                    .glassControl(in: Circle())
                    .offset(x: cos(a) * 112, y: sin(a) * 112)
                }
                Button { canvas.quickAt = (canvas.quickAt + 1) % max(1, canvas.quick.count); canvas.savePrefs() } label: {
                    Text(canvas.quick.indices.contains(canvas.quickAt) ? canvas.quick[canvas.quickAt].name : "").font(.caption.weight(.bold)).padding(8)
                }.glassControl(in: Capsule())
            }
        }
    }
}

// MARK: handbook

/// The handbook, native: the laptop's handbook turned into data (`scripts/paint_handbook.py`), the pictures loaded from the gallery.
struct NativeHandbookView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var zoom: String?
    private let book = NativeHandbook.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { phoneChapter } label: { Label("PL Paint on the iPhone", systemImage: "iphone") }
                }
                ForEach(filtered) { ch in
                    Section("\(ch.n) · \(ch.title)") {
                        ForEach(ch.secs) { s in NavigationLink(s.title) { NativeHandbookSection(section: s, chapter: ch.title) } }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search the handbook")
            .navigationTitle("Handbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var filtered: [NativeHandbook.Chapter] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return book.chapters }
        return book.chapters.compactMap { ch in
            let secs = ch.secs.filter { $0.title.lowercased().contains(q) || $0.plain.lowercased().contains(q) }
            return secs.isEmpty ? nil : NativeHandbook.Chapter(id: ch.id, n: ch.n, title: ch.title, secs: secs)
        }
    }

    private var phoneChapter: some View {
        List {
            Section("Drawing") {
                row("Apple Pencil", "Draws with its pressure and its lean. A finger only draws if Finger paints is on.")
                row("Two fingers", "Pinch to zoom, twist to turn the picture, drag to move it. A small twist near upright snaps back to level.")
                row("Taps and holds", "Two fingers tapped undo, three redo, four fit the picture. Hold two fingers and Undo keeps stepping. All of it can be changed in Gesture controls.")
                row("Pencil double tap", "Swaps between the brush and the eraser (or whatever Gesture controls says).")
                row("Hold still", "Hold the Pencil still at the end of a stroke and it snaps to a line, a triangle, a four-sided shape or an ellipse. Touch with a finger and it becomes exact.")
            }
            Section("The screen") {
                row("The dock", "Brush, eraser and smudge; Select, Transform, the colour picker and ColorDrop. The brush, the colour, size and opacity sit under it.")
                row("The ellipsis", "New canvas, rename, save or share, send to Curate or the Archive, adjustments, copy and paste, the view, assists, Sync, settings and this handbook.")
                row("Hide the controls", "The eye in the ellipsis menu hides everything but the picture.")
            }
            Section("Your works") {
                row("Saved on their own", "Three seconds after the last change, and when you leave the app.")
                row("Sync", "Works, the Daily Mark and your own brushes go both ways with the laptop. A work changed on both sides is kept as two copies.")
            }
        }.navigationTitle("On the iPhone")
    }
    private func row(_ t: String, _ b: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(t).font(.headline); Text(b).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 2) }
}

struct NativeHandbookSection: View {
    let section: NativeHandbook.Section
    let chapter: String
    @State private var zoomed: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(section.b.enumerated()), id: \.offset) { _, b in block(b) }
            }.padding()
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { zoomed.map { ZoomURL(url: $0) } }, set: { zoomed = $0?.url })) { z in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                ScrollView([.horizontal, .vertical]) { AsyncImage(url: z.url) { $0.resizable().scaledToFit() } placeholder: { PLLoader() }.frame(minWidth: UIScreen.main.bounds.width) }
                Button { zoomed = nil } label: { Image(systemName: "xmark.circle.fill").font(.title) }.padding().foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder private func block(_ b: NativeHandbook.Block) -> some View {
        switch b.t {
        case "lead": Text(b.text).font(.title3).fixedSize(horizontal: false, vertical: true)
        case "p": Text(b.text).fixedSize(horizontal: false, vertical: true)
        case "h4": Text(b.text).font(.headline).padding(.top, 6)
        case "tip":
            VStack(alignment: .leading, spacing: 2) {
                if !b.head.isEmpty { Text(b.head).font(.caption.weight(.bold)).foregroundStyle(Wallpaper.line) }
                Text(b.text).font(.subheadline)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Wallpaper.line.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case "list": VStack(alignment: .leading, spacing: 6) { ForEach(Array(b.items.enumerated()), id: \.offset) { _, t in HStack(alignment: .top) { Text("•"); Text(t) } } }
        case "steps": VStack(alignment: .leading, spacing: 6) { ForEach(Array(b.items.enumerated()), id: \.offset) { i, t in HStack(alignment: .top) { Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary); Text(t) } } }
        case "table":
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(b.rows.enumerated()), id: \.offset) { i, r in
                    HStack(alignment: .top) { ForEach(Array(r.enumerated()), id: \.offset) { _, c in Text(c).font(i == 0 ? .caption.weight(.bold) : .caption).frame(maxWidth: .infinity, alignment: .leading) } }
                    Divider()
                }
            }
        case "fig":
            VStack(alignment: .leading, spacing: 8) {
                if let u = NativeHandbook.imageURL(b.src) {
                    Button { zoomed = u } label: { AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { PLLoader().frame(maxWidth: .infinity, minHeight: 120) } }.buttonStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ForEach(Array(b.legend.enumerated()), id: \.offset) { i, l in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 22, height: 22).background(Wallpaper.line, in: Circle()).foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 1) { Text(l.0).font(.subheadline.weight(.semibold)); Text(l.1).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
        default: EmptyView()
        }
    }
    struct ZoomURL: Identifiable { let url: URL; var id: String { url.absoluteString } }
}

/// The handbook data, read once from the bundle.
final class NativeHandbook: @unchecked Sendable {
    static let shared = NativeHandbook()
    struct Block { let t: String; let text: String; let head: String; let items: [String]; let rows: [[String]]; let src: String; let legend: [(String, String)] }
    struct Section: Identifiable { let id: String; let title: String; let b: [Block]; var plain: String { b.map { $0.text + " " + $0.items.joined(separator: " ") + " " + $0.legend.map { $0.0 + " " + $0.1 }.joined(separator: " ") }.joined(separator: " ") } }
    struct Chapter: Identifiable { let id: String; let n: String; let title: String; let secs: [Section] }
    let chapters: [Chapter]

    init() {
        guard let url = Bundle.main.url(forResource: "NativeHandbook", withExtension: "json"), let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let cs = o["chapters"] as? [[String: Any]] else { chapters = []; return }
        chapters = cs.map { c in
            Chapter(id: c["id"] as? String ?? UUID().uuidString, n: c["n"] as? String ?? "", title: c["title"] as? String ?? "", secs: (c["secs"] as? [[String: Any]] ?? []).map { s in
                Section(id: s["id"] as? String ?? UUID().uuidString, title: s["title"] as? String ?? "", b: (s["b"] as? [[String: Any]] ?? []).map { b in
                    let x = b["x"]
                    let str = x as? String ?? ""
                    let arr = (x as? [String]) ?? []
                    let rows = (x as? [[String]]) ?? []
                    let legend = ((x as? [[String]]) ?? []).filter { $0.count == 2 }.map { ($0[0], $0[1]) }
                    return Block(t: b["t"] as? String ?? "p", text: str, head: b["h"] as? String ?? "", items: arr, rows: b["t"] as? String == "table" ? rows : [], src: b["src"] as? String ?? "", legend: b["t"] as? String == "fig" ? legend : [])
                })
            })
        }
    }

    /// The pictures are on the gallery, next to the laptop's own handbook.
    static func imageURL(_ src: String) -> URL? {
        guard !src.isEmpty else { return nil }
        return URL(string: "https://pl-curve-library.psychedluxuries.workers.dev/paint/handbook/" + src)
    }
}
