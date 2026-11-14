import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// PL Paint's own look (its `style.css`): thin glass panels on the dark ground, labels small and spaced.
private struct PaintPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}
extension View {
    func paintPanel() -> some View { modifier(PaintPanel()) }
    /// A panel label: small, spaced, upper case, as the app's own.
    func paintLabel() -> some View { font(.caption.weight(.semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(PaintSkin.text.opacity(0.55)) }
}

/// What a gallery card shares: the work in a format, written to a temporary file.
@MainActor enum PaintGalleryOps {
    enum Kind: String, CaseIterable { case png = "PNG", jpg = "JPEG", psd = "PSD", pdf = "PDF" }

    static func file(id: String, name: String, kind: Kind) -> URL? {
        guard let d = try? NativeStore.load(id) else { return nil }
        let data: Data?
        switch kind { case .png: data = NativeExport.png(d); case .jpg: data = NativeExport.jpeg(d); case .psd: data = NativeExport.psd(d); case .pdf: data = NativeExport.pdf(d) }
        guard let data else { return nil }
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe) \(NativeExport.stamp()).\(kind.rawValue.lowercased())")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    static func rename(id: String, to n: String) {
        let t = String(n.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !t.isEmpty else { return }
        var ix = NativeStore.loadIndex()
        guard let k = ix.list.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
        ix.list[k]["name"] = t; ix.list[k]["updated"] = Date().timeIntervalSince1970 * 1000
        try? NativeStore.saveIndex(ix)
    }

    /// A picture sized to fit a canvas this phone can hold (16.7 million pixels at most, 8192 a side).
    static func canvasSize(for img: CGImage) -> (Int, Int) {
        var w = Double(img.width), h = Double(img.height)
        let k = min(1, 8192 / max(w, h), (16_000_000 / (w * h)).squareRoot())
        w = max(64, (w * k).rounded(.down)); h = max(64, (h * k).rounded(.down))
        return (Int(w), Int(h))
    }
}

/// The Gallery: the first screen, as on the laptop and in Procreate. Every work as a card, stacks as folders, a card for a new canvas, the Daily Mark above.
struct PaintHome: View {
    let model: AppModel
    @Bindable var state: PaintModel
    @State private var handbook = false
    @State private var syncing = false
    @State private var newSheet = false
    @State private var openStack: String?
    @State private var renaming: PaintModel.Work?
    @State private var renameText = ""
    @State private var stacking: PaintModel.Work?
    @State private var stackName = ""
    @State private var deleting: PaintModel.Work?
    @State private var shareURL: URL?
    @State private var photo: PhotosPickerItem?
    @State private var photoSheet = false
    @State private var files = false
    @State private var line: String?
    @State private var busy: String?
    private let sync = NativeSync.shared

    init(model: AppModel, state: PaintModel) { self.model = model; self.state = state }

    private var stacks: [(name: String, works: [PaintModel.Work])] {
        var names: [String] = []
        for w in state.works { if let s = w.stack, !names.contains(s) { names.append(s) } }
        return names.map { n in (n, state.works.filter { $0.stack == n }) }
    }
    private var shown: [PaintModel.Work] { state.works.filter { openStack == nil ? $0.stack == nil : $0.stack == openStack } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                dailyMark
                grid
                if let line { Text(line).font(.footnote).foregroundStyle(PaintSkin.text.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("gallery.line") }
                if !state.outbox.isEmpty { waiting }
                syncPanel
                Button { handbook = true } label: {
                    HStack { Label("The handbook", systemImage: "book"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(PaintSkin.text.opacity(0.4)) }.paintPanel()
                }.buttonStyle(.plain)
                if let f = state.failed { Text(f).font(.footnote).foregroundStyle(PaintSkin.text.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .foregroundStyle(PaintSkin.text)
        .tint(PaintSkin.gold)
        .background(PaintSkin.ground.ignoresSafeArea())
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { photoSheet = true } label: { Label("A photo, as a new work", systemImage: "photo.on.rectangle") }
                    Button { files = true } label: { Label("A file: PSD, a picture, a work, brushes", systemImage: "folder") }
                } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Import").accessibilityIdentifier("gallery.import")
                Button { newSheet = true } label: { Image(systemName: "plus") }.accessibilityLabel("New canvas").accessibilityIdentifier("gallery.new")
            }
        }
        .refreshable { await state.load(model: model) }
        .task { await state.load(model: model) }
        .fullScreenCover(item: $state.request, onDismiss: { Task { await state.load(model: model) } }) { r in NativeCanvasView(model: model, openID: r.work, openPanel: r.panel, setup: r.setup) }
        .sheet(isPresented: $handbook) { NativeHandbookView() }
        .sheet(isPresented: $newSheet) { NativeNewCanvasSheet { spec in state.request = PaintCanvasRequest(work: nil, setup: { $0.make(spec) }) } }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { ShareSheet(items: [$0.url]) }
        .photosPicker(isPresented: $photoSheet, selection: $photo, matching: .images)
        .onChange(of: photo) { _, it in
            guard let it else { return }
            photo = nil
            Task {
                guard let data = try? await it.loadTransferable(type: Data.self) else { line = "That picture did not load."; return }
                bringIn(data: data, fileName: "Photo")
            }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: false) { r in
            guard case .success(let urls) = r, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { line = "That file could not be read."; return }
            bringIn(data: data, fileName: url.lastPathComponent)
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let w = renaming { PaintGalleryOps.rename(id: w.id, to: renameText); Task { await state.load(model: model) } }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Put in a stack", isPresented: Binding(get: { stacking != nil }, set: { if !$0 { stacking = nil } })) {
            TextField("Stack name", text: $stackName)
            Button("Put it there") { if let w = stacking { state.ops.setStack(id: w.id, name: stackName); Task { await state.load(model: model) } }; stacking = nil }
            Button("Cancel", role: .cancel) { stacking = nil }
        } message: { Text("Works with the same stack name sit together here and on the laptop.") }
        .confirmationDialog("Delete this work from the phone?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let w = deleting { state.ops.delete(id: w.id); if w.stack == openStack, shown.count <= 1 { openStack = nil }; Task { await state.load(model: model) } }; deleting = nil }
        } message: { Text("It is removed from the laptop too, the next time they sync.") }
        .preferredColorScheme(.dark)
    }

    private struct ShareItem: Identifiable { let url: URL; var id: String { url.path } }

    // MARK: the cards

    private var dailyMark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("The Daily Mark").paintLabel(); Spacer(); Text("\(state.streak) day\(state.streak == 1 ? "" : "s")").font(.footnote.monospacedDigit()).foregroundStyle(PaintSkin.gold2).contentTransition(.numericText()) }
            DailyMarkStrip(days: state.days)
        }
        .paintPanel()
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            Button { newSheet = true } label: {
                VStack(spacing: 8) { Image(systemName: "plus").font(.largeTitle); Text("New canvas").font(.footnote.weight(.semibold)) }
                    .frame(maxWidth: .infinity).frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PaintSkin.gold.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }.buttonStyle(.plain).accessibilityIdentifier("gallery.newcard")
            if let open = openStack {
                Button { openStack = nil } label: {
                    VStack(spacing: 8) { Image(systemName: "chevron.backward").font(.title); Text(open).font(.footnote.weight(.semibold)) }
                        .frame(maxWidth: .infinity).frame(height: 150).paintPanel()
                }.buttonStyle(.plain).accessibilityLabel("Back from the stack \(open)").accessibilityIdentifier("gallery.stackback")
            } else {
                ForEach(stacks, id: \.name) { s in
                    Button { openStack = s.name } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                Color.white.opacity(0.04)
                                if let t = s.works.first?.thumb { Image(uiImage: t).resizable().scaledToFit().background(NativeChecker().opacity(0.35)).padding(10) }
                                Image(systemName: "square.stack.3d.up.fill").padding(6).background(.ultraThinMaterial, in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(6)
                            }
                            .frame(height: 112).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(s.name).font(.footnote.weight(.semibold)).lineLimit(1)
                            Text("\(s.works.count) work\(s.works.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(PaintSkin.text.opacity(0.55))
                        }.padding(8).background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).accessibilityLabel("Stack \(s.name), \(s.works.count) works").accessibilityIdentifier("gallery.stack.\(s.name)")
                }
            }
            ForEach(shown) { w in card(w) }
        }
        .overlay { if busy != nil { PLLoader().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous)) } }
    }

    private func card(_ w: PaintModel.Work) -> some View {
        Button { open(w) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.white.opacity(0.04)
                    if let t = w.thumb { Image(uiImage: t).resizable().scaledToFit().background(NativeChecker().opacity(0.35)) }
                    if !w.here { Image(systemName: "icloud.and.arrow.down").padding(6).background(.ultraThinMaterial, in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6) }
                }
                .frame(height: 112).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(w.name).font(.footnote.weight(.semibold)).lineLimit(1)
                HStack { Text("\(w.w) × \(w.h)"); Spacer(); Text(w.updated, format: .relative(presentation: .named)) }.font(.caption2).foregroundStyle(PaintSkin.text.opacity(0.55)).lineLimit(1)
            }
            .padding(8).background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Work, \(w.name)").accessibilityIdentifier("gallery.work")
        .contextMenu {
            Button { open(w) } label: { Label(w.here ? "Open" : "Download and open", systemImage: "paintbrush.pointed") }
            if w.here {
                Button { renameText = w.name; renaming = w } label: { Label("Rename", systemImage: "pencil") }
                Button { if state.ops.duplicateWork(id: w.id) { Task { await state.load(model: model) } } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Menu {
                    ForEach(PaintGalleryOps.Kind.allCases, id: \.self) { k in
                        Button(k.rawValue) { if let u = PaintGalleryOps.file(id: w.id, name: w.name, kind: k) { shareURL = u } else { line = "Not made. The \(k.rawValue) could not be built." } }
                    }
                } label: { Label("Share", systemImage: "square.and.arrow.up") }
                Button { stackName = w.stack ?? ""; stacking = w } label: { Label("Put in a stack…", systemImage: "square.stack.3d.up") }
                if w.stack != nil { Button { state.ops.setStack(id: w.id, name: nil); Task { await state.load(model: model) } } label: { Label("Take out of its stack", systemImage: "square.stack.3d.up.slash") } }
                Button(role: .destructive) { deleting = w } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func open(_ w: PaintModel.Work) {
        if w.here { state.openCanvas(work: w.id); return }
        guard let e = w.entry, let http = model.http else { line = "Not connected. Load your config first."; return }
        busy = w.id
        Task {
            defer { busy = nil }
            do { let id = try await NativeRemote.fetch(http, entry: e); state.openCanvas(work: id) }
            catch let err as WorkFileError { line = "Not opened. \(err.why)" }
            catch { line = "Not opened. The work did not download. Pull to try again." }
        }
    }

    /// A photo, a PSD, a picture file, a work from the laptop or brushes: each becomes a new work (brushes go to Mine).
    private func bringIn(data: Data, fileName: String) {
        let low = fileName.lowercased(), base = String((fileName as NSString).deletingPathExtension.prefix(40))
        func picture() {
            guard let ui = UIImage(data: data), let cg = (ui.imageOrientation == .up ? ui.cgImage : NativeLift.redraw(ui)) else { line = "PL Paint cannot open that kind of file."; return }
            let (w, h) = PaintGalleryOps.canvasSize(for: cg)
            state.request = PaintCanvasRequest(work: nil, setup: { c in
                c.startNew(w: w, h: h, transparent: false)
                c.addPictureLayer(cg, name: String(base.prefix(24)))
                c.commitTransform()
                c.rename(base)
            })
        }
        if low.hasSuffix(".psd") {
            do {
                let psd = try NativePSD.read(data)
                let w = min(8192, max(64, psd.w)), h = min(8192, max(64, psd.h))
                guard w * h <= 16_777_216 else { line = "Not opened. That PSD is larger than this phone holds (16.7 million pixels)."; return }
                state.request = PaintCanvasRequest(work: nil, setup: { c in c.startNew(w: w, h: h, transparent: true); _ = c.importPSD(data); c.rename(base) })
            } catch let e as NativePSD.Bad { line = "Not opened. \(e.why)" } catch { line = "Not opened. That file is not a PSD." }
        } else if low.hasSuffix(".abr") {
            line = state.ops.importBrushes(data, fileName: fileName)
        } else if low.hasSuffix(".json") {
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["layers"] != nil {
                state.request = PaintCanvasRequest(work: nil, setup: { c in _ = c.importWorkFile(data, name: base) })
            } else { line = state.ops.importBrushes(data, fileName: fileName) }
        } else { picture() }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waiting to be filed").paintLabel()
            ForEach(state.outbox) { i in HStack { Text(i.title ?? i.id); Spacer(); Text((i.dest ?? "").capitalized).foregroundStyle(PaintSkin.text.opacity(0.6)) }.font(.footnote) }
            Text("Sent to Curate or the Archive; the PC files them.").font(.caption2).foregroundStyle(PaintSkin.text.opacity(0.5))
        }
        .paintPanel()
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Sync with the laptop").paintLabel(); Spacer(); Text(sync.state).font(.footnote).foregroundStyle(sync.failed ? .red : PaintSkin.gold2) }
            if !sync.detail.isEmpty { Text(sync.detail).font(.caption).foregroundStyle(PaintSkin.text.opacity(0.6)) }
            Button { Task { syncing = true; await sync.run(model: model, canvas: nil); await state.load(model: model); syncing = false } } label: {
                Label(syncing || sync.running ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
            }.buttonStyle(.bordered).disabled(syncing || sync.running)
        }
        .paintPanel()
    }
}
