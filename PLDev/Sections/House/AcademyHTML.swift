import Foundation

/// The Academy's reader page, as blocks. The Worker renders each canon document with `marked` into `<article class="doc">`; this turns that
/// markup back into native pieces (headings, paragraphs, quotes, lists, tables, code) so no page is loaded in a web view. It handles the
/// tags the 71 documents actually use: h1-h4, p, em, strong, code, a, span, hr, ul, ol, li, blockquote, table. Images are left out.
enum AcademyBlock {
    case heading(Int, String)
    case para(String)
    case quote(String)
    case item(String, depth: Int, mark: String)
    case code(String)
    case rule
    case table([[String]])
}

enum AcademyHTML {
    static func blocks(fromPage html: String) -> [AcademyBlock] {
        guard let open = html.range(of: "<article class=\"doc\">") else { return [] }
        let rest = html[open.upperBound...]
        let body = rest.range(of: "</article>").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        return parse(body)
    }

    static func title(fromPage html: String) -> String? {
        guard let r = html.range(of: "<article class=\"doc\">") else { return nil }
        let rest = html[r.upperBound...]
        guard let a = rest.range(of: "<h1>"), let b = rest.range(of: "</h1>") else { return nil }
        return decode(String(rest[a.upperBound..<b.lowerBound]))
    }

