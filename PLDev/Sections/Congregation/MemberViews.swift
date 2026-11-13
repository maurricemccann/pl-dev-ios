import SwiftUI

// The members: the directory, and a member's page the way the site draws it (`/member/<handle>`): their mark, their handle, their
// tier, who follows them, the climb, and the works they chose. The owner of the page also gets the tabs the site gives them:
// Boards, Settings, Social, Games and Ask. A member's identity on the site is a handle, a glyph and a colour.

struct DirectoryMember: Decodable, Identifiable, Hashable {
    let handle: String
    let glyph: String?
    let brandColor: String?
    let tier: String?
    var id: String { handle }
}

struct DirectoryReply: Decodable { let members: [DirectoryMember] }

/// A member's public profile, as the site's page carries it.
struct PublicProfile: Decodable, Equatable {
    let handle: String
    let firstName: String?
    let glyph: String?
    let tier: String?
    let brandColor: String?
    let points: Int
    let memberSince: String?
    let isFounder: Bool
    let founderBadge: Bool

    private enum K: String, CodingKey { case handle, firstName, glyph, tier, brandColor, points, memberSince, isFounder, founderBadge }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        handle = try c.decode(String.self, forKey: .handle)
        firstName = try? c.decodeIfPresent(String.self, forKey: .firstName)
        glyph = try? c.decodeIfPresent(String.self, forKey: .glyph)
        tier = try? c.decodeIfPresent(String.self, forKey: .tier)
        brandColor = try? c.decodeIfPresent(String.self, forKey: .brandColor)
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        memberSince = try? c.decodeIfPresent(String.self, forKey: .memberSince)
        isFounder = (try? c.decodeIfPresent(Bool.self, forKey: .isFounder)) ?? false
        founderBadge = (try? c.decodeIfPresent(Bool.self, forKey: .founderBadge)) ?? false
    }
    init(handle: String, firstName: String?, glyph: String?, tier: String?, brandColor: String?, points: Int, memberSince: String?, isFounder: Bool, founderBadge: Bool) {
        self.handle = handle; self.firstName = firstName; self.glyph = glyph; self.tier = tier; self.brandColor = brandColor
        self.points = points; self.memberSince = memberSince; self.isFounder = isFounder; self.founderBadge = founderBadge
    }
}

struct ChosenWork: Decodable, Identifiable, Hashable {
    let cr: String
    let thumb: String
    let title: String?
    var id: String { cr }
}

/// Reads a member's profile from their page on the site, which carries it in its data. A lean JSON route would replace this
/// (a ready one is in `LANES-congregation.md`); until it is live this is the one way to the points and the chosen works.
enum ProfileReader {
    static func read(_ handle: String) async -> (PublicProfile, [ChosenWork])? {
        guard let r = try? await Site.call("GET", "member/\(handle)"), r.status == 200, let html = String(data: r.data, encoding: .utf8) else { return nil }
        let t = html.replacingOccurrences(of: "\\\"", with: "\"")
        guard let obj = balanced(t, after: "\"profile\":{", open: "{", close: "}"),
              let profile = try? JSONDecoder().decode(PublicProfile.self, from: Data(obj.utf8)) else { return nil }
        var chosen: [ChosenWork] = []
        if let arr = balanced(t, after: "\"favorites\":[", open: "[", close: "]"), let works = try? JSONDecoder().decode([ChosenWork].self, from: Data(arr.utf8)) { chosen = works }
        return (profile, chosen)
    }

    /// The text from the bracket that ends `marker` to its matching close, quotes respected.
    private static func balanced(_ s: String, after marker: String, open: Character, close: Character) -> String? {
        guard let m = s.range(of: marker) else { return nil }
        let start = s.index(before: m.upperBound)
        var depth = 0, inString = false, escaped = false
        var i = start
        while i < s.endIndex {
            let ch = s[i]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else if ch == "\"" { inString = true }
            else if ch == open { depth += 1 }
            else if ch == close { depth -= 1; if depth == 0 { return String(s[start...i]) } }
            i = s.index(after: i)
        }
        return nil
    }
}

// MARK: - The directory

struct MembersTabView: View {
    @Bindable var state: CongregationModel
    @State private var members: [DirectoryMember] = []
    @State private var loaded = false
    @State private var failure: String?
    @State private var query = ""
    @State private var found: [DirectoryMember]?
    @State private var searchFailed = false
    @Environment(\.colorScheme) private var scheme

