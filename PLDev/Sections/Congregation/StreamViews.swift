import SwiftUI

// The congregation's public stream: declarations, archive pieces, generated curves, drops and the Three Truths, woven together.
// It is public and read-only until he signs in; reacting and answering need the site's account. The Archive in the Shop uses the
// same model with kind "archive". A drop's picture is shown only when it is one of the site's transparent flats.

struct StreamComment: Decodable, Hashable, Identifiable {
    let id: String
    let handle: String?
    let glyph: String?
    let body: String
    let createdAt: String?
}

struct StreamItem: Decodable, Hashable, Identifiable {
    let kind: String
    let id: String
    var text: String?
    var author: String?
    var createdAt: String?
    var cr: String?
    var image: String?
    var thumb: String?
    var title: String?
    var pillar: String?
    var body: String?
    var slug: String?
    var name: String?
    var price: Int?
    var argument: String?
    var numeral: String?
    var truth: String?
    var gloss: String?
    var axiom: String?
    var year: Int?
    var tier: String?
    var w: Int?
    var h: Int?
    var reactions: Int
    var reacted: Bool
    var comments: [StreamComment]

    private enum K: String, CodingKey {
        case kind, id, text, author, createdAt, cr, image, thumb, title, pillar, body, slug, name, price, argument, numeral, truth, gloss, axiom, year, tier, w, h, reactions, reacted, comments
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        kind = try c.decode(String.self, forKey: .kind)
        id = try c.decode(String.self, forKey: .id)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        author = try? c.decodeIfPresent(String.self, forKey: .author)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        cr = try? c.decodeIfPresent(String.self, forKey: .cr)
        image = try? c.decodeIfPresent(String.self, forKey: .image)
        thumb = try? c.decodeIfPresent(String.self, forKey: .thumb)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        pillar = try? c.decodeIfPresent(String.self, forKey: .pillar)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        slug = try? c.decodeIfPresent(String.self, forKey: .slug)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        price = try? c.decodeIfPresent(Int.self, forKey: .price)
        argument = try? c.decodeIfPresent(String.self, forKey: .argument)
        numeral = try? c.decodeIfPresent(String.self, forKey: .numeral)
        truth = try? c.decodeIfPresent(String.self, forKey: .truth)
        gloss = try? c.decodeIfPresent(String.self, forKey: .gloss)
        axiom = try? c.decodeIfPresent(String.self, forKey: .axiom)
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        tier = try? c.decodeIfPresent(String.self, forKey: .tier)
        w = try? c.decodeIfPresent(Int.self, forKey: .w)
        h = try? c.decodeIfPresent(Int.self, forKey: .h)
        reactions = (try? c.decodeIfPresent(Int.self, forKey: .reactions)) ?? 0
        reacted = (try? c.decodeIfPresent(Bool.self, forKey: .reacted)) ?? false
        comments = (try? c.decodeIfPresent([StreamComment].self, forKey: .comments)) ?? []
    }

    /// The picture to draw. A drop's picture counts only when it is a transparent flat; the rest are the archive's own art.
    var picture: URL? {
        let raw = kind == "archive" ? (thumb ?? image) : image
        guard let raw else { return nil }
        if kind == "drop", !ShopCatalogue.isFlat(raw) { return nil }
        return URL(string: raw)
    }

    var headline: String {
        switch kind {
        case "archive": return title ?? cr ?? "Archive piece"
        case "drop": return name ?? "A piece"
        case "doctrine": return truth ?? ""
        case "declaration": return text ?? ""
        default: return "A curve"
        }
    }
}

@MainActor @Observable final class StreamModel {
    let kind: String?
    var items: [StreamItem] = []
    var total = 0
    var cursor: Int? = 0
    var loading = false
    var failure: String?
    var line: String?
    var tick = 0

    init(kind: String?) { self.kind = kind }

    private struct Page: Decodable { let items: [StreamItem]; let nextCursor: Int?; let total: Int? }

    private func fetch(_ cursor: Int) async throws -> Page {
        var q = ["cursor": String(cursor), "limit": "24"]
        if let kind { q["kind"] = kind }
        return try await Site.get("api/congregation/stream", Page.self, query: q)
    }

