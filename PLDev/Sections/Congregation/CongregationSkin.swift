import AVKit
import SwiftUI
import WebKit

// The Congregation's own pieces, built on the site's skin (`SiteSkin.swift`, owned by the shop lane, never edited here): the
// member's glyph as the site draws it (the real glyph picture, tinted through its alpha as the site's CSS mask does), the round
// obsidian avatar, the bordered toggle, the hairline text field, the small social pills, linked text (#tags, @handles, links),
// the masonry grid, the lightbox, a video, and the human check the site's forms carry.

// MARK: - Glyphs

struct GlyphDef: Identifiable {
    let key: String
    let label: String
    let img: String
    let minTier: String
    var color = false
    var id: String { key }
}

/// The glyph set and the climb that expands it (pl-headless `lib/glyphs.ts`). The key `smiley` stays; its name is the true one.
enum Glyphs {
    static let all: [GlyphDef] = [
        GlyphDef(key: "smiley", label: "What Goes Around Comes Around", img: "glyphs/smiley.png", minTier: "none"),
        GlyphDef(key: "love-yourself", label: "Love Yourself", img: "glyphs/love-yourself.png", minTier: "none"),
        GlyphDef(key: "money-grin", label: "Money Grin", img: "emblems/money-grin-crop.png", minTier: "none", color: true),
        GlyphDef(key: "money", label: "Money Glyph", img: "glyphs/money.png", minTier: "aligned"),
        GlyphDef(key: "glyph-guy", label: "Glyph Guy", img: "glyphs/glyph-guy.png", minTier: "kin"),
    ]
    static func def(_ key: String?) -> GlyphDef? { all.first { $0.key == key } }
    static func label(_ key: String?) -> String? { def(key)?.label }
    @MainActor static func url(_ key: String?) -> URL? { Site.page(def(key)?.img ?? "glyphs/\(key ?? "smiley").png") }
    static func rank(_ tier: String?) -> Int { ["none": 0, "initiate": 1, "aligned": 2, "kin": 3][tier ?? "none"] ?? 0 }
    static func unlocked(_ minTier: String, tier: String?) -> Bool { rank(tier) >= rank(minTier) }

    /// The brand colours a member can take as their accent (`lib/brand-color.ts`).
    static let palette: [(name: String, hex: String)] = [
        ("House Gold", "#c9a84c"), ("Oxblood", "#5e1622"), ("Amethyst", "#6b4e8f"), ("Verdigris", "#2d8a6e"),
        ("Cobalt", "#3a5f9e"), ("Crimson", "#c0392b"), ("Rose", "#c98fb0"), ("Bronze", "#a9743a"),
    ]
}

enum StorefrontColor {
    /// "#c9a84c" → a colour; nil when it is not a six-digit hex.
    static func hex(_ s: String?) -> Color? {
        guard let s, s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A member's glyph: the site's own picture, tinted through its alpha (a colour glyph keeps its colours).
struct GlyphMark: View {
    let glyph: String?
    var color: Color = Bone.gold
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let url = Glyphs.url(glyph) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        if Glyphs.def(glyph)?.color == true { image.resizable().scaledToFit() }
                        else { image.renderingMode(.template).resizable().scaledToFit().foregroundStyle(color) }
                    } else { Color.clear }
                }
            } else { Color.clear }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The round obsidian avatar of the site: the glyph for a member, his mark for the Founder, a gold dot for someone anonymous.
struct AvatarMark: View {
    var glyph: String? = nil
    var color: Color = Bone.gold
    var size: CGFloat = 36
    var founder = false
    var anon = false

    var body: some View {
        Circle().fill(Color(hex: 0x0e0c08)).frame(width: size, height: size)
            .overlay { Circle().strokeBorder(Bone.gold.opacity(0.4), lineWidth: 0.8) }
            .overlay {
                if founder { Image("PLIcons/house").resizable().scaledToFit().padding(size * 0.28).foregroundStyle(Bone.gold) }
                else if anon || glyph == nil { Circle().fill(Bone.gold.opacity(0.5)).frame(width: 8, height: 8) }
                else { GlyphMark(glyph: glyph, color: color, size: size * 0.45) }
            }
            .accessibilityHidden(true)
    }
}