    private struct SearchReply: Decodable { let members: [DirectoryMember]? }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SitePageHead(eyebrow: "The members", lead: "The", accent: "members.",
                             lede: "Everyone in the room. Open a member to see their page, follow them, and read what they have said.")
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        TextField("Find a member", text: $query).siteField().textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.search).onSubmit { Task { await search() } }
                        Button("Find") { Task { await search() } }.buttonStyle(SiteGhost()).frame(maxWidth: 90)
                    }
                    if !loaded {
                        if let failure { SiteEmpty(title: "Could not load the members", detail: failure, actionTitle: "Try again") { Task { await load() } } } else { SitePulse() }
                    } else {
                        let shown = found ?? members
                        Text(found == nil ? "\(members.count) members" : "\(shown.count) found").siteLabel(10).monospacedDigit()
                        if searchFailed { SiteEmpty(title: "The search did not answer", detail: "Try again in a moment.") }
                        else if shown.isEmpty { SiteEmpty(title: found == nil ? "No members listed yet." : "No member by that name.") }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(shown) { m in
                                Button { state.memberHandle = m.handle } label: {
                                    HStack(spacing: 8) {
                                        GlyphMark(glyph: m.glyph, color: StorefrontColor.hex(m.brandColor) ?? Bone.gold, size: 20)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text("@\(m.handle)").font(SiteFont.body(13)).foregroundStyle(Bone.ink(scheme)).lineLimit(1)
                                            if let t = m.tier { Text(t.tierWord).siteLabel(9) }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14).frame(minHeight: 52).background(Bone.raised(scheme), in: Capsule())
                                    .overlay { Capsule().strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                                }.buttonStyle(.plain).accessibilityLabel("@\(m.handle), \(m.tier?.tierWord ?? "")")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .siteScreen()
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .onChange(of: query) { _, q in if q.isEmpty { found = nil; searchFailed = false } }
    }

    private func load() async {
        do { members = try await Site.get("api/members/directory", DirectoryReply.self).members; loaded = true; failure = nil }
        catch { if !loaded { failure = error.localizedDescription } }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { found = nil; searchFailed = false; return }
        if let r = try? await Site.get("api/search", SearchReply.self, query: ["q": q]) { found = r.members ?? []; searchFailed = false } else { found = []; searchFailed = true }
    }
}

// MARK: - A member's page

/// A member's page, pushed from the room, the stream or the directory.
struct MemberView: View {
    let handle: String
    @Bindable var state: CongregationModel

    var body: some View {
        ScrollView {
            MemberHub(handle: handle, state: state).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 40)
        }
        .siteScreen()
        .navigationTitle("@\(handle)").navigationBarTitleDisplayMode(.inline)
    }
}

/// The site's member hub: Profile and Posts for everyone, and for the owner Boards, Settings, Social, Games and Ask.
struct MemberHub: View {
    let handle: String
    @Bindable var state: CongregationModel
    @State private var tabIndex = 0
    @State private var profile: PublicProfile?
    @State private var chosen: [ChosenWork] = []
    @State private var loaded = false
    @State private var desire = false
    @Environment(\.colorScheme) private var scheme
    private let account = SiteAccount.shared