    static func decode(_ s: String) -> String {
        var t = s
        for (k, v) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " ")] { t = t.replacingOccurrences(of: k, with: v) }
        return t
    }

    /// Markdown's own punctuation in plain text would be read as formatting, so it is escaped before the inline marks are added.
    private static func escape(_ s: String) -> String {
        var out = ""
        for c in s { if "\\*_[]`~".contains(c) { out.append("\\") }; out.append(c) }
        return out
    }

    static func parse(_ html: String) -> [AcademyBlock] {
        var out: [AcademyBlock] = []
        var buf = ""
        var quoteDepth = 0
        var lists: [(ordered: Bool, n: Int)] = []
        var headingLevel: Int?
        var liOpen = false
        var rows: [[String]] = []
        var row: [String] = []
        var inCell = false
        var inPre = false
        var pre = ""
        var hrefs: [String] = []

        func flush(as kind: String) {
            let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            buf = ""
            guard !t.isEmpty else { return }
            switch kind {
            case "h": out.append(.heading(headingLevel ?? 2, t))
            case "q": out.append(.quote(t))
            case "li":
                let l = lists.last
                out.append(.item(t, depth: max(0, lists.count - 1), mark: l?.ordered == true ? "\(l!.n)." : "\u{2022}"))
            default: out.append(.para(t))
            }
        }

        let scanner = Scanner(string: html)
        scanner.charactersToBeSkipped = nil
        while !scanner.isAtEnd {
            if scanner.scanString("<") != nil {
                guard let tag = scanner.scanUpToString(">") else { break }
                _ = scanner.scanString(">")
                let closing = tag.hasPrefix("/")
                let name = tag.dropFirst(closing ? 1 : 0).prefix { $0.isLetter || $0.isNumber }.lowercased()
                if inPre && !(closing && name == "pre") { continue }   // markup inside a code block is dropped; its text is kept below
                switch (closing, name) {
                case (false, "h1"), (false, "h2"), (false, "h3"), (false, "h4"), (false, "h5"):
                    flush(as: quoteDepth > 0 ? "q" : "p"); headingLevel = Int(String(name.dropFirst())) ?? 2
                case (true, "h1"), (true, "h2"), (true, "h3"), (true, "h4"), (true, "h5"): flush(as: "h"); headingLevel = nil
                case (false, "p"): if !liOpen && !inCell { flush(as: quoteDepth > 0 ? "q" : "p") }
                case (true, "p"):
                    if inCell { buf += " " }
                    else if liOpen { buf += "\n" }
                    else { flush(as: quoteDepth > 0 ? "q" : "p") }
                case (false, "br"), (false, "br/"): buf += "\n"
                case (false, "ul"): flush(as: "li"); lists.append((false, 0))
                case (false, "ol"): flush(as: "li"); lists.append((true, 0))
                case (true, "ul"), (true, "ol"): if liOpen { flush(as: "li"); liOpen = false }; if !lists.isEmpty { lists.removeLast() }
                case (false, "li"):
                    if liOpen { flush(as: "li") }
                    if !lists.isEmpty { lists[lists.count - 1].n += 1 }
                    liOpen = true
                case (true, "li"): flush(as: "li"); liOpen = false
                case (false, "blockquote"): flush(as: "p"); quoteDepth += 1
                case (true, "blockquote"): flush(as: "q"); quoteDepth = max(0, quoteDepth - 1)
                case (false, "hr"), (false, "hr/"): flush(as: "p"); out.append(.rule)
                case (false, "pre"): flush(as: "p"); inPre = true; pre = ""
                case (true, "pre"): inPre = false; if !pre.isEmpty { out.append(.code(pre.trimmingCharacters(in: .newlines))) }
                case (false, "strong"), (false, "b"), (true, "strong"), (true, "b"): buf += "**"
                case (false, "em"), (false, "i"), (true, "em"), (true, "i"): buf += "*"
                case (false, "code"): buf += "`"
                case (true, "code"): buf += "`"
                case (false, "a"):
                    if let r = tag.range(of: "href=\""), let e = tag[r.upperBound...].firstIndex(of: "\"") { hrefs.append(decode(String(tag[r.upperBound..<e]))) } else { hrefs.append("") }
                    buf += "["
                case (true, "a"):
                    let h = hrefs.popLast() ?? ""
                    buf += h.hasPrefix("http") ? "](\(h))" : "]()"
                case (false, "table"): flush(as: "p"); rows = []
                case (false, "tr"): row = []
                case (true, "tr"): if !row.isEmpty { rows.append(row) }
                case (false, "th"), (false, "td"): inCell = true; buf = ""
                case (true, "th"), (true, "td"): row.append(buf.trimmingCharacters(in: .whitespacesAndNewlines)); buf = ""; inCell = false
                case (true, "table"): if !rows.isEmpty { out.append(.table(rows)) }; rows = []
                default: break
                }
            } else if let text = scanner.scanUpToString("<") {
                if inPre { pre += decode(text) } else { buf += escape(decode(text)) }
            }
        }
        flush(as: "p")
        // "[]()" from a link that went nowhere, and empty emphasis marks, are removed
        return out.map { b in
            func clean(_ s: String) -> String { s.replacingOccurrences(of: "[]()", with: "").replacingOccurrences(of: "****", with: "") }
            switch b {
            case .para(let s): return .para(clean(s))
            case .quote(let s): return .quote(clean(s))
            case .item(let s, let d, let m): return .item(clean(s), depth: d, mark: m)
            default: return b
            }
        }
    }

    /// The curriculum, from the Worker's home page (it has no JSON list): sections with their documents in the Worker's own order.
    struct Doc: Identifiable, Hashable { let key: String; let name: String; var id: String { key } }
    struct Section: Identifiable, Hashable { let id: String; let title: String; let blurb: String; let docs: [Doc] }

    static func curriculum(fromHome html: String) -> [Section] {
        var out: [Section] = []
        let parts = html.components(separatedBy: "<div class=\"section\" data-section-id=\"").dropFirst()
        for p in parts {
            guard let idEnd = p.firstIndex(of: "\"") else { continue }
            let id = String(p[..<idEnd])
            func between(_ a: String, _ b: String) -> String {
                guard let x = p.range(of: a), let y = p[x.upperBound...].range(of: b) else { return "" }
                return decode(String(p[x.upperBound..<y.lowerBound]))
            }
            let title = between("<h2>", "</h2>")
            let blurb = between("<p class=\"blurb\">", "</p>")
            var docs: [Doc] = []
            var rest = Substring(p)
            while let a = rest.range(of: "<li><a href=\"/read?k=") {
                let after = rest[a.upperBound...]
                guard let q = after.firstIndex(of: "\"") else { break }
                let encoded = String(after[..<q])
                let key = encoded.removingPercentEncoding ?? encoded
                var name = key.split(separator: "/").last.map(String.init) ?? key
                if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
                docs.append(Doc(key: key, name: name))
                rest = after[q...]
            }
            if !docs.isEmpty { out.append(Section(id: id, title: title, blurb: blurb, docs: docs)) }
        }
        return out
    }
}
