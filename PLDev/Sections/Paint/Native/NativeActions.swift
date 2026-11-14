import SwiftUI

/// Actions (his note 11-14: "there's no settings within PL Paint and the rows keep going back up in the options menu"). The ••• was a
/// 30-row system Menu that redrew on every canvas change and jumped back to its top, so Settings, its last row, was out of reach.
/// Procreate's answer is an Actions panel in tabs; this is that, as a sheet whose lists keep their place.
struct NativeActionsSheet: View {
    @Bindable var canvas: NativeCanvasModel
    let clearLayer: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("plpn.actions.tab2") private var tab = Tab.canvas

    /// His handbook's own tabs for the phone (chapter 10, "Drawing on a phone": "Actions is in tabs: Canvas, Assist, Hand, Video, Prefs").
    enum Tab: String, CaseIterable, Identifiable {
        case canvas = "Canvas", assist = "Assist", hand = "Hand", video = "Video", prefs = "Prefs"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                switch tab {
                case .canvas:
                    Section("This picture") {
                        open("New canvas", "plus", .newCanvas)
                        open("Rename", "pencil", .rename)
                        open("Save or share the picture", "square.and.arrow.up", .exportPicture)
                        open("Send to Curate or the Archive", "paperplane", .send)
                        open("Bring in: photo, PSD, brushes", "square.and.arrow.down", .bringIn)
                        open("Adjustments and effects", "wand.and.rays", .adjust)
                    }
                    Section("Edit") {
                        run("Copy", "doc.on.doc") { canvas.clipCopy(cut: false) }
                        run("Cut", "scissors") { canvas.clipCopy(cut: true) }
                        run("Paste", "doc.on.clipboard") { canvas.clipPaste() }
                        run("Fill with the colour", "drop.fill") { canvas.fillSelection() }
                        Button(role: .destructive) { dismiss(); clearLayer() } label: { Label("Clear layer", systemImage: "trash") }
                    }
                    Section("The canvas") {
                        run("Flip left and right", "arrow.left.and.right.righttriangle.left.righttriangle.right") { canvas.flipCanvas(horizontal: true) }
                        run("Flip top and bottom", "arrow.up.and.down.righttriangle.up.righttriangle.down") { canvas.flipCanvas(horizontal: false) }
                        run(canvas.doc?.bgVis == false ? "Show the background" : "Transparent background", "checkerboard.rectangle") { canvas.run(action: "Transparent background") }
                        run("Fit to screen", "arrow.up.left.and.down.right.magnifyingglass") { canvas.stage?.fit() }
                        run("Actual pixels", "1.magnifyingglass") { canvas.stage?.actualSize() }
                        run("Turn upright", "arrow.up") { canvas.stage?.turnUpright() }
                        run("Hide the controls", "eye.slash") { canvas.uiHidden = true }
                    }
                case .assist:
                    open("Assists: guides, symmetry, seamless tile", "square.split.diagonal", .assists)
                    open("More tools: facet, echo, nodes, lights, seams", "wand.and.stars", .tools2)
                    run("Make tile (slide half way round)", "square.grid.3x3") { canvas.makeTile() }
                    run("Add the corner copies", "square.on.square.dashed") { canvas.cornerCopies() }
                    open("Check the repeat (3 by 3)", "square.grid.3x3.fill", .repeatCheck)
                    run("Ghost copy behind this layer", "square.2.layers.3d.bottom.filled") { canvas.ghostBelow() }
                case .hand:
                    open("Study: record how I draw", "record.circle", .study)
                    open("Adjust strokes", "dial.medium", .tweak)
                    open("Lift ink from a photo", "photo", .lift)
                    open("Brushes: His hand, His bands", "paintbrush.pointed", .brushes)
                case .video:
                    open("Timelapse", "play.rectangle", .timelapse)
                case .prefs:
                    open("Settings: fingers, palm, Pencil, stabilization", "gearshape", .settings)
                    open("Gesture controls", "hand.tap", .gestures)
                    open("QuickMenu", "circle.grid.cross", .quickEditor)
                    open("Sync with the laptop", "arrow.triangle.2.circlepath", .sync)
                    open("Handbook", "book", .handbook)
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Actions", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)
            }
            .navigationTitle("Actions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// A row that opens another panel: the sheet swaps to it.
    private func open(_ title: String, _ symbol: String, _ panel: NativePanel) -> some View {
        Button { canvas.panel = panel } label: { Label(title, systemImage: symbol) }
    }

    /// A row that acts on the picture at once, then closes so the result is seen.
    private func run(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { dismiss(); action() } label: { Label(title, systemImage: symbol) }
    }
}

/// Paint's Settings from the Gallery (no canvas open): its own model reads and writes the same saved settings the canvas uses.
struct PaintGallerySettings: View {
    let model: AppModel
    @State private var prefs = NativeCanvasModel()

    var body: some View {
        NativeSettingsSheet(canvas: prefs, model: model)
            .sheet(item: Binding(get: { prefs.panel == .gestures || prefs.panel == .quickEditor ? prefs.panel : nil }, set: { prefs.panel = $0 })) { p in
                if p == .gestures { NativeGestureSheet(canvas: prefs) } else { NativeQuickEditorSheet(canvas: prefs) }
            }
            .onDisappear { prefs.savePrefs() }
    }
}