    private var isOwner: Bool { account.signedIn && account.me?.handle == handle }
    private var titles: [String] { isOwner ? ["Profile", "Posts", "Boards", "Settings", "Social", "Games", "Ask"] : ["Profile", "Posts"] }
    private var tab: String { titles[min(tabIndex, titles.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SiteSegment(titles: titles, index: $tabIndex, scrolls: isOwner)
            switch tab {
            case "Profile": profileTab
            case "Posts": MemberPostsView(handle: handle, state: state)
            case "Boards": BoardsPanel()
            case "Settings": SettingsPanel(handle: handle, onSaved: { Task { await loadProfile() } })
            case "Social": SocialPanel(state: state, showDesire: { desire = true })
            case "Games": GamesPanel()
            default: AskPanel()
            }
            VStack(spacing: 10) {
                Text("What persists in the mind becomes your reality.").plHand(19).foregroundStyle(Bone.inkFaint(scheme)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.top, 20)
        }
        .task { await loadProfile() }
        .onAppear { landOnHubTab() }
        .onChange(of: state.hubTab) { _, _ in landOnHubTab() }
        .sheet(isPresented: $desire) { DesireSheet() }
        .animation(.snappy, value: tabIndex)
    }

    /// A link, Siri or Spotlight asked for one of the owner's tabs by name.
    private func landOnHubTab() {
        guard let t = state.hubTab, let i = titles.firstIndex(of: t) else { return }
        tabIndex = i; state.hubTab = nil
    }

    private func loadProfile() async {
        if let (p, c) = await ProfileReader.read(handle) { profile = p; chosen = c }
        else if profile == nil {
            // the page could not be read: what the directory and the account already say, with no climb to show
            if isOwner, let me = account.me {
                profile = PublicProfile(handle: handle, firstName: me.firstName, glyph: me.glyph, tier: me.pointsTier, brandColor: me.brandColor, points: me.points ?? 0, memberSince: nil, isFounder: me.isFounder == true, founderBadge: false)
            } else if let m = (try? await Site.get("api/members/directory", DirectoryReply.self))?.members.first(where: { $0.handle == handle }) {
                profile = PublicProfile(handle: handle, firstName: nil, glyph: m.glyph, tier: m.tier, brandColor: m.brandColor, points: 0, memberSince: nil, isFounder: false, founderBadge: false)
            }
        }
        loaded = true
    }

    @ViewBuilder private var profileTab: some View {
        if let p = profile { ProfileFace(profile: p, chosen: chosen, state: state) }
        else if loaded { SiteEmpty(title: "No member by that name", detail: "That page is not in the room.") }
        else { SitePulse() }
    }
}

private let nextTier: [String: (label: String, at: Int)] = ["none": ("Initiate", 150), "initiate": ("Aligned", 800), "aligned": ("Kin", 2500)]

/// The public face: identity, the climb, the chosen works.
struct ProfileFace: View {
    let profile: PublicProfile
    let chosen: [ChosenWork]
    @Bindable var state: CongregationModel
    @State private var web: WebPage?
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { StorefrontColor.hex(profile.brandColor) ?? Bone.gold }
    private var tierLabel: String {
        if profile.isFounder { return "The Founder" }
        switch profile.tier ?? "none" { case "initiate": return "Initiate"; case "aligned": return "Aligned"; case "kin": return "Kin"; default: return "In the room" }
    }
    private var since: String? { Date.pl(profile.memberSince).map { $0.formatted(.dateTime.month(.wide).year()) } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                AvatarMark(glyph: profile.glyph, color: accent, size: 112, founder: profile.isFounder)
                Text("@\(profile.handle)").font(SiteFont.display(32)).foregroundStyle(Bone.ink(scheme)).padding(.top, 14)
                if let n = profile.firstName, !n.isEmpty { Text(n).font(SiteFont.body(16)).foregroundStyle(Bone.inkSoft(scheme)) }
                Text(tierLabel).font(SiteFont.body(11, relativeTo: .caption, weight: .medium)).textCase(.uppercase).tracking(3).foregroundStyle(accent).padding(.top, 4)
                if profile.founderBadge && !profile.isFounder { Text("Founding Member").siteLabel(10).foregroundStyle(Bone.goldDim) }
                if let s = since { Text("In the congregation since \(s)").siteLabel(10).multilineTextAlignment(.center) }
                if !profile.isFounder { FollowBar(handle: profile.handle, accent: accent).padding(.top, 12) }
            }
            .frame(maxWidth: .infinity)
            if !profile.isFounder { climb.padding(.top, 36) }
            if !chosen.isEmpty {
                VStack(spacing: 14) {
                    Text("Chosen works").siteLabel(11)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(chosen) { f in
                            Button { if let u = Site.page("catalogue/\(f.cr.lowercased())") { web = WebPage(u) } } label: {
                                Color(Bone.raised(scheme)).aspectRatio(1, contentMode: .fit).overlay {
                                    AsyncImage(url: URL(string: f.thumb)) { p in if case .success(let i) = p { i.resizable().scaledToFill() } else { Color.clear } }
                                }.clipped().overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
                            }.buttonStyle(.plain).accessibilityLabel(f.title ?? f.cr)
                        }
                    }
                }.padding(.top, 36)
            }
        }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    /// The climb: points, a thin bar in the member's colour, and what is left to the next tier.
    private var climb: some View {
        let next = nextTier[profile.tier ?? "none"]
        let pct = next.map { min(1, Double(profile.points) / Double($0.at)) } ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("The climb").siteLabel(11)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(profile.points.formatted()).font(SiteFont.display(26)).foregroundStyle(Bone.ink(scheme)).monospacedDigit().contentTransition(.numericText())
                    Text("pts").font(SiteFont.body(13)).foregroundStyle(Bone.inkFaint(scheme))
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Bone.line(scheme))
                    Rectangle().fill(accent).frame(width: g.size.width * pct)
                }
            }.frame(height: 4)
            Text(next.map { "\(($0.at - profile.points).formatted()) to \($0.label)." } ?? "The summit. Kin.").font(SiteFont.body(12)).foregroundStyle(Bone.inkSoft(scheme))
        }
        .siteCard(padding: 22, radius: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Followers, following, and Follow for a signed-in viewer who is not the owner. Optimistic.
struct FollowBar: View {
    let handle: String
    let accent: Color
    struct Counts: Decodable { let followers: Int; let following: Int; let isFollowing: Bool }
    @State private var counts: Counts?
    @State private var busy = false
    @State private var line: String?
    @Environment(\.colorScheme) private var scheme
    private let account = SiteAccount.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                let c = counts
                (Text("\(c?.followers ?? 0)").font(SiteFont.body(13, weight: .semibold)).foregroundColor(Bone.ink(scheme)) + Text(" follower\(c?.followers == 1 ? "" : "s")").font(SiteFont.body(13)).foregroundColor(Bone.inkSoft(scheme)))
                (Text("\(c?.following ?? 0)").font(SiteFont.body(13, weight: .semibold)).foregroundColor(Bone.ink(scheme)) + Text(" following").font(SiteFont.body(13)).foregroundColor(Bone.inkSoft(scheme)))
                if account.signedIn, account.me?.handle != handle, let c {
                    Button { Task { await toggle() } } label: {
                        Text(c.isFollowing ? "Following \u{2713}" : "Follow").font(SiteFont.body(11, relativeTo: .caption, weight: .medium)).textCase(.uppercase).tracking(2)
                            .foregroundStyle(c.isFollowing ? Bone.inkFaint(scheme) : accent).padding(.horizontal, 16).frame(minHeight: 40)
                            .overlay { Capsule().strokeBorder(c.isFollowing ? Bone.line(scheme) : accent, lineWidth: 0.9) }
                    }.buttonStyle(.plain).disabled(busy)
                }
            }
            SiteNote(text: line)
        }
        .sensoryFeedback(PLHaptic.commit, trigger: counts?.isFollowing)
        .task { counts = try? await Site.get("api/follow", Counts.self, query: ["handle": handle]) }
    }

    private func toggle() async {
        guard let before = counts else { return }
        busy = true
        counts = Counts(followers: before.followers + (before.isFollowing ? -1 : 1), following: before.following, isFollowing: !before.isFollowing)
        do {
            let r = try await Site.post("api/follow", ["handle": handle])
            if let o = r.json, let n = o["followers"] as? Int, let b = o["isFollowing"] as? Bool { counts = Counts(followers: n, following: (o["following"] as? Int) ?? before.following, isFollowing: b) }
            line = nil
        } catch { counts = before; line = "Not saved. \(error.localizedDescription)" }
        busy = false
    }
}

