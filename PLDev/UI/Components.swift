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

/// One section on the home grid: its symbol, title, badge, and a quiet line when the config does not let it run yet.
/// One app on the Home grid, drawn the way iOS draws an app: a squircle icon in the app's own colour, a white symbol,
/// the name underneath, the red badge on the icon's corner. A section that cannot run yet is dimmed and says why.
struct SectionTile: View {
    let entry: SectionEntry

    init(entry: SectionEntry) { self.entry = entry }

    private var ready: Bool { entry.readiness.isReady }

    /// Each app's colour, from the system palette so it follows light, dark and increased contrast.
    static func tint(_ id: String) -> Color {
        switch id {
        case "house": return .indigo
        case "capture": return .blue
        case "curate": return .pink
        case "library": return .purple
        case "composer": return .teal
        case "town": return .green
        case "pick": return .yellow
        case "paint": return .red
        case "status": return .gray
        default: return .accentColor
        }
    }

    private var spoken: String {
        var parts = [entry.manifest.title]
        if let badge = entry.badge, badge > 0 { parts.append("\(badge) new") }
        if let note = entry.readiness.plNote { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        let tint = Self.tint(entry.id)
        let icon = RoundedRectangle(cornerRadius: 15, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                icon.fill(tint.gradient)
                Image(systemName: entry.manifest.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                if !ready {
                    icon.fill(.black.opacity(0.45))
                    Image(systemName: "key.fill").font(.caption.bold()).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
                }
            }
            .frame(width: 64, height: 64)
            .overlay(icon.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .overlay(alignment: .topTrailing) {
                if let badge = entry.badge, badge > 0 {
                    CountBadge(count: badge)
                        .offset(x: 8, y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(entry.manifest.title)
                .plFont(.caption)
                .foregroundStyle(ready ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
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
