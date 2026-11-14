import SwiftUI

// The archive, native: the site's own viewer (`public/archive-embed/app.js` in pl-headless) rebuilt on the phone. The same record
// the site reads (the R2 manifest of the complete works, his keeps leading, the Lab joined each Friday), the same search, lenses,
// favourites, colourways, stepping and request ballot. Third-party marks never show (his hard no, the same list the site holds).

struct ArchiveWork: Codable, Identifiable, Hashable, Sendable {
    struct Colourway: Codable, Hashable, Sendable {
        let cr: String
        let color: String?
        let url: String
        let thumb: String
    }
    let cr: String
    let title: String
    let thumb: String
    let url: String
    var subj: String?
    var color: String?
    var med: String?
    var cat: String?
    var note: String?
    var n: Int?
    var family: String?
    var colourways: [Colourway]?
    var shareable: Bool?
    /// The catalogue page's meta rows (`app/catalogue/[cr]/page.tsx`): Body of Work, Pillar, Medium, Year (Category is `cat`).
    var body: String?
    var pillar: String?
    var medium: String?
    var year: Int?
    var id: String { cr }

    /// The rows the site prints, in its order, only those the record carries.
    var metaRows: [(String, String)] {
        let all: [(String, String?)] = [("Body of Work", body), ("Pillar", pillar), ("Category", cat), ("Medium", medium), ("Year", year.map { String($0) })]
        var out: [(String, String)] = []
        for (l, v) in all { if let v, !v.isEmpty { out.append((l, v)) } }
        return out
    }

    /// The motif family the viewer labels a work with.
    var fam: String {
        let s = subj ?? ""
        func has(_ p: String) -> Bool { s.range(of: p, options: .regularExpression) != nil }
        if has("glyph") { return "Glyph" }; if has("heart") { return "Heart" }
        if has("celtic|knot") { return "Knot" }; if has("figur") { return "Figure" }
        if has("pattern") { return "Pattern" }; if has("text") { return "Text" }
        if has("landscape|cosmic|cityscape") { return "Landscape" }
        return "Organic"
    }

    var haystack: String { [cr, title, subj, color, med, cat, fam].compactMap { $0 }.joined(separator: " ").lowercased() }
    var isSeed: Bool { (cat ?? "").lowercased().contains("seed") }
}

