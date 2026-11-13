import SwiftUI

// The Library (components/AssetBrowser.tsx): every asset the laptop's index knows, a filter, a chip per catalog, thumbnails, and a tap that
// attaches the asset to the selected shot. It is the whole of the 1,654-row index, 100 at a time, not a sample.

struct ComposerLibraryRoom: View {
    let model: AppModel
    /// Set when the library is opened from a shot: taps attach to it and the sheet stays open for more.
    var attachTo: String? = nil
    @State private var lib = ComposerLibrary.shared
    @State private var store = ComposerPieces.shared
    @State private var q = ""
    @State private var catalog: String?
    @State private var kind: String?
    @State private var limit = 100
    @State private var detail: ComposerAsset?
    @State private var note: String?
    @State private var tick = 0

    private var needle: String { q.trimmingCharacters(in: .whitespaces).lowercased() }
    private var filtered: [ComposerAsset] {
        lib.assets.filter { a in
            (catalog == nil || a.catalog == catalog) && (kind == nil || a.kind == kind)
                && (needle.isEmpty || a.name.lowercased().contains(needle) || a.ext.contains(needle) || a.tags.contains { $0.lowercased().contains(needle) })
        }
    }
    private var target: ComposerShot? {
        let id = attachTo ?? store.selected ?? store.piece.shots.last?.id
        return store.piece.shots.first { $0.id == id }
    }
    private var targetLabel: String? {
        guard let t = target, let i = store.piece.shots.firstIndex(where: { $0.id == t.id }) else { return nil }
        return "Shot " + String(format: "%02d", i + 1) + ": " + t.title
    }

    var body: some View {
        let rows = filtered
        List {
            Section { header(rows.count).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)) }
            if lib.manifest == nil {
                Section {
                    if let f = lib.failed {
                        ContentUnavailableView { Label("The library did not load", systemImage: "wifi.exclamationmark") } description: { Text(f) } actions: { Button("Try again") { Task { await lib.load(model: model, force: true) } }.buttonStyle(CMPPill(primary: true)) }
                    } else { ProgressView("Reading the library…").frame(maxWidth: .infinity, minHeight: 160).tint(CMP.gold) }
                }.listRowBackground(Color.clear)
            } else if rows.isEmpty {
                Section { ContentUnavailableView.search(text: q).listRowBackground(Color.clear) }
            } else {
                Section {
                    ForEach(rows.prefix(limit)) { a in
                        row(a).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .swipeActions(edge: .trailing) { Button { attach(a) } label: { Label("Attach", systemImage: "plus") }.tint(CMP.gold).disabled(target == nil) }
                    }
                    if rows.count > limit {
                        Button { limit += 100 } label: { Text("Show more: \((rows.count - limit).formatted()) not shown").font(.system(size: 13)).foregroundStyle(CMP.gold).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.plain).listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, prompt: "Filter by name, extension or tag")
        .onChange(of: q) { limit = 100 }
        .onChange(of: catalog) { limit = 100 }
        .onChange(of: kind) { limit = 100 }
        .sheet(item: $detail) { a in AssetDetail(asset: a, store: store, attach: attach) }
        .refreshable { await lib.load(model: model, force: true) }
        .sensoryFeedback(PLHaptic.select, trigger: tick)
        .task { await lib.load(model: model) }
    }

    private func attach(_ a: ComposerAsset) {
        guard let t = target else { note = "Add a shot first, then attach assets to it."; return }
        if t.sourceIds.contains(a.id) { note = "\(a.name) is already on \"\(t.title)\"."; return }
        _ = store.attach(a, to: t.id); tick += 1
        note = "Attached \(a.name) to \"\(t.title)\"."
    }

    private func header(_ shown: Int) -> some View {
        let total = lib.manifest?.total ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library").cmpLabel(11)
                Spacer()
                Text("\(shown.formatted())\(shown != total ? " of \(total.formatted())" : "") assets").cmpNum(11).foregroundStyle(CMP.muted)
            }
            if let m = lib.manifest {
                Text("indexed \(m.generated.replacingOccurrences(of: "T", with: " "))\(m.probed ? "" : " · durations not probed")").cmpNum(10).foregroundStyle(CMP.muted)
            }
            if let l = targetLabel { Text("tap an asset: attaches to \(l)").font(.system(size: 11)).foregroundStyle(CMP.goldDim) }
            else { Text("add a shot to attach assets").font(.system(size: 11)).foregroundStyle(CMP.muted) }
            if let n = note { Text(n).font(.system(size: 11)).foregroundStyle(CMP.dim) }
            let missing = lib.manifest?.roots.filter { !$0.present } ?? []
            if !missing.isEmpty {
                Text("\(missing.count) root\(missing.count > 1 ? "s" : "") not mounted. This list is incomplete: \(missing.map(\.catalog).joined(separator: ", ")).")
                    .font(.system(size: 11)).foregroundStyle(CMP.warn).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CMP.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    CMPChip(title: "all", count: shownTotal, on: catalog == nil) { catalog = nil }
                    ForEach(lib.catalogs(matching: q)) { c in CMPChip(title: c.name, count: c.count, on: catalog == c.name) { catalog = (catalog == c.name) ? nil : c.name } }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    CMPChip(title: "any type", on: kind == nil) { kind = nil }
                    ForEach(["media", "curve", "path", "audio", "model"], id: \.self) { k in
                        let n = lib.assets.filter { $0.kind == k }.count
                        if n > 0 { CMPChip(title: k, count: n, on: kind == k) { kind = (kind == k) ? nil : k } }
                    }
                }
            }
        }
        .cmpCard(padding: 12)
    }
    private var shownTotal: Int { lib.catalogs(matching: q).reduce(0) { $0 + $1.count } }

    private func row(_ a: ComposerAsset) -> some View {
        let on = target?.sourceIds.contains(a.id) == true
        return Button { attach(a) } label: {
            HStack(spacing: 10) {
                Group {
                    if let img = lib.image(a.id) { Image(uiImage: img).resizable().scaledToFill() }
                    else { Text(String(a.socket.rawValue.prefix(3))).font(.system(size: 9, design: .monospaced)).textCase(.uppercase).foregroundStyle(a.socket.color) }
                }
                .frame(width: 44, height: 44).background(CMP.well).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.system(size: 14)).foregroundStyle(CMP.text).lineLimit(1)
                    HStack(spacing: 6) {
                        CMPDot(color: a.socket.color, size: 6)
                        Text([a.socket.rawValue, a.catalog, a.ext.replacingOccurrences(of: ".", with: ""), composerBytes(a.bytes)].joined(separator: " · ")).cmpNum(10).foregroundStyle(CMP.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if let d = a.duration, d > 0 { Text(composerClock(d)).cmpNum(11).foregroundStyle(CMP.goldDim) }
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(CMP.gold).accessibilityLabel("Attached") }
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { attach(a) } label: { Label("Attach to the shot", systemImage: "plus") }.disabled(target == nil)
            Menu {
                ForEach(Array(store.piece.shots.enumerated()), id: \.element.id) { i, s in
                    Button { _ = store.attach(a, to: s.id); tick += 1; note = "Attached \(a.name) to \"\(s.title)\"." } label: { Text("\(String(format: "%02d", i + 1))  \(s.title)") }
                }
            } label: { Label("Attach to another shot", systemImage: "film.stack") }
            Button { detail = a } label: { Label("Details", systemImage: "info.circle") }
            Button { UIPasteboard.general.string = a.id } label: { Label("Copy the id", systemImage: "number") }
            Button { UIPasteboard.general.string = a.path } label: { Label("Copy the path", systemImage: "doc.on.doc") }
        }
        .accessibilityLabel("\(a.name), \(a.socket.rawValue), \(a.catalog)" + (on ? ", attached" : ""))
        .accessibilityHint("Attaches it to the selected shot")
    }
}

