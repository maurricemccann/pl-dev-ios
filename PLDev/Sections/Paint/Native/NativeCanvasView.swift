import SwiftUI
import UIKit

/// The entry point the lead wires: a row "Native canvas (beta)" on the Paint home presents `NativeCanvasView(model:)`.
/// P1: one round brush with Pencil pressure, zoom and twist and pan, undo and redo (patch stack of 250), his works saved on the phone,
/// and his synced works read from pl-cron. The web canvas (`PaintCanvas`) stays his working painter until this one is ready.
struct NativeCanvasView: View {
    let model: AppModel
    @State private var canvas = NativeCanvasModel()
    @State private var showWorks = false
    @State private var showSizes = false
    @State private var showBrushes = false
    @State private var showLayers = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            CanvasRepresentable(model: canvas).ignoresSafeArea()
            if !canvas.hasDoc {
                ContentUnavailableView {
                    Label("No canvas open", systemImage: "paintbrush.pointed")
                } description: {
                    Text("Open one of your works, or start a new canvas.")
                } actions: {
                    Button("Works") { showWorks = true }.buttonStyle(.borderedProminent)
                    Button("New canvas") { showSizes = true }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                topBar
                Spacer(minLength: 0)
                if let l = canvas.line { ResultLine(text: l).padding(8).glassControl(in: Capsule()) }
                if canvas.hasDoc { bottomBar }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showWorks) { NativeWorksSheet(model: model, canvas: canvas) }
        .sheet(isPresented: $showBrushes) { NativeBrushSheet(canvas: canvas) }
        .sheet(isPresented: $showLayers) { NativeLayersSheet(canvas: canvas).presentationDetents([.medium, .large]) }
        .confirmationDialog("New canvas", isPresented: $showSizes, titleVisibility: .visible) {
            Button("Phone screen") { let s = UIScreen.main.nativeBounds.size; canvas.startNew(w: Int(s.width), h: Int(s.height)) }
            Button("2048 × 2048") { canvas.startNew(w: 2048, h: 2048) }
            Button("3000 × 3000") { canvas.startNew(w: 3000, h: 3000) }
            Button("4096 × 4096") { canvas.startNew(w: 4096, h: 4096) }
        } message: { Text("The largest this phone holds is 16.7 million pixels.") }
        .sensoryFeedback(PLHaptic.select, trigger: canvas.activeLayer)
        .onChange(of: phase) { _, p in if p != .active { canvas.saveNow() } }
        .task { restoreLast() }
        .onDisappear { canvas.saveNow() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { canvas.saveNow(); dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                .glassControl(in: Circle()).accessibilityLabel("Close the canvas")
            Button { showWorks = true } label: { Image(systemName: "square.grid.2x2").frame(width: 36, height: 36) }
                .glassControl(in: Circle()).accessibilityLabel("Works")
            Button { showSizes = true } label: { Image(systemName: "plus").frame(width: 36, height: 36) }
                .glassControl(in: Circle()).accessibilityLabel("New canvas")
            Spacer(minLength: 0)
            if canvas.hasDoc {
                Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d").frame(width: 36, height: 36) }
                    .glassControl(in: Circle()).accessibilityLabel("Layers")
                Button { canvas.undoStroke() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 36) }
                    .glassControl(in: Circle()).disabled(!canvas.canUndo).accessibilityLabel("Undo")
                Button { canvas.redoStroke() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 36) }
                    .glassControl(in: Circle()).disabled(!canvas.canRedo).accessibilityLabel("Redo")
                Button { share() } label: { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36) }
                    .glassControl(in: Circle()).accessibilityLabel("Share the picture")
                Button { canvas.stage?.fit() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass").frame(width: 36, height: 36) }
                    .glassControl(in: Circle()).accessibilityLabel("Fit to screen")
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Picker("Tool", selection: $canvas.tool) {
                    Image(systemName: "paintbrush.pointed.fill").tag(NativeTool.paint)
                    Image(systemName: "eraser.fill").tag(NativeTool.erase)
                }.pickerStyle(.segmented).frame(width: 90)
                Button { showBrushes = true } label: { Label(canvas.brush.name, systemImage: "paintbrush.pointed").lineLimit(1) }
                    .buttonStyle(.bordered).accessibilityLabel("Brush: \(canvas.brush.name)")
                ColorPicker("Colour", selection: $canvas.color, supportsOpacity: false).labelsHidden()
                if canvas.brush.needsTwinColour { ColorPicker("Companion colour", selection: $canvas.color2, supportsOpacity: false).labelsHidden() }
                Toggle(isOn: $canvas.fingerPaints) { Image(systemName: "hand.point.up.left") }
                    .toggleStyle(.button).accessibilityLabel("Finger paints")
                Spacer(minLength: 0)
                Text(canvas.docSize).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "circle.fill").font(.system(size: 6))
                Slider(value: $canvas.size, in: 1...200).accessibilityLabel("Brush size")
                Image(systemName: "circle.fill").font(.system(size: 18))
            }
            HStack {
                Image(systemName: "circle.lefthalf.filled").font(.caption)
                Slider(value: $canvas.opacity, in: 0.05...1).accessibilityLabel("Opacity")
            }
        }
        .padding(12).glassControl(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// The flat picture, blends and clips applied, through the share sheet (Photos, Files, Messages).
    private func share() {
        guard let d = canvas.doc, let png = d.flatPNG() else { canvas.say("Not shared. The picture could not be made."); return }
        let safe = canvas.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Untitled" : safe).png")
        do { try png.write(to: url) } catch { canvas.say("Not shared. The file could not be written."); return }
        var top = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let p = top?.presentedViewController { top = p }
        top?.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }

    /// The work he had open last time, if the phone still has it.
    private func restoreLast() {
        guard !canvas.hasDoc, let id = NativeStore.loadIndex().current else { return }
        canvas.open(id: id)
    }
}

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

    var body: some View {
        NavigationStack {
            List {
                Section("On this phone") {
                    if local.isEmpty { Text("Nothing saved here yet.").foregroundStyle(.secondary) }
                    ForEach(Array(local.enumerated()), id: \.offset) { _, e in
                        let id = e["id"] as? String ?? ""
                        Button { canvas.open(id: id); dismiss() } label: { row(name: e["name"] as? String ?? "Untitled", w: e["w"] as? Int ?? 0, h: e["h"] as? Int ?? 0, thumb: thumb(e["thumb"] as? String)) }
                            .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { confirmDelete = id } }
                    }
                }
                Section {
                    if loading { ProgressView() }
                    if let f = failed { Text(f).foregroundStyle(.secondary) }
                    ForEach(remote.filter { r in !local.contains { ($0["id"] as? String) == r.id } }) { r in
                        Button { Task { await fetch(r) } } label: {
                            HStack { row(name: r.name, w: r.w, h: r.h, thumb: r.thumb); if busy == r.id { ProgressView() } }
                        }.disabled(busy != nil)
                    }
                } header: { Text("From the laptop") } footer: { Text("Tap one to bring it onto this phone. It opens from here.") }
            }
            .navigationTitle("Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { reload(); await load() }
            .confirmationDialog("Delete this work from the phone?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let id = confirmDelete { canvas.delete(id: id); reload() }; confirmDelete = nil }
            } message: { Text("The copy on the laptop stays.") }
        }
    }

    private func row(name: String, w: Int, h: Int, thumb: UIImage?) -> some View {
        HStack(spacing: 12) {
            Group { if let t = thumb { Image(uiImage: t).resizable().scaledToFit() } else { Color.secondary.opacity(0.12) } }
                .frame(width: 56, height: 56).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading) { Text(name).foregroundStyle(.primary); Text("\(w) × \(h)").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func thumb(_ s: String?) -> UIImage? { s.flatMap { NativeDoc.image(fromDataURL: $0) }.map { UIImage(cgImage: $0) } }
    private func reload() { local = NativeStore.loadIndex().list }

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