    /// The first page again, replacing what is there only once it arrives.
    func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await fetch(0)
            items = p.items; cursor = p.nextCursor; total = p.total ?? total; failure = nil
        } catch { if items.isEmpty { failure = error.localizedDescription } }
    }

    func more() async {
        guard !loading, let c = cursor else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await fetch(c)
            let have = Set(items.map(\.id))
            items += p.items.filter { !have.contains($0.id) }
            cursor = p.nextCursor; total = p.total ?? total; failure = nil
        } catch { if items.isEmpty { failure = error.localizedDescription } }
    }

    func item(_ id: String) -> StreamItem? { items.first { $0.id == id } }

    /// Optimistic: the heart changes at once and comes back if the site refuses.
    func react(_ id: String) async {
        guard SiteAccount.shared.signedIn else { line = "Not saved. Sign in from the Congregation first."; return }
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let before = items[i]
        items[i].reacted.toggle()
        items[i].reactions = max(0, items[i].reactions + (items[i].reacted ? 1 : -1))
        do {
            let r = try await Site.post("api/congregation/stream/react", ["itemId": id])
            if let j = items.firstIndex(where: { $0.id == id }), let o = r.json, let n = o["count"] as? Int, let b = o["reacted"] as? Bool {
                items[j].reacted = b; items[j].reactions = n
            }
            tick += 1; line = nil
        } catch {
            if let j = items.firstIndex(where: { $0.id == id }) { items[j] = before }
            line = "Not saved. \(error.localizedDescription)"
        }
    }

    /// His word on a stream answer: it leaves the stream. Optimistic, restored if the site refuses.
    func removeComment(_ itemID: String, _ commentID: String) async {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        let before = items[i].comments
        items[i].comments.removeAll { $0.id == commentID }
        do {
            try await Site.post("api/congregation/stream/comment/moderate", ["commentId": commentID, "action": "remove"])
            tick += 1; line = nil
        } catch {
            if let j = items.firstIndex(where: { $0.id == itemID }) { items[j].comments = before }
            line = "Not saved. \(error.localizedDescription)"
        }
    }

    /// Nil on success, else the site's sentence.
    func comment(_ id: String, _ text: String) async -> String? {
        guard SiteAccount.shared.signedIn else { return "Sign in from the Congregation first." }
        do {
            let r = try await Site.post("api/congregation/stream/comment", ["itemId": id, "body": text])
            if let c = r.json?["comment"] as? [String: Any], let cid = c["id"] as? String, let i = items.firstIndex(where: { $0.id == id }) {
                items[i].comments.append(StreamComment(id: cid, handle: c["handle"] as? String, glyph: c["glyph"] as? String, body: (c["body"] as? String) ?? text, createdAt: c["createdAt"] as? String))
            }
            tick += 1
            return nil
        } catch { return error.localizedDescription }
    }
}

// MARK: - The stream tab

struct StreamTabView: View {
    @Bindable var stream: StreamModel
    @Bindable var state: CongregationModel
    @State private var viewIndex = 0
    @State private var lightbox: LightboxItem?
    @State private var web: WebPage?
    @State private var desire = false
    @State private var archiveCount: Int?
    @Environment(\.colorScheme) private var scheme
    private let account = SiteAccount.shared

