import SwiftUI

/// What sits behind every screen: the system's grouped background, and the theme pack's tile over it when one is loaded.
/// Content layer: never glass.
struct Backdrop: View {
    @AppStorage("pldev.tileStrength") private var strength = 0.5
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init() {}

    var body: some View {
        ZStack {
            PLTone.canvas
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

    @AppStorage("pldev.glassBlur") private var glass = true

    /// The Home Screen's tinted look (his reference, 11-13): every icon the same glass, washed in the wallpaper's colour,
    /// a frosted white glyph on it. One colour for every app; the symbol tells them apart.
    var body: some View {
        let icon = RoundedRectangle(cornerRadius: 15, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                Image(systemName: entry.manifest.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.93, blue: 0.86)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                if !ready {
                    Image(systemName: "key.fill").font(.caption.bold()).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
                }
            }
            .frame(width: 64, height: 64)
            .modifier(TileGlass(shape: icon, on: glass))
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
                .foregroundStyle(.white.opacity(ready ? 1 : 0.7))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)   // white on a busy wallpaper, as Springboard draws it
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
    }
}

/// The icon plate: Liquid Glass washed in the wallpaper's line colour; a solid plate when glass is off in Settings.
private struct TileGlass<S: Shape>: ViewModifier {
    let shape: S
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.glassEffect(.regular.tint(Wallpaper.line.opacity(0.45)), in: shape)
        } else {
            content.background(Wallpaper.line.gradient, in: shape)
        }
    }
}

/// Home's wallpaper: his curve tile (the Design Kit's psyground stencil, read from the gallery's /kit, so none of his art
/// ships in this public repo) in his reference's colours, lines over a deep ground. Before the tile arrives, the ground alone.
struct Wallpaper: View {
    static let ground = Color(red: 0.35, green: 0.12, blue: 0.055)   // sampled from his 11-13 reference
    static let line = Color(red: 0.72, green: 0.33, blue: 0.21)
    let model: AppModel
    @State private var tile: UIImage?
    @AppStorage("pldev.tileStrength") private var strength = 0.5   // Settings: how strongly the curves show; 0.5 = his reference

    init(model: AppModel) { self.model = model }

    var body: some View {
        ZStack {
            Self.ground
            if let tile {
                Image(uiImage: tile).resizable(resizingMode: .tile).opacity(min(1, 0.15 + strength * 1.7))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task { tile = await Self.load(model: model) }
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("psyground.png")
    }

    /// The stencil, painted in the line colour at 300 pt a repeat. Cached, so later launches draw it at once and offline.
    private static func load(model: AppModel) async -> UIImage? {
        if let url = cacheURL, let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return paint(img) }
        guard let http = model.http,
              let css = try? await http.send(RequestPlan(origin: "gallery", path: "kit/glass/glass.css")),
              let text = String(data: css, encoding: .utf8),
              let start = text.range(of: "--psyground-tile: url(\"data:image/webp;base64,"),
              let end = text[start.upperBound...].firstIndex(of: "\""),
              let data = Data(base64Encoded: String(text[start.upperBound..<end])),
              let img = UIImage(data: data) else { return nil }
        if let url = cacheURL, let png = img.pngData() { try? png.write(to: url) }
        return paint(img)
    }

    private static func paint(_ stencil: UIImage) -> UIImage? {
        // the tint applies when drawn, not to .cgImage, so draw it once into a bitmap
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        guard let cg = UIGraphicsImageRenderer(size: stencil.size, format: format).image(actions: { _ in
            stencil.withTintColor(UIColor(line)).draw(at: .zero) }).cgImage else { return nil }
        return UIImage(cgImage: cg, scale: CGFloat(cg.width) / 300, orientation: .up)
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