struct LabWork: Codable, Identifiable, Hashable, Sendable {
    let plg: String
    let kind: String
    let joined: String?
    let img: String
    var id: String { plg }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension String {
    var capFirst: String { String(prefix(1)).uppercased() + String(dropFirst()) }
}

enum ArchiveDate {
    /// "Oct 7, 2026" from the site's timestamps (with or without fractional seconds, or a plain date).
    static func text(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        let c = DateFormatter(); c.dateFormat = "yyyy-MM-dd"; c.locale = Locale(identifier: "en_US_POSIX")
        guard let d = a.date(from: iso) ?? b.date(from: iso) ?? c.date(from: String(iso.prefix(10))) else { return nil }
        return d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - The record

@MainActor @Observable final class ArchiveStore {
    static let shared = ArchiveStore()

    var works: [ArchiveWork] = []
    var lab: [LabWork] = []
    var kept: [String: String] = [:]
    var failure: String?
    var loading = false
    var loadedAt: Date?

    /// Third-party marks never show (his hard no; the site's own list, `THIRD_PARTY_CR` in lib/archive-manifest.ts).
    static let blocked: Set<String> = ["PL-0099", "PL-0174", "PL-0122", "PL-0501", "PL-1533", "PL-0332", "PL-0421", "PL-0431", "PL-0172", "PL-0173", "PL-0330",
                                       "PL-0036", "PL-0090", "PL-0211", "PL-0213", "PL-0354", "PL-0358", "PL-0458", "PL-0461"]

    private struct ManifestFile: Decodable { let pieces: [Lossy<ArchiveWork>] }
    private struct KeepsFile: Decodable { struct K: Decodable { let cr: String; let kept: String? }; let keeps: [K] }
    private struct LabFile: Decodable { let entries: [Lossy<LabWork>] }

    private func read(_ url: String, key: String) async -> Data? {
        if let u = URL(string: url), let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)),
           (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true {
            OfflineCache.save(data, for: key); return data
        }
        if let (saved, at) = OfflineCache.load(key) { OfflineState.servedCopy(from: at); return saved }
        return nil
    }

    func load(force: Bool = false) async {
        if !force, let at = loadedAt, !works.isEmpty, Date().timeIntervalSince(at) < 600 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let manifest = read("https://assets.psychedluxuries.com/manifest.json", key: "archive|manifest")
        async let labData = read("https://assets.psychedluxuries.com/plg.json", key: "archive|plg")
        async let keepsFile = try? Site.get("api/archive-keeps", KeepsFile.self)
        let (m, l, k) = await (manifest, labData, keepsFile)
        guard let m else {
            if works.isEmpty { failure = "The archive did not answer. Pull to try again." }
            return
        }
        let parsed: [ArchiveWork] = await Task.detached(priority: .userInitiated) {
            ((try? JSONDecoder().decode(ManifestFile.self, from: m))?.pieces ?? []).compactMap(\.value)
        }.value
        guard !parsed.isEmpty else { if works.isEmpty { failure = "The archive came back empty. Pull to try again." }; return }
        var keeps: [String: String] = [:]
        for x in k?.keeps ?? [] { keeps[x.cr] = x.kept ?? "" }
        kept = keeps
        // his keeps lead (his S308 ruling), the catalogue's order within each; every work stays in All works (his: none hidden), as the site's viewer does
        works = parsed.filter { !Self.blocked.contains($0.cr) }.sorted {
            let a = keeps[$0.cr] != nil, b = keeps[$1.cr] != nil
            return a != b ? a : $0.cr.localizedStandardCompare($1.cr) == .orderedAscending
        }
        if let l, let file = try? JSONDecoder().decode(LabFile.self, from: l) { lab = file.entries.compactMap(\.value) }
        failure = nil
        loadedAt = Date()
    }

    func work(_ cr: String) -> ArchiveWork? { works.first { $0.cr == cr } }
}

/// The favourites (the gold star) and the pieces already spoken for (green): kept on this phone, like the site's.
@MainActor @Observable final class ArchiveMarks {
    static let shared = ArchiveMarks()
    private(set) var fav: Set<String>
    private(set) var voted: Set<String>

    private init() {
        fav = Set(UserDefaults.standard.stringArray(forKey: "pldev.archive.fav") ?? [])
        voted = Set(UserDefaults.standard.stringArray(forKey: "pldev.archive.voted") ?? [])
    }

    func toggleFav(_ cr: String) {
        if fav.contains(cr) { fav.remove(cr) } else { fav.insert(cr) }
        UserDefaults.standard.set(Array(fav), forKey: "pldev.archive.fav")
    }

    func markVoted(_ cr: String) {
        voted.insert(cr)
        UserDefaults.standard.set(Array(voted), forKey: "pldev.archive.voted")
    }
}

// MARK: - The archive tab

struct ArchiveOpen: Hashable, Identifiable {
    let ids: [String]
    let index: Int
    let lab: Bool
    var id: String { ids[index] }
}

struct ArchiveView: View {
    let model: AppModel
    private let store = ArchiveStore.shared
    private let marks = ArchiveMarks.shared
    @State private var query = ""
    @State private var lens = Lens.all
    @State private var open: ArchiveOpen?
    @Environment(\.colorScheme) private var scheme
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]

    enum Lens: String, CaseIterable, Identifiable {
        case all = "All works", heartmark = "HeartMark", lab = "The Lab"
        var id: String { rawValue }
    }

    private var shown: [ArchiveWork] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.works.filter { w in
            if lens == .heartmark && w.family != "HEARTMARK" { return false }
            return q.isEmpty || w.haystack.contains(q)
        }
    }

