import AVKit
import SwiftUI
import TipKit
import UserNotifications

/// Curate: one card at a time; right = keep, left = cut, up = maybe, star = favourite (a keep with the note "fav").
/// The deck order comes from PLDevCore's CurateQueue (the web's rules). Marks go to the gallery's /api/taste, the same store
/// the web deck, the Library and the R1 write. A failed marks load deals no deck; a failed save is counted on screen.
@MainActor enum CurateSection: PLSection {
    static let manifest = SectionManifest(id: "curate", title: "Curate", symbol: "rectangle.stack", needsKeys: ["vault"], needsOrigins: ["gallery"])
    static let state = CurateModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(CurateView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let d = path.first.flatMap(CurateDeck.init(rawValue:)) { state.deck = d }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

@MainActor @Observable final class CurateModel {
    struct Done { let item: LibraryItem; let dir: String; let prev: TasteMark? }

    var deck: CurateDeck = .everything
    var cls: String? = nil
    var queue: [LibraryItem] = []
    var index = 0
    var marks: [String: TasteMark] {   // one store: a mark here shows in the Library at once
        get { LibraryData.shared.marks }
        set { LibraryData.shared.marks = newValue }
    }
    var loading = false
    var loadFailed = false
    var notSaved = 0
    var kept = 0
    var history: [Done] = []
    var comment = ""
    var tick = 0
    var undoTick = 0
    private var allItems: [LibraryItem] = []
    private var seeds: [LibraryItem] = []   // /seed-index.json, loaded when the Seeds class is picked (as the web deck does)

    var current: LibraryItem? { index < queue.count ? queue[index] : nil }

    func load(model: AppModel, force: Bool = false) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            try await LibraryData.shared.load(model: model, force: force)
            allItems = LibraryData.shared.items
            loadFailed = false
            deal()
        } catch {
            loadFailed = true; queue = []   // never deal a deck over marks that did not load
        }
    }

    /// The seed phrases (3,346): their own index, read once.
    func loadSeeds(model: AppModel) async {
        guard seeds.isEmpty, let http = model.http else { return }
        struct Index: Decodable { let items: [LibraryItem] }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "seed-index.json"), timeout: 60),
           let i = try? JSONDecoder().decode(Index.self, from: d) { seeds = i.items }
        deal()
    }

    func deal() {
        let items = cls == "seed" ? seeds : allItems, marks = self.marks, deck = self.deck, cls = self.cls
        queue = CurateQueue.build(deck, items: items, marks: marks, cls: cls)
        index = 0; history = []; kept = 0
        comment = current?.vaultComment(marks) ?? ""
    }

    private func post(_ body: [String: String], model: AppModel) async {
        _ = await LibraryData.shared.post(body, model: model)
        notSaved = LibraryData.shared.notSaved
    }

    func saveComment(model: AppModel) async {
        guard let it = current else { return }
        let t = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != (marks[it.vault_id]?.comment ?? "") else { return }
        marks[it.vault_id, default: TasteMark(v: "")].comment = t
        await post(["only": "comment", "id": it.vault_id, "comment": String(t.prefix(1000))], model: model)
    }

    /// keep / cut / maybe / fav. In the favs deck a keep posts nothing (it already is one).
    func commit(_ dir: String, model: AppModel) async {
        guard let it = current else { return }
        await saveComment(model: model)
        let prev = marks[it.vault_id]
        if dir == "fav" {
            await post(["id": it.vault_id, "v": "keep", "note": "fav"], model: model)
            marks[it.vault_id] = TasteMark(v: "keep", note: "fav", comment: prev?.comment)
        } else if dir == "keep", prev?.v == "keep", [.repass, .cloud, .api, .all, .unseen].contains(deck) {
            // re-pass rule: a keep on a keep (or favourite) leaves it as it was; the post only stamps the time so it leaves the re-pass
            await post(["id": it.vault_id, "v": "keep"].merging(prev?.note.map { ["note": $0] } ?? [:]) { a, _ in a }, model: model)
            marks[it.vault_id] = TasteMark(v: "keep", note: prev?.note, comment: prev?.comment)
        } else if !(deck == .favs && dir == "keep") {
            var body = ["id": it.vault_id, "v": dir]
            if deck == .maybes, let n = prev?.note, !n.isEmpty, dir == "maybe" { body["note"] = n }
            await post(body, model: model)
            marks[it.vault_id] = TasteMark(v: dir, comment: prev?.comment)
        }
        if dir == "keep" || dir == "fav" { kept += 1 }
        history.append(Done(item: it, dir: dir, prev: prev))
        tick += 1
        index += 1
        comment = current?.vaultComment(marks) ?? ""
    }

    func undo(model: AppModel) async {
        guard let last = history.popLast() else { return }
        // one rule for every deck: put back the mark the card had before (with its note), or clear it if it had none
        if let p = last.prev, !p.v.isEmpty {
            await post(["id": last.item.vault_id, "v": p.v].merging(p.note.map { ["note": $0] } ?? [:]) { a, _ in a }, model: model)
        } else {
            await post(["id": last.item.vault_id, "v": "clear"], model: model)
        }
        marks[last.item.vault_id] = last.prev
        if last.dir == "keep" || last.dir == "fav" { kept = max(0, kept - 1) }
        index = max(0, index - 1)
        undoTick += 1
        comment = current?.vaultComment(marks) ?? ""
    }

    func media(_ it: LibraryItem, model: AppModel) -> (still: URL?, video: URL?) { LibraryData.shared.media(it, model: model) }
}

