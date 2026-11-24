import ImageIO
import SwiftUI

/// What sits behind every screen: the system's grouped background, and the theme pack's tile over it when one is loaded.
/// Content layer: never glass.
struct Backdrop: View {
    @AppStorage("pldev.tileStrength") private var strength = 0.5
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init() {}

    var body: some View {
        ZStack {
            HouseGround()   // was PLTone.canvas, Apple's grouped grey: the white that showed behind every push in Light Appearance (his note 11-14)
            if let tile = ThemePack.shared.tile, !reduceTransparency {
                Image(uiImage: tile)
                    .resizable(resizingMode: .tile)
                    .opacity(0.04 + 0.16 * strength)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// An icon with a line of words: the icon carries the colour, the words carry the meaning.
struct NoteLine: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .plFont(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
    }
}

/// A label on the left, its value on the right, read by VoiceOver as one thing.
struct ValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PLSpace.gap) {
            Text(label)
                .plFont(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: PLSpace.gap)
            Text(value)
                .plFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Set or Not set, as a mark and a word. The value of a key is never shown anywhere.
struct KeyRow: View {
    let name: String
    let isSet: Bool

    var body: some View {
        HStack(spacing: PLSpace.gap) {
            Text(name)
                .plFont(.body)
            Spacer(minLength: PLSpace.gap)
            Image(systemName: isSet ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isSet ? PLTone.good : PLTone.quiet)
                .accessibilityHidden(true)
            Text(isSet ? "Set" : "Not set")
                .plFont(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(isSet ? "set" : "not set")")
    }
}

/// A count on a tile or a chip.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : String(count))
            .plFont(.caption, emphasized: true)
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(PLTone.bad, in: Capsule())
            .contentTransition(.numericText())
            .accessibilityLabel("\(count) new")
    }
}

/// The pressed state every tappable card uses: it sinks a little under the finger and springs back.
struct PressableStyle: ButtonStyle {
    let reduce: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(PLMotion.spring(reduce: reduce), value: configuration.isPressed)
    }
}

/// One app on the Home grid, drawn the way iOS draws a tinted Home Screen: a glass squircle, a frosted white symbol,
/// the name underneath in white, the red badge on the icon's corner. A section that cannot run yet is dimmed with a key.
struct SectionTile: View {
    let entry: SectionEntry

    init(entry: SectionEntry) { self.entry = entry }

    private var ready: Bool { entry.readiness.isReady }

    private var spoken: String {
        var parts = [entry.manifest.title]
        if let badge = entry.badge, badge > 0 { parts.append("\(badge) new") }
        if let note = entry.readiness.plNote { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    @AppStorage("pldev.styleTile") private var tileShape = "squircle"   // the theme's tile: squircle, circle or square (S353·7b1e)
    @AppStorage("pldev.styleLook") private var look = "glass"   // and what it draws over the glass: keys, rings, frames
    @AppStorage("pldev.styleIcons") private var iconSet = "pl"

    /// One app on Home: the theme's tile, its glyph, the name under it in the theme's ink.
    var body: some View {
        VStack(spacing: 6) {
            Group {
                if iconSet == "pl", let mine = PLIcon.forSection[entry.manifest.id] { PLIcon.image(mine).resizable().scaledToFit().frame(width: 34, height: 34) }
                else { Image(systemName: entry.manifest.symbol).font(Font.pl(size: 28, weight: .medium)).symbolRenderingMode(.hierarchical) }
            }
            .modifier(PLTile(shape: PLTile.shape(tileShape), look: look))
            .overlay(alignment: .bottomTrailing) {
                if !ready { Image(systemName: "key.fill").font(Font.pl(.caption).bold()).foregroundStyle(.primary).padding(4) }
            }
            .opacity(ready ? 1 : 0.55)
            .overlay(alignment: .topTrailing) {
                if let badge = entry.badge, badge > 0 {
                    CountBadge(count: badge)
                        .offset(x: 8, y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(entry.manifest.title)
                .plFont(.caption)
                .foregroundStyle(Color.primary.opacity(ready ? 1 : 0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
    }
}

/// A 64 point tile: the tile glass from Settings, the theme's look over it, the glyph on top.
struct PLTile: ViewModifier {
    let shape: AnyShape
    let look: String
    @State private var kit = HouseKit.shared
    @Environment(\.colorScheme) private var scheme

    static func shape(_ name: String) -> AnyShape {
        switch name {
        case "circle": AnyShape(Circle())
        case "square": AnyShape(RoundedRectangle(cornerRadius: 12 * PLStyle.radius, style: .continuous))
        default: AnyShape(RoundedRectangle(cornerRadius: 15 * PLStyle.radius, style: .continuous))
        }
    }

    func body(content: Content) -> some View {
        let p = kit.palette
        content
            .foregroundStyle(TileLook.glyph(look, key: p.keyColor, scheme: scheme))
            .frame(width: 64, height: 64)
            .background { if look != "glass" && look != "bare" { TileLook(look: look, shape: shape, key: p.keyColor, accent: p.accentColor) } }
            .modifier(PLSurface(part: .tile, tint: nil, interactive: false, shape: shape))
    }
}

/// Home's wallpaper: his curve tile (the Design Kit's psyground stencil, read from the gallery's /kit, so none of his art
/// ships in this public repo) in his reference's colours, lines over a deep ground. Before the tile arrives, the ground alone.
struct Wallpaper: View {
    /// The chosen house palette's ground and line (his 11-13 Home Screen reference is the default palette).
    @MainActor static var ground: Color { HouseKit.shared.palette.groundColor }
    @MainActor static var line: Color { HouseKit.shared.palette.keyColor }
    /// The psyground stencil (his curve tile, alpha only, 300 pt a repeat), loaded once and shared with every screen's ground.
    @MainActor static var stencil: UIImage?
    let model: AppModel
    @State private var ready = Wallpaper.stencil != nil
    @AppStorage("pldev.styleRepeat") private var repeatSize = 300.0   // the theme's curve scale (S353·7b1e)

    init(model: AppModel) { self.model = model }

    var body: some View {
        ThemeGround(quiet: false)
            .id(ready)
            .task(id: repeatSize) { await Self.load(model: model); ready = Self.stencil != nil }
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("psyground.png")
    }

    /// The stencil from the Design Kit's glass.css on the gallery; cached, so later launches draw it at once and offline.
    static func load(model: AppModel) async {
        if let s = stencil, abs(s.size.width - PLStyle.repeatSize) < 1 { return }   // a theme with another curve scale re-sizes the cached tile
        if let url = cacheURL, let data = try? Data(contentsOf: url), let img = UIImage(data: data) { stencil = sized(img); return }
        guard let http = model.http,
              let css = try? await http.send(RequestPlan(origin: "gallery", path: "kit/glass/glass.css")),
              let text = String(data: css, encoding: .utf8),
              let start = text.range(of: "--psyground-tile: url(\"data:image/webp;base64,"),
              let end = text[start.upperBound...].firstIndex(of: "\""),
              let data = Data(base64Encoded: String(text[start.upperBound..<end])),
              let img = UIImage(data: data) else { return }
        if let url = cacheURL, let png = img.pngData() { try? png.write(to: url) }
        stencil = sized(img)
    }

    private static func sized(_ img: UIImage) -> UIImage? {
        guard let cg = img.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: CGFloat(cg.width) / PLStyle.repeatSize, orientation: .up).withRenderingMode(.alwaysTemplate)
    }
}

/// A designed empty or error state: a symbol, one line, one sentence, and at most one way forward.
struct EmptyNote: View {
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).plFont(.title3)
            } icon: {
                Image(systemName: symbol)
            }
        } description: {
            Text(detail).plFont(.callout)
        } actions: {
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .plFont(.callout, emphasized: true)
                        .frame(minHeight: PLMetric.touch)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// A placeholder row drawn while the first answer is on its way, in place of a spinner.
struct SkeletonRow: View {
    var body: some View {
        HStack {
            Text("Placeholder name")
                .plFont(.body)
            Spacer()
            Text("Waiting")
                .plFont(.callout)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading")
    }
}

extension View {
    /// The title of a pushed screen or a sheet: inline, in the title face, and announced as a header.
    func plScreenTitle(_ text: String) -> some View {
        navigationTitle(text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(text)
                        .plTitle(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}


/// A theme's wallpaper from his archive (S353·7b1e, his picks 11-24): fetched once from the archive's public bucket, shrunk to screen
/// size, kept on the phone. Line art is drawn as a mask in the theme's key colour; a "color" piece is shown as he made it.
struct ThemeWall: View {
    let spec: String, key: Color, strength: Double
    @State private var image: UIImage?

    var body: some View {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        let mode = parts.first ?? "mask"
        Group {
            if let image {
                if mode == "color" {
                    Image(uiImage: image).resizable().scaledToFill().opacity(min(1, 0.25 + strength))
                } else {
                    Rectangle().fill(key).mask {
                        if mode == "invert" { Image(uiImage: image).resizable().scaledToFill().colorInvert().luminanceToAlpha() }
                        else { Image(uiImage: image).resizable().scaledToFill().luminanceToAlpha() }
                    }
                    .opacity(min(1, 0.15 + strength * 1.2))
                }
            }
        }
        .ignoresSafeArea()
        .task(id: spec) { image = await Self.load(parts.count == 2 ? parts[1] : "") }
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    /// Only https addresses on the archive's own bucket are fetched (the spec comes from code, never from a page).
    @MainActor static func load(_ address: String) async -> UIImage? {
        if let hit = cache[address] { return hit }
        guard let url = URL(string: address), url.scheme == "https", url.host?.hasSuffix(".r2.dev") == true || url.host == "assets.psychedluxuries.com" else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("walls", isDirectory: true)
        let file = dir.appendingPathComponent(url.lastPathComponent + ".jpg")
        if let d = try? Data(contentsOf: file), let img = UIImage(data: d) { cache[address] = img; return img }
        guard let (data, resp) = try? await URLSession.shared.data(from: url), (resp as? HTTPURLResponse)?.statusCode == 200,
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: 1800,
                                                                     kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let jpg = img.jpegData(compressionQuality: 0.85) { try? jpg.write(to: file) }
        cache[address] = img
        return img
    }
}
