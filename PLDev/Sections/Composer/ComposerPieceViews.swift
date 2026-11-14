import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers

// The root and the Piece room: the top strip of the web board (name, transition, pieces, counts, Build spec, Board) and the spine of
// shot cards, each with its thumbnail, title, duration, how it enters, its sources and its graph.

struct ComposerView: View {
    let model: AppModel
    let state: ComposerModel
    @State private var room: ComposerRoom = .piece
    @State private var nav = ComposerNav.shared

    var body: some View {
        Group {
            switch room {
            case .piece: PieceRoom(model: model, state: state, room: $room)
            case .library: ComposerLibraryRoom(model: model)
            case .board: BoardRoom(model: model, state: state)
            case .more: MoreRoom(model: model, state: state)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Area", selection: $room) { ForEach(ComposerRoom.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal, PLSpace.margin).padding(.vertical, 8).background(.bar).accessibilityIdentifier("composer.area")
        }
        .cmpScreen()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("Composer").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(PLHaptic.select, trigger: room)
        .onChange(of: nav.room) { _, r in apply(r) }
        .onAppear { apply(nav.room) }
        .task { await ComposerLibrary.shared.load(model: model); await state.load(model: model) }
    }

    private func apply(_ r: ComposerRoom?) { guard let r else { return }; room = r; nav.room = nil }
}

// MARK: the transition picker (page.tsx TransitionPicker): the word, and the seconds when the word has a duration

struct TransitionControl: View {
    let label: String
    let inherit: String
    @Binding var value: String?
    var disabled = false
    var disabledWhy = ""

