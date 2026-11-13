import SwiftUI
import UIKit

/// PL Paint on the iPhone: the only canvas. Everything the laptop app does, native: his brushes and packs, layers, groups, masks, blends,
/// selection, transform, assists, adjustments, exports, and Sync both ways with the laptop. Pencil first; fingers move the picture.
struct NativeCanvasView: View {
    let model: AppModel
    var openID: String? = nil
    @State private var canvas = NativeCanvasModel()
    @State private var showSizes = false
    @State private var confirmClear = false
    @State private var renameText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    private let sync = NativeSync.shared

    var body: some View {
        ZStack {
            CanvasRepresentable(model: canvas).ignoresSafeArea()
            if !canvas.hasDoc { empty }
            VStack(spacing: 8) {
                if !canvas.uiHidden { topBar; NativeStudyBar() }
                Spacer(minLength: 0)
                if canvas.uiHidden { hiddenControls }
                else {
                    if let l = canvas.line { ResultLine(text: l).padding(8).glassControl(in: Capsule()).transition(.opacity) }
                    if canvas.hasDoc { modeBar; bottomBar }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .animation(.smooth(duration: 0.2), value: canvas.mode)
        .animation(.smooth(duration: 0.2), value: canvas.uiHidden)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(item: $canvas.panel) { p in sheet(p) }
        .sensoryFeedback(PLHaptic.select, trigger: canvas.activeLayer)
        .sensoryFeedback(PLHaptic.commit, trigger: canvas.docVersion)
        .onChange(of: phase) { _, p in if p != .active { canvas.saveNow(); Task { await sync.run(model: model, canvas: canvas) } } }
        .task { start() }
        .onDisappear { canvas.saveNow() }
        .confirmationDialog("Clear this layer?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { canvas.clearLayer() }
        } message: { Text(canvas.hasSelection ? "Only the selected part is cleared. Undo brings it back." : "Undo brings it back.") }
    }

    private func start() {
        canvas.onChange = { Task { await sync.changed(model: model, canvas: canvas) } }
        if let id = openID { canvas.open(id: id) } else if !canvas.hasDoc, let id = NativeStore.loadIndex().current { canvas.open(id: id) }
        Task { await sync.run(model: model, canvas: canvas) }
    }

    // MARK: no canvas yet

    private var empty: some View {
        ContentUnavailableView {
            Label("No canvas open", systemImage: "paintbrush.pointed")
        } description: {
            Text("Open one of your works, or start a new canvas.")
        } actions: {
            Button("Works") { canvas.panel = .works }.buttonStyle(.borderedProminent)
            Button("New canvas") { canvas.panel = .newCanvas }.buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
    }

    // MARK: bars

    private func roundButton(_ symbol: String, _ label: String, disabled: Bool = false, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 38, height: 38) }
            .glassControl(tint: on ? Wallpaper.line : nil, in: Circle())
            .disabled(disabled).opacity(disabled ? 0.45 : 1).accessibilityLabel(label)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            roundButton("xmark", "Close the canvas") { canvas.saveNow(); Task { await sync.run(model: model, canvas: canvas) }; dismiss() }
            roundButton("square.grid.2x2", "Works") { canvas.panel = .works }
            if canvas.hasDoc {
                Text(canvas.name).font(.footnote.weight(.semibold)).lineLimit(1).padding(.horizontal, 10).frame(height: 30)
                    .glassControl(in: Capsule()).onTapGesture { renameText = canvas.name; canvas.panel = .rename }
            }
            Spacer(minLength: 0)
            if canvas.hasDoc {
                roundButton("arrow.uturn.backward", "Undo", disabled: !canvas.canUndo && !canvas.trActive) { canvas.undoStroke() }
                roundButton("arrow.uturn.forward", "Redo", disabled: !canvas.canRedo) { canvas.redoStroke() }
                roundButton("square.3.layers.3d", "Layers") { canvas.panel = .layers }
                moreMenu
            } else { roundButton("plus", "New canvas") { canvas.panel = .newCanvas } }
        }
    }

    private var moreMenu: some View {
        Menu {
            Section("This picture") {
                Button { canvas.panel = .newCanvas } label: { Label("New canvas", systemImage: "plus") }
                Button { renameText = canvas.name; canvas.panel = .rename } label: { Label("Rename", systemImage: "pencil") }
                Button { canvas.panel = .exportPicture } label: { Label("Save or share the picture", systemImage: "square.and.arrow.up") }
                Button { canvas.panel = .send } label: { Label("Send to Curate or the Archive", systemImage: "paperplane") }
                Button { canvas.panel = .bringIn } label: { Label("Bring in: photo, PSD, brushes", systemImage: "square.and.arrow.down") }
                Button { canvas.panel = .timelapse } label: { Label("Timelapse", systemImage: "play.rectangle") }
                Button { canvas.panel = .study } label: { Label("Study: record how I draw", systemImage: "record.circle") }
            }
            Section("Edit") {
                Button { canvas.panel = .adjust } label: { Label("Adjustments and effects", systemImage: "slider.horizontal.3") }
                Button { canvas.panel = .tweak } label: { Label("Adjust strokes", systemImage: "dial.medium") }
                Button { canvas.panel = .lift } label: { Label("Lift ink from a photo", systemImage: "photo") }
                Button { canvas.clipCopy(cut: false) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { canvas.clipCopy(cut: true) } label: { Label("Cut", systemImage: "scissors") }
                Button { canvas.clipPaste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Button { canvas.fillSelection() } label: { Label("Fill with the colour", systemImage: "drop.fill") }
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear layer", systemImage: "trash") }
                Menu("Canvas") {
                    Button { canvas.flipCanvas(horizontal: true) } label: { Label("Flip left and right", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    Button { canvas.flipCanvas(horizontal: false) } label: { Label("Flip top and bottom", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                    Button { canvas.run(action: "Transparent background") } label: { Label(canvas.doc?.bgVis == false ? "Show the background" : "Transparent background", systemImage: "checkerboard.rectangle") }
                    Button { canvas.makeTile() } label: { Label("Make tile (slide half way round)", systemImage: "square.grid.3x3") }
                    Button { canvas.cornerCopies() } label: { Label("Add the corner copies", systemImage: "square.on.square.dashed") }
                    Button { canvas.panel = .repeatCheck } label: { Label("Check the repeat (3 by 3)", systemImage: "square.grid.3x3.fill") }
                    Button { canvas.ghostBelow() } label: { Label("Ghost copy behind this layer", systemImage: "square.2.layers.3d.bottom.filled") }
                }
            }
            Section("View") {
                Button { canvas.stage?.fit() } label: { Label("Fit to screen", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                Button { canvas.stage?.actualSize() } label: { Label("Actual pixels", systemImage: "1.magnifyingglass") }
                Button { canvas.stage?.turnUpright() } label: { Label("Turn upright", systemImage: "arrow.up") }
                Button { canvas.uiHidden = true } label: { Label("Hide the controls", systemImage: "eye.slash") }
            }
            Section {
                Button { canvas.panel = .assists } label: { Label("Assists: symmetry, guides, tile", systemImage: "square.split.diagonal") }
                Button { canvas.panel = .sync } label: { Label("Sync with the laptop", systemImage: "arrow.triangle.2.circlepath") }
                Button { canvas.panel = .settings } label: { Label("Settings", systemImage: "gearshape") }
                Button { canvas.panel = .handbook } label: { Label("Handbook", systemImage: "book") }
            }
        } label: { Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 38, height: 38) }
            .glassControl(in: Circle()).accessibilityLabel("More")
    }

    private var hiddenControls: some View {
        HStack {
            roundButton("eye", "Show the controls") { canvas.uiHidden = false }
            Spacer()
            roundButton("arrow.uturn.backward", "Undo", disabled: !canvas.canUndo) { canvas.undoStroke() }
        }
    }

    // MARK: modes

    @ViewBuilder private var modeBar: some View {
        switch canvas.mode {
        case .select: selectBar
        case .transform: transformBar
        case .fill:
            HStack {
                Image(systemName: "drop.fill")
                Slider(value: $canvas.fillThreshold, in: 0...100).accessibilityLabel("ColorDrop threshold")
                Text("\(Int(canvas.fillThreshold))%").font(.caption).monospacedDigit().frame(width: 38)
                Button("Done") { canvas.setMode(.draw) }.buttonStyle(.bordered)
            }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .eyedrop:
            HStack {
                Image(systemName: "eyedropper")
                Text("Touch the picture to pick a colour.").font(.footnote)
                Spacer()
                Button("Done") { canvas.setMode(.draw) }.buttonStyle(.bordered)
            }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .draw:
            if canvas.maskEditing { maskBar }
            else if canvas.sym != .off || canvas.guide != .off || canvas.tile != .off { assistChips }
        }
    }

    private var selectBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Picker("Shape", selection: $canvas.selShape) {
                    Text("Auto").tag(SelShape.auto); Text("Free").tag(SelShape.free); Text("Rect").tag(SelShape.rect); Text("Oval").tag(SelShape.ellipse)
                }.pickerStyle(.segmented)
                Picker("How", selection: $canvas.selOp) {
                    Image(systemName: "square").tag(SelOp.replace); Image(systemName: "plus.square").tag(SelOp.add); Image(systemName: "minus.square").tag(SelOp.remove)
                }.pickerStyle(.segmented).frame(width: 120)
            }
            HStack(spacing: 8) {
                chip("Invert", "circle.lefthalf.filled") { canvas.selectInvert() }
                chip("Feather \(canvas.selFeather)", "aqi.medium") { canvas.cycleFeather() }
                chip("All", "rectangle.dashed") { canvas.selectAll() }
                chip("Back", "clock.arrow.circlepath") { canvas.bringBackSelection() }
                chip("To layer", "square.on.square") { canvas.selectionToLayer() }
                chip("Clear", "xmark.circle") { canvas.selectNothing() }
                Spacer(minLength: 0)
                Button("Done") { canvas.setMode(.draw) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            if canvas.selShape == .auto {
                HStack { Text("Reach").font(.caption); Slider(value: Binding(get: { Double(canvas.selTolerance) }, set: { canvas.selTolerance = Int($0) }), in: 0...120) }
            }
        }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var transformBar: some View {
        VStack(spacing: 8) {
            Picker("Transform", selection: Binding(get: { canvas.trMode }, set: { canvas.setTransformMode($0) })) {
                Text("Free").tag(NativeTransform.Mode.free); Text("Uniform").tag(NativeTransform.Mode.uni)
                Text("Distort").tag(NativeTransform.Mode.distort); Text("Warp").tag(NativeTransform.Mode.warp)
            }.pickerStyle(.segmented)
            HStack(spacing: 8) {
                chip("Flip", "arrow.left.and.right") { canvas.transformFlip(horizontal: true) }
                chip("Flip", "arrow.up.and.down") { canvas.transformFlip(horizontal: false) }
                chip("45°", "rotate.right") { canvas.transformTurn45() }
                chip("Fit", "arrow.up.left.and.arrow.down.right") { canvas.transformFit() }
                chip("Reset", "arrow.counterclockwise") { canvas.transformReset() }
                Spacer(minLength: 0)
                Button("Cancel") { canvas.cancelTransform() }.buttonStyle(.bordered).controlSize(.small)
                Button("Done") { canvas.commitTransform() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            HStack {
                Toggle("Smooth", isOn: Binding(get: { canvas.transform?.smooth ?? true }, set: { canvas.transform?.smooth = $0; canvas.stage?.refreshFloat() })).toggleStyle(.button).controlSize(.small)
                Toggle("Magnetic", isOn: Binding(get: { canvas.transform?.magnetic ?? false }, set: { canvas.transform?.magnetic = $0 })).toggleStyle(.button).controlSize(.small)
                Spacer()
            }.font(.caption)
        }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var maskBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled.inverse")
            Text("Painting the mask").font(.footnote)
            Spacer()
            chip("Invert", "circle.lefthalf.filled") { canvas.invertMask() }
            chip("Apply", "checkmark.circle") { canvas.applyMask() }
            Button("Layer") { canvas.maskEditing = false; canvas.syncFlags() }.buttonStyle(.borderedProminent).controlSize(.small)
        }.padding(10).glassControl(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var assistChips: some View {
        HStack(spacing: 6) {
            if canvas.sym != .off { Label(canvas.sym.label, systemImage: "square.split.2x1").font(.caption2) }
            if canvas.guide != .off { Label(canvas.guide.label, systemImage: "grid").font(.caption2) }
            if canvas.tile != .off { Label("Tile", systemImage: "square.grid.3x3").font(.caption2) }
            Spacer(minLength: 0)
            Button("Assists") { canvas.panel = .assists }.font(.caption2).buttonStyle(.bordered).controlSize(.mini)
        }.padding(8).glassControl(in: Capsule())
    }

    private func chip(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.caption2).labelStyle(.titleAndIcon) }.buttonStyle(.bordered).controlSize(.mini)
    }

    // MARK: the dock

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                dockButton("paintbrush.pointed.fill", "Brush", on: canvas.mode == .draw && canvas.tool == .paint) { canvas.setMode(.draw); canvas.tool = .paint }
                dockButton("eraser.fill", "Eraser", on: canvas.mode == .draw && canvas.tool == .erase) { canvas.setMode(.draw); canvas.tool = .erase }
                dockButton("hand.point.up.braille", "Smudge", on: canvas.mode == .draw && canvas.tool == .smudge) { canvas.setMode(.draw); canvas.tool = .smudge }
                Divider().frame(height: 22)
                dockButton("rectangle.dashed", "Select", on: canvas.mode == .select) { canvas.setMode(canvas.mode == .select ? .draw : .select) }
                dockButton("arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "Transform", on: canvas.mode == .transform) { canvas.toggleTransform() }
                dockButton("eyedropper", "Pick a colour", on: canvas.mode == .eyedrop) { canvas.setMode(canvas.mode == .eyedrop ? .draw : .eyedrop) }
                dockButton("drop.fill", "ColorDrop", on: canvas.mode == .fill) { canvas.setMode(canvas.mode == .fill ? .draw : .fill) }
                Spacer(minLength: 0)
                Toggle(isOn: $canvas.fingerPaints) { Image(systemName: "hand.point.up.left") }
                    .toggleStyle(.button).controlSize(.small).accessibilityLabel("Finger paints")
            }
            HStack(spacing: 10) {
                Button { canvas.panel = .brushes } label: {
                    HStack(spacing: 6) {
                        if canvas.tool == .paint, let ui = NativeBrushPreview.image(canvas.brush, color: UIColor(canvas.color).hex, color2: UIColor(canvas.color2).hex, size: 14, w: 120, h: 34) {
                            Image(uiImage: ui).resizable().scaledToFit().frame(height: 26)
                        }
                        Text(canvas.tool == .paint ? canvas.brush.name : canvas.tool == .erase ? "Eraser" : "Smudge").font(.footnote).lineLimit(1)
                    }
                }.buttonStyle(.bordered).accessibilityLabel("Brush: \(canvas.brush.name)")
                Button { canvas.panel = .colour } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Circle().fill(canvas.color).frame(width: 34, height: 34).overlay(Circle().stroke(.white, lineWidth: 2))
                        if canvas.brush.needsTwinColour { Circle().fill(canvas.color2).frame(width: 15, height: 15).overlay(Circle().stroke(.white, lineWidth: 1.5)) }
                    }
                }.buttonStyle(.plain).accessibilityLabel("Colour")
                Spacer(minLength: 0)
                Text(canvas.docSize).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "circle.fill").font(.system(size: 6))
                Slider(value: Binding(get: { sqrt(max(0, (canvas.size - 1) / 399)) }, set: { canvas.size = 1 + $0 * $0 * 399 })).accessibilityLabel("Brush size")
                Image(systemName: "circle.fill").font(.system(size: 18))
                Text("\(Int(canvas.size))").font(.caption2).monospacedDigit().frame(width: 28, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled").font(.caption)
                Slider(value: $canvas.opacity, in: 0.05...1).accessibilityLabel("Opacity")
                Text("\(Int(canvas.opacityPct))%").font(.caption2).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
        }
        .padding(12).glassControl(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dockButton(_ symbol: String, _ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.callout).frame(width: 34, height: 30) }
            .buttonStyle(.plain)
            .background(on ? Wallpaper.line.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel(label)
    }

    // MARK: sheets

    @ViewBuilder private func sheet(_ p: NativePanel) -> some View {
        switch p {
        case .works: NativeWorksSheet(model: model, canvas: canvas)
        case .newCanvas: NativeNewCanvasSheet(canvas: canvas)
        case .brushes: NativeBrushSheet(canvas: canvas)
        case .studio: NativeStudioSheet(canvas: canvas)
        case .layers: NativeLayersSheet(canvas: canvas).presentationDetents([.medium, .large])
        case .colour: NativeColourSheet(canvas: canvas).presentationDetents([.medium, .large])
        case .adjust: NativeAdjustSheet(canvas: canvas).presentationDetents([.medium, .large])
        case .settings: NativeSettingsSheet(canvas: canvas, model: model)
        case .gestures: NativeGestureSheet(canvas: canvas)
        case .quickEditor: NativeQuickEditorSheet(canvas: canvas)
        case .assists: NativeAssistSheet(canvas: canvas).presentationDetents([.medium, .large])
        case .handbook: NativeHandbookView()
        case .sync: NativeSyncSheet(model: model, canvas: canvas)
        case .exportPicture: NativeExportSheet(canvas: canvas)
        case .send: NativeSendSheet(model: model, canvas: canvas)
        case .lift: NativeLiftSheet(canvas: canvas)
        case .timelapse: NativeTimelapseSheet(canvas: canvas)
        case .study: NativeStudySheet(canvas: canvas)
        case .bringIn: NativeBringInSheet(canvas: canvas)
        case .tweak: NativeTweakSheet(canvas: canvas)
        case .rename: NativeRenameSheet(canvas: canvas)
        case .repeatCheck: NativeRepeatSheet(canvas: canvas)
        }
    }
}

// MARK: works

/// His works: on this phone, and the synced ones from the laptop that are not here yet.
struct NativeWorksSheet: View {
    let model: AppModel
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var local: [[String: Any]] = []
    @State private var remote: [NativeRemote.Entry] = []
    @State private var loading = true
    @State private var failed: String?
    @State private var busy: String?
    @State private var confirmDelete: String?
    @State private var days: [String: Int] = NativeDaily.days
    @State private var stacking: String?
    @State private var stackName = ""
    private struct StackGroup: Identifiable { let name: String; let items: [[String: Any]]; var id: String { name } }
    private var groups: [StackGroup] {
        var names: [String] = []
        for e in local { if let n = e["stack"] as? String, !n.isEmpty, !names.contains(n) { names.append(n) } }
        return [StackGroup(name: "", items: local.filter { ($0["stack"] as? String ?? "").isEmpty })] + names.map { n in StackGroup(name: n, items: local.filter { ($0["stack"] as? String) == n }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("The Daily Mark") {
                    LabeledContent("Streak", value: "\(NativeDaily.streak) days")
                    DailyMarkStrip(days: days)
                }
                ForEach(groups) { g in
                    Section {
                        if g.name.isEmpty && local.isEmpty { Text("Nothing saved here yet. Start a canvas with the plus.").foregroundStyle(.secondary) }
                        ForEach(Array(g.items.enumerated()), id: \.offset) { _, e in
                            let id = e["id"] as? String ?? ""
                            Button { canvas.open(id: id); dismiss() } label: { row(name: e["name"] as? String ?? "Untitled", w: e["w"] as? Int ?? 0, h: e["h"] as? Int ?? 0, thumb: thumb(e["thumb"] as? String), current: id == canvas.workID) }
                                .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { confirmDelete = id } }
                                .swipeActions(edge: .leading) { Button("Copy") { duplicate(id) }.tint(.blue) }
                                .contextMenu {
                                    Button { stackName = e["stack"] as? String ?? ""; stacking = id } label: { Label("Put in a stack…", systemImage: "square.stack.3d.up") }
                                    if e["stack"] != nil { Button { canvas.setStack(id: id, name: nil); reload() } label: { Label("Take out of its stack", systemImage: "square.stack.3d.up.slash") } }
                                }
                        }
                    } header: { Text(g.name.isEmpty ? "On this phone" : "Stack · \(g.name)") }
                }
                Section {
                    if loading { ProgressView() }
                    if let f = failed { Text(f).foregroundStyle(.secondary) }
                    ForEach(remote.filter { r in !local.contains { ($0["id"] as? String) == r.id } }) { r in
                        Button { Task { await fetch(r) } } label: {
                            HStack { row(name: r.name, w: r.w, h: r.h, thumb: r.thumb, current: false); if busy == r.id { ProgressView() } }
                        }.disabled(busy != nil)
                    }
                    if !loading && failed == nil && remote.allSatisfy({ r in local.contains { ($0["id"] as? String) == r.id } }) { Text("Everything from the laptop is on this phone.").foregroundStyle(.secondary) }
                } header: { Text("From the laptop") } footer: { Text("Tap one to bring it onto this phone. Changes made here go back to the laptop on their own.") }
            }
            .navigationTitle("Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss(); canvas.panel = .newCanvas } label: { Label("New canvas", systemImage: "plus") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await load() }
            .task { reload(); await load() }
            .alert("Put in a stack", isPresented: Binding(get: { stacking != nil }, set: { if !$0 { stacking = nil } })) {
                TextField("Stack name", text: $stackName)
                Button("Put it there") { if let id = stacking { canvas.setStack(id: id, name: stackName); reload() }; stacking = nil }
                Button("Cancel", role: .cancel) { stacking = nil }
            } message: { Text("Works with the same stack name sit together here and on the laptop.") }
            .confirmationDialog("Delete this work from the phone?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let id = confirmDelete { canvas.delete(id: id); reload() }; confirmDelete = nil }
            } message: { Text("It is removed from the laptop too, the next time they sync.") }
        }
    }

    private func row(name: String, w: Int, h: Int, thumb: UIImage?, current: Bool) -> some View {
        HStack(spacing: 12) {
            Group { if let t = thumb { Image(uiImage: t).resizable().scaledToFit() } else { Color.secondary.opacity(0.12) } }
                .frame(width: 56, height: 56).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading) { Text(name).foregroundStyle(.primary); Text("\(w) × \(h)").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            if current { Image(systemName: "checkmark").foregroundStyle(Wallpaper.line) }
        }
    }
    private func thumb(_ s: String?) -> UIImage? { s.flatMap { NativeDoc.image(fromDataURL: $0) }.map { UIImage(cgImage: $0) } }
    private func reload() { local = NativeStore.loadIndex().list; days = NativeDaily.days }
    private func duplicate(_ id: String) { if canvas.duplicateWork(id: id) { reload() } }

    private func load() async {
        guard let http = model.http else { loading = false; failed = "Not connected. Load your config first."; return }
        do { remote = try await NativeRemote.list(http); failed = nil } catch { failed = "Your synced works did not load. Pull to try again." }
        loading = false
    }
    private func fetch(_ r: NativeRemote.Entry) async {
        guard let http = model.http else { return }
        busy = r.id
        do { let id = try await NativeRemote.fetch(http, entry: r); busy = nil; canvas.open(id: id); dismiss() }
        catch let e as WorkFileError { busy = nil; failed = "Not opened. \(e.why)" }
        catch { busy = nil; failed = "Not opened. The work did not download. Pull to try again." }
    }
}

// MARK: new canvas

struct NativeNewCanvasSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var w = 2048
    @State private var h = 2048
    @State private var transparent = false
    @State private var paper = "plain"

    var body: some View {
        NavigationStack {
            Form {
                Section("Sizes") {
                    Button("Phone screen · \(Int(UIScreen.main.nativeBounds.width)) × \(Int(UIScreen.main.nativeBounds.height))") { w = Int(UIScreen.main.nativeBounds.width); h = Int(UIScreen.main.nativeBounds.height) }
                    ForEach(NativeToolkit.canvases, id: \.name) { c in
                        Button { w = c.w; h = c.h } label: { HStack { Text(c.name); Spacer(minLength: 0); Text("\(c.w) × \(c.h)").foregroundStyle(.secondary).font(.caption) } }
                    }
                }
                Section("Size in pixels") {
                    Stepper("Width \(w)", value: $w, in: 64...8192, step: 64)
                    Stepper("Height \(h)", value: $h, in: 64...8192, step: 64)
                    if w * h > 16_777_216 { Text("The largest this phone holds is 16.7 million pixels.").foregroundStyle(.red).font(.caption) }
                    else { Text("\(String(format: "%.1f", Double(w * h) / 1_000_000)) million pixels.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Paper") {
                    Picker("Stock", selection: $paper) { ForEach(NativeToolkit.papers) { Text($0.name).tag($0.id) } }
                    Toggle("Transparent background", isOn: $transparent)
                }
            }
            .navigationTitle("New canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Make it") { canvas.startNew(w: w, h: h, transparent: transparent, paperID: paper); dismiss() }.disabled(w * h > 16_777_216) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