    private var tiles: [StreamItem] { stream.items.filter { $0.kind != "declaration" && $0.kind != "doctrine" && $0.picture != nil } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SitePageHead(eyebrow: "The congregation \u{2014} the room and the signal", lead: "The", accent: "congregation.",
                                 lede: "Two acts, one room. Receive the work as it happens, direct from inside the build. Speak your desire into the wall, where it is held and witnessed. Both are the practice.")
                    profileHeader.padding(.horizontal, 20)
                    if account.signedIn { DeclareIntentCard().padding(.horizontal, 20) }
                    SiteSegment(titles: ["The stream", "The grid"], index: $viewIndex).padding(.horizontal, 20)
                    if let l = stream.line { SiteNote(text: l).padding(.horizontal, 24) }
                    if stream.items.isEmpty {
                        if let f = stream.failure {
                            SiteEmpty(title: "Could not load the stream", detail: f, actionTitle: "Try again") { Task { await stream.reload() } }
                        } else { ForEach(0..<3, id: \.self) { _ in SkeletonRow().siteCard().padding(.horizontal, 20) } }
                    } else if viewIndex == 1 {
                        Masonry(items: tiles, columns: 2, spacing: 4) { item in
                            Button {
                                withAnimation(.snappy) { viewIndex = 0 }
                                Task { try? await Task.sleep(for: .milliseconds(160)); withAnimation(.snappy) { proxy.scrollTo(item.id, anchor: .top) } }
                            } label: {
                                AsyncImage(url: item.picture) { p in
                                    if case .success(let i) = p { i.resizable().scaledToFit() } else { Bone.line(scheme).opacity(0.3).frame(height: 140) }
                                }
                                .frame(maxWidth: .infinity).overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
                            }
                            .buttonStyle(.plain).accessibilityLabel("Open \(item.headline)")
                            .onAppear { if item.id == tiles.last?.id { Task { await stream.more() } } }
                        }
                        .padding(.horizontal, 20)
                    } else {
                        ForEach(stream.items) { item in
                            StreamCardView(item: item, stream: stream, onAuth: { state.tab = .me }, onMember: { state.memberHandle = $0 },
                                           onLightbox: { lightbox = $0 }, onWeb: { web = WebPage($0) })
                                .id(item.id).padding(.horizontal, 20)
                                .onAppear { if item.id == stream.items.last?.id { Task { await stream.more() } } }
                        }
                    }
                    if stream.loading && !stream.items.isEmpty { SitePulse() }
                    if stream.cursor == nil, !stream.items.isEmpty { Text("Watch this.").plHand(26).foregroundStyle(Bone.gold).frame(maxWidth: .infinity).padding(.vertical, 16) }
                    else if !stream.items.isEmpty, stream.total > 0 { Text("\(stream.items.count) of \(stream.total)").siteLabel(10).frame(maxWidth: .infinity) }
                }
                .padding(.bottom, 32)
            }
        }
        .siteScreen()
        .refreshable { await stream.reload() }
        .task { if stream.items.isEmpty { await stream.reload() }; await loadCount() }
        .sensoryFeedback(PLHaptic.commit, trigger: stream.tick)
        .fullScreenCover(item: $lightbox) { Lightbox(item: $0) }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $desire) { DesireSheet() }
    }

    /// `@psychedluxuries`, the house's own identity at the head of the stream, as the site draws it.
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                AvatarMark(size: 76, founder: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("@psychedluxuries").font(SiteFont.display(24)).foregroundStyle(Bone.ink(scheme))
                    Text("Since April 2019 \u{00B7} Decide \u{2192} Persist \u{2192} Obtain").siteLabel(10)
                }
            }
            HStack(alignment: .top, spacing: 32) {
                stat(archiveCount.map { $0.formatted() } ?? "\u{2014}", "archive")
                stat("7 yr", "unbroken")
                stat("90%", "curve-governed")
            }
            Text("A philosophy-first wearable art practice. The archive is not the backstory \u{2014} it is the evidence.").siteBody(14)
            VStack(spacing: 10) {
                Button { desire = true } label: { Text("State your reality \u{2192}") }.buttonStyle(SitePill())
                Button { AppModel.shared.open(.section(id: "shop", path: ["signal"], query: [:])) } label: { Text("Receive the signal") }.buttonStyle(SiteGhost())
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { SiteRule().offset(y: 14) }
        .padding(.bottom, 14)
    }

    private func stat(_ n: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(SiteFont.display(21)).foregroundStyle(Bone.ink(scheme)).monospacedDigit()
            Text(l).siteLabel(10)
        }
    }

    private func loadCount() async {
        if archiveCount == nil, let p = try? await Site.get("api/congregation/stream", StreamProbe.self, query: ["kind": "archive", "limit": "1"]) { archiveCount = p.total }
    }
}