/// A member's glyph in the round avatar, with the member's own colour (the older name kept for the screens that already use it).
struct GlyphBadge: View {
    let glyph: String?
    var color: String? = nil
    var founder = false
    var size: CGFloat = 36
    var body: some View { AvatarMark(glyph: glyph, color: StorefrontColor.hex(color) ?? Bone.gold, size: size, founder: founder) }
}

extension String {
    /// The climb's tier as the site words it.
    var tierWord: String { self == "none" ? "In the room" : capitalized }
}

// MARK: - Controls

/// The bordered toggle of the site (`The House | Following`, the profile's tabs): ink fill on the chosen one. Many tabs scroll.
struct SiteSegment: View {
    let titles: [String]
    @Binding var index: Int
    var scrolls = false
    @Environment(\.colorScheme) private var scheme

    private func cell(_ i: Int) -> some View {
        Button { withAnimation(.snappy(duration: 0.18)) { index = i } } label: {
            Text(titles[i]).font(SiteFont.body(11, relativeTo: .caption, weight: .medium)).textCase(.uppercase).tracking(2.2)
                .foregroundStyle(index == i ? Bone.ground(scheme) : Bone.inkSoft(scheme))
                .padding(.horizontal, scrolls ? 16 : 6)
                .frame(maxWidth: scrolls ? nil : .infinity, minHeight: 40)
                .background { if index == i { RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Bone.ink(scheme)) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(index == i ? .isSelected : [])
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 2) { ForEach(titles.indices, id: \.self) { cell($0) } } }
            } else {
                HStack(spacing: 2) { ForEach(titles.indices, id: \.self) { cell($0) } }
            }
        }
        .padding(4)
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
    }
}

private struct SiteFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Bone.ground(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
    }
}

extension View {
    /// The site's text field: transparent on the ground, a hairline, Jost.
    func siteField() -> some View { modifier(SiteFieldStyle()) }
}

/// A quiet text action: tracked capitals, no box (`Approve post`, `Speak`, `+ add a visual`).
struct SiteAction: View {
    enum Tone { case gold, faint, danger }
    let title: String
    var tone: Tone = .gold
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title).font(SiteFont.body(11, relativeTo: .caption, weight: .medium)).textCase(.uppercase).tracking(2.4)
                .foregroundStyle(color).frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.4)
    }

    private var color: Color {
        switch tone {
        case .gold: return Bone.goldDim
        case .faint: return Bone.inkFaint(scheme)
        case .danger: return Bone.oxblood
        }
    }
}

/// The small social pill under a post: a hairline capsule, gold when on.
struct SocialPill<Icon: View>: View {
    let label: String
    var on = false
    var danger = false
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                Text(label).font(SiteFont.body(12, relativeTo: .caption))
            }
            .foregroundStyle(on ? Bone.goldDim : (danger ? Bone.inkFaint(scheme) : Bone.inkSoft(scheme)))
            .padding(.horizontal, 12).frame(minHeight: 36)
            .overlay { Capsule().strokeBorder(on ? Bone.gold : Bone.line(scheme), lineWidth: 0.9) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// The pill's look on any label (a ShareLink, a Menu): hairline capsule, gold when on.
    func sitePillLook(on: Bool = false, scheme: ColorScheme) -> some View {
        self.font(SiteFont.body(12, relativeTo: .caption))
            .foregroundStyle(on ? Bone.goldDim : Bone.inkSoft(scheme))
            .padding(.horizontal, 12).frame(minHeight: 36)
            .overlay { Capsule().strokeBorder(on ? Bone.gold : Bone.line(scheme), lineWidth: 0.9) }
            .contentShape(Capsule())
    }
}

