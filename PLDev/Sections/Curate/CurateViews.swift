import SwiftUI
import TipKit

struct CurateFullTip: Tip {
    var title: Text { Text("Three taps for full screen") }
    var message: Text? { Text("Tap the picture three times to see it with nothing around it, and again to bring the deck back. Press and hold the card for more.") }
    var image: Image? { Image(systemName: "arrow.up.left.and.arrow.down.right") }
}

/// Curate as the web deck draws it (CurateDeck.tsx): the deck's name as a serif title you tap to pick any deck, the counts under
/// it, his words box above the piece, the piece on its bone card, the caption on the page, his five keycaps in their tray.
/// Right keeps, left cuts, up is maybe; the star keeps it as a favourite; the R1 Remote types K C M F Z.
struct CurateView: View {
    let model: AppModel
    @Bindable var state: CurateModel
    @State private var drag: CGSize = .zero
    @State private var showFavourites = false
    @State private var tips = TipGroup(.ordered) { CurateSwipeTip(); CurateFullTip() }
    @FocusState private var commentFocus: Bool
    @State private var tagInput = ""
    @State private var tagFailed = false
    @FocusState private var noteFocus: Bool
    @Environment(\.colorScheme) private var scheme
    private let threshold: CGFloat = 110

    private var origin: CurateModel.Origin? { state.current.flatMap { state.origin($0) } }
    private var ground: Color { origin != nil ? PLC.wash(scheme) : PLG.bg(scheme) }

