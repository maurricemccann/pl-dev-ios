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
struct SectionTile: View {
    let entry: SectionEntry
    @AppStorage("pldev.tileStrength") private var strength = 0.5

    init(entry: SectionEntry) { self.entry = entry }

    private var ready: Bool { entry.readiness.isReady }

    private var spoken: String {
        var parts = [entry.manifest.title]
        if let badge = entry.badge, badge > 0 { parts.append("\(badge) new") }
        if let note = entry.readiness.plNote { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: PLSpace.pad) {
            HStack(alignment: .top) {
                Image(systemName: entry.manifest.symbol)
                    .font(.title2.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ready ? PLTone.accent : PLTone.quiet)
                    .frame(width: 48, height: 48)
                    .background(PLTone.well, in: Circle())
                Spacer(minLength: PLSpace.gap)
                if let badge = entry.badge, badge > 0 {
                    CountBadge(count: badge)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: PLSpace.tight) {
                Text(entry.manifest.title)
                    .plFont(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let note = entry.readiness.plNote {
                    Label(note, systemImage: "key")
                        .plFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(PLSpace.margin)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .background {
            shape.fill(PLTone.surface)
            shape.fill(PLTone.tileWash.opacity(ready ? 0.04 + 0.20 * strength : 0))
        }
        .overlay {
            shape.strokeBorder(PLTone.hairline.opacity(0.6), lineWidth: 0.5)
        }
        .contentShape(shape)
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