private extension LibraryItem {
    func vaultComment(_ marks: [String: TasteMark]) -> String {
        let c = marks[vault_id]?.comment ?? ""
        return c.range(of: #"^(regenerated from your favourites|replaced by)"#, options: .regularExpression) != nil ? "" : c
    }
}

/// A muted clip that loops, through the system player.
struct LoopingClip: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVQueuePlayer(); p.isMuted = true
                looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
                player = p; p.play()
            }
            .onDisappear { player?.pause(); player = nil; looper = nil }
    }
}

struct CurateView: View {
    let model: AppModel
    @Bindable var state: CurateModel
    @State private var drag: CGSize = .zero
    @FocusState private var commentFocus: Bool
    private let threshold: CGFloat = 110
    private let classes: [(String?, String)] = [(nil, "Everything"), ("still", "Stills"), ("cinematic", "Shorts"), ("code-piece", "Code"), ("font", "Fonts"), ("essay", "Essays"), ("seed", "Seeds"), ("archive-work", "Archive")]

    var body: some View {
        VStack(spacing: 12) {
            header
            if state.loadFailed {
                ContentUnavailableView("YOUR MARKS DID NOT LOAD", systemImage: "exclamationmark.triangle",
                                       description: Text("No deck is dealt over marks that did not load. Pull to try again."))
            } else if state.loading && state.queue.isEmpty {
                ProgressView("Loading the library…").frame(maxHeight: .infinity)
            } else if let it = state.current {
                TipView(CurateSwipeTip())
                TextField("A word about this piece", text: $state.comment, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder).focused($commentFocus)
                    .onChange(of: commentFocus) { _, f in if !f { Task { await state.saveComment(model: model) } } }
                card(it).frame(maxHeight: .infinity)
                VStack(spacing: 2) {
                    Text(it.name ?? it.vault_id).font(.title3.weight(.semibold)).italic().lineLimit(1)
                    if let sub = it.sub, !sub.isEmpty { Text(sub.uppercased()).font(.caption2).tracking(1).foregroundStyle(.secondary).lineLimit(1) }
                }
                keys
            } else {
                ContentUnavailableView("Queue clear", systemImage: "checkmark.circle", description: Text("Pick another deck above."))
            }
        }
        .padding(.horizontal, PLSpace.margin)
        .navigationTitle("Curate").navigationBarTitleDisplayMode(.inline)
        .task { if state.queue.isEmpty { await state.load(model: model) } }
        .refreshable { await state.load(model: model, force: true) }
        .sensoryFeedback(.impact(weight: .heavy), trigger: state.tick)
        .sensoryFeedback(.impact(weight: .light), trigger: state.undoTick)
        .focusable()
        .onKeyPress { press in   // the R1 Remote types these, as on the web deck
            guard !commentFocus else { return .ignored }
            switch press.characters.lowercased() {
            case "k": act("keep")
            case "c": act("cut")
            case "m": act("maybe")
            case "f": act("fav")
            case "z": Task { await state.undo(model: model) }
            default: return .ignored
            }
            return .handled
        }
    }

    private func act(_ dir: String) { Task { await state.commit(dir, model: model) }; drag = .zero }

    private var header: some View {
        HStack {
            Menu {
                Picker("Deck", selection: Binding(get: { state.deck }, set: { state.deck = $0; state.deal() })) {
                    ForEach(CurateDeck.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Class", selection: Binding(get: { state.cls }, set: { state.cls = $0; state.deal(); if $0 == "seed" { Task { await state.loadSeeds(model: model) } } })) {
                    ForEach(classes, id: \.1) { Text($0.1).tag($0.0) }
                }
            } label: { Label(state.deck.title, systemImage: "line.3.horizontal.decrease.circle") }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("#\(min(state.index + 1, state.queue.count)) of \(state.queue.count) · \(max(0, state.queue.count - state.index)) left · \(state.kept) kept")
                    .font(.caption.monospacedDigit())
                if state.notSaved > 0 { Text("\(state.notSaved) NOT SAVED").font(.caption.bold()).foregroundStyle(.red) }
            }
        }
    }