/// What an asset is and where it lives on the laptop (the tooltip the web gives each row, with room to read it).
struct AssetDetail: View {
    let asset: ComposerAsset
    let store: ComposerPieces
    let attach: (ComposerAsset) -> Void
    @State private var lib = ComposerLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        if let img = lib.image(asset.id) { Image(uiImage: img).resizable().scaledToFit() }
                        else { Image(systemName: asset.kind == "audio" ? "waveform" : asset.kind == "model" ? "cube" : asset.kind == "curve" ? "scribble" : "photo").font(.system(size: 44)).foregroundStyle(asset.socket.color) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 280).background(CMP.well).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(asset.name + asset.ext).font(.system(size: 20, design: .serif)).foregroundStyle(CMP.text)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { CMPDot(color: asset.socket.color); Text(asset.socket.rawValue).font(.system(size: 14, weight: .medium)).foregroundStyle(CMP.text); Text(asset.socket.carries).font(.system(size: 13)).foregroundStyle(CMP.dim) }
                        Text(asset.socket.why).font(.system(size: 13)).foregroundStyle(CMP.dim)
                    }.cmpCard()
                    VStack(alignment: .leading, spacing: 8) {
                        line("catalog", asset.catalog); line("size", composerBytes(asset.bytes))
                        if let d = asset.duration { line("length", composerClock(d)) }
                        if let w = asset.width, let h = asset.height { line("picture", "\(w)×\(h)") }
                        if !asset.tags.isEmpty { line("tags", asset.tags.joined(separator: ", ")) }
                        line("id", asset.id); line("path", asset.path)
                    }.cmpCard()
                    if !store.piece.shots.isEmpty {
                        Text("Attach to").cmpLabel(10)
                        ForEach(Array(store.piece.shots.enumerated()), id: \.element.id) { i, s in
                            Button { _ = store.attach(asset, to: s.id); dismiss() } label: {
                                HStack { Text(String(format: "%02d", i + 1)).cmpNum(12).foregroundStyle(CMP.muted); Text(s.title).foregroundStyle(CMP.text); Spacer()
                                    if s.sourceIds.contains(asset.id) { Image(systemName: "checkmark").foregroundStyle(CMP.gold) } }
                                    .padding(.vertical, 4).frame(minHeight: 44)
                            }.buttonStyle(.plain).cmpCard(padding: 10)
                        }
                    }
                }
                .padding(PLSpace.margin)
            }
            .cmpScreen().navigationTitle("Asset").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(k).cmpLabel(9).frame(width: 64, alignment: .leading); Text(v).cmpNum(11).foregroundStyle(CMP.dim).textSelection(.enabled); Spacer(minLength: 0) }
    }
}
