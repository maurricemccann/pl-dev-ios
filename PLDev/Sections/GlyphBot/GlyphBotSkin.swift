import SwiftUI

/// GlyphBot's skin: the Congregation's. His 11-24 ruling was to rebuild GlyphBot like the PL DEV Congregation, so it wears the site's
/// tokens (`Bone`, `SiteFont`, `SiteTabs`, `SiteCard` in the Shop's `SiteSkin.swift`, never edited here) where it wore pl-os's on 11-13.
/// Bubbles keep the room's shape: his words gold-washed with a squared lower-right corner, the room's raised with a squared lower-left.
extension View {
    /// A List or Form on the site's ground, rows as the site's raised cream.
    func glyphList() -> some View { siteList() }
}

/// A bubble with one squared corner, as the room draws them (`rounded-2xl rounded-br-sm` / `rounded-bl-sm`).
struct GlyphBubbleShape: Shape {
    let mine: Bool
    func path(in r: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous).path(in: r)
    }
}

struct GlyphBubble<Content: View>: View {
    let mine: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background { GlyphBubbleShape(mine: mine).fill(mine ? Bone.gold.opacity(0.16) : Bone.raised(scheme)) }
            .overlay { GlyphBubbleShape(mine: mine).stroke(mine ? Bone.gold.opacity(0.35) : Bone.line(scheme), lineWidth: 0.8) }
    }
}

/// His own words in the room.
struct GlyphUserBubble: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            GlyphBubble(mine: true) { Text(text).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme)).lineSpacing(4).textSelection(.enabled) }
        }
        .accessibilityElement(children: .combine).accessibilityLabel("You: \(text)")
    }
}

/// `GlyphBot · Oracle` and the online dot over the site's tabs, as the Congregation's tabs sit under its title.
struct GlyphHeader: View {
    let titles: [String]
    @Binding var index: Int
    var online: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GlyphBot \u{00B7} Oracle").siteLabel(11)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(online ? Bone.teal : Bone.amber).frame(width: 6, height: 6)
                    Text(online ? "online" : "offline").siteLabel(11)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 2)
            SiteTabs(titles: titles, index: $index)
        }
        .background(Bone.ground(scheme).opacity(0.94))
    }
}

/// A raised card with its small tracked title and an optional footnote: the unit the setup screen is built from.
struct GlyphCard<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).siteLabel(11).accessibilityAddTraits(.isHeader)
            content()
            if let note { Text(note).font(SiteFont.body(12, relativeTo: .caption)).foregroundStyle(Bone.inkFaint(scheme)).fixedSize(horizontal: false, vertical: true) }
        }
        .siteCard()
    }
}

/// One row of a card: a label on the left, its control on the right, 44 pt tall.
struct GlyphRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 44)
    }
}
