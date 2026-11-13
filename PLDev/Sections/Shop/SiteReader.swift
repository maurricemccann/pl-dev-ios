import SwiftUI

/// The site's own pages read natively (his ask 11-13, "do all": the static pages were opening in a Safari sheet).
/// The live page is fetched and its main text drawn in the app's type: headings, paragraphs, lists and quotes, always current
/// with the site, no copy of the words kept in this repo. Kept on the phone for offline, like every read. Forms stay on the site.
struct SiteReaderView: View {
    let path: String
    let title: String

    enum Block: Hashable { case heading(String, Int), paragraph(String), item(String), quote(String) }
    @State private var blocks: [Block] = []
    @State private var failed: String?
    @State private var loaded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let failed { ContentUnavailableView("Could not load", systemImage: "wifi.exclamationmark", description: Text(failed)) }
                else if !loaded { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                    switch b {
                    case .heading(let t, let level):
                        // the house's pages are his words: headings in his hand
                        Text(t).font(SiteFont.display(level == 1 ? 34 : level == 2 ? 27 : 22)).foregroundStyle(Bone.ink(scheme)).padding(.top, level == 1 ? 0 : 8)
                    case .paragraph(let t): Text(t).siteBody(16)
                    case .item(let t): HStack(alignment: .firstTextBaseline, spacing: 8) { Text("·").foregroundStyle(Bone.gold); Text(t).siteBody(16) }
                    case .quote(let t): Text(t).font(SiteFont.display(22, italic: true)).foregroundStyle(Bone.ink(scheme)).padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Bone.gold).frame(width: 2) }
                    }
                }
                if loaded, let u = Site.page(path) { Link("Open this page on the site", destination: u).font(.footnote).padding(.top, 12) }
            }
            .padding(24)
            .textSelection(.enabled)
        }
        .siteScreen()
        .plScreenTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let key = "site-page|" + path
        var html: String?
        do {
            let r = try await Site.call("GET", path)
            if (200..<300).contains(r.status) { OfflineCache.save(r.data, for: key); html = String(data: r.data, encoding: .utf8) }
        } catch {}
        if html == nil, let (saved, at) = OfflineCache.load(key) { OfflineState.servedCopy(from: at); html = String(data: saved, encoding: .utf8) }
        guard let html else { failed = "The site did not answer and this page has not been saved yet. Pull to try again."; loaded = true; return }
        blocks = Self.blocks(html); failed = blocks.isEmpty ? "The page had no text to show." : nil; loaded = true
    }

    /// The page's main text in reading order. Script, style, navigation and footer are dropped; inline tags are stripped.
    static func blocks(_ html: String) -> [Block] {
        var s = html
        if let a = s.range(of: "<main"), let b = s.range(of: "</main>", range: a.upperBound..<s.endIndex) { s = String(s[a.lowerBound..<b.upperBound]) }
        for tag in ["script", "style", "nav", "footer", "form", "button", "svg", "noscript"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: "", options: .regularExpression)
        }
        guard let re = try? NSRegularExpression(pattern: "<(h1|h2|h3|h4|p|li|blockquote)\\b[^>]*>([\\s\\S]*?)</\\1>", options: [.caseInsensitive]) else { return [] }
        var out: [Block] = []
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let tr = Range(m.range(at: 1), in: s), let br = Range(m.range(at: 2), in: s) else { continue }
            let text = clean(String(s[br]))
            guard !text.isEmpty else { continue }
            switch s[tr].lowercased() {
            case "h1": out.append(.heading(text, 1))
            case "h2": out.append(.heading(text, 2))
            case "h3", "h4": out.append(.heading(text, 3))
            case "li": out.append(.item(text))
            case "blockquote": out.append(.quote(text))
            default: out.append(.paragraph(text))
            }
        }
        return out
    }

    static func clean(_ inner: String) -> String {
        var t = inner.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“", "&hellip;": "…", "&middot;": "·"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            var r = t
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let whole = Range(m.range, in: t), let hexR = Range(m.range(at: 1), in: t), let numR = Range(m.range(at: 2), in: t),
                      let code = UInt32(t[numR], radix: t[hexR].isEmpty ? 10 : 16), let u = Unicode.Scalar(code), let rr = Range(m.range, in: r) else { continue }
                _ = whole; r.replaceSubrange(rr, with: String(Character(u)))
            }
            t = r
        }
        return t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    }
}
