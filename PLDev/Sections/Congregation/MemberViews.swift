import SwiftUI

// The members: the directory, a member's page (their posts, who follows them), and following. A member's identity on the site is
// a handle, a glyph and a colour; the app draws the glyph as a symbol and the colour as the site gives it.

struct DirectoryMember: Decodable, Identifiable, Hashable {
    let handle: String
    let glyph: String?
    let brandColor: String?
    let tier: String?
    var id: String { handle }
}

struct DirectoryReply: Decodable { let members: [DirectoryMember] }

enum StorefrontColor {
    /// "#c9a84c" → a colour; nil when it is not a six-digit hex.
    static func hex(_ s: String?) -> Color? {
        guard let s, s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A member's glyph as an SF Symbol, in their colour. The Founder gets his own mark.
struct GlyphBadge: View {
    let glyph: String?
    var color: String? = nil
    var founder = false

    private var symbol: String {
        if founder { return "seal.fill" }
        switch glyph ?? "smiley" {
        case "smiley": return "face.smiling"
        case "glyph-guy": return "person.fill"
        case "money", "money-grin": return "dollarsign.circle"
        case "love-yourself": return "heart.circle"
        default: return "circle.hexagongrid"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background((founder ? Bone.gold : (StorefrontColor.hex(color) ?? Bone.inkFaint(.light))).gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

extension String {
    /// The climb's tier as a plain word.
    var tierWord: String { self == "none" ? "New" : capitalized }
}

struct MembersTabView: View {
    @Bindable var state: CongregationModel
    @State private var query = ""
    @State private var found: [DirectoryMember]?
    @State private var searchFailed = false
    private let account = SiteAccount.shared

    private struct SearchReply: Decodable { let members: [DirectoryMember] }

    var body: some View {
        Loaded(load: { try await Site.get("api/members/directory", DirectoryReply.self).members }) { members, _ in
            List {
                let shown = found ?? members
                Section {
                    if searchFailed { Text("The search did not answer. Try again in a moment.").foregroundStyle(.secondary) }
                    else if shown.isEmpty { Text(found == nil ? "No members listed yet." : "No member by that name.").foregroundStyle(.secondary) }
                    ForEach(shown) { m in
                        Button { state.memberHandle = m.handle } label: {
                            HStack(spacing: PLSpace.pad) {
                                GlyphBadge(glyph: m.glyph, color: m.brandColor)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("@\(m.handle)").plFont(.body)
                                    if let t = m.tier { Text(t.tierWord).plFont(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: PLMetric.touch)
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text(found == nil ? "\(members.count) members" : "\(shown.count) found") }
            }
            .siteList()
            .searchable(text: $query, prompt: "Find a member")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, q in if q.isEmpty { found = nil } }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { found = nil; searchFailed = false; return }
        if let r = try? await Site.get("api/search", SearchReply.self, query: ["q": q]) { found = r.members ?? []; searchFailed = false } else { found = []; searchFailed = true }
    }
}

struct MemberView: View {
    let handle: String
    @Bindable var state: CongregationModel

    struct Post: Decodable, Identifiable { let id: String; let body: String; let mediaUrl: String?; let glyph: String?; let createdAt: String? }
    struct Posts: Decodable { let posts: [Post] }
    struct Follow: Decodable { let followers: Int; let following: Int; let isFollowing: Bool }

    @State private var follow: Follow?
    @State private var posts: [Post] = []
    @State private var loaded = false
    @State private var failure: String?
    @State private var line: String?
    @State private var member: DirectoryMember?
    private let account = SiteAccount.shared

    var body: some View {
        List {
            Section {
                HStack(spacing: PLSpace.pad) {
                    GlyphBadge(glyph: member?.glyph, color: member?.brandColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(handle)").font(SiteFont.display(26))
                        if let t = member?.tier { Text(t.tierWord).plFont(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if let f = follow {
                    LabeledContent("Followers", value: "\(f.followers)")
                    LabeledContent("Following", value: "\(f.following)")
                    if account.signedIn && account.me?.handle != handle {
                        Button {
                            Task { await toggle() }
                        } label: { Label(f.isFollowing ? "Following" : "Follow", systemImage: f.isFollowing ? "checkmark" : "plus").frame(minHeight: PLMetric.touch) }
                    }
                }
                ResultLine(text: line)
            }
            Section("Posts") {
                if let failure { Text(failure).foregroundStyle(.secondary) }
                else if loaded && posts.isEmpty { Text("No posts yet.").foregroundStyle(.secondary) }
                ForEach(posts) { p in
                    VStack(alignment: .leading, spacing: PLSpace.gap) {
                        Text(p.body).plReading()
                        if let m = p.mediaUrl, let url = URL(string: m) {
                            AsyncImage(url: url) { phase in
                                if case .success(let i) = phase { i.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                            }
                            .frame(maxWidth: .infinity).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                        }
                        Ago(text: p.createdAt).plFont(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, PLSpace.tight)
                }
            }
        }
        .siteList()
        .navigationTitle("@\(handle)").navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sensoryFeedback(PLHaptic.commit, trigger: follow?.isFollowing)
    }

    private func load() async {
        async let f = try? Site.get("api/follow", Follow.self, query: ["handle": handle])
        async let p = Site.get("api/congregation/posts", Posts.self, query: ["handle": handle])
        async let d = try? Site.get("api/members/directory", DirectoryReply.self)
        let (f1, d1) = await (f, d)
        follow = f1
        member = d1?.members.first { $0.handle == handle }
        do { posts = try await p.posts; failure = nil } catch { if !loaded { failure = error.localizedDescription } }
        loaded = true
    }

    private func toggle() async {
        let before = follow
        if let f = follow { follow = Follow(followers: f.followers + (f.isFollowing ? -1 : 1), following: f.following, isFollowing: !f.isFollowing) }
        do {
            let r = try await Site.post("api/follow", ["handle": handle])
            if let o = r.json, let n = o["followers"] as? Int, let g = o["following"] as? Int, let b = o["isFollowing"] as? Bool { follow = Follow(followers: n, following: g, isFollowing: b) }
            line = nil
        } catch { follow = before; line = "Not saved. \(error.localizedDescription)" }
    }
}
