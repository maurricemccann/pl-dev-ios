import SwiftUI
import TipKit

// The members' room: the posts the congregation writes to each other. Public to read. Posting, reacting and answering need the
// site account. For him, as the founder, the room is also where held posts and answers wait for his word.

struct RoomComment: Decodable, Hashable, Identifiable {
    let id: String
    let body: String
    let anon: Bool?
    let glyph: String?
    let status: String?
    let parentId: String?
    let createdAt: String?
}

struct RoomPost: Decodable, Hashable, Identifiable {
    let id: String
    let body: String
    let mediaUrl: String?
    let createdAt: String?
    var status: String?
    let authorKind: String?
    let authorGlyph: String?
    let authorHandle: String?
    let repostHandle: String?
    var reactions: Int
    var reacted: Bool
    var comments: [RoomComment]

    var byFounder: Bool { authorKind == "founder" }
    var waiting: Bool { status == "pending" }
    var author: String { byFounder ? "The Founder" : (authorHandle ?? "A member") }
}

struct RoomReply: Decodable {
    let posts: [RoomPost]
    let canPost: Bool?
    let isFounder: Bool?
    let authed: Bool?
}

@MainActor @Observable final class RoomModel {
    var posts: [RoomPost] = []
    var canPost = false
    var isFounder = false
    var loaded = false
    var failure: String?
    var line: String?
    var tick = 0

    func load() async {
        do {
            let r = try await Site.get("api/congregation/feed", RoomReply.self)
            posts = r.posts; canPost = r.canPost ?? false; isFounder = r.isFounder ?? false; failure = nil; loaded = true
        } catch { if !loaded { failure = error.localizedDescription } }
    }

    var waiting: Int { posts.filter(\.waiting).count + posts.reduce(0) { $0 + $1.comments.filter { $0.status == "pending" }.count } }

    /// Nil on success, else the site's sentence.
    func post(_ text: String, repostOf: String? = nil) async -> String? {
        do {
            var body: [String: Any] = ["body": text]
            if let repostOf { body = ["repostOf": repostOf] }
            let r = try await Site.post("api/congregation/feed", body)
            line = (r.json?["message"] as? String) ?? "Posted."
            tick += 1
            await load()
            return nil
        } catch { return error.localizedDescription }
    }

    func react(_ id: String) async {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        let before = posts[i]
        posts[i].reacted.toggle()
        posts[i].reactions = max(0, posts[i].reactions + (posts[i].reacted ? 1 : -1))
        do {
            let r = try await Site.post("api/congregation/feed/react", ["postId": id])
            if let j = posts.firstIndex(where: { $0.id == id }), let b = r.json?["reacted"] as? Bool { posts[j].reacted = b }
            tick += 1; line = nil
        } catch {
            if let j = posts.firstIndex(where: { $0.id == id }) { posts[j] = before }
            line = "Not saved. \(error.localizedDescription)"
        }
    }

    /// The answer is held until he approves it, as the site does; the site's own sentence says so.
    func answer(_ postID: String, _ text: String, anon: Bool) async -> String {
        do {
            let r = try await Site.post("api/congregation/feed/comment", ["postId": postID, "body": text, "anon": anon])
            tick += 1
            return (r.json?["message"] as? String) ?? "Sent."
        } catch { return "Not sent. \(error.localizedDescription)" }
    }

    /// His word on a held post or answer: approve it into the room, or remove it. Optimistic, restored if the site refuses.
    func moderate(post id: String, approve: Bool) async {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        let before = posts
        if approve { posts[i].status = "published" } else { posts.remove(at: i) }
        do { _ = try await Site.post("api/congregation/feed/moderate", ["postId": id, "action": approve ? "approve" : "remove"]); tick += 1; line = approve ? "Approved." : "Removed." }
        catch { posts = before; line = "Not saved. \(error.localizedDescription)" }
    }

