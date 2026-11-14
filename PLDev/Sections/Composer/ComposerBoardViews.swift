import SwiftUI

// The render Board (components/Board.tsx): one render job is one card; the house moves the cards (Sent, Rendering, Mixing, Filed, Ruled,
// Failed) and the phone only reads them, every 10 seconds while the board is open. Cards made here that the board cannot take yet wait in
// "Waiting for the house" and go in on their own.

struct BoardRoom: View {
    let model: AppModel
    let state: ComposerModel
    @State private var outbox = ComposerOutbox.shared
    @Environment(\.openURL) private var openURL
    @State private var lane: String?
    @State private var result: String?
    @State private var tick = 0

    private var shown: [ComposerModel.Card] { state.cards.filter { lane == nil || $0.lane == lane } }

    var body: some View {
        List {
            Section { header.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)) }
            if let r = result { Section { ResultLine(text: r).foregroundStyle(CMP.dim).listRowBackground(Color.clear) } }
            if !outbox.waiting.isEmpty {
                Section {
                    ForEach(outbox.waiting) { w in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) { Image(systemName: "paperplane").foregroundStyle(CMP.warn); Text("\(w.piece) · \(w.shot)").font(.system(size: 14, weight: .medium)).foregroundStyle(CMP.text).lineLimit(1) }
                            Text(w.look).font(.system(size: 12)).foregroundStyle(CMP.dim)
                            if let n = w.note { Text(n).font(.system(size: 11)).foregroundStyle(CMP.muted) }
                            Text("made \(w.made.formatted(.relative(presentation: .named)))").cmpLabel(9)
                        }
                        .cmpCard(padding: 12, warn: false).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .leading) { Button(role: .destructive) { outbox.discard(w.id) } label: { Label("Discard", systemImage: "trash") } }
                        .swipeActions(edge: .trailing) { Button { Task { await retry() } } label: { Label("Try now", systemImage: "arrow.clockwise") }.tint(CMP.gold) }
                    }
                } header: { Text("Waiting for the house · \(outbox.waiting.count)").cmpLabel(10) } footer: { Text("These cards are made and kept on this phone. They go to the board the next time it can take them.").font(.caption).foregroundStyle(CMP.muted) }
            }
            if shown.isEmpty && !state.failed {
                Section {
                    ContentUnavailableView { Label(lane == nil ? "No cards on the board" : "Nothing in \(ComposerModel.label(lane!))", systemImage: "square.grid.3x2") } description: { Text(lane == nil ? "Send a shot to render from the Piece room and its card walks the lanes here." : ComposerModel.why(lane!)) }
                        .listRowBackground(Color.clear)
                }
            }
            if state.failed && state.cards.isEmpty {
                Section { ContentUnavailableView { Label("Could not read the board", systemImage: "wifi.exclamationmark") } description: { Text("Pull to try again.") }.listRowBackground(Color.clear) }
            }
            ForEach(ComposerModel.order.filter { l in lane == nil || lane == l }, id: \.self) { l in
                let cards = shown.filter { $0.lane == l }
                if !cards.isEmpty {
                    Section {
                        ForEach(cards) { c in
                            CardRow(card: c).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .swipeActions(edge: .trailing) { if c.lane == "filed" || c.lane == "ruled" { Button { openURL(URL(string: "pldev://section/curate")!) } label: { Label("Rule it", systemImage: "hand.thumbsup") }.tint(CMP.gold) } }
                        }
                    } header: {
                        HStack(spacing: 6) { Circle().fill(CMP.lane(l)).frame(width: 7, height: 7); Text("\(ComposerModel.label(l)) · \(cards.count)").cmpLabel(10) }
                    } footer: { Text(ComposerModel.why(l)).font(.caption).foregroundStyle(CMP.muted) }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await reload() }
        .sensoryFeedback(PLHaptic.select, trigger: lane)
        .sensoryFeedback(PLHaptic.success, trigger: tick)
        .task(id: "poll") {   // polls every 10 s so a card walks the lanes without a pull
            while !Task.isCancelled {
                await state.load(model: model)
                if !outbox.waiting.isEmpty { await retry(quiet: true) }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func reload() async { await state.load(model: model); await retry(quiet: true) }
    private func retry(quiet: Bool = false) async {
        guard !outbox.waiting.isEmpty else { return }
        let n = await outbox.flush(model: model)
        if n > 0 { result = "\(n) card\(n == 1 ? "" : "s") went to the board."; tick += 1; await state.load(model: model) }
        else if !quiet { result = "Not sent yet. The board still cannot take them; they stay here." }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(state.cards.count) card\(state.cards.count == 1 ? "" : "s") · the house moves them; you rule on /curate").font(.system(size: 11)).foregroundStyle(CMP.muted)
                Spacer(minLength: 6)
                Group {
                    if state.failed { Text("not reachable").foregroundStyle(CMP.danger) }
                    else if let p = state.pulled, let d = ComposerBoardTime.parse(p) { Text("pulled ").foregroundStyle(CMP.muted) + Text(d, style: .relative).foregroundStyle(CMP.muted) }
                    else { Text("pulling…").foregroundStyle(CMP.muted) }
                }.cmpNum(10)
            }
            if state.source == "r2" { Text("The PC published this board. It shows the last state it saved.").font(.system(size: 11)).foregroundStyle(CMP.dim) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    CMPChip(title: "all", count: state.cards.count, on: lane == nil) { lane = nil }
                    ForEach(ComposerModel.order, id: \.self) { l in CMPChip(title: ComposerModel.label(l), count: state.count(l), on: lane == l) { lane = (lane == l) ? nil : l } }
                }
            }
        }
        .cmpCard(padding: 12)
    }
}

