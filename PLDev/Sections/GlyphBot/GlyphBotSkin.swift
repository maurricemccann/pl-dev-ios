import SwiftUI

/// GlyphBot's own skin (his look ruling 11-13). The Oracle room lives in pl-os, so it wears pl-os's tokens (`PLOS` in House's skin):
/// the console ground, mono labels at 0.18 em, philosophy purple on the room's name, gold on the user's words. Bubbles are
/// `GlyphRoom.tsx`: his words `bg-gold/15` with a `border-gold/30` hairline and a squared lower-right corner; the room's
/// `bg-surface-2` with the line border and a squared lower-left corner; a `›` prompt line at the bottom.
extension View {
    /// A List or Form on the pl-os console ground, rows as the console's raised surface.
    func glyphList() -> some View { modifier(GlyphList()) }
}

private struct GlyphList: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { PLOS.bg(scheme).ignoresSafeArea() }
            .listRowBackground(PLOS.surface(scheme).opacity(0.8))
            .listRowSeparatorTint(PLOS.line(scheme))
            .tint(PLOS.gold)
    }
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
            .background { GlyphBubbleShape(mine: mine).fill(mine ? PLOS.gold.opacity(0.15) : PLOS.surface2(scheme)) }
            .overlay { GlyphBubbleShape(mine: mine).stroke(mine ? PLOS.gold.opacity(0.30) : PLOS.line(scheme), lineWidth: 0.8) }
    }
}

/// His own words in the room.
struct GlyphUserBubble: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            GlyphBubble(mine: true) { Text(text).font(.system(size: 14)).foregroundStyle(PLOS.text(scheme)).lineSpacing(3).textSelection(.enabled) }
        }
        .accessibilityElement(children: .combine).accessibilityLabel("You: \(text)")
    }
}

/// `GlyphBot · Oracle` and the online dot, mono, the pl-os header of the room, above the tabs.
struct GlyphTabs: View {
    let titles: [String]
    @Binding var index: Int
    var online: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("GlyphBot \u{00B7} Oracle").osEyebrow(11).foregroundStyle(PLOS.philosophy)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(online ? PLOS.ok : Color(hex: 0xb08948)).frame(width: 6, height: 6)
                    Text(online ? "online" : "offline").osEyebrow(9).foregroundStyle(PLOS.dim(scheme))
                }
            }
            HStack(spacing: 6) {
                ForEach(titles.indices, id: \.self) { i in
                    Button { withAnimation(.snappy) { index = i } } label: {
                        Text(titles[i]).osEyebrow(10).foregroundStyle(index == i ? Color.black : PLOS.dim(scheme))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background { if index == i { Capsule().fill(PLOS.gold) } }
                            .overlay { Capsule().strokeBorder(index == i ? Color.clear : PLOS.line(scheme), lineWidth: 0.8) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == i ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(PLOS.bg(scheme).opacity(0.94))
        .overlay(alignment: .bottom) { Rectangle().fill(PLOS.line(scheme)).frame(height: 0.6) }
    }
}
