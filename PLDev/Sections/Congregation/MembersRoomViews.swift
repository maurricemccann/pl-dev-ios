import SwiftUI
import Translation
import TipKit

// The members' room, drawn the way the site draws it: a compose card, `The House | Following`, and the room's posts as cream cards
// with the author's round mark, the post in the display face, the action pills, and the answers threaded one level under it.
// Public to read. Posting, reacting, answering, reposting, saving and reporting need the site account. For him, as the Founder,
// the room is also where held posts and answers wait for his word.

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
    var author: String {
        if byFounder { return "The Founder" }
        if authorKind == "anon" { return "A member" }
        if let h = authorHandle, !h.isEmpty { return h.prefix(1).uppercased() + String(h.dropFirst()) }
        return Glyphs.label(authorGlyph) ?? "A member"
    }
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
    func post(_ text: String, media: String = "", repostOf: String? = nil) async -> String? {
        do {
            var body: [String: Any] = ["body": text, "mediaUrl": media]
            if let repostOf { body = ["repostOf": repostOf] }
            let r = try await Site.post("api/congregation/feed", body)
            line = (r.json?["message"] as? String) ?? (repostOf == nil ? "Posted." : "Reposted.")
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
    func answer(_ postID: String, _ text: String, anon: Bool, parentId: String? = nil) async -> String {
        do {
            var body: [String: Any] = ["postId": postID, "body": text, "anon": anon]
            if let parentId { body["parentId"] = parentId }
            let r = try await Site.post("api/congregation/feed/comment", body)
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
        do { let r = try await Site.post("api/congregation/report", ["refType": type, "refId": id]); line = (r.json?["message"] as? String) ?? "Reported."; tick += 1 }
        catch { line = "Not sent. \(error.localizedDescription)" }
    }
}

// MARK: - Following

struct FollowPost: Decodable, Hashable, Identifiable {
    let id: String
    let body: String
    let mediaUrl: String?
    let glyph: String?
    let handle: String?
    let createdAt: String?
    var reactions: Int?
    var reacted: Bool?
}

/// Published posts from the members he follows, newest first. Empty, it offers the directory as "who to follow".
@MainActor @Observable final class FollowingModel {
    var posts: [FollowPost] = []
    var directory: [DirectoryMember] = []
    var cursor: String?
    var loaded = false
    var loading = false
    var failure: String?
    var line: String?

    private struct Page: Decodable { let posts: [FollowPost]; let nextCursor: String? }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await Site.get("api/congregation/following", Page.self)
            posts = p.posts; cursor = p.nextCursor; loaded = true; failure = nil
            if posts.isEmpty, directory.isEmpty { directory = (try? await Site.get("api/members/directory", DirectoryReply.self))?.members ?? [] }
        } catch { if !loaded { failure = error.localizedDescription } }
    }

    func more() async {
        guard !loading, let c = cursor else { return }
        loading = true
        defer { loading = false }
        if let p = try? await Site.get("api/congregation/following", Page.self, query: ["cursor": c]) {
            let have = Set(posts.map(\.id)); posts += p.posts.filter { !have.contains($0.id) }; cursor = p.nextCursor
        }
    }

    func react(_ id: String) async {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        let before = posts[i]
        let now = !(posts[i].reacted ?? false)
        posts[i].reacted = now; posts[i].reactions = max(0, (posts[i].reactions ?? 0) + (now ? 1 : -1))
        do { try await Site.post("api/congregation/feed/react", ["postId": id]); line = nil }
        catch { if let j = posts.firstIndex(where: { $0.id == id }) { posts[j] = before }; line = "Not saved. \(error.localizedDescription)" }
    }
}

// MARK: - The room tab