    private func stamp(_ text: String, _ color: Color, _ amount: CGFloat) -> some View {
        Text(text).font(.system(size: 34, weight: .heavy)).foregroundStyle(color)
            .padding(.horizontal, 10).overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .opacity(Double(min(1, max(0, amount / threshold))))
    }

    private func card(_ it: LibraryItem) -> some View {
        let m = state.media(it, model: model)
        return ZStack {
            RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous).fill(Color.secondary.opacity(0.12))
            if let v = m.video {
                LoopingClip(url: v).id(v)
            } else if let s = m.still {
                AsyncImage(url: s) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
            } else if it.class == "essay", let src = it.src, let url = URL(string: LibraryData.shared.base(model) + src) {
                EssayCard(url: url)
            } else if it.class == "seed" {
                SeedCard(phrase: it.name ?? "")
            } else {
                Text(it.name ?? it.vault_id).font(.title3).padding()
            }
            VStack {
                HStack {
                    stamp("KEEP", .green, drag.width).rotationEffect(.degrees(-8))
                    Spacer()
                    stamp("CUT", .red, -drag.width).rotationEffect(.degrees(8))
                }
                stamp("MAYBE", .yellow, -drag.height)
                Spacer()
            }.padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
        .offset(drag)
        .rotationEffect(.degrees(Double(drag.width / 18)))
        .gesture(DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { g in
                let t = g.translation
                if t.width > threshold { act("keep") }
                else if t.width < -threshold { act("cut") }
                else if t.height < -threshold { act("maybe") }
                else { withAnimation(.spring(duration: 0.3)) { drag = .zero } }
            })
        .animation(.interactiveSpring, value: drag)
        .id(it.vault_id)
    }

    /// His five keycaps, in the web deck's order (cut, maybe, keep, fav, undo), each pressing down under the finger.
    private var keys: some View {
        HStack(spacing: 8) {
            KeyCap(model: model, name: "cut", label: "Cut") { act("cut") }
            KeyCap(model: model, name: "maybe", label: "Maybe") { act("maybe") }
            KeyCap(model: model, name: "keep", label: "Keep") { act("keep") }
            KeyCap(model: model, name: "fav", label: "Favourite") { act("fav") }
            KeyCap(model: model, name: "undo", label: "Undo") { Task { await state.undo(model: model) } }
                .disabled(state.history.isEmpty).opacity(state.history.isEmpty ? 0.5 : 1)
        }
        .padding(.bottom, 8)
    }
}

/// One of his keycap pictures (gallery /remote/cap-<name>-up|down-t3.png): up at rest, down while pressed.
struct KeyCap: View {
    let model: AppModel
    let name: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(CapStyle(base: LibraryData.shared.base(model), name: name))
            .accessibilityLabel(label)
    }
    struct CapStyle: ButtonStyle {
        let base: String
        let name: String
        func makeBody(configuration: Configuration) -> some View {
            AsyncImage(url: URL(string: "\(base)/remote/cap-\(name)-\(configuration.isPressed ? "down" : "up")-t3.png")) { $0.resizable().scaledToFit() }
                placeholder: { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.2)) }
                .frame(maxWidth: .infinity).frame(height: 64)
                .contentShape(Rectangle())
        }
    }
}

/// An essay card: its full text, scrolling inside the card (web: EssayCard).
struct EssayCard: View {
    let url: URL
    @State private var text: String?
    var body: some View {
        ScrollView { Text(text ?? "Loading…").font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
            .task(id: url) {
                if let (d, _) = try? await URLSession.shared.data(from: url) { text = String(decoding: d, as: UTF8.self) } else { text = "Could not load this essay." }
            }
    }
}

/// A seed phrase as the web deck draws it: his hand, upper-cased, on the house ground (the font from the Design Kit).
struct SeedCard: View {
    let phrase: String
    @State private var kit = HouseKit.shared
    var body: some View {
        ZStack {
            kit.palette.groundColor
            Text(phrase.uppercased())
                .font(kit.titleFont.map { Font.custom($0, size: 34, relativeTo: .title) } ?? .system(.title, design: .serif))
                .foregroundStyle(kit.palette.textColor)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .padding(28)
        }
        .accessibilityLabel(phrase)
    }
}