/// One card of the stream, drawn the way the site draws it: the cream card, a round mark and the line above the text.
struct StreamCardView: View {
    let item: StreamItem
    let stream: StreamModel
    var onAuth: () -> Void
    var onMember: (String) -> Void
    var onLightbox: (LightboxItem) -> Void
    var onWeb: (URL) -> Void
    @Environment(\.colorScheme) private var scheme

    private func meta(_ left: String, _ right: String? = nil) -> some View {
        HStack(spacing: 10) {
            AvatarMark(size: 36, founder: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(left).font(SiteFont.body(11, relativeTo: .caption)).textCase(.uppercase).tracking(2.2).foregroundStyle(Bone.goldDim).lineLimit(1)
                if let right { Text(right).siteLabel(10) }
            }
            Spacer(minLength: 0)
        }
    }

    private func dateLabel(_ s: String?) -> String? {
        guard let d = Date.pl(s) else { return nil }
        return d.formatted(.dateTime.month(.wide).day())
    }

    var body: some View {
        if item.kind == "doctrine" {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.numeral ?? "").plHand(38).foregroundStyle(Bone.gold)
                Text(item.truth ?? "").font(SiteFont.display(24, italic: true)).foregroundStyle(Bone.gold).lineSpacing(4)
                Text(item.gloss ?? "").font(SiteFont.body(14)).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.55)).lineSpacing(5)
            }
            .padding(.horizontal, 26).padding(.vertical, 30).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0e0c08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Bone.gold.opacity(0.25), lineWidth: 0.8) }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                switch item.kind {
                case "archive":
                    meta(item.pillar ?? "The Archive", item.cr)
                    picture(fullFirst: true, caption: "\(item.title ?? "")\(item.year.map { " \u{00B7} \($0)" } ?? "")")
                    Text(item.title ?? item.cr ?? "Archive piece").font(SiteFont.display(19)).foregroundStyle(Bone.ink(scheme))
                    if let b = item.body, !b.isEmpty { Text(b).siteBody(14).lineLimit(3) }
                    SiteAction(title: "View in the archive \u{2192}") { AppModel.shared.open(.section(id: "shop", path: ["archive"], query: [:])) }
                case "generated":
                    meta("Generated \u{00B7} The Seals", item.tier == "featured" ? "Featured" : nil)
                    picture(fullFirst: false, caption: "A generated chrome seal")
                    Text("Each phrase\u{2019}s glyph, extruded in gold \u{2014} the mark made into a seal.").siteBody(14)
                case "drop":
                    meta(item.axiom ?? "In the shop", item.price.map(Money.text))
                    Color.clear.frame(height: 240).overlay { FlatImage(url: item.picture, padding: 8) }
                        .background(Bone.raised(scheme).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                    Text(item.name ?? "A piece").font(SiteFont.display(19)).foregroundStyle(Bone.ink(scheme))
                    if let a = item.argument { Text(a).siteBody(14) }
                    if let s = item.slug {
                        SiteAction(title: "Wear the argument \u{2192}") { AppModel.shared.open(.section(id: "shop", path: ["piece", s], query: [:])) }
                    }
                case "declaration":
                    meta("A declaration \u{00B7} the wall", dateLabel(item.createdAt))
                    Text("\u{201C}\(item.text ?? "")\u{201D}").font(SiteFont.display(21, italic: true)).foregroundStyle(Bone.ink(scheme)).lineSpacing(5)
                    Text("\u{2014} \(item.author ?? "Anonymous")").siteLabel(11)
                default:
                    meta("The stream")
                    picture(fullFirst: false, caption: "")
                }
                if item.kind != "doctrine" { StreamActions(item: item, stream: stream, onAuth: onAuth, onMember: onMember) }
            }
            .siteCard(padding: 16, radius: 16)
        }
    }

    @ViewBuilder private func picture(fullFirst: Bool, caption: String) -> some View {
        if let thumb = item.picture {
            Button {
                let big = fullFirst ? (item.image.flatMap(URL.init(string:)) ?? thumb) : thumb
                onLightbox(LightboxItem(src: big, caption: caption))
            } label: {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFit().frame(maxWidth: .infinity)
                    case .failure: Bone.line(scheme).opacity(0.4).frame(height: 160).overlay { Image(systemName: "photo").foregroundStyle(Bone.inkFaint(scheme)) }
                    default: Bone.line(scheme).opacity(0.3).frame(height: 200).overlay { PLLoader() }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
            }
            .buttonStyle(.plain).accessibilityLabel(item.headline.isEmpty ? "Open the picture" : "Open \(item.headline)")
        }
    }
}