    private var labView: [LabWork] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.lab.filter { q.isEmpty || "\($0.plg) \($0.kind)".lowercased().contains(q) }
    }

    var body: some View {
        let works = shown
        let lab = labView
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SitePageHead(eyebrow: "The archive \u{2014} since April 2019", lead: "The complete", accent: "works.",
                             lede: "The archive is not the backstory \u{2014} it is the evidence. " + (store.works.isEmpty ? "Every piece" : "\(store.works.count.formatted()) works") + ", documented, from one hand. Search it. Walk it.")
                if let f = featured { featuredCard(f) }
                if query.isEmpty && lens == .all { ArchiveStrips() }   // the catalogue page's strips: Living Curves, the Mirror doors, the Chosen
                if !store.works.isEmpty {
                    Text("\(store.works.count.formatted()) works \u{00B7} \(store.works.map(\.cr).min() ?? "")\u{2026}\(store.works.map(\.cr).max() ?? "")").siteLabel(10)
                        .padding(.horizontal, 24)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Lens.allCases.filter { $0 != .lab || !store.lab.isEmpty }) { l in
                                SiteChip(title: l.rawValue, on: lens == l) { withAnimation(.smooth) { lens = l } }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    SiteRule().padding(.horizontal, 24)
                }
                content(works, lab)
                if query.isEmpty && lens == .all && !store.works.isEmpty { ArchiveClose() }
            }
            .padding(.bottom, 32)
        }
        .siteScreen()
        .searchable(text: $query, prompt: "Search by number, motif, color\u{2026}")
        .refreshable { await store.load(force: true) }
        .task { await store.load() }
        .navigationDestination(item: $open) { o in ArchiveEntryView(ids: o.ids, start: o.index, lab: o.lab) }
        .sensoryFeedback(PLHaptic.select, trigger: lens)
    }

    /// One work at scale before the search, as the site's page does: PL-0627, the Heart mark as a silver chain beside a rose.
    private var featured: ArchiveWork? { store.work("PL-0627") }

    private func featuredCard(_ w: ArchiveWork) -> some View {
        Button { if let i = store.works.firstIndex(of: w) { open = ArchiveOpen(ids: store.works.map(\.cr), index: i, lab: false) } } label: {
            VStack(spacing: 18) {
                Text("From the archive").siteLabel().foregroundStyle(Bone.gold)
                AsyncImage(url: URL(string: w.url)) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 200)
                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(w.title).font(SiteFont.display(24, italic: true)).foregroundStyle(Color(hex: 0xf1ece1))
                    HStack {
                        Text("\(w.cr) \u{00B7} from one hand").siteLabel(10)
                        Spacer()
                        Text("View the work \u{2192}").siteLabel(10).foregroundStyle(Bone.gold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background(Color(hex: 0x0e0c08), in: RoundedRectangle(cornerRadius: Bone.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel("From the archive: \(w.title), \(w.cr). View the work.")
    }

    @ViewBuilder private func content(_ works: [ArchiveWork], _ lab: [LabWork]) -> some View {
        if store.works.isEmpty {
            if let f = store.failure {
                EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the archive", detail: f, actionTitle: "Try again") { Task { await store.load(force: true) } }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<8, id: \.self) { _ in RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Bone.line(scheme).opacity(0.4)).aspectRatio(0.85, contentMode: .fit) }
                }
                .redacted(reason: .placeholder).padding(.horizontal, 24).accessibilityLabel("Loading the archive")
            }
        } else if lens == .lab {
            if lab.isEmpty { EmptyNote(symbol: "magnifyingglass", title: "Nothing in this lens", detail: "No work in The Lab matches that search.") }
            else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(lab.enumerated()), id: \.element.id) { i, e in
                        Button { open = ArchiveOpen(ids: lab.map(\.plg), index: i, lab: true) } label: {
                            Cell(image: e.img, cr: e.plg, title: e.kind.capFirst, note: ArchiveDate.text(e.joined).map { "Joined \($0)" }, fav: false, voted: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        } else if works.isEmpty {
            EmptyNote(symbol: "magnifyingglass", title: "Nothing in this lens", detail: "No work fits that search.", actionTitle: "Clear") { query = ""; lens = .all }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(works.enumerated()), id: \.element.id) { i, w in
                    Button { open = ArchiveOpen(ids: works.map(\.cr), index: i, lab: false) } label: {
                        Cell(image: w.thumb, cr: w.cr, title: w.title, note: store.kept[w.cr].map { "Kept" + (ArchiveDate.text($0.isEmpty ? nil : $0).map { " " + $0 } ?? "") },
                             fav: marks.fav.contains(w.cr), voted: marks.voted.contains(w.cr))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { marks.toggleFav(w.cr) } label: { Label(marks.fav.contains(w.cr) ? "Remove the star" : "Star it", systemImage: marks.fav.contains(w.cr) ? "star.slash" : "star") }
                        if let url = Site.page("catalogue/\(w.cr)") { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
                    }
                }
            }
            .padding(.horizontal, 24)
            Text("\(works.count.formatted()) of \(store.works.count.formatted()) works").siteLabel(10).contentTransition(.numericText()).frame(maxWidth: .infinity).padding(.top, 8)
        }
    }

    /// One cell of the grid: the work in its frame, its number and title, and what the house marked on it.
    struct Cell: View {
        let image: String
        let cr: String
        let title: String
        let note: String?
        let fav: Bool
        let voted: Bool
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: URL(string: image)) { phase in
                            switch phase {
                            case .success(let i): i.resizable().scaledToFit().padding(8)
                            case .failure: Image(systemName: "photo").foregroundStyle(.tertiary)
                            default: Color.clear
                            }
                        }
                    }
                    .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(voted ? Bone.teal : Bone.line(scheme), lineWidth: voted ? 1.2 : 0.6) }
                    .overlay(alignment: .topTrailing) { if fav { Image(systemName: "sparkle").font(.footnote).foregroundStyle(Bone.gold).padding(8) } }
                Text(cr).siteLabel(10)
                Text(title).font(SiteFont.display(16)).foregroundStyle(Bone.ink(scheme)).lineLimit(2).multilineTextAlignment(.leading)
                if let note { Text(note).siteLabel(9).foregroundStyle(Bone.goldDim) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(cr)\(note.map { ", " + $0 } ?? "")\(fav ? ", starred" : "")\(voted ? ", already requested" : "")")
            .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - One work

struct ArchiveEntryView: View {
    let ids: [String]
    @State var index: Int
    let lab: Bool
    private let store = ArchiveStore.shared
    private let marks = ArchiveMarks.shared
    @State private var shownImage: String?
    @Environment(\.colorScheme) private var scheme

    init(ids: [String], start: Int, lab: Bool) { self.ids = ids; self._index = State(initialValue: start); self.lab = lab }

    private var cr: String { ids[index] }
    private var work: ArchiveWork? { lab ? nil : store.work(cr) }
    private var labWork: LabWork? { lab ? store.lab.first { $0.plg == cr } : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let imageURL = shownImage ?? work?.url ?? labWork?.img
                AsyncImage(url: imageURL.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 240)
                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(work?.title ?? labWork?.kind.capFirst ?? "The work")
                .id(imageURL)
                .transition(.opacity)

                VStack(alignment: .leading, spacing: 10) {
                    Text(cr).siteLabel()
                    Text(work?.title ?? labWork?.kind.capFirst ?? "").font(SiteFont.display(32)).foregroundStyle(Bone.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    if let w = work {
                        if let c = ChosenStore.shared.entry(w.cr) {
                            Text("Chosen \u{2014} No. \(c.padded)").font(.system(size: 11, design: .monospaced)).tracking(2).foregroundStyle(Bone.gold)
                                .padding(.horizontal, 8).padding(.vertical, 4).overlay { Capsule().strokeBorder(Bone.gold.opacity(0.3), lineWidth: 0.8) }
                        }
                        Text("\(w.fam)  \u{00B7}  \((w.color ?? "").replacingOccurrences(of: "-", with: " "))  \u{00B7}  \((w.med ?? "").replacingOccurrences(of: "-", with: " "))").siteLabel(10)
                        Text("\((w.cat ?? "").replacingOccurrences(of: "_", with: " ")) \u{00B7} \u{2116}\(w.n ?? 0)").siteLabel(10)
                        if !w.metaRows.isEmpty {
                            SiteRule().padding(.top, 6)
                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 12) {
                                ForEach(w.metaRows, id: \.0) { row in
                                    let (l, v) = row
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l).font(.system(size: 11, design: .monospaced)).textCase(.uppercase).tracking(2).foregroundStyle(Bone.inkFaint(scheme))
                                        Text(v).font(SiteFont.body(14)).foregroundStyle(Bone.ink(scheme))
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        if let k = store.kept[w.cr] { Text("Kept" + (ArchiveDate.text(k.isEmpty ? nil : k).map { " " + $0 } ?? "")).siteLabel(10).foregroundStyle(Bone.goldDim) }
                        Text((w.note ?? "").isEmpty ? "From the continuous practice. April 2019 \u{2014} present." : w.note!).siteBody(15).padding(.top, 4)
                    } else if let l = labWork {
                        Text("The Lab  \u{00B7}  joined \(ArchiveDate.text(l.joined) ?? "")").siteLabel(10)
                        Text("Made from the practice. Out in the world first, then kept here.").siteBody(15).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)

                if let w = work, let cws = w.colourways, !cws.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colourways").siteLabel(10)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                let all = [ArchiveWork.Colourway(cr: w.cr, color: w.color, url: w.url, thumb: w.thumb)] + cws
                                ForEach(all, id: \.cr) { c in
                                    Button { withAnimation(.easeInOut(duration: 0.2)) { shownImage = c.url } } label: {
                                        AsyncImage(url: URL(string: c.thumb)) { p in
                                            if case .success(let i) = p { i.resizable().scaledToFit() } else { Color.clear }
                                        }
                                        .frame(width: 64, height: 64).padding(4)
                                        .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder((shownImage ?? w.url) == c.url ? Bone.gold : Bone.line(scheme), lineWidth: 1) }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Colourway \((c.color ?? c.cr).replacingOccurrences(of: "-", with: " "))")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                if let w = work {
                    RequestBallot(work: w).padding(.horizontal, 24)
                    if SiteAccount.shared.signedIn { ArchivePin(cr: w.cr).padding(.horizontal, 24) }
                }

                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 48, height: 48) }.accessibilityLabel("Previous work")
                    Spacer()
                    Text("\(index + 1) of \(ids.count.formatted())").siteLabel(10).contentTransition(.numericText())
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 48, height: 48) }.accessibilityLabel("Next work")
                }
                .foregroundStyle(Bone.ink(scheme))
                .padding(.horizontal, 24)
                Text("Watch this.").font(SiteFont.display(24, italic: true)).foregroundStyle(Bone.gold).frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12).padding(.bottom, 24)
        }
        .siteScreen()
        .navigationTitle(cr)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if work != nil {
                    Button { marks.toggleFav(cr) } label: { Image(systemName: marks.fav.contains(cr) ? "star.fill" : "star").symbolEffect(.bounce, value: marks.fav.contains(cr)) }
                        .accessibilityLabel(marks.fav.contains(cr) ? "Remove the star" : "Star it")
                    if let url = Site.page("catalogue/\(cr)") { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                }
            }
        }
        // swipe across to step through the section this was opened from, as the site's viewer does
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if abs(v.translation.width) > 90, abs(v.translation.height) < 70, v.startLocation.x > 24 { step(v.translation.width < 0 ? 1 : -1) }
        })
        .sensoryFeedback(PLHaptic.select, trigger: index)
        .sensoryFeedback(PLHaptic.select, trigger: marks.fav.contains(cr))
        .task { await store.load() }
    }

    private func step(_ d: Int) {
        guard ids.count > 1 else { return }
        withAnimation(.snappy) { index = (index + d + ids.count) % ids.count; shownImage = nil }
    }
}