/// A member's published posts, read-only here (the room is where they are answered).
struct MemberPostsView: View {
    let handle: String
    @Bindable var state: CongregationModel
    struct Post: Decodable, Identifiable { let id: String; let body: String; let mediaUrl: String?; let glyph: String?; let createdAt: String? }
    private struct Posts: Decodable { let posts: [Post] }
    @State private var posts: [Post]?
    @State private var failure: String?
    @State private var web: WebPage?
    @State private var lightbox: LightboxItem?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let posts {
                if posts.isEmpty { SiteEmpty(title: "Nothing posted to the room yet.") }
                ForEach(posts) { p in
                    VStack(alignment: .leading, spacing: 10) {
                        if let d = Date.pl(p.createdAt) { Text(d.formatted(.dateTime.month(.wide).day())).siteLabel(10) }
                        LinkedText(text: p.body, size: 18, onMember: { state.memberHandle = $0 }, onWeb: { web = WebPage($0) })
                        if let m = p.mediaUrl, !m.isEmpty { PostMediaView(media: m, onOpen: { lightbox = LightboxItem(src: $0, caption: "") }, onWeb: { web = WebPage($0) }) }
                        SiteRule().padding(.top, 8)
                    }
                }
            } else if let failure { SiteEmpty(title: "Could not load their posts", detail: failure, actionTitle: "Try again") { Task { await load() } } }
            else { SitePulse() }
        }
        .task { await load() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .fullScreenCover(item: $lightbox) { Lightbox(item: $0) }
    }

    private func load() async {
        do { posts = try await Site.get("api/congregation/posts", Posts.self, query: ["handle": handle]).posts; failure = nil }
        catch { if posts == nil { failure = error.localizedDescription } }
    }
}

