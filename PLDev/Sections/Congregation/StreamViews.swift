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
    var w: Int?
    var h: Int?
    var reactions: Int
    var reacted: Bool
    var comments: [StreamComment]

    private enum K: String, CodingKey {
        case kind, id, text, author, createdAt, cr, image, thumb, title, pillar, body, slug, name, price, argument, numeral, truth, gloss, w, h, reactions, reacted, comments
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

    var body: some View {
        List {
            if let l = stream.line { Text(l).font(.footnote).foregroundStyle(.secondary) }
            if stream.items.isEmpty {
                if let f = stream.failure {
                    EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the stream", detail: f, actionTitle: "Try again") { Task { await stream.reload() } }
                        .listRowBackground(Color.clear)
                } else { ForEach(0..<4, id: \.self) { _ in SkeletonRow() } }
            }
            ForEach(stream.items) { item in
                NavigationLink { StreamDetailView(stream: stream, itemID: item.id) } label: { StreamCard(item: item, stream: stream) }
                    .onAppear { if item.id == stream.items.last?.id { Task { await stream.more() } } }
            }
            if stream.loading && !stream.items.isEmpty { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            if !stream.items.isEmpty, stream.total > 0 { Text("\(stream.items.count) of \(stream.total)").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).listRowBackground(Color.clear) }
        }
        .refreshable { await stream.reload() }
        .task { if stream.items.isEmpty { await stream.reload() } }
        .sensoryFeedback(PLHaptic.commit, trigger: stream.tick)
    }
}

/// One row of the stream, drawn for its kind.
struct StreamCard: View {
    let item: StreamItem
    let stream: StreamModel

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpace.gap) {
            switch item.kind {
            case "doctrine":
                Text(item.numeral ?? "").plFont(.footnote, emphasized: true).foregroundStyle(PLTone.accent)
                Text(item.truth ?? "").plTitle(.title3)
                Text(item.gloss ?? "").plFont(.callout).foregroundStyle(.secondary).plReading()
            case "declaration":
                Text(item.text ?? "").plFont(.body).plReading()
                HStack(spacing: 4) { Text(item.author ?? "Anonymous"); Text("·"); Ago(text: item.createdAt) }.plFont(.footnote).foregroundStyle(.secondary)
            case "drop":
                HStack(spacing: PLSpace.pad) {
                    Color.clear.frame(width: 84, height: 84).overlay { FlatImage(url: item.picture, padding: 4) }
                        .background(PLTone.well, in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In the shop").plFont(.caption).foregroundStyle(.secondary)
                        Text(item.name ?? "A piece").plFont(.headline)
                        if let a = item.argument { Text(a).plFont(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                        if let p = item.price { Text(Money.text(p)).plFont(.footnote).monospacedDigit() }
                    }
                }
            default:
                if let url = item.picture {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let i): i.resizable().scaledToFill()
                        case .failure: Color.secondary.opacity(0.12).overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                        default: Color.secondary.opacity(0.12).overlay { ProgressView() }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                }
                if item.kind == "archive" {
                    Text(item.title ?? item.cr ?? "Archive piece").plFont(.headline)
                    Text([item.cr, item.pillar].compactMap { $0 }.joined(separator: " · ")).plFont(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: PLSpace.margin) {
                Button { Task { await stream.react(item.id) } } label: {
                    Label("\(item.reactions)", systemImage: item.reacted ? "heart.fill" : "heart").monospacedDigit().contentTransition(.numericText())
                        .symbolEffect(.bounce, value: item.reacted)
                }
                .buttonStyle(.plain).foregroundStyle(item.reacted ? PLTone.accent : .secondary)
                .accessibilityLabel(item.reacted ? "Reacted, \(item.reactions)" : "React, \(item.reactions)")
                if !item.comments.isEmpty { Label("\(item.comments.count)", systemImage: "bubble.left").foregroundStyle(.secondary) }
            }
            .plFont(.footnote)
            .frame(minHeight: PLMetric.touch - 8)
        }
        .padding(.vertical, PLSpace.tight)
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
                                default: ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                            .listRowInsets(EdgeInsets())
                        }
                        if item.kind == "archive" {
                            Text(item.title ?? item.cr ?? "").plTitle(.title3)
                            LabeledContent("Reference", value: item.cr ?? "")
                            if let p = item.pillar { LabeledContent("Pillar", value: p) }
                        }
                    case "drop":
                        FlatImage(url: item.picture, padding: PLSpace.roomy).frame(height: 260).listRowInsets(EdgeInsets())
                        Text(item.name ?? "").plTitle(.title3)
                        if let a = item.argument { Text(a).plFont(.callout).foregroundStyle(.secondary) }
                        if let s = item.slug {
                            Button { AppModel.shared.open(.section(id: "shop", path: ["piece", s], query: [:])) } label: { Label("Open the piece", systemImage: "bag") }
                        }
                    case "doctrine":
                        Text(item.numeral ?? "").plFont(.footnote, emphasized: true).foregroundStyle(PLTone.accent)
                        Text(item.truth ?? "").plTitle(.title3)
                        Text(item.gloss ?? "").plReading()
                    default:
                        Text(item.text ?? "").plReading()
                        Text(item.author ?? "").plFont(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { Task { await stream.react(item.id) } } label: {
                            Label("\(item.reactions)", systemImage: item.reacted ? "heart.fill" : "heart").monospacedDigit().contentTransition(.numericText()).symbolEffect(.bounce, value: item.reacted)
                        }
                        .buttonStyle(.plain).foregroundStyle(item.reacted ? PLTone.accent : .secondary)
                        Spacer()
                        if item.kind == "archive", let cr = item.cr, let url = Site.page("catalogue/\(cr)") {
                            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
                if item.kind == "archive", let cr = item.cr {
                    Section {
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
            .navigationTitle(item.kind == "archive" ? (item.cr ?? "Archive") : "Stream")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        } else {
            EmptyNote(symbol: "square.stack", title: "That item is gone", detail: "Pull the stream to see what is there now.")
        }
    }
}