// MARK: - Pin and the request ballot

/// Pins a work to the signed-in account, as the site's pin does.
struct ArchivePin: View {
    let cr: String
    private struct PinState: Decodable { let pinned: Bool? }
    @State private var pinned = false
    @State private var line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                let was = pinned
                pinned.toggle()
                Task {
                    do { _ = try await Site.post("api/account/pins", ["cr": cr, "action": was ? "unpin" : "pin"]); line = nil }
                    catch { pinned = was; line = "Not saved. \(error.localizedDescription)" }
                }
            } label: { Label(pinned ? "Pinned to your page" : "Pin to your page", systemImage: pinned ? "pin.fill" : "pin").symbolEffect(.bounce, value: pinned) }
                .buttonStyle(SiteGhost())
            ResultLine(text: line)
        }
        .task(id: cr) { pinned = (try? await Site.get("api/account/pins", PinState.self, query: ["cr": cr]))?.pinned ?? false }
    }
}

/// `Request this piece`: the catalogue as a ballot. A request is data until the founder crafts; nothing is charged. A member's
/// session is the proof; anyone else gives an email and passes the site's human check, which runs here.
struct RequestBallot: View {
    let work: ArchiveWork
    private let marks = ArchiveMarks.shared
    private let account = SiteAccount.shared
    @State private var open = false
    @State private var cfg: SiteBallot?
    @State private var product: String?
    @State private var email = ""
    @State private var weeks = 1
    @State private var avail = 1
    @State private var spokenFor = false
    @State private var web: WebPage?
    @State private var sending = false
    @State private var message: String?
    @State private var done = false
    @Environment(\.colorScheme) private var scheme