/// React, answer, share and save under a stream card, with the answers opening under them (the site's `Interactions`).
struct StreamActions: View {
    let item: StreamItem
    let stream: StreamModel
    var onAuth: () -> Void
    var onMember: (String) -> Void
    @State private var open = false
    @State private var draft = ""
    @State private var sending = false
    @State private var line: String?
    @State private var removing: StreamComment?
    @Environment(\.colorScheme) private var scheme
    private let account = SiteAccount.shared

    private var live: StreamItem { stream.item(item.id) ?? item }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteRule()
            HStack(spacing: 8) {
                SocialPill(label: live.reactions > 0 ? "\(live.reactions)" : "React", on: live.reacted, action: {
                    if account.signedIn { Task { await stream.react(item.id) } } else { onAuth() }
                }) {
                    GlyphMark(glyph: account.me?.glyph ?? "smiley", color: live.reacted ? Bone.gold : Bone.inkFaint(scheme), size: 15)
                }
                .accessibilityLabel(live.reacted ? "Reacted, \(live.reactions)" : "React, \(live.reactions)")
                SocialPill(label: live.comments.isEmpty ? "Answer" : "\(live.comments.count)", on: open, action: { withAnimation(.snappy) { open.toggle() } }) {
                    Image(systemName: "bubble.left").font(.system(size: 13))
                }
                if let url = Site.page("congregation#\(item.id)") {
                    ShareLink(item: url) { HStack(spacing: 6) { Image(systemName: "arrow.up.right").font(.system(size: 12)); Text("Share") }.sitePillLook(scheme: scheme) }
                }
                Spacer(minLength: 0)
                if ["archive", "generated", "drop"].contains(item.kind), let m = item.image ?? item.thumb { SaveButton(refType: item.kind, refId: item.id, mediaURL: m) }
            }
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(live.comments) { c in
                        HStack(alignment: .top, spacing: 10) {
                            GlyphMark(glyph: c.glyph ?? "smiley", color: Bone.gold, size: 16).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.body).font(SiteFont.body(14)).foregroundStyle(Bone.ink(scheme)).lineSpacing(4)
                                if let h = c.handle { Button { onMember(h) } label: { Text("@\(h)").siteLabel(10) }.buttonStyle(.plain) }
                                else { Text("A member").siteLabel(10) }
                            }
                            Spacer(minLength: 0)
                            if account.isFounder { SiteAction(title: "\u{2715} remove", tone: .faint) { removing = c } }
                        }
                    }
                    if account.signedIn {
                        TextField("Answer the room\u{2026}", text: $draft, axis: .vertical).lineLimit(2...5).siteField()
                        HStack {
                            SiteNote(text: line)
                            Spacer()
                            SiteAction(title: sending ? "\u{2026}" : "Speak") {
                                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines); sending = true
                                Task {
                                    if let err = await stream.comment(item.id, t) { line = "Not sent. \(err)" } else { draft = ""; line = nil }
                                    sending = false
                                }
                            }
                            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        }
                    } else {
                        SiteAction(title: "Enter to answer the room \u{2192}", tone: .faint) { onAuth() }
                    }
                }
                .transition(.opacity)
            }
        }
        .confirmationDialog("Remove this answer?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove it", role: .destructive) { if let c = removing { Task { await stream.removeComment(item.id, c.id) } } }
        } message: { Text("It leaves the stream for everyone.") }
    }
}