// MARK: - The owner's Social, Games and Ask

/// The Social tab: the wall's door, the room, and PL Games, in the site's words.
struct SocialPanel: View {
    @Bindable var state: CongregationModel
    let showDesire: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text("State your reality").siteLabel(11)
                Text("Name a desire in the present tense and the wall holds it, anonymously or in your name.").siteBody(14)
                Button(action: showDesire) { Text("Speak it \u{2192}") }.buttonStyle(SitePill())
            }
            SiteRule()
            VStack(alignment: .leading, spacing: 12) {
                Text("The room").siteLabel(11)
                HStack(spacing: 10) {
                    Button { state.tab = .room } label: { Text("Open the room") }.buttonStyle(SiteGhost())
                    Button { state.tab = .stream } label: { Text("The stream") }.buttonStyle(SiteGhost())
                }
            }
        }
    }
}

/// The door to PL Games: the hub is reached with a short-lived play token the site mints for the signed-in member.
struct GamesPanel: View {
    struct Game: Decodable, Identifiable { let id: String; let title: String; let plays: Int? }
    private struct Roster: Decodable { let games: [Game]; let totalPlays: Int?; let players: Int? }
    @State private var roster: Roster?
    @State private var web: WebPage?
    @State private var line: String?
    @State private var opening = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 12) {
                Text("PL Games").siteLabel(11)
                Text("The room has a table.").font(SiteFont.display(26)).foregroundStyle(Bone.ink(scheme))
                Text("Enter the games carrying your mark. Every play earns the climb.").siteBody(14).multilineTextAlignment(.center)
                Button { Task { await enter() } } label: { Text(opening ? "Opening\u{2026}" : "Enter PL Games \u{2192}") }.buttonStyle(SitePill(gold: true)).frame(maxWidth: 280).disabled(opening)
                SiteNote(text: line)
            }
            .frame(maxWidth: .infinity).siteCard(padding: 26, radius: 20)
            if let r = roster {
                HStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 2) { Text("\(r.games.count)").font(SiteFont.display(21)).foregroundStyle(Bone.ink(scheme)); Text("games").siteLabel(10) }
                    VStack(alignment: .leading, spacing: 2) { Text((r.totalPlays ?? 0).formatted()).font(SiteFont.display(21)).foregroundStyle(Bone.ink(scheme)); Text("plays").siteLabel(10) }
                    VStack(alignment: .leading, spacing: 2) { Text((r.players ?? 0).formatted()).font(SiteFont.display(21)).foregroundStyle(Bone.ink(scheme)); Text("players").siteLabel(10) }
                }
                VStack(spacing: 0) {
                    ForEach(Array(r.games.enumerated()), id: \.element.id) { i, g in
                        HStack {
                            Text(g.title).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
                            Spacer()
                            if let p = g.plays, p > 0 { Text("\(p)").siteLabel(10).monospacedDigit() }
                        }
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        if i < r.games.count - 1 { SiteRule() }
                    }
                }
                .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
            }
        }
        .task { roster = try? await Site.get("api/games/list", Roster.self) }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func enter() async {
        opening = true
        defer { opening = false }
        if let url = await Site.redirectTarget("api/games/launch") { web = WebPage(url); line = nil }
        else { line = "Not opened. The site did not hand over a play token. Sign in again and try once more." }
    }
}

/// "Ask the Founder": a private line to him. For him, member messages are in House.
struct AskPanel: View {
    var body: some View {
        if SiteAccount.shared.isFounder {
            SiteEmpty(title: "Member messages are in House", detail: "Open House, then Support, to read and answer them.")
        } else { MessagesPanel(title: "Ask the Founder") }
    }
}

// MARK: - Redirects

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension Site {
    /// Where a signed-in route sends the browser (the games launch mints a token and redirects): the redirect's address, not followed.
    static func redirectTarget(_ path: String) async -> URL? {
        guard let token = SiteAccount.shared.token, let url = page(path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.setValue("pl_session=\(token)", forHTTPHeaderField: "cookie")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: req), let http = response as? HTTPURLResponse,
              (300..<400).contains(http.statusCode), let loc = http.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: loc, relativeTo: url)?.absoluteURL
    }
}
