import SwiftUI

// The Chosen (`app/chosen/page.tsx`, `components/catalogue/ChosenSection.tsx`): every requested piece the founder made real,
// numbered and permanent. The site reads it from D1 in a server action and has no JSON route for it yet, so this reads the
// live /chosen page itself (the same rows the site prints) and keeps the copy for offline. A JSON route is asked for in
// LANES-site.md; when it lands, only `ChosenStore.load` changes.

struct ChosenEntry: Hashable, Identifiable {
    let no: Int
    let cr: String
    let product: String
    let date: String
    let wearURL: URL?
    var id: Int { no }
    var productText: String { product.replacingOccurrences(of: "_", with: " ") }
    var padded: String { String(format: "%03d", no) }
}

@MainActor @Observable final class ChosenStore {
    static let shared = ChosenStore()
    var entries: [ChosenEntry] = []
    var loaded = false
    var failed = false

    func load(force: Bool = false) async {
        if loaded && !force { return }
        guard let html = await SiteData.html("chosen") else { failed = !loaded; return }
        entries = Self.parse(html); loaded = true; failed = false
    }

    func entry(_ cr: String) -> ChosenEntry? { entries.first { $0.cr == cr } }

    /// `Chosen — №{n}` · `/catalogue#{cr}` · product · date · optional "Wear it" link.
    nonisolated static func parse(_ html: String) -> [ChosenEntry] {
        let rows = SiteData.matches(#"Chosen — №(?:<!-- -->)?(\d+)</span>\s*<a[^>]{0,300}?href="/catalogue#([^"]+)"[^>]*>[^<]*</a>\s*<span[^>]*>([^<]*)</span>\s*<span[^>]*>([^<]*)</span>(?:\s*<a[^>]{0,40}?href="([^"]+)")?"#, in: html)
        var seen = Set<Int>()
        return rows.compactMap { r in
            guard let n = Int(r[0]), seen.insert(n).inserted else { return nil }
            let wear = r.count > 4 && !r[4].isEmpty ? URL(string: SiteHTML.text(r[4])) : nil
            return ChosenEntry(no: n, cr: SiteHTML.text(r[1]), product: SiteHTML.text(r[2]), date: String(SiteHTML.text(r[3]).prefix(10)), wearURL: wear?.scheme == "https" ? wear : nil)
        }
        .sorted { $0.no < $1.no }
    }
}

/// `/chosen`: You desire, *and you receive.*
struct ChosenView: View {
    private let store = ChosenStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("The Archive \u{2014} The Chosen").siteLabel()
                    SiteDisplay(parts: [("You desire, ", false), ("and you receive.", true)], size: 46)
                    Text("Every piece in the catalogue can be requested. Some are chosen, and brought to reality. This is the record \u{2014} numbered, permanent. The congregation\u{2019}s taste, written in objects.")
                        .siteBody(16)
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 40)
                Group {
                    if !store.loaded && !store.failed { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
                    else if store.failed {
                        EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the record", detail: "The site did not answer and the record has not been saved yet. Pull to try again.")
                    } else if store.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("The line is open. The first chosen piece will stand here, numbered \u{2116}1, permanently.")
                                .font(SiteFont.display(24, italic: true)).foregroundStyle(Bone.inkSoft(scheme)).lineSpacing(3)
                            NavigationLink { ArchiveView(model: .shared) } label: { Text("Walk the catalogue \u{2192}") }.buttonStyle(SiteGhost()).fixedSize()
                        }
                    } else {
                        VStack(spacing: 0) {
                            SiteRule()
                            ForEach(store.entries) { e in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Chosen \u{2014} \u{2116}\(e.no)").font(SiteFont.display(24)).foregroundStyle(Bone.gold)
                                    HStack(spacing: 14) {
                                        NavigationLink { ChosenWork(cr: e.cr) } label: { Text(e.cr).font(SiteFont.body(14)).foregroundStyle(Bone.ink(scheme)) }.buttonStyle(.plain)
                                        Text(e.productText).siteBody(14)
                                        Text(e.date).font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme))
                                    }
                                    if let u = e.wearURL { Button { openURL(u) } label: { SiteDoorLabel(title: "Wear it \u{2192}") }.buttonStyle(.plain) }
                                }
                                .padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
                                SiteRule()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                VStack(spacing: 22) {
                    SiteRule()
                    Text("The congregation chooses the work. What persists, arrives.").font(SiteFont.display(26, italic: true)).foregroundStyle(Bone.ink(scheme))
                        .multilineTextAlignment(.center).padding(.top, 40)
                    SiteWatch()
                }
                .padding(.horizontal, 24).padding(.vertical, 40)
            }
        }
        .siteScreen()
        .plScreenTitle("The Chosen")
        .task { await store.load() }
        .refreshable { await store.load(force: true) }
    }
}

/// A chosen work opened in the archive's own page (stepping through the chosen line).
private struct ChosenWork: View {
    let cr: String
    var body: some View {
        let ids = ChosenStore.shared.entries.map(\.cr)
        ArchiveEntryView(ids: ids.isEmpty ? [cr] : ids, start: max(0, ids.firstIndex(of: cr) ?? 0), lab: false)
    }
}

/// `ChosenSection` on the archive page: the line as numbered cells, then the door to the full register.
struct ChosenStrip: View {
    private let store = ChosenStore.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("From The Chosen").siteLabel()
            Text(store.entries.isEmpty ? "The line is open. The first chosen piece will stand here, numbered \u{2116}1." : "The congregation requested these. The founder made them. The work answers.")
                .siteBody(14)
            if !store.entries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(store.entries) { e in
                            NavigationLink { ChosenWork(cr: e.cr) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("No. \(e.padded)").font(.system(size: 11, design: .monospaced)).tracking(2).foregroundStyle(Bone.gold)
                                    Text(e.cr).font(SiteFont.display(18)).foregroundStyle(Bone.ink(scheme))
                                    Text(e.productText.capitalized).font(SiteFont.body(12)).foregroundStyle(Bone.inkSoft(scheme))
                                }
                                .padding(20).frame(width: 170, alignment: .leading).background(Bone.ground(scheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Bone.line(scheme))
                }
            }
            NavigationLink { ChosenView() } label: { SiteDoorLabel(title: "The full Chosen register \u{2192}") }.buttonStyle(.plain)
        }
        .task { await store.load() }
    }
}