/// A short line under a form, in the site's small faint capitals; a refusal reads in oxblood.
struct SiteNote: View {
    let text: String?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let text, !text.isEmpty {
            Text(text).font(SiteFont.body(12, relativeTo: .caption)).foregroundStyle(text.hasPrefix("Not") ? (scheme == .dark ? Color(hex: 0xe08a8a) : Bone.oxblood) : Bone.inkFaint(scheme))
                .frame(maxWidth: .infinity, alignment: .leading).transition(.opacity)
        }
    }
}

/// The site's loading mark: one gold hairline that breathes.
struct SitePulse: View {
    @State private var on = false
    var body: some View {
        Rectangle().fill(Bone.gold.opacity(0.4)).frame(width: 1, height: 32)
            .opacity(on ? 1 : 0.3).frame(maxWidth: .infinity).padding(.vertical, 36)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true } }
            .accessibilityLabel("Loading")
    }
}

/// A designed empty or failed state in the site's voice, with one way forward.
struct SiteEmpty: View {
    let title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(SiteFont.display(22)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.center)
            if let detail { Text(detail).siteBody(14).multilineTextAlignment(.center) }
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(SiteGhost()).frame(maxWidth: 240) }
        }
        .padding(.vertical, 36).padding(.horizontal, 24).frame(maxWidth: .infinity)
    }
}

// MARK: - Linked text

/// A post's words with its links alive, as the site draws them: `#tags` to the tag page, `@handles` to the member, web links out.
struct LinkedText: View {
    let text: String
    var size: CGFloat = 18
    var onMember: (String) -> Void
    var onWeb: (URL) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(attributed)
            .font(SiteFont.display(size)).foregroundStyle(Bone.ink(scheme)).lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "plmember", let h = url.host { onMember(h); return .handled }
                onWeb(url); return .handled
            })
    }

    private var attributed: AttributedString {
        guard let re = try? NSRegularExpression(pattern: #"(https?://[^\s]+|#[a-z0-9]+|@[a-z0-9]{3,20})"#, options: [.caseInsensitive]) else { return AttributedString(text) }
        let ns = text as NSString
        var out = AttributedString()
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last { out += AttributedString(ns.substring(with: NSRange(location: last, length: m.range.location - last))) }
            let seg = ns.substring(with: m.range)
            var a: AttributedString
            if seg.hasPrefix("@") {
                a = AttributedString(seg); a.link = URL(string: "plmember://\(seg.dropFirst().lowercased())")
            } else if seg.hasPrefix("#") {
                a = AttributedString(seg); a.link = Site.page("tag/\(seg.dropFirst().lowercased())")
            } else {
                a = AttributedString(seg.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                a.link = URL(string: seg); a.underlineStyle = .single
            }
            a.foregroundColor = Bone.gold
            out += a
            last = m.range.location + m.range.length
        }
        if last < ns.length { out += AttributedString(ns.substring(from: last)) }
        return out
    }
}

// MARK: - Media