/// One stream item in full, with its answers and a box to add one.
struct StreamDetailView: View {
    let stream: StreamModel
    let itemID: String
    @State private var draft = ""
    @State private var line: String?
    @State private var sending = false
    @State private var web: WebPage?

    var body: some View {
        if let item = stream.item(itemID) {
            List {
                Section {
                    switch item.kind {
                    case "archive", "generated":
                        if let raw = item.kind == "archive" ? (item.image ?? item.thumb) : item.image, let url = URL(string: raw) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let i): i.resizable().scaledToFit()
                                case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 160)
                                default: PLLoader().frame(maxWidth: .infinity, minHeight: 160)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                            .listRowInsets(EdgeInsets())
                        }
                        if item.kind == "archive" {
                            Text(item.title ?? item.cr ?? "").font(SiteFont.display(26))
                            LabeledContent("Reference", value: item.cr ?? "")
                            if let p = item.pillar { LabeledContent("Pillar", value: p) }
                        }
                    case "drop":
                        FlatImage(url: item.picture, padding: PLSpace.roomy).frame(height: 260).listRowInsets(EdgeInsets())
                        Text(item.name ?? "").font(SiteFont.display(26))
                        if let a = item.argument { Text(a).plFont(.callout).foregroundStyle(.secondary) }
                        if let s = item.slug {
                            Button { AppModel.shared.open(.section(id: "shop", path: ["piece", s], query: [:])) } label: { Label("Open the piece", systemImage: "bag") }
                        }
                    case "doctrine":
                        Text(item.numeral ?? "").plFont(.footnote, emphasized: true).foregroundStyle(Bone.gold)
                        Text(item.truth ?? "").font(SiteFont.display(26))
                        Text(item.gloss ?? "").plReading()
                    default:
                        Text(item.text ?? "").plReading()
                        Text(item.author ?? "").plFont(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { Task { await stream.react(item.id) } } label: {
                            Label("\(item.reactions)", systemImage: item.reacted ? "heart.fill" : "heart").monospacedDigit().contentTransition(.numericText()).symbolEffect(.bounce, value: item.reacted)
                        }
                        .buttonStyle(.plain).foregroundStyle(item.reacted ? Bone.gold : .secondary)
                        Spacer()
                        if item.kind == "archive", let cr = item.cr, let url = Site.page("catalogue/\(cr)") {
                            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
                if item.kind == "archive", let cr = item.cr {
                    Section {
                        if SiteAccount.shared.signedIn { PinButton(cr: cr) }
                        Button { if let url = Site.page("catalogue/\(cr)") { web = WebPage(url) } } label: { Label("Request this piece", systemImage: "hand.raised") }
                    } footer: { Text("Requests are a vote, and the site checks a vote comes from a person, so it opens on the site.") }
                }
                Section("Answers") {
                    if item.comments.isEmpty { Text("No answers yet.").foregroundStyle(.secondary) }
                    ForEach(item.comments) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.body).plReading()
                            HStack(spacing: 4) { Text(c.handle ?? "member"); Text("·"); Ago(text: c.createdAt) }.plFont(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if SiteAccount.shared.signedIn {
                        HStack {
                            TextField("Answer", text: $draft, axis: .vertical).lineLimit(1...4)
                            Button {
                                let t = draft; sending = true
                                Task {
                                    line = await stream.comment(item.id, t).map { "Not sent. \($0)" } ?? "Sent."
                                    if line == "Sent." { draft = "" }
                                    sending = false
                                }
                            } label: { Image(systemName: "paperplane.fill") }
                                .disabled(sending || draft.trimmingCharacters(in: .whitespaces).count < 2)
                                .accessibilityLabel("Send the answer")
                        }
                        ResultLine(text: line)
                    } else {
                        Text("Sign in from the Congregation to answer.").plFont(.footnote).foregroundStyle(.secondary)
                    }
                }
                ResultLine(text: stream.line)
            }
            .siteList()
            .navigationTitle(item.kind == "archive" ? (item.cr ?? "Archive") : "Stream")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        } else {
            EmptyNote(symbol: "square.stack", title: "That item is gone", detail: "Pull the stream to see what is there now.")
        }
    }
}