    func moderate(comment id: String, in postID: String, approve: Bool) async {
        let before = posts
        guard let i = posts.firstIndex(where: { $0.id == postID }) else { return }
        if approve {
            posts[i].comments = posts[i].comments.map { $0.id == id ? RoomComment(id: $0.id, body: $0.body, anon: $0.anon, glyph: $0.glyph, status: "approved", parentId: $0.parentId, createdAt: $0.createdAt) : $0 }
        } else { posts[i].comments.removeAll { $0.id == id } }
        do { _ = try await Site.post("api/congregation/feed/moderate", ["commentId": id, "action": approve ? "approve" : "remove"]); tick += 1; line = approve ? "Approved." : "Removed." }
        catch { posts = before; line = "Not saved. \(error.localizedDescription)" }
    }

    func report(_ type: String, _ id: String) async {
        do { let r = try await Site.post("api/congregation/report", ["refType": type, "refId": id]); line = (r.json?["message"] as? String) ?? "Reported." ; tick += 1 }
        catch { line = "Not sent. \(error.localizedDescription)" }
    }
}

struct RoomTabView: View {
    @Bindable var state: CongregationModel
    @State private var room = RoomModel()
    @State private var draft = ""
    @State private var confirmPost = false
    @State private var sendLine: String?
    @State private var removing: RoomPost?
    @State private var reposting: RoomPost?
    private let account = SiteAccount.shared

    var body: some View {
        List {
            if let l = room.line { ResultLine(text: l) }
            if room.canPost {
                Section {
                    TextField("Say something to the room", text: $draft, axis: .vertical).lineLimit(2...8)
                    Button { confirmPost = true } label: { Label("Post to the room", systemImage: "paperplane").frame(minHeight: PLMetric.touch) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ResultLine(text: sendLine)
                }
            } else if room.loaded {
                Section { Label("Sign in from Me to post, react and answer.", systemImage: "person.crop.circle").foregroundStyle(.secondary) }
            }
            if room.isFounder && room.waiting > 0 {
                Section { TipView(RoomSwipeTip()) }
            }
            if !room.loaded {
                if let f = room.failure {
                    EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the room", detail: f, actionTitle: "Try again") { Task { await room.load() } }.listRowBackground(Color.clear)
                } else { ForEach(0..<4, id: \.self) { _ in SkeletonRow() } }
            } else if room.posts.isEmpty {
                ContentUnavailableView("The room is quiet", systemImage: "bubble.left.and.bubble.right", description: Text("Posts from the congregation appear here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(room.posts) { post in
                NavigationLink { RoomPostView(room: room, postID: post.id) } label: { RoomPostRow(post: post, room: room) }
                    .swipeActions(edge: .trailing) {
                        if room.isFounder && post.waiting { Button("Approve") { Task { await room.moderate(post: post.id, approve: true) } }.tint(.green) }
                    }
                    .swipeActions(edge: .leading) {
                        if room.isFounder { Button("Remove", role: .destructive) { removing = post } }
                    }
                    .contextMenu {
                        Button { UIPasteboard.general.string = post.body } label: { Label("Copy the text", systemImage: "doc.on.doc") }
                        if room.canPost && !post.waiting && !room.isFounder {
                            Button { Task { await room.report("post", post.id) } } label: { Label("Report", systemImage: "flag") }
                        }
                        if room.canPost && !post.waiting { Button { reposting = post } label: { Label("Repost", systemImage: "arrow.2.squarepath") } }
                    }
            }
        }
        .refreshable { await room.load() }
        .task { await room.load() }
        .sensoryFeedback(PLHaptic.commit, trigger: room.tick)
        .confirmationDialog(room.isFounder ? "Post as the Founder?" : "Post to the room?", isPresented: $confirmPost, titleVisibility: .visible) {
            Button("Post") {
                let t = draft
                Task { if let err = await room.post(t) { sendLine = "Not posted. \(err)" } else { draft = ""; sendLine = nil; state.tick += 1 } }
            }
        } message: { Text("This is public to the whole congregation, and goes up at once.") }
        .confirmationDialog("Remove this post?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove it", role: .destructive) { if let p = removing { Task { await room.moderate(post: p.id, approve: false) } } }
        } message: { Text("It leaves the room for everyone. Its author is told.") }
        .confirmationDialog("Repost this?", isPresented: Binding(get: { reposting != nil }, set: { if !$0 { reposting = nil } }), titleVisibility: .visible) {
            Button("Repost") { if let p = reposting { Task { _ = await room.post("", repostOf: p.id) } } }
        } message: { Text("It goes up in the room under your name, crediting its author.") }
    }
}

struct RoomPostRow: View {
    let post: RoomPost
    let room: RoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpace.gap) {
            HStack(spacing: PLSpace.gap) {
                GlyphBadge(glyph: post.authorGlyph, founder: post.byFounder)
                Text(post.author).plFont(.subhead, emphasized: true)
                if let r = post.repostHandle { Text("reposted \(r)").plFont(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Ago(text: post.createdAt).plFont(.caption).foregroundStyle(.secondary)
            }
            if post.waiting { Label("Waiting for your word", systemImage: "hourglass").plFont(.caption, emphasized: true).foregroundStyle(PLTone.warn) }
            Text(post.body).plFont(.body).plReading().lineLimit(8)
            if let m = post.mediaUrl, let url = URL(string: m) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFill()
                    case .failure: Color.secondary.opacity(0.12).overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                    default: Color.secondary.opacity(0.12).overlay { ProgressView() }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
            }
            HStack(spacing: PLSpace.margin) {
                Button { Task { await room.react(post.id) } } label: {
                    Label("\(post.reactions)", systemImage: post.reacted ? "heart.fill" : "heart").monospacedDigit().contentTransition(.numericText()).symbolEffect(.bounce, value: post.reacted)
                }
                .buttonStyle(.plain).foregroundStyle(post.reacted ? PLTone.accent : .secondary)
                .accessibilityLabel(post.reacted ? "Reacted, \(post.reactions)" : "React, \(post.reactions)")
                Label("\(post.comments.count)", systemImage: "bubble.left").foregroundStyle(.secondary)
            }
            .plFont(.footnote).frame(minHeight: PLMetric.touch - 8)
        }
        .padding(.vertical, PLSpace.tight)
    }
}

struct RoomPostView: View {
    let room: RoomModel
    let postID: String
    @State private var draft = ""
    @State private var anon = false
    @State private var line: String?
    @State private var sending = false

