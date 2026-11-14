import SwiftUI

/// `/tag/<tag>` (`app/tag/[tag]/page.tsx`): every published congregation post carrying #tag, newest first. The page reads
/// D1 on the server and has no JSON route yet, so this reads the live page's articles (kept for offline). Opened by
/// `pldev://section/shop/tag/<tag>`; the congregation's hashtag links point here once the lead swaps them (LANES-site.md).
struct SiteTagView: View {
    let tag: String
    @State private var posts: [Post] = []
    @State private var loaded = false
    @State private var failed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    struct Post: Hashable { let handle: String?; let date: String; let body: String; let media: URL? }

    private var clean: String { tag.lowercased().filter { $0.isLetter || $0.isNumber }.filter(\.isASCII) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("The congregation \u{00B7} tag").siteTag(11, Bone.gold)
                Text("#\(clean)").font(SiteFont.display(40)).foregroundStyle(Bone.ink(scheme)).padding(.top, 4).padding(.bottom, 28).accessibilityAddTraits(.isHeader)
                if !loaded { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
                else if failed { EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the tag", detail: "The site did not answer and this tag has not been saved yet. Pull to try again.") }
                else if posts.isEmpty { Text("Nothing tagged #\(clean) yet.").siteBody(16).padding(.vertical, 32) }
                else {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(posts, id: \.self) { p in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Text(p.handle.map { "@" + $0 } ?? "The Founder").siteLabel(10)
                                    Text("\u{00B7} \(p.date)").siteLabel(10)
                                }
                                Text(p.body).font(SiteFont.display(19)).foregroundStyle(Bone.ink(scheme)).lineSpacing(4).textSelection(.enabled)
                                if let m = p.media {
                                    AsyncImage(url: m) { ph in
                                        if case .success(let i) = ph { i.resizable().scaledToFit() } else { Rectangle().fill(Bone.line(scheme)).frame(height: 200) }
                                    }
                                    .overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.6) }
                                    .accessibilityLabel(String(p.body.prefix(140)))
                                }
                                SiteRule().padding(.top, 14)
                            }
                        }
                    }
                }
                Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: { SiteDoorLabel(title: "\u{2190} The Congregation", gold: true) }
                    .buttonStyle(.plain).padding(.top, 32)
            }
            .padding(.horizontal, 24).padding(.vertical, 24)
        }
        .siteScreen()
        .plScreenTitle("#\(clean)")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard !clean.isEmpty else { loaded = true; return }
        guard let html = await SiteData.html("tag/\(clean)") else { failed = true; loaded = true; return }
        posts = Self.parse(html); failed = false; loaded = true
    }

    nonisolated static func parse(_ html: String) -> [Post] {
        SiteData.matches("<article[^>]*>(.*?)</article>", in: html).compactMap { a in
            let inner = a[0]
            guard let body = SiteData.matches(#"<p class="font-display[^"]*">(.*?)</p>"#, in: inner).first?.first else { return nil }
            let handle = SiteData.matches(#"href="/member/([^"]+)""#, in: inner).first?.first
            let date = SiteData.matches(#"· (?:<!-- -->)?([^<]+)</span>"#, in: inner).first?.first ?? ""
            let media = SiteData.matches(#"<img[^>]*src="([^"]+)""#, in: inner).first?.first.flatMap { URL(string: SiteHTML.text($0)) }
            return Post(handle: handle.map { SiteHTML.text($0) }, date: SiteHTML.text(date), body: SiteHTML.text(body), media: media?.scheme == "https" ? media : nil)
        }
    }
}
