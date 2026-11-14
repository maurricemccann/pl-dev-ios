import SwiftUI

/// /tag/<tag> as a native page: every published post carrying #tag, newest first (pl-headless `app/tag/[tag]/page.tsx`).
/// A tapped hashtag in any post lands here instead of leaving the app. The page's own query is a D1 `LIKE` that has no JSON route yet,
/// so the view asks `api/congregation/tag?tag=` first (written up in LANES-house.md for the lead to add) and, until that route is
/// live, reads the public room's newest 50 and keeps the posts carrying the tag, so it works today with a shorter reach.
struct TagView: View {
    let tag: String
    @Bindable var state: CongregationModel
    @Environment(\.colorScheme) private var scheme
    private struct Reply: Decodable { let posts: [RoomPost] }
    @State private var posts: [RoomPost]?
    @State private var failure: String?
    @State private var shortReach = false
    @State private var web: WebPage?
    @State private var lightbox: LightboxItem?

    private var clean: String { tag.lowercased().filter { $0.isLetter || $0.isNumber } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The congregation \u{00B7} tag").siteLabel(11)
                    Text("#\(clean)").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme))
                }
                if let posts {
                    if posts.isEmpty { SiteEmpty(title: "Nothing tagged #\(clean) yet.", detail: shortReach ? "This reads the room's newest posts. Older ones may carry it." : nil) }
                    ForEach(posts) { p in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                if let h = p.authorHandle, !h.isEmpty, !p.byFounder {
                                    Button { state.tag = nil; state.memberHandle = h } label: { Text("@\(h)").siteLabel(11) }.buttonStyle(.plain)
                                } else { Text("The Founder").siteLabel(11) }
                                if let d = Date.pl(p.createdAt) { Text("\u{00B7} " + d.formatted(.dateTime.month(.abbreviated).day())).siteLabel(11) }
                            }
                            LinkedText(text: p.body, size: 19, onMember: { state.tag = nil; state.memberHandle = $0 }, onWeb: { web = WebPage($0) })
                            if let m = p.mediaUrl, !m.isEmpty { PostMediaView(media: m, onOpen: { lightbox = LightboxItem(src: $0, caption: "") }, onWeb: { web = WebPage($0) }) }
                            SiteRule().padding(.top, 8)
                        }
                    }
                } else if let failure {
                    SiteEmpty(title: "Could not load this tag", detail: failure, actionTitle: "Try again") { Task { await load() } }
                } else { SitePulse() }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
        }
        .background { SiteGround() }
        .navigationTitle("#\(clean)").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .fullScreenCover(item: $lightbox) { Lightbox(item: $0) }
    }

    private func load() async {
        if let r = try? await Site.get("api/congregation/tag", Reply.self, query: ["tag": clean]) { posts = r.posts; shortReach = false; failure = nil; return }
        do {
            let room = try await Site.get("api/congregation/feed", RoomReply.self)
            let needle = "#" + clean
            posts = room.posts.filter { $0.status != "pending" && $0.body.lowercased().contains(needle) }
            shortReach = true; failure = nil
        } catch { if posts == nil { failure = error.localizedDescription } }
    }
}