enum ComposerBoardTime {
    static func parse(_ s: String) -> Date? {
        let a = ISO8601DateFormatter(); if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; if let d = b.date(from: s) { return d }
        let c = DateFormatter(); c.locale = Locale(identifier: "en_US_POSIX"); c.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return c.date(from: s)
    }
    /// "11-03 06:42" as the web prints it (`(at ?? created).slice(5, 16)`).
    static func short(_ s: String?) -> String { guard let s, s.count >= 16 else { return s ?? "" }; return String(s.dropFirst(5).prefix(11)).replacingOccurrences(of: "T", with: " ") }
}

struct CardRow: View {
    let card: ComposerModel.Card
    @Environment(\.openURL) private var openURL
    @State private var following = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(CMP.lane(card.lane)).frame(width: 8, height: 8)
                Text("\(card.piece ?? "piece") · \(card.shot ?? card.id)").font(.system(size: 15, weight: .medium)).foregroundStyle(CMP.text).lineLimit(2)
            }
            if card.look != nil || card.bed != nil {
                Text([card.look, card.bed.map { "+ " + $0.replacingOccurrences(of: ".wav", with: "").replacingOccurrences(of: ".mp3", with: "") }].compactMap { $0 }.joined(separator: " ")).font(.system(size: 13)).foregroundStyle(CMP.dim)
            }
            if card.lane == "rendering" || card.lane == "sent" {
                if let f = card.fraction { ProgressView(value: f).tint(CMP.gold) }
                if let p = card.progress { Text(p).cmpNum(11).foregroundStyle(CMP.dim) }
            }
            if let f = card.file { Text(f.replacingOccurrences(of: "pl-short-his-", with: "")).font(.system(size: 12, design: .monospaced)).foregroundStyle(CMP.gold).lineLimit(1).truncationMode(.middle) }
            if let n = card.note, !n.isEmpty { Text(String(n.prefix(160))).font(.system(size: 12)).foregroundStyle(CMP.danger) }
            Text(ComposerBoardTime.short(card.at ?? card.created)).cmpNum(10).foregroundStyle(CMP.muted)
        }
        .cmpCard(padding: 12, warn: card.lane == "failed")
        .contextMenu {
            if let f = card.file { Button { UIPasteboard.general.string = f } label: { Label("Copy the file name", systemImage: "doc.on.doc") } }
            Button { UIPasteboard.general.string = card.id } label: { Label("Copy the card id", systemImage: "number") }
            if card.lane == "sent" || card.lane == "rendering" || card.lane == "mixing" {
                Button { RenderLive.follow(card); following = true } label: { Label(RenderLive.following(card) || following ? "Following on the Lock Screen" : "Follow on the Lock Screen", systemImage: "lock.iphone") }
            }
            if card.lane == "filed" || card.lane == "ruled" { Button { openURL(URL(string: "pldev://section/curate")!) } label: { Label("Rule it on Curate", systemImage: "hand.thumbsup") } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.shot ?? card.id), \(ComposerModel.label(card.lane))" + (card.progress.map { ", \($0)" } ?? ""))
    }
}

