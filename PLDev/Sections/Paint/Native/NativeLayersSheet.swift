import SwiftUI

/// The layer list, top layer first. A tap picks the layer to paint on; the eye shows or hides it. Swipe left duplicates, swipe right deletes
/// (asks first). Touch and hold holds the rest: rename, move, alpha lock, clip. The selected layer carries its opacity and blend.
struct NativeLayersSheet: View {
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Int?
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(canvas.layerRows.reversed()) { row in
                        let on = row.id == canvas.activeLayer
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button { canvas.setLayer("vis", !row.visible, at: row.id) } label: { Image(systemName: row.visible ? "eye" : "eye.slash").frame(width: 28) }
                                    .buttonStyle(.plain).accessibilityLabel(row.visible ? "Hide \(row.name)" : "Show \(row.name)")
                                Button { canvas.setActive(row.id) } label: {
                                    VStack(alignment: .leading) {
                                        Text(row.name).foregroundStyle(.primary)
                                        Text(subtitle(row)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                                Spacer(minLength: 0)
                                if on { Image(systemName: "checkmark").foregroundStyle(Wallpaper.line) }
                            }
                            if on {
                                HStack {
                                    Image(systemName: "circle.lefthalf.filled").font(.caption)
                                    Slider(value: Binding(get: { row.opacity }, set: { canvas.setLayer("op", (($0) * 100).rounded() / 100, at: row.id) }), in: 0...1)
                                        .accessibilityLabel("Layer opacity")
                                    Text("\(Int((row.opacity * 100).rounded()))%").font(.caption).monospacedDigit().frame(width: 40, alignment: .trailing)
                                }
                                Picker("Blend", selection: Binding(get: { row.blend }, set: { canvas.setLayer("blend", $0, at: row.id) })) {
                                    ForEach(NativeBlend.modes) { Text($0.label).tag($0.id) }
                                }.pickerStyle(.menu)
                            }
                        }
                        .swipeActions(edge: .trailing) { Button("Duplicate") { canvas.setActive(row.id); canvas.duplicateLayer() }.tint(.blue) }
                        .swipeActions(edge: .leading) { Button("Delete", role: .destructive) { canvas.setActive(row.id); confirmDelete = true } }
                        .contextMenu {
                            Button { renaming = row.id; newName = row.name } label: { Label("Rename", systemImage: "pencil") }
                            Button { canvas.setActive(row.id); canvas.moveLayer(1) } label: { Label("Move up", systemImage: "arrow.up") }
                            Button { canvas.setActive(row.id); canvas.moveLayer(-1) } label: { Label("Move down", systemImage: "arrow.down") }
                            Button { canvas.setLayer("lock", !row.lock, at: row.id) } label: { Label(row.lock ? "Unlock alpha" : "Lock alpha", systemImage: "lock") }
                            Button { canvas.setLayer("clip", !row.clip, at: row.id) } label: { Label(row.clip ? "Release clip" : "Clip to the layer below", systemImage: "arrow.down.right.and.arrow.up.left") }
                        }
                    }
                } footer: { Text("Touch and hold a layer for rename, move, lock and clip.") }
                if let l = canvas.line { Section { ResultLine(text: l) } }
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { canvas.addLayer() } label: { Label("New layer", systemImage: "plus") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename layer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let i = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty { canvas.setLayer("name", String(newName.prefix(40)), at: i) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Delete this layer?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete layer", role: .destructive) { canvas.deleteLayer() }
            } message: { Text("Its pixels are gone and undo starts again from here.") }
            .sensoryFeedback(PLHaptic.select, trigger: canvas.activeLayer)
        }
    }

    private func subtitle(_ r: LayerRow) -> String {
        var bits: [String] = [NativeBlend.mode(r.blend).label, "\(Int((r.opacity * 100).rounded()))%"]
        if r.lock { bits.append("alpha locked") }
        if r.clip { bits.append("clipped") }
        if r.blend.hasPrefix("x-") { bits.append("shown as Normal for now") }
        return bits.joined(separator: " · ")
    }
}