    private var products: [String] { cfg?.products ?? SiteBallot.defaultProducts }
    private var emailOK: Bool { email.range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil }
    private var needsCheck: Bool { !account.signedIn && !(cfg?.siteKey ?? "").isEmpty }
    private var canCast: Bool { !sending && !spokenFor && product != nil && (account.signedIn || emailOK) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if done, let message {
                Text(message).font(SiteFont.display(20, italic: true)).foregroundStyle(Bone.gold)
            } else if !open {
                Button { Task { await show() } } label: { Text("Request this piece") }.buttonStyle(SitePill())
            } else {
                Text("Ask for it as").siteLabel(10)
                FlowChips(items: products.map { $0.replacingOccurrences(of: "_", with: " ") }, selected: product?.replacingOccurrences(of: "_", with: " "),
                          disabled: { work.isSeed && $0 != "sticker" }) { name in product = products.first { $0.replacingOccurrences(of: "_", with: " ") == name } }
                if work.isSeed { Text("Seeds arrive as stickers first.").font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)) }
                if !account.signedIn {
                    SiteField(label: "Your email", text: $email, prompt: "your email", keyboard: .emailAddress, contentType: .emailAddress, capitalize: .never)
                }
                if account.signedIn && avail > 1 {
                    Text("You hold \(avail) weeks of voice. Spend:").siteLabel(10)
                    HStack(spacing: 8) {
                        ForEach(1...avail, id: \.self) { i in SiteChip(title: "\u{00D7}\(i)", on: weeks == i) { weeks = i } }
                    }
                }
                HumanGate(siteKey: account.signedIn ? "" : (cfg?.siteKey ?? ""))
                Button { Task { await cast() } } label: {
                    HStack(spacing: 10) { Text(sending ? "Casting" : needsCheck ? "Continue on the site" : "Cast the request"); if sending { ProgressView().tint(.white) } }
                }
                .buttonStyle(SitePill())
                .disabled(!canCast)
                if let message { Text(message).font(SiteFont.body(14)).foregroundStyle(spokenFor ? Bone.inkSoft(scheme) : Bone.oxblood).lineSpacing(4) }
            }
        }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sensoryFeedback(PLHaptic.commit, trigger: done)
        .onChange(of: email) { _, e in
            guard emailOK, !account.signedIn else { return }
            Task { await check(email: e) }
        }
    }

    private func show() async {
        open = true
        cfg = await SiteBallot.load(cr: work.cr)
        if account.signedIn { apply(cfg) }
    }

    private func check(email: String) async {
        apply(await SiteBallot.load(email: email.trimmingCharacters(in: .whitespaces).lowercased(), cr: work.cr))
    }

    private func apply(_ b: SiteBallot?) {
        guard let b else { return }
        avail = max(1, b.weeksAvailable ?? 1)
        weeks = min(weeks, avail)
        spokenFor = b.votedThisWeek == true
        message = spokenFor ? "You have spoken for this piece this week. Next week, again." : nil
    }

    private func cast() async {
        if needsCheck {   // the human check runs on the site's own page, in Apple's sheet
            UIPasteboard.keep(email.trimmingCharacters(in: .whitespaces).lowercased())
            message = "Your email is copied. The request is cast on the site\u{2019}s page."
            if let url = Site.page("catalogue/\(work.cr.lowercased())") { web = WebPage(url) }
            return
        }
        sending = true; message = nil
        defer { sending = false }
        let body: [String: Any] = ["email": account.signedIn ? (account.me?.email ?? "") : email.trimmingCharacters(in: .whitespaces).lowercased(),
                                   "cr": work.cr, "product": product ?? "", "weeks": weeks]
        do {
            let r = try await Site.call("POST", "api/request", body: body)
            let said = r.message ?? "Something interrupted it. Try again."
            if r.ok { done = true; message = said; marks.markVoted(work.cr) }
            else { message = said }
        } catch { message = error.localizedDescription }
    }
}

/// Option chips that wrap onto as many lines as they need.
struct FlowChips: View {
    let items: [String]
    let selected: String?
    var disabled: (String) -> Bool = { _ in false }
    let pick: (String) -> Void

    var body: some View {
        ShopFlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { i in
                SiteChip(title: i, on: selected == i, dim: disabled(i)) { if !disabled(i) { pick(i) } }
                    .accessibilityHint(disabled(i) ? "Not available for a seed" : "")
            }
        }
    }
}

struct ShopFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}