    private var word: String { (value ?? "").split(separator: " ").first.map(String.init) ?? "" }
    private var secs: Double? { (value ?? "").split(separator: " ").dropFirst().first.flatMap { Double($0) } }
    private var timed: Bool { !word.isEmpty && word != "cut" }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button(inherit) { value = nil }
                ForEach(composerTransitions) { t in
                    Button { value = (t.word == "cut" || secs == nil) ? t.word : "\(t.word) \(GVal.js(secs!))" } label: {
                        Label { Text(t.word); Text(t.why) } icon: { if word == t.word { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label).cmpLabel(9)
                    Text(word.isEmpty ? inherit : word).font(.system(size: 13)).foregroundStyle(CMP.text)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(CMP.goldDim)
                }
                .padding(.horizontal, 12).frame(minHeight: 36)
                .overlay { Capsule().strokeBorder(CMP.line, lineWidth: 0.8) }
            }
            .disabled(disabled)
            if timed, !disabled {
                Stepper(value: Binding(get: { secs ?? composerTransitionSeconds }, set: { value = "\(word) \(GVal.js(max(0.1, ($0 * 10).rounded() / 10)))" }), in: 0.1...5, step: 0.1) {
                    Text(String(format: "%.1f s", secs ?? composerTransitionSeconds)).cmpNum(12).foregroundStyle(CMP.dim)
                }
                .fixedSize()
            }
            if disabled { Text(disabledWhy).font(.caption2).foregroundStyle(CMP.muted).lineLimit(2) }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: the Piece room

struct PieceRoom: View {
    let model: AppModel
    let state: ComposerModel
    @Binding var room: ComposerRoom
    @State private var store = ComposerPieces.shared
    @State private var lib = ComposerLibrary.shared
    @State private var spec: String?
    @State private var askUntitled = false
    @State private var sending: ComposerShot?
    @State private var result: String?
    @State private var attachTo: ComposerShot?
    @State private var reordering = false
    @State private var askDelete: String?
    @State private var importing = false
    @State private var tick = 0
    @State private var warnTick = 0
    @State private var previewing = false
    @State private var graphShot: String?

    private var piece: ComposerPiece { store.piece }
    private var untitled: Int { piece.shots.filter { $0.title.trimmingCharacters(in: .whitespaces).isEmpty || $0.title == "untitled shot" }.count }

    var body: some View {
        List {
            Section { strip.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)) }
            if let r = result { Section { ResultLine(text: r).foregroundStyle(CMP.dim).listRowBackground(Color.clear) } }
            if piece.shots.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No shots yet", systemImage: "film.stack")
                    } description: {
                        Text("A piece is a sequence of shots. Add one, then attach assets to it from the library.")
                    } actions: {
                        Button("Add shot") { withAnimation(.snappy) { store.addShot() }; tick += 1 }.buttonStyle(CMPPill(primary: true))
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    TipView(ComposerShotTip()).listRowBackground(Color.clear)
                    ForEach(Array(piece.shots.enumerated()), id: \.element.id) { i, s in
                        ShotCard(model: model, shot: s, index: i, first: i == 0, last: i == piece.shots.count - 1, pieceTransition: piece.transition, store: store, lib: lib,
                                 onAttach: { attachTo = s }, onSend: { sending = s }, onDelete: { askDelete = s.id }, onGraph: { store.selected = s.id; graphShot = s.id })
                            .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .trailing) {
                                Button { sending = s } label: { Label("Send to render", systemImage: "play.fill") }.tint(CMP.gold)
                            }
                            .swipeActions(edge: .leading) {
                                Button(role: .destructive) { askDelete = s.id } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    .onMove { store.piece.shots.move(fromOffsets: $0, toOffset: $1) }
                    Button { withAnimation(.snappy) { store.addShot() }; tick += 1 } label: { Label("Add shot", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(CMPPill()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain).scrollDismissesKeyboard(.interactively)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { if piece.shots.count > 1 { Button(reordering ? "Done" : "Reorder") { withAnimation { reordering.toggle() } } } }
            ToolbarItem(placement: .topBarTrailing) { Button { withAnimation(.snappy) { store.addShot() }; tick += 1 } label: { Image(systemName: "plus") }.accessibilityLabel("Add a shot").accessibilityIdentifier("composer.addshot") }
        }
        .navigationDestination(item: $graphShot) { id in ComposerGraphView(model: model, shotId: id) }
        .sheet(item: Binding(get: { spec.map { SpecDoc(text: $0) } }, set: { if $0 == nil { spec = nil } })) { doc in ComposerSpecSheet(text: doc.text, name: piece.piece) }
        .sheet(isPresented: $previewing) { ComposerPreviewSheet(piece: piece) }
        .sheet(item: $attachTo) { shot in
            NavigationStack { ComposerLibraryRoom(model: model, attachTo: shot.id).navigationTitle("Attach to \(shot.title)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { attachTo = nil } } } }
                .presentationDetents([.large])
        }
        .confirmationDialog("\(untitled) \(untitled == 1 ? "shot is" : "shots are") still called \"untitled shot\". The title is the only readable label in the spec.", isPresented: $askUntitled, titleVisibility: .visible) {
            Button("Build it anyway") { spec = ComposerSpec.emit(piece, assets: lib.allAssets) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Send \"\(sending?.title ?? "this shot")\" to the house?", isPresented: Binding(get: { sending != nil }, set: { if !$0 { sending = nil } }), titleVisibility: .visible) {
            Button("Send to render") { if let s = sending { Task { await send(s) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It becomes one card on the board, renders on the PC and files to /curate unmarked.") }
        .confirmationDialog("Send \"\(piece.piece)\" to the house?", isPresented: $askSendPiece, titleVisibility: .visible) {
            Button("Send piece to render") { Task { await sendPiece() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let n = ComposerRender.phoneSources(of: piece, extras: ComposerExtras.shared).count
            Text((n > 0 ? "\(n) picture\(n == 1 ? "" : "s") and clip\(n == 1 ? "" : "s") from Photos go up first, then the spec. " : "") + "The whole piece becomes one card, renders on the PC and files to /curate unmarked.")
        }
        .confirmationDialog("Delete this shot?", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }), titleVisibility: .visible) {
            Button("Delete shot", role: .destructive) { if let id = askDelete { withAnimation { store.remove(id) } }; askDelete = nil }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { r in
            guard case .success(let url) = r else { result = "Not imported. The file could not be opened."; return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) { result = store.importJSON(d) ?? "Imported \"\(store.piece.piece)\"." } else { result = "Not imported. The file could not be read." }
        }
        .refreshable { await lib.load(model: model, force: true); await state.load(model: model) }
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
        .sensoryFeedback(PLHaptic.warning, trigger: warnTick)
    }

    // the top strip

    private var strip: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Piece name", text: Binding(get: { store.piece.piece }, set: { store.piece.piece = $0 }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().cmpDisplay(26).foregroundStyle(CMP.text)
                .accessibilityLabel("Piece name")
            HStack(spacing: 10) {
                TransitionControl(label: "transition", inherit: "all cuts", value: Binding(get: { store.piece.transition }, set: { store.piece.transition = $0 }))
                Spacer(minLength: 0)
                piecesMenu
            }
            HStack(alignment: .top, spacing: 14) {
                field("shots", "\(piece.shots.count)")
                field("duration", String(format: "%.1fs", piece.duration))
                Menu {
                    Picker("FPS", selection: Binding(get: { store.piece.fps }, set: { store.piece.fps = $0 })) { ForEach([24, 25, 30, 48, 50, 60], id: \.self) { Text("\($0)").tag($0) } }
                } label: { field("fps", "\(piece.fps)", menu: true) }
                Menu {
                    Picker("Resolution", selection: Binding(get: { store.piece.resolution }, set: { store.piece.resolution = $0 })) { ForEach(composerResolutions, id: \.self) { Text($0).tag($0) } }
                } label: { field("resolution", piece.resolution, menu: true) }
            }
            HStack(spacing: 10) {
                Button("Build spec") {
                    if untitled > 0 { warnTick += 1; askUntitled = true } else { spec = ComposerSpec.emit(piece, assets: lib.allAssets) }
                }
                .buttonStyle(CMPPill(primary: true)).disabled(piece.shots.isEmpty)
                Button("Preview") { previewing = true }.buttonStyle(CMPPill()).disabled(piece.shots.isEmpty).accessibilityIdentifier("composer.preview")
                Button("Board") { room = .board }.buttonStyle(CMPPill())
            }
            Button { askSendPiece = true } label: { Label(render.busy ? "Sending…" : "Send the whole piece to render", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity) }
                .buttonStyle(CMPPill()).disabled(piece.shots.isEmpty || render.busy).accessibilityIdentifier("composer.piece.send")
            if let st = render.step {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: st.fraction).tint(CMP.gold)
                    Text(st.text).cmpNum(11).foregroundStyle(CMP.dim).accessibilityIdentifier("composer.piece.progress")
                }
            }
        }
        .cmpCard(padding: 14)
    }

    private func field(_ label: String, _ value: String, menu: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).cmpLabel(9)
            HStack(spacing: 3) { Text(value).cmpNum(13).foregroundStyle(CMP.text); if menu { Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(CMP.goldDim) } }
        }
        .frame(minHeight: 36, alignment: .leading).contentShape(Rectangle())
    }

    private var piecesMenu: some View {
        Menu {
            ForEach(store.entries) { e in
                Button { store.open(e.id) } label: {
                    Label("\(e.piece.piece)  ·  \(e.piece.shots.count) sh · \(String(format: "%.1f", e.piece.duration))s", systemImage: e.id == store.activeId ? "checkmark" : "film")
                }
            }
            Divider()
            Button { store.newPiece(); tick += 1 } label: { Label("New piece", systemImage: "plus") }
            Button { store.duplicatePiece(store.activeId); tick += 1 } label: { Label("Duplicate this piece", systemImage: "doc.on.doc") }
            ShareLink(item: store.json(), subject: Text(piece.piece)) { Label("Share this piece as JSON", systemImage: "square.and.arrow.up") }
            Button { importing = true } label: { Label("Import a piece…", systemImage: "square.and.arrow.down") }
            if store.entries.count > 1 || !piece.shots.isEmpty {
                Divider()
                Button(role: .destructive) { askDeletePiece = true } label: { Label("Delete this piece", systemImage: "trash") }
            }
        } label: {
            HStack(spacing: 4) { Text("pieces").cmpLabel(9); Text("\(store.entries.count)").cmpNum(12).foregroundStyle(CMP.text); Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(CMP.goldDim) }
                .padding(.horizontal, 12).frame(minHeight: 36).overlay { Capsule().strokeBorder(CMP.line, lineWidth: 0.8) }
        }
        .confirmationDialog("Delete \"\(piece.piece)\"?", isPresented: $askDeletePiece, titleVisibility: .visible) {
            Button("Delete piece", role: .destructive) { store.delete(store.activeId) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(piece.shots.isEmpty ? "" : "\(piece.shots.count) shots go with it. This cannot be undone.") }
    }
    @State private var askDeletePiece = false
    @State private var askSendPiece = false
    @State private var render = ComposerRender.shared

    // send to render

    private func sendPiece() async {
        switch await render.send(piece: piece, model: model) {
        case .sent(_, let n): result = n > 0 ? "Sent. \(n) file\(n == 1 ? "" : "s") uploaded and the piece is on the board." : "Sent. The piece is on the board."; await state.load(model: model); room = .board
        case .queued(let why): result = why; warnTick += 1
        case .refused(let why): result = why; warnTick += 1
        }
    }

    private func send(_ s: ComposerShot) async {
        sending = nil
        do {
            let body = try ComposerCard.body(piece: piece, shot: s, byId: lib.byId)
            switch await ComposerOutbox.shared.send(body: body, model: model) {
            case .made: result = "Sent. The card is on the board."; await state.load(model: model); room = .board
            case .queued(let why): result = why; warnTick += 1
            case .refused(let why): result = why; warnTick += 1
            }
        } catch ComposerCardError.needs(let why) { result = "Not sent. " + why; warnTick += 1 }
        catch { result = "Not sent. The card could not be made."; warnTick += 1 }
    }
}

private struct SpecDoc: Identifiable { let text: String; var id: Int { text.hashValue } }

struct ComposerShotTip: Tip {
    var title: Text { Text("Touch and hold a shot") }
    var message: Text? { Text("It holds move, duplicate, send to render and delete. Swipe left to send it, right to delete.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

// MARK: a shot card (page.tsx ShotCard)

struct ShotCard: View {
    let model: AppModel
    let shot: ComposerShot
    let index: Int
    let first: Bool
    let last: Bool
    let pieceTransition: String?
    let store: ComposerPieces
    let lib: ComposerLibrary
    let onAttach: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void
    let onGraph: () -> Void
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var trimming: ComposerExtra?
    @State private var photoNote: String?

    private var selected: Bool { store.selected == shot.id }
    private var effective: [ComposerOp] { (shot.nodes?.isEmpty == false) ? shot.nodes! : ComposerGraph.deriveGraph(shot, byId: lib.byId) }
    private var short: [ComposerAsset] { shot.sourceIds.compactMap { lib.byId[$0] }.filter { $0.kind != "audio" && ($0.duration ?? .infinity) < shot.duration - 0.05 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(format: "%02d", index + 1)).cmpNum(13).foregroundStyle(CMP.muted)
                Spacer()
                Button(action: onGraph) {
                    Label("Graph", systemImage: "point.3.connected.trianglepath.dotted").labelStyle(.titleAndIcon).font(.system(size: 12, weight: .medium)).foregroundStyle(shot.nodes?.isEmpty == false ? CMP.gold : CMP.dim)
                        .padding(.horizontal, 12).frame(minHeight: 36).overlay { Capsule().strokeBorder(CMP.line, lineWidth: 0.8) }
                }
                .buttonStyle(.plain).accessibilityIdentifier("composer.shot.graph")
                Menu { actions } label: { Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(CMP.dim).frame(width: 40, height: 40).contentShape(Rectangle()) }
                    .accessibilityLabel("Shot actions")
            }
            thumb
            TextField("Title of shot \(index + 1)", text: Binding(get: { shot.title }, set: { v in store.patch(shot.id) { $0.title = v } }))
                .font(.system(size: 16, weight: .medium)).foregroundStyle(CMP.text).textInputAutocapitalization(.never)
            HStack(spacing: 10) {
                Text("dur").cmpLabel(9)
                TextField("", value: Binding(get: { shot.duration }, set: { v in store.patch(shot.id) { $0.duration = max(0.1, v) } }), format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).cmpNum(14).frame(width: 56).padding(.vertical, 6).padding(.horizontal, 8)
                    .background(CMP.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
                Stepper("Duration", value: Binding(get: { shot.duration }, set: { v in store.patch(shot.id) { $0.duration = max(0.1, v) } }), in: 0.1...600, step: 0.5).labelsHidden()
                Spacer()
                Text("\(shot.sourceIds.count) src").cmpNum(11).foregroundStyle(CMP.muted)
            }
            TransitionControl(label: "in", inherit: pieceTransition.map { "inherit (\($0))" } ?? "inherit (cut)",
                              value: Binding(get: { shot.transition }, set: { v in store.patch(shot.id) { $0.transition = v } }),
                              disabled: first, disabledWhy: "Shot 01 has nothing to come from. A fade in from black is its own decision.")
            if !short.isEmpty {
                Text(short.count == 1 ? "\(short[0].name) is \(String(format: "%.1f", short[0].duration ?? 0))s: the last frame holds for \(String(format: "%.1f", shot.duration - (short[0].duration ?? 0)))s"
                                      : "\(short.count) sources are shorter than this shot: their last frames hold")
                    .font(.system(size: 11)).foregroundStyle(CMP.warn)
            }
            sources
            if selected { Divider().overlay(CMP.line); graphSummary }
        }
        .cmpCard(padding: 12, selected: selected)
        .contentShape(RoundedRectangle(cornerRadius: CMP.radius))
        .onTapGesture { withAnimation(.snappy) { store.selected = shot.id } }
        .contextMenu { actions }
        .sheet(item: $trimming) { e in ComposerTrimSheet(extraId: e.id, shotId: shot.id) }
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task {
                importing = true
                let made = await ComposerExtras.shared.importPhotos(new)
                picks = []; importing = false
                for e in made { _ = store.attach(e.asset, to: shot.id) }
                photoNote = made.isEmpty ? "Nothing came in. Photos did not hand the file over." : "Added \(made.count) from Photos."
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot \(index + 1), \(shot.title), \(String(format: "%.1f", shot.duration)) seconds, \(shot.sourceIds.count) sources")
    }

    @ViewBuilder private var actions: some View {
        Button { store.move(shot.id, -1) } label: { Label("Move earlier", systemImage: "arrow.up") }.disabled(first)
        Button { store.move(shot.id, 1) } label: { Label("Move later", systemImage: "arrow.down") }.disabled(last)
        Button { store.duplicateShot(shot.id) } label: { Label("Duplicate shot", systemImage: "plus.square.on.square") }
        Button { onAttach() } label: { Label("Attach from the library", systemImage: "photo.stack") }
        Button { onSend() } label: { Label("Send to render", systemImage: "play.fill") }
        if shot.nodes?.isEmpty == false { Button { store.patch(shot.id) { $0.nodes = nil } } label: { Label("Back to the default wiring", systemImage: "arrow.uturn.backward") } }
        Divider()
        Button(role: .destructive) { onDelete() } label: { Label("Delete shot", systemImage: "trash") }
    }

    /// The card's picture is its first visual source, the one the derived wiring makes the base.
    @ViewBuilder private var thumb: some View {
        let firstVisual = shot.sourceIds.first { lib.byId[$0] != nil && lib.byId[$0]!.kind != "audio" && lib.image($0) != nil }
        Group {
            if let id = firstVisual, let img = lib.image(id) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(shot.sourceIds.isEmpty ? "no sources" : "no preview").font(.system(size: 11)).foregroundStyle(CMP.muted).frame(maxWidth: .infinity, maxHeight: .infinity).background(CMP.surface2.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity).aspectRatio(16.0 / 9.0, contentMode: .fit).background(CMP.well).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
        .accessibilityHidden(true)
    }

    /// What is attached. The card is where a wrong source gets caught, so the sources are named, not only counted.
    @ViewBuilder private var sources: some View {
        if !shot.sourceIds.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(shot.sourceIds.enumerated()), id: \.offset) { n, aid in
                    let a = lib.byId[aid]
                    HStack(spacing: 8) {
                        CMPDot(color: a?.socket.color ?? CMP.danger)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(a?.name ?? "\(aid): missing").font(.system(size: 13)).foregroundStyle(a == nil ? CMP.danger : CMP.text).lineLimit(1)
                            if n == 0, a != nil, a?.kind != "audio" { Text("base").cmpLabel(8) }
                        }
                        Spacer()
                        if let x = ComposerExtras.shared.extra(aid), x.video, x.catalog == "Photos" {
                            Button { trimming = x } label: { Image(systemName: "scissors").font(.system(size: 12)).foregroundStyle(x.trimmed ? CMP.gold : CMP.muted).frame(width: 36, height: 36).contentShape(Rectangle()) }
                                .buttonStyle(.plain).accessibilityLabel("Trim \(x.name)")
                        }
                        Button { store.patch(shot.id) { $0.sourceIds.removeAll { $0 == aid } } } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(CMP.muted).frame(width: 36, height: 36).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel("Remove source")
                    }
                    .contextMenu {
                        if n > 0 { Button { store.patch(shot.id) { if let i = $0.sourceIds.firstIndex(of: aid) { $0.sourceIds.remove(at: i); $0.sourceIds.insert(aid, at: 0) } } } label: { Label("Make this the base", systemImage: "arrow.up.to.line") } }
                        if let x = ComposerExtras.shared.extra(aid), x.video, x.catalog == "Photos" { Button { trimming = x } label: { Label("Trim the clip", systemImage: "scissors") } }
                    }
                }
            }
            .padding(.top, 2)
        }
        HStack(spacing: 18) {
            Button(action: onAttach) { Label("Attach from the library", systemImage: "plus").font(.system(size: 13)).foregroundStyle(CMP.gold).frame(minHeight: 36) }.buttonStyle(.plain)
            PhotosPicker(selection: $picks, maxSelectionCount: 8, matching: .any(of: [.images, .videos])) {
                Label(importing ? "Copying…" : "Add from Photos", systemImage: "photo.on.rectangle").font(.system(size: 13)).foregroundStyle(CMP.gold).frame(minHeight: 36)
            }
            .buttonStyle(.plain).disabled(importing).accessibilityIdentifier("composer.shot.photos")
        }
        if let n = photoNote { Text(n).font(.system(size: 11)).foregroundStyle(CMP.dim) }
    }

    /// The graph as a numbered list, in the order the operations are written, with each out name.
    private var graphSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("graph").cmpLabel(9)
            if shot.nodes?.isEmpty != false { Text(effective.isEmpty ? "Nothing wired yet. Attach sources, or open the graph." : "Default wiring, derived from the sources. Open the graph to score it by hand.").font(.system(size: 12)).foregroundStyle(CMP.dim) }
            ForEach(Array(effective.enumerated()), id: \.offset) { i, n in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", i + 1)).cmpNum(10).foregroundStyle(CMP.muted)
                    Text(n.op.replacingOccurrences(of: "_", with: " ")).font(.system(size: 12))
                    if let o = n.out { Text("→ \(o)").cmpNum(10).foregroundStyle(CMP.dim) }
                }
            }
        }
    }
}

// MARK: the spec sheet (SpecSheet.tsx): the exact text the renderer will read, before it leaves the board

struct ComposerSpecSheet: View {
    let text: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var file: String { (name.isEmpty ? "untitled-piece" : name) + ".spec.md" }
    private var url: URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(CMP.text).textSelection(.enabled).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading).cmpCard(padding: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Then render it").cmpLabel(10)
                        Text("python compose_render.py \(file)").cmpNum(12).foregroundStyle(CMP.dim).textSelection(.enabled)
                        Text("In OpenMontage/projects/pl-curves. The board emits; the CLI renders.").font(.footnote).foregroundStyle(CMP.muted)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(PLSpace.margin)
            }
            .cmpScreen()
            .navigationTitle("The spec").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = text; copied = true; Task { try? await Task.sleep(for: .seconds(1.8)); copied = false } }
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .presentationDetents([.large])
    }
}