    var body: some View {
        VStack(spacing: 10) {
            if !state.full { header }
            content
        }
        .padding(.horizontal, state.full ? 0 : PLSpace.margin)
        .background { ZStack { ground; GalleryGround().opacity(origin != nil ? 0.5 : 1) }.ignoresSafeArea().animation(.easeInOut(duration: 0.24), value: origin == nil) }
        .tint(PLG.gold)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(state.full ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(state.full)
        .navigationTitle("Curate").navigationBarTitleDisplayMode(.inline)
        .background(SwipeBackEnabler())   // the back gesture stays on when the bar is hidden
        .overlay(alignment: .topTrailing) { fullButton }
        .task { if state.queue.isEmpty { await state.load(model: model) }; await state.ensureTags(model: model) }
        .onChange(of: state.linkTick) { Task { await state.select(state.mode, model: model) } }
        .sensoryFeedback(.impact(weight: .heavy), trigger: state.tick)
        .sensoryFeedback(.impact(weight: .light), trigger: state.undoTick)
        .sheet(isPresented: $showFavourites) { CurateFavourites(model: model, state: state) }
        .focusable()
        .onKeyPress(phases: .down) { press in keys(press) }
    }

    // MARK: keys from the R1 Remote and a keyboard

    private func keys(_ press: KeyPress) -> KeyPress.Result {
        guard !commentFocus, !noteFocus else { return .ignored }
        let c = press.characters.lowercased()
        if "kcmfz".contains(c), c.count == 1 { state.full = true }   // a remote key turns the full view on (S328)
        if state.mode.isCategories {
            if let n = Int(c), (1...3).contains(n) { classify(curateCategories[n - 1].0); return .handled }
            if c == "z" { undo(); return .handled }
            return .ignored
        }
        switch press.key {
        case .rightArrow: act("keep"); return .handled
        case .leftArrow: act("cut"); return .handled
        case .upArrow: if allowsMaybe { act("maybe") }; return .handled
        default: break
        }
        switch c {
        case "k": act("keep")
        case "f": act("keep")   // the web deck's rule (CurateDeck.tsx: "F keeps"): the R1 remote's F must mean the same on both (gap audit 11-14)
        case "c": act("cut")
        case "m": if allowsMaybe { act("maybe") }
        case "z": undo()
        default: return .ignored
        }
        return .handled
    }

    /// A re-pass takes its maybe through the image / phrase / layout strip, so a swipe up or an M does nothing there (seeds excepted).
    private var allowsMaybe: Bool { !(state.mode.maybeNeedsTag && state.current?.class != "seed") }

    private func act(_ dir: String, tag: String? = nil) { Task { await state.commit(dir, tag: tag, model: model) }; drag = .zero }
    private func favourite() { Task { await state.favourite(model: model) }; drag = .zero }
    private func classify(_ cat: String) { Task { await state.classify(cat, model: model) } }
    private func undo() { Task { await state.undo(model: model) } }

    // MARK: header

    private var header: some View {
        VStack(spacing: 4) {
            Menu {
                ForEach(CurateMode.groups, id: \.0) { g in
                    Section(g.0) {
                        Picker(g.0, selection: Binding(get: { state.mode }, set: { m in Task { await state.select(m, model: model) } })) {
                            ForEach(g.1) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                if !state.tagNames.isEmpty {
                    Menu("Tags") {
                        ForEach(state.tagNames, id: \.self) { t in Button(t) { Task { await state.select(CurateMode(kind: .tag, tag: t), model: model) } } }
                    }
                }
                Button { showFavourites = true } label: { Label("Favourites · viewer + comments", systemImage: "heart.text.square") }
            } label: {
                HStack(spacing: 6) {
                    Text(state.mode.title).gTitle(21).foregroundStyle(state.mode.isMaybes ? PLC.maybe : PLG.ink(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(PLG.gold)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Deck: \(state.mode.title). Choose another")
            Text(counts).gEyebrow(10).foregroundStyle(state.notSaved > 0 ? PLG.red : PLG.dim(scheme)).contentTransition(.numericText())
            if state.locked {
                Text("This device is locked · load the vault key in Settings before marking").gEyebrow(10).foregroundStyle(PLG.red).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var counts: String {
        let i = min(state.index + 1, max(state.queue.count, 1)), n = state.queue.count
        var s = "#\(i.formatted()) of \(n.formatted()) · \(max(0, n - state.index).formatted()) left"
        if !state.history.isEmpty { s += " · \(state.kept) kept" }
        if state.notSaved > 0 { s += " · \(state.notSaved) NOT SAVED" }
        return s
    }

    private var fullButton: some View {
        Button { withAnimation(.snappy) { state.full.toggle() } } label: {
            Text(state.full ? "×" : "Full").gEyebrow(11).foregroundStyle(PLG.dim(scheme)).padding(.horizontal, 12).frame(minHeight: 36)
                .background(.thinMaterial, in: Capsule()).overlay { Capsule().strokeBorder(PLG.gold.opacity(0.5), lineWidth: 0.8) }
        }
        .buttonStyle(.plain).opacity(state.full ? 0.45 : 1).padding(.trailing, 12).padding(.top, state.full ? 8 : 2)
        .opacity(state.current == nil ? 0 : 1)
        .accessibilityLabel(state.full ? "Exit full view" : "Full view")
    }

    // MARK: body states

    @ViewBuilder private var content: some View {
        if state.loadFailed {
            VStack(spacing: 12) {
                ContentUnavailableView("YOUR MARKS DID NOT LOAD", systemImage: "exclamationmark.triangle",
                                       description: Text("Nothing was dealt, so you are not shown work you already judged. Pull to try again."))
                Button("Try again") { Task { await state.load(model: model, force: true) } }.buttonStyle(.borderedProminent)
            }.frame(maxHeight: .infinity)
        } else if state.loading && state.queue.isEmpty {
            ProgressView("Loading the queue…").frame(maxHeight: .infinity)
        } else if let it = state.current {
            deck(it)
        } else {
            CurateEmpty(model: model, state: state).frame(maxHeight: .infinity)
        }
    }

    private func deck(_ it: LibraryItem) -> some View {
        VStack(spacing: 10) {
            if !state.full {
                if let tip = tips.currentTip { TipView(tip) }
                if !state.mode.isMaybes && !state.mode.isCategories { commentBox }
            }
            card(it).frame(maxHeight: .infinity)
            if !state.full {
                caption(it)
                if state.mode.isMaybes { noteBox }
                if state.mode.isCategories { categories(it) } else {
                    if state.mode.maybeNeedsTag && it.class != "seed" { tagStrip(it) }
                    keysRow(it)
                    if it.class == "archive-work", (it.sub ?? "").contains("· edited") {
                        Button("Keep · use the original") { Task { await state.keepOriginal(model: model) } }
                            .font(.system(size: 10.5)).textCase(.uppercase).tracking(1.3).foregroundStyle(PLG.dim(scheme)).frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(.bottom, state.full ? 0 : 6)
    }

    private var commentBox: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField("A word about this piece", text: $state.comment, axis: .vertical)
                .lineLimit(1...3).focused($commentFocus).submitLabel(.done)
                .onChange(of: state.comment) { _, v in
                    if v.count > 1000 { state.comment = String(v.prefix(1000)) }
                    // Return finishes the comment (a vertical field would take it as a new line): drop the keyboard, which saves it
                    if v.contains("\n") { state.comment = v.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces); commentFocus = false }
                }
                .onChange(of: state.index) { _, _ in commentFocus = false; noteFocus = false }   // a verdict moves on: the keyboard goes with it (his note 11-13)
                .gCard(padding: 14, radius: 22, active: commentFocus || !state.comment.isEmpty)
                .onChange(of: commentFocus) { _, f in if !f { Task { await state.saveComment(model: model) } } }
                .onSubmit { Task { await state.saveComment(model: model) } }
            switch state.commentState {
            case .saving: Text("saving…").gEyebrow(10).foregroundStyle(PLG.dim(scheme))
            case .saved: Text("saved ✓").gEyebrow(10).foregroundStyle(PLG.dim(scheme))
            case .failed: Text("NOT SAVED: tap the box and tap away to retry").gEyebrow(10).foregroundStyle(PLG.red)
            case .idle: EmptyView()
            }
            tagRow
        }
    }

    /// His tags on this piece, removable, and a field to add one (existing tags offered as he types).
    private var tagRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.currentTags, id: \.self) { t in
                        Button { Task { tagFailed = !(await state.setTag(t, on: false, model: model)) } } label: {
                            Label(t, systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption)
                        }
                        .buttonStyle(.bordered).tint(PLG.gold).accessibilityLabel("Remove tag \(t)")
                    }
                    TextField("Add a tag", text: $tagInput).font(.caption).frame(minWidth: 90).submitLabel(.done)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { let t = tagInput; tagInput = ""; Task { tagFailed = !(await state.setTag(t, on: true, model: model)) } }
                }
            }
            let q = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                let hits = state.tagNames.filter { $0.contains(q) && !state.currentTags.contains($0) }.prefix(6)
                HStack(spacing: 6) {
                    ForEach(Array(hits), id: \.self) { t in
                        Button(t) { tagInput = ""; Task { tagFailed = !(await state.setTag(t, on: true, model: model)) } }
                            .font(.caption).buttonStyle(.bordered)
                    }
                }
            }
            if tagFailed { Text("TAG NOT SAVED: is the vault key loaded?").gEyebrow(10).foregroundStyle(PLG.red) }
        }
        .task { await state.ensureTags(model: model) }
    }

    private var noteBox: some View {
        TextField("What is wrong with this one? (saved with your verdict)", text: $state.note, axis: .vertical)
            .lineLimit(2...4).focused($noteFocus)
            .onChange(of: state.note) { _, v in if v.count > 500 { state.note = String(v.prefix(500)) } }
            .padding(12)
            .background(PLG.surface(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(PLC.maybe, lineWidth: 1) }
    }

    private func caption(_ it: LibraryItem) -> some View {
        VStack(spacing: 5) {
            if let o = origin {
                Text(o == .claudeWords ? "Claude’s words" : o == .cloud ? "Cloud batch" : "API render").gEyebrow(10.5).foregroundStyle(PLC.orange(scheme))
            }
            Text(it.class == "seed" ? (it.origin ?? "seed") : (it.name ?? it.item_id)).gTitle(20).foregroundStyle(PLG.ink(scheme)).lineLimit(1).minimumScaleFactor(0.75)
            Text(state.caption(it)).gEyebrow(10).foregroundStyle(PLG.dim(scheme)).lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: the card

    private func card(_ it: LibraryItem) -> some View {
        let swipes = !state.mode.isCategories && it.class != "essay"
        let shape = RoundedRectangle(cornerRadius: state.full ? 0 : 14, style: .continuous)
        return ZStack {
            PLC.bone
            CurateCardMedia(model: model, state: state, item: it)
            stamp
            if state.full, origin != nil { Rectangle().strokeBorder(PLC.orange(scheme), lineWidth: 5).allowsHitTesting(false) }
        }
        .clipShape(shape)
        .overlay { if origin != nil && !state.full { shape.strokeBorder(PLC.orange(scheme), lineWidth: 3) } }
        .shadow(color: (origin != nil ? Color(hex: 0x8c3c0a) : Color(hex: 0x3c280a)).opacity(origin != nil ? 0.30 : 0.18), radius: 18, y: 10)
        .offset(drag)
        .rotationEffect(.degrees(Double(drag.width / 18)))
        .gesture(swipes ? DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { g in
                let t = g.translation
                if abs(t.width) < threshold && abs(t.height) < threshold { withAnimation(.spring(duration: 0.3)) { drag = .zero }; return }
                // whichever axis moved further decides, so a drift sideways never turns a maybe into a cut
                if abs(t.height) > abs(t.width) && t.height < 0 {
                    if allowsMaybe { act("maybe") } else { withAnimation(.spring(duration: 0.3)) { drag = .zero } }
                } else if t.width > 0 { act("keep") } else { act("cut") }
            } : nil)
        .onTapGesture(count: 3) { withAnimation(.snappy) { state.full.toggle() } }
        .animation(.interactiveSpring, value: drag)
        .contextMenu { cardMenu(it) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Keep") { act("keep") }
        .accessibilityAction(named: "Cut") { act("cut") }
        .accessibilityAction(named: "Maybe") { if allowsMaybe { act("maybe") } }
        .accessibilityAction(named: "Favourite") { favourite() }
    }

    @ViewBuilder private func cardMenu(_ it: LibraryItem) -> some View {
        Button { UIPasteboard.general.string = it.name ?? it.item_id } label: { Label("Copy the name", systemImage: "doc.on.doc") }
        Button { UIPasteboard.general.string = it.item_id } label: { Label("Copy the id", systemImage: "number") }
        if it.class == "archive-work", (it.sub ?? "").contains("· edited") {
            Button { Task { await state.keepOriginal(model: model) } } label: { Label("Keep · use the original", systemImage: "arrow.uturn.backward") }
        }
        Button { withAnimation(.snappy) { state.full.toggle() } } label: { Label(state.full ? "Exit full view" : "Full view", systemImage: "arrow.up.left.and.arrow.down.right") }
    }

    /// The verdict stamp opposite the drag (KEEP reads while dragging right, CUT while dragging left, MAYBE across the top).
    @ViewBuilder private var stamp: some View {
        let ax = abs(drag.width), ay = abs(drag.height)
        let dir: String? = (ax < 24 && ay < 24) ? nil : (ay > ax ? (drag.height < 0 && allowsMaybe ? "maybe" : nil) : (drag.width > 0 ? "keep" : "cut"))
        if let dir {
            let color = dir == "keep" ? PLC.keep : dir == "cut" ? PLC.cut : PLC.maybe
            let pull = min(1, max(ax, ay) / threshold)
            VStack {
                HStack {
                    if dir == "keep" { stampText("KEEP", color).rotationEffect(.degrees(-8)); Spacer() }
                    else if dir == "cut" { Spacer(); stampText("CUT", color).rotationEffect(.degrees(8)) }
                    else { Spacer(); stampText("MAYBE", color); Spacer() }
                }
                Spacer()
            }
            .padding(22).opacity(pull).allowsHitTesting(false)
        }
    }

    private func stampText(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 22, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(c)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(c, lineWidth: 3) }
    }

    // MARK: controls

    /// His five keycaps, in the web deck's order (cut, maybe, keep, fav, undo), each pressing down under the finger.
    private func keysRow(_ it: LibraryItem) -> some View {
        let c = state.carried(it)
        let leave = state.mode.kind == .favs || (state.mode.rePassRules && (c.prev == "keep" || c.prev == "fav"))
        return HStack(spacing: 2) {
            KeyCap(model: model, name: "cut", label: "Cut") { act("cut") }
            if allowsMaybe { KeyCap(model: model, name: "maybe", label: "Maybe") { act("maybe") } }
            KeyCap(model: model, name: "keep", label: leave ? (c.prev == "fav" ? "Leave as favourite" : "Leave as keep") : "Keep") { act("keep") }
            KeyCap(model: model, name: "fav", label: "Favourite: a keep, and a taste reference", down: state.starred || c.prev == "fav") { favourite() }
            KeyCap(model: model, name: "undo", label: "Undo") { undo() }
                .disabled(state.history.isEmpty).opacity(state.history.isEmpty ? 0.4 : 1)
        }
        .padding(5).background(PLC.tray, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 7, y: 4)
    }

    /// A re-pass maybe says what he likes: the image, the phrase or the layout.
    private func tagStrip(_ it: LibraryItem) -> some View {
        let c = state.carried(it)
        return HStack(spacing: 0) {
            ForEach(Array([("img", "image"), ("phrase", "phrase"), ("layout", "layout")].enumerated()), id: \.offset) { n, t in
                let on = c.prev == "maybe" && c.note == t.0
                Button { act("maybe", tag: t.0) } label: {
                    Text(t.1).gEyebrow(11).foregroundStyle(on ? PLG.bg(scheme) : PLC.maybe)
                        .frame(maxWidth: .infinity, minHeight: 44).background(on ? PLC.maybe : .clear)
                }
                .buttonStyle(.plain).accessibilityLabel("Maybe: I like the \(t.1)")
                if n < 2 { Rectangle().fill(PLC.maybe).frame(width: 1) }
            }
        }
        .frame(height: 44).clipShape(Capsule()).overlay { Capsule().strokeBorder(PLC.maybe, lineWidth: 1) }
    }

    /// The categories deck: three buttons, the machine's guess pre-lit; a swipe never marks taste here.
    private func categories(_ it: LibraryItem) -> some View {
        let guess = state.carried(it).note
        return HStack(spacing: 10) {
            ForEach(curateCategories, id: \.0) { k in
                let on = guess == k.0
                Button { classify(k.0) } label: {
                    Text(k.1).gEyebrow(12).foregroundStyle(on ? PLG.bg(scheme) : PLG.ink(scheme))
                        .frame(maxWidth: 140, minHeight: 48).frame(maxWidth: .infinity)
                        .background(on ? PLG.ink(scheme) : .clear, in: Capsule())
                        .overlay { Capsule().strokeBorder(on ? PLG.ink(scheme) : PLG.gold.opacity(0.6), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            KeyCap(model: model, name: "undo", label: "Undo") { undo() }.disabled(state.history.isEmpty).opacity(state.history.isEmpty ? 0.4 : 1).frame(width: 52)
        }
        .padding(.top, 6)
    }
}

/// The cleared screen (web Empty): what is left in each deck, and a door into every other one.
struct CurateEmpty: View {
    let model: AppModel
    let state: CurateModel
    @Environment(\.colorScheme) private var scheme

    private func count(_ c: String) -> Int? { state.waiting[c] }
    private func door(_ title: String, _ m: CurateMode, n: Int? = nil, orange: Bool = false) -> some View {
        Button { Task { await state.select(m, model: model) } } label: {
            Text("\(title)\(n.map { " (\($0.formatted()))" } ?? "") →").font(.system(size: 12, design: .monospaced)).foregroundStyle(orange ? .white : PLG.bg(scheme))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(orange ? PLC.orange(.light) : PLG.ink(scheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Queue clear").gEyebrow(12).foregroundStyle(PLG.gold)
                Text("Nothing left to decide").gTitle(26).foregroundStyle(PLG.ink(scheme))
                Text("\(state.mode.short.lowercased()) · this session: +\(state.kept) keep · ~\(state.maybes) maybe · x\(state.cuts) cut.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).multilineTextAlignment(.center)
                FlowLayout {
                    ForEach(Array([("seed", "curate seed phrases"), ("still", "curate stills"), ("cinematic", "curate shorts + videos"), ("code-piece", "curate code pieces"),
                                   ("archive-work", "curate archive works"), ("", "curate everything")].enumerated()), id: \.offset) { _, d in
                        door(d.1, CurateMode(kind: .unmarked, cls: d.0.isEmpty ? nil : d.0), n: count(d.0))
                    }
                    door("sort archive categories", CurateMode(kind: .categories))
                    door("new: unmarked", CurateMode(kind: .new), orange: true)
                    door("re-pass everything", CurateMode(kind: .repass))
                    door("star the favourites", CurateMode(kind: .favs))
                    door("curate essays", CurateMode(kind: .unmarked, cls: "essay"))
                    door("trash: everything you cut", CurateMode(kind: .trash))
                    if state.mode.kind != .maybes { door("curate maybes", CurateMode(kind: .maybes, cls: state.mode.cls), n: count("m:\(state.mode.cls ?? "")")) }
                }
            }
            .padding(24).frame(maxWidth: .infinity)
        }
        .task { await state.ensureSeedCount(model: model) }
        .refreshable { await state.load(model: model, force: true) }
    }
}

/// Doors wrap onto as many lines as they need, centred.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var out: [[Int]] = [[]]; var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let w = v.sizeThatFits(.unspecified).width
            if x + w > width, !out[out.count - 1].isEmpty { out.append([]); x = 0 }
            out[out.count - 1].append(i); x += w + spacing
        }
        return out
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        let r = rows(subviews, width: width)
        let h = r.map { row in row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0 }
        return CGSize(width: width, height: h.reduce(0, +) + spacing * CGFloat(max(0, r.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            var x = bounds.midX - (sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))) / 2
            for (k, i) in row.enumerated() { subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += sizes[k].width + spacing }
            y += (sizes.map(\.height).max() ?? 0) + spacing
        }
    }
}