struct RoomTabView: View {
    @Bindable var state: CongregationModel
    @State private var room = RoomModel()
    @State private var following = FollowingModel()
    @State private var mode = 0
    @State private var draft = ""
    @State private var media = ""
    @State private var picking = false
    @State private var confirmPost = false
    @State private var sending = false
    @State private var sendLine: String?
    @State private var removing: RoomPost?
    @State private var removingAnswer: (RoomPost, RoomComment)?
    @State private var reposting: RoomPost?
    @State private var web: WebPage?
    @State private var lightbox: LightboxItem?
    @Environment(\.colorScheme) private var scheme
    private let account = SiteAccount.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The Congregation Home \u{2014} the room").siteLabel()
                    (Text("The room where the ").font(SiteFont.display(28)).foregroundColor(Bone.ink(scheme))
                        + Text("congregation").font(SiteFont.display(28, italic: true)).foregroundColor(Bone.gold)
                        + Text(" lives.").font(SiteFont.display(28)).foregroundColor(Bone.ink(scheme)))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 20)
                if account.signedIn { compose } else if room.loaded { watching }
                if account.signedIn { SiteSegment(titles: ["The House", "Following"], index: $mode) }
                if let l = room.line, mode == 0 { SiteNote(text: l) }
                if room.isFounder && room.waiting > 0 && mode == 0 { TipView(RoomSwipeTip()) }
                if mode == 1 && account.signedIn { followingBody } else { houseBody }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .siteScreen()
        .refreshable { if mode == 1 { await following.load() } else { await room.load() } }
        .task { while !Task.isCancelled { await room.load(); try? await Task.sleep(for: .seconds(90)) } }   // the site's own floor under real time
        .onChange(of: mode) { _, m in if m == 1, !following.loaded { Task { await following.load() } } }
        .sensoryFeedback(PLHaptic.commit, trigger: room.tick)
        .sheet(isPresented: $picking) { VisualPickerSheet { media = $0 } }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .fullScreenCover(item: $lightbox) { Lightbox(item: $0) }
        .confirmationDialog(room.isFounder ? "Post as the Founder?" : "Post to the room?", isPresented: $confirmPost, titleVisibility: .visible) {
            Button("Post") {
                let t = draft, m = media; sending = true
                Task {
                    if let err = await room.post(t, media: m) { sendLine = "Not posted. \(err)" } else { draft = ""; media = ""; sendLine = nil; state.tick += 1 }
                    sending = false
                }
            }
        } message: { Text("This is public to the whole congregation, and goes up at once.") }
        .confirmationDialog("Remove this post?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove it", role: .destructive) { if let p = removing { Task { await room.moderate(post: p.id, approve: false) } } }
        } message: { Text("It leaves the room for everyone. Its author is told.") }
        .confirmationDialog("Remove this answer?", isPresented: Binding(get: { removingAnswer != nil }, set: { if !$0 { removingAnswer = nil } }), titleVisibility: .visible) {
            Button("Remove it", role: .destructive) { if let (p, c) = removingAnswer { Task { await room.moderate(comment: c.id, in: p.id, approve: false) } } }
        } message: { Text("It leaves the room for everyone.") }
        .confirmationDialog("Repost this?", isPresented: Binding(get: { reposting != nil }, set: { if !$0 { reposting = nil } }), titleVisibility: .visible) {
            Button("Repost") { if let p = reposting { Task { if let err = await room.post("", repostOf: p.id) { room.line = "Not sent. \(err)" } } } }
        } message: { Text("It goes up in the room under your name, crediting its author.") }
    }

    // The compose card (members), or the invitation (the public).
    private var compose: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(room.isFounder ? "Post to the congregation" : "State your reality").siteLabel(11).foregroundStyle(Bone.goldDim)
            TextField(room.isFounder ? "Speak to your people\u{2026}" : "Speak it in the present tense\u{2026}", text: $draft, axis: .vertical)
                .lineLimit(3...8).siteField()
            if let m = URL(string: media), !media.isEmpty {
                PostMediaView(media: m.absoluteString, onOpen: { lightbox = LightboxItem(src: $0, caption: "") }, onWeb: { web = WebPage($0) })
                    .frame(maxHeight: 220)
                    .overlay(alignment: .topTrailing) {
                        Button("remove") { media = "" }.font(SiteFont.body(11, relativeTo: .caption)).textCase(.uppercase).tracking(1.6)
                            .padding(.horizontal, 10).frame(minHeight: 30).background(Bone.ink(scheme).opacity(0.85), in: Capsule())
                            .foregroundStyle(Bone.ground(scheme)).padding(6)
                    }
            }
            HStack {
                SiteAction(title: media.isEmpty ? "+ add a visual" : "\u{27F3} change visual", tone: .faint) { picking = true }
                Spacer()
                Button { confirmPost = true } label: { Text(sending ? "\u{2026}" : (room.isFounder ? "Post" : "Speak")) }
                    .buttonStyle(SitePill()).frame(maxWidth: 140)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            SiteNote(text: sendLine)
        }
        .siteCard(padding: 18, radius: 20)
    }

    private var watching: some View {
        VStack(spacing: 12) {
            Text("You are watching the room.").font(SiteFont.display(22)).foregroundStyle(Bone.ink(scheme))
            Text("The congregation is open to see. To speak, react, and be witnessed \u{2014} enter.").siteBody(14).multilineTextAlignment(.center)
            Button { state.tab = .me } label: { Text("Enter the congregation") }.buttonStyle(SitePill()).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity).siteCard(padding: 22, radius: 20)
    }

    @ViewBuilder private var houseBody: some View {
        if !room.loaded {
            if let f = room.failure { SiteEmpty(title: "Could not load the room", detail: f, actionTitle: "Try again") { Task { await room.load() } } }
            else { SitePulse() }
        } else if room.posts.isEmpty {
            SiteEmpty(title: "The room is quiet.", detail: "Be the first to speak.")
        } else {
            ForEach(room.posts) { post in
                RoomPostCard(post: post, room: room, signedIn: account.signedIn, myGlyph: account.me?.glyph ?? "smiley",
                             accent: StorefrontColor.hex(account.me?.brandColor) ?? Bone.gold,
                             onAuth: { state.tab = .me }, onMember: { state.memberHandle = $0 }, onWeb: { web = WebPage($0) }, onLightbox: { lightbox = $0 },
                             askRemove: { removing = $0 }, askRemoveAnswer: { removingAnswer = ($0, $1) }, askRepost: { reposting = $0 })
            }
        }
    }

    @ViewBuilder private var followingBody: some View {
        if !following.loaded {
            if let f = following.failure { SiteEmpty(title: "Could not load your feed", detail: f, actionTitle: "Try again") { Task { await following.load() } } }
            else { SitePulse() }
        } else if following.posts.isEmpty {
            VStack(spacing: 16) {
                Text("Your following feed is quiet. Find your people.").siteBody(14).multilineTextAlignment(.center)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(following.directory.prefix(12)) { m in
                        Button { state.memberHandle = m.handle } label: {
                            HStack(spacing: 8) {
                                GlyphMark(glyph: m.glyph, color: StorefrontColor.hex(m.brandColor) ?? Bone.gold, size: 18)
                                Text("@\(m.handle)").font(SiteFont.body(13)).foregroundStyle(Bone.ink(scheme)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44).background(Bone.raised(scheme), in: Capsule())
                            .overlay { Capsule().strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            SiteNote(text: following.line)
            ForEach(following.posts) { p in
                FollowCard(post: p, model: following, signedIn: account.signedIn, myGlyph: account.me?.glyph ?? "smiley", onMember: { state.memberHandle = $0 }, onWeb: { web = WebPage($0) })
                    .onAppear { if p.id == following.posts.last?.id { Task { await following.more() } } }
            }
        }
    }
}

// MARK: - A post of the room

struct RoomPostCard: View {
    let post: RoomPost
    let room: RoomModel
    let signedIn: Bool
    let myGlyph: String
    let accent: Color
    var onAuth: () -> Void
    var onMember: (String) -> Void
    var onWeb: (URL) -> Void
    var onLightbox: (LightboxItem) -> Void
    var askRemove: (RoomPost) -> Void
    var askRemoveAnswer: (RoomPost, RoomComment) -> Void
    var askRepost: (RoomPost) -> Void
    @State private var comment = ""
    @State private var anon = false
    @State private var replyTo: RoomComment?
    @State private var sending = false
    @State private var sentLine: String?
    @State private var reported = false
    @State private var translating = false   // apple lane: the system translation sheet for this post
    @Environment(\.colorScheme) private var scheme

    private var dateLabel: String? { Date.pl(post.createdAt)?.formatted(.dateTime.month(.wide).day()) }
    private func label(_ c: RoomComment) -> String { c.anon == true ? "A member" : (Glyphs.label(c.glyph) ?? "A member") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let r = post.repostHandle {
                Text("\u{21BB} reposted \(r == "the founder" ? "the founder" : "@\(r)")").siteLabel(10).foregroundStyle(Bone.goldDim)
            }
            LinkedText(text: post.body, size: 19, onMember: onMember, onWeb: onWeb)
            if room.isFounder && post.waiting {
                HStack(spacing: 18) {
                    SiteAction(title: "Approve post") { Task { await room.moderate(post: post.id, approve: true) } }
                    SiteAction(title: "Remove", tone: .faint) { askRemove(post) }
                }
            }
            if let m = post.mediaUrl, !m.isEmpty { PostMediaView(media: m, onOpen: { onLightbox(LightboxItem(src: $0, caption: "")) }, onWeb: onWeb) }
            actionBar
            if !post.comments.isEmpty { thread }
            answerForm
        }
        .siteCard(padding: 16, radius: 16)
        .contextMenu {
            Button { UIPasteboard.general.string = post.body } label: { Label("Copy the text", systemImage: "doc.on.doc") }
            Button { translating = true } label: { Label("Translate", systemImage: "translate") }
            if let h = post.authorHandle { Button { onMember(h) } label: { Label("Open @\(h)", systemImage: "person") } }
        }
        .translationPresentation(isPresented: $translating, text: post.body)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarMark(glyph: post.authorGlyph, color: accent, size: 36, founder: post.byFounder, anon: post.authorKind == "anon" && post.authorGlyph == nil)
            VStack(alignment: .leading, spacing: 2) {
                if let h = post.authorHandle, !post.byFounder {
                    Button { onMember(h) } label: { Text(post.author).siteLabel(11).foregroundStyle(Bone.inkSoft(scheme)) }.buttonStyle(.plain)
                } else { Text(post.author).siteLabel(11).foregroundStyle(Bone.inkSoft(scheme)) }
                HStack(spacing: 0) {
                    Text(dateLabel ?? "").siteLabel(10)
                    if post.waiting { Text(" \u{00B7} held").siteLabel(10).foregroundStyle(Bone.goldDim) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SiteRule()
            HStack(spacing: 8) {
                SocialPill(label: post.reactions > 0 ? "\(post.reactions)" : "React", on: post.reacted, action: {
                    if signedIn { Task { await room.react(post.id) } } else { onAuth() }
                }) { GlyphMark(glyph: myGlyph, color: post.reacted ? accent : Bone.inkFaint(scheme), size: 15) }
                    .accessibilityLabel(post.reacted ? "Reacted, \(post.reactions)" : "React, \(post.reactions)")
                SocialPill(label: "Repost", action: { if signedIn { askRepost(post) } else { onAuth() } }) { Image(systemName: "arrow.2.squarepath").font(.system(size: 12)) }
                    .disabled(post.waiting)
                Spacer(minLength: 0)
                SaveButton(refType: "post", refId: post.id, mediaURL: post.mediaUrl)
                if !post.byFounder {
                    SocialPill(label: reported ? "Reported" : "Report", danger: true, action: {
                        if !signedIn { onAuth(); return }
                        guard !reported else { return }
                        reported = true
                        Task { await room.report("post", post.id) }
                    }) { Image(systemName: "flag").font(.system(size: 12)) }.disabled(reported)
                }
            }
        }
    }

    private var thread: some View {
        let top = post.comments.filter { $0.parentId == nil }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(top) { c in
                VStack(alignment: .leading, spacing: 10) {
                    answer(c, isReply: false)
                    let replies = post.comments.filter { $0.parentId == c.id }
                    if !replies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) { ForEach(replies) { answer($0, isReply: true) } }
                            .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Bone.line(scheme)).frame(width: 1) }
                            .padding(.leading, 28)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func answer(_ c: RoomComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if c.anon == true { Circle().fill(Bone.line(scheme)).frame(width: 18, height: 18).padding(.top, 2) }
            else { GlyphMark(glyph: c.glyph ?? "smiley", color: accent, size: 18).padding(.top, 2) }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.body).font(SiteFont.body(14)).foregroundStyle(Bone.ink(scheme)).lineSpacing(4)
                HStack(spacing: 14) {
                    HStack(spacing: 0) {
                        Text(c.anon == true ? "Anonymous" : label(c)).siteLabel(10)
                        if c.status == "pending" { Text(" \u{00B7} held").siteLabel(10).foregroundStyle(Bone.goldDim) }
                    }
                    if !isReply, c.status != "pending", signedIn { SiteAction(title: "reply", tone: .faint) { replyTo = c } }
                }
                if room.isFounder, c.status == "pending" {
                    HStack(spacing: 18) {
                        SiteAction(title: "Approve") { Task { await room.moderate(comment: c.id, in: post.id, approve: true) } }
                        SiteAction(title: "Remove", tone: .faint) { askRemoveAnswer(post, c) }
                    }
                }
            }
        }
        .opacity(c.status == "pending" ? 0.65 : 1)
    }

    @ViewBuilder private var answerForm: some View {
        if signedIn {
            VStack(alignment: .leading, spacing: 8) {
                if let r = replyTo {
                    HStack(spacing: 6) {
                        Text("replying to \(label(r))").siteLabel(10).foregroundStyle(Bone.goldDim)
                        SiteAction(title: "cancel", tone: .faint) { replyTo = nil }
                    }
                }
                TextField(replyTo.map { "Reply to \(label($0))\u{2026}" } ?? "Answer the room\u{2026}", text: $comment, axis: .vertical).lineLimit(2...5).siteField()
                HStack {
                    Toggle(isOn: $anon) { Text("Post anonymously").font(SiteFont.body(12)).foregroundStyle(Bone.inkSoft(scheme)) }.tint(Bone.gold).fixedSize()
                    Spacer()
                    SiteAction(title: sending ? "\u{2026}" : "Speak") {
                        let t = comment.trimmingCharacters(in: .whitespacesAndNewlines); sending = true
                        Task {
                            let m = await room.answer(post.id, t, anon: anon, parentId: replyTo?.id)
                            sentLine = m
                            if !m.hasPrefix("Not") { comment = ""; replyTo = nil }
                            sending = false
                        }
                    }
                    .disabled(sending || comment.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                SiteNote(text: sentLine)
            }
            .padding(.top, 4)
        } else {
            SiteAction(title: "Enter to answer the room \u{2192}", tone: .faint) { onAuth() }
        }
    }
}

// MARK: - A post of someone you follow

struct FollowCard: View {
    let post: FollowPost
    let model: FollowingModel
    let signedIn: Bool
    let myGlyph: String
    var onMember: (String) -> Void
    var onWeb: (URL) -> Void
    @State private var lightbox: LightboxItem?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GlyphMark(glyph: post.glyph ?? "smiley", color: Bone.gold, size: 16)
                if let h = post.handle { Button { onMember(h) } label: { Text("@\(h)").siteLabel(11) }.buttonStyle(.plain) } else { Text("A member").siteLabel(11) }
                if let d = Date.pl(post.createdAt) { Text("\u{00B7} \(d.formatted(.dateTime.month(.abbreviated).day()))").siteLabel(10) }
            }
            LinkedText(text: post.body, size: 18, onMember: onMember, onWeb: onWeb)
            if let m = post.mediaUrl, !m.isEmpty { PostMediaView(media: m, onOpen: { lightbox = LightboxItem(src: $0, caption: "") }, onWeb: onWeb) }
            if signedIn {
                HStack(spacing: 14) {
                    SocialPill(label: (post.reactions ?? 0) > 0 ? "\(post.reactions ?? 0)" : "React", on: post.reacted ?? false, action: { Task { await model.react(post.id) } }) {
                        GlyphMark(glyph: myGlyph, color: (post.reacted ?? false) ? Bone.gold : Bone.inkFaint(scheme), size: 15)
                    }
                    SaveButton(refType: "post", refId: post.id, mediaURL: post.mediaUrl)
                    Spacer(minLength: 0)
                }
            }
        }
        .siteCard(padding: 16, radius: 16)
        .fullScreenCover(item: $lightbox) { Lightbox(item: $0) }
    }
}
