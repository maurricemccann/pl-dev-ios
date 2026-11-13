import SwiftUI

// The Library screen, ported from pl-curves-gallery components/LibraryBrowser.tsx (his order 11-13: every feature of the web app,
// working). Grid and list, the Latest batches shelf, the verdict strip with live counts, class / source / tag filters, tag rename,
// Select with Range, bulk verdicts and bulk tags, Undo (20 deep), Deck → into Curate, paging by 100, the full-screen viewer.

enum Verdict: String, CaseIterable, Identifiable {
    case all = "All", unmarked = "Unmarked", keep = "Keep", fav = "Favourite", maybe = "Maybe", cut = "Cut", replaced = "Replaced"
    var id: String { rawValue }
    func matches(_ m: TasteMark?) -> Bool { self == .all || Verdict.of(m) == self }

    /// The verdict a mark stands for (a keep with the note "fav" is a favourite; anything else unknown is unmarked).
    static func of(_ m: TasteMark?) -> Verdict {
        guard let m else { return .unmarked }
        if m.isFav { return .fav }
        switch m.v { case "keep": return .keep; case "maybe": return .maybe; case "cut": return .cut; case "replaced": return .replaced; default: return .unmarked }
    }
    /// The word the store takes: fav is a keep with a note, unmarked is clear.
    init?(wire: String) {
        switch wire { case "keep": self = .keep; case "fav": self = .fav; case "maybe": self = .maybe; case "cut": self = .cut; case "clear": self = .unmarked; default: return nil }
    }
    var tint: Color? {
        switch self { case .keep: return PLG.teal; case .fav: return PLG.gold; case .maybe: return PLG.amber; case .cut: return PLG.red; case .replaced: return Color(hex: 0x6b5d48); default: return nil }
    }
}

/// "11-02 17:37" for a cloud batch, "11-02 gt" for a PC export stamp: the web's fmtBatch.
func libFmtBatch(_ b: String) -> String {
    let c = Array(b)
    guard c.count >= 8 else { return b }
    let md = String(c[4..<6]) + "-" + String(c[6..<8])
    if c.count >= 13, c[8] == "g", c[9...12].allSatisfy(\.isNumber) { return md + " " + String(c[9..<11]) + ":" + String(c[11..<13]) }
    return md + " " + String(c[8...])
}

private struct LibScope: Equatable {
    var cls: String?; var source: String?; var batch: String?; var tag: String?; var q: String; var items: Int; var tagged: Int; var rev: Int
}

struct LibraryView: View {
    let model: AppModel
    @State private var data = LibraryData.shared
    @State private var nav = GalleryNav.shared
    @AppStorage("pldev.lib.list") private var listMode = false
    @State private var verdict: Verdict = .unmarked
    @State private var landed = false
    @State private var cls: String?
    @State private var source: String?
    @State private var batch: String?
    @State private var tagFilter: String?
    @State private var search = ""
    @State private var q = ""
    @State private var limit = 100
    @State private var failed = false
    @State private var failReason: String?
    @State private var scoped: [LibraryItem] = []
    @State private var open: LibraryItem?
    @State private var selecting = false
    @State private var picked = Set<String>()
    @State private var range = false
    @State private var lastTap: Int?
    @State private var showTag = false
    @State private var undo: [[UndoStep]] = []
    @State private var line: String?
    @State private var renameTo = ""
    @State private var tick = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    struct UndoStep { let id: String; let prev: TasteMark? }
    private let classes: [(String?, String)] = [(nil, "All classes"), ("still", "Stills"), ("cinematic", "Shorts"), ("code-piece", "Code"), ("font", "Fonts"), ("archive-work", "Archive")]

    private var scope: LibScope {
        LibScope(cls: cls, source: source, batch: batch, tag: tagFilter, q: q, items: data.items.count, tagged: data.tags.count, rev: data.tags.values.reduce(0) { $0 + $1.count })
    }