// MARK: More: pieces, defaults, the library index, the handbook

struct MoreRoom: View {
    let model: AppModel
    let state: ComposerModel
    @State private var store = ComposerPieces.shared
    @State private var lib = ComposerLibrary.shared
    @State private var outbox = ComposerOutbox.shared
    @AppStorage("composer.defaultResolution") private var resolution = "1080x1920"
    @AppStorage("composer.defaultFps") private var fps = 30
    @AppStorage("composer.defaultTarget") private var target = "remotion → openmontage"
    @AppStorage("composer.defaultTransition") private var transition = ""
    @State private var askDelete: String?
    @State private var result: String?
    @State private var reloading = false

    var body: some View {
        List {
            Section {
                NavigationLink { ComposerHandbookView() } label: { Label("Handbook", systemImage: "book") }
            } footer: { Text("How the piece, the graph, the library, the spec and the board work, in the order you use them.").foregroundStyle(CMP.muted) }

            Section {
                ForEach(store.entries) { e in
                    Button { store.open(e.id); result = "Opened \"\(e.piece.piece)\". It is on the Piece tab." } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.piece.piece).foregroundStyle(CMP.text)
                                Text("\(e.piece.shots.count) shots · \(String(format: "%.1f", e.piece.duration)) s · \(e.piece.resolution) at \(e.piece.fps)").cmpNum(10).foregroundStyle(CMP.muted)
                            }
                            Spacer()
                            if e.id == store.activeId { Image(systemName: "checkmark").foregroundStyle(CMP.gold).accessibilityLabel("Open piece") }
                        }
                    }
                    .swipeActions(edge: .leading) { Button(role: .destructive) { askDelete = e.id } label: { Label("Delete", systemImage: "trash") } }
                    .swipeActions(edge: .trailing) { Button { store.duplicatePiece(e.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(CMP.gold) }
                    .contextMenu {
                        Button { store.duplicatePiece(e.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        ShareLink(item: store.json(e.id)) { Label("Share as JSON", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { askDelete = e.id } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                Button { store.newPiece() ; result = "Made \"\(store.piece.piece)\"." } label: { Label("New piece", systemImage: "plus") }
            } header: { Text("Pieces · \(store.entries.count)").cmpLabel(10) } footer: { Text("Kept on this phone, in the same JSON the web board and the desktop app use. Share one to move it.").foregroundStyle(CMP.muted) }

            Section {
                Picker("Resolution", selection: $resolution) { ForEach(composerResolutions, id: \.self) { Text($0).tag($0) } }
                Picker("Frames per second", selection: $fps) { ForEach([24, 25, 30, 48, 50, 60], id: \.self) { Text("\($0)").tag($0) } }
                Picker("Transitions", selection: $transition) { Text("All cuts").tag(""); ForEach(composerTransitions) { Text($0.word.capitalized).tag($0.word) } }
                LabeledContent("Target") { TextField("remotion → openmontage", text: $target).multilineTextAlignment(.trailing).textInputAutocapitalization(.never).autocorrectionDisabled().cmpNum(12) }
            } header: { Text("New pieces start with").cmpLabel(10) } footer: { Text("Only new pieces. A piece you already made keeps its own numbers.").foregroundStyle(CMP.muted) }

            Section {
                if let m = lib.manifest {
                    LabeledContent("Assets") { Text(m.total.formatted()).cmpNum(13) }
                    LabeledContent("Indexed") { Text(m.generated.replacingOccurrences(of: "T", with: " ")).cmpNum(11) }
                    LabeledContent("Durations") { Text(m.probed ? "probed" : "not probed").cmpNum(11) }
                    ForEach(m.roots, id: \.catalog) { r in
                        HStack { CMPDot(color: r.present ? CMP.ok : CMP.warn, size: 7); Text(r.catalog).cmpNum(12); Spacer(); Text(r.present ? "\(r.count)" : (r.reason ?? "not mounted")).cmpNum(11).foregroundStyle(r.present ? CMP.dim : CMP.warn) }
                    }
                } else { Text(lib.failed ?? "Not loaded yet.").foregroundStyle(CMP.muted) }
                Button { Task { reloading = true; await lib.load(model: model, force: true); reloading = false; result = lib.manifest == nil ? "Not loaded. Pull to try again." : "The library is current." } } label: {
                    HStack { Label("Reload the library", systemImage: "arrow.clockwise"); if reloading { Spacer(); ProgressView() } }
                }.disabled(reloading)
            } header: { Text("The library index").cmpLabel(10) } footer: { Text("The index is read only here: the laptop writes it, the phone reads it and keeps the last copy for offline.").foregroundStyle(CMP.muted) }

            Section {
                LabeledContent("Cards on the board") { Text("\(state.cards.count)").cmpNum(13) }
                LabeledContent("Waiting to be sent") { Text("\(outbox.waiting.count)").cmpNum(13) }
                if !outbox.waiting.isEmpty {
                    Button { Task { let n = await outbox.flush(model: model); result = n > 0 ? "\(n) went to the board." : "Not sent yet. The board still cannot take them." } } label: { Label("Try the waiting cards now", systemImage: "paperplane") }
                }
            } header: { Text("The board").cmpLabel(10) }

            if let r = result { Section { ResultLine(text: r).foregroundStyle(CMP.dim) } }
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog("Delete this piece?", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }), titleVisibility: .visible) {
            Button("Delete piece", role: .destructive) { if let id = askDelete { store.delete(id) }; askDelete = nil }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its shots and graphs go with it. This cannot be undone.") }
        .refreshable { await lib.load(model: model, force: true); await state.load(model: model) }
    }
}

// MARK: the handbook (public/handbook, written for the phone)

struct ComposerHandbookView: View {
    private struct Page: Identifiable { let title: String; let blocks: [Block]; var id: String { title } }
    private enum Block { case text(String), steps([String]), note(String), nodes, sockets, transitions }

    private let pages: [Page] = [
        Page(title: "What Composer is", blocks: [
            .text("A scoring surface for PL video. You build a piece out of shots, give each shot its sources from the library, wire how the shot is made in a graph, and build a spec: a short markdown file that says exactly what to render."),
            .text("Nothing in this app renders. The renderer (compose_render.py, in OpenMontage, projects, pl-curves) makes the pixels. The graph carries intent; the renderer evaluates."),
            .note("The spec is the product. Everything on the screen exists to write it correctly.")]),
        Page(title: "Your first piece", blocks: [
            .steps(["On the Piece tab, tap Add shot. A card appears, called untitled shot, four seconds long.",
                    "Give it a name. The name is the only readable label in the spec.",
                    "Tap Attach from the library on the card, then tap an asset. It attaches and the card shows it. Tap a second: the shot now has a base and an overlay, blended screen.",
                    "Open its graph (the Graph button) to see the wiring, or leave it: the default wiring is real.",
                    "Add more shots the same way and set each duration.",
                    "Tap Build spec, read it, then Share it.",
                    "Render it: python compose_render.py your-piece.spec.md, in OpenMontage, projects, pl-curves."])]),
        Page(title: "The graph", blocks: [
            .text("Every shot has a graph: how that one shot gets made. Open it from the shot's Graph button. One graph per shot; a graph never holds another shot."),
            .steps(["Drag the empty well to move the graph; pinch to zoom; the buttons bottom left zoom and fit.",
                    "Drag a node to move it. Tap a node to select it; its settings open below.",
                    "Drag from a node's output dot (right) to an input dot (left) to wire two nodes. Only matching types connect, and the reason shows when one does not.",
                    "Or select a node and use its inputs list: each input offers every node that fits, and Disconnect.",
                    "Tap a wire to select it, then Remove wire.",
                    "Add node adds a step; Add a source from the library puts one on the shot."]),
            .note("The count in the strip is of operations that will be written. A node that is not wired up is not counted and is not written."),
            .text("Until you change a graph, the shot keeps its default wiring: the first media is the base, the rest overlay with screen, a model is rendered first, and a track drives overlay opacity. The first edit makes the graph explicit; More ▸ Back to the default wiring undoes it.")]),
        Page(title: "Wiring and the types", blocks: [
            .text("Edges are typed and strictly checked. Three rules: the type must fit the input, an input holds one wire (the Shot's layers input holds many), and no cycles."),
            .sockets]),
        Page(title: "The nodes", blocks: [.nodes]),
        Page(title: "Shots and transitions", blocks: [
            .text("A shot card shows its number (shot order in the file is shot order in the piece), its picture (its first visual source), its title, duration, how it enters, its sources and, when selected, its graph as a list."),
            .text("Reorder with Reorder in the toolbar or with Move earlier and later in the shot's menu. Touch and hold a shot for the rest: duplicate, attach, send to render, delete. Swipe left to send it, right to delete."),
            .transitions,
            .note("Shot 01 has nothing to come from, so its transition is never written. A fade in from black is its own decision, asked for explicitly.")]),
        Page(title: "The library", blocks: [
            .text("The Library is every asset the index knows, with a filter, a chip per catalog and a chip per type. Tap an asset to attach it to the selected shot (a gold border marks it); touch and hold for details, another shot, the id or the path."),
            .text("The laptop writes the index and the phone reads it, keeping the last copy so it works offline. A root that is not mounted on the laptop is named at the top: the list is incomplete until it is.")]),
        Page(title: "Sources: index, Curve Library, Photos", blocks: [
            .text("A shot takes its sources from three places, all in the Library pane: the house index (every asset the laptop knows), the Curve Library (his pieces from the gallery, with their stills and clips), and Photos (pictures and clips from this iPhone, up to 12 at a time)."),
            .steps(["Index and Curve Library: tap an asset to attach it to the selected shot.",
                    "Photos: tap Photos, pick pictures or clips, confirm. Each is copied into the app (pictures at 1920 px) and named photo-01, clip-01 and so on.",
                    "Touch and hold a clip, then Trim the clip: drag the in and out points. The trim is written into the spec next to the source, and Make the shot this long sets the shot's duration to it."]),
            .note("Photos are for planning and preview: they play on the phone and are named in the spec, but the house renderer does not read them yet. A render reads a curve path (a tracer job) and its art, so Send to render needs a path source.")]),
        Page(title: "The spec", blocks: [
            .text("Build spec writes the exact markdown the renderer reads and shows it before it leaves the phone. Copy it, or Share it as a .spec.md file. The phone writes the same text the web board and the desktop app write."),
            .text("A shot with no sources is written as sources: [] and renders black; the spec says so out loud. Shots still called untitled shot get one warning, never a block.")]),
        Page(title: "The board", blocks: [
            .text("The render board: one render job is one card. The house moves the cards: Sent, Rendering, Mixing, Filed, Ruled, Failed. The phone reads them every 10 seconds while the board is open."),
            .text("Send to render (in a shot's menu or by swipe) needs a Tracer Render node wired to a tracer job and a File to /curate node in the shot's graph. It becomes one card; the render queue runs it one job at a time, the bed goes on, the word check runs, and the clip is filed to /curate unmarked. You rule it there."),
            .text("If the board cannot take the card yet, it waits on the phone under Waiting for the house and goes in on its own. Touch and hold a card in flight to follow it on the Lock Screen.")]),
    ]

    var body: some View {
        List(pages) { p in
            NavigationLink { page(p) } label: { Text(p.title).foregroundStyle(CMP.text) }
        }
        .scrollContentBackground(.hidden).cmpScreen().navigationTitle("Handbook").navigationBarTitleDisplayMode(.inline)
    }

    private func page(_ p: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(p.blocks.enumerated()), id: \.offset) { _, b in block(b) }
            }
            .padding(PLSpace.margin)
        }
        .cmpScreen().navigationTitle(p.title).navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func block(_ b: Block) -> some View {
        switch b {
        case .text(let t): Text(t).font(.system(size: 15)).foregroundStyle(CMP.text).plReading()
        case .note(let t): Label { Text(t).font(.system(size: 13)).foregroundStyle(CMP.dim) } icon: { Image(systemName: "lightbulb").foregroundStyle(CMP.gold) }.cmpCard()
        case .steps(let s):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(s.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .top, spacing: 10) { Text("\(i + 1)").cmpNum(12).foregroundStyle(CMP.gold).frame(width: 18, alignment: .trailing); Text(t).font(.system(size: 14)).foregroundStyle(CMP.text).plReading() }
                }
            }.cmpCard()
        case .sockets:
            VStack(alignment: .leading, spacing: 10) {
                ForEach([ComposerSocket.media, .curve, .audio, .value, .model, .path, .shot], id: \.self) { s in
                    HStack(alignment: .top, spacing: 8) { CMPDot(color: s.color, size: 9).padding(.top, 4); VStack(alignment: .leading, spacing: 1) { Text("\(s.rawValue): \(s.carries)").font(.system(size: 14, weight: .medium)).foregroundStyle(CMP.text); Text(s.why).font(.system(size: 12)).foregroundStyle(CMP.dim) } }
                }
            }.cmpCard()
        case .nodes:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(NodeKind.allCases, id: \.self) { k in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) { CMPDot(color: k.spec.output?.color ?? CMP.muted, size: 8); Text(k.spec.label).font(.system(size: 15, design: .serif)).foregroundStyle(CMP.text) }
                        Text(k.spec.why).font(.system(size: 13)).foregroundStyle(CMP.dim)
                        if !k.spec.inputs.isEmpty { Text("in: " + k.spec.inputs.map { "\($0.label) (\($0.accepts.map(\.rawValue).joined(separator: "/")))" }.joined(separator: ", ")).cmpNum(10).foregroundStyle(CMP.muted) }
                        Text("out: " + (k.spec.output?.rawValue ?? "nothing")).cmpNum(10).foregroundStyle(CMP.muted)
                    }
                }
            }.cmpCard()
        case .transitions:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(composerTransitions) { t in HStack(alignment: .top, spacing: 10) { Text(t.word).cmpNum(12).foregroundStyle(CMP.gold).frame(width: 70, alignment: .leading); Text(t.why).font(.system(size: 13)).foregroundStyle(CMP.dim) } }
                Text("A transition is a word and, for the timed ones, seconds (dissolve 0.5). A piece-wide default is inherited by every shot unless it names its own.").font(.system(size: 12)).foregroundStyle(CMP.muted)
            }.cmpCard()
        }
    }
}