enum PostMedia {
    static func isVideo(_ s: String) -> Bool { s.range(of: #"\.(mp4|webm|mov)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    /// A Living Code pick: a link out to the piece, never a frame of the library on the site (his ruling S340).
    static func isLivingPiece(_ s: String) -> Bool { s.contains("/pieces/embed?id=") }
    static func livingURL(_ s: String) -> URL? { URL(string: s.replacingOccurrences(of: "?embed=1", with: "").replacingOccurrences(of: "&embed=1", with: "")) }
}

/// A post's picture, video, or living-piece link, as the site shows it.
struct PostMediaView: View {
    let media: String
    var height: CGFloat? = nil
    var onOpen: ((URL) -> Void)? = nil
    var onWeb: (URL) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if PostMedia.isLivingPiece(media), let url = PostMedia.livingURL(media) {
            Button { onWeb(url) } label: {
                Text("A living piece \u{2192}").siteLabel(11).padding(.horizontal, 16).frame(minHeight: 44)
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
            }.buttonStyle(.plain)
        } else if PostMedia.isVideo(media), let url = URL(string: media) {
            SiteVideo(url: url).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let url = URL(string: media) {
            Button { onOpen?(url) } label: {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFit().frame(maxWidth: .infinity)
                    case .failure: Bone.line(scheme).opacity(0.4).frame(height: 140).overlay { Image(systemName: "photo").foregroundStyle(Bone.inkFaint(scheme)) }
                    default: Bone.line(scheme).opacity(0.3).frame(height: 160).overlay { ProgressView() }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
            }
            .buttonStyle(.plain).disabled(onOpen == nil)
            .accessibilityLabel("Picture")
        }
    }
}

struct SiteVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        Group { if let player { VideoPlayer(player: player) } else { Color.black.opacity(0.1) } }
            .onAppear { if player == nil { player = AVPlayer(url: url) } }
            .onDisappear { player?.pause() }
    }
}

// MARK: - Masonry and the lightbox

/// Columns filled in turn, each picture at its own shape (the site's `column-count` masonry).
struct Masonry<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var columns = 2
    var spacing: CGFloat = 4
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { c in
                LazyVStack(spacing: spacing) {
                    ForEach(Array(items.enumerated()).filter { $0.offset % columns == c }, id: \.element.id) { content($0.element) }
                }
            }
        }
    }
}

struct LightboxItem: Identifiable {
    let src: URL
    let caption: String
    var id: String { src.absoluteString }
}

/// A picture on the obsidian ground at full size: pinch to zoom, tap to close (the site's lightbox).
struct Lightbox: View {
    let item: LightboxItem
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color(hex: 0x0e0c08).ignoresSafeArea()
            VStack(spacing: 16) {
                AsyncImage(url: item.src) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
                    default: ProgressView().tint(.white)
                    }
                }
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation(.snappy) { scale = 1 } })
                .padding(.horizontal, 12)
                if !item.caption.isEmpty {
                    Text(item.caption).font(SiteFont.body(12, relativeTo: .caption)).textCase(.uppercase).tracking(3).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.6))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44) }
                .glassControl(in: Circle()).padding(16).accessibilityLabel("Close")
        }
        .onTapGesture { dismiss() }
        .preferredColorScheme(.dark)
    }
}

// MARK: - The archive's own list, for choosing visuals and works

/// One piece of the archive as the member pickers show it.
struct ArchivePick: Identifiable, Hashable {
    let cr: String
    let thumb: String
    let title: String
    var id: String { cr }
}

/// The public archive manifest (the same file the site's pickers read), kept for the session.
@MainActor @Observable final class ArchiveManifest {
    static let shared = ArchiveManifest()
    var pieces: [ArchivePick] = []
    var loading = false
    var failed = false

    private struct File: Decodable {
        struct P: Decodable { let cr: String?; let thumb: String?; let url: String?; let title: String?; let shareable: Bool? }
        let pieces: [P]
    }

    func load() async {
        guard pieces.isEmpty, !loading, let url = URL(string: "https://assets.psychedluxuries.com/manifest.json") else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let file = try JSONDecoder().decode(File.self, from: data)
            pieces = file.pieces.compactMap { p in
                guard p.shareable != false, let cr = p.cr, !cr.isEmpty, let thumb = p.thumb ?? p.url else { return nil }
                let t = (p.title ?? "").trimmingCharacters(in: .whitespaces)
                return ArchivePick(cr: cr, thumb: thumb, title: t.isEmpty ? cr : t)
            }
            failed = false
        } catch { failed = pieces.isEmpty }
    }

    func search(_ q: String) -> [ArchivePick] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        return s.isEmpty ? pieces : pieces.filter { $0.cr.lowercased().contains(s) || $0.title.lowercased().contains(s) }
    }
}