    /// Everything but the verdict: archive works stay out unless the class picks them (his ruling S282); unrenderable never shows; newest batch first.
    private func rescope() {
        let needle = q.trimmingCharacters(in: .whitespaces).lowercased()
        let out = data.items.filter { it in
            if data.unrenderable.contains(it.vault_id) { return false }
            if cls == nil, it.class == "archive-work" { return false }
            if let cls, it.class != cls { return false }
            if let source, it.source != source { return false }
            if let batch, data.batchOf[it.vault_id] != batch { return false }
            if let tagFilter, !(data.tags[it.vault_id] ?? []).contains(tagFilter) { return false }
            if !needle.isEmpty, !"\(it.name ?? "") \(it.item_id) \(it.sub ?? "")".lowercased().contains(needle) { return false }
            return true
        }
        scoped = out.enumerated().sorted { a, b in
            let sa = data.batchOf[a.element.vault_id] ?? "", sb = data.batchOf[b.element.vault_id] ?? ""
            if sa.isEmpty != sb.isEmpty { return !sa.isEmpty }
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private func tally() -> [Verdict: Int] {
        var c: [Verdict: Int] = [:]
        for it in scoped { c[Verdict.of(data.marks[it.vault_id]), default: 0] += 1 }
        c[.all] = scoped.count
        return c
    }

    var body: some View {
        let counts = tally()
        let all = verdict == .all ? scoped : scoped.filter { verdict.matches(data.marks[$0.vault_id]) }
        let page = Array(all.prefix(limit))
        Group {
            if listMode {
                List {
                    Section { header(counts: counts, total: all.count).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                    Section {
                        ForEach(Array(page.enumerated()), id: \.element.id) { n, it in row(it, n: n) }
                        footer(all.count)
                    }
                }
                .listStyle(.plain)
            } else {
                ScrollView {
                    header(counts: counts, total: all.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(Array(page.enumerated()), id: \.element.id) { n, it in tile(it, n: n) }
                    }
                    .padding(.horizontal, 16)
                    footer(all.count).padding(.bottom, 24)
                }
            }
        }
        .gScreen()
        .navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(all: all) }
        .sheet(isPresented: $showTag) { TagSheet(data: data, model: model, picked: $picked, selecting: $selecting) }
        .sensoryFeedback(.impact(weight: .medium), trigger: tick)
        .searchable(text: $search, prompt: "Name or id")
        .task(id: search) { try? await Task.sleep(for: .milliseconds(250)); if !Task.isCancelled { q = search } }
        .overlay(alignment: .bottom) {
            if data.notSaved > 0 { Text("\(data.notSaved) not saved").gEyebrow(11).padding(.horizontal, 14).padding(.vertical, 8).background(PLG.red, in: Capsule()).foregroundStyle(.white).padding() }
        }
        .refreshable { await reload(force: true) }
        .task { if data.items.isEmpty || !data.marksLoaded { await reload(force: false) } else { rescope() } }
        .onChange(of: scope) { _, _ in rescope(); limit = 100 }
        .onChange(of: verdict) { _, _ in limit = 100 }
        .fullScreenCover(item: $open) { it in PieceViewer(model: model, list: all, start: it) }
        .navigationDestination(item: $nav.room) { room in room.view(model) }
    }

    // MARK: header (the shelf, the sources, the verdict strip, the filters)

    private func header(counts: [Verdict: Int], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GalleryHeading(eyebrow: "The Curve Library", title: "Library")
            if failed && !data.marksLoaded {
                ContentUnavailableView("YOUR MARKS DID NOT LOAD", systemImage: "exclamationmark.triangle", description: Text("Nothing can be marked until they do. \(failReason ?? "") Pull to try again."))
            } else if data.items.isEmpty {
                ProgressView("Opening the library…").frame(maxWidth: .infinity).padding(.top, 60)
            }
            if !data.items.isEmpty { shelf }
            sources
            verdictStrip(counts)
            filters
            if let t = tagFilter { renameRow(t) }
            ResultLine(text: line)
            Text("\(total.formatted()) shown · orange ring = cloud batch or API render").font(.system(size: 11)).foregroundStyle(PLG.dim(scheme))
            if total == 0, !data.items.isEmpty {
                Text("Nothing here under these filters. \(verdict == .unmarked ? "Every item in this scope has a verdict. Pick a batch above, or All." : "")")
                    .font(.footnote).foregroundStyle(PLG.dim(scheme))
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    /// The ten newest batches with what is new, kept, maybe and cut. Ignores every filter, so it never disappears.
    private var shelf: some View {
        var by: [String: [Verdict: Int]] = [:]
        for it in data.items { if let b = data.batchOf[it.vault_id] { by[b, default: [:]][Verdict.of(data.marks[it.vault_id]), default: 0] += 1 } }
        let batches = by.keys.sorted(by: >).prefix(10)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Latest batches").gEyebrow(10).foregroundStyle(PLG.goldDim(scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(batches), id: \.self) { b in
                        let c = by[b] ?? [:]
                        Button { batch = batch == b ? nil : b; verdict = .all } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(libFmtBatch(b)).gMono(12).foregroundStyle(PLG.ink(scheme))
                                HStack(spacing: 5) {
                                    if (c[.unmarked] ?? 0) > 0 { Text("\(c[.unmarked] ?? 0) new").foregroundStyle(PLG.red) }
                                    Text("\((c[.keep] ?? 0) + (c[.fav] ?? 0))✓").foregroundStyle(PLG.teal)
                                    Text("\(c[.maybe] ?? 0)~").foregroundStyle(PLG.amber)
                                    Text("\(c[.cut] ?? 0)✕").foregroundStyle(PLG.red)
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced)).monospacedDigit()
                            }
                            .gCard(padding: 12, radius: 18, active: batch == b).fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sources: some View {
        HStack(spacing: 8) {
            ForEach([("cloud-batch", "Cloud batches"), ("on-model", "API renders")], id: \.0) { s in
                let on = source == s.0
                Button { source = on ? nil : s.0; batch = nil; verdict = .all } label: {
                    Text("\(s.1) \(data.items.filter { $0.source == s.0 }.count.formatted())").gEyebrow(10.5).foregroundStyle(on ? .white : PLG.orange)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(on ? PLG.orange : PLG.orange.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(PLG.orange.opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func verdictStrip(_ counts: [Verdict: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Verdict.allCases) { v in
                    Button { verdict = v } label: { GalleryChip(title: v.rawValue, count: counts[v] ?? 0, on: verdict == v, tint: v.tint) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var filters: some View {
        let tagCounts = data.tags.values.reduce(into: [String: Int]()) { acc, l in for t in l { acc[t, default: 0] += 1 } }
        let sourceNames = Array(Set(data.items.compactMap(\.source))).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipMenu(classes.first { $0.0 == cls }?.1 ?? "All classes") {
                    Picker("Class", selection: $cls) { ForEach(classes, id: \.1) { Text($0.1).tag($0.0) } }
                }
                chipMenu(source.map { $0 } ?? "All sources") {
                    Picker("Source", selection: $source) { Text("All sources").tag(String?.none); ForEach(sourceNames, id: \.self) { Text($0).tag(String?.some($0)) } }
                }
                if !tagCounts.isEmpty {
                    chipMenu(tagFilter.map { "#\($0)" } ?? "All tags") {
                        Picker("Tag", selection: $tagFilter) {
                            Text("All tags").tag(String?.none)
                            ForEach(tagCounts.keys.sorted(), id: \.self) { Text("\($0) (\(tagCounts[$0] ?? 0))").tag(String?.some($0)) }
                        }
                    }
                }
                if let b = batch {
                    Button { batch = nil } label: { GalleryChip(title: "batch \(libFmtBatch(b)) ✕", on: true) }.buttonStyle(.plain)
                }
            }
        }
        .onChange(of: tagFilter) { _, t in if t != nil { verdict = .all } }
    }

    private func chipMenu<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        Menu { content() } label: {
            HStack(spacing: 6) { Text(title).font(.system(size: 14, weight: .medium)); Image(systemName: "chevron.down").font(.caption2) }
                .foregroundStyle(PLG.ink(scheme)).padding(.horizontal, 14).frame(minHeight: 44)
                .overlay { Capsule().strokeBorder(PLG.gold.opacity(0.45), lineWidth: 0.9) }
        }
    }

    private func renameRow(_ t: String) -> some View {
        HStack(spacing: 8) {
            TextField("rename \(t) to (or merge)", text: $renameTo).textInputAutocapitalization(.never).autocorrectionDisabled()
                .gCard(padding: 10, radius: 16)
            Button("Rename") {
                let to = renameTo.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
                guard to.range(of: #"^[a-z0-9-]{1,24}$"#, options: .regularExpression) != nil, to != t else { line = "Not saved. Use a different tag: letters, digits, hyphens."; return }
                Task { line = await data.rename(t, to: to, model: model); if line?.hasPrefix("Renamed") == true { tagFilter = to; renameTo = "" }; tick += 1 }
            }
            .buttonStyle(.bordered).tint(PLG.gold).disabled(renameTo.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder private func footer(_ total: Int) -> some View {
        if total > limit {
            Button("Show more") { limit += 100 }
                .buttonStyle(.bordered).tint(PLG.gold).frame(maxWidth: .infinity).padding(.vertical, 12)
                .onAppear { limit += 100 }   // the web's infinite window: the end of the page loads the next hundred
                .listRowBackground(Color.clear)
        }
    }

    // MARK: tiles and rows

    private func tile(_ it: LibraryItem, n: Int) -> some View {
        let m = data.marks[it.vault_id]
        return Button { if selecting { tapSel(it.vault_id, n: n) } else { open = it } } label: {
            Tile(item: it, mark: m, url: data.media(it, model: model).still)
                .overlay(alignment: .topLeading) {
                    if selecting { Image(systemName: picked.contains(it.vault_id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(.white, picked.contains(it.vault_id) ? Color.accentColor : .black.opacity(0.3)).padding(6) }
                }
                .overlay { if picked.contains(it.vault_id) { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PLG.ink(scheme), lineWidth: 3) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(it.name ?? it.item_id), \(Verdict.of(m).rawValue)")
        .contextMenu { menu(for: it) }
    }

    private func row(_ it: LibraryItem, n: Int) -> some View {
        let m = data.marks[it.vault_id]
        let v = Verdict.of(m)
        let tags = (data.tags[it.vault_id] ?? []).map { "#" + $0 }
        let meta = ([it.class, it.source ?? "", data.batchOf[it.vault_id].map(libFmtBatch) ?? ""] + tags).filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 10) {
            if selecting { Image(systemName: picked.contains(it.vault_id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(picked.contains(it.vault_id) ? PLG.gold : PLG.dim(scheme)) }
            Tile(item: it, mark: m, url: data.media(it, model: model).still).frame(width: 44, height: 55)
            VStack(alignment: .leading, spacing: 2) {
                Text(it.name ?? it.item_id).gTitle(16).foregroundStyle(PLG.ink(scheme)).lineLimit(1)
                Text(meta).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !selecting { VerdictButtons(v: v, size: 40) { w in Task { await apply([it.vault_id], w) } } }
        }
        .contentShape(Rectangle())
        .onTapGesture { if selecting { tapSel(it.vault_id, n: n) } else { open = it } }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {   // swipe left is the yes
            Button { Task { await apply([it.vault_id], "keep") } } label: { Label("Keep", systemImage: "checkmark") }.tint(PLG.teal)
            Button { Task { await apply([it.vault_id], "fav") } } label: { Label("Favourite", systemImage: "star.fill") }.tint(PLG.gold)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {    // swipe right is the no
            Button { Task { await apply([it.vault_id], "cut") } } label: { Label("Cut", systemImage: "xmark") }.tint(PLG.red)
            Button { Task { await apply([it.vault_id], "maybe") } } label: { Label("Maybe", systemImage: "questionmark") }.tint(PLG.amber)
        }
        .contextMenu { menu(for: it) }
    }

    @ViewBuilder private func menu(for it: LibraryItem) -> some View {
        let v = Verdict.of(data.marks[it.vault_id])
        Button(v == .keep ? "Clear the keep" : "Keep", systemImage: "checkmark") { Task { await apply([it.vault_id], v == .keep ? "clear" : "keep") } }
        Button(v == .fav ? "Clear the favourite" : "Favourite", systemImage: "star") { Task { await apply([it.vault_id], v == .fav ? "clear" : "fav") } }
        Button(v == .maybe ? "Clear the maybe" : "Maybe", systemImage: "questionmark") { Task { await apply([it.vault_id], v == .maybe ? "clear" : "maybe") } }
        Button(v == .cut ? "Clear the cut" : "Cut", systemImage: "xmark", role: .destructive) { Task { await apply([it.vault_id], v == .cut ? "clear" : "cut") } }
        Divider()
        Button("Tag this piece…", systemImage: "tag") { picked = [it.vault_id]; showTag = true }
        Button("Copy the id", systemImage: "doc.on.doc") { UIPasteboard.general.string = it.vault_id }
    }

    // MARK: toolbar

    @ToolbarContentBuilder private func toolbar(all: [LibraryItem]) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { GalleryRoomsView(model: model) } label: { Label("Rooms", systemImage: "square.grid.2x2") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await undoLast() } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(undo.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("View", selection: $listMode) { Label("Grid", systemImage: "square.grid.3x3").tag(false); Label("List", systemImage: "list.bullet").tag(true) }
                Button("Deck →", systemImage: "rectangle.stack") { model.open(.section(id: "curate", path: [deck.rawValue], query: [:])) }
                Button(selecting ? "Done selecting" : "Select", systemImage: "checkmark.circle") { withAnimation { selecting.toggle(); picked.removeAll(); range = false; lastTap = nil } }
            } label: { Label("More", systemImage: "ellipsis.circle") }
        }
        if selecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Menu("\(picked.count) chosen") {
                    Button("All shown", systemImage: "checklist") { picked = Set(all.prefix(limit).map(\.vault_id)) }
                    Button("None", systemImage: "circle") { picked.removeAll() }
                    Toggle("Range: tap two to take all between", isOn: $range)
                    Button("Tag…", systemImage: "tag") { showTag = true }.disabled(picked.isEmpty)
                }
                Spacer()
                bulk("cut", "xmark", PLG.red, "Cut"); bulk("maybe", "questionmark", PLG.amber, "Maybe"); bulk("keep", "checkmark", PLG.teal, "Keep"); bulk("fav", "star.fill", PLG.gold, "Favourite"); bulk("clear", "eraser", nil, "Clear the mark")
            }
        }
    }

    private func bulk(_ w: String, _ symbol: String, _ tint: Color?, _ label: String) -> some View {
        Button { let ids = Array(picked); Task { await apply(ids, w); picked.removeAll() } } label: { Image(systemName: symbol) }
            .tint(tint).disabled(picked.isEmpty).accessibilityLabel(label)
    }

    /// The Curate deck the current scope belongs to (the web's Deck → door).
    private var deck: CurateDeck {
        if source == "cloud-batch" { return .cloud }
        if source == "on-model" { return .api }
        switch verdict { case .maybe: return .maybes; case .cut: return .trash; case .keep, .fav: return .favs; default: return .everything }
    }

    private func tapSel(_ id: String, n: Int) {
        let shownIDs = Array((verdict == .all ? scoped : scoped.filter { verdict.matches(data.marks[$0.vault_id]) }).prefix(limit))
        if range, let a = lastTap, a != n, shownIDs.indices.contains(a), shownIDs.indices.contains(n) {
            for it in shownIDs[min(a, n)...max(a, n)] { picked.insert(it.vault_id) }
        } else if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        lastTap = n
    }

    // MARK: writes

    /// Optimistic, put back and counted when the store refuses. "replaced" is the system's word; a keep never strips a favourite.
    private func apply(_ ids: [String], _ wire: String) async {
        guard data.marksLoaded, let target = Verdict(wire: wire) else { return }
        let targets = ids.filter { id in
            let cur = Verdict.of(data.marks[id])
            if cur == .replaced { return false }
            if wire == "keep", cur == .fav { return false }
            return cur != target
        }
        guard !targets.isEmpty else { return }
        let steps = targets.map { UndoStep(id: $0, prev: data.marks[$0]) }
        let at = ISO8601DateFormatter().string(from: .now)
        for s in steps {
            switch wire {
            case "clear": data.marks[s.id] = nil
            case "fav": data.marks[s.id] = TasteMark(v: "keep", at: at, note: "fav", comment: s.prev?.comment)
            default: data.marks[s.id] = TasteMark(v: wire, at: at, comment: s.prev?.comment)
            }
        }
        tick += 1
        let refused = await data.writeMarks(targets.map { wire == "fav" ? ["id": $0, "v": "keep", "note": "fav"] : ["id": $0, "v": wire] }, model: model)
        for s in steps where refused.contains(s.id) { data.marks[s.id] = s.prev }
        let kept = steps.filter { !refused.contains($0.id) }
        if !refused.isEmpty { line = "Not saved. The store refused \(refused.count) of \(targets.count); they were put back." } else { line = nil }
        if !kept.isEmpty { undo = Array((undo + [kept]).suffix(20)) }
        LibraryGlanceWriter.publish(data)
    }

    func undoLast() async {
        guard let last = undo.last else { return }
        undo.removeLast()
        for s in last { data.marks[s.id] = s.prev }
        tick += 1
        let wire: [[String: String]] = last.map { s in
            guard let p = s.prev else { return ["id": s.id, "v": "clear"] }
            var d = ["id": s.id, "v": p.v]; if let n = p.note { d["note"] = n }; return d
        }
        let refused = await data.writeMarks(wire, model: model)
        line = refused.isEmpty ? "Undone." : "Not saved. The store refused the undo for \(refused.count)."
        LibraryGlanceWriter.publish(data)
    }

    private func reload(force: Bool) async {
        do { try await data.load(model: model, force: force); failed = false; failReason = nil } catch { failed = true; failReason = plainSentence(error) }
        rescope()
        if !landed, !data.items.isEmpty {   // Unmarked is the working queue; an empty queue lands on All so the page never opens blank
            landed = true
            if (tally()[.unmarked] ?? 0) == 0 { verdict = .all }
        }
    }
}

/// The four verdict circles, the web's `Verdicts`: tapping the active one clears it.
struct VerdictButtons: View {
    let v: Verdict
    var size: CGFloat = 44
    let onTap: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            b("cut", .cut); b("maybe", .maybe); b("keep", .keep); b("fav", .fav)
        }
    }
    private func b(_ w: String, _ me: Verdict) -> some View {
        let on = v == me
        let tint = me.tint ?? .gray
        return Button { onTap(on ? "clear" : w) } label: {
            PLIcon.mark(w).resizable().scaledToFit().frame(width: size * 0.38, height: size * 0.38)
                .foregroundStyle(on ? Color(hex: 0x15120b) : tint)
                .frame(width: size, height: size)
                .background(on ? tint : Color.clear, in: Circle())
                .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
        }
        .buttonStyle(.plain).accessibilityLabel(me.rawValue).accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A library tile as the web draws it: the piece, its name, a play badge on clips, the mark's dot (faint when unmarked), an orange ring on cloud and API renders.
struct Tile: View {
    let item: LibraryItem
    let mark: TasteMark?
    let url: URL?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: 0x1a1610)
            if let url { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            else { Text(item.name ?? item.vault_id).font(.caption2).padding(4) }
        }
        .overlay(alignment: .bottomTrailing) {
            Circle().fill(Verdict.of(mark).tint ?? PLG.dim(.dark)).frame(width: 12, height: 12).opacity(mark == nil ? 0.35 : 1)
                .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 2)).padding(6)
        }
        .overlay(alignment: .topLeading) {
            if item.class == "cinematic" || item.class == "code-piece" {
                Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(5).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4)).padding(5)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(item.name ?? item.vault_id).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.white)
                .lineLimit(1).padding(.leading, 6).padding(.trailing, 26).padding(.vertical, 3)
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(item.source == "cloud-batch" || item.source == "on-model" ? PLG.orange : PLG.gold.opacity(0.22), lineWidth: item.source == "cloud-batch" || item.source == "on-model" ? 2 : 0.8))
    }
}

/// Tag or untag the chosen pieces. His own tags sit in a list too (iOS hides suggestions behind a text field).
struct TagSheet: View {
    let data: LibraryData
    let model: AppModel
    @Binding var picked: Set<String>
    @Binding var selecting: Bool
    @State private var name = ""
    @State private var line: String?
    @Environment(\.dismiss) private var dismiss

    private var clean: String { name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-") }
    private var valid: Bool { clean.range(of: #"^[a-z0-9-]{1,24}$"#, options: .regularExpression) != nil }

    var body: some View {
        let counts = data.tags.values.reduce(into: [String: Int]()) { acc, l in for t in l { acc[t, default: 0] += 1 } }
        NavigationStack {
            Form {
                Section("Tag name") {
                    TextField("letters, digits, hyphens, up to 24", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if !counts.isEmpty {
                    Section("Your tags") {
                        ForEach(counts.keys.sorted(), id: \.self) { t in Button { name = t } label: { LabeledContent("#" + t, value: "\(counts[t] ?? 0)") } }
                    }
                }
                Section {
                    Button("Tag \(picked.count) \(picked.count == 1 ? "piece" : "pieces")") { Task { await go(add: true) } }.disabled(!valid || picked.isEmpty)
                    Button("Untag \(picked.count)") { Task { await go(add: false) } }.disabled(!valid || picked.isEmpty)
                } footer: { if !valid, !name.isEmpty { Text("Tag: letters, digits, hyphens, up to 24.") } }
                if let line { Section { ResultLine(text: line) } }
            }
            .navigationTitle("Tag \(picked.count)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func go(add: Bool) async {
        line = await data.tag(Array(picked), add: add, tag: clean, model: model)
        if line?.hasPrefix("Not") == false { picked.removeAll(); selecting = false; dismiss() }
    }
}

/// Full screen: swipe between pieces, mark each, a word about it. Favourite = keep with the note "fav"; tapping the active
/// verdict clears it; a favourite is never overwritten by a plain keep. The list is frozen at open, so a marked piece stays until
/// you swipe on (the web moves on only for keyboard marks).
struct PieceViewer: View {
    let model: AppModel
    let list: [LibraryItem]
    @State var selection: String
    @State private var data = LibraryData.shared
    @State private var comment = ""
    @State private var note = ""
    @State private var tick = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(model: AppModel, list: [LibraryItem], start: LibraryItem) {
        self.model = model; self.list = list; _selection = State(initialValue: start.vault_id)
    }

    private var index: Int { list.firstIndex { $0.vault_id == selection } ?? 0 }
    private var current: LibraryItem? { list.first { $0.vault_id == selection } }
    private var ringed: Bool { current?.source == "cloud-batch" || current?.source == "on-model" }
    private var v: Verdict { Verdict.of(data.marks[selection]) }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, it in
                    Group { if abs(n - index) <= 2 { page(it) } else { Color.clear } }.tag(it.vault_id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background { ZStack { GalleryGround(); if ringed { PLG.orange.opacity(0.12).ignoresSafeArea() } } }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("\(index + 1) / \(list.count)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0).accessibilityLabel("Previous")
                    Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(index >= list.count - 1).accessibilityLabel("Next")
                    if let it = current, let u = data.media(it, model: model).video ?? data.media(it, model: model).still { ShareLink(item: u) }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .onChange(of: selection, initial: true) { _, id in comment = ownComment(data.marks[id]?.comment); note = "" }
        }
    }

    private func page(_ it: LibraryItem) -> some View {
        let m = data.media(it, model: model)
        return Group {
            if it.class == "code-piece" { LivePieceCard(model: model, pieceID: it.item_id, thumb: m.still) }
            else if let vid = m.video { LoopingClip(url: vid) }
            else if let s = m.still { AsyncImage(url: s) { $0.resizable().scaledToFit() } placeholder: { ProgressView() } }
            else { Text(it.name ?? it.vault_id).foregroundStyle(PLG.dim(scheme)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func step(_ d: Int) { if let n = list.indices.contains(index + d) ? index + d : nil { withAnimation { selection = list[n].vault_id } } }

    /// The system's own notes ("regenerated from your favourites", "replaced by …") are not his words about the piece.
    private func ownComment(_ c: String?) -> String {
        guard let c, c.range(of: #"^(regenerated from your favourites|replaced by)"#, options: .regularExpression) == nil else { return "" }
        return c
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let it = current {
                VStack(spacing: 2) {
                    if ringed { Text(it.source == "cloud-batch" ? "Cloud batch" : "API render").gEyebrow(10.5).foregroundStyle(PLG.orange) }
                    Text(it.name ?? it.item_id).gTitle(19).foregroundStyle(PLG.ink(scheme)).lineLimit(1)
                    Text(([it.item_id, it.class, it.source ?? "", data.batchOf[it.vault_id].map(libFmtBatch) ?? "", v.rawValue] + (data.tags[it.vault_id] ?? []).map { "#" + $0 }).filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            VerdictButtons(v: v, size: 56) { w in Task { await set(w) } }
            if v != .unmarked {
                HStack(alignment: .bottom) {
                    TextField("Tell me something about this piece", text: $comment, axis: .vertical).lineLimit(1...3)
                        .gCard(padding: 12, radius: 16, active: !comment.isEmpty).onSubmit { Task { await saveComment() } }
                    Button { Task { await saveComment() } } label: {
                        Text(note.isEmpty ? "Save" : note).gEyebrow(11).foregroundStyle(PLG.gold).padding(.horizontal, 14).frame(minHeight: 44).overlay { Capsule().strokeBorder(PLG.gold.opacity(0.45)) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding().background(.ultraThinMaterial)
    }

    private func set(_ w: String) async {
        let id = selection, prev = data.marks[id], cur = Verdict.of(prev)
        guard data.marksLoaded, let target = Verdict(wire: w), cur != .replaced, !(w == "keep" && cur == .fav), cur != target else { return }
        await saveComment()
        let at = ISO8601DateFormatter().string(from: .now)
        switch w {
        case "clear": data.marks[id] = nil
        case "fav": data.marks[id] = TasteMark(v: "keep", at: at, note: "fav", comment: prev?.comment)
        default: data.marks[id] = TasteMark(v: w, at: at, comment: prev?.comment)
        }
        tick += 1
        let refused = await data.writeMarks([w == "fav" ? ["id": id, "v": "keep", "note": "fav"] : ["id": id, "v": w]], model: model)
        if !refused.isEmpty { data.marks[id] = prev }
        LibraryGlanceWriter.publish(data)
    }

    private func saveComment() async {
        let id = selection, t = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard data.marks[id] != nil, t != ownComment(data.marks[id]?.comment) else { return }
        let prev = data.marks[id]?.comment
        data.marks[id]?.comment = t
        let ok = await data.post(["only": "comment", "id": id, "comment": String(t.prefix(1000))], model: model)
        if !ok { data.marks[id]?.comment = prev }
        note = ok ? "Saved" : "Not saved"
    }
}
