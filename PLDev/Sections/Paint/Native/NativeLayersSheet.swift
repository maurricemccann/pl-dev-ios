import SwiftUI

/// The layer list, top layer first, with groups. A tap picks the layer to paint on; the eye shows or hides it (hold it for solo). Swipe to
/// duplicate, merge down or delete; touch and hold for the rest. The selected layer (or group) carries its opacity, blend and glow.
struct NativeLayersSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Int?
    @State private var renamingGroup: Int?
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var editing = false

    private var rows: [LayerRow] { canvas.layerRows.reversed() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        if isGroupTop(row) { groupHeader(row.group) }
                        if row.group == 0 || groupOpen(row.group) { layerRow(row).listRowInsets(EdgeInsets(top: 6, leading: row.group == 0 ? 16 : 34, bottom: 6, trailing: 16)) }
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        let n = rows.count
                        canvas.reorderLayer(from: n - 1 - f, to: n - 1 - (to > f ? to - 1 : to))
                    }
                } footer: { Text("Touch and hold a layer for rename, move, lock, clip, reference and assist. Hold the eye to see only that layer.") }
                controls
                if let l = canvas.line { Section { ResultLine(text: l) } }
            }
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(editing ? "Done moving" : "Move") { editing.toggle() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil || renamingGroup != nil }, set: { if !$0 { renaming = nil; renamingGroup = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    let n = String(newName.trimmingCharacters(in: .whitespaces).prefix(24))
                    if !n.isEmpty { if let i = renaming { canvas.setLayer("name", n, at: i) } else if let g = renamingGroup { canvas.setGroup(g, "name", n) } }
                    renaming = nil; renamingGroup = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil; renamingGroup = nil }
            }
            .confirmationDialog(canvas.selectedGroup != 0 ? "Delete this group and its layers?" : "Delete this layer?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { canvas.deleteLayer() }
            } message: { Text("Undo brings it back.") }
        }
    }

    // MARK: rows

    private func isGroupTop(_ r: LayerRow) -> Bool {
        guard r.group != 0 else { return false }
        return r.id == canvas.layerRows.lastIndex { $0.group == r.group }
    }
    private func groupOpen(_ id: Int) -> Bool { canvas.groupRows.first { $0.id == id }?.open ?? true }

    private func groupHeader(_ id: Int) -> some View {
        let g = canvas.groupRows.first { $0.id == id }
        return HStack {
            Button { canvas.setGroup(id, "open", !(g?.open ?? true), history: false) } label: { Image(systemName: (g?.open ?? true) ? "chevron.down" : "chevron.right").frame(width: 22) }.buttonStyle(.plain)
            Image(systemName: "folder")
            Text(g?.name ?? "Group").font(.subheadline.weight(.semibold))
            Spacer()
            Text(blendLetter(g?.blend ?? "source-over") + ((g?.opacity ?? 1) < 1 ? " \(Int((g?.opacity ?? 1) * 100))" : "")).font(.caption2).foregroundStyle(.secondary)
            Button { canvas.setGroup(id, "vis", !(g?.visible ?? true)) } label: { Image(systemName: (g?.visible ?? true) ? "eye" : "eye.slash") }.buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .listRowBackground(canvas.selectedGroup == id ? Wallpaper.line.opacity(0.18) : nil)
        .onTapGesture { canvas.selectGroup(id) }
        .contextMenu {
            Button { renamingGroup = id; newName = g?.name ?? "" } label: { Label("Rename the group", systemImage: "pencil") }
            Button { canvas.selectedGroup = id; canvas.groupButton() } label: { Label("Ungroup", systemImage: "rectangle.3.group") }
            Button { canvas.selectedGroup = id; canvas.mergeGroup() } label: { Label("Merge the group", systemImage: "arrow.triangle.merge") }
            Button { canvas.selectedGroup = id; canvas.moveGroup(1) } label: { Label("Move up", systemImage: "arrow.up") }
            Button { canvas.selectedGroup = id; canvas.moveGroup(-1) } label: { Label("Move down", systemImage: "arrow.down") }
            Button(role: .destructive) { canvas.selectedGroup = id; confirmDelete = true } label: { Label("Delete the group", systemImage: "trash") }
        }
    }

    private func layerRow(_ row: LayerRow) -> some View {
        let on = row.id == canvas.activeLayer && canvas.selectedGroup == 0
        return HStack(spacing: 10) {
            Button { canvas.toggleVisible(row.id) } label: { Image(systemName: row.visible ? "eye" : "eye.slash").frame(width: 26) }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in canvas.soloLayer(row.id) })
                .accessibilityLabel(row.visible ? "Hide \(row.name)" : "Show \(row.name)")
            LayerThumb(canvas: canvas, index: row.id, version: canvas.docVersion).frame(width: 46, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if row.clip { Image(systemName: "arrow.turn.down.right").font(.caption2) }
                    Text(row.name).lineLimit(1)
                    if row.ref { tag("ref") }
                    if row.assist == true || (row.assist == nil && canvas.assist && canvas.guide != .off) { tag("assist") }
                }
                Text(subtitle(row)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if row.hasMask {
                Button { canvas.setActive(row.id); canvas.maskEditing.toggle(); canvas.syncFlags() } label: {
                    Image(systemName: "circle.lefthalf.filled.inverse").padding(5)
                        .background(on && canvas.maskEditing ? Wallpaper.line.opacity(0.4) : Color.clear, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Paint the mask")
            }
            if on { Image(systemName: "checkmark").foregroundStyle(Wallpaper.line) }
        }
        .contentShape(Rectangle())
        .listRowBackground(on ? Wallpaper.line.opacity(0.18) : nil)
        .onTapGesture { canvas.setActive(row.id) }
        .swipeActions(edge: .trailing) {
            Button("Duplicate") { canvas.setActive(row.id); canvas.duplicateLayer() }.tint(.blue)
            Button("Merge down") { canvas.setActive(row.id); canvas.mergeDown() }.tint(.indigo)
        }
        .swipeActions(edge: .leading) { Button("Delete", role: .destructive) { canvas.setActive(row.id); confirmDelete = true } }
        .contextMenu {
            Button { renaming = row.id; newName = row.name } label: { Label("Rename", systemImage: "pencil") }
            Button { canvas.setActive(row.id); canvas.moveLayer(1) } label: { Label("Move up", systemImage: "arrow.up") }
            Button { canvas.setActive(row.id); canvas.moveLayer(-1) } label: { Label("Move down", systemImage: "arrow.down") }
            Button { canvas.setLayer("lock", !row.lock, at: row.id) } label: { Label(row.lock ? "Unlock alpha" : "Lock alpha", systemImage: "lock") }
            Button { canvas.setActive(row.id); canvas.toggleClip() } label: { Label(row.clip ? "Release clip" : "Clip to the layer below", systemImage: "arrow.down.right.and.arrow.up.left") }
            Button { canvas.setActive(row.id); canvas.toggleRef() } label: { Label(row.ref ? "Not a reference" : "Reference layer", systemImage: "scope") }
            Button { canvas.toggleLayerAssist(row.id) } label: { Label("Assisted drawing on this layer", systemImage: "square.split.diagonal") }
            if row.hasMask {
                Button { canvas.setActive(row.id); canvas.applyMask() } label: { Label("Apply the mask", systemImage: "checkmark.circle") }
                Button(role: .destructive) { canvas.setActive(row.id); canvas.deleteMask() } label: { Label("Delete the mask", systemImage: "trash") }
            }
        }
    }

    private func tag(_ t: String) -> some View { Text(t).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1).background(Color.secondary.opacity(0.2), in: Capsule()) }
    private func blendLetter(_ id: String) -> String {
        let m: [String: String] = ["source-over": "N", "multiply": "M", "screen": "S", "overlay": "O", "darken": "D", "lighten": "L", "color-dodge": "CD", "color-burn": "CB", "hard-light": "HL", "soft-light": "SL", "difference": "DF", "exclusion": "EX", "hue": "H", "saturation": "SA", "color": "C", "luminosity": "LU"]
        return m[id] ?? "X"
    }
    private func subtitle(_ r: LayerRow) -> String {
        var bits: [String] = [NativeBlend.mode(r.blend).label, "\(Int((r.opacity * 100).rounded()))%"]
        if r.lock { bits.append("alpha locked") }
        if r.glow > 0 { bits.append("glow") }
        return bits.joined(separator: " · ")
    }

    // MARK: the selected layer or group

    @ViewBuilder private var controls: some View {
        if canvas.selectedGroup != 0, let g = canvas.groupRows.first(where: { $0.id == canvas.selectedGroup }) {
            Section("Group · \(g.name)") {
                HStack {
                    Image(systemName: "circle.lefthalf.filled").font(.caption)
                    Slider(value: Binding(get: { g.opacity }, set: { canvas.setGroup(g.id, "op", ($0 * 100).rounded() / 100, history: false) }), in: 0...1) { e in if !e { canvas.markChanged() } }
                    Text("\(Int((g.opacity * 100).rounded()))%").font(.caption).monospacedDigit().frame(width: 40)
                }
                Picker("Blend", selection: Binding(get: { g.blend }, set: { canvas.setGroup(g.id, "blend", $0) })) { ForEach(NativeBlend.modes) { Text($0.label).tag($0.id) } }
                actions
            }
        } else if let row = canvas.layerRows.first(where: { $0.id == canvas.activeLayer }) {
            Section("Layer · \(row.name)") {
                HStack {
                    Image(systemName: "circle.lefthalf.filled").font(.caption)
                    Slider(value: Binding(get: { row.opacity }, set: { canvas.setLayer("op", ($0 * 100).rounded() / 100, at: row.id, history: false) }), in: 0...1) { e in
                        if e { canvas.beginLayerEdit("op", at: row.id) } else { canvas.endLayerEdit(); canvas.markChanged() }
                    }.accessibilityLabel("Layer opacity")
                    Text("\(Int((row.opacity * 100).rounded()))%").font(.caption).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Picker("Blend", selection: Binding(get: { row.blend }, set: { canvas.setLayer("blend", $0, at: row.id) })) {
                    ForEach(NativeBlend.modes) { Text($0.label).tag($0.id) }
                }.pickerStyle(.menu)
                HStack {
                    Image(systemName: "sparkles").font(.caption)
                    Slider(value: Binding(get: { row.glow }, set: { canvas.setLayer("glow", ($0 * 100).rounded() / 100, at: row.id, history: false) }), in: 0...1) { e in
                        if e { canvas.beginLayerEdit("glow", at: row.id) } else { canvas.endLayerEdit(); canvas.markChanged() }
                    }.accessibilityLabel("Glow")
                    Text("Glow").font(.caption).frame(width: 40, alignment: .trailing)
                }
                Toggle("Alpha lock (paints only where there are pixels)", isOn: Binding(get: { row.lock }, set: { canvas.setLayer("lock", $0, at: row.id) }))
                Toggle("Clip to the layer below", isOn: Binding(get: { row.clip }, set: { _ in canvas.setActive(row.id); canvas.toggleClip() }))
                actions
            }
        }
    }

    @ViewBuilder private var actions: some View {
        let hasMask = canvas.layerRows.first { $0.id == canvas.activeLayer }?.hasMask ?? false
        HStack(spacing: 8) {
            Button { canvas.addLayer() } label: { Label("New", systemImage: "plus") }
            Button { canvas.duplicateLayer() } label: { Label("Copy", systemImage: "plus.square.on.square") }
            Button { canvas.mergeDown() } label: { Label("Merge", systemImage: "arrow.down.to.line") }
            Button { canvas.groupButton() } label: { Label(canvas.selectedGroup != 0 || (canvas.layerRows.first { $0.id == canvas.activeLayer }?.group ?? 0) != 0 ? "Ungroup" : "Group", systemImage: "folder") }
        }.buttonStyle(.bordered).controlSize(.small).labelStyle(.titleAndIcon)
        HStack(spacing: 8) {
            Button { canvas.maskButton() } label: { Label(!hasMask ? "Add mask" : canvas.maskEditing ? "Paint layer" : "Paint mask", systemImage: "circle.lefthalf.filled.inverse") }
            Button { canvas.toggleRef() } label: { Label("Reference", systemImage: "scope") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }.buttonStyle(.bordered).controlSize(.small).labelStyle(.titleAndIcon)
    }
}

/// A small picture of one layer over a light checker, redrawn when the work changes.
struct LayerThumb: View {
    let canvas: NativeCanvasModel
    let index: Int
    let version: Int
    var body: some View {
        Group {
            if let d = canvas.doc, d.layers.indices.contains(index), let img = thumb(d.layers[index]) { Image(uiImage: img).resizable().scaledToFit() }
            else { Color.secondary.opacity(0.1) }
        }
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    private func thumb(_ l: NativeLayer) -> UIImage? {
        guard let src = l.pixels.image() else { return nil }
        let k = 92.0 / Double(max(src.width, src.height)), w = max(1, Int(Double(src.width) * k)), h = max(1, Int(Double(src.height) * k))
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .medium
        c.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage().map { UIImage(cgImage: $0) }
    }
}