    var body: some View {
        if let post = room.posts.first(where: { $0.id == postID }) {
            List {
                Section {
                    RoomPostRow(post: post, room: room)
                }
                Section("Answers") {
                    if post.comments.isEmpty { Text("No answers yet.").foregroundStyle(.secondary) }
                    ForEach(post.comments) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.body).plReading()
                            HStack(spacing: 4) {
                                Text(c.anon == true ? "Anonymous" : "A member"); Text("·"); Ago(text: c.createdAt)
                                if c.status == "pending" { Text("· waiting").foregroundStyle(PLTone.warn) }
                            }.plFont(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            if room.isFounder && c.status == "pending" { Button("Approve") { Task { await room.moderate(comment: c.id, in: post.id, approve: true) } }.tint(.green) }
                        }
                        .swipeActions(edge: .leading) {
                            if room.isFounder { Button("Remove", role: .destructive) { Task { await room.moderate(comment: c.id, in: post.id, approve: false) } } }
                        }
                    }
                }
                if room.canPost {
                    Section {
                        TextField("Answer", text: $draft, axis: .vertical).lineLimit(1...5)
                        Toggle("Anonymous", isOn: $anon)
                        Button {
                            let t = draft; let a = anon; sending = true
                            Task { line = await room.answer(post.id, t, anon: a); if !(line ?? "").hasPrefix("Not") { draft = "" }; sending = false }
                        } label: { Label("Send the answer", systemImage: "paperplane").frame(minHeight: PLMetric.touch) }
                            .disabled(sending || draft.trimmingCharacters(in: .whitespaces).count < 2)
                        ResultLine(text: line)
                    } footer: { Text("Answers are held until the founder has seen them.") }
                }
            }
            .navigationTitle("Post").navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(PLHaptic.commit, trigger: room.tick)
        } else {
            EmptyNote(symbol: "bubble.left", title: "That post is gone", detail: "Pull the room to see what is there now.")
        }
    }
}
